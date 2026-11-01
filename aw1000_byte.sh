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
    echo -e "${BOLD_MAGENTA}            TELEGRAM: @NIALVPN                ${RESET}"
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
    # Pinned to v3.3.0 (1913bfb27) - latest stable release.
    # The 3.x line no longer defines the old "qmodem_runtime" netifd protocol
    # (verified: no occurrence anywhere in the v3.3.0 tree), so the WAN
    # interface is still written as a plain proto=dhcp - the reason 2.8.9 was
    # pinned in the first place. Cross-major jumps skip 3.0-3.2: the upstream
    # migration note says to back up UCI and to verify at-daemon, SMS backend
    # and the dial after upgrading.
    sed -i '\#^src-git qmodem #d' feeds.conf.default 2>/dev/null
    echo 'src-git qmodem https://github.com/FUjr/QModem.git^1913bfb272de39adb7b1ef79b91706368fd89399' >> feeds.conf.default
    # passwall2 luci app, pinned to 26.4.10 (4b4b84dc1) - the version proven
    # working on the DOTYWRT AW1000. Newer passwall2 hardcodes
    # xray_min_version="26.7.11" AND injects version.min into every generated
    # config, which makes older xray refuse to start; 26.4.10 has neither.
    grep -q '^src-git passwall_luci ' feeds.conf.default 2>/dev/null || \
        echo 'src-git passwall_luci https://github.com/Openwrt-Passwall/openwrt-passwall2.git^4b4b84dc120bb37592ea51e7107ce4fe0083420f' >> feeds.conf.default
    # vantage theme + dashboard: dropped. The image ships Footstrap only -
    # keeping a second JS theme costs space and its luci-app-vantage dashboard
    # duplicates pages the Vantage-derived widgets now provide.
    sed -i '\#^src-git vantage #d' feeds.conf.default 2>/dev/null
    # luci feed: the v25.12.1 pin (ed7692cb, 2026-07-06) predates the Footstrap
    # theme, which landed on the branch on 2026-09-03. defconfig drops unknown
    # symbols silently, so CONFIG_PACKAGE_luci-theme-footstrap=y was ignored,
    # the image shipped Bootstrap, and the BYTE logo overrides under files/
    # (footstrap assets) had no theme to attach to. Pin the last commit of the
    # theme's landing series: same day, so the feed stays as close to the
    # release tag as having the theme allows.
    sed -i -E 's#^(src-git luci https://github\.com/immortalwrt/luci\.git)\^[0-9a-f]+#\1^17b3c7daab81c06396f0d9eb35012777dbc36436#' feeds.conf.default
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
    # dotycat packages: luci-app-aw1k-led (AW1000 LED controller), etc.
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
    # footstrap theme ships in immortalwrt/luci, no external feed needed

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

    # qca-nss-ecm stays in the *tree* but not in the *image*: the preset has
    # "# CONFIG_PACKAGE_kmod-qca-nss-ecm is not set", the same choice
    # XT-Martinez/aw1000-feed makes. Reasons: ECM 12.5.2024.11.06 does not
    # build on 6.12.x past the .9x series (ecm_bond_notifier.c, struct bond_cb),
    # so enabling it would pin the kernel away from the version the AW1000
    # phone driver is validated against, and ECM forwards established flows
    # past netfilter, which defeats the TTL rewrite. The sources and their
    # kernel-port patches stay in nss/feeds/nss/qca-nss-ecm/patches/ so the
    # experiment is one preset line + TARGET_BRANCH=v25.12.1 away.
    echo -e "${BOLD_GREEN}qca-nss-ecm sources kept, package not selected (see preset)${RESET}"

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
    # luci-app-netstat is vendored from packages/luci-app-netstat. If an
    # upstream feed ever ships the same name, two packages would provide one
    # Kconfig symbol and defconfig aborts - the same failure shape as
    # weechat-full above. The vendored copy lives in package/, so removing the
    # feed copy is safe.
    rm -rf package/feeds/luci/luci-app-netstat feeds/luci/applications/luci-app-netstat
    echo -e "${BOLD_GREEN}luci-app-netstat FEED COPY REMOVED (vendored package wins)${RESET}"
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
        echo "CONFIG_VERSION_NUMBER=\"25.12(${kernel})\""
        echo "CONFIG_VERSION_CODE=\"${ver}\""
    } >> .config
    echo -e "${BOLD_GREEN}FIRMWARE VERSION: BYTE 25.12(${kernel}) ${ver}${RESET}"
}

