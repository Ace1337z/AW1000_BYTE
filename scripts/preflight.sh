#!/bin/bash
# Run the real apply_preset() from aw1000_byte.sh against the real build tree.
# This is what CI does before `make world`; running it locally is the only way
# to catch set -e / sed / awk / patch bugs in it without a 3 h CI round trip.
#
#   bash scripts/preflight.sh [--no-build]
#
# Steps: extract apply_preset() (self-contained, no helper calls) -> run it in
# the build tree -> make defconfig -> optional full make -j<N>.
# Exits non-zero on the first failure and leaves the log in /tmp/opencode.
set -euo pipefail

REPO=${REPO:-$(cd "$(dirname "$0")/.." && pwd)}
TREE=${TREE:-/home/ace/lb/builder/immortalwrt}
LOG=${LOG:-/tmp/opencode/preflight.log}
BUILD=1
[ "${1:-}" = "--no-build" ] && BUILD=0

[ -f "$REPO/aw1000_byte.sh" ] || { echo "no aw1000_byte.sh in $REPO"; exit 1; }
[ -d "$TREE" ] || { echo "no build tree at $TREE (set TREE=)"; exit 1; }
: >"$LOG"

say() { printf '%s\n' "$*" | tee -a "$LOG"; }
run() { say "+ $*"; "$@" >>"$LOG" 2>&1 || { say "FAILED: $*"; exit 1; }; }

start=$(grep -n '^apply_preset() {' "$REPO/aw1000_byte.sh" | cut -d: -f1)
[ -n "$start" ] || { echo "apply_preset() not found"; exit 1; }
# The function body contains a heredoc whose terminator line is a bare `}`, so
# "first ^}$ after start" ends the extraction mid-heredoc and produces a syntax
# error. Take the last `^}$` before the next top-level function definition.
end=$(awk -v s="$start" '
    NR > s && /^[A-Za-z_][A-Za-z0-9_]*\(\) \{/ { print last; exit }
    NR > s && /^}$/ { last = NR }
' "$REPO/aw1000_byte.sh")
[ -n "$end" ] || { echo "could not find the end of apply_preset()"; exit 1; }

say "== apply_preset() from aw1000_byte.sh:${start}-${end} on $TREE"
say "== log: $LOG"
# apply_preset() calls apply_version(); pull every top-level function defined
# before ci_check_packages() so the extracted script is self-contained.
helpers=$(mktemp)
awk '
    /^[A-Za-z_][A-Za-z0-9_]*\(\) \{/ { infn = 1 }
    /^ci_check_packages\(\) \{/ { exit }
    infn { print }
' "$REPO/aw1000_byte.sh" >"$helpers"
bash -n "$helpers" || { echo "extracted functions do not parse"; exit 1; }
cd "$TREE"
# Same globals the script sets before it calls apply_preset().
set +u
(
    BOLD_RED=$'\033[1;31m'
    BOLD_GREEN=$'\033[1;32m'
    BOLD_YELLOW=$'\033[1;33m'
    RESET=$'\033[0m'
    script_dir="$REPO"
    preset_folder="$REPO"
    preset_repo="https://github.com/Ace1337z/AW1000_BYTE.git"
    set -e
    eval "$(cat "$helpers")"
    apply_preset
) || { say "apply_preset FAILED (see above / $LOG)"; rm -f "$helpers"; exit 1; }
rm -f "$helpers"
say "== apply_preset OK"

run make defconfig
say "== defconfig OK"
grep -c '=y$' .config | sed 's/^/== CONFIG_* =y lines: /' | tee -a "$LOG"

# ci_check_packages() is the gate CI runs right after defconfig. Run it here
# too: it is the only thing that proves the tree apply_preset() just produced
# actually carries every package/flag the preset asked for.
gstart=$(grep -n '^ci_check_packages() {' "$REPO/aw1000_byte.sh" | cut -d: -f1)
gend=$(awk -v s="$gstart" '
    NR > s && /^[A-Za-z_][A-Za-z0-9_]*\(\) \{/ { print last; exit }
    NR > s && /^}$/ { last = NR }
' "$REPO/aw1000_byte.sh")
[ -n "$gend" ] || { say "could not find the end of ci_check_packages()"; exit 1; }
gate=$(mktemp)
sed -n "${gstart},${gend}p" "$REPO/aw1000_byte.sh" >"$gate"
bash -n "$gate" || { say "extracted ci_check_packages() does not parse"; exit 1; }
say "== ci_check_packages() from aw1000_byte.sh:${gstart}-${gend}"
set +u
gateout=$(mktemp)
set +e
(
    BOLD_RED=$'\033[1;31m'; BOLD_GREEN=$'\033[1;32m'; RESET=$'\033[0m'
    script_dir="$REPO"
    eval "$(cat "$gate")"
    ci_check_packages
) >"$gateout" 2>&1
grc=$?
set -e
grep -E 'MISSING|FORBIDDEN|ALL REQUIRED' "$gateout" | tee -a "$LOG"
cat "$gateout" >>"$LOG"
rm -f "$gate" "$gateout"
[ "$grc" -eq 0 ] || { say "ci_check_packages FAILED (rc=$grc)"; exit 1; }
say "== ci_check_packages OK"

if [ "$BUILD" = 1 ]; then
    run make "-j${JOBS:-$(nproc)}"
    say "== make OK"
    ls -l bin/targets/qualcommax/ipq807x/*sysupgrade*.bin | tee -a "$LOG"
fi
say "== preflight done"
