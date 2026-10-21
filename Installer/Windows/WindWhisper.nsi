Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"
!include "WinVer.nsh"
!include "WordFunc.nsh"

!ifndef PRODUCT_VERSION
  !error "Use build-installer.ps1 to provide the MSI metadata and paths."
!endif

Name "风语输入法"
UninstallCaption "风语输入法卸载"
OutFile "${OUTPUT_FILE}"
InstallDir "$PROGRAMFILES64\WindWhisper Input Method"
!ifdef SETUP_PREVIEW
  RequestExecutionLevel user
  Caption "风语输入法安装 — 界面预览"
!else
  RequestExecutionLevel admin
  Caption "风语输入法安装"
!endif
ManifestDPIAware true
ManifestSupportedOS all
SetCompressor /SOLID lzma
ShowInstDetails nevershow
ShowUninstDetails nevershow
BrandingText "风语输入法 · Windows 版"
VIProductVersion "${PRODUCT_VERSION}.0"
VIAddVersionKey /LANG=2052 "ProductName" "风语输入法"
VIAddVersionKey /LANG=2052 "CompanyName" "WindWhisper"
VIAddVersionKey /LANG=2052 "FileDescription" "风语输入法安装程序"
VIAddVersionKey /LANG=2052 "FileVersion" "${PRODUCT_VERSION}.0"
VIAddVersionKey /LANG=2052 "ProductVersion" "${PRODUCT_VERSION}"
VIAddVersionKey /LANG=2052 "LegalCopyright" "WindWhisper"

!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\WindWhisperInputMethod"
!define MSI_UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_CODE}"
!define MUI_ICON "${ICON_FILE}"
!define MUI_UNICON "${ICON_FILE}"
!define MUI_WELCOMEFINISHPAGE_BITMAP "${WIZARD_BITMAP}"
!define MUI_UNWELCOMEFINISHPAGE_BITMAP "${WIZARD_BITMAP}"
!define MUI_WELCOMEFINISHPAGE_BITMAP_STRETCH FitControl
!define MUI_UNWELCOMEFINISHPAGE_BITMAP_STRETCH FitControl
!define MUI_ABORTWARNING
!define MUI_UNABORTWARNING

!define MUI_WELCOMEPAGE_TITLE "欢迎安装风语输入法"
!define MUI_WELCOMEPAGE_TEXT "轻巧、流畅的中文输入体验。$\r$\n$\r$\n版本 ${PRODUCT_VERSION} · Windows 10/11 x64$\r$\n$\r$\n点击“安装”开始安装。升级会保留你的自定义词组和个人设置。"
!insertmacro MUI_PAGE_WELCOME
!define MUI_PAGE_HEADER_TEXT "正在安装风语输入法"
!define MUI_PAGE_HEADER_SUBTEXT "正在配置输入服务，请稍候。"
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_TITLE "风语输入法安装完成"
!define MUI_FINISHPAGE_TEXT "按 Win + Space 即可切换到风语输入法。$\r$\n$\r$\n请重新打开正在使用输入法的应用。如果仍显示旧版图标或候选框，保存工作后注销并重新登录 Windows。"
!define MUI_FINISHPAGE_TEXT_REBOOT "风语输入法已安装。部分输入服务正在使用，需要重新启动 Windows 才能完成更新。$\r$\n$\r$\n请先保存正在编辑的内容。"
!define MUI_FINISHPAGE_REBOOTLATER_DEFAULT
!insertmacro MUI_PAGE_FINISH

!define MUI_WELCOMEPAGE_TITLE "卸载风语输入法"
!define MUI_WELCOMEPAGE_TEXT "此向导将移除风语输入法。$\r$\n$\r$\n你的自定义词组、词频数据和个人设置将被保留。$\r$\n$\r$\n点击“卸载”开始卸载。"
!insertmacro MUI_UNPAGE_WELCOME
!define MUI_PAGE_HEADER_TEXT "正在卸载风语输入法"
!define MUI_PAGE_HEADER_SUBTEXT "正在移除输入服务，请稍候。"
!insertmacro MUI_UNPAGE_INSTFILES
!define MUI_FINISHPAGE_TITLE "风语输入法已卸载"
!define MUI_FINISHPAGE_TEXT "输入法已移除，你的个人数据仍然保留。$\r$\n$\r$\n如果任务栏仍显示风语输入法，请注销并重新登录 Windows。"
!define MUI_FINISHPAGE_REBOOTLATER_DEFAULT
!insertmacro MUI_UNPAGE_FINISH
!insertmacro MUI_LANGUAGE "SimpChinese"
SetFont /LANG=${LANG_SIMPCHINESE} "Microsoft YaHei UI" 9

