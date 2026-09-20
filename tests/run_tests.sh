#!/usr/bin/env bash
# CShift test runner (bash: Linux, macOS, Git Bash, MSYS2).
#
#   tests/run_tests.sh [path/to/cshiftc] [-O0|-O1|-O2|-O3]
#
# The compiler is taken from the first argument, $CSHIFTC or build/cshiftc[.exe].
# clang (or the program given with $CSHIFT_CC) must be available for linking.
#
# What is tested:
#   1. tests/test.csh + tests/mathlib.csh  -> stdout must match tests/test.expected, all
#      checks pass and no heap block is leaked (--arc-stats).
#   2. tests/cases/*.csh                   -> small programs with expectations in comments:
#        // expect-error:  <text>   compilation must fail and print <text>
#        // expect-exit:   <n>      exit code of the program (default 0)
#        // expect-stdout: <text>   stdout contains <text>   (may be repeated)
#        // expect-stderr: <text>   stderr contains <text>   (may be repeated)
#        // arc-ignore              skip the leak check

set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
COMPILER=""
OPT="-O2"
for arg in "$@"; do
    case "$arg" in
        -O[0-3]) OPT="$arg" ;;
        *) COMPILER="$arg" ;;
    esac
done
if [ -z "$COMPILER" ]; then COMPILER="${CSHIFTC:-}"; fi
if [ -z "$COMPILER" ]; then
    for c in "$DIR/../build/cshiftc" "$DIR/../build/cshiftc.exe"; do
        if [ -x "$c" ]; then COMPILER="$c"; break; fi
    done
fi
if [ -z "$COMPILER" ] || [ ! -x "$COMPILER" ]; then
    echo "cshiftc not found. Pass its path as first argument or set CSHIFTC."
    exit 2
fi
CC_ARGS=()
if [ -n "${CSHIFT_CC:-}" ]; then CC_ARGS=(--cc "$CSHIFT_CC"); fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASSED=0
FAILED=0

report_fail() {
    echo "FAIL  $1"
    [ -n "${2:-}" ] && echo "      $2"
    FAILED=$((FAILED + 1))
}
report_ok() {
    PASSED=$((PASSED + 1))
    [ -n "${VERBOSE:-}" ] && echo "ok    $1"
}

# Reads all values of a directive ("// name: value") from a file.
directives() {
    sed -n "s|^// $2:[[:space:]]*\(.*[^[:space:]]\)[[:space:]]*\$|\1|p" "$1" | tr -d '\r'
}

# --- 1. main test program ----------------------------------------------------
echo "== test.csh ($OPT)"
if ! "$COMPILER" $OPT "${CC_ARGS[@]}" --arc-stats "$DIR/test.csh" "$DIR/mathlib.csh" -o "$TMP/test.exe" 2> "$TMP/compile.err"; then
    report_fail "test.csh" "compilation failed:"
    cat "$TMP/compile.err"
else
    "$TMP/test.exe" > "$TMP/test.out" 2> "$TMP/test.err"
    code=$?
    tr -d '\r' < "$TMP/test.out" > "$TMP/test.out.n"
    tr -d '\r' < "$DIR/test.expected" > "$TMP/test.expected.n"
    if [ "$code" -ne 0 ]; then
        report_fail "test.csh" "exit code $code (failed checks):"
        grep FAIL "$TMP/test.out.n"
    elif [ "$(cat "$TMP/test.expected.n")" != "$(cat "$TMP/test.out.n")" ]; then
        report_fail "test.csh" "output differs from test.expected"
        echo "----- expected"
        cat "$TMP/test.expected.n"
        echo "----- actual"
        cat "$TMP/test.out.n"
        echo "-----"
    elif ! grep -q "live=0" "$TMP/test.err"; then
        report_fail "test.csh" "heap blocks leaked: $(grep '\[arc\]' "$TMP/test.err")"
    else
        report_ok "test.csh"
        echo "ok    test.csh ($(grep 'passed:' "$TMP/test.out.n"), $(grep '\[arc\]' "$TMP/test.err" | tr -d '\r'))"
    fi
fi

# --- 2. small cases -----------------------------------------------------------
echo "== cases/"
for file in "$DIR"/cases/*.csh; do
    name="$(basename "$file")"
    expected_error="$(directives "$file" expect-error | head -n 1)"

    if [ -n "$expected_error" ]; then
        if "$COMPILER" $OPT "${CC_ARGS[@]}" "$file" -o "$TMP/case.exe" 2> "$TMP/case.err" > /dev/null; then
            report_fail "$name" "compilation succeeded but an error was expected"
        elif ! grep -qF -- "$expected_error" "$TMP/case.err"; then
            report_fail "$name" "expected error '$expected_error', got: $(head -n 3 "$TMP/case.err" | tr '\n' ' ')"
        else
            report_ok "$name"
        fi
        continue
    fi

    if ! "$COMPILER" $OPT "${CC_ARGS[@]}" --arc-stats "$file" -o "$TMP/case.exe" 2> "$TMP/case.err"; then
        report_fail "$name" "compilation failed: $(head -n 3 "$TMP/case.err" | tr '\n' ' ')"
        continue
    fi
    # Run in the temp directory: some tests create files.
    ( cd "$TMP" && "$TMP/case.exe" > "$TMP/case.out" 2> "$TMP/case.run.err" )
    code=$?
    want_exit="$(directives "$file" expect-exit | head -n 1)"
    want_exit="${want_exit:-0}"
    problem=""
    [ "$code" -ne "$want_exit" ] && problem="exit code $code, expected $want_exit"
    while IFS= read -r text; do
        [ -z "$text" ] && continue
        grep -qF -- "$text" "$TMP/case.out" || problem="stdout does not contain '$text'"
    done < <(directives "$file" expect-stdout)
    while IFS= read -r text; do
        [ -z "$text" ] && continue
        grep -qF -- "$text" "$TMP/case.run.err" || problem="stderr does not contain '$text'"
    done < <(directives "$file" expect-stderr)
    if ! grep -q "^// arc-ignore" "$file" && grep -q "\[arc\]" "$TMP/case.run.err"; then
        grep -q "live=0" "$TMP/case.run.err" || problem="heap blocks leaked: $(grep '\[arc\]' "$TMP/case.run.err" | tr -d '\r')"
    fi
    if [ -n "$problem" ]; then
        report_fail "$name" "$problem"
    else
        report_ok "$name"
    fi
done

echo
echo "$PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
