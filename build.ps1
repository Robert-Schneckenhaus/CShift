# Builds the CShift compiler (cshiftc) on Windows using MSYS2's CLANG64 toolchain.
#
#   .\build.ps1                 build into .\build
#   .\build.ps1 -Test           also build stages 1 and 2 (build\stage2\cshiftc.exe, the self-hosted compiler) and run the tests
#   .\build.ps1 -Msys2 D:\msys64
#   .\build.ps1 -Dynamic        link LLVM as a DLL (smaller exe, but cshiftc.exe then only starts when
#                               C:\msys64\clang64\bin is in PATH)
#
# By default cshiftc.exe is linked statically, so it runs from any shell. Compiling a program still needs
# 'clang' in PATH for the final link step.
#
# One-time setup (see README.md): install MSYS2 and, in an MSYS2 shell, run
#   pacman -S mingw-w64-clang-x86_64-{clang,llvm,cmake,ninja}

param(
    [string]$Msys2 = $(if ($env:MSYS2_ROOT) { $env:MSYS2_ROOT } else { "C:\msys64" }),
    [switch]$Test,
    [string]$Config = "Release",
    [switch]$Dynamic
)

$ErrorActionPreference = "Stop"
$bash = Join-Path $Msys2 "usr\bin\bash.exe"
if (-not (Test-Path $bash)) {
    Write-Error "MSYS2 not found at '$Msys2'. Install it from https://www.msys2.org or pass -Msys2 <path>."
}

$root = $PSScriptRoot.Replace('\', '/')
$env:MSYSTEM = "CLANG64"
$env:CHERE_INVOKING = "1"

$static = if ($Dynamic) { "OFF" } else { "ON" }
$script = "cd '$root' && cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=$Config -DCSHIFT_STATIC=$static && cmake --build build"
if ($Test) { $script += " && bash selfhost/build-release.sh build/cshiftc.exe dev build/stage2 && bash tests/run_tests.sh build/stage2/cshiftc.exe" }

& $bash -lc $script
exit $LASTEXITCODE
