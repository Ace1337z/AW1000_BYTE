#!/bin/sh

CONFIG=passwall
LOG_FILE=/tmp/log/$CONFIG.log
LOCK_FILE_DIR=/tmp/lock
LOCK_FILE=${LOCK_FILE_DIR}/${CONFIG}_script.lock

echolog() {
	local d="$(date "+%Y-%m-%d %H:%M:%S")"
	#echo -e "$d: $1"
	echo -e "$d: $1" >> $LOG_FILE
}

config_n_get() {
	local ret=$(uci -q get "${CONFIG}.${1}.${2}" 2>/dev/null)
	echo "${ret:=$3}"
}

config_t_get() {
	local index=0
	[ -n "$4" ] && index=$4
	local ret=$(uci -q get $CONFIG.@$1[$index].$2 2>/dev/null)
	echo ${ret:=$3}
}

test_url() {
	local url=$1
	local try=1
	[ -n "$2" ] && try=$2
	local timeout=2
	[ -n "$3" ] && timeout=$3
	local extra_params=$4
	curl --help all | grep "\-\-retry-all-errors" > /dev/null
	[ $? == 0 ] && extra_params="--retry-all-errors ${extra_params}"
	status=$(/usr/bin/curl -I -o /dev/null -skL $extra_params --connect-timeout ${timeout} --retry ${try} -w %{http_code} "$url")
	case "$status" in
		204|\
		200)
			status=200
		;;
	esac
	echo $status
}

test_proxy() {
	result=0
	status=$(test_url "https://www.google.com/generate_204" ${retry_num} ${connect_timeout})
	if [ "$status" = "200" ]; then
		result=0
	else
		status2=$(test_url "https://www.baidu.com" ${retry_num} ${connect_timeout})
		if [ "$status2" = "200" ]; then
			result=1
		else
			result=2
			ping -c 3 -W 1 223.5.5.5 > /dev/null 2>&1
			[ $? -eq 0 ] && {
				result=1
			}
		fi
	fi
	echo $result
}

url_test_node() {
	result=0
	local node_id=$1
	local _type=$(echo $(config_n_get ${node_id} type nil) | tr 'A-Z' 'a-z')
	[ "${_type}" != "nil" ] && {
		if [ "${_type}" == "socks" ]; then
			local _address=$(config_n_get ${node_id} address)
			local _port=$(config_n_get ${node_id} port)
			[ -n "${_address}" ] && [ -n "${_port}" ] && {
				local curlx="socks5h://${_address}:${_port}"
				local _username=$(config_n_get ${node_id} username)
				local _password=$(config_n_get ${node_id} password)
				[ -n "${_username}" ] && [ -n "${_password}" ] && curlx="socks5h://${_username}:${_password}@${_address}:${_port}"
			}
		else
			local _tmp_port=$(/usr/share/${CONFIG}/app.sh get_new_port 61080 tcp)
			/usr/share/${CONFIG}/app.sh run_socks flag="url_test_${node_id}" node=${node_id} bind=127.0.0.1 socks_port=${_tmp_port} config_file=url_test_${node_id}.json
			local curlx="socks5h://127.0.0.1:${_tmp_port}"
		fi
		sleep 1s
		result=$(curl --connect-timeout 3 -o /dev/null -I -skL -w "%{http_code}:%{time_starttransfer}" -x $curlx "https://www.google.com/generate_204")
		pgrep -af "url_test_${node_id}" | awk '! /test\.sh/{print $1}' | xargs kill -9 >/dev/null 2>&1
		rm -rf "/tmp/etc/${CONFIG}/url_test_${node_id}.json"
	}
	echo $result
}

