#!/usr/bin/env bash
# Build a self-hosted opkg repository from a finished BYTE by ACE build.
#
# ImmortalWrt 25.12 publishes only apk feeds, so an opkg image has nowhere to
# `opkg update` from. This assembles the .ipk set the build already produced
# into a browsable repo with per-feed Packages indexes, laid out exactly like
# downloads.immortalwrt.org so distfeeds.conf can point at it unchanged.
#
# Output layout (served as the release's "repo" download):
#   packages/aarch64_cortex-a53/<feed>/Packages[.gz] + *.ipk
#   targets/qualcommax/ipq807x/packages/Packages[.gz] + *.ipk
#
# Usage: build-package-repo.sh <immortalwrt-dir> <out-dir> [manifest]
#
# If a manifest is given, only packages listed in it are published. bin/packages
# accumulates .ipk files from earlier builds (sing-box, AdGuardHome, hysteria,
# the removed proxy plugins), and shipping those would both bloat the repo and
# advertise packages this image deliberately drops.
set -euo pipefail

src=${1:?usage: build-package-repo.sh <immortalwrt-dir> <out-dir> [manifest]}
out=${2:?usage: build-package-repo.sh <immortalwrt-dir> <out-dir> [manifest]}
manifest=${3:-}

# On-demand allowlist: .github/repo/ondemand.txt (a directory so it can also
# hold other repo-shared data later).
repo=$(cd "$(dirname "$0")" && pwd)
[ -f "$repo/repo/ondemand.txt" ] || { echo "missing $repo/repo/ondemand.txt"; exit 1; }

if [ -n "$manifest" ] && [ -f "$manifest" ]; then
	# Manifest lines are "name - version"; the first field is the package name.
	cut -d' ' -f1 "$manifest" | LC_ALL=C sort -u > /tmp/repo-allow.$$
	echo "filtering to $(wc -l < /tmp/repo-allow.$$) packages from the image manifest"
else
	: > /tmp/repo-allow.$$
	echo "no manifest given - publishing every .ipk found"
fi
trap 'rm -f /tmp/repo-allow.$$' EXIT

want() { # <ipk path>
	local base name
	base=$(basename "$1")
	# name_version_arch.ipk; version may contain underscores, so cut at _arch
	name=${base%%_*}

	# 0) Never republish what is already in the image. opkg only needs the feed
	#    for things it does NOT have, and republishing an installed package
	#    just bloats the feed (mihomo-meta 20M, xray-core 10M, tailscale 10M
	#    are all installed) and risks an "upgrade" to the same version.
	if [ -s /tmp/repo-allow.$$ ] && grep -qx "$name" /tmp/repo-allow.$$; then
		return 1
	fi

	# 1) Kernel-pinned kmods. These MUST come from this build: a kmod built
	#    against a different kernel makes opkg refuse with "Not downgrading
	#    package kernel". Cheap (~3 MB) and CDN-friendly.
	case "$name" in
		kmod-*) return 0 ;;
	esac

	# 2) Packages that only exist in this project (not in ImmortalWrt 24.10.6):
	#    qmodem/SMS, the AW1000 phone stack, our themes and modeminfo.
	case "$name" in
		# adguardhome (the binary) must ship with luci-app-adguardhome: the UI
		# requires >=0.107.73-r3, and ImmortalWrt 24.10.6 only has 0.107.57,
		# so the 24.10.6 copy can never satisfy it. Our tree builds 0.107.79.
		adguardhome|luci-app-adguardhome|\
		qmodem|tom_modem|sms-tool_q|ubus-at-daemon|sms-forwarder|libqmodem-sms|\
		luci-app-qmodem*|luci-app-modeminfo|luci-app-aw1k-led|\
		luci-app-fxs|fxsd|kmod-aw1000-fxs|luci-app-ramfree|luci-app-cpufreq|\
		luci-app-tailscale-community|luci-app-filemanager|tailscale|\
		luci-theme-vantage|luci-app-vantage|luci-app-passwall*|\
		xray-core|geoview|nikki|mihomo-meta|luci-app-nikki)
			return 0 ;;
	esac

	# 3) Everything else - the eight apps, their lucI frontends, common
	#    userland libraries - is served by the official ImmortalWrt 24.10.6
	#    opkg feeds. Publishing our own copies here would shadow those
	#    versions, which is exactly how banip 1.9.1 got advertised with no
	#    .ipk behind it.
	return 1
}

arch_dir="$src/bin/packages/aarch64_cortex-a53"
target_dir="$src/bin/targets/qualcommax/ipq807x/packages"
[ -d "$arch_dir" ] || { echo "no $arch_dir"; exit 1; }

mkdir -p "$out/packages/aarch64_cortex-a53" "$out/targets/qualcommax/ipq807x/packages"

# apk does not exist in this image; make sure a stray .apk never ships.
if find "$arch_dir" -name '*.apk' | grep -q .; then
	echo "ERROR: .apk files present but this image is opkg-only"; exit 1
fi

