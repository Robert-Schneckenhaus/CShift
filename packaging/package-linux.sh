#!/usr/bin/env bash
# Creates the Linux release folder: cshiftc plus clang and libclang, so that the folder works after it has been
# extracted and added to PATH. The C library (libc6-dev), gcc's startup files and binutils come from the system
# ("build-essential"), like for every C toolchain.
#
#   packaging/package-linux.sh <version> <build-dir> <output-dir>
#
# LLVM_PREFIX (default /usr/lib/llvm-22) is the LLVM installation whose clang is bundled. patchelf is required.
# Result: <output-dir>/cshift-<version>-linux-x64/
set -euo pipefail

version="${1:?version}"
build="${2:?build directory that contains cshiftc}"
out="${3:?output directory}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
llvm="${LLVM_PREFIX:-/usr/lib/llvm-22}"
name="cshift-$version-linux-x64"
dist="$out/$name"

rm -rf "$dist"
mkdir -p "$dist/toolchain/bin" "$dist/toolchain/lib"

# ---- the compiler and the documentation ----
cp "$build/cshiftc" "$dist/"
cp "$root/README.md" "$root/FFI.md" "$root/Buildkonzept.md" "$root/Sprachkonzept.md" "$dist/"
cp "$root/packaging/README-release-linux.txt" "$dist/README.txt"
sed -i "s/@VERSION@/$version/g" "$dist/README.txt"
echo "$version" > "$dist/VERSION"

# ---- toolchain: clang ----
cp -L "$llvm/bin/clang" "$dist/toolchain/bin/clang"

# The LLVM libraries clang needs (libLLVM, libclang-cpp), stored under the names the program asks for. Libraries
# of the system (libc, libz, libedit, ...) are not bundled.
ldd "$llvm/bin/clang" | awk '/=> \// { print $1, $3 }' | while read -r soname path; do
    case "$soname" in
        libLLVM*|libclang-cpp*) cp -L "$path" "$dist/toolchain/lib/$soname" ;;
    esac
done

# libclang (loaded by cshiftc to read C headers): one copy, named libclang.so
libclang="$(ls "$llvm"/lib/libclang.so "$llvm"/lib/libclang.so.* "$llvm"/lib/libclang-[0-9]*.so* 2>/dev/null | head -n 1)"
[ -n "$libclang" ] || { echo "libclang not found in $llvm/lib (install libclang-<version>-dev)"; exit 1; }
cp -L "$libclang" "$dist/toolchain/lib/libclang.so"

# clang's own headers (stddef.h, ...), found relative to the clang program
clang_version="$(ls "$llvm/lib/clang" | sort -n | tail -n 1)"
mkdir -p "$dist/toolchain/lib/clang/$clang_version"
cp -rL "$llvm/lib/clang/$clang_version/include" "$dist/toolchain/lib/clang/$clang_version/include"

# The programs find the libraries next to them, wherever the folder is extracted.
patchelf --set-rpath '$ORIGIN/../lib' "$dist/toolchain/bin/clang"
for lib in "$dist"/toolchain/lib/*.so*; do
    patchelf --set-rpath '$ORIGIN' "$lib"
done
strip --strip-unneeded "$dist/toolchain/bin/clang" 2>/dev/null || true

du -sh "$dist"
echo "$dist"
