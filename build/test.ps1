# Builds Tests/MicrosoftMcp.Tests.dpr and runs it; exits non-zero when the build or a test fails.
#   powershell -File build/test.ps1 [-Platform Win64|Linux64]
# Linux64 tests run inside WSL (distro from WSL_DISTRO, see env.ps1) against the system libcrypto.so.3.
# With MICROSOFTMCP_TEST_PG set the FireDAC mailbox store tests run against that PostgreSQL database (see build/docker-compose.yml):
# on Win64 libpq.dll comes from PG_BIN_DIR, on Linux64 the system libpq.so.5 of the WSL distro is used.
param([ValidateSet('Win64', 'Linux64')] [string] $Platform = 'Win64')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'env.ps1')

$root = Split-Path $PSScriptRoot -Parent
$testProject = 'Tests/MicrosoftMcp.Tests.dpr'
$testProgram = [IO.Path]::GetFileNameWithoutExtension($testProject)
$outputFolder = "$root\bin\$Platform\Debug"

# Environment variables that WSL passes on to the Linux64 tests.
$sharedVariables = @('MICROSOFTMCP_TEST_PG', 'MICROSOFTMCP_PG_VENDORLIB')

try {
  & (Join-Path $PSScriptRoot 'build.ps1') -Project $testProject -Platform $Platform -Config Debug
}
catch {
  Write-Host $_.Exception.Message
  exit 2
}

if ($env:MICROSOFTMCP_TEST_PG) {
  Write-Host 'MICROSOFTMCP_TEST_PG is set: the FireDAC mailbox store tests use PostgreSQL'
}

if ($Platform -eq 'Linux64') {
  $env:WSLENV = (@($env:WSLENV) + $sharedVariables | Where-Object { $_ }) -join ':'
  $windowsPath = (Join-Path $outputFolder $testProgram) -replace '\\', '/'
  $linuxPath = wsl -d $env:WSL_DISTRO -- wslpath -a "$windowsPath"
  wsl -d $env:WSL_DISTRO -- "$linuxPath" '-exit:continue'
}
else {
  if ($env:PG_BIN_DIR) { $env:PATH = "$($env:PG_BIN_DIR);$($env:PATH)" }
  & (Join-Path $outputFolder "$testProgram.exe") '-exit:continue' "-xml:$outputFolder\test-results.xml"
}

$testExitCode = $LASTEXITCODE
if ($testExitCode -ne 0) {
  Write-Host "Tests failed on $Platform (exit $testExitCode)"
  exit $testExitCode
}
Write-Host "All tests passed on $Platform"
