[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9-]+/[A-Za-z0-9_.-]+$')]
    [string]$Repository,
    [ValidatePattern('^[0-9]+$')]
    [string]$RunId,
    [string]$Destination = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist')
)
$ErrorActionPreference = 'Stop'

function Get-VeltrixGitHubToken {
    if ($env:GH_TOKEN) { return $env:GH_TOKEN }
    if ($env:GITHUB_TOKEN) { return $env:GITHUB_TOKEN }

    if (Get-Command gh -ErrorAction SilentlyContinue) {
        $cliToken = gh auth token --hostname github.com 2>$null
        if ($LASTEXITCODE -eq 0 -and $cliToken) { return $cliToken }
    }

    if (Get-Command git -ErrorAction SilentlyContinue) {
        $previousPrompt = $env:GIT_TERMINAL_PROMPT
        $previousInteractive = $env:GCM_INTERACTIVE
        try {
            $env:GIT_TERMINAL_PROMPT = '0'
            $env:GCM_INTERACTIVE = 'never'
            $owner = $Repository.Split('/')[0]
            foreach ($account in @("username=$owner", '')) {
                $inputFields = @('protocol=https', 'host=github.com')
                if ($account) { $inputFields += $account }
                $credential = (($inputFields -join "`n") + "`n`n") | git credential fill 2>$null
                $password = $credential | Where-Object { $_.StartsWith('password=') } | Select-Object -First 1
                if ($LASTEXITCODE -eq 0 -and $password) { return $password.Substring(9) }
            }
        } finally {
            $env:GIT_TERMINAL_PROMPT = $previousPrompt
            $env:GCM_INTERACTIVE = $previousInteractive
        }
    }
    throw 'Sign in through Git Credential Manager or use gh auth login.'
}

$headers = @{
    Authorization = 'Bearer ' + (Get-VeltrixGitHubToken)
    'User-Agent' = 'Veltrix-artifact-download'
    Accept = 'application/vnd.github+json'
}
$api = "https://api.github.com/repos/$Repository"
if (-not $RunId) {
    $runs = Invoke-RestMethod -Uri "$api/actions/workflows/build-ios.yml/runs?branch=main&status=success&per_page=1" -Headers $headers
    $RunId = ($runs.workflow_runs | Select-Object -First 1).id
}
if (-not $RunId) { throw 'No successful main-branch workflow run was found.' }

$artifacts = Invoke-RestMethod -Uri "$api/actions/runs/$RunId/artifacts?name=Veltrix-unsigned-ipa" -Headers $headers
$artifact = $artifacts.artifacts | Where-Object { $_.name -eq 'Veltrix-unsigned-ipa' -and -not $_.expired } |
    Select-Object -First 1
if (-not $artifact) { throw "Run $RunId has no available Veltrix-unsigned-ipa artifact." }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$stage = New-Item -ItemType Directory -Path (Join-Path ([IO.Path]::GetTempPath()) ('veltrix-' + [Guid]::NewGuid().ToString('N')))
try {
    $archivePath = Join-Path $stage.FullName 'artifact.zip'
    Invoke-WebRequest -UseBasicParsing -Uri "$api/actions/artifacts/$($artifact.id)/zip" -Headers $headers -OutFile $archivePath
    $artifactZip = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        foreach ($name in @('Veltrix.ipa', 'Veltrix.ipa.sha256')) {
            $entry = $artifactZip.GetEntry($name)
            if (-not $entry) { throw "Artifact is missing $name." }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $stage.FullName $name))
        }
    } finally {
        $artifactZip.Dispose()
    }

    $ipa = Join-Path $stage.FullName 'Veltrix.ipa'
    $manifest = Join-Path $stage.FullName 'Veltrix.ipa.sha256'
    $actual = (Get-FileHash -LiteralPath $ipa -Algorithm SHA256).Hash
    $expected = ((Get-Content -Raw -LiteralPath $manifest).Trim() -split '\s+')[0]
    if ($actual -ne $expected) { throw 'SHA-256 verification failed.' }

    $payload = [IO.Compression.ZipFile]::OpenRead($ipa)
    try {
        if (-not $payload.GetEntry('Payload/Veltrix.app/Info.plist') -or
            -not $payload.GetEntry('Payload/Veltrix.app/Veltrix')) {
            throw 'Invalid IPA payload.'
        }
    } finally {
        $payload.Dispose()
    }
    $null = New-Item -ItemType Directory -Path $Destination -Force
    Copy-Item -LiteralPath $ipa,$manifest -Destination $Destination -Force
    Get-Item -LiteralPath (Join-Path $Destination 'Veltrix.ipa')
} finally {
    foreach ($name in @('artifact.zip', 'Veltrix.ipa', 'Veltrix.ipa.sha256')) {
        $temporaryFile = Join-Path $stage.FullName $name
        if (Test-Path -LiteralPath $temporaryFile) { Remove-Item -LiteralPath $temporaryFile -Force }
    }
    Remove-Item -LiteralPath $stage.FullName
}
