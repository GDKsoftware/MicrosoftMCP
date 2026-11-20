# Builds a Delphi program of this repository with the command-line compiler.
#   powershell -File build/build.ps1 [-Project Tests/MicrosoftMcp.Tests.dpr] [-Platform Win64|Linux64] [-Config Debug|Release]
# Fails on compile errors and on any hint or warning in this repository's own code.
param(
  [string] $Project = 'Tests/MicrosoftMcp.Tests.dpr',
  [ValidateSet('Win64', 'Linux64')] [string] $Platform = 'Win64',
  [ValidateSet('Debug', 'Release')] [string] $Config = 'Debug'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'env.ps1')

$root = Split-Path $PSScriptRoot -Parent

# Folders with this repository's own units; every subfolder with a .pas file joins the search path.
$ownSourceRoots = @('Source', 'Tests')

# Library folders; subfolders with tests, samples, packages or UI code are left out.
$librarySourceRoots = @(
  "$root\lib\mcpserver\src",
  "$root\lib\mcpauth4d\Source",
  "$root\lib\mcpauth4d\Server",
  "$root\lib\microsoft365-4d\Source",
  "$root\lib\spring4d\Source",
  "$root\lib\taurustls\Source",
  "$env:BDS_ROOT\source\DUnitX"
)
$libraryExcludePattern = '\\(Tests?|Demos?|Samples?|Examples?|Packages|Vcl|Fmx|Design)(\\|$)'

# Folders searched for include files only, never compiled from source.
$includeOnlyRoots = @(
  "$env:BDS_ROOT\source\Indy10\Core",
  "$env:BDS_ROOT\source\Indy10\System",
  "$env:BDS_ROOT\source\Indy10\Protocols"
)

# OpenSSL 3 for Win64, copied next to the executable. The first folder holding both libraries wins.
$openSslFiles = @('libcrypto-3-x64.dll', 'libssl-3-x64.dll')
$openSslCandidates = @(
  $env:OPENSSL_DIR,
  'C:\Program Files\OpenSSL-Win64\bin',
  'C:\Program Files\Git\mingw64\bin',
  'C:\Program Files\Git\ucrt64\bin'
)

function Get-UnitFolders([string] $Path, [bool] $IsLibrary) {
  if (-not (Test-Path $Path)) {
    if ($IsLibrary) { throw "Library folder not found: $Path (run 'git submodule update --init')" }
    return @()
  }
  Get-ChildItem $Path -Recurse -Filter *.pas |
    ForEach-Object { $_.DirectoryName } |
    Sort-Object -Unique |
    Where-Object { -not $IsLibrary -or ($_ -notmatch $libraryExcludePattern) }
}

function Get-CompilerSettings([string] $TargetPlatform) {
  if ($TargetPlatform -eq 'Linux64') {
    return @{
      Compiler   = 'dcclinux64.exe'
      Namespaces = 'System;Xml;Data;Datasnap;Web;Soap;Posix'
      Arguments  = @("--syslibroot:$($env:LINUX_SDK_ROOT)", "--libpath:$($env:LINUX_SDK_LIBPATH)")
    }
  }
  return @{
    Compiler   = 'dcc64.exe'
    Namespaces = 'System;Xml;Data;Datasnap;Web;Soap;Winapi;System.Win'
    Arguments  = @()
  }
}

function Get-ConfigArguments([string] $BuildConfig) {
  if ($BuildConfig -eq 'Debug') { return @('-$O-', '-$R+', '-$Q+', '-$W+', '-$D+', '-$L+', '-DDEBUG', '-V') }
  return @('-$O+', '-$R+', '-$Q+', '-$D-', '-$L-', '-DRELEASE')
}

function Test-OwnSourceMessage([string] $Line, [string[]] $OwnFileNames) {
  if ($Line -notmatch '^(?<file>.+?\.(pas|dpr|inc))\(\d+\)\s+(Hint|Warning|Error|Fatal)') { return $false }
  $file = $Matches['file']
  if ($file -like "$root\lib\*") { return $false }
  if ($file -like "$root\*") { return $true }
  return $OwnFileNames -contains [IO.Path]::GetFileName($file)
}

function Copy-OpenSslLibraries([string] $TargetFolder) {
  foreach ($candidate in $openSslCandidates) {
    if (-not $candidate) { continue }
    $paths = $openSslFiles | ForEach-Object { Join-Path $candidate $_ }
    $allPresent = @($paths | Where-Object { Test-Path $_ }).Count -eq $openSslFiles.Count
    if ($allPresent) {
      $paths | ForEach-Object { Copy-Item $_ $TargetFolder -Force }
      Write-Host "Copied OpenSSL from $candidate"
      return
    }
  }
  Write-Warning 'OpenSSL 3 (libcrypto-3-x64.dll, libssl-3-x64.dll) not found; set OPENSSL_DIR in build/env.local.ps1'
}

$projectPath = (Resolve-Path (Join-Path $root $Project)).Path
$projectName = [IO.Path]::GetFileNameWithoutExtension($projectPath)

$ownFolders = @($ownSourceRoots | ForEach-Object { Get-UnitFolders (Join-Path $root $_) $false }) + @(Split-Path $projectPath -Parent)
$ownFileNames = @($ownSourceRoots | ForEach-Object { Join-Path $root $_ } | Where-Object { Test-Path $_ } |
  ForEach-Object { Get-ChildItem $_ -Recurse -Include *.pas, *.dpr, *.inc } | ForEach-Object { $_.Name })
$libraryFolders = @($librarySourceRoots | ForEach-Object { Get-UnitFolders $_ $true })

$platformFolders = @("$env:BDS_ROOT\lib\$Platform\release", "$env:BDS_COMMON\Dcp\$Platform", "$env:BDS_ROOT\include")
$unitPath = (@($platformFolders) + $ownFolders + $libraryFolders | Select-Object -Unique) -join ';'
$includePath = (@($unitPath) + $librarySourceRoots + $includeOnlyRoots) -join ';'

$outputFolder = "$root\bin\$Platform\$Config"
$dcuFolder = "$root\dcu\$Platform\$Config\$projectName"
New-Item -ItemType Directory -Force $outputFolder, $dcuFolder | Out-Null

$compiler = Get-CompilerSettings $Platform
$arguments = @('--no-config', '--codepage:65001', '-B', '-Q', "-NS$($compiler.Namespaces)", "-E$outputFolder", "-NU$dcuFolder",
  "-U$unitPath", "-I$includePath", "-R$unitPath", "-O$unitPath") + (Get-ConfigArguments $Config) + $compiler.Arguments + @($projectPath)

Push-Location (Split-Path $projectPath -Parent)
try {
  $output = & "$env:BDS_ROOT\bin\$($compiler.Compiler)" @arguments 2>&1 | ForEach-Object { "$_" }
  $exitCode = $LASTEXITCODE
}
finally {
  Pop-Location
}

$ownMessages = @($output | Where-Object { Test-OwnSourceMessage $_ $ownFileNames })
$output | Where-Object { ($_ -match '\b(Error|Fatal)\b') -or ($ownMessages -contains $_) } | ForEach-Object { Write-Host $_ }

if ($exitCode -ne 0) { throw "Compilation of $projectName for $Platform failed (exit $exitCode)" }
if ($ownMessages.Count -gt 0) { throw "Compilation of $projectName for $Platform produced $($ownMessages.Count) hint(s)/warning(s) in own code" }

if ($Platform -eq 'Win64') { Copy-OpenSslLibraries $outputFolder }
Write-Host "Built $projectName ($Platform $Config) -> $outputFolder"
