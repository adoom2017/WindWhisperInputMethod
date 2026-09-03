# 风语输入法

风语（WindWhisper）是一款面向 Windows 和 macOS 的中文输入法，支持小鹤音形、小鹤双拼和全拼。项目使用同一份词典与输入规则，并针对 Windows TSF 和 macOS InputMethodKit 分别提供原生界面。

## 功能概览

- 默认使用小鹤音形，同时支持小鹤双拼和全拼
- 候选词横向展示，支持键盘选词、翻页和高亮移动
- 小鹤音形支持形码缩选与 `~` 编码反查
- 支持简体中文、繁体中文以及全角、半角切换
- 候选框支持深色和浅色配色
- 支持长句输入、自定义词条和稳定的候选排序
- Windows 系统快捷键会直接透传，不占用 Win、Ctrl 或 Alt 组合键

## Windows 使用说明

### 系统要求

- Windows 10 或 Windows 11
- x64 系统
- 安装时需要管理员权限

### 安装

1. 下载或构建 `WindWhisperInputMethod-x64.msi`。
2. 双击 MSI，按 Windows Installer 提示完成安装。
3. 按 `Win + Space`，选择“风语输入法”。
4. 打开记事本或浏览器输入框开始使用。

覆盖安装新版本后，请关闭并重新打开正在使用输入法的应用。如果任务栏仍加载旧状态，注销 Windows 后重新登录即可完全刷新。

当前本地构建的 MSI 未使用商业代码签名证书，Windows 可能显示“未知发布者”；这不影响输入法功能。

### 中英文切换

任务栏中会显示风语的“风”字标识，旁边的模式按钮直接显示当前状态：

- `中`：中文输入模式
- `英`：英文输入模式

可以使用以下任一方式切换：

- 单独按下并释放 `Shift`
- 左键点击任务栏中的 `中` / `英` 按钮

Shift 与其他按键组成快捷键时不会切换模式。Win、Ctrl、Alt 组合键会交给 Windows 或当前应用处理，例如 `Win + R`、`Win + E` 和 `Ctrl + C`。

### 输入和选词

中文模式下直接输入编码，候选框会在光标附近横向显示。

| 按键 | 功能 |
| --- | --- |
| `Space` / `Enter` | 提交当前高亮候选 |
| `1`–`5` | 选择本页对应候选 |
| `←` / `↑` | 移动到上一个候选 |
| `→` / `↓` | 移动到下一个候选 |
| `PageUp` / `-` | 上一页 |
| `PageDown` / `=` | 下一页 |
| `Backspace` | 删除一个尚未提交的编码；没有组合串时删除应用中的文字 |
| `Esc` | 取消当前组合输入 |

小鹤音形默认允许先输入音码，再继续输入形码缩小候选范围。输入 `~` 可以查看候选的完整音形编码，例如：

```text
ni~   →  你 nirx
ni~r  →  倪 nire
```

候选右侧显示的编码仅用于提示，不会写入最终文本。

### 输入法设置

右键点击任务栏中的 `中` / `英` 按钮，可以直接调整：

- 输入方案：小鹤音形、小鹤双拼、全拼
- 字符宽度：全角、半角
- 繁简切换：简体中文、繁体中文
- 候选框配色：深色、浅色

设置保存在当前 Windows 用户下。输入方案变更后，切换到其他应用或重新打开输入框即可使用新方案。

### 升级、修复和卸载

新版本 MSI 可以直接覆盖旧版本。安装程序会更新 TSF 注册信息并保留用户数据。

如果安装后任务栏没有立即出现风语输入法，可以：

1. 关闭并重新打开编辑器或浏览器。
2. 再按一次 `Win + Space` 检查输入法列表。
3. 运行安装包旁的 `Refresh-Tsf-OneClick.cmd`（如果发布包包含该文件）。
4. 仍未恢复时，注销并重新登录 Windows。

卸载路径：

