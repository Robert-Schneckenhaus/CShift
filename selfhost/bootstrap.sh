#!/usr/bin/env bash
# Bootstrap check: cshc ("stage 1", built by another compiler) compiles its own sources into "stage 2". Both must
# generate the same LLVM IR for the sources of cshc: the compiler has reached a fixed point.
#
#   selfhost/bootstrap.sh <cshc> [--stage2 <file>] [-v]
#
#   --stage2   stage 2 is already built (by <cshc>, from these sources: selfhost/build-release.sh); it is not built
#              again, only compared
#   -v         also runs the test cases with stage 2 (selfhost/status.sh)
#
# clang has to be found ($CSHIFT_CC or PATH).
set -u
STAGE1="${1:?path of cshc}"
shift
STAGE2=""
VERBOSE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --stage2) STAGE2="${2:?path of stage 2}"; shift 2 ;;
        -v) VERBOSE="-v"; shift ;;
        *) echo "bootstrap.sh: unknown argument '$1'"; exit 2 ;;
    esac
done
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CC_ARGS=()
if [ -n "${CSHIFT_CC:-}" ]; then CC_ARGS=(--cc "$CSHIFT_CC"); fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FILES=$(find "$ROOT/selfhost/src" -name '*.csh' | sort)
EXE=""
case "$STAGE1" in *.exe) EXE=".exe" ;; esac

# stage 2: cshc built by cshc
if [ -z "$STAGE2" ]; then
    STAGE2="$TMP/stage2$EXE"
    if ! "$STAGE1" "${CC_ARGS[@]}" $FILES -o "$STAGE2" > "$TMP/stage2.log" 2>&1; then
        echo "stage 2 does not build:"; head -n 10 "$TMP/stage2.log"; exit 1
    fi
fi

# the IR that both stages generate for the sources of cshc
"$STAGE1" --emit-llvm $FILES -o "$TMP/stage1.ll" > "$TMP/e1.log" 2>&1 || { cat "$TMP/e1.log"; exit 1; }
"$STAGE2" --emit-llvm $FILES -o "$TMP/stage2.ll" > "$TMP/e2.log" 2>&1 || { cat "$TMP/e2.log"; exit 1; }
# 'cmp'/'diff' are not guaranteed to be installed (e.g. a minimal MSYS2 CLANG64 environment), so this compares in
# plain bash; the two files are a few MB of text, which bash handles without trouble.
if [ "$(cat "$TMP/stage1.ll")" != "$(cat "$TMP/stage2.ll")" ]; then
    echo "stage 1 and stage 2 generate different IR"
    if command -v diff > /dev/null 2>&1; then
        diff "$TMP/stage1.ll" "$TMP/stage2.ll" | head -n 20
    fi
    exit 1
fi
echo "bootstrap ok: stage 1 and stage 2 generate identical IR ($(wc -c < "$TMP/stage1.ll" | tr -d ' ') bytes)"

if [ "$VERBOSE" = "-v" ]; then
    bash "$ROOT/selfhost/status.sh" "$STAGE2"
fi
