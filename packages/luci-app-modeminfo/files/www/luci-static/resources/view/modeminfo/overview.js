'use strict';
'require view';
'require rpc';
'require poll';
'require ui';

// Modem page for the BYTE build.
//
// Every number on this page comes from the shared status cache that
// /usr/sbin/byte-status-cache keeps in /tmp/aw1000-status: `live` (serving
// cell, carriers, CSQ, registration, temperature), `static` (identity, SIM,
// PDP context) and `history` (one line per poll: mode + RSRP/SINR for LTE and
// NR). The page therefore never opens the AT port, never races the dialer and
// costs the modem nothing, no matter how many browser tabs are open.
//
// /usr/bin/modeminfo turns those files into "Key: value" lines, the rpcd
// plugin keys them into JSON, and this view only draws them.

var callStatus  = rpc.declare({ object: 'modeminfo', method: 'status' });
var callPorts   = rpc.declare({ object: 'modeminfo', method: 'ports' });
var callHistory = rpc.declare({ object: 'modeminfo', method: 'history' });
var callSample  = rpc.declare({ object: 'modeminfo', method: 'sample' });
var callSetPort = rpc.declare({ object: 'modeminfo', method: 'set_port', params: [ 'port' ] });
var callSetInt  = rpc.declare({ object: 'modeminfo', method: 'set_interval', params: [ 'seconds' ] });

var CSS_URL = L.resource('modeminfo/modeminfo.css');

/* Quality thresholds, in dB/dBm: good, fair, everything below is poor. */
var QUALITY = {
	rsrp: [ -90, -105 ],
	rsrq: [ -10, -15 ],
	sinr: [ 13, 0 ],
	rssi: [ -65, -80 ]
};

/* Full-scale ends for the bars, so a value maps to a sane 0-100%. */
var RANGE = {
	rsrp: [ -120, -60 ],
	rsrq: [ -20, -3 ],
	sinr: [ -10, 30 ],
	rssi: [ -100, -40 ]
};

function num(v) {
	var n = parseFloat(v);
	return isNaN(n) ? null : n;
}

function tone(kind, v) {
	var q = QUALITY[kind], n = num(v);
	if (!q || n === null) return 'idle';
	if (n >= q[0]) return 'ok';
	if (n >= q[1]) return 'warn';
	return 'err';
}

function pct(kind, v) {
	var r = RANGE[kind], n = num(v);
	if (!r || n === null) return 0;
	return Math.max(0, Math.min(100, Math.round((n - r[0]) / (r[1] - r[0]) * 100)));
}

function bar(kind, v) {
	return E('span', { 'class': 'mi-bar mi-bar--' + tone(kind, v) }, [
		E('span', { 'class': 'mi-bar__fill', 'style': 'width:' + pct(kind, v) + '%' })
	]);
}

/* The collector already attaches units ("-89 dBm"), so only append when the
   reading does not carry one - otherwise the page said "dBm dBm". */
function metric(label, kind, value) {
	var missing = (value == null || value === '' || value === '-');
	var shown = missing ? '-' : String(value).trim();

	return E('div', { 'class': 'mi-metric' }, [
		E('div', { 'class': 'mi-metric__label' }, [ label ]),
		E('div', { 'class': 'mi-metric__value mi-tone--' + tone(kind, value) }, [ shown ]),
		kind ? bar(kind, value) : ''
	]);
}

function card(title, hint, body, extra) {
	return E('section', { 'class': 'mi-card' + (extra ? ' ' + extra : '') }, [
		E('div', { 'class': 'mi-card__head' }, [
			E('h3', {}, [ title ]),
			hint ? E('span', { 'class': 'mi-hint' }, [ hint ]) : ''
		])
	].concat(body));
}

function kv(pairs) {
	var dl = E('dl', { 'class': 'mi-kv' });

	pairs.forEach(function(p) {
		if (p[1] == null || p[1] === '' || p[1] === '-') return;
		dl.appendChild(E('dt', {}, [ p[0] ]));
		dl.appendChild(E('dd', {}, [ String(p[1]) ]));
	});

	return dl;
}

/* "PCC: LTE|B28|20|9310|451|-89|-13|-" -> object. The role prefix comes from
   the label the collector used, the rest is the pipe-separated payload. */
