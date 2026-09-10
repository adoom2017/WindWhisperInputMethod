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
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
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
    # Drain both pipes concurrently so verbose compiler output cannot deadlock.
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $output = $stdout.GetAwaiter().GetResult()
    $errors = $stderr.GetAwaiter().GetResult()
    if ($output) { Write-Host $output }
    if ($errors) { Write-Host $errors }
    if ($process.ExitCode -ne 0) {
        throw "$FilePath failed with exit code $($process.ExitCode)"
    }
}

function Assert-WindowlessExecutable {
    param([Parameter(Mandatory)][string]$Path)

    $stream = [IO.File]::OpenRead($Path)
    $reader = [IO.BinaryReader]::new($stream)
    try {
        if ($reader.ReadUInt16() -ne 0x5A4D) { throw "Invalid executable: $Path" }
        $stream.Position = 0x3C
        $peOffset = $reader.ReadInt32()
        if ($peOffset -lt 0 -or $peOffset + 94 -gt $stream.Length) {
            throw "Invalid PE header: $Path"
        }
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x4550) { throw "Invalid PE signature: $Path" }
        # Subsystem has the same offset in PE32 and PE32+ optional headers.
        $stream.Position = $peOffset + 24 + 68
        if ($reader.ReadUInt16() -ne 2) {
            throw "Registration helper must use Windows GUI subsystem. Rebuild without -SkipBuild: $Path"
        }
    }
    finally { $reader.Dispose() }
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
Assert-WindowlessExecutable -Path (Join-Path $sourceDirectory 'fy_tsf_registration.exe')
$outputPath = Join-Path $outputDirectory 'WindWhisperInputMethod-x64.msi'
Invoke-NativeChecked -FilePath $wix -ArgumentList @(
    'build', (Join-Path $PSScriptRoot 'Product.wxs'),
    '-arch', 'x64', '-d', "SourceDir=$sourceDirectory",
    '-d', "RepositoryRoot=$repositoryRoot", '-o', $outputPath
)
# Keep development refresh scripts out of the release deliverables, including
# copies left by older runs. Their source copies remain in Installer/Windows.
foreach ($name in @('Refresh-Tsf-OneClick.cmd', 'Refresh-Tsf.ps1')) {
    $legacyCopy = Join-Path $outputDirectory $name
    if (Test-Path -LiteralPath $legacyCopy -PathType Leaf) {
        Remove-Item -LiteralPath $legacyCopy
    }
}
Write-Host $outputPath