test_node() {
	local node_id=$1
	local _type=$(echo $(config_n_get ${node_id} type nil) | tr 'A-Z' 'a-z')
	[ "${_type}" != "nil" ] && {
		if [ "${_type}" == "socks" ]; then
			local _address=$(config_n_get ${node_id} address)
			local _port=$(config_n_get ${node_id} port)
			[ -n "${_address}" ] && [ -n "${_port}" ] && {
				local curlx="socks5h://${_address}:${_port}"
				local _username=$(config_n_get ${node_id} username)
				local _password=$(config_n_get ${node_id} password)
				[ -n "${_username}" ] && [ -n "${_password}" ] && curlx="socks5h://${_username}:${_password}@${_address}:${_port}"
			}
		else
			local _tmp_port=$(/usr/share/${CONFIG}/app.sh get_new_port 61080 tcp)
			/usr/share/${CONFIG}/app.sh run_socks flag="test_node_${node_id}" node=${node_id} bind=127.0.0.1 socks_port=${_tmp_port} config_file=test_node_${node_id}.json
			local curlx="socks5h://127.0.0.1:${_tmp_port}"
		fi
		sleep 1s
		_proxy_status=$(test_url "https://www.google.com/generate_204" ${retry_num} ${connect_timeout} "-x $curlx")
		pgrep -af "test_node_${node_id}" | awk '! /test\.sh/{print $1}' | xargs kill -9 >/dev/null 2>&1
		rm -rf "/tmp/etc/${CONFIG}/test_node_${node_id}.json"
		if [ "${_proxy_status}" -eq 200 ]; then
			return 0
		fi
	}
	return 1
}

flag=0
main_node=$(config_t_get global tcp_node nil)

test_auto_switch() {
	flag=$(expr $flag + 1)
	local TYPE=$1
	local b_tcp_nodes=$2
	local now_node=$3
	[ -z "$now_node" ] && {
		if [ -f "/tmp/etc/$CONFIG/id/${TYPE}" ]; then
			now_node=$(cat /tmp/etc/$CONFIG/id/${TYPE})
			if [ "$(config_n_get $now_node protocol nil)" = "_shunt" ]; then
				if [ "$shunt_logic" == "1" ] && [ -f "/tmp/etc/$CONFIG/id/${TYPE}_default" ]; then
					now_node=$(cat /tmp/etc/$CONFIG/id/${TYPE}_default)
				elif [ "$shunt_logic" == "2" ] && [ -f "/tmp/etc/$CONFIG/id/${TYPE}_main" ]; then
					now_node=$(cat /tmp/etc/$CONFIG/id/${TYPE}_main)
				else
					shunt_logic=0
				fi
			else
				shunt_logic=0
			fi
		else
			#echolog "auto-switch: unknown error"
			return 1
		fi
	}
	
	[ $flag -le 1 ] && {
		main_node=$now_node
	}

	status=$(test_proxy)
	if [ "$status" == 2 ]; then
		echolog "auto-switch: cannot reach the network - check connectivity"
		return 2
	fi
	
	# check whether the primary node is usable 
	if [ "$restore_switch" == "1" ] && [ "$main_node" != "nil" ] && [ "$now_node" != "$main_node" ]; then
		test_node ${main_node}
		[ $? -eq 0 ] && {
			# primary node is healthy - switching to it
			echolog "auto-switch: ${TYPE} primary node [$(config_n_get $main_node type): $(config_n_get $main_node remarks)] healthy - switching to the primary"
			/usr/share/${CONFIG}/app.sh node_switch flag=${TYPE} new_node=${main_node} shunt_logic=${shunt_logic}
			[ $? -eq 0 ] && {
				echolog "auto-switch: ${TYPE} node switch complete"
				[ "$shunt_logic" != "0" ] && {
					local tcp_node=$(config_t_get global tcp_node nil)
					[ "$(config_n_get $tcp_node protocol nil)" = "_shunt" ] && {
						if [ "$shunt_logic" == "1" ]; then
							uci set $CONFIG.$tcp_node.default_node="$main_node"
						elif [ "$shunt_logic" == "2" ]; then
							uci set $CONFIG.$tcp_node.main_node="$main_node"
						fi
						uci commit $CONFIG
					}
				}
			}
			return 0
		}
	fi
	
	if [ "$status" == 0 ]; then
		#echolog "auto-switch: ${TYPE} node [$(config_n_get $now_node type): $(config_n_get $now_node remarks)] healthy"
		return 0
	elif [ "$status" == 1 ]; then
		echolog "auto-switch: ${TYPE} node [$(config_n_get $now_node type): $(config_n_get $now_node remarks)] unhealthy - trying the next backup"
		local new_node
		in_backup_nodes=$(echo $b_tcp_nodes | grep $now_node)
		# check whether the current node is in the backup list
		if [ -z "$in_backup_nodes" ]; then
			# if not, use the first node as the new node
			new_node=$(echo $b_tcp_nodes | awk -F ' ' '{print $1}')
		else
			# otherwise use the next backup node
			#local count=$(expr $(echo $b_tcp_nodes | grep -o ' ' | wc -l) + 1)
			local next_node=$(echo $b_tcp_nodes | awk -F "$now_node" '{print $2}' | awk -F " " '{print $1}')
			if [ -z "$next_node" ]; then
				new_node=$(echo $b_tcp_nodes | awk -F ' ' '{print $1}')
			else
				new_node=$next_node
			fi
		fi
		test_node ${new_node}
		if [ $? -eq 0 ]; then
			[ "$restore_switch" == "0" ] && {
				[ "$shunt_logic" == "0" ] && uci set $CONFIG.@global[0].tcp_node=$new_node
				[ -z "$(echo $b_tcp_nodes | grep $main_node)" ] && uci add_list $CONFIG.@auto_switch[0].tcp_node=$main_node
				uci commit $CONFIG
			}
			echolog "auto-switch: ${TYPE} node [$(config_n_get $new_node type): $(config_n_get $new_node remarks)] healthy - switching to it"
			/usr/share/${CONFIG}/app.sh node_switch flag=${TYPE} new_node=${new_node} shunt_logic=${shunt_logic}
			[ $? -eq 0 ] && {
				[ "$restore_switch" == "1" ] && [ "$shunt_logic" != "0" ] && {
					local tcp_node=$(config_t_get global tcp_node nil)
					[ "$(config_n_get $tcp_node protocol nil)" = "_shunt" ] && {
						if [ "$shunt_logic" == "1" ]; then
							uci set $CONFIG.$tcp_node.default_node="$main_node"
						elif [ "$shunt_logic" == "2" ]; then
							uci set $CONFIG.$tcp_node.main_node="$main_node"
						fi
						uci commit $CONFIG
					}
				}
				echolog "auto-switch: ${TYPE} node switch complete"
			}
			return 0
		else
			test_auto_switch ${TYPE} "${b_tcp_nodes}" ${new_node}
		fi
	fi
}

