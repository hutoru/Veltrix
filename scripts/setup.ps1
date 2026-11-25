[CmdletBinding()]
param(
    [string]$Repository,
    [switch]$InstallGitHubCli
)
$ErrorActionPreference = 'Stop'
$veltrixRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $veltrixRoot
try {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'Install Git for Windows first, then reopen PowerShell.'
    }

    if ($InstallGitHubCli -and -not (Get-Command gh -ErrorAction SilentlyContinue)) {
        winget install --id GitHub.cli --exact --source winget
        if ($LASTEXITCODE -ne 0) { throw 'GitHub CLI installation failed.' }
        $veltrixCli = Join-Path $env:ProgramFiles 'GitHub CLI'
        if (Test-Path -LiteralPath $veltrixCli) { $env:Path += ";$veltrixCli" }
    }

    if (-not (Test-Path -LiteralPath '.git')) {
        git init -b main
        if ($LASTEXITCODE -ne 0) { throw 'Unable to initialize Git.' }
    }

    if ($Repository) {
        $currentRemote = git remote get-url origin 2>$null
        if ($LASTEXITCODE -ne 0) {
            git remote add origin $Repository
            if ($LASTEXITCODE -ne 0) { throw 'Unable to add origin.' }
        } elseif ($currentRemote -ne $Repository) {
            throw "Origin already points to $currentRemote. Check the repository before changing it."
        }
    }

    if (Get-Command gh -ErrorAction SilentlyContinue) {
        gh auth status --hostname github.com
        if ($LASTEXITCODE -ne 0) { Write-Host 'Run gh auth login to authorize workflow monitoring.' }
    }
} finally {
    Pop-Location
}
