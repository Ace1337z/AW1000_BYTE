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
n "**Cellular / connectivity**"
n ""
n "- **Cellular carrier now comes up automatically.** qmodem was configured for"
n "  USB slot \`4-1\`, but the RG500Q modem enumerates on \`3-1\`. The scan found no"
n "  device at \`4-1\`, disabled the slot, and never dialed — leaving WAN with no"
n "  carrier and empty modem info. Fixed in the shipped config and the board"
n "  default; the modem dials at boot."
n "- **Modem info no longer errors.** An empty cell ID made the info script run"
n "  \`printf \"%d\" \"0x\"\`, which busybox aborts on, spamming the log under"
n "  \`uhttpd\` and blanking the LuCI page. Conversions are now guarded and the"
n "  leading \`b\` marker is stripped."
n "- **MTU fixed at 1420 on the cellular link** (was 1500). A 1500-byte payload"
n "  cannot cross an LTE/NR bearer, so large transfers and calls stalled while"
n "  small packets passed. Re-applied on every redial."
n ""
n "**Package manager**"
n ""
n "- **The stale-signature workaround is gone.** The feed now points at"
n "  \`raw.githubusercontent.com\` directly (was jsDelivr, which served a stale"
n "  \`Packages.sig\`). \`opkg update\` verifies cleanly out of the box — no manual"
n "  \`sed\` needed. The signing key is still installed before the firmware is"
n "  compiled."
n "- **AdGuard Home installable.** Its UI needs a newer build than the 24.10.6"
n "  feeds carry, so the binary is now published alongside the app."
n ""
n "**HTTP/3-QUIC**"
n ""
n "- **\`curl\`/\`libcurl\` built with HTTP/3 support** (nghttp3 + ngtcp2 on"
n "  OpenSSL). \`curl --http3\` works, so QUIC-capable endpoints negotiate"
n "  HTTP/3 and benefit from its lower handshake latency."
n ""
n "**Stability / speed**"
n ""
n "- **Phone updated to v0.4.1** — newer upstream call handling and fixes. Built"
n "  from upstream, pinned to the release tag."
n "- **zram swap is live** (lzo-rle, 433 MB), preventing an OOM from killing the"
n "  proxy."
n "- **CPU governor pinned to performance** so the first packet after idle is not"
n "  delayed by a frequency ramp."
n "- **Passwall v1 removed.** It and passwall2 fight over the same nft redirect"
n "  rules; only passwall2 ships."
n ""
n "## Install"
n ""
n '```sh'
n "sha256sum -c sha256sums"
n [ -n "${img:-}" ] && n "sysupgrade -n $(basename "$img")"
n '```'
n ""
n "> \`-n\` discards \`/etc/config\`. Set a root password and WiFi key after flashing."
n "> Feeds are pre-configured: \`opkg update\` works out of the box."
n ""
if [ -n "${size:-}" ]; then
	n "<sub>Image size: $size</sub>"
fi
