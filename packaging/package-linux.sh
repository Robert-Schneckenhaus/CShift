#!/usr/bin/env bash
# Creates the Linux release folder: cshiftc plus clang and libclang, so that the folder works after it has been
# extracted and added to PATH. The C library (libc6-dev), gcc's startup files and binutils come from the system
# ("build-essential"), like for every C toolchain.
#
#   packaging/package-linux.sh <version> <build-dir> <output-dir>
#
# LLVM_PREFIX (default /usr/lib/llvm-22) is the LLVM installation whose clang is bundled. patchelf is required.
# <build-dir> contains the released cshiftc: the self-hosted compiler (selfhost/build-release.sh).
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
cp "$root/README.md" "$root/FFI.md" "$root/BuildDesign.md" "$root/LanguageDesign.md" "$dist/"
cp "$root/packaging/README-release-linux.txt" "$dist/README.txt"
sed -i "s/@VERSION@/$version/g" "$dist/README.txt"
echo "$version" > "$dist/VERSION"

# ---- toolchain: clang ----
cp -L "$llvm/bin/clang" "$dist/toolchain/bin/clang"

# libclang (loaded by cshiftc to read C headers): one copy, named libclang.so
libclang=""
for candidate in "$llvm"/lib/libclang.so "$llvm"/lib/libclang.so.* "$llvm"/lib/libclang-[0-9]*.so*; do
    if [ -e "$candidate" ]; then
        libclang="$candidate"
        break
    fi
done
if [ -z "$libclang" ]; then
    echo "error: libclang not found in $llvm/lib (install libclang-<version>-dev). Files there:" >&2
    ls "$llvm/lib" >&2 || true
    exit 1
fi
echo "libclang: $libclang"
cp -L "$libclang" "$dist/toolchain/lib/libclang.so"

# The LLVM libraries that clang and libclang need (libLLVM, libclang-cpp), stored under the names the programs ask
# for. Libraries of the system (libc, libz, libedit, ...) are not bundled.
for program in "$llvm/bin/clang" "$libclang"; do
    echo "dependencies of $(basename "$program"):"
    ldd "$program" | sed 's/^/    /'
    while read -r soname path; do
        case "$soname" in
            libLLVM*|libclang-cpp*)
                echo "bundling $soname ($path)"
                cp -L "$path" "$dist/toolchain/lib/$soname"
                ;;
        esac
    done < <(ldd "$program" | awk '/=> \// { print $1, $3 }')
done
compgen -G "$dist/toolchain/lib/libLLVM*" > /dev/null || { echo "error: libLLVM was not found among the dependencies of clang" >&2; exit 1; }

# clang's own headers (stddef.h, ...), found relative to the clang program
resource=""
for candidate in "$llvm"/lib/clang/*; do
    [ -d "$candidate/include" ] && resource="$candidate"
done
if [ -z "$resource" ]; then
    echo "error: clang resource directory (lib/clang/<version>/include) not found in $llvm" >&2
    exit 1
fi
echo "resource directory: $resource"
clang_version="$(basename "$resource")"
mkdir -p "$dist/toolchain/lib/clang/$clang_version"
cp -rL "$resource/include" "$dist/toolchain/lib/clang/$clang_version/include"

# The programs find the libraries next to them, wherever the folder is extracted.
patchelf --set-rpath '$ORIGIN/../lib' "$dist/toolchain/bin/clang"
for lib in "$dist"/toolchain/lib/*.so*; do
    patchelf --set-rpath '$ORIGIN' "$lib"
done
strip --strip-unneeded "$dist/toolchain/bin/clang" 2>/dev/null || true

du -sh "$dist"
echo "$dist"
