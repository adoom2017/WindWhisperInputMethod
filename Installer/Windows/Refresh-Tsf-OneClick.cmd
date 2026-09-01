@echo off
setlocal
title WindWhisper TSF refresh

set "SCRIPT=%~dp0Refresh-Tsf.ps1"
if not exist "%SCRIPT%" (
  echo Refresh-Tsf.ps1 was not found:
  echo %SCRIPT%
  pause
  exit /b 2
)

echo Refreshing WindWhisper without signing out...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "EXITCODE=%ERRORLEVEL%"
echo.
if not "%EXITCODE%"=="0" (
  echo Refresh failed with exit code %EXITCODE%.
  echo If the input method is installed by MSI, run this file as the same user that uses the language bar.
) else (
  echo Refresh completed. Close and reopen the editor or browser under test.
)
pause
exit /b %EXITCODE%
