#!/usr/bin/env bash
# Turns a regular release folder (packaging/package-windows.sh or package-linux.sh) into a single, standalone
# executable: the same 'toolchain/' folder, gzip-compressed, appended after the compiler's own image, with a
# small footer so cshiftc can find it. On first use that actually needs it (linking, or "using X from
# "header.h";"), cshiftc extracts it once into a per-user cache directory and uses it from there from then on;
# every run after that just finds it already there. See CSFTTC01 in selfhost/native/host.c for the reader.
#
# This works because both the PE and the ELF loader only read what their own headers declare - trailing bytes
# appended after a normal executable are simply ignored by the OS loader, the same trick self-extracting
# installers (NSIS, 7z SFX, makeself) and AppImage use.
#
#   packaging/make-standalone.sh <dist-dir> <output-file>
#
# <dist-dir> is a package-*.sh output folder (cshift-<version>-<platform>/), already containing the compiler and
# 'toolchain/'. On Linux, the result is still not fully hermetic: package-linux.sh's toolchain relies on the
# host's C library and binutils (see its own header comment), exactly like the regular Linux archive already
# does - "standalone" here means "one file to download", not "no system dependencies at all".
set -euo pipefail

dist="${1:?a package-*.sh output folder (containing the compiler and toolchain/)}"
out="${2:?output file for the standalone executable}"

exe="$dist/cshiftc.exe"
[ -f "$exe" ] || exe="$dist/cshiftc"
[ -f "$exe" ] || { echo "error: no cshiftc(.exe) in '$dist'" >&2; exit 1; }
[ -d "$dist/toolchain" ] || { echo "error: no '$dist/toolchain' (run package-windows.sh/package-linux.sh first)" >&2; exit 1; }

file_size() { stat -c%s "$1" 2>/dev/null || stat -f%z "$1"; }

# 8 bytes -> their little-endian hex escapes, for printf '%b'. Portable (no python/perl/xxd dependency).
u64le() {
    local n="$1" out="" i byte
    for i in 0 1 2 3 4 5 6 7; do
        byte=$(( (n >> (i * 8)) & 0xFF ))
        out+="\\x$(printf '%02x' "$byte")"
    done
    printf '%b' "$out"
}

archive="$(mktemp)"
trap 'rm -f "$archive"' EXIT
tar czf "$archive" -C "$dist" toolchain

mkdir -p "$(dirname "$out")"
cat "$exe" "$archive" > "$out"
{ printf 'CSFTTC01'; u64le "$(file_size "$archive")"; } >> "$out"
chmod +x "$out"

echo "$(file_size "$exe") + $(file_size "$archive") (toolchain) + 16 (footer) = $(file_size "$out") bytes"
echo "$out"
