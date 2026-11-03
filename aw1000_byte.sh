#!/bin/bash
set -e

# Absolute path of this script. NOTE: `realpath "$0"` is wrong here - when the
# script is started as `bash aw1000_byte.sh`, $0 is "aw1000_byte.sh" and
# realpath returns ".../builder/aw1000_byte.sh" only if the file exists at that
# exact relative path, but under some invocations $0 is the interpreter name.
# Use the containing directory instead, which is what every caller needs.
script_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
[ -n "$script_dir" ] || script_dir="$(pwd)"
script_path="$script_dir/$(basename "$0")"

RESET='\033[0m'
BOLD='\033[1m'
RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'
BLUE='\033[34m'; MAGENTA='\033[35m'
BOLD_RED="${BOLD}${RED}"
BOLD_GREEN="${BOLD}${GREEN}"
BOLD_YELLOW="${BOLD}${YELLOW}"
BOLD_BLUE="${BOLD}${BLUE}"
BOLD_MAGENTA="${BOLD}${MAGENTA}"

# Stable opkg repo signing key, copied into the build tree immediately after
# the ImmortalWrt clone.
#
# base-files only runs usign -G when key-build is missing, so a key that is
# already there is reused. That matters across builds: CI clones a fresh tree
# every run, so without this each run invents a new key. The image then ships
# key N while the published repo is re-signed with key N+1 on the next run,
# devices keep key N, and opkg prints "Updated list" while discarding every
# index -- a silent, total repo failure.
#
# This lives here, not in a workflow step, because the tree does not exist
# until the clone below. A workflow step that copied into immortalwrt/ before
# the clone failed with
#   cp: cannot create regular file 'builder/immortalwrt/key-build': No such file or directory
# on any run whose cache restore did not pre-create the directory (i.e. always
# on a cold cache), and skipped the whole build.
install_repo_key() {
    local keydir="$script_dir/repo-key" f
    if [ ! -d "$keydir" ]; then
        echo -e "${BOLD_YELLOW}NO repo-key/ IN TREE: base-files will generate a key (local build)${RESET}"
        return 0
    fi
    for f in key-build key-build.pub key-build.ucert; do
        [ -s "$keydir/$f" ] || {
            echo -e "${BOLD_RED}REPO KEY INCOMPLETE: missing $keydir/$f${RESET}"
            return 1
        }
    done
    for f in key-build key-build.pub key-build.ucert; do
        cp -f "$keydir/$f" "$distro/$f" || return 1
    done
    # usign refuses to sign as root unless the private key is 0600.
    chmod 600 "$distro/key-build" 2>/dev/null || true
    chmod 644 "$distro/key-build.pub" "$distro/key-build.ucert" 2>/dev/null || true
    echo -e "${BOLD_GREEN}REPO SIGNING KEY INSTALLED${RESET}"
}

main_menu() {
    clear 2>/dev/null || true
    echo -e "${BOLD_MAGENTA}##############################################${RESET}"
    echo -e "${BOLD_MAGENTA}          BYTE by ACE BUILD MENU                ${RESET}"
    echo -e "${BOLD_MAGENTA}##############################################${RESET}"
    echo -e "${BOLD_BLUE}DISTRO: IMMORTALWRT${RESET}"
    echo -e "${BOLD_BLUE}BUILD MENU:${RESET}"

    distro="immortalwrt"
    repo="https://github.com/immortalwrt/immortalwrt.git"
    preset_repo="https://github.com/Ace1337z/AW1000_BYTE.git"
    preset_folder="aw1000_byte"
    # ImmortalWrt release tag v25.12.1 = kernel 6.12.94.
    # Chosen for two hardware reasons, not fashion:
    #   - the AW1000 phone (openwrt-aw1000-phone v0.7.0) publishes and validates
    #     its kmod against 6.12.94 (OpenWrt 25.12.5 / NoobWRT rj11 images), and
    #     the FXS driver is built in-tree here, so the kernel must be one its
    #     maintainer actually tests;
    #   - if qca-nss-ecm is ever enabled, its 6.12 port was written against the
    #     .9x series (the .112 bonding/notifier change is what broke it).
    # Override with TARGET_BRANCH=openwrt-25.12 (6.12.112) or v25.12.2 (6.12.103).
    target_branch="${TARGET_BRANCH:-v25.12.1}"

    deps=(
        ack antlr3 asciidoc autoconf automake autopoint binutils bison build-essential
        bzip2 ccache clang cmake cpio curl device-tree-compiler ecj fastjar flex gawk gettext
        gcc-multilib g++-multilib git gnutls-dev gperf haveged help2man intltool lib32gcc-s1
        libc6-dev-i386 libelf-dev libglib2.0-dev libgmp3-dev libltdl-dev libmpc-dev libmpfr-dev
        libncurses-dev libpython3-dev libreadline-dev libssl-dev libtool libyaml-dev libz-dev
        lld llvm lrzsz mkisofs msmtp nano ninja-build p7zip p7zip-full patch pkgconf python3
        python3-pip python3-ply python3-docutils python3-pyelftools qemu-utils re2c rsync scons
        squashfs-tools subversion swig texinfo uglifyjs upx-ucl unzip vim wget xmlto xxd zlib1g-dev zstd
    )

    SUDO=$(command -v sudo &>/dev/null && echo "sudo" || echo "")

    echo -e "${BOLD_YELLOW}UPDATING SYSTEM PACKAGES${RESET}"
    if [ -n "$CI" ]; then
        # CI runners are ephemeral: skip the full-upgrade, keep the dep install.
        $SUDO apt-get update -y || {
            echo -e "${BOLD_RED}ERROR: APT UPDATE FAILED${RESET}"
            exit 1
        }
    else
        $SUDO apt update -y && $SUDO apt full-upgrade -y || {
            echo -e "${BOLD_RED}ERROR: SYSTEM UPDATE FAILED${RESET}"
            exit 1
        }
    fi

    echo -e "${BOLD_YELLOW}INSTALLING DEPENDENCIES FOR ${distro^^}${RESET}"
    $SUDO apt install -y "${deps[@]}" || {
        echo -e "${BOLD_RED}ERROR: FAILED TO INSTALL DEPENDENCIES${RESET}"
        exit 1
    }

    echo -e "${BOLD_GREEN}DEPENDENCIES INSTALLED SUCCESSFULLY${RESET}"

    if [ ! -d "$distro" ]; then
        echo -e "${BOLD_YELLOW}CLONING REPO: $repo INTO $distro${RESET}"
        # Fetch all branches: CI targets the ImmortalWrt release branch (e.g.
        # openwrt-25.12), which is not the clone's default branch (main).
        git clone --no-single-branch "$repo" "$distro" || {
            echo -e "${BOLD_RED}GIT CLONE FAILED. EXITING${RESET}"
            exit 1
        }
        echo -e "${BOLD_GREEN}REPO CLONED SUCCESSFULLY${RESET}"
        just_cloned=1
    else
        echo -e "${BOLD_GREEN}DIRECTORY '$distro' ALREADY EXISTS. SKIPPING CLONE${RESET}"
        just_cloned=0
    fi
    # Must run after the clone: the key is copied *into* the tree.
    install_repo_key || {
        echo -e "${BOLD_RED}REPO KEY INSTALL FAILED${RESET}"
        exit 1
    }
}

update_feeds() {
    echo -e "${BOLD_YELLOW}ADDING EXTERNAL FEEDS (QMODEM, PASSWALL2, NSS, FXS)${RESET}"
    # qmodem: modem management (replaces 3ginfo/modemband/sms-tool-js).
    # Pinned to main @ b4effcda (2026-11-02), upstream version 3.4.0_rc3.
    # Why not the v3.4.0_rc3.1 tag: AW1000 voice support (qmodem-voip audio
    # profile for the Quectel RG500Q-EA over /var/run/fxsd/pcm.sock) came in
    # FUjr/QModem#290, which is only in main - the tag's modem_supports.json
    # has no RG500Q-EA entry at all, so qmodem_voip refuses to start on this
    # board. There is no plain v3.4.0 tag yet; main is the only pin that
    # carries both qmodem-sipd and the AW1000 profile.
    # at-daemon is versioned by ../../version.mk (QMODEM_VERSION), so this pin
    # is also what satisfies the >= 3.4.0 requirement of QModem voice/fxsd.
    # The WAN interface stays a plain proto=dhcp on wwan0_1 (files/etc/config/
    # network). 3.4.0 ships a qmodem_runtime netifd protocol again, but nothing
    # in BYTE uses it: one owner of the WAN interface, and quectel-CM already
    # brings the data session up.
    # 3.4.0 also moved the dial/driver menu options from luci-app-qmodem to the
    # qmodem package (PACKAGE_luci-app-qmodem_* -> PACKAGE_qmodem_*), and
    # luci-app-qmodem-sms now pulls the event-driven qmodem-smsd stack
    # (qmodem-smsd, qmodem-settings, libqmodem-sms, sms-forwarder-next).
    sed -i '\#^src-git qmodem #d' feeds.conf.default 2>/dev/null
    echo 'src-git qmodem https://github.com/FUjr/QModem.git^b4effcdaa7f73b26b27f01a8cca3c31f8e98be26' >> feeds.conf.default
    # passwall2 luci app, pinned to 26.4.10 (4b4b84dc1) - the version proven
    # working on the DOTYWRT AW1000. Newer passwall2 hardcodes
    # xray_min_version="26.7.11" AND injects version.min into every generated
    # config, which makes older xray refuse to start; 26.4.10 has neither.
    grep -q '^src-git passwall_luci ' feeds.conf.default 2>/dev/null || \
        echo 'src-git passwall_luci https://github.com/Openwrt-Passwall/openwrt-passwall2.git^4b4b84dc120bb37592ea51e7107ce4fe0083420f' >> feeds.conf.default
    # PassWall v1 has NO feed line on purpose: it is vendored at
    # packages/luci-app-passwall (4.66-8) and only built on demand, because v1
    # and v2 fight over the same transparent-proxy rules and port 53. Adding a
    # src-git for it would put a second, differently-versioned luci-app-passwall
    # into the feed metadata and invite `opkg upgrade` to swap the vendored
    # copy for an upstream one (that is exactly what happened to qmodem's TTL
    # script). packages/ is copied into ./package/, which wins over feeds for
    # the in-tree name.
    # vantage theme + dashboard: dropped. The image ships Footstrap only -
    # keeping a second JS theme costs space and its luci-app-vantage dashboard
    # duplicates pages the Vantage-derived widgets now provide.
    sed -i '\#^src-git vantage #d' feeds.conf.default 2>/dev/null
    # luci feed: pinned to  2026-10-10  (350fc919675b) - the first 25.12-series
    # commit that carries the dashboard widget API. The widgets under
    # files/www/.../view/dashboard/include/ require view/dashboard/lib/{charts,
    # history,layout,system,widgets}.js and the cards|charts|tabs slot layout,
    # which landed on 2026-09-24 (ee2fe5b961b5). On an older pin the require
    # rejects, the widget's load() catch sets failed=true and the dashboard
    # silently falls back to the stock Router/LAN/WiFi sections.
    sed -i -E 's#^(src-git luci https://github\.com/immortalwrt/luci\.git)\^[0-9a-f]+#\1^350fc919675bb62e415927afff65697fcb8f775d#' feeds.conf.default
    # Footstrap theme: upstream standalone repo at v0.14.19 (b9967e43c5ec,
    # 2026-11-01) instead of the luci feed's copy, which is a divergent older
    # lineage (fs-appearance.js / menu-footstrap-common.js, no styles/ tree)
    # and lags the theme author's releases by months.
    # Order is load-bearing: scripts/feeds resolves a source name that exists
    # in two feeds by feed order, and only the first one is installed - the
    # other is skipped silently. Inserting before the luci line makes this repo
    # win; appending it would leave the image on the luci feed's copy.
    sed -i '\#^src-git footstrap #d' feeds.conf.default 2>/dev/null
    sed -i '/^src-git luci /i src-git footstrap https://github.com/VizzleTF/luci-theme-footstrap.git^b9967e43c5ec09aec0771cfeecde35525640fd9d' feeds.conf.default
    sed -i '\#^src-git fxs #d' feeds.conf.default 2>/dev/null
    # NSS offload: qca-nss-drv + qca-nss-ecm (QSDK 12.5, kernel 6.12 patches)
    grep -q '^src-git nss ' feeds.conf.default 2>/dev/null || \
        echo 'src-git nss https://github.com/qosmio/nss-packages.git;NSS-12.5-K6.x' >> feeds.conf.default
    # AW1000 RJ11 phone port: kmod-aw1000-fxs, fxsd, luci-app-fxs (packages live in openwrt/).
    # Upstream v0.7.0 publishes kmod-aw1000-fxs-6.12.94.0.3.0-r1, i.e. the
    # driver is tested against kernel 6.12.94 - the kernel of tag v25.12.1,
    # which is this build's default. Do not move the default without moving
    # that pin: the in-tree kmod is built against the image kernel, so a kernel
    # outside .94 is unverified for the SLIC.
    # Upstream, pinned to v0.7.0 (a764a2d39): adds SIP calling through QModem
    # voice (off by default), HD wideband audio, caller-ID modes, ring patterns,
    # do-not-disturb and call-history retention. The kernel driver stays 0.3.0.
    # Pinned by full 40-char SHA: an abbreviated one makes src-git fail with
    # "couldn't find remote ref".
    echo 'src-git fxs https://github.com/Perz3us/openwrt-aw1000-phone.git^a764a2d3934a1aeeeab74f30160994e6a1c5ffe3' >> feeds.conf.default
    # dotycat packages: luci-app-dstore, luci-app-nssinfo, ... (aw1k-led is
    # removed below, see apply_preset).
    grep -q '^src-git dotycat ' feeds.conf.default 2>/dev/null || \
        echo 'src-git dotycat https://github.com/dotywrt/dotycat-package.git;dotycat' >> feeds.conf.default
    # Nikki: mihomo-based transparent proxy (luci-app-nikki, mihomo-meta,
    # mihomo-alpha). Not shipped in the image - built for the self-hosted opkg
    # repo so it can be installed on demand. Pinned by full 40-char SHA:
    # an abbreviated SHA makes src-git fail with "couldn't find remote ref".
    grep -q '^src-git nikki ' feeds.conf.default 2>/dev/null || \
        echo 'src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git^78e1a751d55ed0762811f054ee699049473da7b8' >> feeds.conf.default
    # luci-app-modeminfo is vendored as a local package (its repo has a
    # root-level Makefile that the feeds scanner cannot index); see packages/.
    # luci-theme-footstrap is NOT vendored: it comes from the pinned upstream
    # feed added above, and its Makefile includes $(TOPDIR)/feeds/luci/luci.mk,
    # so the luci feed must stay in feeds.conf.default.

    echo -e "${BOLD_YELLOW}UPDATING FEEDS${RESET}"
    ./scripts/feeds update -a && ./scripts/feeds install -a || {
        echo -e "${BOLD_RED}ERROR: FEEDS UPDATE FAILED${RESET}"
        return 1
    }

    # Interactive only: let the user edit feeds and re-run.
    if [ -z "$CI" ]; then
        read -rp "${BOLD_BLUE}EDIT FEEDS IF NEEDED, THEN PRESS ENTER TO CONTINUE: ${RESET}"
        ./scripts/feeds update -a && ./scripts/feeds install -a || {
            echo -e "${BOLD_RED}ERROR: FEEDS INSTALL FAILED AFTER EDIT${RESET}"
            return 1
        }
    fi

    echo -e "${BOLD_GREEN}FEEDS UPDATED SUCCESSFULLY${RESET}"
}