start() {
	ENABLED=$(config_t_get global enabled 0)
	[ "$ENABLED" != 1 ] && return 1
	ENABLED=$(config_t_get auto_switch enable 0)
	[ "$ENABLED" != 1 ] && return 1
	delay=$(config_t_get auto_switch testing_time 1)
	#sleep 9s
	connect_timeout=$(config_t_get auto_switch connect_timeout 3)
	retry_num=$(config_t_get auto_switch retry_num 3)
	restore_switch=$(config_t_get auto_switch restore_switch 0)
	shunt_logic=$(config_t_get auto_switch shunt_logic 0)
	while [ "$ENABLED" -eq 1 ]; do
		[ -f "$LOCK_FILE" ] && {
			sleep 6s
			continue
		}
		touch $LOCK_FILE
		TCP_NODE=$(config_t_get auto_switch tcp_node nil)
		[ -n "$TCP_NODE" -a "$TCP_NODE" != "nil" ] && {
			TCP_NODE=$(echo $TCP_NODE | tr -s ' ' '\n' | uniq | tr -s '\n' ' ')
			test_auto_switch TCP "$TCP_NODE"
		}
		rm -f $LOCK_FILE
		sleep ${delay}m
	done
}

arg1=$1
shift
case $arg1 in
test_url)
	test_url $@
	;;
url_test_node)
	url_test_node $@
	;;
*)
	start
	;;
esac
