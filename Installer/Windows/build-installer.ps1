[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',
    [switch]$SkipBuild,
    [switch]$Preview
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$compiler = & (Join-Path $PSScriptRoot 'Install-Nsis.ps1')
. (Join-Path $PSScriptRoot 'build-msi.ps1') -Configuration $Configuration -SkipBuild:$SkipBuild

$outputDirectory = Join-Path $repositoryRoot "build/windows/Installer/$Configuration"
$msiPath = Join-Path $outputDirectory 'WindWhisperInputMethod-x64.msi'
$installer = New-Object -ComObject WindowsInstaller.Installer
$database = $installer.OpenDatabase($msiPath, 0)
function Get-MsiProperty([string]$Name) {
    $view = $database.OpenView("SELECT ``Value`` FROM ``Property`` WHERE ``Property`` = '$Name'")
    try {
        [void]$view.Execute()
        return $view.Fetch().StringData(1)
    } finally { [void]$view.Close() }
}
$version = Get-MsiProperty 'ProductVersion'
$productCode = Get-MsiProperty 'ProductCode'
if ($version -notmatch '^\d+\.\d+\.\d+$' -or
    $productCode -notmatch '^\{[0-9A-Fa-f-]{36}\}$') {
    throw 'Invalid MSI version or product code.'
}
$fileView = $database.OpenView('SELECT `FileSize` FROM `File`')
$sizeBytes = 0L
try {
    $fileView.Execute()
    while ($record = $fileView.Fetch()) { $sizeBytes += $record.IntegerData(1) }
} finally { $fileView.Close() }
$sizeKB = [int][Math]::Ceiling($sizeBytes / 1024) + 512
$artPath = Join-Path $outputDirectory 'wizard.bmp'
& (Join-Path $repositoryRoot 'Scripts/generate-windows-installer-art.ps1') -OutputPath $artPath
if ($Preview) {
    $outputDirectory = Join-Path $repositoryRoot 'build/windows/Installer/Preview'
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
$outputPath = Join-Path $outputDirectory $(if ($Preview) {
    'WindWhisperInputMethod-Preview.exe'
} else { 'WindWhisperInputMethod-x64-Setup.exe' })
$arguments = @(
    '/V3', '/WX', '/INPUTCHARSET', 'UTF8',
    "/DPRODUCT_VERSION=$version", "/DPRODUCT_CODE=$productCode",
    "/DPAYLOAD_MSI=$msiPath", "/DOUTPUT_FILE=$outputPath",
    "/DICON_FILE=$(Join-Path $repositoryRoot 'Resources/WindWhisperProfile.ico')",
    "/DWIZARD_BITMAP=$artPath", "/DINSTALL_SIZE_KB=$sizeKB"
)
if ($Preview) { $arguments += '/DSETUP_PREVIEW' }
$arguments += Join-Path $PSScriptRoot 'WindWhisper.nsi'
# Reuse the hidden-process helper loaded by build-msi.ps1.
Invoke-NativeChecked -FilePath $compiler -ArgumentList $arguments
Assert-WindowlessExecutable -Path $outputPath
$fileVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($outputPath)
if ($fileVersion.ProductVersion -ne $version) { throw 'EXE/MSI version mismatch.' }
$hash = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  $([IO.Path]::GetFileName($outputPath))" |
    Set-Content -LiteralPath "$outputPath.sha256" -Encoding utf8NoBOM
Write-Host $outputPath
