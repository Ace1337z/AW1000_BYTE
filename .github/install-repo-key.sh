#!/usr/bin/env bash
# Publish the stable opkg repo signing key into the build tree.
#
# base-files only generates key-build when it is missing
# ([ -s $(BUILD_KEY) -a -s $(BUILD_KEY).pub ] || usign -G ...), so a key that
# already exists is reused. That matters: CI clones a fresh tree every run, so
# without this the build generates a NEW key each time. The image then ships
# key-build.pub for key N while the repo published in the same run is signed
# with key N, which happens to match - but the NEXT build replaces the repo
# with a new key while devices still hold the old one, and every index fails
# with "Signature check failed". opkg still prints "Updated list", so the
# failure is silent: /var/opkg-lists ends up empty and nothing can be
# installed.
#
# Committing one key for the project keeps image and repo in agreement across
# every future build.
#
# Usage: install-repo-key.sh <immortalwrt-dir> <key-dir>
set -euo pipefail

src=${1:?usage: install-repo-key.sh <immortalwrt-dir> <key-dir>}
keydir=${2:?usage: install-repo-key.sh <immortalwrt-dir> <key-dir>}

for f in key-build key-build.pub key-build.ucert; do
	if [ ! -s "$keydir/$f" ]; then
		echo "missing $keydir/$f"
		exit 1
	fi
	# usign refuses to sign as root without this.
	chmod 600 "$src/$f" 2>/dev/null || true
	cp "$keydir/$f" "$src/$f"
done

usign="$src/staging_dir/host/bin/usign"
[ -x "$usign" ] || usign=$(command -v usign || true)

if [ -n "$usign" ] && [ -x "$usign" ]; then
	echo "installed repo signing key: $("$usign" -F -p "$src/key-build.pub")"
else
	echo "installed key-build (usign not available to print the id)"
fi