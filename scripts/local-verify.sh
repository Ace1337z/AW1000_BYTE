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
    local bad=0 rej
    rej=$(find "$tree"/build_dir -name '*.rej' -o -name '*.orig' 2>/dev/null | head -20)
    if [ -n "$rej" ]; then
        echo "failed patch hunks present (patch ran with -f):"
        echo "$rej"
        bad=1
    fi
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
gate_config() {
    in_tree make defconfig
    local want got missing
    want=$(grep -oE '^CONFIG_PACKAGE_[A-Za-z0-9_.+-]+=y' "$repo_root/preset" | sed 's/^CONFIG_PACKAGE_//;s/=y$//' | sort -u)
    got=$(grep -oE '^CONFIG_PACKAGE_[A-Za-z0-9_.+-]+=y' "$tree/.config" | sed 's/^CONFIG_PACKAGE_//;s/=y$//' | sort -u)
    missing=$(comm -23 <(echo "$want") <(echo "$got"))
    [ -n "$missing" ] || { echo "every requested package survived defconfig"; return 0; }
    local kconf="$tree/tmp/.config-package.in"
    # Names that never appear in the package index cannot be selected at all.
    local absent="" refused=""
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        if [ -f "$kconf" ] && grep -q "^config PACKAGE_${p}\$" "$kconf"; then
            refused="$refused $p"
        else
            absent="$absent $p"
        fi
    done <<< "$missing"
    echo "requested but NOT in .config:"
    [ -n "$absent" ] && { echo "  no such package in any feed:"; for p in $absent; do echo "    $p"; done; }
    [ -n "$refused" ] && { echo "  package exists but dependency unmet (defconfig refused it):"; for p in $refused; do echo "    $p"; done; }
    return 1
}

# LuCI JS gate: node parses every view we ship before the image is assembled.
gate_js() {
    local bad=0 f
    while IFS= read -r f; do
        node --check "$f" || bad=1
    done < <(find "$repo_root/files" "$tree/package/luci-app-byte" -name '*.js' -type f 2>/dev/null)
    return $bad
}

# Kernel-config gate: proves the NSS/DSCPREMARK options reached the *built*
# kernel config (KCONFIG of a package only lands in .config.override) and that
# the QSDK bonding front end is really gone.
gate_kconf() {
    local ldir kc
    ldir=$(ls -d "$tree"/build_dir/target-*/linux-qualcommax_ipq807x/linux-6.12.* 2>/dev/null | head -1)
    [ -n "$ldir" ] || { echo "no kernel build dir - run the target gate first"; return 1; }
    kc="$ldir/.config"
    echo "kernel: $(sed -n 's/^# Linux\/.* \([0-9.]*\).*/\1/p' "$ldir/Makefile" | head -1)"
    local bad=0
    for sym in CONFIG_NF_CONNTRACK_DSCPREMARK_EXT CONFIG_NSS_DRV_RMNET_ENABLE; do
        if grep -qx "$sym=y" "$kc"; then echo "ok   $sym=y"; else echo "FAIL $sym missing from $kc"; bad=1; fi
    done
    if grep -qx 'CONFIG_BONDING=y' "$kc"; then echo "FAIL CONFIG_BONDING=y (ECM bonding front end still enabled)"; bad=1; else echo "ok   CONFIG_BONDING is not set"; fi
    if grep -rq 'ECM_INTERFACE_BOND_ENABLE' "$tree"/feeds/nss/qca-nss-ecm/src 2>/dev/null; then
        echo "FAIL ECM_INTERFACE_BOND_ENABLE still in ECM source"; bad=1
    else
        echo "ok   no ECM_INTERFACE_BOND_ENABLE in ECM source"
    fi
    if [ -f "$ldir/.config.override" ]; then
        echo "--- .config.override ---"; cat "$ldir/.config.override"
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
