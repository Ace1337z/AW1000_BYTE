'use strict';
'require baseclass';
'require rpc';
'require view.dashboard.lib.charts as charts';

// Storage card. It replaces the NSS offload card: that figure is only refreshed
// while the NSS clock scales itself, and clock scaling is off on this board, so
// the number was always stale.
//
// The widget keeps the "nss" id on purpose. /etc/config/dashboard written by an
// older image lists "nss" under "cards", and the layout resolver drops ids the
// device does not know - renaming the id would silently empty the card row on
// every upgraded unit.
const callSystemInfo = rpc.declare({
	object: 'system',
	method: 'info',
	expect: { }
});

// system.info() reports root/tmp in kilobytes.
function scaled(kb) {
	const units = [ _('KiB'), _('MiB'), _('GiB') ];
	let v = Math.max(0, kb || 0), i = 0;

	while (v >= 1024 && i < units.length - 1) {
		v /= 1024;
		i++;
	}

	return '%.1f %s'.format(v, units[i]);
}

function usedPercent(used, total) {
	return (total > 0) ? Math.min(100, Math.max(0, used / total * 100)) : 0;
}

function bar(used, total) {
	const p = usedPercent(used, total);
	const kind = (p >= 90) ? 'dashboard-storage-high' : ((p >= 75) ? 'dashboard-storage-warn' : '');

	return E('div', {
		'class': 'dashboard-storage-bar ' + kind,
		'role': 'progressbar',
		'aria-valuemin': '0',
		'aria-valuemax': '100',
		'aria-valuenow': String(Math.round(p))
	}, [ E('i', { 'style': 'width:%.1f%%'.format(p) }) ]);
}

return baseclass.extend({
	widgets: [
		{ id: 'nss', slot: 'cards', title: _('Storage'), order: 40 }
	],

	available() {
		return true;
	},

	load() {
		return L.resolveDefault(callSystemInfo(), {});
	},

	render(info) {
		info = info || {};

		const root = info.root || {};
		const tmp = info.tmp || {};
		const rUsed = root.used || 0, rTotal = root.total || 0;
		const tUsed = tmp.used || 0, tTotal = tmp.total || 0;

		return {
			cards: [ {
				id: 'nss',
				node: () => E('div', { 'class': 'cbi-section dashboard-kpi dashboard-storage' }, [
					charts.icon('storage', 'dashboard-kpi-icon'),
					E('div', { 'class': 'dashboard-kpi-text' }, [
						E('small', {}, [ _('Storage') ]),
						E('strong', { 'class': 'dashboard-kpi-value' },
							[ '%s / %s'.format(scaled(rUsed), scaled(rTotal)) ]),
						bar(rUsed, rTotal),
						E('small', { 'class': 'dashboard-kpi-sub' },
							[ _('overlay · %d%% used').format(Math.round(usedPercent(rUsed, rTotal))) ]),
						E('small', { 'class': 'dashboard-kpi-sub dashboard-kpi-line' },
							[ _('/tmp %s / %s').format(scaled(tUsed), scaled(tTotal)) ])
					])
				])
			} ]
		};
	}
});
