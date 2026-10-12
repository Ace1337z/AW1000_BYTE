'use strict';
'require baseclass';
'require rpc';

var call = {
	board: rpc.declare({ object: 'system', method: 'board' }),
	info: rpc.declare({ object: 'system', method: 'info' }),
	cpu: rpc.declare({ object: 'luci', method: 'getCPUUsage' }),
	temp: rpc.declare({ object: 'luci', method: 'getTempInfo' }),
	users: rpc.declare({ object: 'luci', method: 'getOnlineUsers' })
};

return baseclass.extend({
	title: _(''),
	load() {
		return Promise.all([
			L.resolveDefault(call.board(), {}),
			L.resolveDefault(call.info(), {}),
			L.resolveDefault(call.cpu(), {}),
			L.resolveDefault(call.temp(), {}),
			L.resolveDefault(call.users(), {})
		]);
	},
	render([board, info, cpu, temp, users]) {
		const date = new Date(info.localtime * 1000);
		const datestr = '%04d-%02d-%02d %02d:%02d'.format(
			date.getUTCFullYear(), date.getUTCMonth() + 1,
			date.getUTCDate(), date.getUTCHours(), date.getUTCMinutes()
		);

		const cpuStr = cpu.cpuusage
			? (cpu.cpuusage.includes('%') ? cpu.cpuusage : cpu.cpuusage + '%')
			: '?';
		const tempStr = temp.tempinfo?.match(/\d+/)?.[0]
			? temp.tempinfo.match(/\d+/)[0] + '°C'
			: '?';

		const cpuTempStr = `${tempStr} / ${cpuStr}`;

		const versionString = E('span', {}, [
			(board.release?.distribution || '').toUpperCase() + ' ' +
			(board.release?.version || '?') + '/' + (board.kernel || '?')
		]);

		const fields = [
			[_('Firmware'), 'byte'],
			[_('Version'), versionString],
			[_('Time'), datestr],
			[_('Uptime'), info.uptime ? '%t'.format(info.uptime) : '?'],
			[_('Temp / Cpu'), cpuTempStr],
			...(users?.onlineusers != null ? [[_('Online Users'), users.onlineusers.toString()]] : [])
		];

		const table = E('table', { class: 'table' });
		fields.forEach(([label, value]) => {
			table.appendChild(E('tr', { class: 'tr' }, [
				E('td', { class: 'td left', width: '33%' }, [label]),
				E('td', { class: 'td left' }, [value])
			]));
		});

		return table;
	}
});
