# Downloads the official GLFW binaries for Windows and copies the static library to demo-opengl\lib\libglfw3.a.
#
#   .\get-glfw.ps1
#
# Alternatively, in MSYS2 CLANG64: pacman -S mingw-w64-clang-x86_64-glfw (then lib\ isn't needed; the program uses
# glfw3.dll from C:\msys64\clang64\bin at run time).
param(
    [string]$Version = "3.4",
    [string]$Output = (Join-Path $PSScriptRoot "lib")
)

$ErrorActionPreference = "Stop"
$name = "glfw-$Version.bin.WIN64"
$work = Join-Path ([System.IO.Path]::GetTempPath()) "cshift-glfw"
if (Test-Path $work) { Remove-Item -Recurse -Force $work }
New-Item -ItemType Directory $work | Out-Null

$zip = Join-Path $work "$name.zip"
Invoke-WebRequest "https://github.com/glfw/glfw/releases/download/$Version/$name.zip" -OutFile $zip
Expand-Archive $zip -DestinationPath $work

New-Item -ItemType Directory -Force $Output | Out-Null
Copy-Item -Force (Join-Path $work "$name\lib-mingw-w64\libglfw3.a") $Output
Write-Host "Copied libglfw3.a to $Output"