# Regenerate every index from the .ipk files that are actually here, rather
# than trusting an index some feed forgot to emit (dotycat ships none).
make_index() { # <dir>
	local d=$1 n=0
	# An empty feed still needs a valid index: distfeeds.conf is generated from
	# the enabled feed list, so URL count is fixed by config, not by whether a
	# feed happens to contain packages. Serving 404 for "routing" would break
	# opkg update exactly like the dead ImmortalWrt URLs did.
	if [ -z "$(ls "$d"/*.ipk 2>/dev/null)" ]; then
		# Not literally empty: usign cannot sign a zero-byte message, and an
		# unsigned index makes opkg print "Signature file download failed"
		# for that feed. A lone comment line is a valid, signable index that
		# announces no packages.
		echo "# no packages in this feed for this build" > "$d/Packages"
		gzip -9nc "$d/Packages" > "$d/Packages.gz"
		echo "  $(basename "$d"): 0 packages (empty index)"
		return 0
	fi
	{
		for ipk in "$d"/*.ipk; do
			local tmp ctl
			tmp=$(mktemp -d)
			# Two ipk layouts exist: legacy ar(control.tar.gz, data.tar.gz)
			# and the newer gzipped tar containing ./control.tar.gz (with a
			# ./ prefix). Try the tar form first, then fall back to ar.
			if ! tar xzf "$ipk" -C "$tmp" ./control.tar.gz 2>/dev/null &&
			   ! tar xzf "$ipk" -C "$tmp" control.tar.gz 2>/dev/null; then
				( cd "$tmp" && ar x "$ipk" 2>/dev/null ) || true
			fi
			ctlf=$(ls "$tmp"/control.tar.* 2>/dev/null | head -1 || true)
			if [ -n "$ctlf" ]; then
				tar xzf "$ctlf" -C "$tmp" ./control 2>/dev/null ||
					tar xzf "$ctlf" -C "$tmp" control 2>/dev/null || true
			fi
			ctl=$(ls "$tmp"/control 2>/dev/null | head -1 || true)
			if [ -n "$ctl" ]; then
				cat "$ctl"
				echo "Filename: $(basename "$ipk")"
				echo "Size: $(stat -c%s "$ipk")"
				echo ""
				n=$((n + 1))
			fi
			rm -rf "$tmp"
		done
	} > "$d/Packages"
	if [ "$n" -gt 0 ]; then
		gzip -9nc "$d/Packages" > "$d/Packages.gz"
	fi
	echo "  $(basename "$d"): $n packages"
}

echo "indexing architecture feeds:"
for feed in "$arch_dir"/*/; do
	name=$(basename "$feed")
	mkdir -p "$out/packages/aarch64_cortex-a53/$name"
	# Work on a copy so the build tree is never mutated.
	for ipk in "$feed"/*.ipk; do
		[ -e "$ipk" ] || continue
		if want "$ipk"; then
			cp "$ipk" "$out/packages/aarch64_cortex-a53/$name/"
		fi
	done
	make_index "$out/packages/aarch64_cortex-a53/$name"
done

# Feeds that are enabled but produced no packages (routing, telephony, video)
# still appear in the generated distfeeds.conf, so give them a valid index.
# Derive the list from .config rather than hardcoding it: base-files emits a
# distfeeds line for every enabled feed, so the repo must have a directory for
# each one. Hardcoding the list is how nikki ended up enabled in the image with
# no repo directory, which opkg reports as "no such file or directory".
mapfile -t enabled_feeds < <(
	sed -n 's/^CONFIG_FEED_\([a-z0-9_]*\)=y$/\1/p' "$src/.config" 2>/dev/null | sort -u
)
[ "${#enabled_feeds[@]}" -gt 0 ] || enabled_feeds=(routing telephony video)

for name in "${enabled_feeds[@]}"; do
	d="$out/packages/aarch64_cortex-a53/$name"
	[ -d "$d" ] && continue
	mkdir -p "$d"
	make_index "$d"
done

echo "indexing target feed (kernel modules):"
if [ -d "$target_dir" ]; then
	for ipk in "$target_dir"/*.ipk; do
		[ -e "$ipk" ] || continue
		if want "$ipk"; then
			cp "$ipk" "$out/targets/qualcommax/ipq807x/packages/"
		fi
	done
	make_index "$out/targets/qualcommax/ipq807x/packages"
fi

total=$(find "$out" -name '*.ipk' | wc -l)
size=$(du -sh "$out" | cut -f1)

# Sign every Packages index. The image installs key-build.pub at
# /etc/opkg/keys/<id>, so signing with the same build key makes the repo
# verifiable on the device without shipping another trust anchor.
usign="$src/staging_dir/host/bin/usign"
keyprv="$src/key-build"
keypub="$src/key-build.pub"
keyid=""
if [ -x "$usign" ] && [ -s "$keyprv" ] && [ -s "$keypub" ]; then
	keyid=$("$usign" -F -p "$keypub")
	echo
	echo "signing indexes with build key $keyid"
	n=0
	while IFS= read -r idx; do
		# usign refuses a zero-length message, so an empty feed index stays
		# unsigned. opkg treats a missing .sig as "nothing to verify" and the
		# index has no packages, so there is nothing to protect.
		if [ -s "$idx" ]; then
			"$usign" -S -m "$idx" -s "$keyprv" -x "$idx.sig"
			n=$((n + 1))
		fi
	done < <(find "$out" -name 'Packages' -type f)
	echo "  signed $n indexes"
	# Publish the public key next to the indexes for reference.
	cp "$keypub" "$out/key-build.pub"
else
	echo
	echo "WARNING: no usign/key-build found - repo left UNSIGNED and"
	echo "         opkg will reject it unless check_signature is disabled."
fi

echo
echo "repo ready: $total packages, $size at $out${keyid:+, signed with $keyid}"
[ "$total" -gt 0 ] || { echo "ERROR: repo has no packages"; exit 1; }
