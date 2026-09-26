#!/usr/bin/env bash
# Builds the compiler that is released: cshc, the CShift compiler written in CShift, installed as 'cshiftc'.
#
#   selfhost/build-release.sh <stage0> <version> <output-dir>
#
#   stage 0   the C++ compiler (build/cshiftc, frozen: it only has to be able to compile cshc)
#   stage 1   cshc built by stage 0
#   stage 2   cshc built by stage 1: <output-dir>/cshiftc[.exe], the released compiler
#
# The bootstrap check (selfhost/bootstrap.sh) makes sure that stage 1 and stage 2 generate the same IR for the sources
# of cshc. The version is written into selfhost/version/version.txt for the build and restored afterwards.
# clang has to be found ($CSHIFT_CC or PATH).
set -euo pipefail
STAGE0="${1:?path of the C++ compiler (stage 0)}"
VERSION="${2:?version, e.g. 1.05 or dev}"
OUT="${3:?output directory}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CC_ARGS=()
if [ -n "${CSHIFT_CC:-}" ]; then CC_ARGS=(--cc "$CSHIFT_CC"); fi
EXE=""
case "$STAGE0" in *.exe) EXE=".exe" ;; esac

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
version_file="$ROOT/selfhost/version/version.txt"
saved="$(cat "$version_file")"
trap 'printf "%s\n" "$saved" > "$version_file"' EXIT
printf '%s\n' "$VERSION" > "$version_file"

echo "stage 1: cshc built by $STAGE0"
"$STAGE0" build "$ROOT/selfhost" "${CC_ARGS[@]}" -o "$OUT/stage1/cshc$EXE"
echo "stage 2: cshc built by stage 1"
"$OUT/stage1/cshc$EXE" build "$ROOT/selfhost" "${CC_ARGS[@]}" -o "$OUT/cshiftc$EXE"
bash "$ROOT/selfhost/bootstrap.sh" "$OUT/stage1/cshc$EXE"
"$OUT/cshiftc$EXE" --version