select_target() {
    echo -e "${BOLD_BLUE}AVAILABLE BRANCHES:${RESET}"
    git branch -a
    echo -e "${BOLD_BLUE}AVAILABLE TAGS:${RESET}"
    git tag | sort -V

    # Non-interactive when TARGET_BRANCH is set (CI); otherwise prompt.
    if [ -n "$target_branch" ]; then
        if git checkout "$target_branch" &>/dev/null; then
            echo -e "${BOLD_GREEN}CHECKED OUT TO ${target_branch}${RESET}"
            return 0
        fi
        # The directory may pre-exist (reused CI workspace / interrupted run)
        # without the target branch fetched. Fetch it, then retry the checkout.
        echo -e "${BOLD_YELLOW}BRANCH ${target_branch} NOT PRESENT - FETCHING${RESET}"
        if git fetch --depth 1 origin "$target_branch" &>/dev/null && \
           git checkout "$target_branch" &>/dev/null; then
            echo -e "${BOLD_GREEN}FETCHED AND CHECKED OUT TO ${target_branch}${RESET}"
            return 0
        fi
        # A stale/shallow leftover clone cannot reach the target branch.
        # Throw it away and start over with a clean full clone (--no-single-branch
        # pulls every branch, so openwrt-25.12 is guaranteed on the first clone).
        echo -e "${BOLD_YELLOW}STALE CLONE WITHOUT ${target_branch}; RECLONING ${distro}${RESET}"
        cd .. || exit 1
        rm -rf "$distro"
        git clone --no-single-branch "$repo" "$distro" || {
            echo -e "${BOLD_RED}RECLONE FAILED. EXITING${RESET}"
            exit 1
        }
        cd "$distro" || exit 1
        git checkout "$target_branch" &>/dev/null || {
            echo -e "${BOLD_RED}CHECKOUT FAILED AFTER RECLONE: ${target_branch}${RESET}"
            exit 1
        }
        echo -e "${BOLD_GREEN}RECLONED AND CHECKED OUT TO ${target_branch}${RESET}"
        return 0
    fi

    while true; do
        read -rp "${BOLD_BLUE}ENTER BRANCH OR TAG TO CHECKOUT: ${RESET}" target_tag
        if git checkout "$target_tag" &>/dev/null; then
            echo -e "${BOLD_GREEN}CHECKED OUT TO ${target_tag}${RESET}"
            break
        else
            echo -e "${BOLD_RED}INVALID BRANCH OR TAG: ${target_tag}${RESET}"
        fi
    done
}

apply_preset() {
    echo -e "${BOLD_YELLOW}CLEANING OLD PRESET AND CONFIG${RESET}"
    rm -rf ./files .config
    # Remove a previously cloned preset dir, but never the repo we are running from.
    if [ -d "$preset_folder" ] && [ "$(realpath "$preset_folder")" != "$(realpath "$script_dir")" ]; then
        rm -rf "$preset_folder"
    fi

    # When run from a checkout of this repo (CI), use the local preset/files.
    if [ -f "$script_dir/preset" ] && [ -d "$script_dir/files" ]; then
        preset_folder="$(realpath "$script_dir")"
        echo -e "${BOLD_GREEN}USING LOCAL PRESET: $preset_folder${RESET}"
    else
        echo -e "${BOLD_YELLOW}CLONING PRESET FROM $preset_repo${RESET}"
        if ! git clone "$preset_repo" "$preset_folder"; then
            echo -e "${BOLD_RED}FAILED TO CLONE PRESET${RESET}"
            exit 1
        fi
        echo -e "${BOLD_GREEN}PRESET CLONED${RESET}"
    fi

    cp -r "$preset_folder/files" ./ 2>/dev/null && \
        echo -e "${BOLD_GREEN}FILES COPIED${RESET}" || \
        echo -e "${BOLD_RED}FILES NOT FOUND OR FAILED TO COPY${RESET}"
    # Local vendored packages (e.g. luci-app-modeminfo) copied into the tree.
    if [ -d "$preset_folder/packages" ]; then
        cp -r "$preset_folder/packages/." ./package/ && \
            echo -e "${BOLD_GREEN}LOCAL PACKAGES COPIED${RESET}" || \
            echo -e "${BOLD_RED}LOCAL PACKAGE COPY FAILED${RESET}"
    fi
    # NSS kernel patches + DTS files (target/linux/qualcommax overlay)
    if [ -d "$preset_folder/nss" ]; then
        cp -r "$preset_folder/nss/." ./ && \
            echo -e "${BOLD_GREEN}NSS PATCHES APPLIED${RESET}" || \
            echo -e "${BOLD_RED}NSS PATCH COPY FAILED${RESET}"
    fi
    cp "$preset_folder/preset" .config 2>/dev/null && \
        echo -e "${BOLD_GREEN}PRESET APPLIED${RESET}" || \
        echo -e "${BOLD_RED}WARNING: PRESET NOT FOUND${RESET}"

    # Firmware version shown in Status -> Overview. Runs after the preset so
    # its CONFIG_VERSION_* lines are the ones that survive. Fatal: an
    # undetected kernel would ship "25.12(x)" and a filename that contradicts
    # the image, which is worse than a failed build.
    apply_version || {
        echo -e "${BOLD_RED}FIRMWARE VERSION UNDETECTED - ABORTING${RESET}"
        exit 1
    }

    # qmodem TTL (luci-app-qmodem-ttlfw4). Upstream's implementation is NOT
    # BYTE's: it matches only `iifname br-lan`, so router-originated packets
    # leave with the host TTL; it defines its own `chain postrouting`, and fw4
    # already owns that hook, so the firewall reload can fail and the rewrite
    # silently stops; it stops qca-nss-ecm; and it ships enable=0.
    #
    # files/ already overrides what runs at boot, but the *package* kept the
    # upstream script, so `opkg upgrade luci-app-qmodem-ttlfw4` put it back and
    # the unit silently lost NSS and the router-originated rewrite. Patch the
    # feed package as well, so the ipk this build publishes and the image carry
    # the same code.
    local qttl="$PWD/feeds/qmodem/luci/luci-app-qmodem-ttlfw4" qpair
    if [ ! -d "$qttl" ]; then
        echo -e "${BOLD_RED}qmodem TTL PACKAGE NOT FOUND: $qttl${RESET}"
        exit 1
    fi
    for qpair in \
        "etc/init.d/qmodem_ttl:root/etc/init.d/qmodem_ttl" \
        "etc/config/qmodem_ttl:root/etc/config/qmodem_ttl" \
        "www/luci-static/resources/view/qmodem/ttl.js:htdocs/luci-static/resources/view/qmodem/ttl.js"; do
        cp -f "files/${qpair%%:*}" "$qttl/${qpair##*:}" || {
            echo -e "${BOLD_RED}qmodem TTL: cannot patch $qttl/${qpair##*:}${RESET}"
            exit 1
        }
    done
    echo -e "${BOLD_GREEN}qmodem TTL PACKAGED AS BYTE (oifname wwan*, NSS kept)${RESET}"
    # qca-nss-ecm is enabled in the image (see preset). Its bonding front end
    # must be compiled out: ecm_bond_notifier.c registers 'struct bond_cb' /
    # bond_register_cb(), which are QSDK kernel additions that do not exist in
    # mainline (checked in v6.12.74, v6.12.94 and v6.12.112), so enabling the
    # front end breaks the build on every mainline kernel. The package forces
    # it on whenever kmod-bonding is selected, so remove the dependency and
    # the guard. No AW1000 configuration has a bond device, and every
    # '#ifdef ECM_INTERFACE_BOND_ENABLE' block then drops out.
    local ecm_mk="$PWD/feeds/nss/qca-nss-ecm/Makefile"
    if [ ! -f "$ecm_mk" ]; then
        echo -e "${BOLD_RED}qca-nss-ecm Makefile not found${RESET}"
        exit 1
    fi
    sed -i '/PACKAGE_kmod-bonding:kmod-bonding/d' "$ecm_mk"
    sed -i '/ifneq (\$(CONFIG_PACKAGE_kmod-bonding),)/,/^endif$/d' "$ecm_mk"
    sed -i '/ECM_INTERFACE_BOND_ENABLE/d' "$ecm_mk"
    if grep -q 'ECM_INTERFACE_BOND_ENABLE' "$ecm_mk"; then
        echo -e "${BOLD_RED}qca-nss-ecm still references ECM_INTERFACE_BOND_ENABLE${RESET}"
        exit 1
    fi
    if grep -q 'PACKAGE_kmod-bonding' "$ecm_mk"; then
        echo -e "${BOLD_RED}qca-nss-ecm still depends on kmod-bonding${RESET}"
        exit 1
    fi
    echo -e "${BOLD_GREEN}qca-nss-ecm: bonding front end disabled${RESET}"
    # qca-nss-ecm's init forces packet steering OFF at boot and on every
    # network reload:
    #
    #   disable_packet_steering() {
    #     uci -q set network.globals.packet_steering=0 && uci commit ...
    #     uci -q del network.globals.steering_flows    && uci commit ...
    #     /usr/libexec/network/packet-steering.uc -l 0 0
    #   }
    #
    # It runs from start_service() (START=26, right after netifd's
    # packet_steering at START=25) and from reload_service(), and `network` is a
    # reload trigger. The result on 1.2.30 was a unit whose image config said
    # packet_steering '1' / steering_flows '32768' but whose *overlay* said 0,
    # with no steering_flows at all: the switch in LuCI showed Disabled, the
    # RFS flow table was empty, and byte-selfcheck logged a MISMATCH every boot.
    # The one-shot uci-defaults could not help - ECM ran after it and the script
    # had already deleted itself.
    #
    # This box has no reason to park steering: QSDK does it because NSS takes
    # the data path, but ECM excludes the modem netdevs here (patch 0027) and
    # the LAN/WiFi path still benefits from per-queue CPU assignment. Replace
    # the writer with a reader: re-apply whatever UCI says (default 1, so a
    # config without the key still steers). No uci set, no commit, no delete -
    # the value now has exactly one owner, /etc/config/network.
    local ecm_init="$PWD/feeds/nss/qca-nss-ecm/files/qca-nss-ecm.init"
    if [ ! -f "$ecm_init" ]; then
        echo -e "${BOLD_RED}qca-nss-ecm init not found: $ecm_init${RESET}"
        exit 1
    fi
    python3 - "$ecm_init" <<'PY' || { echo -e "${BOLD_RED}qca-nss-ecm: cannot stop it from disabling packet steering${RESET}"; exit 1; }
import re
import sys

path = sys.argv[1]
src = open(path).read()

if "apply_packet_steering() {" in src and "disable_packet_steering" not in src:
    sys.exit(0)  # already patched: apply_preset() may run on a reused tree

new = '''apply_packet_steering() {
  local steering flows opts
  steering="$(uci -q get network.@globals[0].packet_steering)"
  flows="$(uci -q get network.@globals[0].steering_flows)"
  [ -n "$steering" ] || steering=1
  opts=
  [ "${flows:-0}" -gt 0 ] 2>/dev/null && opts="-l $flows"
  if [ -e "/usr/libexec/platform/packet-steering.sh" ]; then
    /usr/libexec/platform/packet-steering.sh "$steering"
  else
    /usr/libexec/network/packet-steering.uc $opts "$steering"
  fi
}'''

pat = re.compile(r'^disable_packet_steering\(\) \{.*?^\}', re.S | re.M)
src, n = pat.subn(new, src)
if n != 1:
    sys.exit("expected 1 disable_packet_steering() block, found %d" % n)
src = src.replace("  disable_packet_steering\n", "  apply_packet_steering\n")
if "disable_packet_steering" in src:
    sys.exit("disable_packet_steering survived the rewrite")
open(path, "w").write(src)
PY
    if grep -q 'disable_packet_steering\|packet_steering=0' "$ecm_init"; then
        echo -e "${BOLD_RED}qca-nss-ecm still disables packet steering${RESET}"
        exit 1
    fi
    grep -q '^apply_packet_steering() {' "$ecm_init" || {
        echo -e "${BOLD_RED}qca-nss-ecm init lost apply_packet_steering()${RESET}"
        exit 1
    }
    echo -e "${BOLD_GREEN}qca-nss-ecm: packet steering preserved (re-applied from UCI)${RESET}"

    # Kconfig variant cycle: upstream packages/net/weechat defines TWO packages
    # in ONE Makefile (weechat-minimal with DEFAULT_VARIANT, and weechat-full
    # with CONFLICTS:=weechat-minimal), both PROVIDES:=weechat. luci-app-weechat
    # depends on the bare name "+weechat", so Kconfig cannot pick a provider:
    #
    #   PACKAGE_luci-app-weechat depends on PACKAGE_weechat-full
    #   PACKAGE_weechat-full depends on PACKAGE_weechat-minimal
    #   PACKAGE_weechat-minimal is selected by PACKAGE_luci-app-weechat
    #
    # -> "recursive dependency detected!" and `make defconfig` aborts.
    #
    # The feeds/packages branch (openwrt-25.12) is NOT pinned, so upstream
    # added weechat-full while this repo was in flight - the same tree built
    # fine before 2026-10-16. Neither variant is in the image, so drop the
    # non-default one: with only weechat-minimal left there is one provider and
    # "+weechat" resolves.
    local wm="$PWD/feeds/packages/net/weechat/Makefile"
    if [ -f "$wm" ] && grep -q '^define Package/weechat-full$' "$wm"; then
        # Three separate blocks plus its BuildPackage call, all in this file.
        # Deleting only the definition would leave the description/install
        # blocks behind and Kconfig would still register the symbol.
        sed -i \
            -e '/^define Package\/weechat-full$/,/^endef$/d' \
            -e '/^define Package\/weechat-full\/description$/,/^endef$/d' \
            -e '/^define Package\/weechat-full\/install$/,/^endef$/d' \
            -e '/^Package\/weechat-full\/conffiles =/d' \
            -e '/^$(eval $(call BuildPackage,weechat-full))$/d' \
            "$wm"
        echo -e "${BOLD_GREEN}weechat-full VARIANT REMOVED (Kconfig cycle)${RESET}"
    fi

    # Same shape in the nikki feed: mihomo-alpha and mihomo-meta both declare
    # PROVIDES:=mihomo and CONFLICT each other, while nikki depends on the bare
    # "+mihomo". Keep the default (mihomo-meta, DEFAULT_VARIANT=1) and drop the
    # alpha package directory so exactly one provider remains.
    rm -rf package/feeds/nikki/mihomo-alpha feeds/nikki/mihomo-alpha
    echo -e "${BOLD_GREEN}mihomo-alpha VARIANT REMOVED (Kconfig cycle)${RESET}"
    # luci-app-netstat is vendored at packages/luci-app-netstat (from
    # dotywrt/dotycat-package, branch dotycat) with vnstat2 parsing fixes. If
    # an upstream feed ships the same PKG_NAME, two package directories collide
    # and the scanner keeps ONE silently (CONFIG_OVERRIDE_PKGS shows the
    # winner), so drop both feed copies: the vendored directory must be the
    # only one, otherwise the vnstat 2.x patches can disappear without a word.
    rm -rf package/feeds/luci/luci-app-netstat feeds/luci/applications/luci-app-netstat \
           package/feeds/dotycat/luci-app-netstat
    echo -e "${BOLD_GREEN}luci-app-netstat FEED COPIES REMOVED (vendored package wins)${RESET}"
    # luci-app-ramfree is vendored for the same reason: the luci feed is pinned
    # to 350fc919 (the first pin with view/dashboard/lib) and ImmortalWrt added
    # the app after that pin, so a pinned build would silently drop it and the
    # "Release RAM" entry would vanish. The package is ~1 KB of ucode + JSON.
    rm -rf package/feeds/luci/luci-app-ramfree feeds/luci/applications/luci-app-ramfree
    echo -e "${BOLD_GREEN}luci-app-ramfree VENDORED (missing at luci pin)${RESET}"
    # luci-app-passwall2 hard-depends on geoview + v2ray-geoip + v2ray-geosite
    # (~7.4 MB of ipks, ~3.4 MB in squashfs). The node this image is built for
    # is VLESS over plain WebSocket (security=none): no geoip:/geosite: routing
    # rules exist, xray only loads the .dat files when such a rule matches, and
    # passwall2 auto-disables geoview when the binary is absent
    # (nftables.sh: enable_geoview_ip=0 if `first_type geoview` is empty).
    # v2ray-geoip itself ships an 18-byte empty geoip.dat stub to
    # /usr/share/xray/, proving the file is optional. Users who need geo-based
    # routing can opkg install them from the self-hosted repo.
    local psm="$PWD/feeds/passwall_luci/luci-app-passwall2/Makefile"
    if [ -f "$psm" ] && grep -q '+geoview' "$psm"; then
        sed -i -e 's/ +geoview +v2ray-geoip +v2ray-geosite//' "$psm"
        if grep -qE '\+(geoview|v2ray-geoip|v2ray-geosite)\b' "$psm"; then
            echo -e "${BOLD_RED}luci-app-passwall2: geo deps still present${RESET}"
            exit 1
        fi
        echo -e "${BOLD_GREEN}luci-app-passwall2: geoview/geoip/geosite deps dropped (~7.4 MB)${RESET}"
    fi
    # xt_DSCP now calls the DSCPREMARK conntrack extension (kernel patch
    # 0600-6), so xt_DSCP.ko imports nf_conntrack.ko. kmod-ipt-ipopt does not
    # declare that dependency and package/kernel's ELF dependency checker then
    # fails the whole build with
    #   Package kmod-ipt-ipopt is missing dependencies for the following
    #   libraries: nf_conntrack.ko
    # (it resolves the import to the provider and finds it missing from the
    # package's own provides list). AddDepends/ipt emits DEPENDS+=, so appending
    # the kmod to that call adds it next to +kmod-ipt-core without touching the
    # shared macro. kmod-nf-conntrack is already in the image, so this costs no
    # flash and no boot time - it only records what the module already needs.
    local nfm="$PWD/package/kernel/linux/modules/netfilter.mk"
    if [ ! -f "$nfm" ]; then
        echo -e "${BOLD_RED}package/kernel/linux/modules/netfilter.mk not found${RESET}"
        exit 1
    fi
    if ! awk '/^define KernelPackage\/ipt-ipopt$/,/^endef$/' "$nfm" | \
            grep -q 'AddDepends/ipt,+kmod-nf-conntrack'; then
        # Anchor on the block, not on the file: AddDepends/ipt is shared by a
        # dozen kmod packages and only xt_DSCP grew the import. The block has a
        # single bare `$(call AddDepends/ipt)` line; rewrite just that one and
        # keep its indentation.
        awk -v rep='$(call AddDepends/ipt,+kmod-nf-conntrack)' '
            /^define KernelPackage\/ipt-ipopt$/ { blk = 1 }
            blk && /^[[:space:]]*\$\(call AddDepends\/ipt\)[[:space:]]*$/ {
                match($0, /^[[:space:]]*/)
                print substr($0, 1, RLENGTH) rep
                blk = 0
                next
            }
            /^endef$/ { blk = 0 }
            { print }
        ' "$nfm" >"$nfm.tmp" && mv "$nfm.tmp" "$nfm"
    fi
    if ! awk '/^define KernelPackage\/ipt-ipopt$/,/^endef$/' "$nfm" | \
            grep -q 'AddDepends/ipt,+kmod-nf-conntrack'; then
        echo -e "${BOLD_RED}kmod-ipt-ipopt still lacks +kmod-nf-conntrack${RESET}"
        exit 1
    fi
    echo -e "${BOLD_GREEN}kmod-ipt-ipopt: +kmod-nf-conntrack (xt_DSCP -> nf_conntrack.ko)${RESET}"
    # ndisc6 1.0.2 no longer exists anywhere fetchable: remlab.net answers 410
    # Gone (upstream keeps only 1.0.8/1.0.9) and neither the ImmortalWrt nor the
    # OpenWrt source mirrors ever carried it, so `make world` ended with
    # "No more mirrors to try - giving up" (run 41400987301). qmodem pulls
    # ndisc6/rdisc6 in whenever luci-app-qmodem is enabled, so the download sits
    # on the critical path. Bump the feed copy to 1.0.8 - the release Debian
    # tracks - and switch the URL to https, because remlab 301-redirects http
    # to https and a redirect chain is one more way for the fetch to fail.
    local ndm="$PWD/feeds/qmodem/application/ndisc6/Makefile"
    if [ -f "$ndm" ]; then
        sed -i -e 's|^PKG_VERSION:=.*|PKG_VERSION:=1.0.8|' \
            -e 's|^PKG_SOURCE_URL:=.*|PKG_SOURCE_URL:=https://www.remlab.net/files/ndisc6|' \
            -e 's|^PKG_MD5SUM:=.*|PKG_MD5SUM:=335a810a0180d36a1e2a5a81c425e2d6|' \
            -e '/^TARGET_CFLAGS += -std=c99$/d' "$ndm"
        # The feed's two patches are 1.0.2-only and cannot apply to 1.0.8:
        #   100-favor_bsd  adds #define __FAVOR_BSD next to _BSD_SOURCE in
        #     src/trace-{tcp,udp}.c; 1.0.8 rewrote those files (C11 alignas) and
        #     no longer undefines _GNU_SOURCE, so the hunk has no context.
        #   110-strverscmp ships a copy of glibc strverscmp into rdnssd/,
        #     because the old rdnssd/ layout lacked it; 1.0.8 moved the daemon
        #     to rdnss/ and musl exports strverscmp now.
        # Neither is needed: 1.0.8 builds clean against aarch64 musl (checked
        # with a musl-cross toolchain), so drop the whole directory.
        rm -rf "$(dirname "$ndm")/patches"
        # `TARGET_CFLAGS += -std=c99` also has to go: 1.0.8 uses `alignas` code
        # (src/trace-udp.c, src/trace-tcp.c) which is C11, and building it as
        # c99 fails with "expected expression before 'struct'". The toolchain
        # default (gnu17) builds it.
        if grep -q '^TARGET_CFLAGS += -std=c99$' "$ndm"; then
            echo -e "${BOLD_RED}ndisc6: c99 flag still present${RESET}"
            exit 1
        fi
        if ! grep -q '^PKG_VERSION:=1\.0\.8$' "$ndm" || \
                ! grep -q '^PKG_MD5SUM:=335a810a0180d36a1e2a5a81c425e2d6$' "$ndm"; then
            echo -e "${BOLD_RED}ndisc6: could not pin 1.0.8${RESET}"
            exit 1
        fi
        echo -e "${BOLD_GREEN}ndisc6: 1.0.2 -> 1.0.8 (1.0.2 answered 410)${RESET}"
    fi
    # A patch directory is only applied if Build/Prepare actually calls
    # $(Build/Patch). qmi_wwan_q overrides Build/Prepare (copy src/ flat into
    # PKG_BUILD_DIR) and never called it, so patches/0001-disable-qca-nss-hook
    # existed, was copied into the feed, and was never applied: modpost kept
    # failing with "rmnet_nss_callbacks ... undefined!" (run 41469086214). The
    # copy stays flat because the patch is -p1 against PKG_BUILD_DIR root; only
    # the patch step is appended.
    local qmm="$PWD/feeds/qmodem/driver/quectel_QMI_WWAN/Makefile"
    if [ -f "$qmm" ]; then
        if ! grep -qF '$(Build/Patch)' "$qmm"; then
            awk '
                /^define Build\/Prepare$/ { blk = 1 }
                blk && /\$\(CP\) \.\/src\// {
                    print
                    print "\t$(Build/Patch)"
                    blk = 0
                    next
                }
                /^endef$/ { blk = 0 }
                { print }
            ' "$qmm" >"$qmm.tmp" && mv "$qmm.tmp" "$qmm"
        fi
        if ! grep -qF '$(Build/Patch)' "$qmm"; then
            echo -e "${BOLD_RED}qmi_wwan_q: Build/Prepare does not apply patches${RESET}"
            exit 1
        fi
        echo -e "${BOLD_GREEN}qmi_wwan_q: Build/Prepare applies patches/ (NSS hook stripped)${RESET}"
    fi
    # qmodem reports the wrong connection state on this modem. The Quectel
    # RG500Q answers AT+CGPADDR=1 with IPv4 and dotted-decimal IPv6 inside ONE
    # quoted field:
    #   +CGPADDR: 1,"10.226.134.159,36.2.180.0.65.251.63.38.0.0.0.0.0.0.0.1"
    # while the stock get_cgpaddr_ipv4() only matches a whole quoted dotted
    # quad ('"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"'), so it returned nothing; the
    # IPv6 branch greps for ':' groups and finds none either. Both empty ->
    # get_connect_status() says "No" while the WAN is up, which is why the
    # Overview page showed "Connect Status: No" next to live IPv4/IPv6 default
    # routes. Rewrite the helper to split on commas and keep the first
    # standalone 4-octet quad. FM350 (separate quoted fields) and the 0.0.0.0
    # placeholder still behave: qmodem's own tests assert both.
    #
    # 3.4.0 upstreamed the fix: its get_cgpaddr_ipv4() already does
    # `tr -d '"' | tr ',' '\n'`. Patching it again is a no-op in behaviour but
    # rewrites a function we no longer need to own, so detect the upstream fix
    # and leave that file alone. Only when the body still matches the whole
    # quoted-quad form do we replace it - and then the marker is asserted, so a
    # future upstream rewrite cannot silently drop the fix.
    local qgs="$PWD/feeds/qmodem/application/qmodem/files/usr/share/qmodem/generic.sh"
    if [ ! -f "$qgs" ]; then
        # No generic.sh at all: nothing to check, same as before.
        qgs=""
    else
        local cgpbody
        cgpbody="$(sed -n '/^get_cgpaddr_ipv4()$/,/^}$/p' "$qgs")"
        if [ -n "$cgpbody" ] && printf '%s\n' "$cgpbody" | grep -q "tr ','"; then
            echo -e "${BOLD_GREEN}qmodem: upstream get_cgpaddr_ipv4 already splits the field${RESET}"
            qgs=""
        fi
    fi
    if [ -n "$qgs" ]; then
        if ! grep -q 'dotted-decimal IPv6 in ONE quoted field' "$qgs"; then
            local newfn
            newfn="$(mktemp)"
            cat >"$newfn" <<'CGPNEW'
