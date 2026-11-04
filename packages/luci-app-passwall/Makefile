# Copyright (C) 2018-2020 L-WRT Team
# Copyright (C) 2021-2023 xiaorouji
#
# This is free software, licensed under the GNU General Public License v3.
#
# BYTE by ACE: vendored copy of PassWall v1 (4.66-8). IN THE IMAGE since
# 1.2.39, SHIPPING DISABLED (0_default_config sets global.enabled=0 and the
# package installs no rc.d symlink), so it cannot take port 53 or the redirect
# hooks away from passwall2 at boot.
#   - both v1 and v2 install transparent-proxy rules and both want port 53
#     (dnsmasq), so running them together breaks whichever started last.
#     Enabling v1 means disabling passwall2 first; that is a user decision.
#   - it was published on demand until 1.2.38. That never worked: the repo is
#     filtered against the image manifest, so dns2socks/dns2tcp/microsocks
#     were missing from it and opkg refused the install. dns2tcp is in the
#     image (it is v1's default dns_mode); dns2socks and microsocks are
#     published on demand again since 1.2.40, they back optional modes only.
#   - v1 ships Lua controllers; luci-lua-runtime, lua, libuci-lua and
#     luci-lib-jsonc are already in the image, so the pages load.
#   - the Nftables variant is the only one that can work here, and its
#     upstream `select PACKAGE_nftables` is repointed to nftables-json below.
#
# Core defaults are pinned to Xray only (below). Upstream turns on nine
# INCLUDE_* options for aarch64, which would pull v2ray-core,
# shadowsocks-libev, shadowsocks-rust, shadowsocksr-libev, trojan-plus,
# simple-obfs and haproxy into the image. xray-core is already there
# (passwall2 uses it), so v1 gets a working core at zero extra size; any other
# core can be installed separately from the ImmortalWrt feeds.

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-passwall
PKG_VERSION:=4.66-8
PKG_RELEASE:=

PKG_CONFIG_DEPENDS:= \
	CONFIG_PACKAGE_$(PKG_NAME)_Iptables_Transparent_Proxy \
	CONFIG_PACKAGE_$(PKG_NAME)_Nftables_Transparent_Proxy \
	CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Brook \
	CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Haproxy \
	CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Hysteria \
	CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_NaiveProxy \
	CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Client \
	CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Server \
	CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Client \
	CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Server \
	CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_ShadowsocksR_Libev_Client \
	CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_ShadowsocksR_Libev_Server \
	CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Simple_Obfs \
	CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Trojan_GO \
	CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Trojan_Plus \
	CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_V2ray \
	CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_V2ray_Geodata \
	CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_V2ray_Plugin \
	CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Xray \
	CONFIG_PACKAGE_$(PKG_NAME)_INCLUDE_Xray_Plugin

LUCI_TITLE:=LuCI support for PassWall
LUCI_PKGARCH:=all
# Dependencies are the set this package actually executes with its pinned
# core (Xray) and its shipped default config. dns2socks and microsocks were
# dropped in 1.2.40: dns2socks only backs the optional dns_mode=dns2socks
# filter and microsocks only backs socks_enabled / the socks server, both off
# by default. They stay published in the BYTE opkg repo (ondemand.txt), and
# the LuCI page hides a mode whose binary is missing (api.is_finded).
LUCI_DEPENDS:=+coreutils +coreutils-base64 +coreutils-nohup +curl \
	+chinadns-ng +dns2tcp +ip-full +libuci-lua +lua +luci-compat +luci-lib-jsonc \
	+resolveip +tcping +unzip \
	+PACKAGE_$(PKG_NAME)_INCLUDE_Brook:brook \
	+PACKAGE_$(PKG_NAME)_INCLUDE_Haproxy:haproxy \
	+PACKAGE_$(PKG_NAME)_INCLUDE_Hysteria:hysteria \
	+PACKAGE_$(PKG_NAME)_INCLUDE_NaiveProxy:naiveproxy \
	+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Client:shadowsocks-libev-ss-local \
	+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Client:shadowsocks-libev-ss-redir \
	+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Server:shadowsocks-libev-ss-server \
	+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Client:shadowsocks-rust-sslocal \
	+PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Server:shadowsocks-rust-ssserver \
	+PACKAGE_$(PKG_NAME)_INCLUDE_ShadowsocksR_Libev_Client:shadowsocksr-libev-ssr-local \
	+PACKAGE_$(PKG_NAME)_INCLUDE_ShadowsocksR_Libev_Client:shadowsocksr-libev-ssr-redir \
	+PACKAGE_$(PKG_NAME)_INCLUDE_ShadowsocksR_Libev_Server:shadowsocksr-libev-ssr-server \
	+PACKAGE_$(PKG_NAME)_INCLUDE_Simple_Obfs:simple-obfs \
	+PACKAGE_$(PKG_NAME)_INCLUDE_Trojan_GO:trojan-go \
	+PACKAGE_$(PKG_NAME)_INCLUDE_Trojan_Plus:trojan-plus \
	+PACKAGE_$(PKG_NAME)_INCLUDE_V2ray:v2ray-core \
	+PACKAGE_$(PKG_NAME)_INCLUDE_V2ray_Geodata:v2ray-geoip \
	+PACKAGE_$(PKG_NAME)_INCLUDE_V2ray_Geodata:v2ray-geosite \
	+PACKAGE_$(PKG_NAME)_INCLUDE_V2ray_Plugin:v2ray-plugin \
	+PACKAGE_$(PKG_NAME)_INCLUDE_Xray:xray-core \
	+PACKAGE_$(PKG_NAME)_INCLUDE_Xray_Plugin:xray-plugin

