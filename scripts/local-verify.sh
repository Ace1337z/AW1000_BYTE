#!/bin/bash
# Local build verification, stage by stage.
#
# Why this exists: CI takes ~3 h per attempt and stops at the first failure, so
# every unknown costs a full run. This script reproduces the same build locally
# and splits it into gates, so a failure is found - and re-tested after a fix -
# in seconds or minutes instead of hours. Push only once gate 6 is green; CI
# then only confirms and publishes.
#
# Usage:
#   ./scripts/local-verify.sh              # run every gate that has not passed
#   ./scripts/local-verify.sh download     # run one gate
#   ./scripts/local-verify.sh all|download|tools|toolchain|target|packages|image|ondemand|repo
#
# Layout it expects (same as the CI job):
#   <repo>/immortalwrt/      the tree, already configured by aw1000_byte.sh
#   <repo>/scripts/local-verify.sh   this file
#
# Host prerequisites: same list as .github/workflows/build.yml. On a machine
# without sudo they can be extracted into $HOSTROOT and exported by an env file
# (see the `HOSTROOT` block below).
set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(dirname "$script_dir")"
tree="$repo_root/immortalwrt"
logdir="${LOCAL_VERIFY_LOG_DIR:-/tmp/opencode}"
mkdir -p "$logdir"

# Optional host-tool prefix (gawk/flex/bison/pkgconf/deb-extracted headers).
if [ -n "${HOSTROOT:-}" ]; then
    export PATH="$HOSTROOT/usr/bin:$HOSTROOT/bin:$PATH"
    export C_INCLUDE_PATH="$HOSTROOT/usr/include"
    export CPLUS_INCLUDE_PATH="$HOSTROOT/usr/include"
    export LIBRARY_PATH="$HOSTROOT/usr/lib/x86_64-linux-gnu:$HOSTROOT/lib/x86_64-linux-gnu"
    export LD_LIBRARY_PATH="$LIBRARY_PATH"
    export PKG_CONFIG_PATH="$HOSTROOT/usr/lib/x86_64-linux-gnu/pkgconfig:$HOSTROOT/usr/share/pkgconfig"
fi

JOBS="${JOBS:-$(nproc)}"

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'

[ -d "$tree" ] || { echo "${RED}no $tree - run aw1000_byte.sh first${RESET}"; exit 1; }

# run <gate> <command...>
# Success is recorded so a re-run resumes at the first unfinished gate.
run() {
    local gate="$1"; shift
    local log="$logdir/gate_${gate}.log"
    local stamp="$tree/.local-verify/${gate}.ok"
    mkdir -p "$tree/.local-verify"
    if [ -f "$stamp" ] && [ "${FORCE_GATE:-0}" != 1 ]; then
        echo "${YELLOW}skip ${gate} (already green: $stamp)${RESET}"
        return 0
    fi
    echo "${YELLOW}=== gate: ${gate} === ${RESET}(log: $log)"
    if "$@" >"$log" 2>&1; then
        touch "$stamp"
        echo "${GREEN}=== gate: ${gate} ok${RESET}"
        return 0
    fi
    echo "${RED}=== gate: ${gate} FAILED${RESET}"
    # Show the useful part of the log: fatal make lines, then the tail.
    grep -aE "make(\[[0-9]+\])?: \*\*\*|ERROR:|Error [0-9]+$|undefined!|No more mirrors|Patch failed|Hunk #|missing dependencies" \
        "$log" | grep -av "mirror2.openwrt.org\|Failed to connect" | tail -15
    echo "--- tail ---"
    grep -av "% Total\|Dload\|--:--:--\|mirror2.openwrt.org" "$log" | tail -25
    return 1
}

in_tree() { ( cd "$tree" && "$@" ); }

