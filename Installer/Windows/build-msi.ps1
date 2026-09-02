[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$sourceDirectory = Join-Path $repositoryRoot "build\windows\Platform\Windows\$Configuration"
$outputDirectory = Join-Path $repositoryRoot "build\windows\Installer\$Configuration"
$wix = Join-Path $repositoryRoot 'build\tools\wix\wix.exe'

function Invoke-NativeChecked {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        [Parameter(Mandatory)]
        [string[]]$ArgumentList
    )

    # Some automation hosts provide both Path and PATH in the native process
    # environment. MSBuild treats those as duplicate keys when it starts cl.exe.
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.WorkingDirectory = $repositoryRoot
    $startInfo.UseShellExecute = $false
    foreach ($argument in $ArgumentList) {
        $startInfo.ArgumentList.Add($argument)
    }
    $startInfo.Environment.Clear()
    $seenEnvironmentNames = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    Get-ChildItem Env: | ForEach-Object {
        if ($seenEnvironmentNames.Add($_.Name)) {
            $startInfo.Environment[$_.Name] = $_.Value
        }
    }

    $process = [Diagnostics.Process]::Start($startInfo)
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        throw "$FilePath failed with exit code $($process.ExitCode)"
    }
}

if (-not $SkipBuild) {
    $cmake = (Get-Command cmake -ErrorAction Stop).Source
    Invoke-NativeChecked -FilePath $cmake -ArgumentList @(
        '--build', 'build/windows', '--config', $Configuration
    )
}

$dictionarySource = Join-Path $repositoryRoot 'Resources\fy.dict.yaml'
$dictionaryTarget = Join-Path $sourceDirectory 'fy.dict.yaml'
if (-not (Test-Path -LiteralPath $dictionaryTarget -PathType Leaf) -or
    (Get-Item -LiteralPath $dictionarySource).LastWriteTimeUtc -gt
    (Get-Item -LiteralPath $dictionaryTarget).LastWriteTimeUtc) {
    Copy-Item -LiteralPath $dictionarySource -Destination $dictionaryTarget -Force
}

foreach ($path in @(
    $wix,
    (Join-Path $sourceDirectory 'fy_engine.dll'),
    (Join-Path $sourceDirectory 'fy_tsf.dll'),
    (Join-Path $sourceDirectory 'fy_tsf_registration.exe'),
    $dictionaryTarget
)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required build input is missing: $path"
    }
}

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$outputPath = Join-Path $outputDirectory 'WindWhisperInputMethod-x64.msi'
& $wix build (Join-Path $PSScriptRoot 'Product.wxs') `
    -arch x64 `
    -d "SourceDir=$sourceDirectory" `
    -d "RepositoryRoot=$repositoryRoot" `
    -o $outputPath
if ($LASTEXITCODE -ne 0) {
    throw "WiX failed with exit code $LASTEXITCODE"
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Refresh-Tsf-OneClick.cmd') `
    -Destination (Join-Path $outputDirectory 'Refresh-Tsf-OneClick.cmd') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Refresh-Tsf.ps1') `
    -Destination (Join-Path $outputDirectory 'Refresh-Tsf.ps1') -Force
Write-Host $outputPath
