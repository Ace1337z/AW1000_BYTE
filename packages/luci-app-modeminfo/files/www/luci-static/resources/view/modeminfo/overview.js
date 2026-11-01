'use strict';
'require view';
'require rpc';
'require poll';
'require ui';

var callStatus  = rpc.declare({ object: 'modeminfo', method: 'status' });
var callPorts   = rpc.declare({ object: 'modeminfo', method: 'ports' });
var callSetPort = rpc.declare({ object: 'modeminfo', method: 'set_port', params: [ 'port' ] });
var callSetInt  = rpc.declare({ object: 'modeminfo', method: 'set_interval', params: [ 'seconds' ] });
var callSample  = rpc.declare({ object: 'modeminfo', method: 'sample' });

var CSS_URL = L.resource('modeminfo/modeminfo.css');

/* Quality thresholds for the bars. RSRP/RSRQ/SINR in dB, RSSI in dBm. */
var QUALITY = {
	rsrp: [ -90, -105 ],   /* good >= -90, fair >= -105 */
	rsrq: [ -10, -15 ],
	sinr: [ 13, 0 ],
	rssi: [ -65, -80 ]
};

function tone(kind, v) {
	var q = QUALITY[kind], n = parseFloat(v);
	if (!q || isNaN(n))
		return 'idle';
	if (n >= q[0]) return 'ok';
	if (n >= q[1]) return 'warn';
	return 'err';
}

function bars(kind, v) {
	var q = QUALITY[kind], n = parseFloat(v);
	var pct = 0;
	if (!isNaN(n) && q)
		pct = Math.max(0, Math.min(100, Math.round((n - (q[1] - 10)) / (q[0] + 10 - (q[1] - 10)) * 100)));
	return E('span', { 'class': 'mi-bar mi-bar--' + tone(kind, v) }, [
		E('span', { 'class': 'mi-bar__fill', 'style': 'width:' + pct + '%' })
	]);
}

function metric(label, kind, value, unit) {
	var shown = (value == null || value === '' || value === '-') ? '-' : value + (unit || '');
	return E('div', { 'class': 'mi-metric' }, [
		E('div', { 'class': 'mi-metric__label' }, [ label ]),
		E('div', { 'class': 'mi-metric__value mi-tone--' + tone(kind, value) }, [ shown ]),
		kind ? bars(kind, value) : ''
	]);
}

function card(title, hint, body) {
	return E('section', { 'class': 'mi-card' }, [
		E('div', { 'class': 'mi-card__head' }, [
			E('h3', {}, [ title ]),
			hint ? E('span', { 'class': 'mi-hint' }, [ hint ]) : ''
		])
	].concat(body));
}

function kv(pairs) {
	var dl = E('dl', { 'class': 'mi-kv' });
	pairs.forEach(function(p) {
		if (p[1] == null || p[1] === '' || p[1] === '-')
			return;
		dl.appendChild(E('dt', {}, [ p[0] ]));
		dl.appendChild(E('dd', {}, [ p[1] ]));
	});
	return dl;
}

