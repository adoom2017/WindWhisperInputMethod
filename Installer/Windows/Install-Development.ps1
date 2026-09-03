[CmdletBinding()]
param(
    [ValidateSet('Install', 'Uninstall', 'Status')]
    [string]$Action = 'Install',
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',
    [switch]$Elevated,
    [string]$LogPath
)

$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-ElevatedSelf {
    if (-not $LogPath) {
        $LogPath = Join-Path $PSScriptRoot '..\..\build\windows\install-development.log'
    }
    $argumentList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $PSCommandPath),
        '-Action', $Action,
        '-Configuration', $Configuration,
        '-Elevated',
        '-LogPath', ('"{0}"' -f [IO.Path]::GetFullPath($LogPath))
    )
    $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs `
        -ArgumentList $argumentList -Wait -PassThru
    exit $process.ExitCode
}

if (-not $Elevated -or -not (Test-IsAdministrator)) {
    Invoke-ElevatedSelf
}

if ($LogPath) {
    $resolvedLogPath = [IO.Path]::GetFullPath($LogPath)
    New-Item -ItemType Directory -Path (Split-Path -Parent $resolvedLogPath) -Force | Out-Null
    Start-Transcript -LiteralPath $resolvedLogPath -Force | Out-Null
}

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$sourceDirectory = Join-Path $repositoryRoot "build\windows\Platform\Windows\$Configuration"
$installRoot = Join-Path $env:LOCALAPPDATA 'Programs\WindWhisper\InputMethod'
$installParent = Split-Path -Parent $installRoot
$registrationName = 'fy_tsf_registration.exe'
$requiredFiles = @('fy_engine.dll', 'fy_tsf.dll', $registrationName)

function Assert-SafeInstallPath {
    $resolvedParent = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Programs\WindWhisper'))
    $resolvedTarget = [IO.Path]::GetFullPath($installRoot)
    if (-not $resolvedTarget.StartsWith($resolvedParent + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe install path: $resolvedTarget"
    }
}

function Invoke-Registrar {
    param(
        [Parameter(Mandatory)] [string]$Command,
        [string]$DllPath,
        [switch]$AllowFailure
    )
    $registrar = Join-Path $installRoot $registrationName
    if (-not (Test-Path -LiteralPath $registrar)) {
        if ($AllowFailure) { return $false }
        throw "Registration utility is missing: $registrar"
    }
    $arguments = @($Command)
    if ($DllPath) { $arguments += $DllPath }
    & $registrar @arguments
    if ($LASTEXITCODE -ne 0) {
        if ($AllowFailure) { return $false }
        throw "Registration utility failed with exit code $LASTEXITCODE"
    }
    return $true
}

function Install-WindWhisper {
    foreach ($file in $requiredFiles) {
        $source = Join-Path $sourceDirectory $file
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Build output is missing: $source"
        }
    }

    Assert-SafeInstallPath
    New-Item -ItemType Directory -Path $installParent -Force | Out-Null
    $transactionId = [Guid]::NewGuid().ToString('N')
    $stagingRoot = Join-Path $installParent "InputMethod.staging.$transactionId"
    $backupRoot = Join-Path $installParent "InputMethod.backup.$transactionId"
    New-Item -ItemType Directory -Path $stagingRoot | Out-Null

    try {
        foreach ($file in $requiredFiles) {
            Copy-Item -LiteralPath (Join-Path $sourceDirectory $file) `
                -Destination (Join-Path $stagingRoot $file)
        }

        if (Test-Path -LiteralPath $installRoot) {
            Invoke-Registrar -Command 'unregister' -AllowFailure
            Move-Item -LiteralPath $installRoot -Destination $backupRoot
        }
        Move-Item -LiteralPath $stagingRoot -Destination $installRoot

        $dllPath = Join-Path $installRoot 'fy_tsf.dll'
        Invoke-Registrar -Command 'register' -DllPath $dllPath
        Invoke-Registrar -Command 'status' -DllPath $dllPath

        if (Test-Path -LiteralPath $backupRoot) {
            Remove-Item -LiteralPath $backupRoot -Recurse -Force
        }
        Write-Host "WindWhisper installed successfully: $installRoot"
    }
    catch {
        if (Test-Path -LiteralPath $installRoot) {
            Invoke-Registrar -Command 'unregister' -AllowFailure
            Remove-Item -LiteralPath $installRoot -Recurse -Force
        }
        if (Test-Path -LiteralPath $backupRoot) {
            Move-Item -LiteralPath $backupRoot -Destination $installRoot
            $oldDll = Join-Path $installRoot 'fy_tsf.dll'
            Invoke-Registrar -Command 'register' -DllPath $oldDll -AllowFailure
        }
        if (Test-Path -LiteralPath $stagingRoot) {
            Remove-Item -LiteralPath $stagingRoot -Recurse -Force
        }
        throw
    }
}

function Uninstall-WindWhisper {
    Assert-SafeInstallPath
    if (-not (Test-Path -LiteralPath $installRoot)) {
        Write-Host 'WindWhisper is not installed.'
        return
    }
    Invoke-Registrar -Command 'unregister' -AllowFailure
    Remove-Item -LiteralPath $installRoot -Recurse -Force
    Write-Host 'WindWhisper uninstalled. User data was preserved.'
}

function Get-WindWhisperStatus {
    $dllPath = Join-Path $installRoot 'fy_tsf.dll'
    Invoke-Registrar -Command 'status' -DllPath $dllPath
    Write-Host "WindWhisper registration is healthy: $installRoot"
}

try {
    switch ($Action) {
        'Install' { Install-WindWhisper }
        'Uninstall' { Uninstall-WindWhisper }
        'Status' { Get-WindWhisperStatus }
    }
}
catch {
    Write-Error ($_ | Out-String)
    exit 1
}
finally {
    if ($LogPath) {
        Stop-Transcript | Out-Null
    }
}
