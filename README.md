# 风语输入法

风语（WindWhisper）支持 Windows、macOS 和 iOS，提供小鹤音形、小鹤双拼和全拼输入。

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
| `Space` | 提交当前高亮候选 |
| `Enter` | 直接提交英文编码并清空候选；无编码时由应用正常处理 |
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
- 管理自定义词组：新增、编辑、删除词组，设置可选权重，以及导入、导出词库

设置保存在当前 Windows 用户下。保存自定义词组后会立即应用到当前输入法实例；其他已经打开的应用会在重新获得焦点时自动加载最新词典。

### 升级、修复和卸载

新版本 MSI 可以直接覆盖旧版本。安装程序会更新 TSF 注册信息并保留用户数据。

如果安装后任务栏没有立即出现风语输入法，可以：

1. 关闭并重新打开编辑器或浏览器。
2. 再按一次 `Win + Space` 检查输入法列表。
3. 如果任务栏仍显示旧状态，请注销 Windows 后重新登录，使输入法重新加载。
4. 仍未恢复时，注销并重新登录 Windows。

卸载路径：

```text
Windows 设置 → 应用 → 已安装的应用 → 风语输入法 → 卸载
```

卸载默认保留 `%LOCALAPPDATA%\WindWhisper\InputMethod` 中的设置和自定义词典，重新安装后可以继续使用。

### 自定义词典

Windows 用户词典位置：

```text
%LOCALAPPDATA%\WindWhisper\InputMethod\custom_words.tsv
```

每行使用制表符分隔：

```text
词语<Tab>编码<Tab>权重
```

权重可以省略；数值越高，候选排序越靠前。推荐通过 Windows 任务栏模式按钮的右键菜单选择“管理自定义词组...”，避免手工编辑格式。请定期备份该文件。

管理窗口中的“导入”支持合并或替换当前词库；合并时，同词组、同编码的记录会使用导入文件中的权重。“导出”生成 UTF-8 编码的 TSV 文件，可用于备份或迁移到其他设备。

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

### 输入与设置

从菜单栏的风语菜单切换输入方案、繁简、全半角和管理自定义词组。

- 单独按下并释放左 `Shift` 切换中英文。
- 输入编码后按空格选词，数字键选择对应候选，`-` / `=` 翻页。
- 按回车直接提交当前英文编码并清空候选，不额外换行；没有编码时正常回车。
- `Backspace` 删除一个编码，`Esc` 取消当前组合。
- 小鹤音形输入 `~` 可反查候选的完整音形编码。

## iOS 安装与使用

安装宿主 App 后，在“设置 → 通用 → 键盘 → 键盘 → 添加新键盘”中添加“风语”，
并开启“允许完全访问”。在宿主 App 中选择输入方案，再在普通文本框中切换到风语。

编译、真机安装、打包和键盘使用说明见 [iOS README](iOS/README.md)。

## Windows 编译与打包

需要 Windows 10/11 x64、Visual Studio 2022（MSVC v143、Windows SDK）、CMake、
PowerShell 7、.NET SDK 和 WiX Toolset 4。在仓库根目录的 Developer PowerShell 中执行：

```powershell
dotnet tool install wix --version "4.*" --tool-path build/tools/wix
cmake -S . -B build/windows -A x64
cmake --build build/windows --config Release
pwsh -NoProfile -File Installer/Windows/build-msi.ps1 -Configuration Release
```

WiX 已安装到 `build/tools/wix` 时，可跳过第一条命令。

安装包：`build/windows/Installer/Release/WindWhisperInputMethod-x64.msi`。

GitHub Actions 的 **Build Windows Installer** 工作流会在推送到 `main`、提交面向 `main` 的 PR 时自动构建 Windows x64 MSI，也支持在 Actions 页面手动选择 **Run workflow**。运行成功后，在该次运行的 Artifacts 中下载 `windwhisper-windows-x64-*`，解压后即可双击 MSI 安装。

发布 GitHub Release 时，同一工作流会从发布标签构建、运行测试，并将 MSI 和 SHA-256 校验文件上传到 Release 附件。发布前请将 `Installer/Windows/Product.wxs` 的版本号与标签保持一致，例如版本 `1.0.40` 对应 `v1.0.40`。Windows 构建不依赖 macOS 签名密钥；当前生成的 MSI 未做 Authenticode 签名。

直接双击 MSI 安装。安装注册程序使用无控制台模式，发布目录不再附带 CMD 刷新脚本。构建工具在后台运行，输出仍显示在当前构建终端；打包会校验注册程序的 Windows GUI 子系统，防止旧控制台程序混入安装包。

## macOS 编译

需要 Xcode 26 或兼容版本。以下命令均在仓库根目录执行：

```bash
./Scripts/build.sh Debug
./Scripts/install-user.sh Debug
```

如果没有开发签名证书，可使用本地签名编译：

```bash
WINDWHISPER_AD_HOC_SIGNING=1 ./Scripts/build.sh Debug
```

构建产物：`build/DerivedData/Build/Products/<Configuration>/windwhisper.app`。
`Debug` 构建用于 Apple Silicon 开发；`Release` 构建用于通用发布包。

## macOS 打包

本地安装包：

```bash
Scripts/package-release.sh local 0.1.0 2026091001
```

版本号和纯数字构建号按需替换。产物输出到 `dist/`，包含 PKG、DMG 和 SHA-256 文件。
`local` 使用本地签名；对外发布使用下方的签名和公证流程。

### 签名与公证

准备 Apple Developer 账号中的 `Developer ID Application` 和 `Developer ID Installer`
证书，并将包含私钥的证书导入钥匙串。查看可用身份：

```bash
security find-identity -v -p codesigning
security find-identity -v -p basic
```

首次使用时保存公证凭据，按提示输入 Apple ID、团队 ID 和 App 专用密码：

```bash
xcrun notarytool store-credentials "windwhisper-notary"
```

将证书名称替换为本机实际身份后打包：

```bash
WINDWHISPER_APP_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
WINDWHISPER_INSTALLER_SIGN_IDENTITY="Developer ID Installer: Your Name (TEAMID)" \
WINDWHISPER_NOTARY_PROFILE="windwhisper-notary" \
  Scripts/package-release.sh notarized 0.1.0 2026091001
```

脚本自动完成通用应用构建、签名、公证和票据装订。仅需签名时，将 `notarized` 改为 `signed`。
公证凭据位于非默认钥匙串时，设置 `WINDWHISPER_NOTARY_KEYCHAIN` 为对应路径。

也可通过 GitHub Release 自动打包：配置签名与公证 Secrets 后，发布 `vMAJOR.MINOR.PATCH`
格式的 Release。配置步骤见 [自动发布说明](docs/GITHUB_RELEASE.md)。