```text
Windows 设置 → 应用 → 已安装的应用 → 风语输入法 → 卸载
```

卸载默认保留 `%LOCALAPPDATA%\WindWhisper\InputMethod` 中的设置和自定义词典，重新安装后可以继续使用。

## macOS 使用说明

### 系统要求

- macOS 13 或更高版本
- 发布版同时支持 Apple Silicon 和 Intel Mac

### 安装

1. 双击下载的 DMG。
2. 双击 `安装风语.pkg`，按系统安装器提示输入管理员密码并完成安装。
3. 安装器会在升级时自动切换到 ABC、停止旧版进程，并将新版安装到 `/Library/Input Methods/`。
4. 打开“系统设置 → 键盘 → 文本输入 → 编辑”。
5. 在简体中文分类中添加并启用“风语”。
6. 从菜单栏输入法菜单切换到风语；若菜单未立即刷新，再注销并重新登录。

首次安装新的输入法身份时，macOS 会要求用户手动授权。详细的升级、回滚和卸载说明见 [发布版安装说明](docs/RELEASE_INSTALL.md)。

## 自定义词典

Windows 用户词典位置：

```text
%LOCALAPPDATA%\WindWhisper\InputMethod\custom_words.tsv
```

每行使用制表符分隔：

```text
词语<Tab>编码<Tab>权重
```

权重可以省略。修改词典后，关闭并重新打开使用输入法的应用，使词典重新加载。请定期备份该文件。

## Windows 开发构建

需要 Visual Studio 2022、MSVC v143、Windows 10/11 SDK、CMake 和 WiX Toolset 4。

在 Developer PowerShell 中执行：

```powershell
cmake -S . -B build/windows -A x64
cmake --build build/windows --config Release
ctest --test-dir build/windows -C Release --output-on-failure
pwsh -NoProfile -File Installer/Windows/build-msi.ps1 -Configuration Release
```

安装包输出到：

```text
build/windows/Installer/Release/WindWhisperInputMethod-x64.msi
```

Windows 架构、TSF 注册和测试说明见 [Windows 开发文档](docs/WINDOWS_HANDOFF.md)。

## macOS 开发构建

需要 Xcode 26 或兼容版本。在仓库根目录执行：

```bash
./Scripts/verify-project.sh
./Scripts/build.sh Debug
```

安装当前用户的开发版本：

```bash
./Scripts/install-user.sh Debug
```

构建产物位于：

```text
build/DerivedData/Build/Products/<Configuration>/windwhisper.app
```

## 正式签名与 Apple 公证

对 Mac 外部分发需同时使用 Apple Developer 账号中的 `Developer ID Application`
和 `Developer ID Installer` 证书，分别签名应用与 PKG。`Apple Development` 证书仅适用于开发调试。先检查本机可用的签名身份：

```bash
security find-identity -v -p codesigning
security find-identity -v -p basic
```

第一条命令应列出 Application identity，第二条命令还应列出 Installer identity：

```text
Developer ID Application: Your Name (TEAMID)
Developer ID Installer: Your Name (TEAMID)
```

如果显示 `0 valid identities found`，请在“钥匙串访问”中导入创建该证书时导出的
`.p12`，并确认证书下方有对应的私钥。仅安装从 Apple 下载的 `.cer`
不会构成可用 identity；如果私钥在另一台 Mac，需从那台 Mac 导出包含私钥的
`.p12` 再导入本机。

### 生成正式签名包

将下面的 identity 替换为上一步查到的完整证书名称：

```bash
WINDWHISPER_APP_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
WINDWHISPER_INSTALLER_SIGN_IDENTITY="Developer ID Installer: Your Name (TEAMID)" \
  Scripts/package-release.sh signed 0.1.0 2026090201
```

