#!/usr/bin/env bash
# Release body for one BYTE by ACE build.
#
# Everything identifying the build is DERIVED, never typed:
#   * the version comes from the build's own .config (CONFIG_VERSION_NUMBER and
#     CONFIG_VERSION_CODE) - the same strings the image and LuCI report;
#   * the change list is the newest block of README.md's changelog.
# A release body can therefore only describe the build it is attached to. The
# previous static text ("FINAL", kernel 6.12.112, 24.10.6 feeds) described a
# firmware from months earlier and kept being published under new tags.
#
# Usage: release-notes-final.sh <target-dir> [out-dir]
# Env:   FW_CODE, FW_RELEASE, FW_KERNEL  override the derived values
#        CONFIG_FILE                     path to the built .config
#        README                          path to the repository README.md
set -euo pipefail
dir=${1:?usage: release-notes-final.sh <target-dir> [out-dir]}
out=${2:-}

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)
readme=${README:-$repo/README.md}
cfg=${CONFIG_FILE:-$repo/immortalwrt/.config}

img=$(ls "$dir"/*squashfs-sysupgrade.bin 2>/dev/null | head -1 || true)
if [ -n "$out" ] && [ -d "$out" ]; then
	c=$(ls "$out"/*squashfs-sysupgrade.bin 2>/dev/null | head -1 || true)
	[ -n "$c" ] && img=$c
fi
size=""
[ -n "${img:-}" ] && size=$(du -h "$img" | cut -f1)
# An empty placeholder file reports "0" - do not advertise that as a size.
case "$size" in ''|0|0B|0K) size="" ;; esac

cfg_get() {
	sed -n "s/^$1=\"\{0,1\}\([^\"]*\)\"\{0,1\}$/\1/p" "$cfg" 2>/dev/null | head -1
}

num=$(cfg_get CONFIG_VERSION_NUMBER)   # 25.12.6.12.94 -> release + kernel
code=${FW_CODE:-$(cfg_get CONFIG_VERSION_CODE)}

# Fall back to the image name (byte-<num>-qualcommax-...) when .config is gone.
if [ -z "$num" ] && [ -n "${img:-}" ]; then
	num=$(basename "$img" | sed -n 's/^[^-]*-\([0-9][0-9.]*\)-qualcommax.*/\1/p')
fi

release=${FW_RELEASE:-}
kernel=${FW_KERNEL:-}
if [ -z "$release" ] && [ -n "$num" ]; then
	release=$(printf '%s' "$num" | cut -d. -f1-2)
fi
if [ -z "$kernel" ] && [ -n "$num" ]; then
	# Everything after the release pair: the kernel is a 3-part version
	# (25.12.6.12.94 -> 6.12.94), so f3-4 would drop the patch level.
	kernel=$(printf '%s' "$num" | cut -d. -f3-)
fi
release=${release:-25.12}
kernel=${kernel:-?}
code=${code:-?}

# Newest changelog block: the first "###" section under "## Changelog".
changelog=""
if [ -f "$readme" ]; then
	changelog=$(awk '
		/^## Changelog/ { inlog = 1; next }
		inlog && /^### / { if (seen) exit; seen = 1; next }
		inlog && seen && /^## / { exit }
		inlog && seen { print }
	' "$readme")
	# drop leading blank lines
	changelog=$(printf '%s\n' "$changelog" | sed '/./,$!d')
fi
# No README (tarball export): list the commits that produced this build.
if [ -z "$changelog" ]; then
	changelog=$(git -C "$repo" log --no-merges --format='- %s' -n 15 2>/dev/null || true)
fi

n() { printf '%s\n' "$@"; }

n "# BYTE ${release} VERSION ${code}"
n ""
n "Arcadyan AW1000 (\`qualcommax/ipq807x\`) · kernel ${kernel} · build ${GITHUB_RUN_NUMBER:-local}"
n ""
n "## What changed in this build"
n ""
if [ -n "$changelog" ]; then
	n "$changelog"
else
	n "_The changelog could not be read from this checkout; see the repository"
	n "README for the full engineering log._"
fi
n ""
n "## Install"
n ""
n '```sh'
n "sha256sum -c sha256sums"
if [ -n "${img:-}" ]; then
	n "sysupgrade -n $(basename "$img")"
else
	n "sysupgrade -n BYTE_by_ACE-...-squashfs-sysupgrade.bin"
fi
n '```'
n ""
n "> \`-n\` discards \`/etc/config\`. Use it when coming from another firmware;"
n "> drop it to keep settings on an upgrade from a previous BYTE image."
n "> Feeds are pre-configured: \`opkg update\` works out of the box."
n ""
n "> **Keep a recovery path before flashing** — serial console or the"
n "> initramfs image under TFTP. \`sysupgrade -n\` does not keep configuration"
n "> and an interrupted flash needs one of the two to recover."
n ""
if [ -n "${size:-}" ]; then
	n "<sub>Image size: $size</sub>"
fi
