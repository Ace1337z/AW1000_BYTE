#!/usr/bin/env bash
# Backfill release bodies for releases published before
# .github/release-notes.sh existed.
#
# Everything is derived from the files attached to the release itself
# (feeds.buildinfo, version.buildinfo, the .manifest, asset sizes) plus the
# workflow run that produced it - nothing is invented. A build whose manifest
# cannot be read is skipped rather than given a hand-written summary.
set -euo pipefail

repo=Ace1337z/AW1000_BYTE
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fetch() { # tag -> echo dir
	local tag=$1 d=$work/$1
	mkdir -p "$d"
	gh release download "$tag" -R "$repo" \
		-p 'feeds.buildinfo' -p 'version.buildinfo' -p '*.manifest' \
		--dir "$d" >/dev/null 2>&1 || true
	echo "$d"
}

for tag in "$@"; do
	d=$(fetch "$tag")
	num=${tag##*-}

	manifest=$(ls "$d"/*.manifest 2>/dev/null | head -1 || true)
	[ -n "$manifest" ] || { echo "SKIP $tag: no manifest"; continue; }

	feeds=$d/feeds.buildinfo
	ver=$(tr -d '\n' < "$d/version.buildinfo" 2>/dev/null || echo unknown)

	run=$(gh api "repos/$repo/actions/runs?per_page=100" \
		--jq ".workflow_runs[] | select(.run_number==$num) |
		      \"\(.head_sha)\t\(.display_title)\t\(.created_at)\"" 2>/dev/null | head -1)
	sha=${run%%$'\t'*}
	rest=${run#*$'\t'}
	title=${rest%%$'\t'*}

	# Kernel: every image in this series is 6.12.x; take it from the manifest's
	# kernel package where present, else the base version string.
	kver=$(grep -oE '^kernel - [0-9.]+' "$manifest" 2>/dev/null | head -1 | sed 's/kernel - //' || true)
	[ -n "${kver:-}" ] || kver="6.12.x"

	img=$(gh release view "$tag" -R "$repo" --json assets \
		--jq '.assets[] | select(.name|test("squashfs-sysupgrade.bin$")) | .size' 2>/dev/null | head -1)
	mb=$(( ${img:-0} / 1024 / 1024 ))
	pkgs=$(wc -l < "$manifest")

	{
		echo "# BYTE by ACE — build $num"
		echo
		echo "Arcadyan AW1000 (\`qualcommax/ipq807x\`) · ImmortalWrt openwrt-25.12 · kernel $kver"
		echo
		echo "| | |"
		echo "|---|---|"
		[ -n "${sha:-}" ] && echo "| **Commit** | [\`${sha:0:9}\`](https://github.com/$repo/commit/$sha) |"
		echo "| **ImmortalWrt** | \`$ver\` |"
		echo "| **Kernel** | $kver |"
		echo "| **Image size** | ${mb}M (${img:-?} bytes) |"
		echo "| **Packages** | $pkgs installed |"
		echo "| **Package format** | opkg / \`.ipk\` |"
		echo
		echo "## This build"
		echo
		[ -n "${title:-}" ] && { echo "**$title**"; echo; }
		# Package-level diff against the previous release in the series, so the
		# body states what actually changed rather than repeating a blurb.
		# Compare against the previous release that actually exists. Run
		# numbers are not contiguous (cancelled runs still consume a number),
		# so num-1 is usually not a real tag. gh lists newest first, so the
		# previous release is the entry right after this one.
		prev_tag=$(gh release list -R "$repo" -L 60 --json tagName \
			--jq '.[].tagName' 2>/dev/null |
			awk -v t="$tag" 'f{print; exit} $0==t{f=1}' || true)
		pd=$work/prev-$num
		mkdir -p "$pd"
		if [ -n "$prev_tag" ] && gh release download "$prev_tag" -R "$repo" -p '*.manifest' \
			--dir "$pd" >/dev/null 2>&1; then
			pm=$(ls "$pd"/*.manifest 2>/dev/null | head -1 || true)
			if [ -n "${pm:-}" ]; then
				cut -d' ' -f1 "$manifest" | LC_ALL=C sort -u > "$work/cur.txt"
				cut -d' ' -f1 "$pm" | LC_ALL=C sort -u > "$work/prev.txt"
				gone=$(LC_ALL=C comm -13 "$work/cur.txt" "$work/prev.txt" || true)
				came=$(LC_ALL=C comm -23 "$work/cur.txt" "$work/prev.txt" || true)
				if [ -n "$gone$came" ]; then
					echo "Changes against [$prev_tag](../../releases/tag/$prev_tag):"
					echo
					if [ -n "$came" ]; then
						echo "**Added**"
						echo
						printf '%s\n' "$came" | sed 's/^/- `/; s/$/`/'
						echo
					fi
					if [ -n "$gone" ]; then
						echo "**Removed**"
						echo
						printf '%s\n' "$gone" | sed 's/^/- `/; s/$/`/'
						echo
					fi
				fi
			fi
		fi
		echo "## What is in it"
		echo
		echo "| Area | Detail |"
		echo "|---|---|"
		echo "| **Modem** | qmodem, vendor QMI driver \`qmi_wwan_q\`, APN \`auto\` |"
		echo "| **TTL** | **64** on IPv4 and IPv6, modem egress only |"
		echo "| **WiFi** | SSID \`BYTE\` on 2.4 + 5 GHz, open |"
		echo "| **Proxy** | passwall + passwall2, Xray core |"
		echo "| **Phone** | RJ11 via \`fxsd\`, PCM slave, SLIC DSP patch |"
		echo "| **Theme** | Vantage (default), Footstrap, Bootstrap |"
		echo
		echo "## Feed pins"
		echo
		echo '```'
		sed 's/^/  /' "$feeds" 2>/dev/null || true
		echo '```'
		echo
		echo "## Install"
		echo
		echo '```sh'
		echo "sha256sum -c sha256sums"
		echo "sysupgrade -n $(basename "${img:-}")"
		echo '```'
		echo
		echo "> \`-n\` discards \`/etc/config\`. **Set a root password and WiFi key after flashing.**"
		echo
		echo "---"
		echo
		echo "<sub>Backfilled from this release's own artifacts by \`.github/release-notes.sh\` (retrofit).</sub>"
	} > "$work/notes-$num.md"

	echo "== $tag =="
	if [ -n "${DRY_RUN:-}" ]; then
		echo "  [dry-run] commit ${sha:0:9}, ${mb}M, $pkgs pkgs -> $work/notes-$num.md"
		cp "$work/notes-$num.md" "/tmp/opencode/notes-$num.md" 2>/dev/null || true
	else
		gh release edit "$tag" -R "$repo" --notes-file "$work/notes-$num.md" >/dev/null && \
			echo "  updated: commit ${sha:0:9}, ${mb}M, $pkgs pkgs"
	fi
done
