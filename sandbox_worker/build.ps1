$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Tag = "windows-x86_64"
$OutDir = Join-Path $Root "sandbox_worker\bin\$Tag"
$Src = Join-Path $Root "sandbox_worker\src\main.cpp"
$TargetTriple = (& g++ -dumpmachine | Out-String).Trim()
if ($LASTEXITCODE -ne 0) {
    throw "g++ was not found or could not report its target triple."
}
if ($TargetTriple -notmatch "x86_64") {
    throw "windows-x86_64 worker requires an x86_64 g++ target (detected '$TargetTriple')."
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
& g++ -std=c++17 -O2 -Wall -Wextra -static -o (Join-Path $OutDir "sandbox_runner.exe") $Src -lws2_32 -ladvapi32 -luserenv -lole32
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Output "Built $OutDir\sandbox_runner.exe"
