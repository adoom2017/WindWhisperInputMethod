# Windows 编译、打包与使用

## 环境要求

- Windows 10/11 x64
- Visual Studio 2022，包含 MSVC v143 和 Windows 10/11 SDK
- CMake、PowerShell 7、.NET SDK、WiX Toolset 4

## 编译与打包

在仓库根目录的 Developer PowerShell 中执行：

```powershell
dotnet tool install wix --version "4.*" --tool-path build/tools/wix
cmake -S . -B build/windows -A x64
cmake --build build/windows --config Release
pwsh -NoProfile -File Installer/Windows/build-msi.ps1 -Configuration Release
```

WiX 已安装到 `build/tools/wix` 时，可跳过第一条命令。

安装包输出到 `build/windows/Installer/Release/WindWhisperInputMethod-x64.msi`。

## 安装与使用

1. 以管理员权限安装 MSI。
2. 按 `Win + Space` 切换到“风语输入法”。
3. 输入编码后按空格选词，按回车直接提交英文编码，按 `-` / `=` 翻页。
4. 单独按下并释放 `Shift` 或点击任务栏的 `中` / `英` 按钮切换中英文。
5. 右键点击模式按钮，切换输入方案、繁简、全半角、配色或管理自定义词组。

升级后重新打开使用输入法的应用；若未刷新，注销并重新登录。
在 Windows“设置 → 应用 → 已安装的应用”中卸载风语，用户设置和词典默认保留在
`%LOCALAPPDATA%\WindWhisper\InputMethod`。

完整的按键和词典使用说明见 [项目 README](../../README.md#windows-使用说明)。
