#!/usr/bin/env bash
# Creates the Windows release folder: cshiftc.exe plus a toolchain (clang, lld, libclang, C headers and libraries)
# so that the folder works after it has been extracted and added to PATH.
#
#   packaging/package-windows.sh <version> <build-dir> <output-dir>
#
# <build-dir> contains the released cshiftc.exe: the self-hosted compiler (selfhost/build-release.sh). Run it in an
# MSYS2 CLANG64 shell. Result:
#   <output-dir>/cshift-<version>-windows-x64/
set -euo pipefail

version="${1:?version}"
build="${2:?build directory that contains cshiftc.exe}"
out="${3:?output directory}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
prefix="$(cygpath -u "${MINGW_PREFIX:?run this script in an MSYS2 CLANG64 shell}")"
name="cshift-$version-windows-x64"
dist="$out/$name"

rm -rf "$dist"
mkdir -p "$dist/toolchain/bin" "$dist/toolchain/lib" "$dist/toolchain/include"

# ---- the compiler and the documentation ----
cp "$build/cshiftc.exe" "$dist/"
# DLLs of the MSYS2 prefix the compiler itself needs (normally none: it is plain C code linked by clang)
ldd "$build/cshiftc.exe" | awk '/=> .*\/(clang64|mingw64|ucrt64)\/bin\// { print $3 }' | while read -r dll; do
    cp -n "$dll" "$dist/"
done
cp "$root/README.md" "$root/FFI.md" "$root/BuildDesign.md" "$root/LanguageDesign.md" "$dist/"
cp "$root/packaging/README-release.txt" "$dist/README.txt"
sed -i "s/@VERSION@/$version/g" "$dist/README.txt"
echo "$version" > "$dist/VERSION"

# ---- toolchain: programs and the DLLs they need ----
copy_program() {
    local file="$1"
    cp "$file" "$dist/toolchain/bin/"
    # ldd lists the DLLs recursively; only those of the MSYS2 prefix are copied (Windows' own DLLs exist everywhere)
    ldd "$file" | awk '/=> .*\/(clang64|mingw64|ucrt64)\/bin\// { print $3 }' | while read -r dll; do
        cp -n "$dll" "$dist/toolchain/bin/"
    done
}
for program in clang.exe ld.lld.exe libclang.dll; do
    copy_program "$prefix/bin/$program"
done

# ---- toolchain: libraries, headers of clang and of the C library ----
# The layout mirrors the MSYS2 prefix, which is where clang looks for them relative to its own location. Only the
# files of the packages that make up the MinGW-w64 C runtime are taken (C headers, import libraries, startup files).
copy_package_files() {
    pacman -Qlq "$1" | grep -v '/$' | while read -r file; do
        rel="${file#"$prefix"/}"
        case "$rel" in
            lib/cmake/*|lib/pkgconfig/*|include/c++/*|*.idl|*.dll) ;;
            lib/*|include/*)
                mkdir -p "$dist/toolchain/$(dirname "$rel")"
                cp "$file" "$dist/toolchain/$rel"
                ;;
        esac
    done
}
for package in crt headers winpthreads libunwind libc++; do
    copy_package_files "mingw-w64-clang-x86_64-$package"
done

clang_version="$(ls "$prefix/lib/clang" | sort -n | tail -n 1)"
mkdir -p "$dist/toolchain/lib/clang/$clang_version/lib/windows"
cp -r "$prefix/lib/clang/$clang_version/include" "$dist/toolchain/lib/clang/$clang_version/include"
cp "$prefix"/lib/clang/"$clang_version"/lib/windows/libclang_rt.builtins-*.a "$dist/toolchain/lib/clang/$clang_version/lib/windows/"

du -sh "$dist"
echo "$dist"