function parseCarrier(line) {
	var s = String(line), cut = s.indexOf(': ');
	var role = (cut >= 0 ? s.slice(0, cut) : '?');
	var f = (cut >= 0 ? s.slice(cut + 2) : s).split('|');
	return {
		role: role,
		rat: f[0] || '-',
		band: f[1] || '-',
		bw: f[2] || '-',
		freq: f[3] || '-',
		pci: f[4] || '-',
		rsrp: f[5] || '-',
		rsrq: f[6] || '-',
		sinr: f[7] || '-'
	};
}

/* --- history -----------------------------------------------------------------
   /tmp/aw1000-status/history is "<epoch> <mode> <lte rsrp> <nr rsrp> <lte sinr>
   <nr sinr>" with "-" for whatever the modem did not report. The backend hands
   back the last ~30 minutes. */

function series(points, field) {
	var out = [];
	points.forEach(function(p) {
		var v = num(p[field]);
		if (v !== null) out.push({ t: p.t, v: v });
	});
	return out;
}

function sparkline(lines, unit, floor, ceil) {
	var W = 320, H = 90, PAD = 4, all = [];

	lines.forEach(function(l) { all = all.concat(l.points); });
	if (!all.length)
		return E('p', { 'class': 'mi-empty' }, [ _('no samples yet') ]);

	if (ceil == null) {
		ceil = Math.max.apply(null, all.map(function(p) { return p.v; })) + 2;
		floor = Math.min.apply(null, all.map(function(p) { return p.v; })) - 2;
	}
	if (ceil === floor) ceil = floor + 1;

	var t0 = Math.min.apply(null, all.map(function(p) { return p.t; }));
	var t1 = Math.max.apply(null, all.map(function(p) { return p.t; }));
	var span = (t1 - t0) || 1;

	function x(t) { return PAD + (t - t0) / span * (W - 2 * PAD); }
	function y(v) { return H - PAD - (v - floor) / (ceil - floor) * (H - 2 * PAD); }

	var grid = E('g', { 'class': 'mi-spark__grid' }, [
		E('line', { x1: PAD, y1: H / 2, x2: W - PAD, y2: H / 2 })
	]);

	var paths = lines.map(function(l) {
		if (!l.points.length) return '';
		var d = l.points.map(function(p, i) {
			return (i ? 'L' : 'M') + x(p.t).toFixed(1) + ' ' + y(p.v).toFixed(1);
		}).join(' ');
		return E('path', {
			'class': 'mi-spark__line',
			style: 'stroke:' + l.color,
			d: d
		});
	});

	var legend = E('div', { 'class': 'mi-legend' }, lines.map(function(l) {
		var last = l.points.length ? l.points[l.points.length - 1].v : null;
		return E('span', {}, [
			E('i', { style: 'background:' + l.color }),
			l.name + ' ' + (last === null ? '-' : last.toFixed(0) + ' ' + unit)
		]);
	}));

	return E('div', { 'class': 'mi-spark' }, [
		E('svg', {
			viewBox: '0 0 ' + W + ' ' + H,
			preserveAspectRatio: 'none',
			'class': 'mi-spark__svg'
		}, [ grid ].concat(paths)),
		legend
	]);
}

