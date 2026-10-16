[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$toolRoot = Join-Path $repositoryRoot 'build/tools/nsis'
$compiler = Join-Path $toolRoot 'nsis-3.12/Bin/makensis.exe'
if (Test-Path -LiteralPath $compiler -PathType Leaf) {
    Write-Output $compiler
    return
}

# Portable, pinned compiler; does not install software into the build machine.
$downloadUrl = 'https://downloads.sourceforge.net/project/nsis/NSIS%203/3.12/nsis-3.12.zip'
$expectedHash = '56581f90db321581c5381193d796fffcf2d24b2f8fed2160a6c6a3baa67f2c4f'
New-Item -ItemType Directory -Path $toolRoot -Force | Out-Null
$archivePath = Join-Path $toolRoot 'nsis-3.12-portable.zip'
if (-not (Test-Path -LiteralPath $archivePath) -or
    (Get-FileHash -LiteralPath $archivePath).Hash.ToLowerInvariant() -ne $expectedHash) {
    Invoke-WebRequest $downloadUrl -OutFile $archivePath
    if ((Get-FileHash -LiteralPath $archivePath).Hash.ToLowerInvariant() -ne $expectedHash) {
        # Some SourceForge mirrors return a download landing page (HTTP 200).
        # Follow only its official, version-specific download URL, then verify.
        $page = Get-Content -LiteralPath $archivePath -Raw
        $match = [regex]::Match($page, 'content="5; url=([^"]+)"')
        $redirectUrl = [Net.WebUtility]::HtmlDecode($match.Groups[1].Value)
        if (-not $redirectUrl.StartsWith($downloadUrl + '?', [StringComparison]::Ordinal)) {
            throw 'NSIS download did not return the pinned archive.'
        }
        Invoke-WebRequest $redirectUrl -OutFile $archivePath
    }
}
if ((Get-FileHash -LiteralPath $archivePath).Hash.ToLowerInvariant() -ne $expectedHash) {
    throw 'NSIS archive SHA-256 mismatch.'
}
Expand-Archive -LiteralPath $archivePath -DestinationPath $toolRoot -Force
if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
    throw "NSIS compiler missing after extraction: $compiler"
}
Write-Output $compiler
