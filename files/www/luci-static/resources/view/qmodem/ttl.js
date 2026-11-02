'use strict';
/* BYTE by ACE override of luci-app-qmodem-ttlfw4's ttl.js.
 *
 * The shipped page warns that enabling TTL modification disables NSS/ECM. That
 * is no longer true: modem egress (wwan*, rmnet*) is excluded from acceleration
 * inside ECM itself (qca-nss-ecm patch 0027), so the rewrite and NSS offload
 * coexist. Only the wording changes here - the UCI schema is untouched.
 */
'require view';
'require form';
'require uci';
'require ui';
return view.extend({
	load: function () {
		return uci.load('qmodem_ttl');
	},

	render: function () {
		var m, s, o;

		m = new form.Map('qmodem_ttl', _('TTL Configuration'),
			_('Rewrite the IPv4 TTL and IPv6 Hop Limit of every packet leaving through the modem. This defeats carrier tethering detection.'));

		s = m.section(form.NamedSection, 'main', 'main', _('Global TTL Settings'));
		s.anonymous = true;

		o = s.option(form.Flag, 'enable', _('Enable TTL Modification'));
		o.default = '1';
		o.rmempty = false;
		o.description = _('Rewrite TTL/Hop Limit on the modem uplink. Applies to forwarded LAN/WiFi traffic and to traffic the router originates itself.');

		o = s.option(form.Value, 'ttl', _('TTL Value'));
		o.datatype = 'range(1,255)';
		o.default = '64';
		o.placeholder = '64';
		o.description = _('Value used for both IPv4 TTL and IPv6 Hop Limit. Common values: 64 (Linux default), 128 (Windows default).');

		s = m.section(form.NamedSection, 'main', 'main', _('Important Notes'));
		s.anonymous = true;
		var note = s.option(form.DummyValue, '_note');
		note.rawhtml = true;
		note.cfgvalue = function () {
			return E('div', { 'class': 'cbi-value-description' }, [
				E('ul', {}, [
					E('li', {}, _('NSS/ECM stays enabled: only the modem data interfaces are excluded from acceleration, so LAN, WiFi and bridge traffic is still offloaded.')),
					E('li', {}, _('FW4 flow offloading (the software flowtable) is kept at 0 in both states, because it bypasses the TTL rewrite.')),
					E('li', {}, _('Run "nss-offload status" on the console to see whether ECM is loaded and the rule is active.')),
					E('li', {}, _('Settings take effect after saving and applying changes.'))
				])
			]);
		};

		return m.render();
	},
});
