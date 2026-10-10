#!/usr/bin/env bash
# CShift test runner (bash: Linux, macOS, Git Bash, MSYS2).
#
#   tests/run_tests.sh [path/to/cshiftc] [-O0|-O1|-O2|-O3]
#
# The compiler is taken from the first argument, $CSHIFTC, build/stage2/cshiftc[.exe] (the self-hosted compiler that is
# released, see selfhost/build-release.sh) or selfhost/bin/cshc[.exe].
# clang (or the program given with $CSHIFT_CC) must be available for linking.
# CSHIFT_TARGET=<triple> builds the programs for another target that runs on this machine (i686-linux-gnu: the
# 32-bit code; needs the 32-bit C library, e.g. gcc-multilib). wasm32-wasi: WebAssembly, run with node
# (tests/wasi-run.mjs); needs wasi-libc for clang (Ubuntu: wasi-libc, libclang-rt-*-dev-wasm32). Cases that need a
# feature the target does not have say so with "// skip-target: <target prefix>".
# CSHIFT_BACKEND=<backend> compiles with another backend (wasm: CShift's own WebAssembly backend, together with
# CSHIFT_TARGET=wasm32-wasi; it needs neither clang nor wasi-libc. m68k: the 68000 backend, together with
# CSHIFT_TARGET=m68k-linux-gnu: the programs are linked by m68k-linux-gnu-gcc and run under qemu-m68k; Debian/Ubuntu:
# qemu-user gcc-m68k-linux-gnu libc6-dev-m68k-cross).
#
# What is tested:
#   1. tests/test.csh + tests/mathlib.csh  -> stdout must match tests/test.expected, all
#      checks pass and no heap block is leaked (--arc-stats).
#   2. tests/cases/*.csh                   -> small programs with expectations in comments:
#        // expect-error:  <text>   compilation must fail and print <text> (several lines: all of them)
#        // expect-exit:   <n>      exit code of the program (default 0)
#        // expect-stdout: <text>   stdout contains <text>   (may be repeated)
#        // expect-stdout-64: <text>, expect-stdout-32: <text>   the same, only on targets with 64-bit / 32-bit pointers
#        // expect-stderr: <text>   stderr contains <text>   (may be repeated)
#        // arc-ignore              skip the leak check
#        // options:       <args>   extra compiler options (e.g. --unchecked)
#        // stdin:         <text>   a line of the program's standard input (may be repeated; without it, stdin is empty)
#   3. tests/projects/*/                  -> projects built with "cshiftc build|run" (see the comment further down),
#      plus "cshiftc new". A project may contain native/*.c files (compiled with clang before the build) for FFI tests.
#   3b. tests/query/*.csh                 -> "cshiftc query" (hover, definition) and "cshiftc check"; the tests of the
#      VS Code extension (vscode-extension/test, if node is installed); tests/publish/*/: "cshiftc publish", the page
#      run by node (tests/publish-run.mjs); "cshiftc serve" (tests/serve-check.mjs).

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
    for c in "$DIR/../build/stage2/cshiftc" "$DIR/../build/stage2/cshiftc.exe" "$DIR/../selfhost/bin/cshc" "$DIR/../selfhost/bin/cshc.exe"; do
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
C_TARGET=()
if [ -n "${CSHIFT_TARGET:-}" ]; then CC_ARGS+=(--target "$CSHIFT_TARGET"); C_TARGET=(--target="$CSHIFT_TARGET"); fi
if [ -n "${CSHIFT_BACKEND:-}" ]; then CC_ARGS+=(--backend "$CSHIFT_BACKEND"); fi
# How a compiled program runs: directly, or through node for WebAssembly
RUNNER=()
case "${CSHIFT_TARGET:-}" in
    wasm32-*) RUNNER=(node --no-warnings "$DIR/wasi-run.mjs") ;;
    m68k-*linux*) RUNNER=(qemu-m68k) ;;
