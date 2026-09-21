#!/usr/bin/env bash
# Bootstrap check: cshc (built by the C++ compiler, "stage 1") compiles its own sources into "stage 2". Both must
# generate the same LLVM IR for the sources of cshc: the compiler has reached a fixed point.
#
#   selfhost/bootstrap.sh <cshc> [-v]      -v also runs the test cases with stage 2 (selfhost/status.sh)
#
# clang has to be found ($CSHIFT_CC or PATH).
set -u
STAGE1="${1:?path of cshc}"
VERBOSE="${2:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CC_ARGS=()
if [ -n "${CSHIFT_CC:-}" ]; then CC_ARGS=(--cc "$CSHIFT_CC"); fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FILES=$(find "$ROOT/selfhost/src" -name '*.csh' | sort)
EXE=""
case "$STAGE1" in *.exe) EXE=".exe" ;; esac

# stage 2: cshc built by cshc
if ! "$STAGE1" "${CC_ARGS[@]}" $FILES -o "$TMP/stage2$EXE" > "$TMP/stage2.log" 2>&1; then
    echo "stage 2 does not build:"; head -n 10 "$TMP/stage2.log"; exit 1
fi

# the IR that both stages generate for the sources of cshc
"$STAGE1" --emit-llvm $FILES -o "$TMP/stage1.ll" > "$TMP/e1.log" 2>&1 || { cat "$TMP/e1.log"; exit 1; }
"$TMP/stage2$EXE" --emit-llvm $FILES -o "$TMP/stage2.ll" > "$TMP/e2.log" 2>&1 || { cat "$TMP/e2.log"; exit 1; }
if ! cmp -s "$TMP/stage1.ll" "$TMP/stage2.ll"; then
    echo "stage 1 and stage 2 generate different IR"
    diff "$TMP/stage1.ll" "$TMP/stage2.ll" | head -n 20
    exit 1
fi
echo "bootstrap ok: stage 1 and stage 2 generate identical IR ($(wc -c < "$TMP/stage1.ll" | tr -d ' ') bytes)"

if [ "$VERBOSE" = "-v" ]; then
    bash "$ROOT/selfhost/status.sh" "$TMP/stage2$EXE"
fi
