#!/bin/sh
# VENDORED, pinned copy of https://github.com/Ace1337z/openwrt-agh-passwall2
# (install.sh, branch main). Settings only: installs adguardhome + LuCI app,
# moves dnsmasq to 54, points AdGuard at PassWall2 DNS 127.0.0.1:15353.
# Do not fetch this over the network at runtime - the copy in the image is the
# one the panel runs, so an upstream change cannot alter behaviour silently.
# ==============================================================================
#  OpenWrt + AdGuardHome + PassWall2  —  conflict-free one-shot installer
#  Repository : https://github.com/Ace1337z/openwrt-agh-passwall2
# ------------------------------------------------------------------------------
#  SETTINGS ONLY. This script does NOT add any PassWall2 proxy nodes.
#  You still add/choose your nodes in LuCI -> PassWall2 afterwards.
#
#  What it does:
#    1. Installs AdGuardHome (+ LuCI) and PassWall2 LuCI if missing
#    2. Moves dnsmasq to port 54 so AdGuardHome can own port 53 (LAN DNS)
#    3. Creates/patches AdGuardHome config:
#         upstream                 -> tcp://127.0.0.1:15353  (PassWall2 DNS)
#         .lan/.local/.home.arpa   -> 127.0.0.1:54           (dnsmasq)
#         bootstrap/fallback       -> reachable IPv4 resolvers (no IPv6)
#         SafeSearch / parental    -> OFF (avoids google->forcesafesearch)
#    4. Configures PassWall2 to NOT hijack DNS (dns_redirect=0) and keep the
#       local DNS/proxy on loopback, so AdGuard + PassWall2 never conflict.
#    5. Enables + restarts services in the correct order.
#
#  Result:
#    client -> router:53 (AdGuardHome: ad-block/filter)
#           -> PassWall2 DNS 127.0.0.1:15353 (CN-direct / foreign-proxy split)
#           -> local .lan names -> dnsmasq 127.0.0.1:54
#
#  Safe & idempotent. Existing configs are backed up to *.agh-pw.bak.<ts>.
#
#  Usage (on the router, as root):
#    wget -O - https://raw.githubusercontent.com/Ace1337z/openwrt-agh-passwall2/main/install.sh | sh
#  or:
#    sh install.sh
# ==============================================================================

set -u

# ------------------------------ tunables --------------------------------------
AGH_PORT=53            # AdGuardHome listen port (LAN DNS)
DNSMASQ_PORT=54        # dnsmasq port (must differ from AGH_PORT)
PW_DNS_PORT=15353      # PassWall2 built-in DNS port
AGH_DIR="${AGH_DIR:-/etc/adguardhome}"
AGH_YAML="${AGH_YAML:-${AGH_DIR}/adguardhome.yaml}"
AGH_UCI="${AGH_UCI:-/etc/config/adguardhome}"
DHCP_CFG="${DHCP_CFG:-/etc/config/dhcp}"
PW_CFG="${PW_CFG:-/etc/config/passwall2}"
INIT_D="${INIT_D:-/etc/init.d}"
AGH_WORKDIR="${AGH_WORKDIR:-/var/lib/adguardhome}"
BOOT1="223.5.5.5"      # bootstrap/fallback, IPv4, reachable
BOOT2="119.29.29.29"

