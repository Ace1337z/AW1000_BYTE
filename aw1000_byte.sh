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
    # Latest OpenWrt (ImmortalWrt 25.12) by default; override with TARGET_BRANCH=...
    target_branch="${TARGET_BRANCH:-openwrt-25.12}"

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
}

update_feeds() {
    echo -e "${BOLD_YELLOW}ADDING EXTERNAL FEEDS (QMODEM, PASSWALL2, VANTAGE)${RESET}"
    # qmodem: modem management (replaces 3ginfo/modemband/sms-tool-js).
    # Pinned to v2.8.9 (052f84477) - the exact version running on the working
    # DOTYWRT AW1000. The 3.x line introduced the "qmodem_runtime" netifd
    # protocol and host_ipv4_owner handling, which can leave network.wan with
    # a proto LuCI has no form for (the WAN page then shows no preset). 2.8.9
    # always writes a plain proto=dhcp interface.
    grep -q '^src-git qmodem ' feeds.conf.default 2>/dev/null || \
        echo 'src-git qmodem https://github.com/FUjr/QModem.git^052f8447770014fbcbcad895f56a618a9d5537a4' >> feeds.conf.default
    # passwall2 luci app, pinned to 26.4.10 (4b4b84dc1) - the version proven
    # working on the DOTYWRT AW1000. Newer passwall2 hardcodes
    # xray_min_version="26.7.11" AND injects version.min into every generated
    # config, which makes older xray refuse to start; 26.4.10 has neither.
    grep -q '^src-git passwall_luci ' feeds.conf.default 2>/dev/null || \
        echo 'src-git passwall_luci https://github.com/Openwrt-Passwall/openwrt-passwall2.git^4b4b84dc120bb37592ea51e7107ce4fe0083420f' >> feeds.conf.default
    # vantage theme + dashboard (external feed); drop the old upstream URL if present
    sed -i '\#^src-git vantage https://github.com/anothaDev/luci-theme-vantage.git#d' feeds.conf.default 2>/dev/null
    grep -q '^src-git vantage ' feeds.conf.default 2>/dev/null || \
        echo 'src-git vantage https://github.com/Ace1337z/luci-theme-vantage.git;main' >> feeds.conf.default
    # NSS offload: qca-nss-drv + qca-nss-ecm (QSDK 12.5, kernel 6.12 patches)
    grep -q '^src-git nss ' feeds.conf.default 2>/dev/null || \
        echo 'src-git nss https://github.com/qosmio/nss-packages.git;NSS-12.5-K6.x' >> feeds.conf.default
    # AW1000 RJ11 phone port: kmod-aw1000-fxs, fxsd, luci-app-fxs (packages live in openwrt/)
    grep -q '^src-git fxs ' feeds.conf.default 2>/dev/null || \
        echo 'src-git fxs https://github.com/Ace1337z/openwrt-aw1000-phone.git;main' >> feeds.conf.default
    # dotycat packages: luci-app-aw1k-led (AW1000 LED controller), etc.
    grep -q '^src-git dotycat ' feeds.conf.default 2>/dev/null || \
        echo 'src-git dotycat https://github.com/dotywrt/dotycat-package.git;dotycat' >> feeds.conf.default
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

    # qca-nss-ecm 12.5.2024.11.06 cannot compile against kernel 6.12.112
    # (struct bond_cb was reworked), and ECM offload bypasses netfilter so it
    # would defeat the TTL-64 rewrite anyway. A "# CONFIG_... is not set" line
    # in the preset proved unreliable across fresh feed checkouts, so remove
    # the package from the tree outright: with no Makefile there is nothing
    # for defconfig or `make world` to enable.
    rm -rf package/feeds/nss/qca-nss-ecm feeds/nss/qca-nss-ecm
    echo -e "${BOLD_GREEN}qca-nss-ecm REMOVED FROM TREE${RESET}"
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
    local f b d nb
    [ -d "$dir" ] || return 0

    # 1) Rename image + metadata files.
    while IFS= read -r f; do
        d="$(dirname "$f")"
        b="$(basename "$f")"
        nb="$(printf '%s' "$b" | sed \
            -e 's/ImmortalWrt/BYTE_by_ACE/g' \
            -e 's/immortalwrt/BYTE_by_ACE/g' \
            -e 's/^byte-by-ace-/BYTE_by_ACE-/' \
            -e 's/^byte-/BYTE_by_ACE-/')"
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

# CI-only: fail fast if the preset did not resolve the required packages.
ci_check_packages() {
    local missing="" p
    for p in luci-app-passwall luci-app-passwall2 luci-app-openclash \
             luci-theme-footstrap luci-theme-vantage luci-app-vantage \
             luci-app-adguardhome adguardhome luci-app-qmodem qmodem \
             kmod-aw1000-fxs fxsd luci-app-fxs \
             kmod-qca-nss-drv nss-firmware \
             kmod-qmi_wwan_q luci-app-modeminfo \
             luci-app-aw1k-led luci-app-ramfree; do
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
    # luci-app-nft-ttl rewrites /etc/nftables.d/ttl64.nft with a postrouting
    # rule keyed on iifname; our byte-ttl owns that file instead.
    if grep -q "^CONFIG_PACKAGE_luci-app-nft-ttl=y$" .config; then
        forbidden="$forbidden luci-app-nft-ttl"
    fi
    # ECM must not be built: it does not compile on kernel 6.12.112 and it
    # would bypass the TTL rewrite. apply_preset deletes the package, so any
    # reappearance means the deletion did not happen.
    if grep -q "^CONFIG_PACKAGE_kmod-qca-nss-ecm=y$" .config; then
        forbidden="$forbidden kmod-qca-nss-ecm"
    fi
    [ -e package/feeds/nss/qca-nss-ecm ] && forbidden="$forbidden qca-nss-ecm-tree"
    # TTL must default to 64 on the modem uplink - this is the single most
    # important behaviour of the image (tethering detection).
    # NOTE: ci_check_packages runs with CWD=immortalwrt, so repo paths must be
    # resolved via $script_dir rather than assumed relative.
    local repo_root="$(realpath "$script_dir" 2>/dev/null)"
    [ -n "$repo_root" ] || repo_root="$(realpath .)"
    grep -qE "^[[:space:]]*option ttl4 '64'$" "$repo_root/files/etc/config/qmodem_ttl" 2>/dev/null || \
        missing="$missing TTL64(qmodem_ttl.ttl4)"
    grep -qE "^[[:space:]]*option enable '1'$" "$repo_root/files/etc/config/qmodem_ttl" 2>/dev/null || \
        missing="$missing TTL-ENABLED(qmodem_ttl.enable)"
    [ -x "$repo_root/files/etc/init.d/byte-ttl" ] || missing="$missing byte-ttl-init"
    grep -q 'oifname' "$repo_root/files/etc/nftables.d/ttl64.nft" 2>/dev/null || \
        missing="$missing TTL-RULE(oifname)"
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
