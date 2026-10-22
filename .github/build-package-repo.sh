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
	[ -s /tmp/repo-allow.$$ ] || return 0
	local base name
	base=$(basename "$1")
	# name_version_arch.ipk; version may contain underscores, so cut at _arch
	name=${base%%_*}
	grep -qx "$name" /tmp/repo-allow.$$ || return 1
	# Explicitly never publish the size-trimmed set, manifest or not.
	case "$name" in
		sing-box|adguardhome|luci-app-adguardhome|hysteria|naiveproxy| \
		xray-plugin|v2ray-plugin|luci-app-openclash|luci-theme-argon| \
		shadowsocks-rust-sslocal|shadowsocks-rust-ssserver|simple-obfs-client|ruby)
			return 1 ;;
	esac
	return 0
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
for name in routing telephony video; do
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
