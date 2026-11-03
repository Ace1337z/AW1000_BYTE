'use strict';
'require baseclass';
'require fs';
'require rpc';
'require uci';

var callGetUnixtime = rpc.declare({
	object: 'luci',
	method: 'getUnixtime',
	expect: { result: 0 }
});

var callLuciVersion = rpc.declare({
	object: 'luci',
	method: 'getVersion'
});

var callSystemBoard = rpc.declare({
	object: 'system',
	method: 'board'
});

var callSystemInfo = rpc.declare({
	object: 'system',
	method: 'info'
});

var callCPUBench = rpc.declare({
	object: 'luci',
	method: 'getCPUBench'
});

var callCPUInfo = rpc.declare({
	object: 'luci',
	method: 'getCPUInfo'
});

var callCPUUsage = rpc.declare({
	object: 'luci',
	method: 'getCPUUsage'
});

var callTempInfo = rpc.declare({
	object: 'luci',
	method: 'getTempInfo'
});

/* Brand string shown as "Hostname". The real hostname stays BYTE_by_ACE (a
 * space is not a legal DHCP/DNS name), so the panel shows the readable form
 * while dnsmasq, SSH prompts and leases keep the underscore version. */
var BRAND = 'BYTE by ACE';

/* "BYTE 25.12.6.12.94 1.2.27" -> "BYTE 25.12 VERSION 1.2.27".
 * The kernel is already its own row, so repeating it inside the firmware
 * string only makes the panel harder to read. Fallback for images that do not
 * stamp /etc/byte-version yet. */
function firmwareLabel(desc, bytever) {
	if (bytever)
		return bytever;

	var m = /^(\S+)\s+([0-9]+(?:\.[0-9]+)+)\s+(\S+)/.exec(desc || '');
	if (!m)
		return desc || null;

	var series = m[2].split('.').slice(0, 2).join('.');
	return '%s %s VERSION %s'.format(m[1], series, m[3]);
}

return baseclass.extend({
	title: _('System'),

	load: function() {
		return Promise.all([
			L.resolveDefault(callSystemBoard(), {}),
			L.resolveDefault(callSystemInfo(), {}),
			L.resolveDefault(callCPUBench(), {}),
			L.resolveDefault(callCPUInfo(), {}),
			L.resolveDefault(callCPUUsage(), {}),
			L.resolveDefault(callTempInfo(), {}),
			L.resolveDefault(callLuciVersion(), { revision: _('unknown version'), branch: 'LuCI' }),
			L.resolveDefault(callGetUnixtime(), 0),
			L.resolveDefault(fs.read('/etc/byte-version', 128), null),
			uci.load('system')
		]);
	},

	render: function(data) {
		var boardinfo   = data[0],
		    systeminfo  = data[1],
		    cpubench    = data[2],
		    cpuinfo     = data[3],
		    cpuusage    = data[4],
		    tempinfo    = data[5],
		    luciversion = data[6],
		    unixtime    = data[7],
		    bytever     = (data[8] && data[8].code === 0) ? (data[8].data || '').trim() : '';

		luciversion = luciversion.branch + ' ' + luciversion.revision;

		var datestr = null;
		if (unixtime) {
			var date = new Date(unixtime * 1000),
				zn = uci.get('system', '@system[0]', 'zonename')?.replaceAll(' ', '_') || 'UTC',
				ts = uci.get('system', '@system[0]', 'clock_timestyle') || 0,
				hc = uci.get('system', '@system[0]', 'clock_hourcycle') || 0;

			datestr = new Intl.DateTimeFormat(undefined, {
				dateStyle: 'medium',
				timeStyle: (ts == 0) ? 'long' : 'full',
				hourCycle: (hc == 0) ? undefined : hc,
				timeZone: zn
			}).format(date);
		}

		var fields = [
			_('Hostname'),         BRAND,
			_('Model'),            boardinfo.model + (cpubench.cpubench || ''),
			_('Architecture'),     cpuinfo.cpuinfo || boardinfo.system,
			_('Target Platform'),  (L.isObject(boardinfo.release) ? boardinfo.release.target : ''),
			/* BYTE: show only the firmware identity. Upstream appends
			 * " / luci-<version>", which puts two versions in one row and
			 * buries the string this image actually ships. The LuCI
			 * version is still visible in System -> Software (luci-base). */
			_('Firmware Version'), firmwareLabel(
				L.isObject(boardinfo.release) ? boardinfo.release.description : '', bytever),
			_('Kernel Version'),   boardinfo.kernel,
			_('Local Time'),       datestr,
			_('Uptime'),           systeminfo.uptime ? '%t'.format(systeminfo.uptime) : null,
			_('Load Average'),     Array.isArray(systeminfo.load) ? '%.2f, %.2f, %.2f'.format(
				systeminfo.load[0] / 65535.0,
				systeminfo.load[1] / 65535.0,
				systeminfo.load[2] / 65535.0
			) : null,
			_('CPU usage (%)'),    cpuusage.cpuusage
		];

		if (tempinfo.tempinfo) {
			fields.splice(6, 0, _('Temperature'));
			fields.splice(7, 0, tempinfo.tempinfo);
		}

		var table = E('table', { 'class': 'table' });

		for (var i = 0; i < fields.length; i += 2) {
			table.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '33%' }, [ fields[i] ]),
				E('td', { 'class': 'td left' }, [ (fields[i + 1] != null) ? fields[i + 1] : '?' ])
			]));
		}

		return table;
	}
});
