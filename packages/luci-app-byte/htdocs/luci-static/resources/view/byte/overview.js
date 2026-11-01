'use strict';
'require view';
'require rpc';
'require poll';
'require ui';

var callStatus = rpc.declare({ object: 'byte', method: 'status' });
var callSetup  = rpc.declare({ object: 'byte', method: 'setup' });
var callAction = rpc.declare({ object: 'byte', method: 'action', params: [ 'name' ] });
var callLog    = rpc.declare({ object: 'byte', method: 'log', params: [ 'lines' ] });

var CSS_URL = L.resource('byte/byte.css');

function badge(text, tone) {
	return E('span', { 'class': 'byte-badge byte-badge--' + tone }, [ text ]);
}

function kv(pairs) {
	var dl = E('dl', { 'class': 'byte-kv' });
	pairs.forEach(function(p) {
		if (p[1] == null || p[1] === '')
			return;
		dl.appendChild(E('dt', {}, [ p[0] ]));
		dl.appendChild(E('dd', {}, [ p[2] || p[1] ]));
	});
	return dl;
}

function card(title, hint, body, wide) {
	return E('section', { 'class': 'byte-card' + (wide ? ' byte-card--wide' : '') }, [
		E('div', { 'class': 'byte-card__head' }, [
			E('h3', {}, [ title ]),
			hint ? E('span', { 'class': 'byte-hint' }, [ hint ]) : ''
		])
	].concat(body));
}

function fmtUptime(sec) {
	sec = +sec || 0;
	var d = Math.floor(sec / 86400),
	    h = Math.floor(sec % 86400 / 3600),
	    m = Math.floor(sec % 3600 / 60);
	if (d > 0)
		return '%dd %dh %dm'.format(d, h, m);
	if (h > 0)
		return '%dh %dm'.format(h, m);
	return '%dm'.format(m);
}

function fmtMem(used, total) {
	if (!total)
		return '-';
	return '%d%% (%s of %s MB)'.format(Math.round(used / total * 100), used, total);
}

function aghTone(s) {
	if (!s.installed)
		return [ 'Not installed', 'idle' ];
	if (s.running)
		return [ 'Running', 'ok' ];
	return [ 'Installed, stopped', 'warn' ];
}

function webUrl(s) {
	if (!s.agh || !s.agh.web)
		return null;
	/* AdGuard reports the listen address as "0.0.0.0:3000" / ":3000" / "[::]:3000". */
	var m = /:(\d+)$/.exec(s.agh.web);
	var port = m ? m[1] : '3000';
	return 'http://' + window.location.hostname + ':' + port;
}

