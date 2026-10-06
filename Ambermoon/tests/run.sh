#!/usr/bin/env bash
# Tests of the Ambermoon tools: the results of AmbermoonPack and AmbermoonEventEditor for synthetic data (pack/,
# events/; made by tools/make_data.py) must be the ones of the original tools (expected.txt: MD5 sums of the console
# output and of the files written).
#
#   Ambermoon/tests/run.sh [path/to/cshiftc]                    builds the tools and compares (default compiler:
#                                                               $CSHIFTC, build/stage2/cshiftc, selfhost/bin/cshc)
#   Ambermoon/tests/run.sh --record "<pack command>" "<editor command>"
#                                                               writes expected.txt with the original tools, e.g.
#                                                               "dotnet AmbermoonPack.dll" "dotnet AmbermoonEventEditor.dll"
#
# The console output is compared without carriage returns (Windows writes them for line breaks).
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

RECORD=0
if [ "${1:-}" = "--record" ]; then
    RECORD=1
    PACK="${2:?the command of the original AmbermoonPack}"
    EDITOR="${3:?the command of the original AmbermoonEventEditor}"
else
    COMPILER="${1:-${CSHIFTC:-}}"
    if [ -z "$COMPILER" ]; then
        for c in "$ROOT/build/stage2/cshiftc" "$ROOT/build/stage2/cshiftc.exe" "$ROOT/selfhost/bin/cshc" "$ROOT/selfhost/bin/cshc.exe"; do
            if [ -x "$c" ]; then COMPILER="$c"; break; fi
        done
    fi
    if [ -z "$COMPILER" ]; then echo "cshiftc not found"; exit 2; fi
    CC_ARGS=()
    if [ -n "${CSHIFT_CC:-}" ]; then CC_ARGS=(--cc "$CSHIFT_CC"); fi
    for tool in AmbermoonPack AmbermoonEventEditor; do
        if ! "$COMPILER" build "$ROOT/Ambermoon/$tool" "${CC_ARGS[@]}" -o "$TMP/$tool" > "$TMP/build.log" 2>&1; then
            echo "FAIL  Ambermoon: building $tool failed:"
            head -n 20 "$TMP/build.log"
            exit 1
        fi
    done
    PACK="$TMP/AmbermoonPack"
    EDITOR="$TMP/AmbermoonEventEditor"
fi

hash_text() { tr -d '\r' < "$1" | md5sum | cut -c1-32; }
hash_file() { if [ -f "$1" ]; then md5sum < "$1" | cut -c1-32; else echo "-"; fi; }
# all files of a folder: names and contents
hash_dir() {
    if [ -d "$1" ]; then (cd "$1" && for f in $(ls); do echo "$f $(md5sum < "$f" | cut -c1-32)"; done) | md5sum | cut -c1-32; else echo "-"; fi
}

RESULTS="$TMP/results.txt"
: > "$RESULTS"

# AmbermoonPack: pack, then unpack what was packed
while read -r name args; do
    case "$name" in ''|'#'*) continue ;; esac
    work="$TMP/p_$name"
    mkdir -p "$work"
    cp -r "$DIR/pack/files" "$DIR/pack/textfiles" "$DIR/pack/items" "$work/"
    # shellcheck disable=SC2086
    (cd "$work" && $PACK $args > stdout 2>&1 < /dev/null; echo "exit $?" >> stdout)
    echo "pack $name $(hash_text "$work/stdout") $(hash_file "$work/out")" >> "$RESULTS"
    if [ -f "$work/out" ]; then
        if [ "$name" = "pkitem" ]; then
            (cd "$work" && $PACK UNITEM out unpacked > stdout2 2>&1 < /dev/null; echo "exit $?" >> stdout2)
        else
            (cd "$work" && $PACK UNPACK out unpacked > stdout2 2>&1 < /dev/null; echo "exit $?" >> stdout2)
        fi
        echo "unpack $name $(hash_text "$work/stdout2") $(hash_dir "$work/unpacked")" >> "$RESULTS"
    fi
done < "$DIR/pack/cases.txt"

# AmbermoonEventEditor: sessions of commands
n=0
while read -r session file type; do
    case "$session" in ''|'#'*) continue ;; esac
    n=$((n + 1))
    work="$TMP/e_$n"
    mkdir -p "$work"
    input="$(basename "$file")"
    cp "$DIR/events/$file" "$work/$input"
    sed 's#@OUT@#saved#g' "$DIR/events/sessions/$session" > "$work/session"
    (cd "$work" && $EDITOR "$input" "$type" < session > stdout 2>&1; echo "exit $?" >> stdout)
    echo "events $session:$file $(hash_text "$work/stdout") $(hash_file "$work/saved") $(hash_file "$work/$input")" >> "$RESULTS"
done < "$DIR/events/cases.txt"

if [ $RECORD -eq 1 ]; then
    { echo "# MD5 sums of the results of the original tools (Ambermoon/tests/run.sh --record): kind, case, console output,"
      echo "# written file (or folder) and, for the editor, the edited file."
      cat "$RESULTS"; } > "$DIR/expected.txt"
    echo "wrote $DIR/expected.txt ($(wc -l < "$RESULTS") results)"
    exit 0
fi

pass=0
fail=0
while read -r kind name rest; do
    want="$(grep -F "$kind $name " "$DIR/expected.txt" | head -n 1)"
    if [ "$want" = "$kind $name $rest" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL  Ambermoon $kind $name"
        echo "      expected: ${want:-(none)}"
        echo "      got:      $kind $name $rest"
    fi
done < "$RESULTS"
echo "ok    Ambermoon tools ($pass of $((pass + fail)) results like the original)"
[ $fail -eq 0 ]
