[CmdletBinding()]
param(
    [string]$InstallRoot = '',
    [switch]$RestartExplorer
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $machineInstall = Join-Path $env:ProgramFiles 'WindWhisper Input Method'
    $userInstall = Join-Path $env:LOCALAPPDATA 'Programs\WindWhisper\InputMethod'
    $InstallRoot = if (Test-Path -LiteralPath $machineInstall) {
        $machineInstall
    } elseif (Test-Path -LiteralPath $userInstall) {
        $userInstall
    } else {
        $machineInstall
    }
}
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$registrar = Join-Path $InstallRoot 'fy_tsf_registration.exe'
$dll = Join-Path $InstallRoot 'fy_tsf.dll'
if (-not (Test-Path -LiteralPath $registrar -PathType Leaf) -or
    -not (Test-Path -LiteralPath $dll -PathType Leaf)) {
    throw "WindWhisper installation is incomplete: $InstallRoot"
}

# A TSF profile is cached by ctfmon/TextInputHost.  Restarting ctfmon is
# enough to refresh the language bar and does not require signing out.
$ctfmonPath = Join-Path $env:SystemRoot 'System32\ctfmon.exe'
Get-Process -Name ctfmon -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Process -FilePath $ctfmonPath -WindowStyle Hidden

# Windows 11's modern language indicator is hosted by TextInputHost rather
# than ctfmon.  It keeps TSF language-bar items in-process, so restart it as
# well; Windows will respawn it automatically when the indicator is needed.
Get-Process -Name TextInputHost -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

& $registrar activate
if ($LASTEXITCODE -ne 0) {
    # ActivateProfile can return E_FAIL when the profile is already enabled or
    # when TextInputHost owns the current session.  A healthy registration is
    # sufficient here because the user can select WindWhisper from the input
    # indicator immediately after the host restarts.
    & $registrar status $dll
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to activate WindWhisper profile (exit code $LASTEXITCODE)."
    }
}

if ($RestartExplorer) {
    # Optional: this refreshes the taskbar language indicator as well.  Open
    # Explorer windows are restored by Windows, but shell menus briefly close.
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe')
}

Write-Host 'TSF refreshed without signing out.'
Write-Host 'Close and reopen the target editor/browser if it had already loaded the old DLL.'
