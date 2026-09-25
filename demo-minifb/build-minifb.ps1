# Builds libminifb.a for the demo with clang (MSYS2 CLANG64: cmake, ninja, clang and llvm-ar must be in PATH).
#
#   .\build-minifb.ps1 -Source C:\path\to\minifb
#
# -Source is a checkout of https://github.com/emoon/minifb (the headers in include/ come from there).
# The C++ wrapper (MiniFB_cpp.cpp) is left out and replaced by an empty C function, so that the library does not
# depend on a C++ runtime. The result is demo-minifb\libminifb.a.
param(
    [Parameter(Mandatory = $true)][string]$Source,
    [string]$Output = (Join-Path $PSScriptRoot "libminifb.a")
)

$ErrorActionPreference = "Stop"
$work = Join-Path ([System.IO.Path]::GetTempPath()) "cshift-minifb"
if (Test-Path $work) { Remove-Item -Recurse -Force $work }
New-Item -ItemType Directory $work | Out-Null

cmake -S $Source -B "$work\build" -G Ninja -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ `
    -DCMAKE_BUILD_TYPE=Release -DMINIFB_BUILD_EXAMPLES=OFF -DMINIFB_BUILD_VERSION_INFO=OFF
if ($LASTEXITCODE -ne 0) { throw "cmake configure failed" }
cmake --build "$work\build"
if ($LASTEXITCODE -ne 0) { throw "cmake build failed" }

$lib = "$work\build\libminifb.a"
llvm-ar d $lib MiniFB_cpp.cpp.obj
"struct mfb_window;`nvoid release_cpp_stub(struct mfb_window* window) { (void)window; }`n" | Set-Content -Encoding ascii "$work\stub.c"
clang -c -O2 "$work\stub.c" -o "$work\stub.obj"
if ($LASTEXITCODE -ne 0) { throw "compiling the stub failed" }
llvm-ar q $lib "$work\stub.obj"
Copy-Item -Force $lib $Output
Write-Host "Built $Output"
