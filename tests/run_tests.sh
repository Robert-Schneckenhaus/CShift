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
#   3. tests/projects/*/                  -> projects built with "cshiftc build|run" (see the comment further down),
#      plus "cshiftc new". A project may contain native/*.c files (compiled with clang before the build) for FFI tests.

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
COMPILER="$(cd "$(dirname "$COMPILER")" && pwd)/$(basename "$COMPILER")"
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

# --- 3. projects (cshiftc new/build/run with cshift.json) -----------------------
#   tests/projects/<name>/ is copied to a temp directory first (builds create bin/ or out/).
#     expected-error.txt   build must fail and print the first line of the file
#     expected.txt         "cshiftc run" must print exactly this
#     (neither)            "cshiftc build" must succeed
echo "== projects/"
for dir in "$DIR"/projects/*/; do
    name="project $(basename "$dir")"
    work="$TMP/proj_$(basename "$dir")"
    cp -r "$dir" "$work"

    # Native sources of a project (native/*.c) are compiled to objects the project links.
    for c_file in "$work"/native/*.c; do
        [ -f "$c_file" ] || continue
        "${CSHIFT_CC:-clang}" -c "$c_file" -o "${c_file%.c}.o" || report_fail "$name" "cannot compile $c_file"
    done

    if [ -f "$work/expected-error.txt" ]; then
        want="$(head -n 1 "$work/expected-error.txt" | tr -d '\r')"
        if "$COMPILER" build "$work" $OPT "${CC_ARGS[@]}" > /dev/null 2> "$TMP/proj.err"; then
            report_fail "$name" "the build succeeded but an error was expected"
        elif ! grep -qF -- "$want" "$TMP/proj.err"; then
            report_fail "$name" "expected error '$want', got: $(head -n 3 "$TMP/proj.err" | tr '\n' ' ')"
        else
            report_ok "$name"
        fi
    elif [ -f "$work/expected.txt" ]; then
        problem=""
        "$COMPILER" run "$work" $OPT "${CC_ARGS[@]}" > "$TMP/proj.out" 2> "$TMP/proj.err" || problem="run failed: $(head -n 3 "$TMP/proj.err" | tr '\n' ' ')"
        tr -d '\r' < "$TMP/proj.out" > "$TMP/proj.out.n"
        tr -d '\r' < "$work/expected.txt" > "$TMP/proj.expected.n"
        [ -z "$problem" ] && [ "$(cat "$TMP/proj.out.n")" != "$(cat "$TMP/proj.expected.n")" ] && problem="output differs: $(cat "$TMP/proj.out.n" | tr '\n' '|')"
        # The project file is also found from a subdirectory (searched upwards).
        if [ -z "$problem" ]; then
            ( cd "$work/src" && "$COMPILER" run $OPT "${CC_ARGS[@]}" > "$TMP/proj.out2" 2> "$TMP/proj.err" ) || problem="run from a subdirectory failed: $(head -n 3 "$TMP/proj.err" | tr '\n' ' ')"
            [ -z "$problem" ] && [ "$(tr -d '\r' < "$TMP/proj.out2")" != "$(cat "$TMP/proj.expected.n")" ] && problem="output differs when run from a subdirectory"
        fi
        if [ -n "$problem" ]; then report_fail "$name" "$problem"; else report_ok "$name"; fi
    else
        if "$COMPILER" build "$work" $OPT "${CC_ARGS[@]}" > "$TMP/proj.out" 2> "$TMP/proj.err" && grep -q "Built" "$TMP/proj.out"; then
            report_ok "$name"
        else
            report_fail "$name" "build failed: $(head -n 3 "$TMP/proj.err" | tr '\n' ' ')"
        fi
    fi
done

# cshiftc new creates a working project
if "$COMPILER" new "$TMP/fresh" > /dev/null 2> "$TMP/proj.err" &&
   "$COMPILER" run "$TMP/fresh" $OPT "${CC_ARGS[@]}" 2> "$TMP/proj.err" | tr -d '\r' | grep -qx "Hello, World!"; then
    report_ok "cshiftc new"
else
    report_fail "cshiftc new" "the generated project does not print Hello, World! ($(head -n 3 "$TMP/proj.err" | tr '\n' ' '))"
fi

# --- 4. the front end written in CShift (selfhost/) ------------------------------------------------------------
#   The lexer and parser of selfhost/ are built with the compiler under test. Token and syntax tree dumps of all
#   .csh files of the repository must be identical to those of the C++ front end (selfhost/compare.sh).
#   CSHIFT_SKIP_SELFHOST=1 skips this section.
echo "== selfhost/"
if [ -n "${CSHIFT_SKIP_SELFHOST:-}" ] || [ ! -d "$DIR/../selfhost" ]; then
    echo "skipped"
else
    work="$TMP/selfhost"
    cp -r "$DIR/../selfhost" "$work"
    if ! "$COMPILER" build "$work" $OPT "${CC_ARGS[@]}" > "$TMP/selfhost.out" 2> "$TMP/selfhost.err"; then
        report_fail "selfhost build" "$(head -n 5 "$TMP/selfhost.err" | tr '\n' ' ')"
    else
        cshc="$work/bin/cshc"
        [ -f "$cshc.exe" ] && cshc="$cshc.exe"
        if bash "$DIR/../selfhost/compare.sh" "$COMPILER" "$cshc" > "$TMP/selfhost.cmp" 2>&1; then
            report_ok "selfhost front end"
        else
            report_fail "selfhost front end" "different output from the C++ front end:"
            head -n 20 "$TMP/selfhost.cmp"
        fi
        # The code generator written in CShift: the cases that passed once (selfhost/passing.txt) must keep passing.
        if bash "$DIR/../selfhost/status.sh" "$cshc" --check > "$TMP/selfhost.status" 2>&1; then
            report_ok "selfhost code generator"
            echo "ok    selfhost code generator ($(head -n 1 "$TMP/selfhost.status" | sed 's/^tests.cases with cshc: //'))"
        else
            report_fail "selfhost code generator" "a case that passed with cshc does not pass any more:"
            head -n 10 "$TMP/selfhost.status"
        fi
        # The main test program built by cshc must behave exactly like the one built by the C++ compiler.
        if "$cshc" "${CC_ARGS[@]}" --arc-stats "$DIR/test.csh" "$DIR/mathlib.csh" -o "$TMP/test.cshc.exe" 2> "$TMP/test.cshc.err"; then
            "$TMP/test.cshc.exe" > "$TMP/test.cshc.out" 2> "$TMP/test.cshc.err2"
            tr -d '\r' < "$TMP/test.cshc.out" > "$TMP/test.cshc.out.n"
            if [ "$(cat "$TMP/test.expected.n")" != "$(cat "$TMP/test.cshc.out.n")" ]; then
                report_fail "selfhost test.csh" "output differs from test.expected"
            elif ! grep -q "live=0" "$TMP/test.cshc.err2"; then
                report_fail "selfhost test.csh" "heap blocks leaked: $(grep '\[arc\]' "$TMP/test.cshc.err2")"
            else
                report_ok "selfhost test.csh"
            fi
        else
            report_fail "selfhost test.csh" "compilation failed: $(head -n 3 "$TMP/test.cshc.err" | tr '\n' ' ')"
        fi
        # The standard library that is embedded in cshc must be the current one (regenerate with cshc --gen-stdlib).
        if "$cshc" --gen-stdlib "$DIR/../stdlib" "$TMP/EmbeddedStdlib.csh" 2> /dev/null &&
           cmp -s "$TMP/EmbeddedStdlib.csh" "$DIR/../selfhost/src/Driver/EmbeddedStdlib.csh"; then
            report_ok "selfhost embedded stdlib"
        else
            report_fail "selfhost embedded stdlib" "selfhost/src/Driver/EmbeddedStdlib.csh is out of date: run  cshc --gen-stdlib stdlib selfhost/src/Driver/EmbeddedStdlib.csh"
        fi
        # Projects (cshift.json, build/run/new) built by cshc.
        if bash "$DIR/../selfhost/projects.sh" "$cshc" > "$TMP/selfhost.proj" 2>&1; then
            report_ok "selfhost projects"
            head -n 1 "$TMP/selfhost.proj"
        else
            report_fail "selfhost projects" "a project does not build with cshc:"
            head -n 10 "$TMP/selfhost.proj"
        fi
        # cshc compiles itself; the result must generate the same IR as the original (selfhost/bootstrap.sh).
        if bash "$DIR/../selfhost/bootstrap.sh" "$cshc" > "$TMP/selfhost.boot" 2>&1; then
            report_ok "selfhost bootstrap"
            cat "$TMP/selfhost.boot"
        else
            report_fail "selfhost bootstrap" "cshc cannot rebuild itself:"
            head -n 10 "$TMP/selfhost.boot"
        fi
    fi
fi

echo
echo "$PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