!ifndef SETUP_PREVIEW
Var LogPath
Var RepairArguments
!endif

Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_OK|MB_ICONSTOP "此安装包仅支持 64 位 Windows。" /SD IDOK
    SetErrorLevel 1633
    Quit
  ${EndIf}
  ${IfNot} ${AtLeastWin10}
    MessageBox MB_OK|MB_ICONSTOP "风语输入法需要 Windows 10 或更高版本。" /SD IDOK
    SetErrorLevel 1633
    Quit
  ${EndIf}
  SetRegView 64
  SetShellVarContext all
  ; Fixed system location: no long path field and no arbitrary /D override.
  StrCpy $INSTDIR "$PROGRAMFILES64\WindWhisper Input Method"
!ifndef SETUP_PREVIEW
  ReadRegStr $0 HKLM "${UNINSTALL_KEY}" "DisplayVersion"
  ${If} $0 != ""
    ${VersionCompare} "$0" "${PRODUCT_VERSION}" $1
    ${If} $1 == 1
      MessageBox MB_OK|MB_ICONINFORMATION "已安装更新版本的风语输入法，无需降级。" /SD IDOK
      SetErrorLevel 1638
      Quit
    ${EndIf}
  ${EndIf}
!endif
FunctionEnd

Section "风语输入法"
  SetDetailsPrint none
!ifdef SETUP_PREVIEW
  ; Separate developer-only preview executable: never installs or writes ARP.
  InitPluginsDir
  WriteUninstaller "$PLUGINSDIR\Uninstall-preview.exe"
  SetDetailsPrint textonly
  DetailPrint "正在预览安装界面（不会更改系统）…"
  Sleep 1200
!else
  InitPluginsDir
  SetOutPath "$PLUGINSDIR"
  File /oname=WindWhisper.msi "${PAYLOAD_MSI}"
  CreateDirectory "$APPDATA\WindWhisper\Installer"
  StrCpy $LogPath "$APPDATA\WindWhisper\Installer\install.log"
  StrCpy $RepairArguments ""
  System::Call 'msi::MsiQueryProductStateW(w "${PRODUCT_CODE}") i .r1'
  ${If} $1 == 5
    StrCpy $RepairArguments "REINSTALL=ALL REINSTALLMODE=vomus"
  ${EndIf}
  SetDetailsPrint textonly
  DetailPrint "正在安装并配置输入法，请稍候…"
  SetDetailsPrint none
  ClearErrors
  ; GUI-subsystem msiexec and registrar: no cmd/PowerShell process or window.
  ExecWait '"$SYSDIR\msiexec.exe" /i "$PLUGINSDIR\WindWhisper.msi" /qn /norestart ARPSYSTEMCOMPONENT=1 MSIRESTARTMANAGERCONTROL=DisableShutdown $RepairArguments /L*v "$LogPath"' $0
  ${If} ${Errors}
    StrCpy $0 1603
  ${EndIf}
  ${If} $0 != 0
  ${AndIf} $0 != 3010
    MessageBox MB_OK|MB_ICONSTOP "安装未完成（错误代码 $0）。$\r$\n$\r$\n请关闭正在使用输入法的应用后重试。详细日志：$\r$\n$LogPath" /SD IDOK
    SetErrorLevel $0
    Abort
  ${EndIf}
  ${If} $0 == 3010
    SetRebootFlag true
  ${EndIf}
  ; Publish the NSIS uninstall entry only after MSI commits successfully.
  ClearErrors
  SetOutPath "$INSTDIR"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "DisplayName" "风语输入法"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "Publisher" "WindWhisper"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\fy_tsf.dll,0"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "ProductCode" "${PRODUCT_CODE}"
  WriteRegStr HKLM "${UNINSTALL_KEY}" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
  WriteRegStr HKLM "${UNINSTALL_KEY}" "QuietUninstallString" '$\"$INSTDIR\Uninstall.exe$\" /S'
  WriteRegDWORD HKLM "${UNINSTALL_KEY}" "EstimatedSize" ${INSTALL_SIZE_KB}
  WriteRegDWORD HKLM "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINSTALL_KEY}" "NoRepair" 1
  ${If} ${Errors}
    ; Keep a usable Windows Installer uninstall entry if the front-end fails.
    WriteRegDWORD HKLM "${MSI_UNINSTALL_KEY}" "SystemComponent" 0
    DeleteRegKey HKLM "${UNINSTALL_KEY}"
    MessageBox MB_OK|MB_ICONSTOP "输入服务已安装，但安装向导未能完成配置。请从 Windows 设置中卸载风语输入法后重试。" /SD IDOK
    SetErrorLevel 1603
    Abort
  ${EndIf}
  SetDetailsPrint textonly
  DetailPrint "风语输入法安装完成。"
