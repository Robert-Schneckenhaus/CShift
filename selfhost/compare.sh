#!/usr/bin/env bash
# Compares the front end of the C++ compiler with the one written in CShift for all .csh files of the repository:
# token dump and syntax tree dump (including the error messages) must be identical.
#   selfhost/compare.sh <cshiftc> <cshc> [tokens|ast]
set -u
CSHIFTC="${1:?path of cshiftc}"
CSHC="${2:?path of cshc}"
MODE="${3:-all}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

compare() {
    local name="$1" flagCpp="$2" flagCs="$3"
    local same=0 different=0
    for f in "$ROOT"/tests/cases/*.csh "$ROOT"/tests/*.csh "$ROOT"/tests/projects/*/src/*.csh "$ROOT"/tests/projects/*/extra/*.csh \
             "$ROOT"/stdlib/*.csh "$ROOT"/selfhost/src/*.csh "$ROOT"/selfhost/src/*/*.csh "$ROOT"/demo/src/*.csh; do
        [ -f "$f" ] || continue
        "$CSHIFTC" $flagCpp "$f" > "$TMP/a.txt" 2> "$TMP/a.err"
        "$CSHC" $flagCs "$f" > "$TMP/b.txt" 2> "$TMP/b.err"
        tr -d '\r' < "$TMP/a.txt" > "$TMP/a1.txt"; tr -d '\r' < "$TMP/b.txt" > "$TMP/b1.txt"
        tr -d '\r' < "$TMP/a.err" > "$TMP/a1.err"; tr -d '\r' < "$TMP/b.err" > "$TMP/b1.err"
        if cmp -s "$TMP/a1.txt" "$TMP/b1.txt" && cmp -s "$TMP/a1.err" "$TMP/b1.err"; then
            same=$((same + 1))
        else
            different=$((different + 1))
            echo "DIFFERENT ($name): ${f#$ROOT/}"
            diff "$TMP/a1.txt" "$TMP/b1.txt" | head -6
            diff "$TMP/a1.err" "$TMP/b1.err" | head -6
        fi
    done
    echo "$name: $same identical, $different different"
    [ "$different" -eq 0 ]
}

status=0
if [ "$MODE" = all ] || [ "$MODE" = tokens ]; then compare tokens --dump-tokens --tokens || status=1; fi
if [ "$MODE" = all ] || [ "$MODE" = ast ]; then compare ast --dump-ast --ast || status=1; fi
exit $status
