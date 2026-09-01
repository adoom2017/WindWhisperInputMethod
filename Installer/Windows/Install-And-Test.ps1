[CmdletBinding()]
param(
    [string]$MsiPath = '',
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if ([string]::IsNullOrWhiteSpace($MsiPath)) {
    $MsiPath = Join-Path $repositoryRoot `
        'build\windows\Installer\Release\WindWhisperInputMethod-x64.msi'
}
$MsiPath = [IO.Path]::GetFullPath($MsiPath)

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
        '-MsiPath', ('"{0}"' -f $MsiPath)
    )
    if ($Uninstall) {
        $arguments += '-Uninstall'
    }
    $elevated = Start-Process -FilePath $shell -Verb RunAs `
        -ArgumentList $arguments -Wait -PassThru
    exit $elevated.ExitCode
}

if (-not (Test-Path -LiteralPath $MsiPath -PathType Leaf)) {
    throw "MSI not found: $MsiPath"
}

$logDirectory = Join-Path $repositoryRoot 'build\windows\Installer'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$operation = if ($Uninstall) { 'uninstall' } else { 'install' }
$logPath = Join-Path $logDirectory "$operation.log"
$msiexecArguments = if ($Uninstall) {
    @('/x', ('"{0}"' -f $MsiPath), '/passive', '/norestart',
      '/L*V', ('"{0}"' -f $logPath))
} else {
    @('/i', ('"{0}"' -f $MsiPath), '/passive', '/norestart',
      '/L*V', ('"{0}"' -f $logPath))
}

$installer = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" `
    -ArgumentList $msiexecArguments -Wait -PassThru
if ($installer.ExitCode -notin @(0, 3010)) {
    throw "Windows Installer failed with exit code $($installer.ExitCode). Log: $logPath"
}

if ($Uninstall) {
    Write-Host "Uninstall completed. User data was preserved. Log: $logPath"
    exit 0
}

$installFolder = Join-Path $env:ProgramFiles 'WindWhisper Input Method'
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
Write-Host 'No sign-out is required. Refresh the language bar with:'
Write-Host "  pwsh -NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\Refresh-Tsf.ps1`""
Write-Host 'Close and reopen the target editor/browser so it reloads the new DLL.'
Write-Host "Log: $logPath"
if ($installer.ExitCode -eq 3010) {
    Write-Host 'Windows Installer requested a restart.'
}
