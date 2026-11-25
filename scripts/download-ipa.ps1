[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Repository,
    [string]$RunId,
    [string]$Destination = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist')
)
$ErrorActionPreference = 'Stop'
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw 'Install and authenticate GitHub CLI using scripts/setup.ps1 -InstallGitHubCli.'
}
if (-not $RunId) {
    $run = gh run list --repo $Repository --workflow build-ios.yml --branch main --status success --limit 1 --json databaseId
    if ($LASTEXITCODE -ne 0) { throw 'Unable to read GitHub Actions runs.' }
    $RunId = ($run | ConvertFrom-Json | Select-Object -First 1).databaseId
}
if (-not $RunId) { throw 'No successful main-branch workflow run was found.' }

$null = New-Item -ItemType Directory -Path $Destination -Force
gh run download $RunId --repo $Repository --name Veltrix-unsigned-ipa --dir $Destination
if ($LASTEXITCODE -ne 0) { throw 'Artifact download failed.' }
$ipa = Join-Path $Destination 'Veltrix.ipa'
$manifest = Join-Path $Destination 'Veltrix.ipa.sha256'
$actual = (Get-FileHash -LiteralPath $ipa -Algorithm SHA256).Hash
$expected = ((Get-Content -Raw -LiteralPath $manifest).Trim() -split '\s+')[0]
if ($actual -ne $expected) { throw 'SHA-256 verification failed.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ipa).Path)
try {
    if (-not $zip.GetEntry('Payload/Veltrix.app/Info.plist') -or
        -not $zip.GetEntry('Payload/Veltrix.app/Veltrix')) {
        throw 'Invalid IPA payload.'
    }
} finally {
    $zip.Dispose()
}
Get-Item -LiteralPath $ipa
