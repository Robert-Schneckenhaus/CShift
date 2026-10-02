#!/usr/bin/env bash
# The documentation of every earlier release, for the "since" of the reference (scripts/prepare.mjs):
#
#   site/scripts/history.sh <cshiftc> <out-dir> [<newest version>]
#
# For each release branch (origin/release/vX.XX, fetched before) up to <newest version>, its standard library is
# documented by <cshiftc> (this version's 'cshiftc doc', which reads the older sources as well): <out-dir>/X.XX.json
# and X.XX-amiga.json. A release whose library cannot be read is left out.
set -u
CSHIFTC="${1:?cshiftc}"
OUT="${2:?output directory}"
NEWEST="${3:-}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$OUT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
for v in $(git -C "$ROOT" for-each-ref --format='%(refname:short)' 'refs/remotes/origin/release/v*' | sed 's|.*/v||' | sort -V); do
    if [ -n "$NEWEST" ] && [ "$(printf '%s\n%s\n' "$v" "$NEWEST" | sort -V | tail -n 1)" != "$NEWEST" ]; then
        continue
    fi
    mkdir -p "$TMP/$v"
    git -C "$ROOT" archive "origin/release/v$v" stdlib | tar -x -C "$TMP/$v" 2> /dev/null || continue
    "$CSHIFTC" doc --stdlib "$TMP/$v/stdlib" -o "$OUT/$v.json" > /dev/null 2>&1 || rm -f "$OUT/$v.json"
    "$CSHIFTC" doc --stdlib "$TMP/$v/stdlib" --target m68k-amigaos -o "$OUT/$v-amiga.json" > /dev/null 2>&1 || rm -f "$OUT/$v-amiga.json"
done
echo "history: $(ls "$OUT" | grep -c -v amiga) releases"