define Package/$(PKG_NAME)/config
menu "Configuration"

config PACKAGE_$(PKG_NAME)_Iptables_Transparent_Proxy
	bool "Iptables Transparent Proxy"
	select PACKAGE_dnsmasq-full
	select PACKAGE_ipset
	select PACKAGE_ipt2socks
	select PACKAGE_iptables
	select PACKAGE_iptables-zz-legacy
	select PACKAGE_iptables-mod-conntrack-extra
	select PACKAGE_iptables-mod-iprange
	select PACKAGE_iptables-mod-socket
	select PACKAGE_iptables-mod-tproxy
	select PACKAGE_kmod-ipt-nat
	depends on PACKAGE_$(PKG_NAME)
	default y if ! PACKAGE_firewall4

config PACKAGE_$(PKG_NAME)_Nftables_Transparent_Proxy
	bool "Nftables Transparent Proxy"
	select PACKAGE_dnsmasq-full
	# BYTE by ACE: upstream selects PACKAGE_nftables, which is the nojson
	# variant and CONFLICTS nftables-json. firewall4 already ships
	# nftables-json (same /usr/sbin/nft, JSON support), so the upstream
	# select produced two providers of the same file and image assembly
	# died with a collision. nftables-json PROVIDES nftables, so every
	# `nft` call passwall makes resolves to the copy the image already has.
	select PACKAGE_nftables-json
	select PACKAGE_kmod-nft-socket
	select PACKAGE_kmod-nft-tproxy
	select PACKAGE_kmod-nft-nat
	depends on PACKAGE_$(PKG_NAME)
	default y if PACKAGE_firewall4

config PACKAGE_$(PKG_NAME)_INCLUDE_Brook
	bool "Include Brook"
	default n

config PACKAGE_$(PKG_NAME)_INCLUDE_Haproxy
	bool "Include Haproxy"
	default n	# BYTE: pinned

config PACKAGE_$(PKG_NAME)_INCLUDE_Hysteria
	bool "Include Hysteria"
	default n

config PACKAGE_$(PKG_NAME)_INCLUDE_NaiveProxy
	bool "Include NaiveProxy"
	depends on !(arc||(arm&&TARGET_gemini)||armeb||mips||mips64||powerpc)
	default n

config PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Client
	bool "Include Shadowsocks Libev Client"
	default n	# BYTE: pinned

config PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev_Server
	bool "Include Shadowsocks Libev Server"
	default n	# BYTE: pinned

config PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Client
	bool "Include Shadowsocks Rust Client"
	depends on aarch64||arm||i386||mips||mipsel||x86_64
	default n	# BYTE: pinned

config PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Rust_Server
	bool "Include Shadowsocks Rust Server"
	depends on aarch64||arm||i386||mips||mipsel||x86_64
	default n

config PACKAGE_$(PKG_NAME)_INCLUDE_ShadowsocksR_Libev_Client
	bool "Include ShadowsocksR Libev Client"
	default n	# BYTE: pinned

config PACKAGE_$(PKG_NAME)_INCLUDE_ShadowsocksR_Libev_Server
	bool "Include ShadowsocksR Libev Server"
	default n

config PACKAGE_$(PKG_NAME)_INCLUDE_Simple_Obfs
	bool "Include Simple-Obfs (Shadowsocks Plugin)"
	default n	# BYTE: pinned

config PACKAGE_$(PKG_NAME)_INCLUDE_Trojan_GO
	bool "Include Trojan-GO"
	default n

config PACKAGE_$(PKG_NAME)_INCLUDE_Trojan_Plus
	bool "Include Trojan-Plus"
	default n	# BYTE: pinned

config PACKAGE_$(PKG_NAME)_INCLUDE_V2ray
	bool "Include V2ray"
	default n	# BYTE: pinned

config PACKAGE_$(PKG_NAME)_INCLUDE_V2ray_Geodata
	bool "Include V2ray_Geodata"
	default n

config PACKAGE_$(PKG_NAME)_INCLUDE_V2ray_Plugin
	bool "Include V2ray-Plugin (Shadowsocks Plugin)"
	default n	# BYTE: pinned

config PACKAGE_$(PKG_NAME)_INCLUDE_Xray
	bool "Include Xray"
	default y	# BYTE: pinned

config PACKAGE_$(PKG_NAME)_INCLUDE_Xray_Plugin
	bool "Include Xray-Plugin (Shadowsocks Plugin)"
	default n

endmenu
endef

define Package/$(PKG_NAME)/conffiles
/etc/config/passwall
/etc/config/passwall_server
/usr/share/passwall/rules/direct_host
/usr/share/passwall/rules/direct_ip
/usr/share/passwall/rules/proxy_host
/usr/share/passwall/rules/proxy_ip
/usr/share/passwall/rules/block_host
/usr/share/passwall/rules/block_ip
/usr/share/passwall/rules/lanlist_ipv4
/usr/share/passwall/rules/lanlist_ipv6
/usr/share/passwall/rules/domains_excluded
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