get_cgpaddr_ipv4()
{
	# Quectel RG500Q returns IPv4 and dotted-decimal IPv6 in ONE quoted field:
	#   +CGPADDR: 1,"10.226.134.159,36.2.180.0.65.251.63.38.0.0.0.0.0.0.0.1"
	# (FM350 uses separate quoted fields). The stock helper only matched a
	# whole quoted dotted quad, so it returned nothing and the connection
	# status stayed "No" while the WAN was up. Split on commas, drop quotes and
	# CRs, keep the first standalone 4-octet quad that is not 0.0.0.0.
	echo "$1" | tr ',' '\n' | tr -d '"' | tr -d '\r' \
		| sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
		| grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' | grep -v '^0\.0\.0\.0$' \
		| head -n 1
}
CGPNEW
            awk -v new="$newfn" '
                /^get_cgpaddr_ipv4\(\)$/ {
                    while ((getline line < new) > 0)
                        print line
                    skip = 1
                    next
                }
                skip && /^}$/ { skip = 0; next }
                !skip { print }
            ' "$qgs" >"$qgs.tmp" && mv "$qgs.tmp" "$qgs"
            rm -f "$newfn"
        fi
        if ! grep -q 'dotted-decimal IPv6 in ONE quoted field' "$qgs"; then
            echo -e "${BOLD_RED}qmodem: get_cgpaddr_ipv4 rewrite did not apply${RESET}"
            exit 1
        fi
        echo -e "${BOLD_GREEN}qmodem: get_cgpaddr_ipv4 handles IPv4+IPv6 in one field${RESET}"
    fi
}

run_menuconfig() {
    if [ -n "$SKIP_MENUCONFIG" ]; then
        echo -e "${BOLD_YELLOW}SKIPPING MENUCONFIG (SKIP_MENUCONFIG set)${RESET}"
        return 0
    fi
    echo -e "${BOLD_YELLOW}RUNNING MENUCONFIG${RESET}"
    make menuconfig
    echo -e "${BOLD_GREEN}CONFIGURATION SAVED${RESET}"
}

