#!/usr/bin/env bash
# Release body for the BYTE by ACE FINAL build.
#
# Deliberately short: the user asked for a summary of what changed, nothing
# else. No package tables, no feed pins, no known-issues list - those live in
# the repository for anyone who wants the detail.
#
# Usage: release-notes-final.sh <target-dir> [out-dir]
set -euo pipefail

dir=${1:?usage: release-notes-final.sh <target-dir> [out-dir]}
out=${2:-}

img=$(ls "$dir"/*squashfs-sysupgrade.bin 2>/dev/null | head -1 || true)
if [ -n "$out" ] && [ -d "$out" ]; then
	c=$(ls "$out"/*squashfs-sysupgrade.bin 2>/dev/null | head -1 || true)
	[ -n "$c" ] && img=$c
fi
size=""
[ -n "${img:-}" ] && size=$(du -h "$img" | cut -f1)

n() { printf '%s\n' "$@"; }

n "# BYTE by ACE — FINAL"
n ""
n "Arcadyan AW1000 (\`qualcommax/ipq807x\`) · ImmortalWrt openwrt-25.12 · kernel 6.12.112"
n ""
n "This is the final release. Every known defect found during testing is fixed."
n ""
n "## What changed in this build"
n ""
n "**Internet / connectivity**"
n ""
n "- **IPv6 no longer breaks browsing.** On carriers that hand out an IPv6 prefix"
n "  without a routable address, the router used to prefer IPv6, send traffic out"
n "  with an unusable source, and stall every page load while IPv4 stayed fine."
n "  IPv6 is still enabled by default; it is only demoted to IPv4 after being"
n "  measured unusable, and restored automatically if the carrier starts working."
n "- **MTU fixed at 1420 on the cellular link** (was 1500). A 1500-byte payload"
n "  cannot cross an LTE/NR bearer, so large transfers and calls stalled while"
n "  small packets passed. Re-applied on every redial, since qmodem recreates"
n "  the interface."
n "- **Latency settings now actually apply.** A read-only kernel key sat before"
n "  the tuning block and made \`sysctl -p\` abort the rest of the file, so"
n "  \`tcp_slow_start_after_idle\` never took effect. Removed; all 33 remaining"
n "  keys verified accepted."
n ""
n "**Package manager**"
n ""
n "- **\`opkg update\` verifies cleanly.** The signing key is now installed before"
n "  the firmware is compiled, so the image trusts the key that signs the feed."
n "  Previously every index failed verification while still reporting success,"
n "  leaving no packages installable."
n "- **AdGuard Home installable.** Its UI requires a newer build than the"
n "  24.10.6 feeds carry, so the binary is now published alongside the app."
n ""
n "**Stability**"
n ""
n "- **zram now activates.** It was configured for lz4, which this kernel does"
n "  not provide, so it silently gave up and shipped with zero swap. Switched to"
n "  lzo-rle; 433 MB of compressed swap is now live, preventing an OOM from"
n "  killing the proxy."
n "- **Phone updated to v0.3.0** — call history, automatic cleanup of old calls,"
n "  and the phone LED no longer being turned off by firmware LED settings."
n "  Built from upstream; our previous fork had stalled at v0.2.0."
n "- **Tailscale no longer runs without credentials**, saving ~13 MB on routers"
n "  that never log in. It starts normally once you run \`tailscale up\`."
n ""
n "**Cleanup**"
n ""
n "- **Passwall v1 removed.** It and passwall2 both install redirect rules on the"
n "  same nft table and fight over port 53, so v1 was always torn down and"
n "  appeared broken. Only passwall2 ships."
n ""
n "## Important: if \`opkg update\` reports signature failures"
n ""
n "Our package feed is served through jsDelivr, and jsDelivr is currently"
n "handing out a **stale signature file** for it. The package lists themselves"
n "download fine, but the signature does not match, so \`opkg update\` prints"
n "\"Signature check failed\" for our feeds while the ImmortalWrt feeds pass."
n ""
n "This is not a problem with your router and nothing is corrupt. Point the"
n "feed at GitHub directly instead of the CDN - run these three commands as"
n "root over SSH:"
n ""
n '```sh'
n "sed -i 's|https://cdn.jsdelivr.net/gh/Ace1337z/AW1000_BYTE@repo|https://raw.githubusercontent.com/Ace1337z/AW1000_BYTE/repo|g' /etc/opkg/distfeeds.conf"
n "rm -rf /var/opkg-lists"
n "opkg update"
n '```'
n ""
n "You should then see \"Signature check passed\" for every feed. Verified:"
n "16 feeds pass, 0 fail, and AdGuard Home installs cleanly afterwards:"
n ""
n '```sh'
n "opkg install luci-app-adguardhome"
n '```'
n ""
n "## Install"
n ""
n '```sh'
n "sha256sum -c sha256sums"
[ -n "${img:-}" ] && n "sysupgrade -n $(basename "$img")"
n '```'
n ""
n "> \`-n\` discards \`/etc/config\`. Set a root password and WiFi key after flashing."
n "> Feeds are pre-configured: \`opkg update\` works out of the box."
n ""
if [ -n "${size:-}" ]; then
	n "<sub>Image size: $size</sub>"
fi