gate_download()  { in_tree make download -j"$JOBS"; }
gate_tools()     { in_tree make tools/compile -j"$JOBS"; }
gate_toolchain() { in_tree make toolchain/compile -j"$JOBS"; }
gate_target()    { in_tree make target/compile -j"$JOBS"; }
# packages also proves the *post-patch* state: $(PATCH) runs with -f, so a hunk
# that fails leaves a .rej and the build carries on with the old source.
gate_packages()  {
    in_tree make package/compile -j"$JOBS" || return 1
    local bad=0 rej touched=0
    # $(PATCH) runs with -f: a failed hunk leaves .rej and the build continues
    # with the old source. .rej is always a failure. .orig alone is not:
    # patch renames the pre-image to .orig when it succeeds, so the test is
    # whether the patched file differs from its .orig backup. config.guess and
    # config.sub are exempt: scripts/refresh-config-sub-guess.sh refreshes them
    # wholesale, and a no-op refresh leaves an identical .orig pair.
    rej=$(find "$tree"/build_dir -name '*.rej' 2>/dev/null | head -20)
    if [ -n "$rej" ]; then
        echo "failed patch hunks present (patch ran with -f):"
        echo "$rej"
        bad=1
    fi
    local f
    while IFS= read -r f; do
        case "${f##*/}" in config.guess.orig | config.sub.orig) continue ;; esac
        if diff -q "${f%.orig}" "$f" >/dev/null 2>&1; then
            echo "FAIL ${f%.orig} is identical to its .orig (patch produced no change)"
            bad=1
        fi
    done < <(find "$tree"/build_dir -name '*.orig' 2>/dev/null | head -200)
    local src
    src=$(ls -d "$tree"/build_dir/target-*/linux-qualcommax_ipq807x/qmi_wwan_q-*/qmi_wwan_q.c 2>/dev/null | head -1)
    if [ -n "$src" ]; then
        if grep -q '#define CONFIG_QCA_NSS_DRV' "$src"; then
            echo "FAIL $src still defines CONFIG_QCA_NSS_DRV (patch not applied)"
            bad=1
        else
            echo "ok   qmi_wwan_q source has the NSS hook removed"
        fi
    fi
    # NSS_DRV_RMNET_ENABLE is a module -D flag, not a kernel symbol: the only
    # place it is observable is the built qca-nss-drv.ko. ECM's RAWIP front end
    # calls this export, so its absence is a runtime break, not a warning.
    local drv syms
    drv=$(ls "$tree"/build_dir/target-*/linux-qualcommax_ipq807x/qca-nss-drv-*/qca-nss-drv.ko 2>/dev/null | head -1)
    if [ -n "$drv" ]; then
        # Do NOT pipe nm into grep -q: with `set -o pipefail`, grep -q exiting
        # early SIGPIPEs nm on this 45 MB unstripped module and the whole
        # pipeline reports failure even though the symbol is present.
        syms=$(nm -g "$drv" 2>/dev/null | grep ' nss_rmnet_rx_get_ifnum$' | head -1)
        if [ -n "$syms" ]; then
            echo "ok   qca-nss-drv exports nss_rmnet_rx_get_ifnum (NSS_DRV_RMNET_ENABLE compiled in)"
        else
            echo "FAIL $drv does not export nss_rmnet_rx_get_ifnum (ECM RAWIP would break)"
            bad=1
        fi
    else
        echo "note qca-nss-drv.ko not found - cannot check the RMNET export"
    fi
    return $bad
}
# Full world: reuses everything above, then assembles squashfs/sysupgrade.
gate_image()     { in_tree make -j"$JOBS"; }
gate_ondemand()  { bash "$repo_root/.github/build-ondemand-packages.sh" "$tree"; }
gate_repo() {
    local manifest
    manifest=$(ls "$tree"/bin/targets/qualcommax/ipq807x/*.manifest 2>/dev/null | head -1)
    [ -n "$manifest" ] || { echo "no .manifest - image gate has not run"; return 1; }
    bash "$repo_root/.github/build-package-repo.sh" "$tree" "$repo_root/repo" "$manifest"
}

# Config gate: make defconfig silently drops every symbol whose package or
# dependency is missing, so a featured=y package can vanish without any error.
# This compares what `preset` asked for against what .config actually kept, and
# classifies each loss: package not in any feed, or dependency not satisfied.
# It also fails on the opposite drift: a symbol preset marks "not set" that
# defconfig re-enabled anyway (e.g. a stale =y in a reused tree).
gate_config() {
    in_tree make defconfig
    local want got missing
    want=$(grep -oE '^CONFIG_PACKAGE_[A-Za-z0-9_.+-]+=y' "$repo_root/preset" | sed 's/^CONFIG_PACKAGE_//;s/=y$//' | sort -u)
    got=$(grep -oE '^CONFIG_PACKAGE_[A-Za-z0-9_.+-]+=y' "$tree/.config" | sed 's/^CONFIG_PACKAGE_//;s/=y$//' | sort -u)
    missing=$(comm -23 <(echo "$want") <(echo "$got"))
    local bad=0
    if [ -n "$missing" ]; then
        local kconf="$tree/tmp/.config-package.in"
        # Names that never appear in the package index cannot be selected at all.
        local absent="" refused=""
        while IFS= read -r p; do
            [ -n "$p" ] || continue
            if [ -f "$kconf" ] && grep -qE "^[[:space:]]*(menu)?config PACKAGE_${p}\$" "$kconf"; then
                refused="$refused $p"
            else
                absent="$absent $p"
            fi
        done <<< "$missing"
        echo "requested but NOT in .config:"
        [ -n "$absent" ] && { echo "  no such package in any feed:"; for p in $absent; do echo "    $p"; done; }
        [ -n "$refused" ] && { echo "  package exists but dependency unmet (defconfig refused it):"; for p in $refused; do echo "    $p"; done; }
        bad=1
    fi
    # Reverse drift: preset says "not set" but .config has =y anyway. Happens
    # when a reused tree keeps an old selection that a dependency change
    # should have removed (found: geoview/v2ray-geoip after passwall2's geo
    # deps were stripped - defconfig preserves an explicit =y with no
    # dependent, so the ~7.4 MB would have shipped unnoticed).
    local extra
    extra=$(comm -13 <(echo "$want") <(echo "$got") | grep -vE '^(busybox|libc|libgcc|libpthread|librt)$' || true)
    if [ -n "$extra" ]; then
        echo "=y in .config but NOT requested by preset:"
        for p in $extra; do
            if grep -qE "^# CONFIG_PACKAGE_${p} is not set$" "$repo_root/preset"; then
                echo "  $p (preset explicitly says not set!)"
            else
                echo "  $p (pulled in by a dependency - verify this is wanted)"
            fi
        done
        # Only an explicit preset "not set" is fatal; dependency-pulled =y is
        # normal (kmods pulled by luci apps, etc.) and just gets reported.
        for p in $extra; do
            grep -qE "^# CONFIG_PACKAGE_${p} is not set$" "$repo_root/preset" && { bad=1; break; }
        done
    fi
    [ "$bad" = 0 ] && echo "every requested package survived defconfig; no preset-not-set symbol is enabled"
    return $bad
}

# LuCI JS gate: node parses every view we ship before the image is assembled.
gate_js() {
    local bad=0 f
    while IFS= read -r f; do
        node --check "$f" || bad=1
    done < <(find "$repo_root/files" "$tree/package/luci-app-byte" -name '*.js' -type f 2>/dev/null)
    return $bad
}

# Kernel-config gate: proves the DSCPREMARK kernel patch reached the *built*
# kernel config and that the QSDK bonding front end is really gone.
#
# NSS_DRV_* is deliberately NOT checked here: qca-nss-drv's KernelPackage has
# no KCONFIG at all. Those options are PKG_CONFIG_DEPENDS + a feed Config.in
# that the package Makefile turns into `DRV_MAKE_OPTS += NSS_DRV_X_ENABLE=n`,
# i.e. -D flags for the module. They never appear in any kernel .config, so the
# real proof is an exported symbol in the built .ko (checked in gate_packages).
gate_kconf() {
    local ldir kc
    ldir=$(ls -d "$tree"/build_dir/target-*/linux-qualcommax_ipq807x/linux-6.12.* 2>/dev/null | head -1)
    [ -n "$ldir" ] || { echo "no kernel build dir - run the target gate first"; return 1; }
    kc="$ldir/.config"
    echo "kernel: $(awk -F' = ' '/^VERSION = |^PATCHLEVEL = |^SUBLEVEL = /{printf "%s.", $2}' "$ldir/Makefile" | sed 's/\.$//')"
    local bad=0
    if grep -qx 'CONFIG_NF_CONNTRACK_DSCPREMARK_EXT=y' "$kc"; then
        echo "ok   CONFIG_NF_CONNTRACK_DSCPREMARK_EXT=y"
    else
        echo "FAIL CONFIG_NF_CONNTRACK_DSCPREMARK_EXT missing from $kc"; bad=1
    fi
    if grep -qx 'CONFIG_BONDING=y' "$kc"; then echo "FAIL CONFIG_BONDING=y (ECM bonding front end still enabled)"; bad=1; else echo "ok   CONFIG_BONDING is not set"; fi
    if grep -rq 'ECM_INTERFACE_BOND_ENABLE' "$tree"/feeds/nss/qca-nss-ecm/src 2>/dev/null; then
        echo "FAIL ECM_INTERFACE_BOND_ENABLE still in ECM source"; bad=1
    else
        echo "ok   no ECM_INTERFACE_BOND_ENABLE in ECM source"
    fi
    # The KCONFIG line of kmod-nf-conntrack lands in .config.override (a kernel
    # symbol never appears in the top-level .config); its presence there proves
    # the package's KCONFIG was honoured and the patch's `default y` was seen.
    if grep -qx 'CONFIG_NF_CONNTRACK_DSCPREMARK_EXT=y' "$ldir/.config.override"; then
        echo "ok   .config.override carries it (kmod-nf-conntrack KCONFIG honoured)"
    else
        echo "FAIL .config.override lacks NF_CONNTRACK_DSCPREMARK_EXT"; bad=1
    fi
    return $bad
}

gates="${1:-all}"
case "$gates" in
    all)
        for g in download tools toolchain config target kconf packages js image ondemand repo; do
            run "$g" "gate_$g" || exit 1
        done
        ;;
    download|tools|toolchain|config|target|kconf|packages|js|image|ondemand|repo)
        run "$gates" "gate_$gates" || exit 1
        ;;
    *)
        echo "usage: $0 [all|download|tools|toolchain|config|target|kconf|packages|js|image|ondemand|repo]"
        exit 2
        ;;
esac
echo "${GREEN}all requested gates green${RESET}"