# Rename distro-branded output files to the "BYTE by ACE" firmware name.
# VERSION_DIST is "BYTE by ACE"; filenames cannot contain spaces, so the build
# sanitises it to the lowercase/dashed "byte-by-ace" image prefix.  We normalise
# that to the canonical "BYTE_by_ACE" identifier and keep the checksum and
# profiles.json metadata in sync with the renamed files.
rename_output() {
    local dir="bin/targets"
    local f b d nb tag
    [ -d "$dir" ] || return 0

    # Build/run number in the filename, so a user can tell at a glance which
    # firmware they are flashing. GITHUB_RUN_NUMBER in CI; otherwise the short
    # commit; otherwise no tag at all, so a plain local build still works.
    # Prefer the version code from the generated .config, because apply_version
    # derives it from the commit count (1.2.1, 1.2.2, ...). Reading the static
    # preset here would name every image 1.2.1 while Status reports the real
    # version, so the file a user downloads would not match the running image.
    # Falls back to the preset, then build<run>, then the short commit.
    tag="${BUILD_TAG:-}"
    if [ -z "$tag" ]; then
        local code
        code=$(sed -n 's/^CONFIG_VERSION_CODE="\(.*\)"$/\1/p' ./.config 2>/dev/null | head -1)
        [ -n "$code" ] || \
            code=$(sed -n 's/^CONFIG_VERSION_CODE="\(.*\)"$/\1/p' "$script_dir/preset" 2>/dev/null | head -1)
        [ -n "$code" ] && tag="$code"
    fi
    if [ -z "$tag" ] && [ -n "${GITHUB_RUN_NUMBER:-}" ]; then
        tag="build${GITHUB_RUN_NUMBER}"
    fi
    if [ -z "$tag" ]; then
        tag=$(git rev-parse --short HEAD 2>/dev/null || echo "")
    fi

    # 1) Rename image + metadata files, inserting the build tag.
    while IFS= read -r f; do
        d="$(dirname "$f")"
        b="$(basename "$f")"
        nb="$(printf '%s' "$b" | sed \
            -e 's/ImmortalWrt/BYTE_by_ACE/g' \
            -e 's/immortalwrt/BYTE_by_ACE/g' \
            -e 's/^byte-by-ace-/BYTE_by_ACE-/' \
            -e 's/^byte-/BYTE_by_ACE-/')"
        # Put the tag right after the BYTE_by_ACE- prefix so names read
        # BYTE_by_ACE-build28-qualcommax-... and sort together. Skip if a tag
        # is already there, so re-running this function cannot produce
        # build28-build28.
        if [ -n "$tag" ]; then
            case "$nb" in
                BYTE_by_ACE-build*)
                    : ;;
                BYTE_by_ACE-?*)
                    nb="BYTE_by_ACE-${tag}-${nb#BYTE_by_ACE-}" ;;
            esac
        fi
        [ "$b" = "$nb" ] || mv -f "$f" "$d/$nb"
    done < <(find "$dir" -type f)

    # 2) Fix image references inside profiles.json.
    while IFS= read -r f; do
        sed -i -e 's/byte-by-ace-/BYTE_by_ACE-/g' \
               -e 's/"byte-/"BYTE_by_ACE-/g' "$f"
    done < <(find "$dir" -name profiles.json)

    # 3) Regenerate sha256sums so hashes reference the final file names.
    while IFS= read -r f; do
        d="$(dirname "$f")"
        ( cd "$d" || exit 0
          : > sha256sums
          find . -maxdepth 1 -type f ! -name sha256sums -printf '%P\n' \
              | LC_ALL=C sort | xargs -r sha256sum | sed 's/  / */' >> sha256sums )
    done < <(find "$dir" -name sha256sums)
}
get_version() {
    version_tag=$(git describe --tags --exact-match 2>/dev/null || echo "")
    version_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
}

# Firmware version, rendered by LuCI -> Status -> Overview as:
#
#     BYTE 25.12(6.12.94) 1.2.1
#
# dist version DIST(RELEASE) CODE
#   DIST    CONFIG_VERSION_DIST     "BYTE"
#   RELEASE CONFIG_VERSION_NUMBER   "25.12(<kernel>)"  kernel read from the tree
#   CODE    CONFIG_VERSION_CODE     "<major>.<minor>.<patch>"
#
# base-files writes DISTRIB_DESCRIPTION='%D %V %C', so those three fields are
# exactly the string the status page shows.
#
# The patch is derived, not hand-edited: it is the number of commits since
# FW_BASE in version.env (see that file). Every commit moves 1.2.1 -> 1.2.2.
# Needs full history: CI checks out with fetch-depth: 0. Without history (or
# with HEAD still on FW_BASE) FW_PATCH_FALLBACK is used.
apply_version() {
    local base maj min patch kernel ver n
    base=$(sed -n 's/^FW_BASE=//p' "$script_dir/version.env" 2>/dev/null | head -1)
    maj=$(sed -n 's/^FW_MAJOR=//p' "$script_dir/version.env" 2>/dev/null | head -1)
    min=$(sed -n 's/^FW_MINOR=//p' "$script_dir/version.env" 2>/dev/null | head -1)
    patch=$(sed -n 's/^FW_PATCH_FALLBACK=//p' "$script_dir/version.env" 2>/dev/null | head -1)
    case "$maj" in '' | *[!0-9]*) maj=1 ;; esac
    case "$min" in '' | *[!0-9]*) min=2 ;; esac
    case "$patch" in '' | *[!0-9]*) patch=1 ;; esac

    if [ -n "$base" ] && git -C "$script_dir" cat-file -e "${base}^{commit}" 2>/dev/null; then
        n=$(git -C "$script_dir" rev-list --count "${base}..HEAD" 2>/dev/null)
        # n=0 means HEAD is still the base commit (local, uncommitted work):
        # keep the fallback so the build does not claim 1.2.0.
        case "$n" in '' | *[!0-9]*) n=0 ;; esac
        [ "$n" -ge 1 ] 2>/dev/null && patch=$n
    fi

    # The patch level is NOT in include/kernel-version.mk (that file only includes
    # the per-version detail file) and NOT in include/version.mk (the
    # KERNEL_VERSION there is a placeholder replaced only by the SDK). It lives
    # in target/linux/generic/kernel-<KERNEL_PATCHVER>:
    #
    #   target/linux/qualcommax/Makefile   KERNEL_PATCHVER:=6.12
    #   target/linux/generic/kernel-6.12   LINUX_VERSION-6.12 = .94
    #
    # so read the subtarget's KERNEL_PATCHVER from .config's board, then the
    # matching detail file. Anything else silently yields the placeholder "x".
    local board patchver
    board=$(sed -n 's/^CONFIG_TARGET_BOARD="\(.*\)"$/\1/p' .config 2>/dev/null | head -1)
    [ -n "$board" ] || board=qualcommax
    kernel=""
    if [ -f "target/linux/$board/Makefile" ]; then
        patchver=$(sed -n 's/^KERNEL_PATCHVER:=//p' "target/linux/$board/Makefile" 2>/dev/null |
            tr -d '[:space:]' | head -1)
    fi
    # No generic/Makefile fallback and no scan across kernel-*: both can pick a
    # series this target does not build (a 6.6 detail file is present in the
    # tree too), and a plausible-but-wrong kernel in the version string is
    # exactly the drift this feature exists to prevent.
    if [ -n "${patchver:-}" ] && [ -f "target/linux/generic/kernel-$patchver" ]; then
        kernel=$(awk -v pv="$patchver" -F' = ' '$1 == "LINUX_VERSION-" pv { print pv $2; exit }' \
            "target/linux/generic/kernel-$patchver" 2>/dev/null)
    fi
    # Shape check: "6.12.94". Rejects the "x" placeholder and anything empty.
    case "$kernel" in
    '' | *[!0-9.]* | *.*.*.*)
        echo -e "${BOLD_RED}VERSION: kernel patch level not found (board=${board:-?} patchver=${patchver:-?})${RESET}"
        return 1
        ;;
    esac

    ver="${maj}.${min}.${patch}"
    sed -i -e '/^CONFIG_VERSION_DIST=/d' \
           -e '/^CONFIG_VERSION_NUMBER=/d' \
           -e '/^CONFIG_VERSION_CODE=/d' .config
    {
        echo "CONFIG_VERSION_DIST=\"BYTE\""
        # CONFIG_VERSION_NUMBER lands in image FILENAMES (IMG_PREFIX, via
        # $(DEVICE_IMG_PREFIX)). Parentheses are legal in a Kconfig string and
        # fine for /etc/openwrt_release, but Build/kernel-bin runs
        # `rm -f $@` unquoted, and bash parses the "(" as a subshell token:
        #   bash: -c: line 1: syntax error near unexpected token `('
        # The build then dies in target/install, after every package compiled
        # (~1 h locally, ~3 h in CI). So the string keeps its display shape
        # (LuCI Status shows "BYTE 25.12(6.12.94) 1.2.x") but the parentheses
        # are emitted as a safe character pair: '.' reads identically in
        # "25.12(6.12.94)" vs "25.12.6.12.94" contexts, and VERSION_CODE still
        # carries the release detail. display variant in
        # /etc/openwrt_release is set separately below.
        echo "CONFIG_VERSION_NUMBER=\"25.12.${kernel}\""
        echo "CONFIG_VERSION_CODE=\"${ver}\""
    } >> .config
    echo -e "${BOLD_GREEN}FIRMWARE VERSION: BYTE 25.12(${kernel}) ${ver}${RESET}"
}

