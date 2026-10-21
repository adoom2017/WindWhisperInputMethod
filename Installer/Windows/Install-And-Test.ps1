[CmdletBinding()]
param(
    [Alias('MsiPath')][string]$InstallerPath = '',
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if ([string]::IsNullOrWhiteSpace($InstallerPath)) {
    $InstallerPath = Join-Path $repositoryRoot `
        'build\windows\Installer\Release\WindWhisperInputMethod-x64-Setup.exe'
}
$InstallerPath = [IO.Path]::GetFullPath($InstallerPath)

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isAdministrator = $principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdministrator) {
    $shell = (Get-Process -Id $PID).Path
    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $PSCommandPath),
        '-InstallerPath', ('"{0}"' -f $InstallerPath)
    )
    if ($Uninstall) {
        $arguments += '-Uninstall'
    }
    $elevated = Start-Process -FilePath $shell -Verb RunAs `
        -ArgumentList $arguments -Wait -PassThru
    exit $elevated.ExitCode
}

$installFolder = Join-Path $env:ProgramFiles 'WindWhisper Input Method'
$operation = if ($Uninstall) { 'uninstall' } else { 'install' }
$logPath = Join-Path $env:ProgramData "WindWhisper\Installer\$operation.log"
if ([IO.Path]::GetExtension($InstallerPath) -eq '.msi') {
    # Retain explicit -MsiPath compatibility for legacy installer diagnosis.
    $msiexecArguments = @($(if ($Uninstall) { '/x' } else { '/i' }),
        ('"{0}"' -f $InstallerPath), '/passive', '/norestart',
        '/L*V', ('"{0}"' -f $logPath))
    New-Item -ItemType Directory -Path (Split-Path -Parent $logPath) -Force | Out-Null
    $installer = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" `
        -ArgumentList $msiexecArguments -Wait -PassThru
} else {
    $executable = if ($Uninstall) { Join-Path $installFolder 'Uninstall.exe' } else { $InstallerPath }
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        throw "Installer not found: $executable"
    }
    $installer = Start-Process -FilePath $executable -Wait -PassThru
}
if ($installer.ExitCode -notin @(0, 3010)) {
    throw "Installer failed with exit code $($installer.ExitCode). Log: $logPath"
}

if ($Uninstall) {
    Write-Host "Uninstall completed. User data was preserved. Log: $logPath"
    exit 0
}

$registrar = Join-Path $installFolder 'fy_tsf_registration.exe'
$tsfDll = Join-Path $installFolder 'fy_tsf.dll'
foreach ($path in @($registrar, $tsfDll, (Join-Path $installFolder 'fy_engine.dll'))) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Installed file is missing: $path"
    }
}

& $registrar status $tsfDll
if ($LASTEXITCODE -ne 0) {
    throw "TSF post-install verification failed with exit code $LASTEXITCODE. Log: $logPath"
}

Write-Host 'Install and TSF registration verification completed successfully.'
Write-Host 'Refresh the language bar with (or sign out and back in):'
Write-Host "  pwsh -NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\Refresh-Tsf.ps1`""
Write-Host 'Close and reopen the target editor/browser so it reloads the new DLL.'
Write-Host "Log: $logPath"
if ($installer.ExitCode -eq 3010) {
    Write-Host 'Windows Installer requested a restart.'
}