return view.extend({
	load: function() {
		return Promise.all([ callStatus(), callPorts(), callHistory() ]);
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

	render: function(data) {
		var status = data[0] || { meta: {}, modem: {}, carriers: [] };
		var ports  = data[1] || { ports: [], current: '' };
		var hist   = data[2] || { points: [] };
		var self = this;

		if (!document.querySelector('link[href="' + CSS_URL + '"]'))
			document.head.appendChild(E('link', { rel: 'stylesheet', href: CSS_URL }));

		this.s = status;
		this.points = hist.points || [];
		this.ports = ports;
		this.meta = status.meta || {};

		this.refs = {};
		this.refs.body = E('div', { 'class': 'mi-grid' });
		this.refs.foot = E('footer', { 'class': 'mi-foot' });
		this.buildBody();

		poll.add(function() { return self.refresh(); }, Math.max(2, +this.meta.interval || 5));

		/* Hero sits BELOW the cards: LuCI pins its toolbar to the top of the
		 * viewport, so a hero rendered first ends up underneath it and both
		 * the title and the controls get clipped at small heights. Same order
		 * as luci-app-byte. */
		return E('div', { 'class': 'mi-page' }, [
			this.refs.body,
			E('header', { 'class': 'mi-hero' }, [
				this.heroText(),
				E('div', { 'class': 'mi-controls' }, [
					E('label', {}, [
						E('span', {}, [ _('AT port (fallback only)') ]),
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
							return E('option', { value: n, selected: +this.meta.interval === n ? '' : null },
								[ _('%d s').format(n) ]);
						}, this))
					]),
					E('button', {
						'class': 'btn cbi-button cbi-button-action',
						click: ui.createHandlerFn(this, 'handleSample')
					}, [ _('Refresh now') ])
				])
			]),
			this.refs.foot
		]);
	},

	heroText: function() {
		var m = (this.s && this.s.modem) || {};
		var parts = [ m.operator, m.network, m.registration ].filter(function(x) {
			return x && x !== '-' && x !== 'unknown';
		});

		return E('div', { 'class': 'mi-hero__text' }, [
			E('h2', {}, [ (m.modem || _('Modem')).toString() ]),
			E('p', { 'class': 'mi-sub' }, [ parts.join(' \u00b7 ') || _('no modem data yet') ])
		]);
	},

	buildBody: function() {
		var s = this.s || { modem: {}, meta: {} };
		var m = s.modem || {};
		var carriers = (s.carriers || []).map(parseCarrier);
		var body = this.refs.body;

		body.innerHTML = '';

		body.appendChild(this.signalCard(m));
		body.appendChild(this.carrierCard(carriers));
		body.appendChild(this.trendCard());
		body.appendChild(this.cellCard(m));
		body.appendChild(this.dataCard(m));
		body.appendChild(this.modemCard(m));

		this.paintFoot();
	},

	signalCard: function(m) {
		var rows = [];

		if (num(m.lte_rsrp) !== null || num(m.lte_rsrq) !== null ||
		    num(m.lte_sinr) !== null || num(m.lte_rssi) !== null) {
			rows.push(E('div', { 'class': 'mi-row' }, [
				E('div', { 'class': 'mi-row__label' }, [ _('LTE') ]),
				E('div', { 'class': 'mi-metrics' }, [
					metric('RSRP', 'rsrp', m.lte_rsrp),
					metric('RSRQ', 'rsrq', m.lte_rsrq),
					metric('SINR', 'sinr', m.lte_sinr),
					metric('RSSI', 'rssi', m.lte_rssi)
				])
			]));
		}

		if (num(m.nr_rsrp) !== null || num(m.nr_sinr) !== null || num(m.nr_rsrq) !== null) {
			rows.push(E('div', { 'class': 'mi-row' }, [
				E('div', { 'class': 'mi-row__label' }, [ _('5G NR') ]),
				E('div', { 'class': 'mi-metrics' }, [
					metric('RSRP', 'rsrp', m.nr_rsrp),
					metric('RSRQ', 'rsrq', m.nr_rsrq),
					metric('SINR', 'sinr', m.nr_sinr)
				])
			]));
		}

		rows.push(E('p', { 'class': 'mi-note' }, [
			_('CSQ %s \u00b7 BER %s \u00b7 score %s/100')
				.format(m.csq || '-', m.ber || '-', m.signal_score || '-')
		]));

		return card(_('Signal'), m.network || '', rows, 'mi-card--wide');
	},

	carrierCard: function(carriers) {
		if (!carriers.length)
			return card(_('Carrier aggregation'), '', [
				E('p', { 'class': 'mi-empty' }, [ _('no carrier info') ])
			]);

		var head = E('tr', {}, [
			E('th', {}, [ _('Role') ]), E('th', {}, [ _('RAT') ]),
			E('th', {}, [ _('Band') ]), E('th', {}, [ _('BW') ]),
			E('th', {}, [ _('Freq') ]), E('th', {}, [ _('PCI') ]),
			E('th', {}, [ _('RSRP') ]), E('th', {}, [ _('SINR') ])
		]);

		var rows = carriers.map(function(c) {
			return E('tr', {}, [
				E('td', {}, [ c.role ]),
				E('td', {}, [ c.rat ]),
				E('td', {}, [ c.band ]),
				E('td', {}, [ c.bw === '-' ? '-' : c.bw + ' MHz' ]),
				E('td', {}, [ c.freq ]),
				E('td', {}, [ c.pci ]),
				E('td', { 'class': 'mi-tone--' + tone('rsrp', c.rsrp) }, [ c.rsrp ]),
				E('td', { 'class': 'mi-tone--' + tone('sinr', c.sinr) }, [ c.sinr ])
			]);
		});

		return card(_('Carrier aggregation'), _('%d carriers').format(carriers.length), [
			E('div', { 'class': 'mi-table-wrap' }, [
				E('table', { 'class': 'mi-table' }, [ E('thead', {}, [ head ]), E('tbody', {}, rows) ])
			])
		]);
	},

	trendCard: function() {
		var pts = this.points || [];
		var lteRsrp = series(pts, 'lte_rsrp');
		var nrRsrp  = series(pts, 'nr_rsrp');
		var lteSinr = series(pts, 'lte_sinr');
		var nrSinr  = series(pts, 'nr_sinr');

		return card(_('Trend'), _('last %d samples').format(pts.length), [
			E('div', { 'class': 'mi-trends' }, [
				sparkline([
					{ name: _('LTE'), color: '#2f7de1', points: lteRsrp },
					{ name: _('5G'), color: '#8b5cf6', points: nrRsrp }
				], 'dBm', -140, -40),
				sparkline([
					{ name: _('LTE'), color: '#2f7de1', points: lteSinr },
					{ name: _('5G'), color: '#8b5cf6', points: nrSinr }
				], 'dB', -20, 30)
			])
		], 'mi-card--wide');
	},

	cellCard: function(m) {
		return card(_('Cell'), '', [
			kv([
				[ _('MCC / MNC'), m.mcc_mnc ],
				[ _('Cell ID'), m.lte_cell_id || m.nr_cell_id ],
				[ _('Cell ID (dec)'), m.lte_cell_id_dec || m.nr_cell_id_dec ],
				[ _('PCI'), m.lte_pci || m.nr_pci ],
				[ _('TAC'), m.lte_tac || m.nr_tac ],
				[ _('EARFCN'), m.lte_earfcn ],
				[ _('NR ARFCN'), m.nr_arfcn ]
			])
		]);
	},

	dataCard: function(m) {
		return card(_('Data'), '', [
			kv([
				[ _('APN'), m.apn ],
				[ _('IPv4'), m.ipv4 ],
				[ _('IPv6'), m.ipv6 ],
				[ _('DNS'), m.dns ],
				[ _('Roaming'), m.roaming ]
			])
		]);
	},

	modemCard: function(m) {
		return card(_('Modem'), '', [
			kv([
				[ _('Model'), m.modem ],
				[ _('Manufacturer'), m.manufacturer ],
				[ _('Firmware'), m.firmware ],
				[ _('IMEI'), m.imei ],
				[ _('ICCID'), m.iccid ],
				[ _('SIM slot'), m.sim_slot ],
				[ _('Protocol'), m.protocol ],
				[ _('Temperature'), m.temperature ]
			])
		]);
	},

	paintFoot: function() {
		var meta = this.meta || {};
		var foot = this.refs.foot;

		if (!foot) return;
		foot.innerHTML = '';
		foot.appendChild(E('span', {}, [ meta.available
			? _('sampled %d s ago from /tmp/aw1000-status').format(meta.age || 0)
			: _('no sample yet — check the modem status service') ]));
		foot.appendChild(E('span', {}, [ (this.ports && this.ports.current) || '' ]));
	},

	refresh: function() {
		var self = this;
		return Promise.all([ callStatus(), callHistory() ]).then(function(r) {
			var s = r[0] || {}, h = r[1] || { points: [] };
			var changed =
				JSON.stringify(s.modem || {}) !== JSON.stringify((self.s && self.s.modem) || {}) ||
				JSON.stringify(s.carriers || []) !== JSON.stringify((self.s && self.s.carriers) || []) ||
				JSON.stringify(h.points || []) !== JSON.stringify(self.points || []);

			self.s = s;
			self.points = h.points || [];
			self.meta = s.meta || self.meta;

			if (changed) {
				self.buildBody();
				var hero = document.querySelector('.mi-hero__text');
				if (hero && self.heroText) {
					var repl = self.heroText();
					hero.parentNode.replaceChild(repl, hero);
				}
			} else {
				self.paintFoot();
			}

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
