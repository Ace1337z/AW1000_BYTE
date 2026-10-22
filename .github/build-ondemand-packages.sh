#!/usr/bin/env bash
# Build the on-demand packages into bin/packages WITHOUT adding them to the
# image.
#
# The image is filtered by .config, so packages that are not selected are never
# built and therefore cannot be published in the opkg repo. Enabling them in
# .config would put them in the firmware, which is exactly what we do not want:
# OpenClash alone would roughly double a 43 MB image and its redirect rules
# can bypass the nftables TTL chain.
#
# So: enable the set, build it, then restore .config. The resulting .ipk files
# stay in bin/packages and build-package-repo.sh picks them up via
# .github/repo/ondemand.txt.
#
# Usage: build-ondemand-packages.sh <immortalwrt-dir>
set -euo pipefail

src=${1:?usage: build-ondemand-packages.sh <immortalwrt-dir>}
here=$(cd "$(dirname "$0")" && pwd)
list="$here/repo/ondemand.txt"
[ -f "$list" ] || { echo "missing $list"; exit 1; }

cd "$src"

# Packages live either in a feed (package/feeds/<feed>/<name>, a symlink) or
# in-tree (package/network/utils/...). Entries under package/feeds/<name> that
# are plain files are feed indexes, not packages, hence -mindepth 2.
# Many packages are sub-packages: declared inside a parent Makefile with no
# directory of their own (iptables-nft lives in package/network/utils/iptables,
# kmod-ifb in package/kernel/modules/net-sched). So a name search alone misses
# them; fall back to grepping for "define Package/<name>".
pkg_path() {
	local p=$1 d
	for d in $(find package/feeds -mindepth 2 -maxdepth 2 -name "$p" 2>/dev/null); do
		[ -d "$d" ] && echo "$d"
	done
	[ -d "package/$p" ] && echo "package/$p"
	[ -d "package/kernel/$p" ] && echo "package/kernel/$p"
	[ -d "package/kernel/modules/$p" ] && echo "package/kernel/modules/$p"
	local mk
	for mk in $(grep -rl "^define Package/${p}\$" \
			--include=Makefile package 2>/dev/null); do
		echo "$(dirname "$mk")"
	done | sort -u
}

# Save the image config so the firmware build is unaffected.
backup=$(mktemp)
cp .config "$backup"
restore() { cp "$backup" .config; rm -f "$backup"; }
trap restore EXIT

echo "=== enabling on-demand packages (build only, not for the image) ==="
added=0
while read -r p; do
	case "$p" in ''|\#*) continue ;; esac
	# Selecting a package that does not exist in any feed would fail defconfig.
	# Resolved packages live at package/feeds/<feed>/<name>. Entries there are
	# symlinks into feeds/, so do NOT filter on -type d (it excludes them all).
	# Note package/feeds/<name> also exists as a plain file (the feed index),
	# hence -mindepth 2.
	if [ -z "$(pkg_path "$p")" ]; then
		echo "  skip $p (not in any feed)"
		continue
	fi
	if grep -q "^CONFIG_PACKAGE_${p}=y$" .config; then continue; fi
	sed -i "/^# CONFIG_PACKAGE_${p} is not set$/d" .config
	echo "CONFIG_PACKAGE_${p}=y" >> .config
	echo "  + $p"
	added=$((added + 1))
done < "$list"
echo "  $added package(s) enabled for build"

[ "$added" -gt 0 ] || { echo "nothing to do"; exit 0; }

make defconfig >/dev/null 2>&1 || true

# Build everything just enabled. Building by feed target keeps this bounded.
echo
echo "=== building ==="
targets=""
for p in $(grep -vE '^\s*(#|$)' "$list"); do
	for d in $(pkg_path "$p"); do
		targets="$targets ${d}/compile"
	done
done
targets=$(printf '%s\n' $targets | sort -u | tr '\n' ' ')
echo "targets:$(echo "$targets" | wc -w)"
# shellcheck disable=SC2086
make $targets -j"$(nproc)" 2>&1 | grep -iE "^ERROR|error:|\*\*\*" | head -20 || true

built=$(find bin/packages -name '*.ipk' -newer "$backup" 2>/dev/null | wc -l)
echo
echo "=== done: $built new .ipk ==="
find bin/packages -name '*.ipk' -newer "$backup" 2>/dev/null |
	sed 's|.*/||' | sort | head -40

restore
trap - EXIT
echo
echo "image .config restored ($(grep -c '^CONFIG_PACKAGE_.*=y$' .config) packages selected)"