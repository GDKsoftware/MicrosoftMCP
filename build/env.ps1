# Toolchain settings shared by build.ps1 and test.ps1.
# Override any value in build/env.local.ps1 (ignored by git); see env.local.example.ps1.

$localSettings = Join-Path $PSScriptRoot 'env.local.ps1'
if (Test-Path $localSettings) { . $localSettings }

function Set-DefaultVariable([string] $Name, [scriptblock] $Value) {
  if (-not [Environment]::GetEnvironmentVariable($Name, 'Process')) {
    [Environment]::SetEnvironmentVariable($Name, (& $Value), 'Process')
  }
}

function Get-NewestGccVersion([string] $SdkRoot) {
  $gccRoot = Join-Path $SdkRoot 'usr\lib\gcc\x86_64-linux-gnu'
  if (-not (Test-Path $gccRoot)) { return '' }
  Get-ChildItem $gccRoot -Directory |
    Sort-Object { [int]($_.Name -replace '\D.*$', '') } |
    Select-Object -Last 1 -ExpandProperty Name
}

Set-DefaultVariable 'BDS_ROOT'       { 'C:\Program Files (x86)\Embarcadero\Studio\37.0' }
Set-DefaultVariable 'BDS_COMMON'     { 'C:\Users\Public\Documents\Embarcadero\Studio\37.0' }
Set-DefaultVariable 'LINUX_SDK_ROOT' { Join-Path $env:USERPROFILE 'Documents\Embarcadero\Studio\SDKs\ubuntu26.04.sdk' }
Set-DefaultVariable 'LINUX_GCC_VERSION' { Get-NewestGccVersion $env:LINUX_SDK_ROOT }
Set-DefaultVariable 'LINUX_SDK_LIBPATH' {
  $libraryFolders = @(
    "usr\lib\gcc\x86_64-linux-gnu\$($env:LINUX_GCC_VERSION)",
    'usr\lib\x86_64-linux-gnu',
    'lib\x86_64-linux-gnu',
    'lib64'
  ) | ForEach-Object { Join-Path $env:LINUX_SDK_ROOT $_ }
  $libraryFolders -join ';'
}
Set-DefaultVariable 'WSL_DISTRO' { 'Ubuntu' }

# Folder with libpq.dll and the DLLs it depends on, put on the PATH of the Win64 tests for the FireDAC PostgreSQL driver.
Set-DefaultVariable 'PG_BIN_DIR' {
  Get-ChildItem 'C:\Program Files\PostgreSQL' -Directory -ErrorAction SilentlyContinue |
    Sort-Object { [int]($_.Name -replace '\D.*$', '') } |
    ForEach-Object { Join-Path $_.FullName 'bin' } |
    Where-Object { Test-Path (Join-Path $_ 'libpq.dll') } |
    Select-Object -Last 1
}