return view.extend({
	load: function() {
		return callStatus();
	},

	handleSetup: function(ev) {
		var btn = ev.currentTarget;
		var self = this;

		return ui.showModal(_('Install and wire AdGuard Home'), [
			E('p', {}, [ _('This installs AdGuard Home (and its LuCI app if missing) from this firmware\'s own opkg repository, then wires it to PassWall2 without DNS or port conflicts:') ]),
			E('ul', { 'style': 'margin:0;padding-left:18px;font-size:12.5px;line-height:1.6' }, [
				E('li', {}, [ _('dnsmasq moves to port 54, AdGuard Home takes port 53') ]),
				E('li', {}, [ _('AdGuard upstream becomes PassWall2 DNS on 127.0.0.1:15353') ]),
				E('li', {}, [ _('.lan / .local / .home.arpa keep resolving through dnsmasq') ]),
				E('li', {}, [ _('SafeSearch/parental filtering is turned off') ])
			]),
			E('p', { 'class': 'byte-note' }, [ _('Existing configs are backed up before they are touched. Nothing is proxied for you: PassWall2 nodes are still yours to add.') ])
		], [
			[ _('Cancel'), ui.hideModal ],
			[ _('Install and wire'), function() {
				ui.hideModal();
				ui.showModal(_('Working'), [
					E('p', { 'class': 'byte-note' }, [
						E('span', { 'class': 'byte-spin' }),
						_('Installing packages and rewriting DNS configuration. This can take a minute on a slow feed.')
					])
				]);
				return callSetup().then(function(res) {
					ui.hideModal();
					ui.showModal(res.ok ? _('AdGuard Home is wired up') : _('Setup reported problems'), [
						E('pre', { 'class': 'byte-log' }, [ res.message || '' ])
					], [ [ _('Close'), ui.hideModal ] ]);
					return self.refresh();
				}).catch(function(err) {
					ui.hideModal();
					ui.addNotification(null, E('p', {}, [ _('Setup failed: ') + err ]), 'danger');
				});
			} ]
		]);
	},

	handleAction: function(name, ev) {
		var self = this;
		if (ev && ev.currentTarget)
			ev.currentTarget.disabled = true;
		return callAction(name).then(function(res) {
			if (!res.ok)
				ui.addNotification(null, E('p', {}, [ (res.message || _('Action failed')).trim() ]), 'warning');
			return self.refresh();
		}).catch(function(err) {
			ui.addNotification(null, E('p', {}, [ String(err) ]), 'danger');
		});
	},

	handleLog: function() {
		return callLog(120).then(function(res) {
			ui.showModal(_('Last AdGuard Home setup run'), [
				E('pre', { 'class': 'byte-log' }, [ res.log || _('No setup has run yet.') ])
			], [ [ _('Close'), ui.hideModal ] ]);
		});
	},

	/* Build the page once from a status snapshot, then let poll() patch the
	   values in place. Re-rendering the whole view every few seconds would
	   drop focus and scroll position. */
	render: function(status) {
		var self = this;

		if (!document.querySelector('link[href="' + CSS_URL + '"]'))
			document.head.appendChild(E('link', { rel: 'stylesheet', href: CSS_URL }));

		this.s = status;
		this.refs = {};

		var tone = aghTone(status);
		this.refs.aghBadge = badge(tone[0], tone[1]);

		var aghBody = [
			E('div', { 'class': 'byte-actions' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-apply',
					click: ui.createHandlerFn(this, 'handleSetup')
				}, [ status.agh.installed ? _('Re-run setup') : _('Install and wire') ]),
				E('button', {
					'class': 'btn cbi-button',
					click: ui.createHandlerFn(this, 'handleAction', status.agh.running ? 'stop' : 'start')
				}, [ status.agh.running ? _('Stop') : _('Start') ]),
				E('button', {
					'class': 'btn cbi-button',
					click: ui.createHandlerFn(this, 'handleAction', 'restart')
				}, [ _('Restart') ]),
				E('button', {
					'class': 'btn cbi-button',
					click: ui.createHandlerFn(this, 'handleAction', status.agh.enabled ? 'autostart_off' : 'autostart_on')
				}, [ status.agh.enabled ? _('Disable autostart') : _('Enable autostart') ]),
				webUrl(status) ? E('a', {
					'class': 'btn cbi-button cbi-button-action',
					'href': webUrl(status), 'target': '_blank', 'rel': 'noopener'
				}, [ _('Open AdGuard Home') ]) : '',
				status.log_available ? E('button', {
					'class': 'btn cbi-button',
					click: ui.createHandlerFn(this, 'handleLog')
				}, [ _('Setup log') ]) : ''
			]),
			kv([
				[ _('Version'), status.agh.version || '-' ],
				[ _('Web interface'), status.agh.web || '-' ],
				[ _('DNS port'), status.agh.dns_port || '-' ],
				[ _('Autostart'), status.agh.enabled ? _('enabled') : _('disabled') ]
			]),
			E('p', { 'class': 'byte-note' }, [ status.agh.installed
				? _('AdGuard Home is served from this firmware\'s repository. Filtering lists, clients and query log live in AdGuard\'s own web UI, linked above.')
				: _('AdGuard Home is not installed. The installer pulls it from this firmware\'s repository, moves dnsmasq to port 54 and keeps PassWall2 as the upstream resolver.') ])
		];

		var chainBody = [
			E('div', { 'class': 'byte-chain' }, [
				E('div', { 'class': 'byte-chain__step' }, [
					E('b', {}, [ _('LAN clients') ]),
					E('span', {}, [ _('router port 53') ])
				]),
				E('div', { 'class': 'byte-chain__arrow' }, [ '\u2193' ]),
				E('div', { 'class': 'byte-chain__step' }, [
					E('b', {}, [ _('AdGuard Home') ]),
					E('span', { 'class': 'byte-mono' }, [ ':' + (status.agh.dns_port || '53') + ' ' + (status.agh.running ? _('(running)') : _('(stopped)')) ])
				]),
				E('div', { 'class': 'byte-chain__arrow' }, [ '\u2193' ]),
				E('div', { 'class': 'byte-chain__step' }, [
					E('b', {}, [ _('PassWall2 DNS') ]),
					E('span', { 'class': 'byte-mono' }, [ '127.0.0.1:15353' ])
				]),
				E('div', { 'class': 'byte-chain__step' }, [
					E('b', {}, [ _('dnsmasq') ]),
					E('span', { 'class': 'byte-mono' }, [ ':' + status.dns.dnsmasq_port + ' (' + _('local names') + ')' ])
				])
			]),
			kv([
				[ _('PassWall2 DNS redirect'), status.dns.passwall_redirect === '0' ? _('off (correct)') : (status.dns.passwall_redirect || '-') ],
				[ _('PassWall2 remote DNS'), status.dns.passwall_remote_dns || '-' ],
				[ _('Packet steering'), status.dns.steering === '1' ? _('on') : _('off') ]
			])
		];

		var sysBody = [
			kv([
				[ _('Firmware'), status.system.version || status.system.release || '-' ],
				[ _('Model'), status.system.model || '-' ],
				[ _('Kernel'), status.system.kernel || '-' ],
				[ _('Uptime'), fmtUptime(status.system.uptime) ],
				[ _('Load'), status.system.load || '-' ],
				[ _('Memory'), fmtMem(status.system.mem_used, status.system.mem_total) ],
				[ _('WAN'), status.system.wan_up ? status.system.wan_ip : _('down') ],
				[ _('opkg feed'), status.system.repo_feeds > 0 ? _('BYTE repository configured') : _('missing') ]
			])
		];

		var links = [
			[ 'admin/status/overview', _('Dashboard') ],
			[ 'admin/tools/netstat', _('Netstat') ],
			[ 'admin/modem/qmodem/modem_info', _('Modem') ],
			[ 'admin/network/firewall', _('Firewall') ]
		];

		poll.add(function() { return self.refresh(); }, 10);

		return E('div', { 'class': 'byte-page' }, [
			E('header', { 'class': 'byte-hero' }, [
				E('div', {}, [
					E('h2', {}, [ 'BYTE' ]),
					E('p', { 'class': 'byte-sub' }, [
						_('Firmware control panel for %s').format(status.system.model || 'AW1000'),
						' \u00b7 ', E('code', {}, [ status.system.kernel || '' ])
					])
				]),
				E('div', { 'class': 'byte-actions' }, [
					this.refs.aghBadge
				])
			]),

			E('div', { 'class': 'byte-grid' }, [
				card(_('AdGuard Home'), status.agh.installed ? (status.agh.version || '') : _('not installed'), aghBody, true),
				card(_('DNS chain'), _('who answers what'), chainBody),
				card(_('System'), '', sysBody),
				card(_('Pages'), _('shipped with this firmware'), [
					E('div', { 'class': 'byte-links' }, links.map(function(l) {
						return E('a', { 'href': L.url(l[0]) }, [
							E('span', {}, [ l[1] ]),
							E('span', { 'class': 'byte-arrow' }, [ '\u2192' ])
						]);
					}))
				])
			]),

			E('footer', { 'class': 'byte-footer' }, [
				E('span', {}, [ _('BYTE by ACE') ]),
				E('span', {}, [ status.system.release || '' ]),
				E('span', {}, [ status.system.model || '' ]),
				E('span', {}, [ status.system.kernel || '' ])
			])
		]);
	},

	refresh: function() {
		var self = this;
		return callStatus().then(function(s) {
			self.s = s;
			var tone = aghTone(s);
			var b = self.refs.aghBadge;
			if (b) {
				b.className = 'byte-badge byte-badge--' + tone[1];
				b.textContent = tone[0];
			}
			return s;
		});
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
