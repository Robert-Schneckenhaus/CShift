# Builds the CShift compiler (cshiftc) on Windows using MSYS2's CLANG64 toolchain.
#
#   .\build.ps1                 build into .\build
#   .\build.ps1 -Test           build and run the test suite
#   .\build.ps1 -Msys2 D:\msys64
#
# One-time setup (see README.md): install MSYS2 and, in an MSYS2 shell, run
#   pacman -S mingw-w64-clang-x86_64-{clang,llvm,cmake,ninja}

param(
    [string]$Msys2 = $(if ($env:MSYS2_ROOT) { $env:MSYS2_ROOT } else { "C:\msys64" }),
    [switch]$Test,
    [string]$Config = "Release"
)

$ErrorActionPreference = "Stop"
$bash = Join-Path $Msys2 "usr\bin\bash.exe"
if (-not (Test-Path $bash)) {
    Write-Error "MSYS2 not found at '$Msys2'. Install it from https://www.msys2.org or pass -Msys2 <path>."
}

$root = $PSScriptRoot.Replace('\', '/')
$env:MSYSTEM = "CLANG64"
$env:CHERE_INVOKING = "1"

$script = "cd '$root' && cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=$Config && cmake --build build"
if ($Test) { $script += " && bash tests/run_tests.sh" }

& $bash -lc $script
exit $LASTEXITCODE
