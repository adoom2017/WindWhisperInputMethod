[CmdletBinding()]
param(
    [string]$InstallerPath = '',
    [switch]$AllowMachineChanges
)

$ErrorActionPreference = 'Stop'
if (-not $AllowMachineChanges) {
    throw 'This smoke test installs and uninstalls WindWhisper. Run on a disposable Windows VM with -AllowMachineChanges.'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not [Security.Principal.WindowsPrincipal]::new($identity).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this test in an elevated PowerShell on a disposable Windows VM.'
}
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if (-not $InstallerPath) {
    $InstallerPath = Join-Path $repositoryRoot 'build/windows/Installer/Release/WindWhisperInputMethod-x64-Setup.exe'
}
$InstallerPath = (Resolve-Path -LiteralPath $InstallerPath).Path
$arpKey = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\WindWhisperInputMethod'
$legacyUpgradeKey = 'HKLM:\Software\Classes\Installer\UpgradeCodes\6D23D4A9A4D6D8C4F9F2A8B0D7E0D611'
if (Test-Path $arpKey) { throw 'An NSIS WindWhisper installation already exists; use a clean VM.' }
if (Test-Path $legacyUpgradeKey) { throw 'An MSI WindWhisper installation already exists; use a clean VM.' }
$installedFolder = Join-Path $env:ProgramFiles 'WindWhisper Input Method'
if (Test-Path -LiteralPath $installedFolder) { throw 'WindWhisper files already exist; use a clean VM.' }

# fy_tsf_registration.exe is a windowless (GUI-subsystem) program: `&` neither
# waits for it nor sets $LASTEXITCODE, so start it and wait for its exit code.
function Invoke-Registrar([string]$Registrar, [string[]]$Arguments) {
    # Start-Process does not quote arguments; install paths contain spaces.
    $quoted = $Arguments | ForEach-Object { '"' + $_ + '"' }
    $process = Start-Process -FilePath $Registrar -ArgumentList $quoted -Wait -PassThru -NoNewWindow
    return $process.ExitCode
}

function Invoke-Setup([string]$FilePath, [string[]]$Arguments) {
    $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -notin @(0, 3010)) {
        throw "Installer failed with exit code $($process.ExitCode): $FilePath"
    }
}

try {
    Invoke-Setup $InstallerPath @('/S')
    $entry = Get-ItemProperty $arpKey
    $version = [Diagnostics.FileVersionInfo]::GetVersionInfo($InstallerPath).ProductVersion
    if ($entry.DisplayVersion -ne $version) { throw 'Installed EXE version mismatch.' }
    $msiKey = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$($entry.ProductCode)"
    if ((Get-ItemProperty $msiKey).SystemComponent -ne 1) { throw 'Duplicate visible MSI uninstall entry.' }
    foreach ($name in @('fy_tsf.dll', 'fy_engine.dll', 'fy_tsf_registration.exe', 'fy.dict.yaml', 'Uninstall.exe')) {
        if (-not (Test-Path -LiteralPath (Join-Path $installedFolder $name))) {
            throw "Installed file missing: $name"
        }
    }
    $status = Invoke-Registrar (Join-Path $installedFolder 'fy_tsf_registration.exe') @(
        'status', (Join-Path $installedFolder 'fy_tsf.dll'))
    if ($status -ne 0) { throw "TSF registration verification failed with exit code $status." }
    # Re-running the same EXE must repair rather than show MSI error 1638.
    Invoke-Setup $InstallerPath @('/S')
    Write-Host 'Silent installation, hidden MSI entry, and same-version repair passed.'
} finally {
    $uninstaller = Join-Path $installedFolder 'Uninstall.exe'
    if (Test-Path -LiteralPath $uninstaller) {
        # _?= prevents NSIS from spawning a detached temporary uninstaller, so
        # Start-Process -Wait observes the real uninstall operation in CI.
        Invoke-Setup $uninstaller @('/S', "_?=$installedFolder")
    }
}
if (Test-Path $arpKey) { throw 'NSIS uninstall entry was not removed.' }
if (Test-Path $msiKey) { throw 'MSI uninstall entry was not removed.' }
Write-Host 'Uninstall and uninstall-entry cleanup passed.'
