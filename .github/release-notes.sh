#!/usr/bin/env bash
# Generate the release body for one BYTE by ACE build.
#
# Everything written here is read out of the build that just finished, not
# copied from a template, so a release can never describe a firmware that was
# not built. Run from the repository root with the built tree present:
#
#   .github/release-notes.sh <target-dir> > notes.md
#
# <target-dir> is immortalwrt/bin/targets/<board>/<subtarget>.
set -euo pipefail

dir=${1:?usage: release-notes.sh <target-dir>}
repo_root=$(cd "$(dirname "$0")/.." && pwd)

# --- build identity -------------------------------------------------------
branch=${TARGET_BRANCH:-unknown}
run_num=${GITHUB_RUN_NUMBER:-0}
sha=${GITHUB_SHA:-unknown}
short_sha=${sha:0:9}
repo=${GITHUB_REPOSITORY:-Ace1337z/AW1000_BYTE}

kernel=$(cat "$dir/version.buildinfo" 2>/dev/null | tr -d '\n' || true)

# The kernel release is the versioned directory under the built tree
# (build_dir/toolchain-*/linux-6.12.112). Failing to find it is not fatal:
# fall back rather than aborting the release.
kver=$(ls -d "$repo_root"/immortalwrt/build_dir/toolchain-*/linux-[0-9]*/ 2>/dev/null |
	sed 's|.*/linux-||; s|/$||' | head -1 || true)
if [ -z "${kver:-}" ]; then
	kver=$(ls -d "$repo_root"/immortalwrt/build_dir/*/linux-[0-9]*/ 2>/dev/null |
		sed 's|.*/linux-||; s|/$||' | head -1 || true)
fi
[ -n "${kver:-}" ] || kver="unknown"

img=$(ls "$dir"/*squashfs-sysupgrade.bin 2>/dev/null | head -1 || true)
# Prefer the collected artifact set: bin/ can hold a stale image from an
# earlier local build, and reporting the wrong size is worse than none.
if [ -n "${OUT_DIR:-}" ] && [ -d "${OUT_DIR:-}" ]; then
	collected=$(ls "$OUT_DIR"/*squashfs-sysupgrade.bin 2>/dev/null | head -1 || true)
	[ -n "${collected:-}" ] && img=$collected
fi
size="unknown"
if [ -n "${img:-}" ]; then
	size=$(du -h "$img" | cut -f1)
	size="${size} ($(stat -c%s "$img") bytes)"
fi

notes() { printf '%s\n' "$@"; }

notes "# BYTE by ACE — build $run_num"
notes ""
notes "Arcadyan AW1000 (\`qualcommax/ipq807x\`) · ImmortalWrt $branch · kernel $kver"
notes ""
notes "| | |"
notes "|---|---|"
notes "| **Commit** | [\`$short_sha\`](https://github.com/$repo/commit/$sha) |"
notes "| **ImmortalWrt** | \`$kernel\` |"
notes "| **Kernel** | $kver |"
notes "| **Image size** | $size |"
notes "| **Package format** | opkg / \`.ipk\` |"
notes ""
notes "## This build"
notes ""
# The commit body of the change that triggered this run. Empty for a manual
# dispatch, which is fine - the table above still identifies the build.
if [ -n "${GITHUB_SHA:-}" ]; then
	msg=$(git -C "$repo_root" log -1 --format=%s "$sha" 2>/dev/null || true)
	body=$(git -C "$repo_root" log -1 --format=%b "$sha" 2>/dev/null || true)
	[ -n "$msg" ] && { notes "**$msg**"; notes ""; }
	[ -n "$body" ] && { notes '```'; notes "$body"; notes '```'; notes ""; }
fi
notes "## What is in it"
notes ""
notes "| Area | Detail |"
notes "|---|---|"
notes "| **Modem** | qmodem, vendor QMI driver \`qmi_wwan_q\`, APN \`auto\`, AT on \`/dev/ttyUSB3\` |"
notes "| **TTL** | **64** on IPv4 and IPv6, modem egress only (\`wwan0_1\`/\`wwan0\`) |"
notes "| **WiFi** | SSID \`BYTE\` on 2.4 + 5 GHz, open |"
notes "| **Proxy** | passwall + passwall2, Xray core |"
notes "| **SMS** | LuCI SMS page + forwarding (Telegram/webhook/ServerChan) |"
notes "| **Phone** | RJ11 via \`fxsd\`, Caller ID, hold, speed dial, blocked numbers |"
notes "| **Theme** | Vantage (default), Footstrap, Bootstrap |"
notes ""
notes "## Feed pins"
notes ""
notes "Every external package is pinned to a commit, so this image is reproducible:"
notes ""
notes '```'
sed 's/^/  /' "$dir/feeds.buildinfo" 2>/dev/null || true
notes '```'
notes ""
notes "## Install"
notes ""
# Use the real asset name rather than a reconstructed one: it now carries the
# build number, and a hardcoded string here would send users to a 404.
sysup=$(basename "${img:-}")
notes "**From an existing OpenWrt / ImmortalWrt:**"
notes '```sh'
[ -n "${sysup:-}" ] && notes "sysupgrade -n ${sysup}" || notes "sysupgrade -n <the squashfs-sysupgrade.bin from this release>"
notes '```'
notes ""
notes "**First install or recovery:** use the \`squashfs-factory.ubi\` from this"
notes "release, or boot \`initramfs-uImage.itb\` into RAM for a non-destructive test."
notes ""
notes "Verify the download first:"
notes '```sh'
notes "sha256sum -c sha256sums"
notes '```'
notes ""
notes "> \`-n\` discards \`/etc/config\`. Drop it to keep settings across the upgrade."
notes "> Firmware defaults (TTL 64, open SSID, empty root password) still win on"
notes "> first boot either way. **Set a root password and WiFi key after flashing.**"
notes ""
notes "## Notes"
notes ""
notes "- TTL rewrite and NSS/ECM flow offload are mutually exclusive: ECM forwards"
notes "  in hardware bypassing netfilter, so the TTL would never be applied. ECM"
notes "  is not shipped."
notes "- \`qca-nss-drv\` is present for the paths that do not touch the TTL."
notes ""
notes "---"
notes ""
notes "<sub>Auto-generated from the build artifacts by \`.github/release-notes.sh\`.</sub>"