# CI-only: fail fast if the preset did not resolve the required packages.
ci_check_packages() {
    local missing="" forbidden="" p ndm qmp
    # ci_check_packages runs with CWD=immortalwrt, so repo paths must be
    # resolved via $script_dir rather than assumed relative.
    local repo_root="$(realpath "$script_dir" 2>/dev/null)"
    [ -n "$repo_root" ] || repo_root="$(realpath .)"
    # openclash / adguardhome are intentionally not shipped (size); the
    # proxy stack is passwall + passwall2 with the Xray core only.
    # passwall v1 is deliberately absent: it and passwall2 both install redirect
    # rules on the same nft table and hijack port 53, so they cannot coexist -
    # v1 gets torn down and looks "not running". Only passwall2 ships; require
    # that v1 stays out.
    if grep -q '^CONFIG_PACKAGE_luci-app-passwall=y$' .config; then
        forbidden="$forbidden passwall-v1(ships alongside passwall2, cannot coexist)"
    fi
    # preset can drift from the feeds. A CONFIG_PACKAGE_x=y whose symbol no
    # longer exists is dropped by defconfig with at most a warning, so a
    # requested app can vanish from the image without failing anything (found:
    # luci-app-cpufreq, luci-lib-nixio_openssl, and three *_INCLUDE_*
    # sub-options whose parent app had left the luci feed). Assert every
    # requested symbol is still declared in the generated package index.
    pidx="tmp/.config-package.in"
    if [ -f "$pidx" ]; then
        for rp in $(grep -oE '^CONFIG_PACKAGE_[A-Za-z0-9_.+-]+=y$' "$repo_root/preset" | \
                sed 's/^CONFIG_PACKAGE_//;s/=y$//'); do
            grep -qE "^[[:space:]]*(menu)?config PACKAGE_${rp}\$" "$pidx" || \
                missing="$missing preset-no-such-package:$rp"
        done
    fi
    for p in luci-app-passwall2 \
             luci-theme-footstrap \
             luci-app-qmodem qmodem modem_scan tom_modem \
             luci-app-netstat vnstat2 \
             kmod-aw1000-fxs fxsd luci-app-fxs \
             kmod-qca-nss-drv kmod-qca-nss-ecm nss-firmware \
             kmod-qmi_wwan_q luci-app-modeminfo \
             luci-app-byte luci-app-ramfree \
             xray-core \
             luci-app-filemanager \
             luci-app-qmodem-sms luci-app-qmodem-ttlfw4 sms-forwarder-next sms-tool_q ubus-at-daemon \
             qmodem-voip qmodem-sipd qmodem-smsd luci-app-qmodem-voip \
             kmod-sound-core alsa-lib libpjsip libpjsip-ua adb px5g-mbedtls libsoxr \
             kmod-ifb kmod-sched-cake kmod-sched-core kmod-ipt-ipset \
             kmod-macvlan kmod-nf-ipt kmod-nft-socket kmod-nf-nathelper \
             kmod-nf-nathelper-extra ipset tc-tiny iptables-nft \
             iptables-mod-conntrack-extra iptables-mod-ipopt ruby \
             rpcd-mod-rpcsys; do
        grep -q "^CONFIG_PACKAGE_${p}=y$" .config || missing="$missing $p"
    done
    # passwall2's geo deps are stripped in apply_preset() (~7.4 MB): this node
    # is VLESS over plain ws, no geoip:/geosite: routing rule ever matches, and
    # passwall2 degrades gracefully without geoview. Assert they stay OUT.
    for p in geoview v2ray-geoip v2ray-geosite; do
        grep -q "^CONFIG_PACKAGE_${p}=y$" .config && \
            forbidden="$forbidden $p(passwall2 geo deps stripped: ~7.4 MB)"
    done
    # NSS ECM needs these drv features compiled in
    for p in CONFIG_NSS_DRV_IPV6_ENABLE CONFIG_NSS_DRV_VIRT_IF_ENABLE \
             CONFIG_NSS_DRV_PPPOE_ENABLE CONFIG_NSS_DRV_BRIDGE_ENABLE \
             CONFIG_NSS_DRV_VLAN_ENABLE CONFIG_NSS_FIRMWARE_VERSION_12_5; do
        grep -q "^${p}=y$" .config || missing="$missing $p"
    done
    # qmodem's vendor driver already provides qmi_wwan_q.ko; the packaged
    # copies would collide on the same file during rootfs assembly.
    # kmod-usb-net-qmi-wwan (upstream generic) also matches the RG500Q IDs
    # (0x2c7c:0x0800) and races qmi_wwan_q for /dev/cdc-wdm0, crashing the dial.
    for p in kmod-usb-net-qmi-wwan kmod-usb-net-qmi-wwan-quectel kmod-usb-net-qmi-wwan-fibocom; do
        if grep -q "^CONFIG_PACKAGE_${p}=y$" .config; then
            forbidden="$forbidden $p"
        fi
    done
    # luci-app-nft-ttl is a third TTL implementation: its own firewall include,
    # no ECM/NSS handling, and it would race luci-app-qmodem-ttlfw4 over the
    # same packets. The image ships the qmodem app only.
    if grep -q "^CONFIG_PACKAGE_luci-app-nft-ttl=y$" .config; then
        forbidden="$forbidden luci-app-nft-ttl"
    fi
    # Size: these must stay out of the image.
    for p in sing-box hysteria naiveproxy xray-plugin v2ray-plugin \
             luci-theme-argon luci-theme-vantage luci-app-vantage \
             luci-app-openclash adguardhome \
             luci-app-adguardhome \
             tailscale luci-app-tailscale-community; do
        grep -q "^CONFIG_PACKAGE_${p}=y$" .config && forbidden="$forbidden $p"
    done
    # Two QModem UIs must never be installed together: luci-app-qmodem (Lua)
    # and luci-app-qmodem-next (JS) both own the Modem menu and both drive the
    # same dialer, so the second one loaded wins and the pages disagree.
    grep -q "^CONFIG_PACKAGE_luci-app-qmodem-next=y$" .config && \
        forbidden="$forbidden luci-app-qmodem-next(coexists with luci-app-qmodem)"
    # luci-app-aw1k-led was dropped: its led-status daemon duplicates the
    # declarative LED triggers in /etc/config/system, and it was the only thing
    # that pulled Lua controllers into the image. A stale =y in a reused tree
    # would bring the old Lua menu tree (and its "Tools -> 5G LED Config" page,
    # which no longer has a controller) back.
    grep -q "^CONFIG_PACKAGE_luci-app-aw1k-led=y$" .config && \
        forbidden="$forbidden luci-app-aw1k-led(duplicates /etc/config/system LED triggers)"
    # Only Footstrap ships. A leftover Argon entry in /etc/config/luci leaves a
    # dead menu entry pointing at /luci-static/argon, which 404s.
    grep -qi 'argon' "$repo_root/files/etc/config/luci" 2>/dev/null && \
        forbidden="$forbidden luci-config-argon-theme(theme asset not shipped)"
    # ECM is ALWAYS ON and must stay that way: bridge / LAN<->WiFi / local
    # flows are accelerated by it. Modem egress is excluded in the ECM source
    # (patch 0027) so the TTL rewrite always wins on the WAN path. A build
    # without ECM silently loses the dashboard NSS widget and all LAN offload.
    grep -q "^CONFIG_PACKAGE_kmod-qca-nss-ecm=y$" .config || \
        missing="$missing kmod-qca-nss-ecm"
    # ECM's bonding front end cannot compile on a mainline kernel: ecm_bond_notifier.c
    # uses QSDK-only 'struct bond_cb' / bond_register_cb(). kmod-bonding must
    # stay out and the package Makefile must not force ECM_INTERFACE_BOND_ENABLE.
    # apply_preset() strips both; a regression here costs a 3 h build.
    grep -q "^CONFIG_PACKAGE_kmod-bonding=y$" .config && \
        forbidden="$forbidden kmod-bonding(ECM bond notifier cannot compile here)"
    grep -q 'ECM_INTERFACE_BOND_ENABLE' feeds/nss/qca-nss-ecm/Makefile 2>/dev/null && \
        forbidden="$forbidden ECM_BOND_ENABLE(bond notifier cannot compile here)"
    # Patch 0027 is the whole TTL guarantee: modem egress must never be
    # accelerated. Patch 0600-6 provides the DSCPREMARK conntrack extension
    # that ECM's KCONFIG selects and links against.
    [ -f "$repo_root/nss/feeds/nss/qca-nss-ecm/patches/0027-ecm-interface-exclude-modem-egress-from-acceleration.patch" ] || \
        missing="$missing ecm-patch-0027(modem-egress-exclusion)"
    [ -f "$repo_root/nss/target/linux/qualcommax/patches-6.12/0600-6-qca-nss-ecm-support-netfilter-DSCPREMARK.patch" ] || \
        missing="$missing dscpremark-patch"
    # KCONFIG in a kmod package lands in $(LINUX_DIR)/.config.override, never in
    # the top-level .config, so the wiring is asserted here instead: the package
    # must still request the symbol, and the patch must keep it unconditional
    # (`default y`). kmod-nf-conntrack does force NETFILTER_ADVANCED=y, so the
    # upstream `depends on NETFILTER_ADVANCED` would resolve - but that is an
    # implicit chain through another package's KCONFIG. `default y` keeps the
    # extension visible no matter what, which is what ECM links against.
    grep -q 'KCONFIG:=CONFIG_NF_CONNTRACK_DSCPREMARK_EXT=y' feeds/nss/qca-nss-ecm/Makefile 2>/dev/null || \
        missing="$missing ecm-KCONFIG-dscpremark"
    grep -q '^+	default y$' "$repo_root/nss/target/linux/qualcommax/patches-6.12/0600-6-qca-nss-ecm-support-netfilter-DSCPREMARK.patch" 2>/dev/null || \
        missing="$missing dscpremark-default-y"
    # The same patch makes xt_DSCP.ko import nf_conntrack.ko. The kernel-package
    # dependency checker resolves that import to its provider package and aborts
    # if kmod-ipt-ipopt does not declare it ("Package kmod-ipt-ipopt is missing
    # dependencies for the following libraries: nf_conntrack.ko"). apply_preset()
    # appends it to AddDepends/ipt; assert the rewritten block, because a
    # netfilter.mk change upstream would silently drop it again.
    awk '/^define KernelPackage\/ipt-ipopt$/,/^endef$/' \
        package/kernel/linux/modules/netfilter.mk 2>/dev/null | \
        grep -q 'AddDepends/ipt,+kmod-nf-conntrack' || \
        missing="$missing kmod-ipt-ipopt(nf_conntrack dep)"
    # ndisc6/rdisc6 come in with luci-app-qmodem, so their tarball is on the
    # `make world` critical path. Upstream remlab.net now keeps only 1.0.8 and
    # 1.0.9; the feed copy asked for 1.0.2, which answers 410 there and was
    # never mirrored by ImmortalWrt or OpenWrt - the build died with "No more
    # mirrors to try - giving up" (run 41400987301). apply_preset() rewrites the
    # feed Makefile to 1.0.8 with a pinned hash and an https URL; assert all
    # three, because a feed bump would bring the dead 1.0.2 reference back.
    ndm="feeds/qmodem/application/ndisc6/Makefile"
    if [ -f "$ndm" ]; then
        grep -q '^PKG_VERSION:=1\.0\.8$' "$ndm" || \
            missing="$missing ndisc6-1.0.8(1.0.2 is 410 upstream)"
        grep -q '^PKG_MD5SUM:=335a810a0180d36a1e2a5a81c425e2d6$' "$ndm" || \
            missing="$missing ndisc6-md5(pinned)"
        grep -q '^PKG_SOURCE_URL:=https://www\.remlab\.net/files/ndisc6$' "$ndm" || \
            missing="$missing ndisc6-url(https, no redirect)"
        # 1.0.2-era patches cannot apply to 1.0.8 and the c99 flag breaks its
        # C11 `alignas` code; the build failed on both in run 41438049720.
        [ -d "$(dirname "$ndm")/patches" ] && \
            forbidden="$forbidden ndisc6-patches(1.0.2-only)"
        grep -q '^TARGET_CFLAGS += -std=c99$' "$ndm" && \
            forbidden="$forbidden ndisc6-c99(1.0.8 needs C11)"
    else
        missing="$missing ndisc6-feed-Makefile"
    fi
    # qmi_wwan_q 1.5 defines CONFIG_QCA_NSS_DRV on every IPQ807x/IPQ5018/IPQ8074
    # target and then references rmnet_nss_callbacks from the separate
    # rmnet_nss.ko. That module is unselectable here (its DEPENDS include
    # +@NSS_DRV_C2C_ENABLE, a chip-to-chip path an AW1000 does not want), so
    # modpost aborts: "rmnet_nss_callbacks" [qmi_wwan_q.ko] undefined! (run
    # 41456411377). The patch drops the two #define lines; the driver keeps its
    # own QMAP implementation and only the optional NSS RX hand-off goes away.
    # ECM excludes wwan*/rmnet* anyway (patch 0027), so no WAN offload is lost.
    qmp="$repo_root/nss/feeds/qmodem/driver/quectel_QMI_WWAN/patches/0001-disable-qca-nss-hook.patch"
    [ -f "$qmp" ] || missing="$missing qmi_wwan_q-no-nss-patch"
    [ -f "feeds/qmodem/driver/quectel_QMI_WWAN/patches/0001-disable-qca-nss-hook.patch" ] || \
        missing="$missing qmi_wwan_q-patch-not-copied(nss/ overlay)"
    grep -q '^-#define CONFIG_QCA_NSS_DRV$' "$qmp" 2>/dev/null || \
        missing="$missing qmi_wwan_q-patch-no-define-removal"
    # The patch is -p1 against PKG_BUILD_DIR root, so Build/Prepare must keep
    # copying the *contents* of src/ (a move to 'cp -r src' would break it).
    grep -qF '$(CP) ./src/* $(PKG_BUILD_DIR)/' \
        feeds/qmodem/driver/quectel_QMI_WWAN/Makefile 2>/dev/null || \
        missing="$missing qmi_wwan_q-prepare-flattened(patch is -p1)"
    # ... and Build/Prepare must actually run the patch step: a build that only
    # ships patches/ still fails modpost (run 41469086214).
    grep -qF '$(Build/Patch)' \
        feeds/qmodem/driver/quectel_QMI_WWAN/Makefile 2>/dev/null || \
        missing="$missing qmi_wwan_q-patches-never-applied(Build/Prepare skips Build/Patch)"
    # rmnet-nss cannot be selected (C2C unmet) and is not wanted: assert it
    # stays out so the patch and the image agree.
    grep -q '^CONFIG_PACKAGE_kmod-rmnet-nss=y$' .config && \
        forbidden="$forbidden kmod-rmnet-nss(unselectable, C2C dep; patch handles it)"
    # Ruby's Kconfig defaults RUBY_ENABLE_YJIT to y on aarch64 and that pulls
    # rust/host into the build. The Rust host package downloads prebuilt LLVM
    # from ci-artifacts.rust-lang.org, and rust-lang rotates those out, so the
    # build dies on an HTTP 404 after ~3 h. YJIT cannot work here anyway: Ruby
    # 3.4 does not support cross-compiling YJIT, and the build host (x86_64)
    # differs from the target (aarch64).
    grep -q '^# CONFIG_RUBY_ENABLE_YJIT is not set$' .config || \
        missing="$missing ruby-yjit-off(rust-host-llvm-404)"
    # The target rust compiler package is never wanted: it is only a dependency
    # of YJIT and of Rust application packages, none of which ship.
    grep -q '^CONFIG_PACKAGE_rust=y$' .config && \
        forbidden="$forbidden rust-target-package(huge, unused)"
    # ECM must never be parked by the TTL service: modem egress is excluded in
    # the ECM source instead, so TTL and NSS run together. A script that stops
    # ECM re-introduces the old mutual-exclusion and loses LAN offload.
    grep -q "qca-nss-ecm stop" "$repo_root/files/etc/init.d/qmodem_ttl" 2>/dev/null && \
        forbidden="$forbidden ttl-stops-ecm(must stay loaded)"
    # Same for the two TTL apps: the Lua one writes its own firewall include
    # and the fw4 one writes /etc/nftables.d/99-reset-ttl-from-br-lan.nft, so
    # both would fight over the same packets.
    grep -q "^CONFIG_PACKAGE_luci-app-qmodem-ttl=y$" .config && \
        forbidden="$forbidden luci-app-qmodem-ttl(Lua variant; use -ttlfw4)"
    # The non-default variants are removed so Kconfig has a single provider per
    # name; if either comes back, "recursive dependency detected!" returns and
    # defconfig aborts before compiling anything.
    grep -q '^define Package/weechat-full$' feeds/packages/net/weechat/Makefile 2>/dev/null && \
        forbidden="$forbidden weechat-full-variant(Kconfig-cycle)"
    [ -e package/feeds/nikki/mihomo-alpha ] && \
        forbidden="$forbidden mihomo-alpha-variant(Kconfig-cycle)"
    # TTL must default to 64 on the modem uplink - this is the single most
    # important behaviour of the image (tethering detection).
    # TTL is owned by luci-app-qmodem-ttlfw4 now: one UCI switch and one TTL
    # value (1-255), and the rewrite is always installed. Assert the shipped
    # defaults and that the app is in the image, because a missing app means
    # the image loses TTL rewriting entirely - silently.
    grep -qE "^[[:space:]]*option ttl '64'$" "$repo_root/files/etc/config/qmodem_ttl" 2>/dev/null || \
        missing="$missing TTL(qmodem_ttl.ttl)"
    grep -qE "^[[:space:]]*option enable '1'$" "$repo_root/files/etc/config/qmodem_ttl" 2>/dev/null || \
        missing="$missing TTL-ENABLED(qmodem_ttl.enable)"
    # The image overrides the QModem init script: upstream hooks `iifname
    # br-lan`, which leaves router-originated traffic (dnsmasq, NTP, proxy
    # upstream, health checks) with the host TTL. Assert the override exists
    # and really matches the egress interface, or the build silently ships the
    # weaker upstream rule.
    [ -x "$repo_root/files/etc/init.d/qmodem_ttl" ] || \
        missing="$missing ttl-init-override"
    grep -q 'oifname' "$repo_root/files/etc/init.d/qmodem_ttl" 2>/dev/null || \
        missing="$missing TTL-RULE(oifname-egress)"
    # The LuCI page is overridden too: the packaged copy still warns that
    # enabling TTL disables NSS. files/ is copied over the package rootfs
    # (include/image.mk prepare_rootfs), so the override must exist or the UI
    # ships the wrong advice.
    [ -f "$repo_root/files/www/luci-static/resources/view/qmodem/ttl.js" ] || \
        missing="$missing ttl-luci-override"
    # ...and the *package* must carry the same code, or an `opkg upgrade
    # luci-app-qmodem-ttlfw4` puts upstream's script back: br-lan-only match,
    # its own postrouting chain, qca-nss-ecm stopped, enable=0. apply_preset
    # copies the three files into the feed package; assert they really landed
    # and that the packaged script still has no ECM stop.
    local qttl="feeds/qmodem/luci/luci-app-qmodem-ttlfw4" qpair
    for qpair in "etc/init.d/qmodem_ttl:root/etc/init.d/qmodem_ttl" \
                 "etc/config/qmodem_ttl:root/etc/config/qmodem_ttl" \
                 "www/luci-static/resources/view/qmodem/ttl.js:htdocs/luci-static/resources/view/qmodem/ttl.js"; do
        cmp -s "$repo_root/files/${qpair%%:*}" "$qttl/${qpair##*:}" || \
            missing="$missing qmodem-ttl-package(${qpair##*:} not BYTE's)"
    done
    grep -q 'byte_ttl' "$qttl/root/etc/init.d/qmodem_ttl" 2>/dev/null || \
        missing="$missing qmodem-ttl-package(no byte_ttl chain)"
    if grep -q 'qca-nss-ecm stop' "$qttl/root/etc/init.d/qmodem_ttl" 2>/dev/null; then
        forbidden="$forbidden qmodem-ttl-package(stops-ecm)"
    fi
    if grep -q '99-reset-ttl-from-br-lan' "$qttl/root/etc/init.d/qmodem_ttl" 2>/dev/null &&
        ! grep -q 'NFT_LEGACY' "$qttl/root/etc/init.d/qmodem_ttl" 2>/dev/null; then
        forbidden="$forbidden qmodem-ttl-package(writes-upstream-include)"
    fi
    # Offload policy lives in the same service: fw4's flowtable is forced to
    # flow_offloading=0 in every state (TTL on and off, NSS installed or not),
    # because it skips the mangle chain after the first packet. A regression to
    # 1 is invisible in the UI - the TTL rule still loads, only accelerated
    # flows leak.
    grep -q "flow_offloading='0'" "$repo_root/files/etc/init.d/qmodem_ttl" 2>/dev/null || \
        missing="$missing TTL-OFFLOAD(forced-off)"
    if grep -q "flow_offloading='1'" "$repo_root/files/etc/init.d/qmodem_ttl" 2>/dev/null; then
        missing="$missing TTL-OFFLOAD(sets-1)"
    fi
    # adguardhome: the LuCI app requires >=0.107.73-r3, but ImmortalWrt
    # 24.10.6 only publishes 0.107.57, so the binary MUST come from our repo
    # (we build 0.107.79). If it ever stops being published the UI becomes
    # uninstallable, which is silent until a user tries.
    grep -q 'luci-app-adguardhome' "$repo_root/.github/build-package-repo.sh" 2>/dev/null || \
        missing="$missing repo-publishes-luci-app-adguardhome"
    grep -q 'adguardhome|luci-app-adguardhome' "$repo_root/.github/build-package-repo.sh" 2>/dev/null || \
        missing="$missing repo-publishes-adguardhome-binary"
    # PassWall v1 (Lua) is published on demand, never installed. It is vendored
    # at packages/luci-app-passwall (4.66-8) rather than pulled from a feed, so
    # the on-demand build compiles the exact copy that was reviewed here and no
    # `opkg upgrade` can swap it for an upstream version - same failure mode as
    # qmodem's TTL script.
    local pwall="$repo_root/packages/luci-app-passwall" inc
    [ -f "$pwall/Makefile" ] || missing="$missing passwall-v1-vendored"
    grep -q '^PKG_VERSION:=4\.66-8$' "$pwall/Makefile" 2>/dev/null || \
        missing="$missing passwall-v1-version(must be 4.66-8)"
    # Cores pinned to Xray only: xray-core is already in the image, while the
    # other eight INCLUDE_* options would add ~25 MB of repo assets and a Go +
    # Rust build to every CI run. A `default y` creeping back in is silent -
    # the package still builds, just three times slower.
    for inc in Haproxy Shadowsocks_Libev_Client Shadowsocks_Libev_Server \
               Shadowsocks_Rust_Client ShadowsocksR_Libev_Client Simple_Obfs \
               Trojan_Plus V2ray V2ray_Plugin Xray_Plugin; do
        awk -v want="config PACKAGE_\$(PKG_NAME)_INCLUDE_${inc}" '
            $0 == want { f = 1; next }
            f && /^config / { exit }
            f && /^[[:space:]]*default / { print; exit }
        ' "$pwall/Makefile" 2>/dev/null | grep -q 'default n' || \
            missing="$missing passwall-v1-core-enabled(${inc}; Xray only)"
    done
    awk -v want='config PACKAGE_$(PKG_NAME)_INCLUDE_Xray' '
        $0 == want { f = 1; next }
        f && /^config / { exit }
        f && /^[[:space:]]*default / { print; exit }
    ' "$pwall/Makefile" 2>/dev/null | grep -q 'default y' || \
        missing="$missing passwall-v1-no-xray-default"
    # Every script must be executable in the ipk. The uci-defaults one is the
    # one that matters: it creates /etc/config/passwall from 0_default_config
    # and flips use_nft to 1, so shipping it 0644 means v1 starts with no
    # config at all and an iptables path this image does not have - and
    # nothing fails, it just does not work.
    local pwf
    for pwf in root/etc/init.d/passwall root/etc/init.d/passwall_server \
               root/etc/uci-defaults/luci-passwall \
               root/etc/hotplug.d/iface/98-passwall \
               root/usr/share/passwall/app.sh root/usr/share/passwall/monitor.sh; do
        [ -x "$pwall/$pwf" ] || missing="$missing passwall-v1-not-executable($pwf)"
    done
    # v1 must be published (it is not in the image manifest, so a typo in the
    # on-demand list would silently leave it out of the repo), and its three
    # non-image runtime deps with it.
    for inc in luci-app-passwall dns2socks dns2tcp microsocks; do
        grep -qx "$inc" "$repo_root/.github/repo/ondemand.txt" 2>/dev/null || \
            missing="$missing ondemand-missing:$inc"
    done
    # ...and it must have no feed line: a src-git pin would reintroduce a
    # second luci-app-passwall into the feed metadata. Checked on the generated
    # feeds.conf.default (the source only mentions it in a comment).
    grep -q '^src-git passwall1 ' feeds.conf.default 2>/dev/null && \
        forbidden="$forbidden passwall1-feed(vendored copy must win)"

    # The image must trust the key the repo is signed with, otherwise every
    # index fails verification while opkg still reports "Updated list". That
    # only works if key-build is in the tree BEFORE base-files runs, so the
    # CI step that installs it must precede the firmware build.
    # The committed key is the single source of truth. CI copies repo-key/* into
    # immortalwrt/ BEFORE base-files runs (step order matters - see the
    # workflow), so the image and the published repo share one key. A stray
    # top-level key-build.pub would mean something generated one early.
    [ -s "$repo_root/repo-key/key-build" ] || missing="$missing repo-key(key-build)"
    [ -s "$repo_root/repo-key/key-build.pub" ] || missing="$missing repo-key(key-build.pub)"
    if [ -e "$repo_root/key-build.pub" ] && \
       ! cmp -s "$repo_root/key-build.pub" "$repo_root/repo-key/key-build.pub" 2>/dev/null; then
        forbidden="$forbidden KEY_MISMATCH(top-level key-build.pub != repo-key/)"
    fi

    # The cellular MTU must stay pinned: qmodem creates the interface at the
    # kernel default of 1500, which an LTE/NR bearer cannot carry, so
    # full-size packets get dropped upstream (PMTU blackhole) while small ones
    # pass - which reads as "works but keeps dropping".
    [ -x "$repo_root/files/etc/init.d/byte-mtu" ] || missing="$missing byte-mtu-init"
    [ -x "$repo_root/files/etc/hotplug.d/iface/90-byte-mtu" ] || missing="$missing byte-mtu-hotplug"
    # Tuning must be verifiable on the device, not just declared: byte-selfcheck
    # logs the observed governor/qdisc/MTU/RPS against the configured values, so
    # a kernel that silently rejects a key shows up instead of going unnoticed.
    # luci-app-byte ships the AdGuard Home panel. Its backend is an rpcd exec
    # plugin, so a missing file is a 404 in the UI rather than a build error -
    # assert the three pieces that make the page work.
    for f in packages/luci-app-byte/Makefile \
             packages/luci-app-byte/root/usr/libexec/rpcd/byte \
             packages/luci-app-byte/root/usr/share/rpcd/acl.d/luci-app-byte.json \
             packages/luci-app-byte/root/usr/libexec/luci-app-byte/agh-passwall2.sh \
             packages/luci-app-byte/htdocs/luci-static/resources/view/byte/overview.js; do
        [ -e "$repo_root/$f" ] || missing="$missing luci-app-byte($f)"
    done
    # luci-app-modeminfo was rewritten as a JS view over an rpcd exec plugin.
    # Assert both halves and assert the Lua ones are gone: the old controller
    # registered the same menu path, so a half-applied change renders either a
    # blank page or a duplicate menu entry.
    for f in packages/luci-app-modeminfo/files/usr/bin/modeminfo \
             packages/luci-app-modeminfo/files/usr/libexec/rpcd/modeminfo \
             packages/luci-app-modeminfo/files/usr/share/luci/menu.d/luci-app-modeminfo.json \
             packages/luci-app-modeminfo/files/usr/share/rpcd/acl.d/luci-app-modeminfo.json \
             packages/luci-app-modeminfo/files/www/luci-static/resources/view/modeminfo/overview.js; do
        [ -e "$repo_root/$f" ] || missing="$missing luci-app-modeminfo($f)"
    done
    for f in packages/luci-app-modeminfo/files/usr/lib/lua/luci/controller/modeminfo.lua \
             packages/luci-app-modeminfo/files/usr/lib/lua/luci/view/modeminfo.htm; do
        if [ -e "$repo_root/$f" ]; then
            forbidden="$forbidden modeminfo-lua-view($f)"
        fi
    done
    # The upstream promotion badges ("If you like my work…") are removed from
    # this fork on purpose: no sponsor assets, no shields.io calls from a
    # router UI on an isolated LAN.
    if grep -rqi "If you like my work\|shields.io\|Sponsor.svg\|Telegram.svg" \
        "$repo_root/packages/luci-app-modeminfo/files" 2>/dev/null; then
        forbidden="$forbidden modeminfo-promo-badge"
    fi
    # BYTE branding replaces the theme's LuCI logo. files/ is applied after the
    # theme package, so these three files are what the browser actually gets.
    for f in files/www/luci-static/footstrap/logo.svg \
             files/www/luci-static/footstrap/logo_48.png \
             files/www/luci-static/footstrap/app-icon-192.png \
             files/www/luci-static/footstrap/manifest.json; do
        [ -e "$repo_root/$f" ] || missing="$missing byte-branding($f)"
    done
    [ -x "$repo_root/files/etc/init.d/byte-selfcheck" ] || missing="$missing byte-selfcheck-init"
    [ -x "$repo_root/files/etc/hotplug.d/iface/91-byte-selfcheck" ] || missing="$missing byte-selfcheck-hotplug"
    [ -x "$repo_root/files/etc/init.d/byte-affinity" ] || missing="$missing byte-affinity-init"
    # Vendored LuCI apps live in packages/ and are copied into ./package/ by the
    # build script. If one goes missing the preset entry is silently dropped by
    # defconfig, so assert the source directories.
    for p in luci-app-netstat luci-app-ramfree luci-app-byte luci-app-modeminfo; do
        [ -f "$repo_root/packages/$p/Makefile" ] || missing="$missing vendored($p)"
    done
    # luci-app-netstat is the dotycat app with vnstat2 support patched in. If the
    # patch or the dependency fix is lost, the page renders with an empty
    # interface list and 0 B on vnstat 2.13 (that was the reported bug).
    if [ -f "$repo_root/packages/luci-app-netstat/Makefile" ]; then
        grep -q '^LUCI_DEPENDS:=.*vnstat2' "$repo_root/packages/luci-app-netstat/Makefile" || \
            missing="$missing netstat-dep-vnstat2"
        grep -q 'vnstat --iflist' \
            "$repo_root/packages/luci-app-netstat/files/usr/lib/lua/luci/view/vnstat.htm" || \
            missing="$missing netstat-vnstat2-parser"
    fi
    # Upstream's 99-vnstat runs `opkg remove vnstat2 && opkg install vnstat` on
    # first boot: needs the network, downgrades the binary and drops the DB.
    # Only executable lines count - the vendored script documents that command
    # in a comment and must not trip this.
    grep -rEn '^[[:space:]]*[^#[:space:]].*opkg remove vnstat2' \
        "$repo_root/packages/luci-app-netstat/" 2>/dev/null && \
        forbidden="$forbidden netstat-removes-vnstat2(defeats shipped vnstat2)"
    # luci-app-vnstat2 ("Traffic Monitor" under Status) duplicates the vendored
    # netstat app ("VnStats" under Tools): two menus, two parsers, one database.
    # The vnstat2/vnstati2 binaries stay - netstat needs them - but the extra
    # LuCI frontend must not ship. Keeps ~120 KB of view/po out of the image.
    grep -q '^CONFIG_PACKAGE_luci-app-vnstat2=y$' .config && \
        forbidden="$forbidden luci-app-vnstat2(duplicate of netstat frontend)"
    grep -q '^CONFIG_PACKAGE_luci-i18n-vnstat2-[a-z_-]*=y$' .config && \
        forbidden="$forbidden luci-i18n-vnstat2(translations for a dropped app)"
    # udp-broadcast-relay-redux is not in this build, and must stay out. It
    # floods every UDP broadcast to every bridged port, so the moment a user
    # attaches an IPTV box (IGMP joins, multicast-heavy) the LAN bridge turns
    # into a broadcast amplifier and IPTV playback stalls. IPTV belongs on its
    # own bridge/port with multicast snooping, not on a relay daemon. The old
    # preset carried a dead "is not set" line for it; that line is gone and this
    # gate keeps it from coming back through a dependency or a preset refresh.
    grep -q '^CONFIG_PACKAGE_udp-broadcast-relay-redux=y$' .config && \
        forbidden="$forbidden udp-broadcast-relay-redux(floods LAN, stalls IPTV)"
    grep -rn 'udp-broadcast-relay-redux' "$repo_root/preset" >/dev/null 2>&1 && \
        forbidden="$forbidden udp-broadcast-relay-redux-preset-line(stale entry)"
    # IPTV: multicast must stay on the port that joined it. The three br-lan
    # keys are what keep an HD stream off the WiFi airtime and stop the group
    # state from timing out; the upgrade path is the uci-defaults script (an
    # existing /etc/config/network is preserved by sysupgrade).
    local netcfg="$repo_root/files/etc/config/network"
    for k in igmp_snooping multicast_querier hash_max; do
        grep -q "^[[:space:]]*option $k '" "$netcfg" 2>/dev/null || \
            missing="$missing iptv-bridge-$k"
    done
    local mcast="$repo_root/files/etc/uci-defaults/93-byte-multicast"
    [ -x "$mcast" ] || missing="$missing iptv-multicast-uci-defaults"
    for k in igmp_snooping multicast_querier hash_max; do
        grep -q "set_default $k " "$mcast" 2>/dev/null || \
            missing="$missing iptv-multicast-$k"
    done
    # Branding: the box is "BYTE" everywhere an admin looks. The theme header
    # prints the hostname as its wordmark, so the hostname *is* the header text.
    # The logo cannot be done with CSS (the theme hardcodes the OpenWrt arcs as
    # inline SVG in its brand partial), so we override that partial - and assert
    # the theme still ships and includes it, or the override would sit unused
    # and the OpenWrt mark would come back with no build error.
    grep -q "^[[:space:]]*option hostname 'BYTE'$" "$repo_root/files/etc/config/system" 2>/dev/null || \
        missing="$missing branding-hostname"
    local brand="$repo_root/files/usr/share/ucode/luci/template/themes/footstrap/partials/brand.ut"
    [ -f "$brand" ] || missing="$missing branding-brand-template"
    grep -q 'fs-wordmark' "$brand" 2>/dev/null || missing="$missing branding-brand-markup"
    grep -q '00b5e2' "$brand" 2>/dev/null || missing="$missing branding-brand-mark"
    local theme=feeds/luci/themes/luci-theme-footstrap/ucode/template/themes/footstrap
    [ -f "$theme/partials/brand.ut" ] || \
        missing="$missing branding-theme-partial(check $theme)"
    grep -q 'partials/brand' "$theme/header.ut" 2>/dev/null || \
        missing="$missing branding-theme-include"
    [ -x "$repo_root/files/etc/uci-defaults/91-byte-identity" ] || \
        missing="$missing branding-rename-script"
    # luci-app-byte is the AdGuard Home + PassWall2 setup page, not a general
    # BYTE settings page. It sits under Tools next to unrelated apps and its
    # primary button moves dnsmasq off port 53, so the page has to say what it
    # does and the menu entry has to name it.
    grep -q 'AdGuard Home + PassWall2 setup' \
        "$repo_root/packages/luci-app-byte/htdocs/luci-static/resources/view/byte/overview.js" || \
        missing="$missing byte-purpose-notice"
    grep -q 'AdGuard Home + PassWall2' \
        "$repo_root/packages/luci-app-byte/root/usr/share/luci/menu.d/luci-app-byte.json" || \
        missing="$missing byte-menu-purpose"
    # Packet steering: images up to 1.2.0 shipped 0, and sysupgrade keeps the
    # old /etc/config/network, so a fresh unit needs the uci-defaults script and
    # an upgraded unit needs a writer that is not in /etc. Both are asserted.
    local steer="$repo_root/files/etc/uci-defaults/92-byte-steering"
    [ -x "$steer" ] || missing="$missing steering-uci-defaults"
    grep -q "packet_steering='1'" "$steer" 2>/dev/null || missing="$missing steering-value"
    grep -q "steering_flows='32768'" "$steer" 2>/dev/null || \
        missing="$missing steering-flows"
    # The boot service is the one that survives an upgrade: /etc/rc.local is in
    # keep.d and the uci-defaults script deletes itself, so only a file that
    # ships in the new squashfs with its own rc.d symlink runs every boot.
    local bsteer="$repo_root/files/etc/init.d/byte-steering"
    [ -x "$bsteer" ] || missing="$missing byte-steering-init"
    grep -q "^START=24$" "$bsteer" 2>/dev/null || \
        missing="$missing byte-steering-order(must precede packet_steering=25)"
    grep -q "^STEERING=1$" "$bsteer" 2>/dev/null || missing="$missing byte-steering-value"
    grep -q "^FLOWS=32768$" "$bsteer" 2>/dev/null || missing="$missing byte-steering-flows"
    [ -L "$repo_root/files/etc/rc.d/S24byte-steering" ] || \
        missing="$missing byte-steering-symlink(not enabled at boot)"
    # The image config has to agree with the service, otherwise a build without
    # the service would ship whatever the config happens to say.
    grep -qE "^[[:space:]]*option packet_steering '1'$" "$repo_root/files/etc/config/network" 2>/dev/null || \
        missing="$missing network-packet_steering"
    grep -qE "^[[:space:]]*option steering_flows '32768'$" "$repo_root/files/etc/config/network" 2>/dev/null || \
        missing="$missing network-steering_flows"
    # qca-nss-ecm used to force steering off at START=26 and on every network
    # reload (`uci set ...=0`, `uci del ...steering_flows`, `packet-steering.uc
    # 0`). apply_preset() rewrites that block into a reader; a feed bump that
    # brings the writer back is invisible in the build and only shows up as a
    # Disabled switch on the device.
    local ecm_init="feeds/nss/qca-nss-ecm/files/qca-nss-ecm.init"
    [ -f "$ecm_init" ] || missing="$missing ecm-init(not-in-feed)"
    grep -q '^apply_packet_steering() {' "$ecm_init" 2>/dev/null || \
        missing="$missing ecm-steering-reader(apply_packet_steering missing)"
    if grep -q 'disable_packet_steering\|packet_steering=0' "$ecm_init" 2>/dev/null; then
        forbidden="$forbidden ecm-disables-steering"
    fi
    # QModem voice / SIP on the AW1000 RJ11 port (fxsd <-> qmodem-voip <->
    # qmodem-sipd). Two things break silently on a feed bump:
    #  * AW1000 audio support lives in QModem main (PR #290), not in a release
    #    tag: v3.4.0_rc3.1's modem_supports.json has no RG500Q-EA profile at
    #    all, so qmodem_voip starts and then refuses every call.
    #  * at-daemon is versioned by feeds/qmodem/version.mk, and QModem voice
    #    needs 3.4.0 or newer.
    local qmv="feeds/qmodem/version.mk"
    grep -qE '^QMODEM_VERSION:=3\.([4-9]|[1-9][0-9])\.' "$qmv" 2>/dev/null || \
        missing="$missing qmodem-version(voice needs at-daemon >= 3.4.0)"
    local qmsup="feeds/qmodem/application/voipd/files/usr/share/qmodem/modem_supports.json"
    [ -f "$qmsup" ] || missing="$missing qmodem-voice-profiles(missing)"
    grep -q 'RG500Q-EA' "$qmsup" 2>/dev/null || \
        missing="$missing qmodem-aw1000-voice(RG500Q-EA profile absent: only QModem main has it)"
    grep -q 'pcm_socket' "$qmsup" 2>/dev/null || \
        missing="$missing qmodem-pcm-socket(AW1000 audio path)"
    [ -x "$repo_root/files/etc/init.d/byte-voip" ] || missing="$missing byte-voip-init"
    grep -q "^START=19$" "$repo_root/files/etc/init.d/byte-voip" 2>/dev/null || \
        missing="$missing byte-voip-order(must precede qmodem_init=80)"
    [ -L "$repo_root/files/etc/rc.d/S19byte-voip" ] || \
        missing="$missing byte-voip-symlink(not enabled at boot)"
    # IPv6 policy: the check must autodetect wanv6, measure real connectivity,
    # and be reversible. The regressions that matter are all silent on a built
    # image, so they are asserted here.
    local bv6="$repo_root/files/usr/libexec/byte-v6-check"
    [ -x "$bv6" ] || missing="$missing byte-v6-check"
    grep -q -- '--watch' "$bv6" 2>/dev/null || missing="$missing byte-v6-watch-mode"
    grep -q -- '--kick' "$bv6" 2>/dev/null || missing="$missing byte-v6-kick-mode"
    # Autodetect: qmodem deletes network.wanv6 on every redial, so the check has
    # to be able to recreate it, not just read it.
    grep -q 'ensure_wanv6()' "$bv6" 2>/dev/null || missing="$missing byte-v6-autodetect"
    grep -q 'ifup wanv6' "$bv6" 2>/dev/null || missing="$missing byte-v6-ifup-retry"
    # Real connectivity, not "an address exists": ICMPv6 plus a TCP fallback.
    grep -q 'ping6 ' "$bv6" 2>/dev/null || missing="$missing byte-v6-probe-icmp"
    grep -q 'wget -6' "$bv6" 2>/dev/null || missing="$missing byte-v6-probe-tcp"
    # PD-only carriers must be probed source-bound from the delegated prefix or
    # a working network gets demoted for lacking a WAN address.
    grep -qE 'ping6 .*-I ' "$bv6" 2>/dev/null || missing="$missing byte-v6-probe-source-bound"
    # Fail fast rather than blackhole, and only while demoted.
    grep -q 'unreachable default metric' "$bv6" 2>/dev/null || \
        missing="$missing byte-v6-fail-fast-route"
    # Demotion must be reversible from the snapshot. A hardcoded restore is the
    # regression: it turned a user's `ra=disabled` into `ra=server`.
    grep -q 'state_get RA' "$bv6" 2>/dev/null || missing="$missing byte-v6-state-snapshot"
    if grep -q "uci -q set dhcp.lan.ra='server'" "$bv6" 2>/dev/null; then
        forbidden="$forbidden byte-v6-hardcoded-restore(RA must come from the snapshot)"
    fi
    if grep -q "boot()" "$repo_root/files/etc/init.d/byte-v6" 2>/dev/null; then
        forbidden="$forbidden byte-v6-init-legacy(non-procd start: triggers never register)"
    fi
    grep -q '^USE_PROCD=1$' "$repo_root/files/etc/init.d/byte-v6" 2>/dev/null || \
        missing="$missing byte-v6-init-procd"
    grep -q -- '--watch' "$repo_root/files/etc/init.d/byte-v6" 2>/dev/null || \
        missing="$missing byte-v6-init-watcher"
    grep -q "^START=98$" "$repo_root/files/etc/init.d/byte-v6" 2>/dev/null || \
        missing="$missing byte-v6-order(after odhcpd)"
    [ -L "$repo_root/files/etc/rc.d/S98byte-v6" ] || \
        missing="$missing byte-v6-symlink(not enabled at boot)"
    [ -x "$repo_root/files/etc/hotplug.d/iface/30-byte-v6" ] || \
        missing="$missing byte-v6-hotplug"
    # The old hotplug handler started a second one-shot check per ifup; with a
    # watcher in place that races two uci commits.
    [ -e "$repo_root/files/etc/hotplug.d/iface/95-byte-v6" ] && \
        forbidden="$forbidden byte-v6-duplicate-hotplug(one-shot runner left behind)"
    # qmodem 3.4.0 moved the dial/driver menu options from luci-app-qmodem to
    # the qmodem package. A leftover PACKAGE_luci-app-qmodem_* line in the
    # preset is dropped by defconfig without a warning, which would silently
    # fall back to upstream defaults (generic QMI driver, normal quectel-cm).
    if grep -q '^CONFIG_PACKAGE_luci-app-qmodem_' "$repo_root/preset" 2>/dev/null; then
        forbidden="$forbidden preset-luci-app-qmodem-option(3.4.0 moved these to PACKAGE_qmodem_*)"
    fi
    # sms-forwarder and sms-forwarder-next declare PKG_CONFLICTS on each other,
    # and luci-app-qmodem-sms now depends on -next. Shipping both aborts image
    # assembly with a conflict; shipping only the old one silently loses the
    # SMS UI's backend.
    if grep -q '^CONFIG_PACKAGE_sms-forwarder=y$' .config; then
        forbidden="$forbidden sms-forwarder(conflicts with sms-forwarder-next)"
    fi
    # luci-app-modeminfo's install recipe used to copy ./files/etc and
    # ./files/www only, so menu.d/acl.d stayed in the source tree: the app
    # shipped with no menu item and rpcd answered "Permission denied". The page
    # is only reachable when both JSON files are installed, so assert them.
    for j in usr/share/luci/menu.d/luci-app-modeminfo.json \
             usr/share/rpcd/acl.d/luci-app-modeminfo.json; do
        [ -f "$repo_root/packages/luci-app-modeminfo/files/$j" ] || \
            missing="$missing modeminfo-json($j)"
        grep -q "$j" "$repo_root/packages/luci-app-modeminfo/Makefile" 2>/dev/null || \
            missing="$missing modeminfo-install($j)"
    done
    # Dashboard: the NSS offload card was replaced by a Storage card. The id
    # stays "nss" so /etc/config/dashboard from an upgraded unit still resolves;
    # the capacity bar and the tab-hiding rule live in the shipped custom.css.
    local dash="$repo_root/files/www/luci-static/resources/view/dashboard"
    grep -q "id: 'nss', slot: 'cards'" "$dash/include/48_nss.js" 2>/dev/null || \
        missing="$missing dashboard-storage-card"
    grep -q 'callSystemInfo' "$dash/include/48_nss.js" 2>/dev/null || \
        missing="$missing dashboard-storage-data"
    [ -f "$dash/icons/storage.svg" ] || missing="$missing dashboard-storage-icon"
    grep -q 'dashboard-storage-bar' "$dash/css/custom.css" 2>/dev/null || \
        missing="$missing dashboard-storage-css"
    grep -q '^\.Dashboard > \.cbi-map' "$dash/css/custom.css" 2>/dev/null || \
        missing="$missing dashboard-tabs-hidden"
    # ...and that no feed copy of the vendored netstat app survived anywhere
    # it would be scanned: a leftover duplicate PKG_NAME makes the scanner
    # keep the feed copy (which lacks po/) and the i18n symbol disappears
    # from .config. The feeds/ source dir itself is harmless (nothing scans
    # it directly) and stays for the next feeds update.
    for dup in package/feeds/luci/luci-app-netstat package/feeds/dotycat/luci-app-netstat \
               feeds/luci/applications/luci-app-netstat; do
        [ -e "$dup" ] && forbidden="$forbidden netstat-feed-copy-remains($dup - duplicate PKG_NAME drops the i18n symbol)"
    done
    # The self-check reads these files as the source of truth; a missing key
    # would make it assert the wrong thing.
    for k in net.ipv4.tcp_congestion_control net.core.default_qdisc \
             net.ipv4.tcp_mtu_probing net.ipv4.tcp_slow_start_after_idle; do
        grep -q "^${k} = " "$repo_root/files/etc/sysctl.conf" 2>/dev/null || \
            missing="$missing sysctl($k)"
    done
    grep -q "option governor0 'performance'" "$repo_root/files/etc/config/cpufreq" 2>/dev/null || \
        missing="$missing cpufreq(performance)"
    # The hourly drop_caches/swapoff crontab was removed on purpose (it stalls
    # the box for no gain). Fail the build if it reappears. Only live entries
    # count - comments in the file document the removal and must not match.
    if grep -vE '^[[:space:]]*#' "$repo_root/files/etc/crontabs/root" 2>/dev/null |
        grep -qE 'drop_caches|swapoff'; then
        forbidden="$forbidden CRON(drop_caches/swapoff)"
    fi
    # Every feed base-files emits a distfeeds line for must also exist in the
    # published repo, or opkg gets a 404 and reports "no such file or
    # directory" for that feed. Adding a feed to the build without adding it to
    # the repo is exactly that failure, so fail the build instead.
    # "base" is deliberately absent: it has no CONFIG_FEED_* symbol and is
    # always emitted by base-files, so requiring one would always fail.
    local f
    for f in luci packages qmodem nss fxs dotycat passwall_luci \
             routing telephony video nikki; do
        grep -q "^CONFIG_FEED_${f}=y$" .config || \
            forbidden="$forbidden FEED_WITHOUT_REPO_DIR($f)"
    done

    # A package listed as both "=y" and "is not set" in the preset resolves to
    # whichever appears last, so an appended block silently loses to an older
    # negative line. That is how build 30 failed: 14 required packages were
    # "=y" in the preset yet absent from .config. Catch the contradiction
    # before it reaches defconfig.
    local repo_root_check conflicted
    repo_root_check="$(realpath "$script_dir" 2>/dev/null)"
    [ -n "$repo_root_check" ] || repo_root_check="$(realpath .)"
    conflicted=$(grep -oE '^CONFIG_PACKAGE_[A-Za-z0-9_-]+=y$' "$repo_root_check/preset" 2>/dev/null |
        sed 's/^CONFIG_PACKAGE_//; s/=y$//' |
        while read -r pn; do
            grep -qx "# CONFIG_PACKAGE_${pn} is not set" "$repo_root_check/preset" && echo "$pn"
        done | tr '\n' ' ')
    [ -z "$conflicted" ] || forbidden="$forbidden PRESET_CONFLICT($(echo $conflicted | tr ' ' ','))"

    # The distfeeds must point at the self-hosted opkg repo. ImmortalWrt 25.12
    # publishes only .apk feeds (opkg asks for Packages.gz, the mirror serves
    # packages.adb), so any downloads.immortalwrt.org URL makes every feed fail
    # with "wget returned 8" and `opkg update` is dead on the device.
    grep -q '^CONFIG_VERSION_REPO="https://raw.githubusercontent.com/Ace1337z/AW1000_BYTE/repo"' .config || \
        missing="$missing VERSION_REPO(raw-github-kmod-repo)"
    if grep -q '^CONFIG_VERSION_REPO=.*downloads.immortalwrt.org' .config; then
        forbidden="$forbidden VERSION_REPO(apk-only-mirror)"
    fi

    # qmodem AT plumbing. override_at_port/sms_at_port pointing at
    # /dev/ttyUSB2 makes tom_modem hang there on the RG500Q: the qmodem
    # "WAN" panel then shows empty Manufacturer/Revision/Temperature and
    # Connect Status "No" while the uplink is actually up. Since 3.3.0 every
    # AT consumer (dial, SMS, the RJ11 phone) must share ubus-at-daemon, so
    # use_ubus=1 is required and the daemon must actually be in the image.
    grep -q "option use_ubus '1'" "$repo_root/files/etc/config/qmodem" 2>/dev/null || \
        missing="$missing qmodem-use_ubus1"
    grep -q "option at_port '/dev/ttyUSB3'" "$repo_root/files/etc/config/qmodem" 2>/dev/null || \
        missing="$missing qmodem-at_port"
    grep -q "^CONFIG_PACKAGE_ubus-at-daemon=y$" "$repo_root/preset" 2>/dev/null || \
        missing="$missing ubus-at-daemon"
    if grep -qE "^[[:space:]]*option (override_at_port|sms_at_port) " "$repo_root/files/etc/config/qmodem" 2>/dev/null; then
        forbidden="$forbidden qmodem-ttyUSB2-override"
    fi
    # AW1000 phone (RJ11). The driver and daemon are built in-tree from the
    # pinned feed, against the same kernel as the image, so a kernel/tag change
    # is the only way this silently breaks. Assert the three packages, the
    # pin, and the 0.7.0 config schema: fxsd ignores unknown options, which
    # means a stale config does not fail loudly, it just loses the new keys.
    for pn in kmod-aw1000-fxs fxsd luci-app-fxs; do
        grep -q "^CONFIG_PACKAGE_${pn}=y$" "$repo_root/preset" 2>/dev/null || \
            missing="$missing phone($pn)"
    done
    grep -q '^[[:space:]]*echo .*src-git fxs .*openwrt-aw1000-phone.*\^a764a2d3934a1aeeeab74f30160994e6a1c5ffe3' \
        "$repo_root/aw1000_byte.sh" 2>/dev/null || \
        missing="$missing phone-feed-pin(v0.7.0)"
    # Kernel/tag pairing: the phone kmod is published for 6.12.94, which is
    # tag v25.12.1. A default that drifts away from it silently ships an
    # unverified SLIC driver.
    grep -q 'target_branch="${TARGET_BRANCH:-v25.12.1}"' "$repo_root/aw1000_byte.sh" 2>/dev/null || \
        missing="$missing kernel-tag(v25.12.1=6.12.94)"
    grep -q "default: v25.12.1" "$repo_root/.github/workflows/build.yml" 2>/dev/null || \
        missing="$missing workflow-tag(v25.12.1)"
    for k in at_port enabled volume ring_pattern callerid callerid_timing \
             hd sip ringback history_days; do
        grep -q "^[[:space:]]*option ${k} " "$repo_root/files/etc/config/fxs" 2>/dev/null || \
            missing="$missing fxs-config($k)"
    done
    grep -q "option at_port 'auto'" "$repo_root/files/etc/config/fxs" 2>/dev/null || \
        missing="$missing fxs-config(at_port=auto)"
    # Firmware version: Status -> Overview must read
    #   BYTE 25.12(<kernel>) <major>.<minor>.<patch>
    # The patch is derived from commit count since FW_BASE, so this only works
    # if version.env is present and CI checks out full history.
    [ -f "$repo_root/version.env" ] || missing="$missing version.env"
    grep -q '^FW_BASE=[0-9a-f]\{40\}$' "$repo_root/version.env" 2>/dev/null || \
        missing="$missing version.env(FW_BASE)"
    grep -q 'apply_version' "$repo_root/aw1000_byte.sh" 2>/dev/null || \
        missing="$missing apply_version"
    grep -q 'fetch-depth: 0' "$repo_root/.github/workflows/build.yml" 2>/dev/null || \
        missing="$missing version(fetch-depth-0)"
    # version.env is a build input: without it in the push paths filter, editing
    # the version would silently produce no new image.
    awk '/^on:/,/^permissions:/' "$repo_root/.github/workflows/build.yml" 2>/dev/null | \
        grep -q '^ *- version\.env$' || \
        missing="$missing version(workflow-path)"
    # Release naming. The GitHub release used to be tagged and titled
    # "BYTE_by_ACE-FINAL-..." from a hardcoded string, so every build published
    # under the same "FINAL" name and a body describing an older firmware.
    # Identity now comes from the .config the image was built from, and the
    # body is the current README changelog block. Fail if any of that is
    # replaced with a literal again.
    if grep -qE 'TAG: *BYTE_by_ACE-FINAL|TITLE: *BYTE by ACE . FINAL' \
        "$repo_root/.github/workflows/build.yml" 2>/dev/null; then
        forbidden="$forbidden release(static-FINAL-tag-or-title)"
    fi
    grep -q 'FW_CODE=$(cfg_get CONFIG_VERSION_CODE)' \
        "$repo_root/.github/workflows/build.yml" 2>/dev/null || \
        missing="$missing release(derive-version-from-config)"
    grep -q 'TAG="BYTE_by_ACE-${FW_CODE}-${TARGET_BRANCH}-${GITHUB_RUN_NUMBER}"' \
        "$repo_root/.github/workflows/build.yml" 2>/dev/null || \
        missing="$missing release(tag-carries-version)"
    grep -q 'TITLE="BYTE ${FW_RELEASE} VERSION ${FW_CODE}' \
        "$repo_root/.github/workflows/build.yml" 2>/dev/null || \
        missing="$missing release(title-carries-version)"
    grep -q 'FW_CODE="$FW_CODE" FW_RELEASE="$FW_RELEASE" FW_KERNEL="$FW_KERNEL"' \
        "$repo_root/.github/workflows/build.yml" 2>/dev/null || \
        missing="$missing release(notes-env)"
    grep -q 'want="# BYTE ${FW_RELEASE} VERSION ${FW_CODE}"' \
        "$repo_root/.github/workflows/build.yml" 2>/dev/null || \
        missing="$missing release(notes-header-check)"
    # The notes script must not fall back to a typed header either: its title
    # line has to be built from the version it was handed.
    grep -q 'n "# BYTE ${release} VERSION ${code}"' \
        "$repo_root/.github/release-notes-final.sh" 2>/dev/null || \
        missing="$missing release-notes(derived-header)"
    if grep -qE '^n "# BYTE by ACE' "$repo_root/.github/release-notes-final.sh" 2>/dev/null; then
        forbidden="$forbidden release-notes(static-header)"
    fi
    # The dashboard include/*.js widgets need view/dashboard/lib/* from the luci
    # feed and land as a silent no-op on an older pin, so pin and payload are
    # both asserted. The pin lives in feeds.conf.default (written with sed from
    # the pattern below), so assert the generated line, not a string in this
    # script - the literal "luci.git^<sha>" never appears here.
    grep -q 'luci\.git\^350fc919675bb62e415927afff65697fcb8f775d' feeds.conf.default 2>/dev/null || \
        missing="$missing luci-feed-pin(dashboard-lib)"
    [ -f feeds/luci/modules/luci-mod-dashboard/htdocs/luci-static/resources/view/dashboard/lib/charts.js ] || \
        missing="$missing dashboard-lib(charts.js)"
    # Footstrap comes from the upstream standalone repo, and that feed line must
    # come BEFORE the luci line: scripts/feeds installs only the first feed that
    # provides a source name and skips the rest without a word, so a later line
    # would silently ship the luci feed's divergent older copy.
    grep -q 'VizzleTF/luci-theme-footstrap\.git\^b9967e43c5ec09aec0771cfeecde35525640fd9d' \
        "$repo_root/aw1000_byte.sh" 2>/dev/null || \
        missing="$missing footstrap-feed-pin(0.14.19)"
    # Order in the generated feeds.conf.default, not in this script: the line is
    # inserted with sed's `i`, so the two orders below are the whole difference
    # between shipping 0.14.19 and silently shipping the luci feed's copy.
    awk '/^src-git luci /{ l = NR } /^src-git footstrap /{ f = NR } END { exit !(f && l && f < l) }' \
        feeds.conf.default 2>/dev/null || \
        missing="$missing footstrap-feed-order(before-luci)"
    # The install directory is the proof: package/feeds/<feed>/<pkg> only exists
    # for the feed scripts/feeds actually picked, so a lost ordering race shows
    # up here instead of as an unexpectedly old theme on the router.
    [ -f package/feeds/footstrap/luci-theme-footstrap/Makefile ] || \
        missing="$missing footstrap-from-feed(footstrap)"
    # Anything the boot sequence executes must carry the exec bit in git: the
    # image copies these files verbatim, so a 100644 init script is installed
    # and never run (this bit qmodem_ttl once, which made the TTL rule absent).
    for f in "$repo_root"/files/etc/init.d/* "$repo_root"/files/etc/hotplug.d/iface/* \
        "$repo_root"/files/etc/uci-defaults/* "$repo_root"/files/etc/rc.local \
        "$repo_root"/files/usr/sbin/* "$repo_root"/files/usr/bin/* \
        "$repo_root"/files/usr/libexec/*; do
        [ -e "$f" ] || continue
        [ -x "$f" ] || missing="$missing not-exec(${f#"$repo_root"/})"
    done
    # Repo signing key: the copy must happen in the build script *after* the
    # clone (the tree does not exist before it), and no workflow step may copy
    # into builder/immortalwrt - that failed every cold-cache run outright.
    keycall=$(grep -n 'install_repo_key ||' "$repo_root/aw1000_byte.sh" 2>/dev/null | cut -d: -f1 | head -1)
    keyclone=$(grep -n 'GIT CLONE FAILED' "$repo_root/aw1000_byte.sh" 2>/dev/null | cut -d: -f1 | head -1)
    if [ -n "$keycall" ] && [ -n "$keyclone" ] && [ "$keycall" -gt "$keyclone" ] 2>/dev/null; then
        :
    else
        missing="$missing repo-key(after-clone)"
    fi
    if grep -q 'install-repo-key.sh' "$repo_root/.github/workflows/build.yml" 2>/dev/null; then
        missing="$missing workflow(pre-clone-key-step)"
    fi
    # Kernel patch level comes from target/linux/generic/kernel-<PATCHVER>,
    # resolved through CONFIG_TARGET_BOARD. The old include/version.mk fallback
    # returned its "x" placeholder and shipped "25.12(x)".
    awk '/^apply_version\(\)/,/^}/' "$repo_root/aw1000_byte.sh" 2>/dev/null |
        grep -q 'target/linux/generic/kernel-' || \
        missing="$missing version(kernel-detail-file)"
    if awk '/^apply_version\(\)/,/^}/' "$repo_root/aw1000_byte.sh" 2>/dev/null |
        grep -q 'KERNEL_VERSION:='; then
        missing="$missing version(version.mk-placeholder)"
    fi
    # Every local image the README references must exist, or the page renders a
    # broken image on GitHub. Remote (http) references are skipped.
    for img in $(grep -oE '!\[[^]]*\]\([^)]*\)' "$repo_root/README.md" 2>/dev/null |
        sed -e 's/^.*](//' -e 's/)$//' | grep -v '^http'); do
        [ -e "$repo_root/$img" ] || missing="$missing readme-image($img)"
    done
    grep -q '^CONFIG_VERSION_DIST="BYTE"$' "$repo_root/preset" 2>/dev/null || \
        missing="$missing preset(VERSION_DIST)"
    # Image filenames must carry the derived version, not the static preset
    # value: rename_output has to read .config first, or the downloaded file
    # says 1.2.1 while Status says 1.2.2 after the next commit.
    awk '/^rename_output\(\)/,/^}/' "$repo_root/aw1000_byte.sh" 2>/dev/null | \
        grep -q 'CONFIG_VERSION_CODE=.*\./\.config' || \
        missing="$missing rename(VERSION_CODE from .config)"
    # Status -> Overview prints `release.description`; upstream appends the Lua
    # CI (LuCI) version to it. Assert the override exists and really dropped
    # that suffix - otherwise the row reads "BYTE ... 1.2.1 / luci-25.12.1".
    sysview="files/www/luci-static/resources/view/status/include/10_system.js"
    if [ -e "$repo_root/$sysview" ] &&
        grep -q "boardinfo.release.description" "$repo_root/$sysview" 2>/dev/null &&
        ! grep -q "release.description + ' / '" "$repo_root/$sysview" 2>/dev/null; then
        :
    else
        missing="$missing status-firmware-version($sysview)"
    fi
    grep -q '^# CONFIG_USE_APK is not set$' .config || missing="$missing IPK(opkg)"
    if [ -n "$forbidden" ]; then
        echo -e "${BOLD_RED}FORBIDDEN CONFIG (see reasons in aw1000_byte.sh):$forbidden${RESET}"
        return 1
    fi
    if [ -n "$missing" ]; then
        echo -e "${BOLD_RED}MISSING REQUIRED CONFIG:$missing${RESET}"
        return 1
    fi
    echo -e "${BOLD_GREEN}ALL REQUIRED PACKAGES PRESENT IN .config${RESET}"
}

start_build() {
    get_version
    while true; do
        echo -e "${BOLD_YELLOW}STARTING BUILD WITH $(nproc) CORES${RESET}"
        start=$(date +%s)

        if make -j"$(nproc)"; then
            dur=$(( $(date +%s) - start ))
            rename_output
            echo -e "${BOLD_YELLOW}BUILD VERSION: ${version_branch}${version_tag}${RESET}"
            echo -e "${BOLD_BLUE}OUTPUT DIRECTORY: $(pwd)/bin/targets/${RESET}"
            printf "${BOLD_GREEN}BUILD COMPLETED IN %02dh %02dm %02ds${RESET}\n" \
                $((dur / 3600)) $(((dur % 3600) / 60)) $((dur % 60))
            # Only clean up when running standalone (not from a repo checkout/CI).
            if [ -z "$CI" ] && [ "$preset_folder" != "$(realpath "$script_dir")" ]; then
                rm -rf "$preset_folder"; rm -f -- "$script_path"
            fi
            exit 0
        else
            echo -e "${BOLD_RED}BUILD FAILED. RETRYING WITH VERBOSE OUTPUT${RESET}"
            make -j1 V=s
            if [ -n "$CI" ]; then
                echo -e "${BOLD_RED}CI BUILD FAILED${RESET}"
                exit 1
            fi
            read -rp "${BOLD_RED}PLEASE FIX ERRORS AND PRESS ENTER TO RETRY: ${RESET}"
            make distclean
            update_feeds || return 1
            select_target
            apply_preset
            run_menuconfig
        fi
    done
}

build_menu() {
    cd "$distro" || exit 1
    select_target
    update_feeds || exit 1
    apply_preset
    make defconfig
    if [ -n "$CI" ]; then ci_check_packages || exit 1; fi
    run_menuconfig
    start_build
}

rebuild_menu() {
    clear 2>/dev/null || true
    echo -e "${BOLD_MAGENTA}##############################################${RESET}"
    echo -e "${BOLD_MAGENTA}          BYTE by ACE REBUILD MENU              ${RESET}"
    echo -e "${BOLD_MAGENTA}##############################################${RESET}"
    echo -e "${BOLD_BLUE}REBUILD MENU:${RESET}"
    echo -e "1) FIRMWARE & PACKAGE UPDATE (FULL REBUILD)"
    echo -e "2) FIRMWARE UPDATE (FAST REBUILD)"
    echo -e "3) CONFIG UPDATE (FAST REBUILD)"
    echo -e "4) EXISTING UPDATE (NO CHANGES)"

    while true; do
        read -rp "${BOLD_BLUE}CHOOSE OPTION: ${RESET}" opt
        case "$opt" in
            1)
                echo -e "${BOLD_YELLOW}REMOVING EXISTING BUILD DIRECTORY: $distro${RESET}"
                rm -rf "$distro"
                git clone "$repo" "$distro" || {
                    echo -e "${BOLD_RED}ERROR: GIT CLONE FAILED${RESET}"
                    exit 1
                }
                cd "$distro" || exit 1
                select_target
                update_feeds || exit 1
                apply_preset
                make defconfig
                run_menuconfig
                start_build
                ;;
            2)
                cd "$distro" || exit 1
                make clean
                select_target
                apply_preset
                make defconfig
                start_build
                ;;
            3)
                cd "$distro" || exit 1
                rm -f .config
                apply_preset
                make defconfig
                run_menuconfig
                start_build
                ;;
            4)
                cd "$distro" || exit 1
                start_build
                ;;
            *)
                echo -e "${BOLD_RED}INVALID CHOICE${RESET}"
                ;;
        esac
    done
}

main_menu
if [ -n "$CI" ] || [ "$just_cloned" = "1" ]; then
    build_menu
else
    rebuild_menu
fi
