#!/usr/bin/env bash
# How much of the language does cshc handle? Runs tests/cases/*.csh with cshc and sorts the results:
#   pass         the expectations of the file (// expect-error, expect-exit, expect-stdout, expect-stderr) hold
#   unsupported  cshc stops with "cshc does not support ..." (a feature that is not ported yet)
#   FAIL         everything else (a real difference to the C++ compiler)
#
#   selfhost/status.sh <cshc> [-v]      -v lists the files of every group
#   selfhost/status.sh <cshc> --check   fails if a case listed in selfhost/passing.txt does not pass any more
set -u
CSHC="${1:?path of cshc}"
VERBOSE="${2:-}"
CHECK=0
[ "$VERBOSE" = "--check" ] && CHECK=1
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CC_ARGS=()
if [ -n "${CSHIFT_CC:-}" ]; then CC_ARGS=(--cc "$CSHIFT_CC"); fi # the clang for cshc (like in tests/run_tests.sh)
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

directives() { sed -n "s|^// $2:[[:space:]]*\(.*[^[:space:]]\)[[:space:]]*\$|\1|p" "$1" | tr -d '\r'; }

pass=(); unsupported=(); fail=()
for file in "$ROOT"/tests/cases/*.csh; do
    name="$(basename "$file")"
    want_error="$(directives "$file" expect-error | head -n 1)"
    exe="$TMP/case.exe"
    rm -f "$exe"
    if "$CSHC" -O0 "${CC_ARGS[@]}" "$file" -o "$exe" > "$TMP/c.out" 2> "$TMP/c.err"; then compiled=1; else compiled=0; fi
    if [ -n "$want_error" ]; then
        if [ $compiled -eq 0 ] && grep -qF -- "$want_error" "$TMP/c.err"; then pass+=("$name"); continue; fi
        if grep -q "cshc does not support" "$TMP/c.err"; then unsupported+=("$name"); else fail+=("$name"); fi
        continue
    fi
    if [ $compiled -eq 0 ]; then
        if grep -q "cshc does not support" "$TMP/c.err"; then unsupported+=("$name"); else fail+=("$name"); fi
        continue
    fi
    ( cd "$TMP" && "$exe" > "$TMP/r.out" 2> "$TMP/r.err" ); code=$?
    want_exit="$(directives "$file" expect-exit | head -n 1)"; want_exit="${want_exit:-0}"
    ok=1
    [ "$code" -ne "$want_exit" ] && ok=0
    while IFS= read -r text; do [ -z "$text" ] && continue; grep -qF -- "$text" "$TMP/r.out" || ok=0; done < <(directives "$file" expect-stdout)
    while IFS= read -r text; do [ -z "$text" ] && continue; grep -qF -- "$text" "$TMP/r.err" || ok=0; done < <(directives "$file" expect-stderr)
    if [ $ok -eq 1 ]; then pass+=("$name"); else fail+=("$name"); fi
done
total=$(( ${#pass[@]} + ${#unsupported[@]} + ${#fail[@]} ))
echo "tests/cases with cshc: ${#pass[@]} pass, ${#unsupported[@]} unsupported, ${#fail[@]} FAIL (of $total)"
if [ "$VERBOSE" = "-v" ]; then
    echo "--- pass:"; printf '  %s\n' "${pass[@]:-}"
    echo "--- unsupported:"; printf '  %s\n' "${unsupported[@]:-}"
    echo "--- FAIL:"; printf '  %s\n' "${fail[@]:-}"
fi
if [ "$CHECK" -eq 1 ]; then
    # Every case of passing.txt must still pass (the list only grows as more of the language is ported).
    lost=0
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        found=0
        for p in "${pass[@]:-}"; do [ "$p" = "$name" ] && found=1; done
        if [ $found -eq 0 ]; then echo "no longer passing: $name"; lost=$((lost + 1)); fi
    done < "$ROOT/selfhost/passing.txt"
    [ $lost -eq 0 ]
else
    [ ${#fail[@]} -eq 0 ]
fi