esac
POINTER_BITS=64
case "${CSHIFT_TARGET:-}" in
    i[3-6]86-*|x86-*|arm-*|armv*|thumb*|m68k-*|mips-*|mipsel-*|powerpc-*|riscv32-*|wasm32-*) POINTER_BITS=32 ;;
esac

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
    "${RUNNER[@]}" "$TMP/test.exe" > "$TMP/test.out" 2> "$TMP/test.err"
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
    options="$(directives "$file" options | head -n 1)"
    skip=""
    while IFS= read -r prefix; do
        prefix="${prefix%% *}" # the target prefix, then the reason
        [ -n "$prefix" ] && [ -n "${CSHIFT_TARGET:-}" ] && [ "${CSHIFT_TARGET#"$prefix"}" != "$CSHIFT_TARGET" ] && skip=1
    done < <(directives "$file" skip-target)
    [ -n "$skip" ] && continue

    if [ -n "$expected_error" ]; then
        if "$COMPILER" $OPT $options "${CC_ARGS[@]}" "$file" -o "$TMP/case.exe" 2> "$TMP/case.err" > /dev/null; then
            report_fail "$name" "compilation succeeded but an error was expected"
        else
            missing=""
            while IFS= read -r text; do
                [ -z "$text" ] && continue
                grep -qF -- "$text" "$TMP/case.err" || missing="$text"
            done < <(directives "$file" expect-error)
            if [ -n "$missing" ]; then
                report_fail "$name" "expected error '$missing', got: $(head -n 3 "$TMP/case.err" | tr '\n' ' ')"
            else
                report_ok "$name"
            fi
        fi
        continue
    fi

    if ! "$COMPILER" $OPT $options "${CC_ARGS[@]}" --arc-stats "$file" -o "$TMP/case.exe" 2> "$TMP/case.err"; then
        report_fail "$name" "compilation failed: $(head -n 3 "$TMP/case.err" | tr '\n' ' ')"
        continue
    fi
    # Run in the temp directory: some tests create files.
    directives "$file" stdin > "$TMP/case.in"
    ( cd "$TMP" && "${RUNNER[@]}" "$TMP/case.exe" < "$TMP/case.in" > "$TMP/case.out" 2> "$TMP/case.run.err" )
    code=$?
    want_exit="$(directives "$file" expect-exit | head -n 1)"
    want_exit="${want_exit:-0}"
    problem=""
    [ "$code" -ne "$want_exit" ] && problem="exit code $code, expected $want_exit"
    while IFS= read -r text; do
        [ -z "$text" ] && continue
        grep -qF -- "$text" "$TMP/case.out" || problem="stdout does not contain '$text'"
    done < <(directives "$file" expect-stdout; directives "$file" "expect-stdout-$POINTER_BITS")
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
# Programs for WebAssembly do not run on their own: the projects (cshiftc run) and the debugger need a native target.
if [ ${#RUNNER[@]} -gt 0 ]; then
    echo "== projects/ (skipped for ${CSHIFT_TARGET})"
else
    echo "== projects/"
    for dir in "$DIR"/projects/*/; do
        name="project $(basename "$dir")"
        work="$TMP/proj_$(basename "$dir")"
        cp -r "$dir" "$work"

        # Native sources of a project (native/*.c) are compiled to objects the project links.
        for c_file in "$work"/native/*.c; do
            [ -f "$c_file" ] || continue
            "${CSHIFT_CC:-clang}" "${C_TARGET[@]}" -c "$c_file" -o "${c_file%.c}.o" || report_fail "$name" "cannot compile $c_file"
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

    # --checked overrides "unchecked": true of a project
    if "$COMPILER" run --checked "$DIR/projects/unchecked" $OPT "${CC_ARGS[@]}" -o "$TMP/checked_override" > /dev/null 2> "$TMP/proj.err"; then
        report_fail "cshiftc --checked" "the overflow did not panic"
    elif ! grep -q "panic: integer overflow" "$TMP/proj.err"; then
        report_fail "cshiftc --checked" "expected an overflow panic, got: $(head -n 3 "$TMP/proj.err" | tr '\n' ' ')"
    else
        report_ok "cshiftc --checked"
    fi

    # cshiftc new creates a working project
    if "$COMPILER" new "$TMP/fresh" > /dev/null 2> "$TMP/proj.err" &&
       "$COMPILER" run "$TMP/fresh" $OPT "${CC_ARGS[@]}" 2> "$TMP/proj.err" | tr -d '\r' | grep -qx "Hello, World!"; then
        report_ok "cshiftc new"
    else
        report_fail "cshiftc new" "the generated project does not print Hello, World! ($(head -n 3 "$TMP/proj.err" | tr '\n' ' '))"
    fi

    # An AmigaOS executable contains only what it uses (needs no clang): hello world without printf's formatting code
    printf 'using System;\nint Main()\n{\n    Console.WriteLine("Hello " + 42.ToString());\n    return 0;\n}\n' > "$TMP/amiga_hello.csh"
    if "$COMPILER" --target m68k-amigaos --stdlib "$DIR/../stdlib" "$TMP/amiga_hello.csh" --emit-asm -o "$TMP/amiga_hello.s" 2> "$TMP/amiga.err" &&
       "$COMPILER" --target m68k-amigaos --stdlib "$DIR/../stdlib" "$TMP/amiga_hello.csh" -o "$TMP/amiga_hello" 2>> "$TMP/amiga.err"; then
        size=$(wc -c < "$TMP/amiga_hello" | tr -d ' ')
        if grep -q "__cs_vformat\|^printf:" "$TMP/amiga_hello.s"; then
            report_fail "amiga trimming" "hello world contains printf"
        elif [ "$size" -gt 12000 ]; then
            report_fail "amiga trimming" "hello world has $size bytes (more than 12000)"
        else
            report_ok "amiga trimming"
        fi
    else
        report_fail "amiga trimming" "$(head -n 3 "$TMP/amiga.err" | tr '\n' ' ')"
    fi

    # With vamos (amitools: pip install amitools "machine68k<0.4") AmigaOS programs run on this machine: the copies
    # and fills of the Amiga runtime (memcpy, memmove, memset with their jump towers) against plain loops
    if command -v vamos > /dev/null 2>&1; then
        if ! "$COMPILER" --target m68k-amigaos --stdlib "$DIR/../stdlib" "$DIR/amiga/memory.csh" -o "$TMP/amiga_memory" 2> "$TMP/amiga.err"; then
            report_fail "amiga runtime (vamos)" "$(head -n 3 "$TMP/amiga.err" | tr '\n' ' ')"
        elif ! (cd "$TMP" && vamos amiga_memory > "$TMP/amiga.out" 2>&1) || ! grep -q "errors 0" "$TMP/amiga.out"; then
            report_fail "amiga runtime (vamos)" "$(tail -n 3 "$TMP/amiga.out" | tr '\n' ' ')"
        else
            report_ok "amiga runtime (vamos)"
        fi
    fi

    # Debug information (-g): LLVM accepts the metadata (it verifies it while compiling), the program still runs, and, if
    # gdb is installed, a breakpoint on a line stops there with the file and line in the backtrace, shows the parameters
    # and a global variable and, with the pretty printers that the program carries, a string as its text.
    printf 'using System;\n\nint Square(int x)\n{\n    int y = x * x;\n    return y;\n}\n\nint Main()\n{\n    Func<int, int> twice = (int v) => v * 2;\n    string name = "Ann";\n    return twice(Square(3)) - 18 + name.Length - 3 + Hits - 7;\n}\n\nint Hits = 7;\n' > "$TMP/debug_info.csh"
    if ! "$COMPILER" -g -O0 "${CC_ARGS[@]}" "$TMP/debug_info.csh" -o "$TMP/debug_info.exe" 2> "$TMP/debug.err"; then
        report_fail "debug information" "$(head -n 3 "$TMP/debug.err" | tr '\n' ' ')"
    elif ! "$TMP/debug_info.exe"; then
        report_fail "debug information" "the program built with -g does not run correctly"
    elif ! "$COMPILER" -g --emit-llvm "$TMP/debug_info.csh" -o "$TMP/debug_info.ll" 2>> "$TMP/debug.err" ||
         ! grep -q 'DISubprogram(name: "Square"' "$TMP/debug_info.ll"; then
        report_fail "debug information" "no subprogram for Square in the IR"
    elif [ "$(uname -s)" = "Linux" ] && command -v gdb > /dev/null 2>&1 &&
         ! gdb -batch -ex 'break debug_info.csh:5' -ex run -ex bt "$TMP/debug_info.exe" 2>&1 | grep -q "in Main () at .*debug_info.csh:13"; then
        report_fail "debug information" "gdb does not stop at debug_info.csh:5 with Main at line 13 in the backtrace"
    elif [ "$(uname -s)" = "Linux" ] && command -v gdb > /dev/null 2>&1 &&
         ! gdb -batch -ex 'break debug_info.csh:5' -ex run -ex 'info args' -ex up -ex 'info locals' "$TMP/debug_info.exe" 2>&1 | grep -q "x = 3"; then
        report_fail "debug information" "gdb does not show the parameter x = 3"
    elif [ "$(uname -s)" = "Linux" ] && command -v gdb > /dev/null 2>&1 &&
         ! gdb -batch -ex 'break debug_info.csh:5' -ex run -ex 'print Hits' "$TMP/debug_info.exe" 2>&1 | grep -q "= 7"; then
        report_fail "debug information" "gdb does not show the global variable Hits = 7"
    elif [ "$(uname -s)" = "Linux" ] && command -v gdb > /dev/null 2>&1 && gdb -batch -ex 'python print(1)' > /dev/null 2>&1 &&
         ! gdb -batch -iex "add-auto-load-safe-path $TMP" -ex 'break debug_info.csh:5' -ex run -ex up -ex 'print name' "$TMP/debug_info.exe" 2>&1 | grep -q '= "Ann"'; then
        report_fail "debug information" "gdb does not show the string variable name as \"Ann\" (the pretty printers of tools/debug/cshift_gdb.py)"
    else
        report_ok "debug information"
    fi
fi

# --- 3b. cshiftc check / query (the VS Code extension) ---------------------------------------------------------
#   tests/query/*.csh: "// query: <line> <col> => <text>": the JSON answer of "cshiftc query --at <file> <line> <col>"
#   contains <text> (the file alone is the program). "cshiftc check" reports the errors of a program and generates
#   nothing: exit code 1 with the messages, 0 for a correct program.
echo "== query/"
for f in "$DIR"/query/*.csh; do
    [ -f "$f" ] || continue
    name="query $(basename "$f")"
    problem=""
    while IFS= read -r line; do
        pos="${line%% => *}"
        want="${line#* => }"
        qline="${pos%% *}"
        qcol="${pos##* }"
        got="$("$COMPILER" query --at "$f" "$qline" "$qcol" "$f" 2> /dev/null | tr -d '\r')"
        case "$got" in
            *"$want"*) ;;
            *) problem="at $qline:$qcol expected '$want', got: $got"; break ;;
        esac
    done < <(directives "$f" "query")
    if [ -n "$problem" ]; then report_fail "$name" "$problem"; else report_ok "$name"; fi
done
# Names imported from a C header (the ffi project, copied and built in section 3): the hover of the namespace, and go
# to definition goes to the line of the header the name is declared in.
ffi_main="$TMP/proj_ffi/src/main.csh"
if [ -f "$ffi_main" ]; then
    problem=""
    for q in "70 17|int32 Geo.geo_add(int32 a, int32 b)|\"line\": 41" "70 17|native/geo.h|\"col\": 5" "70 13|namespace Geo (imported from|geo.h" "63 17|const int32 GEO_VERSION = 3|\"line\": 7"; do
        pos="${q%%|*}"; rest="${q#*|}"; want1="${rest%%|*}"; want2="${rest#*|}"
        got="$("$COMPILER" query --at "$ffi_main" ${pos% *} ${pos#* } "$TMP/proj_ffi" 2> /dev/null | tr -d '\r')"
        case "$got" in *"$want1"*"$want2"*|*"$want2"*"$want1"*) ;; *) problem="at $pos expected '$want1' and '$want2', got: $got"; break ;; esac
    done
    if [ -n "$problem" ]; then report_fail "query ffi" "$problem"; else report_ok "query ffi"; fi
fi
# A constant from embed("file") shows the text of the file (the embed project, copied in section 3).
embed_main="$TMP/proj_embed/src/main.csh"
if [ -f "$embed_main" ]; then
    got="$("$COMPILER" query --at "$embed_main" 4 14 "$TMP/proj_embed" 2> /dev/null | tr -d '\r')"
    case "$got" in
        *'const string Version // 6 bytes, 1 line\n1.2.3"'*) report_ok "query embed" ;;
        *) report_fail "query embed" "expected the text of data/version.txt, got: $got" ;;
    esac
fi
printf 'int Main()\n{\n    int x = "a";\n    return y;\n}\n' > "$TMP/check_bad.csh"
if "$COMPILER" check "$TMP/check_bad.csh" > /dev/null 2> "$TMP/check.err"; then
    report_fail "cshiftc check" "a program with errors passed"
elif ! grep -q "check_bad.csh:3:13: error: cannot implicitly convert" "$TMP/check.err" || ! grep -q "check_bad.csh:4:12: error: undefined name 'y'" "$TMP/check.err"; then
    report_fail "cshiftc check" "missing errors: $(tr '\n' ' ' < "$TMP/check.err")"
elif ! "$COMPILER" check "$DIR/query/names.csh" > /dev/null 2> "$TMP/check.err" || [ -e "$DIR/query/names" ]; then
    report_fail "cshiftc check" "a correct program failed or an output was written: $(head -n 3 "$TMP/check.err" | tr '\n' ' ')"
else
    report_ok "cshiftc check"
fi
# "cshiftc doc": the doc comments of a program as JSON, the errors in doc comments, and the doc comments of the
# standard library are correct and complete.
problem=""
if ! "$COMPILER" doc "$DIR/query/doc_comments.csh" > "$TMP/doc.json" 2> "$TMP/doc.err"; then
    problem="failed: $(head -n 3 "$TMP/doc.err" | tr '\n' ' ')"
else
    for want in '{"name": "", "doc": {"summary": "Points and colors."' '"name": "Add", "signature": "Point Add(Point other)"' \
                '"params": [{"name": "other", "text": "the point to add, in the same units."}], "returns": "the sum, see [Point.X]."' \
                '"signature": "Color.Green = 2"' '"errors": [{"name": "ParseError.Invalid", "text": "the text is not a number."}]' \
                '"since": "0.22"' '"name": "Y", "signature": "int Y"'; do
        grep -qF "$want" "$TMP/doc.json" || { problem="the JSON does not contain: $want"; break; }
    done
    if [ -z "$problem" ] && grep -qF '"name": "Main"' "$TMP/doc.json"; then problem="the JSON documents Main"; fi
fi
printf '%s\n' '/// Bad.' '/// @param y not there' '/// @bogus' '/// See [Nowhere].' '/// @error IoError.Missing never' \
    'void F(int x) { }' 'struct S { int A; }' > "$TMP/doc_bad.csh"
if [ -z "$problem" ]; then
    if "$COMPILER" doc "$TMP/doc_bad.csh" > /dev/null 2> "$TMP/doc.err"; then
        problem="wrong doc comments passed"
    else
        for want in "doc_bad.csh:6:6: error: '@param y': function F has no parameter 'y'" "unknown tag '@bogus' in the doc comment of function F" \
                    "cannot find 'Nowhere' (a link in the doc comment of function F)" "'@error IoError.Missing' in the doc comment of function F: no such error"; do
            grep -qF "$want" "$TMP/doc.err" || { problem="missing error: $want"; break; }
        done
    fi
fi
if [ -z "$problem" ] && ! "$COMPILER" doc --require-docs "$TMP/doc_bad.csh" 2>&1 | grep -qF "doc_bad.csh:7:12: error: field S.A has no doc comment"; then
    problem="--require-docs does not report the field S.A"
fi
# every public declaration of the standard library is documented (also the AmigaOS part)
for target in "" "m68k-amigaos"; do
    if [ -z "$problem" ] && ! "$COMPILER" doc --require-docs --stdlib "$DIR/../stdlib" ${target:+--target "$target"} > /dev/null 2> "$TMP/doc.err"; then
        problem="the doc comments of the standard library${target:+ for $target}: $(head -n 5 "$TMP/doc.err" | tr '\n' ' ')"
    fi
done
if [ -n "$problem" ]; then report_fail "cshiftc doc" "$problem"; else report_ok "cshiftc doc"; fi
# The VS Code extension (vscode-extension/test): its logic and its connection to the editor, with this cshiftc.
# Under MSYS2/Git Bash node is a Windows program: it may not be in PATH, and it needs Windows paths. Like the projects
# it needs a native target (F5 builds the program for the debugger with clang); it does not depend on CSHIFT_TARGET,
# so a pass for WebAssembly leaves it to the native one.
NODE=""
if command -v node > /dev/null 2>&1; then
    NODE="node"
elif [ -x "/c/Program Files/nodejs/node.exe" ]; then
    NODE="/c/Program Files/nodejs/node.exe"
fi
EXT_TESTS="$DIR/../vscode-extension/test"
EXT_COMPILER="$COMPILER"
if command -v cygpath > /dev/null 2>&1; then
    EXT_TESTS="$(cygpath -w "$EXT_TESTS")"
    EXT_COMPILER="$(cygpath -w "$COMPILER")"
fi
if [ ${#RUNNER[@]} -gt 0 ]; then
    echo "vscode extension: skipped for ${CSHIFT_TARGET} (F5 needs a native target)"
elif [ -n "$NODE" ]; then
    if CSHIFTC="$EXT_COMPILER" "$NODE" --test "$EXT_TESTS/lib.test.js" "$EXT_TESTS/extension.test.js" > "$TMP/ext.out" 2>&1; then
        report_ok "vscode extension"
    else
        report_fail "vscode extension" "$(grep -E '^not ok|Error|expected|actual' "$TMP/ext.out" | head -n 6 | tr '\n' ' ')"
    fi
else
    echo "vscode extension: skipped (node not found)"
fi

# cshiftc publish (tests/publish/<name>/): the page of a project, run by node with the program, the files and the
# runtime that the page holds (tests/publish-run.mjs). The output must be expected.txt, the exit code the number in
# expected-exit.txt (default 0); the program is not left next to the page. Like the extension it does not depend on
# CSHIFT_TARGET (a page is always WebAssembly), so a pass for WebAssembly leaves it to the native one.
if [ ${#RUNNER[@]} -gt 0 ]; then
    echo "publish: skipped for ${CSHIFT_TARGET} (done by the native pass)"
elif [ -n "$NODE" ]; then
    echo "== publish/"
    for dir in "$DIR"/publish/*/; do
        project="$(basename "$dir")"
        name="publish $project"
        work="$TMP/publish_$project"
        cp -r "$dir" "$work"
        page="$work/bin/$project.html"
        run_page=("$DIR/publish-run.mjs" "$page")
        if command -v cygpath > /dev/null 2>&1; then run_page=("$(cygpath -w "$DIR/publish-run.mjs")" "$(cygpath -w "$page")"); fi
        want_exit=0
        [ -f "$work/expected-exit.txt" ] && want_exit="$(tr -d '\r\n ' < "$work/expected-exit.txt")"
        if ! "$COMPILER" publish "$work" > "$TMP/publish.out" 2> "$TMP/publish.err"; then
            report_fail "$name" "publish failed: $(head -n 3 "$TMP/publish.err" | tr '\n' ' ')"
        elif ! grep -q "Published" "$TMP/publish.out" || [ ! -f "$page" ] || [ -f "$page.wasm" ]; then
            report_fail "$name" "no page at bin/$project.html (or the .wasm was left next to it): $(head -n 2 "$TMP/publish.out" | tr '\n' ' ')"
        else
            "$NODE" "${run_page[@]}" > "$TMP/publish.run" 2> "$TMP/publish.run.err"
            code=$?
            if [ "$code" != "$want_exit" ]; then
                report_fail "$name" "exit code $code instead of $want_exit: $(head -n 3 "$TMP/publish.run.err" | tr '\n' ' ')"
            elif [ "$(tr -d '\r' < "$TMP/publish.run")" != "$(tr -d '\r' < "$work/expected.txt")" ]; then
                report_fail "$name" "output differs: $(tr -d '\r' < "$TMP/publish.run" | tr '\n' '|')"
            else
                report_ok "$name"
            fi
        fi
    done
else
    echo "publish: skipped (node not found)"
fi

# cshiftc serve: the server of tests/publish/assets (a copy) on a port of its own; tests/serve-check.mjs changes a
# source and breaks it, and waits for each build (the page and the number that the page asks for)
if [ ${#RUNNER[@]} -eq 0 ] && [ -n "$NODE" ]; then
    work="$TMP/serve_assets"
    cp -r "$DIR/publish/assets" "$work"
    port=$((20000 + $$ % 20000))
    check=("$DIR/serve-check.mjs" "$port" "$work")
    if command -v cygpath > /dev/null 2>&1; then check=("$(cygpath -w "$DIR/serve-check.mjs")" "$port" "$(cygpath -w "$work")"); fi
    "$COMPILER" serve "$work" --port "$port" > "$TMP/serve.out" 2>&1 &
    serve_pid=$!
    if "$NODE" "${check[@]}" > "$TMP/serve.check" 2>&1; then
        report_ok "cshiftc serve"
    else
        report_fail "cshiftc serve" "$(tail -n 2 "$TMP/serve.check" | tr '\n' ' ') (server: $(tail -n 3 "$TMP/serve.out" | tr '\n' ' '))"
    fi
    kill "$serve_pid" 2> /dev/null
    wait "$serve_pid" 2> /dev/null
fi

# --- 4. the front end written in CShift (selfhost/) ------------------------------------------------------------
#   cshc (selfhost/) is built with the compiler under test; it must pass the test cases, build the projects and
#   rebuild itself (bootstrap). CSHIFT_SKIP_SELFHOST=1 skips this section: for a compiler under test that is built from
#   these sources by selfhost/build-release.sh (as in ci.yml), it would repeat sections 1 to 3 with the same compiler.
echo "== selfhost/"
if [ -n "${CSHIFT_SKIP_SELFHOST:-}" ] || [ ! -d "$DIR/../selfhost" ]; then
    echo "skipped"
else
    work="$TMP/selfhost"
    cp -r "$DIR/../selfhost" "$work"
    cp -r "$DIR/../stdlib" "$TMP/stdlib" # read at compile time by embed (../../../stdlib from selfhost/src/Driver)
    mkdir -p "$TMP/tools" && cp -r "$DIR/../tools/debug" "$TMP/tools/debug" # the gdb pretty printers (CodeGen/Debug.csh)
    mkdir -p "$TMP/web" && cp "$DIR/../web/cshift.js" "$TMP/web/cshift.js" # the runtime of 'publish' (Driver/Publish.csh)
    if ! "$COMPILER" build "$work" $OPT "${CC_ARGS[@]}" > "$TMP/selfhost.out" 2> "$TMP/selfhost.err"; then
        report_fail "selfhost build" "$(head -n 5 "$TMP/selfhost.err" | tr '\n' ' ')"
    else
        cshc="$work/bin/cshc"
        [ -f "$cshc.exe" ] && cshc="$cshc.exe"
        # The code generator written in CShift: the cases that passed once (selfhost/passing.txt) must keep passing.
        if bash "$DIR/../selfhost/status.sh" "$cshc" --check > "$TMP/selfhost.status" 2>&1; then
            report_ok "selfhost code generator"
            echo "ok    selfhost code generator ($(head -n 1 "$TMP/selfhost.status" | sed 's/^tests.cases with cshc: //'))"
        else
            report_fail "selfhost code generator" "a case that passed with cshc does not pass any more:"
            head -n 10 "$TMP/selfhost.status"
        fi
        # The main test program built by cshc must behave exactly like the one built by the compiler under test.
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
        # Projects (cshift.json, build/run/new, C headers through libclang) built by cshc.
        if [ -n "${CSHIFT_TARGET:-}" ]; then
            echo "selfhost projects: skipped (cshc built for $CSHIFT_TARGET cannot load the libclang of this machine)"
        elif bash "$DIR/../selfhost/projects.sh" "$cshc" > "$TMP/selfhost.proj" 2>&1; then
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

# --- 5. the wasm backend: its own cases (tests/wasm/*.csh: the output must be <name>.expected, exit code 0), then it
#        compiles the compiler: as WebAssembly (under node) that must build itself again, byte for byte -------------
if [ "${CSHIFT_BACKEND:-}" = "wasm" ]; then
    echo "== wasm/"
    for file in "$DIR"/wasm/*.csh; do
        name="$(basename "$file" .csh)"
        if ! "$COMPILER" --backend wasm "$file" -o "$TMP/wasm-case.wasm" 2> "$TMP/wasm-case.err"; then
            report_fail "wasm/$name" "compilation failed: $(head -n 3 "$TMP/wasm-case.err" | tr '\n' ' ')"
        elif ! "${RUNNER[@]}" "$TMP/wasm-case.wasm" > "$TMP/wasm-case.out" 2> "$TMP/wasm-case.err"; then
            report_fail "wasm/$name" "the program failed: $(head -n 3 "$TMP/wasm-case.err" | tr '\n' ' ')"
        elif ! diff -q <(tr -d '\r' < "$TMP/wasm-case.out") "$DIR/wasm/$name.expected" > /dev/null; then
            report_fail "wasm/$name" "output differs from $name.expected: $(head -n 3 "$TMP/wasm-case.out" | tr '\n' ' ')"
        else
            report_ok "wasm/$name"
        fi
    done

    echo "== wasm backend: cshc.wasm builds itself"
    lib=(--stdlib "$DIR/../stdlib")
    if ! (cd "$DIR/.." && "$COMPILER" build selfhost --backend wasm "${lib[@]}" -o "$TMP/cshc-a.wasm") > /dev/null 2> "$TMP/wasm-a.err"; then
        report_fail "wasm bootstrap" "cshc does not build: $(grep -v 'imported from' "$TMP/wasm-a.err" | head -n 3 | tr '\n' ' ')"
    elif ! (cd "$DIR/.." && "${RUNNER[@]}" "$TMP/cshc-a.wasm" build selfhost --backend wasm "${lib[@]}" -o "$TMP/cshc-b.wasm") > /dev/null 2> "$TMP/wasm-b.err"; then
        report_fail "wasm bootstrap" "cshc.wasm cannot build itself: $(grep -v 'imported from' "$TMP/wasm-b.err" | head -n 3 | tr '\n' ' ')"
    elif ! cmp -s "$TMP/cshc-a.wasm" "$TMP/cshc-b.wasm"; then
        report_fail "wasm bootstrap" "cshc.wasm builds a different cshc.wasm"
    else
        report_ok "wasm bootstrap"
    fi
fi

echo
echo "$PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
