#!/usr/bin/env bash
# Provides stage 0 of the bootstrap: the released cshiftc whose version is in selfhost/stage0.txt. selfhost/ and
# stdlib/ may use every language feature of that version (and no newer one); raise the version after a release when
# the compiler's own sources should use newer features.
#
#   selfhost/fetch-stage0.sh [output-dir]      prints the path of the stage 0 compiler on stdout
#
# $CSHIFT_STAGE0 names a compiler to use instead (e.g. one built locally). Otherwise the release archive for this
# platform is downloaded once into <output-dir> (default: build/stage0) with the GitHub CLI ('gh', authenticated,
# e.g. GH_TOKEN; the repository may be private), from $CSHIFT_REPO (default: Robert-Schneckenhaus/CShift).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ -n "${CSHIFT_STAGE0:-}" ]; then
    echo "$CSHIFT_STAGE0"
    exit 0
fi

VERSION="$(tr -d ' \r\n' < "$ROOT/selfhost/stage0.txt")"
OUT="${1:-$ROOT/build/stage0}"
REPO="${CSHIFT_REPO:-Robert-Schneckenhaus/CShift}"
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) name="cshift-$VERSION-windows-x64"; archive="$name.zip"; exe="cshiftc.exe" ;;
    *)                    name="cshift-$VERSION-linux-x64"; archive="$name.tar.xz"; exe="cshiftc" ;;
esac
compiler="$OUT/$name/$exe"

if [ ! -x "$compiler" ]; then
    if ! command -v gh > /dev/null 2>&1; then
        echo "error: stage 0 (cshiftc $VERSION) is needed: install the GitHub CLI ('gh') or set CSHIFT_STAGE0" >&2
        exit 1
    fi
    mkdir -p "$OUT"
    echo "downloading stage 0: $archive (v$VERSION from $REPO)" >&2
    gh release download "v$VERSION" --repo "$REPO" --pattern "$archive" --dir "$OUT" --clobber >&2
    case "$archive" in
        *.zip)    (cd "$OUT" && unzip -q -o "$archive") ;;
        *.tar.xz) tar -xJf "$OUT/$archive" -C "$OUT" ;;
    esac
    rm -f "$OUT/$archive"
fi
"$compiler" --version >&2
echo "$compiler"
