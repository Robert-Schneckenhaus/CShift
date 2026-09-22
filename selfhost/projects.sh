#!/usr/bin/env bash
# Builds the projects of tests/projects with cshc (cshc build / run / new), like section 3 of tests/run_tests.sh.
#
#   selfhost/projects.sh <cshc> [-v]
#
# A project that needs something cshc does not support yet ("cshc does not support ...", e.g. C header imports)
# counts as "unsupported". Anything else that goes wrong is a FAIL. Exit status 1 if there is a FAIL.
set -u
CSHC="${1:?path of cshc}"
CSHC="$(cd "$(dirname "$CSHC")" && pwd)/$(basename "$CSHC")"
VERBOSE="${2:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CC_ARGS=()
if [ -n "${CSHIFT_CC:-}" ]; then CC_ARGS=(--cc "$CSHIFT_CC"); fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ARGS=("${CC_ARGS[@]}")

pass=(); unsupported=(); fail=()
for dir in "$ROOT"/tests/projects/*/; do
    name="$(basename "$dir")"
    work="$TMP/proj_$name"
    cp -r "$dir" "$work"
    for c_file in "$work"/native/*.c; do
        [ -f "$c_file" ] || continue
        "${CSHIFT_CC:-clang}" -c "$c_file" -o "${c_file%.c}.o" || { fail+=("$name"); continue 2; }
    done
    problem=""
    if [ -f "$work/expected-error.txt" ]; then
        want="$(head -n 1 "$work/expected-error.txt" | tr -d '\r')"
        if "$CSHC" build "$work" "${ARGS[@]}" > /dev/null 2> "$TMP/err"; then
            problem="the build succeeded but an error was expected"
        elif ! grep -qF -- "$want" "$TMP/err"; then
            problem="expected error '$want', got: $(head -n 3 "$TMP/err" | tr '\n' ' ')"
        fi
    elif [ -f "$work/expected.txt" ]; then
        "$CSHC" run "$work" "${ARGS[@]}" > "$TMP/out" 2> "$TMP/err" || problem="run failed: $(head -n 3 "$TMP/err" | tr '\n' ' ')"
        if [ -z "$problem" ] && [ "$(tr -d '\r' < "$TMP/out")" != "$(tr -d '\r' < "$work/expected.txt")" ]; then
            problem="output differs: $(tr -d '\r' < "$TMP/out" | tr '\n' '|')"
        fi
        if [ -z "$problem" ]; then
            # the project file is also found from a subdirectory (searched upwards)
            ( cd "$work/src" && "$CSHC" run "${ARGS[@]}" > "$TMP/out2" 2> "$TMP/err" ) || problem="run from a subdirectory failed: $(head -n 3 "$TMP/err" | tr '\n' ' ')"
            [ -z "$problem" ] && [ "$(tr -d '\r' < "$TMP/out2")" != "$(tr -d '\r' < "$work/expected.txt")" ] && problem="output differs when run from a subdirectory"
        fi
    else
        if ! "$CSHC" build "$work" "${ARGS[@]}" > "$TMP/out" 2> "$TMP/err" || ! grep -q "Built" "$TMP/out"; then
            problem="build failed: $(head -n 3 "$TMP/err" | tr '\n' ' ')"
        fi
    fi
    if [ -z "$problem" ]; then
        pass+=("$name")
    elif grep -q "cshc does not support" "$TMP/err" 2> /dev/null; then
        unsupported+=("$name")
    else
        fail+=("$name: $problem")
    fi
done

# cshc new creates a working project
if "$CSHC" new "$TMP/fresh" > /dev/null 2> "$TMP/err" &&
   "$CSHC" run "$TMP/fresh" "${ARGS[@]}" 2> "$TMP/err" | tr -d '\r' | grep -qx "Hello, World!"; then
    pass+=("new")
else
    fail+=("new: the generated project does not print Hello, World! ($(head -n 3 "$TMP/err" | tr '\n' ' '))")
fi

echo "tests/projects with cshc: ${#pass[@]} pass, ${#unsupported[@]} unsupported, ${#fail[@]} FAIL"
if [ "$VERBOSE" = "-v" ]; then
    echo "--- pass:"; printf '  %s\n' "${pass[@]:-}"
    echo "--- unsupported:"; printf '  %s\n' "${unsupported[@]:-}"
fi
[ ${#fail[@]} -gt 0 ] && { echo "--- FAIL:"; printf '  %s\n' "${fail[@]}"; }
[ ${#fail[@]} -eq 0 ]
