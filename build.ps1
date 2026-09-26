# Builds the CShift compiler (cshiftc) on Windows using MSYS2's CLANG64 toolchain.
#
#   .\build.ps1                 build build\stage2\cshiftc.exe (stages 1 and 2 of the bootstrap)
#   .\build.ps1 -Test           and run the tests
#   .\build.ps1 -Msys2 D:\msys64
#
# Stage 0 is the release named in selfhost\stage0.txt: downloaded with the GitHub CLI ('gh auth login' once), or the
# compiler that $env:CSHIFT_STAGE0 names (see selfhost/fetch-stage0.sh).
#
# One-time setup (see README.md): install MSYS2 and, in an MSYS2 shell, run
#   pacman -S mingw-w64-clang-x86_64-{clang,lld}

param(
    [string]$Msys2 = $(if ($env:MSYS2_ROOT) { $env:MSYS2_ROOT } else { "C:\msys64" }),
    [switch]$Test
)

$ErrorActionPreference = "Stop"
$bash = Join-Path $Msys2 "usr\bin\bash.exe"
if (-not (Test-Path $bash)) {
    Write-Error "MSYS2 not found at '$Msys2'. Install it from https://www.msys2.org or pass -Msys2 <path>."
}

$root = $PSScriptRoot.Replace('\', '/')
$env:MSYSTEM = "CLANG64"
$env:CHERE_INVOKING = "1"
$env:MSYS2_PATH_TYPE = "inherit" # the Windows PATH, so that gh.exe is found

$script = "cd '$root' && stage0=`$(bash selfhost/fetch-stage0.sh) && bash selfhost/build-release.sh `"`$stage0`" dev build/stage2"
if ($Test) { $script += " && bash tests/run_tests.sh build/stage2/cshiftc.exe" }

& $bash -lc $script
exit $LASTEXITCODE