`signed` 模式会构建 arm64/x86_64 通用应用，启用 Hardened Runtime、时间戳并使用
Developer ID 签名，然后在 `dist/` 下生成 PKG、内含该 PKG 的 DMG 和各自的 SHA-256 文件。构建号必须为纯数字。
可用以下命令查看和验证签名：

```bash
pkgutil --check-signature dist/windwhisper-0.1.0-2026090201-macos-universal.pkg
spctl --assess --type install --verbose=2 \
  dist/windwhisper-0.1.0-2026090201-macos-universal.pkg
```

仅完成 Developer ID 签名的包可用于内部验证；面向用户分发时应继续完成 Apple 公证。
`Scripts/package-release.sh local ...` 只会使用 ad-hoc 签名，不是正式发布包。

### 生成已公证发布包

先在 Apple ID 账号页面创建 app-specific password，然后将公证凭据安全存入登录钥匙串：

```bash
xcrun notarytool store-credentials "windwhisper-notary" \
  --apple-id "your-apple-id@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

提交公证并将 ticket staple 到 PKG 和 DMG：

```bash
WINDWHISPER_APP_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
WINDWHISPER_INSTALLER_SIGN_IDENTITY="Developer ID Installer: Your Name (TEAMID)" \
WINDWHISPER_NOTARY_PROFILE="windwhisper-notary" \
WINDWHISPER_NOTARY_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db" \
  Scripts/package-release.sh notarized 0.1.0 2026090201
```

`notarized` 模式会完成签名、上传公证、等待 Apple 结果、staple、
`stapler validate` 和最终发布包校验。PKG 安装后输入法位于：

```text
/Library/Input Methods/windwhisper.app
```

### 生成正式签名并公证的安装包

`Scripts/package-release.sh` 会同时生成签名 PKG 和包含 `安装风语.pkg` 的 DMG。
PKG 在覆盖前停止旧输入法进程，避免 Finder 因应用正在使用而拒绝升级。
下面示例中的版本号、构建号、证书名称和公证 profile 应替换为实际值：

```bash
WINDWHISPER_APP_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
WINDWHISPER_INSTALLER_SIGN_IDENTITY="Developer ID Installer: Your Name (TEAMID)" \
WINDWHISPER_NOTARY_PROFILE="windwhisper-notary" \
  Scripts/package-release.sh notarized 0.1.0 2026090301
```

若公证凭据存放在非默认钥匙串，为 `notarytool submit` 增加
`--keychain /path/to/keychain-db`。只有 `notarytool` 返回 `Accepted`，并且
`stapler validate` 与 `spctl` 均通过后，PKG 和 DMG 才可作为正式对外发布产物。
最终应同时发布 `.pkg`、`.dmg` 和对应的 SHA-256 文件。仅签名但未公证的安装包
可用于内部测试，不应作为面向普通用户的正式下载包。

不要将 `.p12`、证书密码、Apple ID app-specific password 或公证凭据提交到
Git。GitHub Actions 中的证书与公证凭据应保存为 Repository Secrets，详见
[`docs/GITHUB_RELEASE.md`](docs/GITHUB_RELEASE.md)。

## 项目结构

```text
Core/               跨平台 C++ 输入核心和测试
Platform/Windows/   Windows TSF、任务栏按钮与候选窗
Platform/macOS/     macOS InputMethodKit 与原生界面
Installer/Windows/  WiX MSI 和安装维护脚本
Installer/macOS/    PKG 安装前后维护脚本
Resources/          词典、图标与共享资源
Scripts/            构建、安装、验证和发布脚本
docs/               架构、发布与验收文档
```

## 自动发布

发布 `vMAJOR.MINOR.PATCH` 格式的 GitHub Release 后，GitHub Actions 会自动构建、
Developer ID 签名、公证并上传 macOS universal PKG、DMG 与各自的 SHA-256 文件。首次启用前需
配置签名与 Apple 公证 Secrets，详见
[`docs/GITHUB_RELEASE.md`](docs/GITHUB_RELEASE.md)。
