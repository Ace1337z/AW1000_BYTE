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

/* The installer writes ANSI colour codes; a <pre> shows them as escape
 * garbage, so strip them before display. */
function stripAnsi(s) {
	return (s || '').replace(/\x1b\[[0-9;]*m/g, '');
}

return view.extend({
	load: function() {
		return callStatus();
	},

	/* LuCI >= 24.x: showModal(title, children, ...classes). Buttons are part of
	 * the children (a .button-row), NOT a third argument - passing an array
	 * there makes classList.add() throw and the click looks dead. */
	handleSetup: function(ev) {
		var self = this;

		return ui.showModal(_('Install and wire AdGuard Home'), [
			E('p', {}, [ _('This installs AdGuard Home (and its LuCI app if missing) from this firmware\'s own opkg repository, then wires it to PassWall2 without DNS or port conflicts:') ]),
			E('ul', { 'style': 'margin:0;padding-left:18px;font-size:12.5px;line-height:1.6' }, [
				E('li', {}, [ _('dnsmasq moves to port 54, AdGuard Home takes port 53') ]),
				E('li', {}, [ _('AdGuard upstream becomes PassWall2 DNS on 127.0.0.1:15353') ]),
				E('li', {}, [ _('.lan / .local / .home.arpa keep resolving through dnsmasq') ]),
				E('li', {}, [ _('SafeSearch/parental filtering is turned off') ])
			]),
			E('p', { 'class': 'byte-note' }, [ _('Existing configs are backed up before they are touched. Nothing is proxied for you: PassWall2 nodes are still yours to add.') ]),
			E('div', { 'class': 'button-row' }, [
				E('button', {
					'class': 'btn cbi-button',
					'click': ui.hideModal
				}, [ _('Cancel') ]),
				E('button', {
					'class': 'btn cbi-button cbi-button-apply',
					'click': function() {
						ui.hideModal();
						return self.startSetup();
					}
				}, [ _('Install and wire') ])
			])
		]);
	},

	/* Terminal view: the backend starts the installer detached and this loop
	 * tails its log once a second, so long opkg downloads are visible live
	 * instead of a frozen "Working" spinner. */
	startSetup: function() {
		var self = this,
		    term = E('pre', { 'class': 'byte-log' }, [ _('Starting…') ]),
		    state = E('p', { 'class': 'byte-note' }, [ _('Requesting installer…') ]),
		    live = true;

		ui.showModal(_('AdGuard Home setup - live output'), [
			state,
			term,
			E('div', { 'class': 'button-row' }, [
				E('button', {
					'class': 'btn cbi-button',
					'click': function() { live = false; ui.hideModal(); }
				}, [ _('Close') ])
			])
		]);

		function tick() {
			if (!live)
				return;

			return callLog(400).then(function(res) {
				if (!live)
					return;

				var txt = stripAnsi(res.log);
				term.textContent = txt || _('Waiting for output…');
				term.scrollTop = term.scrollHeight;

				if (res.running) {
					state.textContent = _('Installer running - output streams above.');
					window.setTimeout(tick, 1000);
				}
				else if (res.started) {
					var ok = (res.exit === 0);
					state.textContent = ok
						? _('Finished successfully (exit 0).')
						: _('Finished with errors (exit %d) - see the tail of the log above.').format(res.exit);
					self.refresh();
				}
				else {
					state.textContent = _('No setup run found.');
				}
			}).catch(function(err) {
				if (!live)
					return;
				term.textContent += '\n' + String(err);
				window.setTimeout(tick, 1500);
			});
		}

		return callSetup().then(function(res) {
			if (!res || !res.ok) {
				state.textContent = (res && res.message) || _('Could not start the installer.');
				return;
			}
			state.textContent = _('Installer started (pid %d). Streaming output…').format(res.pid || 0);
			window.setTimeout(tick, 600);
		}).catch(function(err) {
			state.textContent = String(err);
		});
	},

	handleAction: function(name, ev) {
		var self = this;

		return callAction(name).then(function(res) {
			var msg = ((res && res.message) || '').trim();
			if (res && res.ok)
				ui.addNotification(null, E('p', {}, [ msg || _('Done.') ]), 'info');
			else
				ui.addNotification(null, E('p', {}, [ msg || _('Action failed.') ]), 'warning');
			return self.refresh();
		}).catch(function(err) {
			ui.addNotification(null, E('p', {}, [ String(err) ]), 'danger');
		});
	},

	handleLog: function() {
		return callLog(400).then(function(res) {
			ui.showModal(_('Last AdGuard Home setup run'), [
				E('pre', { 'class': 'byte-log' }, [ stripAnsi(res.log) || _('No setup has run yet.') ]),
				E('div', { 'class': 'button-row' }, [
					E('button', { 'class': 'btn cbi-button', 'click': ui.hideModal }, [ _('Close') ])
				])
			]);
		});
	},

	buildPage: function(status) {
		if (!document.querySelector('link[href="' + CSS_URL + '"]'))
			document.head.appendChild(E('link', { rel: 'stylesheet', href: CSS_URL }));

		var tone = aghTone(status);

		var aghBody = [
			E('div', { 'class': 'byte-actions' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-apply',
					'click': ui.createHandlerFn(this, 'handleSetup')
				}, [ status.agh.installed ? _('Re-run setup') : _('Install and wire') ]),
				status.agh.installed ? E('button', {
					'class': 'btn cbi-button',
					'click': ui.createHandlerFn(this, 'handleAction', status.agh.running ? 'stop' : 'start')
				}, [ status.agh.running ? _('Stop') : _('Start') ]) : '',
				status.agh.installed ? E('button', {
					'class': 'btn cbi-button',
					'click': ui.createHandlerFn(this, 'handleAction', 'restart')
				}, [ _('Restart') ]) : '',
				status.agh.installed ? E('button', {
					'class': 'btn cbi-button',
					'click': ui.createHandlerFn(this, 'handleAction', status.agh.enabled ? 'autostart_off' : 'autostart_on')
				}, [ status.agh.enabled ? _('Disable autostart') : _('Enable autostart') ]) : '',
				webUrl(status) ? E('a', {
					'class': 'btn cbi-button cbi-button-action',
					'href': webUrl(status), 'target': '_blank', 'rel': 'noopener'
				}, [ _('Open AdGuard Home') ]) : '',
				status.log_available ? E('button', {
					'class': 'btn cbi-button',
					'click': ui.createHandlerFn(this, 'handleLog')
				}, [ _('Setup log') ]) : ''
			]),
			kv([
				[ _('State'), tone[0] ],
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

		/* Hero goes BELOW the cards. LuCI pins its toolbar to the top of the
		 * viewport, and a hero rendered first sits under it: the title and the
		 * status badge were being clipped. Same order as luci-app-modeminfo. */
		return E('div', { 'class': 'byte-page' }, [
			/* This page is not a general BYTE settings page - say so before any
			 * button, or an admin who lands here from Tools has no idea that
			 * "Install and wire" touches dnsmasq's port and PassWall2's DNS. */
			E('section', { 'class': 'byte-intro' }, [
				E('h3', {}, [ _('AdGuard Home + PassWall2 setup') ]),
				E('p', {}, [ _('This page wires DNS filtering for the whole LAN: it installs AdGuard Home from this firmware\'s own repository and puts it in front of PassWall2. Clients keep using port 53 on the router, AdGuard filters, PassWall2 resolves and proxies, and dnsmasq moves to port 54 for .lan names.') ]),
				E('p', { 'class': 'byte-note' }, [ _('It is not a general settings page: PassWall2 nodes live under Services - PassWall2, and TTL, modem, WiFi, firewall and the rest are under Network. Nothing is proxied for you here.') ])
			]),

			E('div', { 'class': 'byte-grid' }, [
				card(_('AdGuard Home'), status.agh.installed ? (status.agh.version || '') : _('not installed'), aghBody, true),
				card(_('DNS chain'), _('who answers what'), chainBody)
			]),

			E('header', { 'class': 'byte-hero' }, [
				E('div', {}, [
					E('h2', {}, [ 'BYTE' ]),
					E('p', { 'class': 'byte-sub' }, [
						_('AdGuard Home in front of PassWall2 on %s').format(status.system.model || 'AW1000'),
						' \u00b7 ', E('code', {}, [ status.system.version || '' ])
					])
				]),
				E('div', { 'class': 'byte-actions' }, [
					badge(tone[0], tone[1])
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

	/* Re-render in place after any state change: button labels (Start/Stop,
	 * Enable/Disable autostart) and the badge must follow the real state. */
	refresh: function() {
		var self = this;

		return callStatus().then(function(s) {
			self.s = s;

			if (self.root && self.root.parentNode) {
				var next = self.buildPage(s);
				self.root.parentNode.replaceChild(next, self.root);
				self.root = next;
			}

			return s;
		});
	},

	render: function(status) {
		var self = this;

		this.s = status;
		this.root = this.buildPage(status);

		if (!this.pollerAdded) {
			this.pollerAdded = true;
			poll.add(function() { return self.refresh(); }, 10);
		}

		return this.root;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