!endif
SectionEnd

Function .onInstSuccess
  ${If} ${RebootFlag}
    SetErrorLevel 3010
  ${EndIf}
FunctionEnd

Function un.onInit
  SetRegView 64
  SetShellVarContext all
  StrCpy $INSTDIR "$PROGRAMFILES64\WindWhisper Input Method"
!ifndef SETUP_PREVIEW
  ReadRegStr $0 HKLM "${UNINSTALL_KEY}" "ProductCode"
  ${If} $0 != "${PRODUCT_CODE}"
    MessageBox MB_OK|MB_ICONSTOP "此卸载程序不属于当前安装版本。请从 Windows 设置的“已安装的应用”中卸载风语输入法。" /SD IDOK
    SetErrorLevel 1605
    Quit
  ${EndIf}
!endif
FunctionEnd

Section "Uninstall"
  SetDetailsPrint none
!ifdef SETUP_PREVIEW
  SetDetailsPrint textonly
  DetailPrint "正在预览卸载界面（不会更改系统）…"
  Sleep 1200
!else
  CreateDirectory "$APPDATA\WindWhisper\Installer"
  StrCpy $LogPath "$APPDATA\WindWhisper\Installer\uninstall.log"
  SetDetailsPrint textonly
  DetailPrint "正在移除输入法，个人词组和设置将被保留…"
  SetDetailsPrint none
  ClearErrors
  ExecWait '"$SYSDIR\msiexec.exe" /x ${PRODUCT_CODE} /qn /norestart MSIRESTARTMANAGERCONTROL=DisableShutdown /L*v "$LogPath"' $0
  ${If} ${Errors}
    StrCpy $0 1603
  ${EndIf}
  ${If} $0 != 0
  ${AndIf} $0 != 3010
  ${AndIf} $0 != 1605
  ${AndIf} $0 != 1614
    MessageBox MB_OK|MB_ICONSTOP "卸载未完成（错误代码 $0）。请稍后重试。$\r$\n$\r$\n详细日志：$\r$\n$LogPath" /SD IDOK
    SetErrorLevel $0
    Abort
  ${EndIf}
  ${If} $0 == 3010
    SetRebootFlag true
  ${EndIf}
  DeleteRegKey HKLM "${UNINSTALL_KEY}"
  ; MSI owns the payload. Remove only our own uninstaller; never recurse into
  ; the installation directory or touch LOCALAPPDATA user dictionaries.
  Delete /REBOOTOK "$INSTDIR\Uninstall.exe"
  RMDir /REBOOTOK "$INSTDIR"
  SetDetailsPrint textonly
  DetailPrint "风语输入法已卸载，个人数据已保留。"
!endif
SectionEnd

Function un.onUninstSuccess
  ${If} ${RebootFlag}
    SetErrorLevel 3010
  ${EndIf}
FunctionEnd