# ---------------------------------------------------------------- helpers -----
log()  { printf '\033[1;36m[agh-pw]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

need_root() {
    [ -n "${AGH_PW_SKIP_ROOT:-}" ] && return 0
    [ "$(id -u)" = "0" ] || die "Run as root on the OpenWrt router."
}

pkg_installed() {
    if command -v opkg >/dev/null 2>&1; then
        opkg list-installed 2>/dev/null | grep -q "^${1} "
    else
        apk info -e "$1" >/dev/null 2>&1
    fi
}
pkg_ensure() {
    p="$1"
    if pkg_installed "$p"; then
        log "  - ${p}: already installed"; return 0
    fi
    log "  - ${p}: installing"
    if command -v opkg >/dev/null 2>&1; then
        opkg update >/dev/null 2>&1 || true
        opkg install "$p" >/dev/null 2>&1 || { warn "opkg install ${p} failed (check repo/space)"; return 1; }
    elif command -v apk >/dev/null 2>&1; then
        apk add "$p" >/dev/null 2>&1 || { warn "apk add ${p} failed"; return 1; }
    else
        return 1
    fi
}

backup() { [ -f "$1" ] && cp -f "$1" "$1.agh-pw.bak.$(date +%s)" 2>/dev/null || true; }

# -------------------------- patch AdGuardHome YAML ----------------------------
# Rewrites ONLY the managed keys inside the top-level "dns:" section. Everything
# else in the file is preserved. (Validated against AdGuardHome v0.107.x)
patch_agh_dns() {
    _in="$1"
    awk -v port="${AGH_PORT}" -v pwdns="tcp://127.0.0.1:${PW_DNS_PORT}" \
        -v dm="${DNSMASQ_PORT}" -v b1="${BOOT1}" -v b2="${BOOT2}" '
    function emit_managed(   ) {
        print "  bind_hosts:"
        print "    - 0.0.0.0"
        print "  port: " port
        print "  upstream_dns:"
        print "    - " pwdns
        print "    - \"[/lan/]127.0.0.1:" dm "\""
        print "    - \"[/local/]127.0.0.1:" dm "\""
        print "    - \"[/home.arpa/]127.0.0.1:" dm "\""
        print "  upstream_dns_file: \"\""
        print "  bootstrap_dns:"
        print "    - " b1
        print "    - " b2
        print "  fallback_dns:"
        print "    - " b1
        print "    - " b2
        print "  upstream_mode: parallel"
        print "  fastest_timeout: 1s"
    }
    BEGIN { in_dns=0; found=0; skip_cont=0 }
    {
        if ($0 ~ /^dns:[[:space:]]*$/) { found=1; print; emit_managed(); in_dns=1; next }
        if (in_dns==1 && $0 ~ /^[^[:space:]#]/) { in_dns=0 }
        if (in_dns==1) {
            if ($0 ~ /^[[:space:]]{2}(bind_hosts|port|upstream_dns|upstream_dns_file|bootstrap_dns|fallback_dns|upstream_mode|fastest_timeout):/) { skip_cont=1; next }
            if (skip_cont==1 && $0 ~ /^[[:space:]]{4}/) { next }
            if ($0 ~ /^[[:space:]]{2}[A-Za-z_]/) { skip_cont=0 }
        }
        print
    }
    END { if (found==0) { print "dns:"; emit_managed() } }
    ' "$_in"
}

# Write a complete, valid AdGuardHome default config (for fresh installs).
write_default_agh_yaml() {
    cat > "${AGH_YAML}" <<'YAML'
http:
  pprof:
    port: 6060
    enabled: false
  doh:
    routes:
    - GET /dns-query
    - POST /dns-query
    insecure_enabled: false
  address: 0.0.0.0:3000
  session_ttl: 30d
users: []
auth_attempts: 0
block_auth_min: 15
http_proxy: ''
language: ''
theme: auto
dns:
  bind_hosts:
  - 0.0.0.0
  port: 53
  anonymize_client_ip: false
  ratelimit: 20
  ratelimit_subnet_len_ipv4: 24
  ratelimit_subnet_len_ipv6: 56
  ratelimit_whitelist: []
  refuse_any: true
  upstream_dns:
  - tcp://127.0.0.1:15353
  - '[/lan/]127.0.0.1:54'
  - '[/local/]127.0.0.1:54'
  - '[/home.arpa/]127.0.0.1:54'
  upstream_dns_file: ''
  bootstrap_dns:
  - 223.5.5.5
  - 119.29.29.29
  fallback_dns:
  - 223.5.5.5
  - 119.29.29.29
  upstream_mode: parallel
  fastest_timeout: 1s
  allowed_clients: []
  disallowed_clients: []
  blocked_hosts:
  - version.bind
  - id.server
  - hostname.bind
  trusted_proxies:
  - 127.0.0.0/8
  - ::1/128
  cache_enabled: true
  cache_size: 67108864
  cache_ttl_min: 0
  cache_ttl_max: 0
  cache_optimistic: true
  cache_optimistic_answer_ttl: 30s
  cache_optimistic_max_age: 12h
  bogus_nxdomain: []
  aaaa_disabled: false
  enable_dnssec: true
  edns_client_subnet:
    custom_ip: ''
    enabled: false
    use_custom: false
  max_goroutines: 300
  handle_ddr: true
  ipset: []
  ipset_file: ''
  bootstrap_prefer_ipv6: false
  upstream_timeout: 10s
  private_networks: []
  use_private_ptr_resolvers: false
  local_ptr_upstreams: []
  use_dns64: false
  dns64_prefixes: []
  serve_http3: false
  use_http3_upstreams: false
  serve_plain_dns: true
  hostsfile_enabled: true
  pending_requests:
    enabled: true
tls:
  enabled: false
  server_name: ''
  force_https: false
  port_https: 443
  port_dns_over_tls: 853
  port_dns_over_quic: 853
  port_dnscrypt: 0
  dnscrypt_config_file: ''
  certificate_chain: ''
  private_key: ''
  certificate_path: ''
  private_key_path: ''
  strict_sni_check: false
querylog:
  dir_path: ''
  ignored: []
  interval: 90d
  size_memory: 1000
  enabled: true
  ignored_enabled: false
  file_enabled: true
statistics:
  dir_path: ''
  ignored: []
  interval: 1d
  enabled: true
  ignored_enabled: false
filters: []
whitelist_filters: []
user_rules: []
dhcp:
  enabled: false
  interface_name: ''
  local_domain_name: lan
  dhcpv4:
    gateway_ip: ''
    subnet_mask: ''
    range_start: ''
    range_end: ''
    lease_duration: 86400
    icmp_timeout_msec: 1000
    options: []
  dhcpv6:
    range_start: ''
    lease_duration: 86400
    ra_slaac_only: false
    ra_allow_slaac: false
filtering:
  blocking_ipv4: ''
  blocking_ipv6: ''
  blocked_services:
    schedule:
      time_zone: UTC
    ids: []
  protection_disabled_until: null
  safe_search:
    enabled: false
    bing: false
    duckduckgo: false
    ecosia: false
    google: false
    pixabay: false
    yandex: false
    youtube: false
  blocking_mode: default
  parental_block_host: family-block.dns.adguard.com
  safebrowsing_block_host: standard-block.dns.adguard.com
  rewrites: []
  safe_fs_patterns:
  - /var/lib/adguardhome/userfilters/*
  max_http_size: 256MB
  safebrowsing_cache_size: 1048576
  safesearch_cache_size: 1048576
  parental_cache_size: 1048576
  cache_time: 30
  filters_update_interval: 24
  blocked_response_ttl: 10
  filtering_enabled: true
  rewrites_enabled: true
  parental_enabled: false
  safebrowsing_enabled: false
  protection_enabled: true
clients:
  runtime_sources:
    whois: true
    arp: true
    rdns: true
    dhcp: true
    hosts: true
  persistent: []
log:
  enabled: true
  file: ''
  max_backups: 0
  max_size: 100
  max_age: 3
  compress: false
  local_time: false
  verbose: false
os:
  group: ''
  user: ''
  rlimit_nofile: 0
schema_version: 34
YAML
}

# ---------------------------------- steps -------------------------------------
step_install() {
    log "Step 1/6: packages"
    pkg_ensure adguardhome          || warn "AdGuardHome missing — DNS may not start"
    pkg_ensure luci-app-adguardhome || warn "LuCI app for AdGuardHome not installed"
    pkg_ensure luci-app-passwall2   || warn "PassWall2 LuCI app not installed"
}

step_dnsmasq_port() {
    log "Step 2/6: dnsmasq -> port ${DNSMASQ_PORT}"
    backup "${DHCP_CFG}"
    uci set dhcp.@dnsmasq[0].port="${DNSMASQ_PORT}"
    uci set dhcp.@dnsmasq[0].authoritative='1' 2>/dev/null || true
    uci set dhcp.@dnsmasq[0].dns_redirect='0'  2>/dev/null || true
    uci commit dhcp
}

step_passwall_dns() {
    log "Step 3/6: PassWall2 DNS (disable redirect, keep local proxy)"
    if ! uci show passwall2 >/dev/null 2>&1; then
        warn "passwall2 uci config not found — is PassWall2 installed? skipping."
        return 0
    fi
    backup "${PW_CFG}"
    # Do NOT let PassWall hijack DNS on port 53 — AdGuardHome owns it.
    # (dnsmasq_dns_redirect is PassWall's own internal backup field, managed
    #  automatically by PassWall; we must NOT set it ourselves.)
    uci set passwall2.@global[0].dns_redirect='0'
    # Keep PassWall's local DNS/proxy on loopback so AdGuard can forward to it.
    uci set passwall2.@global[0].localhost_proxy='1'
    uci set passwall2.@global[0].remote_dns='1.1.1.1'      2>/dev/null || true
    uci set passwall2.@global[0].remote_dns_protocol='tcp' 2>/dev/null || true
    uci set passwall2.@global[0].remote_dns_detour='remote' 2>/dev/null || true
    uci commit passwall2
}

step_adguard_config() {
    log "Step 4/6: AdGuardHome config"
    mkdir -p "${AGH_DIR}" "${AGH_WORKDIR}"

    if [ -f "${AGH_YAML}" ]; then
        log "  - existing config found, patching DNS section"
        backup "${AGH_YAML}"
        patch_agh_dns "${AGH_YAML}" > "${AGH_YAML}.new"
        [ -s "${AGH_YAML}.new" ] || die "failed to generate new AdGuardHome config"
        mv -f "${AGH_YAML}.new" "${AGH_YAML}"
    else
        log "  - no config found, writing sane default"
        write_default_agh_yaml
    fi
    sed -i 's/^\([[:space:]]*bootstrap_prefer_ipv6:\).*/\1 false/' "${AGH_YAML}" 2>/dev/null || true
    chmod 600 "${AGH_YAML}" 2>/dev/null || true

    # UCI wrapper points at our file.
    backup "${AGH_UCI}"
    touch "${AGH_UCI}"
    uci set adguardhome.config='config' 2>/dev/null || true
    uci set adguardhome.config.enabled='1'
    uci set adguardhome.config.config_file="${AGH_YAML}"
    uci set adguardhome.config.work_dir="${AGH_WORKDIR}"
    uci commit adguardhome
}

step_dnsmasq_forward() {
    log "Step 5/6: dnsmasq forwards to PassWall2 (split routing)"
    dropin="$(uci get dhcp.@dnsmasq[0].confdir 2>/dev/null)"
    if [ -z "${dropin}" ]; then
        dropin="/tmp/dnsmasq.d"
        uci set dhcp.@dnsmasq[0].confdir="${dropin}"
    fi
    mkdir -p "${dropin}"
    cat > "${dropin}/dnsmasq-passwall2.conf" <<EOF
# Managed by agh-pw installer: forward dnsmasq -> PassWall2 DNS
server=127.0.0.1#${PW_DNS_PORT}
all-servers
no-poll
no-resolv
EOF
    uci commit dhcp
}

step_enable_restart() {
    log "Step 6/6: enabling + restarting (dnsmasq -> passwall2 -> adguardhome)"
    "${INIT_D}/dnsmasq" restart     >/dev/null 2>&1 || warn "dnsmasq restart failed"
    "${INIT_D}/passwall2" enable    >/dev/null 2>&1 || true
    "${INIT_D}/passwall2" restart   >/dev/null 2>&1 || warn "passwall2 restart failed"
    "${INIT_D}/adguardhome" enable  >/dev/null 2>&1 || true
    "${INIT_D}/adguardhome" restart >/dev/null 2>&1 || warn "adguardhome restart failed"
    sleep 3

    log "==== Summary ===="
    printf '  dnsmasq port             : %s\n' "$(uci get dhcp.@dnsmasq[0].port 2>/dev/null)"
    printf '  dnsmasq dns_redirect     : %s\n' "$(uci get dhcp.@dnsmasq[0].dns_redirect 2>/dev/null)"
    printf '  passwall2 dns_redirect   : %s\n' "$(uci get passwall2.@global[0].dns_redirect 2>/dev/null)"
    if (netstat -ln 2>/dev/null || ss -ln 2>/dev/null) | grep -qE '[:.]53[[:space:]]'; then
        printf '  AdGuardHome on :53       : yes\n'
    else
        printf '  AdGuardHome on :53       : NOT DETECTED (check log)\n'
    fi
    echo
    RIP="$(uci get network.lan.ipaddr 2>/dev/null | cut -d/ -f1)"
    [ -n "$RIP" ] || RIP="<router-ip>"
    log "Next steps:"
    log "  1) Open AdGuardHome UI:  http://${RIP}:3000"
    log "     (first install: create admin user/password there)"
    log "  2) Add/choose your proxy nodes in LuCI -> Services -> PassWall2"
    log ""
    log "Finished."
}

main() {
    need_root
    log "OpenWrt AdGuardHome + PassWall2 conflict-free setup"
    step_install
    step_dnsmasq_port
    step_passwall_dns
    step_adguard_config
    step_dnsmasq_forward
    step_enable_restart
}

main "$@"
