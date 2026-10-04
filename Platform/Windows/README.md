# Windows 编译、打包与使用

## 安装

需要 Windows 10/11 x64 和管理员权限。

1. 双击 `WindWhisperInputMethod-x64.msi` 完成安装。MSI 未做 Authenticode 签名，可能提示“未知发布者”。
2. 按 `Win + Space` 切换到“风语输入法”。

升级时直接安装新版 MSI，再重新打开正在使用输入法的应用；任务栏仍是旧状态时注销并重新登录。
卸载路径：设置 → 应用 → 已安装的应用 → 风语输入法。用户数据默认保留在
`%LOCALAPPDATA%\WindWhisper\InputMethod`。

## 使用

任务栏显示 `中` / `英` 模式按钮，颜色跟随系统浅色/深色任务栏。

- **切换中英文**：单独按下并释放 `Shift`，或左键点击模式按钮。`Win`、`Ctrl`、`Alt` 组合键交给系统和应用处理。
- **设置**：右键点击模式按钮，可切换输入方案、全角/半角、简体/繁体、候选框深色/浅色，以及管理自定义词组。
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

需要 Visual Studio 2022（MSVC v143、Windows SDK）、CMake、PowerShell 7、.NET SDK 和 WiX Toolset 4。
在仓库根目录的 Developer PowerShell 中执行：

```powershell
dotnet tool install wix --version "4.*" --tool-path build/tools/wix   # 已安装可跳过
cmake -S . -B build/windows -A x64
cmake --build build/windows --config Release
ctest --test-dir build/windows -C Release
pwsh -NoProfile -File Installer/Windows/build-msi.ps1 -Configuration Release
```

安装包：`build/windows/Installer/Release/WindWhisperInputMethod-x64.msi`。

GitHub Actions 的 **Build Windows Installer** 工作流在推送到 `main`、面向 `main` 的 PR 和手动运行时构建 MSI，
产物在该次运行的 Artifacts 中。发布 GitHub Release 时会从标签构建并把 MSI 和 SHA-256 附到 Release；
发布前让 `Installer/Windows/Product.wxs` 的版本号与标签一致（如 `1.0.40` 对应 `v1.0.40`）。
