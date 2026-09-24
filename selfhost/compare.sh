#!/usr/bin/env bash
# Compares the front end of the C++ compiler with the one written in CShift for all .csh files of the repository:
# token dump and syntax tree dump (including the error messages) must be identical. Files listed in
# selfhost/frontend-skip.txt (syntax cshc does not support yet, e.g. a cshiftc-only language feature) are left out.
#   selfhost/compare.sh <cshiftc> <cshc> [tokens|ast]
set -u
CSHIFTC="${1:?path of cshiftc}"
CSHC="${2:?path of cshc}"
MODE="${3:-all}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 'diff' and 'cmp' are not guaranteed to be installed (e.g. a minimal MSYS2 CLANG64 environment), so comparisons use
# plain bash; the diagnostic output falls back to printing both files if 'diff' is missing.
have_diff=0
command -v diff > /dev/null 2>&1 && have_diff=1
same_content() { [ "$(cat "$1")" = "$(cat "$2")" ]; }
show_diff() {
    if [ "$have_diff" -eq 1 ]; then
        diff "$1" "$2" | head -n 6
    else
        echo "--- $1"; head -n 6 "$1"
        echo "--- $2"; head -n 6 "$2"
    fi
}

# Files that use syntax the CShift front end does not know yet (see selfhost/frontend-skip.txt) - an expected
# difference, not a regression, so they are left out of the comparison entirely rather than reported as FAILing.
SKIP_LIST="$ROOT/selfhost/frontend-skip.txt"
skip_paths=""
if [ -f "$SKIP_LIST" ]; then
    while IFS= read -r line; do
        line="${line%%#*}"                  # strip comments
        line="$(echo "$line" | xargs)"       # trim whitespace; also drops now-empty lines
        [ -n "$line" ] && skip_paths="$skip_paths|$line|"
    done < "$SKIP_LIST"
fi
is_skipped() { [ -n "$skip_paths" ] && [ "${skip_paths#*|$1|}" != "$skip_paths" ]; }

compare() {
    local name="$1" flagCpp="$2" flagCs="$3"
    local same=0 different=0 skipped=0
    for f in "$ROOT"/tests/cases/*.csh "$ROOT"/tests/*.csh "$ROOT"/tests/projects/*/src/*.csh "$ROOT"/tests/projects/*/extra/*.csh \
             "$ROOT"/stdlib/*.csh "$ROOT"/selfhost/src/*.csh "$ROOT"/selfhost/src/*/*.csh "$ROOT"/demo/src/*.csh; do
        [ -f "$f" ] || continue
        if is_skipped "${f#$ROOT/}"; then
            skipped=$((skipped + 1))
            continue
        fi
        "$CSHIFTC" $flagCpp "$f" > "$TMP/a.txt" 2> "$TMP/a.err"
        "$CSHC" $flagCs "$f" > "$TMP/b.txt" 2> "$TMP/b.err"
        tr -d '\r' < "$TMP/a.txt" > "$TMP/a1.txt"; tr -d '\r' < "$TMP/b.txt" > "$TMP/b1.txt"
        tr -d '\r' < "$TMP/a.err" > "$TMP/a1.err"; tr -d '\r' < "$TMP/b.err" > "$TMP/b1.err"
        if same_content "$TMP/a1.txt" "$TMP/b1.txt" && same_content "$TMP/a1.err" "$TMP/b1.err"; then
            same=$((same + 1))
        else
            different=$((different + 1))
            echo "DIFFERENT ($name): ${f#$ROOT/}"
            show_diff "$TMP/a1.txt" "$TMP/b1.txt"
            show_diff "$TMP/a1.err" "$TMP/b1.err"
        fi
    done
    echo "$name: $same identical, $different different, $skipped skipped (frontend-skip.txt)"
    [ "$different" -eq 0 ]
}

status=0
if [ "$MODE" = all ] || [ "$MODE" = tokens ]; then compare tokens --dump-tokens --tokens || status=1; fi
if [ "$MODE" = all ] || [ "$MODE" = ast ]; then compare ast --dump-ast --ast || status=1; fi
exit $status