# CI-only: fail fast if the preset did not resolve the required packages.
ci_check_packages() {
    local missing="" p
    # openclash / adguardhome are intentionally not shipped (size); the
    # proxy stack is passwall + passwall2 with the Xray core only.
    # passwall v1 is deliberately absent: it and passwall2 both install redirect
    # rules on the same nft table and hijack port 53, so they cannot coexist -
    # v1 gets torn down and looks "not running". Only passwall2 ships; require
    # that v1 stays out.
    if grep -q '^CONFIG_PACKAGE_luci-app-passwall=y$' .config; then
        forbidden="$forbidden passwall-v1(ships alongside passwall2, cannot coexist)"
    fi
    for p in luci-app-passwall2 \
             luci-theme-footstrap \
             luci-app-qmodem qmodem modem_scan tom_modem \
             luci-app-netstat vnstat2 \
             kmod-aw1000-fxs fxsd luci-app-fxs \
             kmod-qca-nss-drv nss-firmware \
             kmod-qmi_wwan_q luci-app-modeminfo \
             luci-app-aw1k-led luci-app-byte luci-app-ramfree \
             xray-core \
             luci-app-filemanager \
             luci-app-qmodem-sms luci-app-qmodem-ttlfw4 sms-forwarder sms-tool_q ubus-at-daemon \
             kmod-ifb kmod-sched-cake kmod-sched-core kmod-ipt-ipset \
             kmod-macvlan kmod-nf-ipt kmod-nft-socket kmod-nf-nathelper \
             kmod-nf-nathelper-extra ipset tc-tiny iptables-nft \
             iptables-mod-conntrack-extra iptables-mod-ipopt ruby \
             rpcd-mod-rpcsys; do
        grep -q "^CONFIG_PACKAGE_${p}=y$" .config || missing="$missing $p"
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
    local forbidden=""
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
    # ECM stays out on purpose (see the preset): its 6.12 port does not build on
    # the branch kernel, and it would bypass the TTL rewrite. Enabling it is a
    # deliberate experiment, not something that should slip into a release.
    grep -q "^CONFIG_PACKAGE_kmod-qca-nss-ecm=y$" .config && \
        forbidden="$forbidden kmod-qca-nss-ecm(see preset: build-breaker on this kernel)"
    # Same for the two TTL apps: the Lua one writes its own firewall include
    # and the fw4 one writes /etc/nftables.d/99-reset-ttl-from-br-lan.nft, so
    # both would fight over the same packets (and only the fw4 one parks ECM).
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
    # NOTE: ci_check_packages runs with CWD=immortalwrt, so repo paths must be
    # resolved via $script_dir rather than assumed relative.
    local repo_root="$(realpath "$script_dir" 2>/dev/null)"
    [ -n "$repo_root" ] || repo_root="$(realpath .)"
    # TTL is owned by luci-app-qmodem-ttlfw4 now: one UCI switch and one TTL
    # value (1-255), and the service also parks ECM while it is on. Assert the
    # shipped defaults and that the app is in the image, because a missing app
    # means the image loses TTL rewriting entirely - silently.
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
    grep -q 'luci\.git\^17b3c7da' "$repo_root/aw1000_byte.sh" 2>/dev/null || \
        missing="$missing luci-feed-pin(footstrap)"
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
    echo -e "${BOLD_MAGENTA}            TELEGRAM: @NIALVPN                ${RESET}"
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
