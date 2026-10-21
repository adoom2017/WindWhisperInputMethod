# Windows 编译、打包与使用

## 安装

需要 Windows 10/11 x64 和管理员权限。

1. 双击 `WindWhisperInputMethod-x64-Setup.exe`，按中文向导完成安装。安装包未做 Authenticode 签名，可能提示“未知发布者”。
2. 按 `Win + Space` 切换到“风语输入法”。

升级时直接运行新版 EXE，也支持从旧版 MSI 安装升级。安装向导仅显示进度和操作提示，不显示文件路径或命令窗口。
安装后重新打开正在使用输入法的应用；任务栏仍是旧状态时注销并重新登录。如果提示重启，可保存工作后再重启。
卸载路径：设置 → 应用 → 已安装的应用 → 风语输入法。用户数据默认保留在
`%LOCALAPPDATA%\WindWhisper\InputMethod`。

## 使用

任务栏显示 `中` / `英` 模式按钮，颜色跟随系统浅色/深色任务栏。
模式按钮和“风”字图标采用普通字重及一致的字号比例；“风”字使用适合深浅背景的中性灰，无描边、阴影或底板。

- **切换中英文**：单独按下并释放 `Shift`，或左键点击模式按钮。`Win`、`Ctrl`、`Alt` 组合键交给系统和应用处理。
- **设置**：右键点击模式按钮，可切换输入方案、全角/半角、中文/英文标点、简体/繁体、候选框深色/浅色，以及管理自定义词组。
  保存后当前输入法立即生效，其他应用在重新获得焦点时加载。

| 按键 | 功能 |
| --- | --- |
| `Space` | 提交高亮候选 |
| `1`–`5` | 选择本页对应候选 |
| `←` `↑` / `→` `↓` | 上一个 / 下一个候选 |
| `PageUp` `-` / `PageDown` `=` | 上一页 / 下一页 |
| `Enter` | 直接提交英文编码；无编码时由应用处理 |
| `Backspace` | 删除一个编码；无编码时删除应用中的文字 |
| `Esc` | 取消当前组合 |

## 自定义词组

推荐通过右键菜单的“管理自定义词组...”编辑，支持新增、修改、删除、设置权重，以及导入（合并或替换）和导出 UTF-8 TSV。
文件位于 `%LOCALAPPDATA%\WindWhisper\InputMethod\custom_words.tsv`，每行格式为 `词组<Tab>编码<Tab>权重`，
权重可省略，越高越靠前。

## 编译与打包

需要 Visual Studio 2022（MSVC v143、Windows SDK）、CMake、PowerShell 7、.NET SDK 和 WiX Toolset。
打包脚本会下载并校验固定版本的便携 NSIS 编译器，无需单独安装 NSIS。
在仓库根目录的 Developer PowerShell 中执行：

```powershell
dotnet tool install wix --version 6.0.2 --tool-path build/tools/wix   # 已安装可跳过
cmake -S . -B build/windows -A x64
cmake --build build/windows --config Release
ctest --test-dir build/windows -C Release
pwsh -NoProfile -File Installer/Windows/build-installer.ps1 -Configuration Release
```

安装包：`build/windows/Installer/Release/WindWhisperInputMethod-x64-Setup.exe`，旁边的 `.sha256` 文件用于校验。

NSIS 提供欢迎、安装进度、完成及卸载向导，内部以无界面方式执行 MSI，保留输入法注册、升级回滚和用户数据保留逻辑。
Windows 的“已安装的应用”只显示一个“风语输入法”入口；再次运行同一安装包可修复安装。诊断日志位于
`%PROGRAMDATA%\WindWhisper\Installer\install.log` 和 `uninstall.log`，正常安装界面不会展示日志路径。

GitHub Actions 的 **Build Windows Installer** 工作流在推送到 `main`、面向 `main` 的 PR 和手动运行时构建 NSIS EXE，
运行回归测试及静默安装、修复、卸载验证，产物在该次运行的 Artifacts 中。发布 GitHub Release 时会从标签构建并把 EXE 和 SHA-256 附到 Release；
发布前让 `Installer/Windows/Product.wxs` 的版本号与标签一致（如 `1.0.48` 对应 `v1.0.48`）。MSI 仅作为内部构建产物，不再对外发布。

仅预览向导界面（无需管理员权限，不安装或更改输入法）：

```powershell
pwsh -NoProfile -File Installer/Windows/build-installer.ps1 -Configuration Release -SkipBuild -Preview
```

在干净的 Windows 虚拟机中，以管理员身份执行完整安装验证：

```powershell
pwsh -NoProfile -File Installer/Windows/Test-Installer.ps1 -AllowMachineChanges
```