return view.extend({
	load: function() {
		return Promise.all([ callStatus(), callPorts() ]);
	},

	handleSample: function() {
		var self = this;
		return callSample().then(function(s) {
			self.s = s;
			return self.repaint();
		});
	},

	handlePort: function(ev) {
		var self = this, p = ev.currentTarget.value;
		return callSetPort(p).then(function() {
			return self.handleSample();
		});
	},

	handleInterval: function(ev) {
		var n = ev.currentTarget.value;
		return callSetInt(n).then(function() {
			ui.addNotification(null, E('p', {}, [ _('Refresh interval set to %s s').format(n) ]), 'info');
		});
	},

	/* Values arrive as strings straight from AT output; render them without
	   interpreting, so "b12345" (hex cell id) and "-" stay visible as-is. */
	render: function(data) {
		var status = data[0] || { meta: {}, modem: {}, carriers: [] };
		var ports = data[1] || { ports: [], current: '' };
		var self = this;

		if (!document.querySelector('link[href="' + CSS_URL + '"]'))
			document.head.appendChild(E('link', { rel: 'stylesheet', href: CSS_URL }));

		this.s = status;
		this.ports = ports;
		this.refs = {};

		var m = status.modem || {};
		var meta = status.meta || {};
		var carriers = status.carriers || [];

		this.refs.body = E('div', { 'class': 'mi-grid' });
		this.buildBody();

		poll.add(function() { return self.refresh(); }, Math.max(2, +meta.interval || 5));

		return E('div', { 'class': 'mi-page' }, [
			E('header', { 'class': 'mi-hero' }, [
				E('div', {}, [
					E('h2', {}, [ (m.modem || _('Modem')).toString() ]),
					E('p', { 'class': 'mi-sub' }, [
						[ m.isp, m.network, m.protocol ].filter(function(x) { return x && x !== '-'; }).join(' \u00b7 ')
						|| _('no modem data yet')
					])
				]),
				E('div', { 'class': 'mi-controls' }, [
					E('label', {}, [
						E('span', {}, [ _('AT port') ]),
						E('select', {
							'class': 'cbi-input-select',
							change: ui.createHandlerFn(this, 'handlePort')
						}, (ports.ports || []).map(function(p) {
							return E('option', { value: p, selected: p === ports.current ? '' : null }, [ p ]);
						}))
					]),
					E('label', {}, [
						E('span', {}, [ _('Refresh') ]),
						E('select', {
							'class': 'cbi-input-select',
							change: ui.createHandlerFn(this, 'handleInterval')
						}, [ 2, 3, 5, 10, 30 ].map(function(n) {
							return E('option', { value: n, selected: +meta.interval === n ? '' : null },
								[ _('%d s').format(n) ]);
						}))
					]),
					E('button', {
						'class': 'btn cbi-button cbi-button-action',
						click: ui.createHandlerFn(this, 'handleSample')
					}, [ _('Refresh now') ])
				])
			]),
			this.refs.body,
			E('footer', { 'class': 'mi-foot' }, [
				E('span', {}, [ meta.available
					? _('sampled %d s ago').format(meta.age || 0)
					: _('no sample yet — check the AT port') ]),
				E('span', {}, [ ports.current || '' ])
			])
		]);
	},

	buildBody: function() {
		var s = this.s || { modem: {}, meta: {} };
		var m = s.modem || {};
		var carriers = s.carriers || [];
		var body = this.refs.body;

		body.innerHTML = '';

		body.appendChild(card(_('Signal'), m.network || '', [
			E('div', { 'class': 'mi-metrics' }, [
				metric('RSRP', 'rsrp', m.lte_rsrp, ' dBm'),
				metric('RSRQ', 'rsrq', m.lte_rsrq, ' dB'),
				metric('SINR', 'sinr', m.lte_sinr, ' dB'),
				metric('RSSI', 'rssi', m.rssi, ' dBm')
			]),
			E('div', { 'class': 'mi-metrics' }, [
				metric('5G RSRP', 'rsrp', m.nr5g_nsa_rsrp || m.nr5g_sa_rsrp, ' dBm'),
				metric('5G RSRQ', 'rsrq', m.nr5g_nsa_rsrq || m.nr5g_sa_rsrq, ' dB'),
				metric('5G SINR', 'sinr', m.nr5g_nsa_sinr || m.nr5g_sa_sinr, ' dB'),
				metric('CSQ', null, m.csq, m.signal_strength ? ' (' + m.signal_strength + ')' : '')
			])
		]));

		body.appendChild(card(_('Cell'), carriers.length ? '' : _('no carrier info'), [
			kv([
				[ _('Cell ID'), m.lte_cell_id_dec || m.lte_cell_id || m.nr5g_sa_cell_id_dec || m.nr5g_sa_cell_id ],
				[ _('MCC / MNC'), [ m.lte_mcc, m.lte_mnc ].filter(Boolean).join(' / ') || [ m.nr5g_sa_mcc, m.nr5g_sa_mnc ].filter(Boolean).join(' / ') ],
				[ _('PCC'), (carriers[0] || '').replace(/^PCC:\s*/, '') ]
			].concat(carriers.slice(1).map(function(c) {
				var p = c.split(/:\s*/);
				return [ p[0], p[1] ];
			})))
		]));

		body.appendChild(card(_('Modem'), m.temperature || '', [
			kv([
				[ _('Model'), m.modem ],
				[ _('Firmware'), m.revision ],
				[ _('IMEI'), m.imei ],
				[ _('Protocol'), m.protocol ],
				[ _('Temperature'), m.temperature ]
			])
		]));
	},

	refresh: function() {
		var self = this;
		return callStatus().then(function(s) {
			var changed = JSON.stringify(s.modem || {}) !== JSON.stringify((self.s && self.s.modem) || {});
			self.s = s;
			if (changed)
				self.buildBody();
			var foot = document.querySelector('.mi-foot span');
			if (foot && s.meta)
				foot.textContent = s.meta.available
					? _('sampled %d s ago').format(s.meta.age || 0)
					: _('no sample yet — check the AT port');
			return s;
		});
	},

	repaint: function() {
		this.buildBody();
		return this.refresh();
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
