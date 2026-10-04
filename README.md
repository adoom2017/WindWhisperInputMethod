# 风语输入法

风语（WindWhisper）是一款本地运行的中文输入法，支持 macOS、Windows 和 iOS，提供小鹤音形、小鹤双拼和风语全拼三种方案。所有输入和词库查询都在本机完成，不联网。

## 功能

- **三种方案**：小鹤音形（四键唯一候选自动上屏）、小鹤双拼、风语全拼。
- **反查编码**：小鹤音形下输入 `~` 查看候选的完整音形编码，例如 `ni~` → `你 nirx`。
- **自定义词组**：为常用词句设置编码，仅在小鹤音形下生效。
- **词频学习**：按“方案 + 编码 + 所选词条”记录选择次数，常用的候选自动靠前；记录只保存在本机，不跨设备同步。
- **繁简与全半角**：可切换简体/繁体输出和全角/半角字符。

## 平台

| 平台 | 系统要求 | 安装 | 详细说明 |
| --- | --- | --- | --- |
| macOS | macOS 13+，Apple Silicon / Intel | 运行 DMG 中的 `安装风语.pkg`，在“系统设置 → 键盘 → 文本输入”中添加“风语” | [Platform/macOS](Platform/macOS/README.md) |
| Windows | Windows 10/11 x64 | 安装 MSI，按 `Win + Space` 切换到“风语输入法” | [Platform/Windows](Platform/Windows/README.md) |
| iOS | iOS 17+ | 安装 App，在“设置 → 通用 → 键盘 → 键盘 → 添加新键盘”中添加“风语” | [iOS](iOS/README.md) |

## 基本操作

| 操作 | macOS / Windows | iOS |
| --- | --- | --- |
| 切换中英文 | 单独按下并释放 `Shift`（macOS 为左 `Shift`） | 点空格键上的“中/英” |
| 选词 | `Space` 选高亮项，`1`–`5` 选对应项 | 点击候选，或按空格 |
| 翻页 | `-` / `=`（Windows 也支持 `PageUp` / `PageDown`） | 横向滑动候选栏 |
| 提交英文编码 | `Enter` | 回车 |
| 删除编码 / 取消 | `Backspace` / `Esc` | 退格 |

设置入口：macOS 在菜单栏的风语菜单，Windows 右键点击任务栏的 `中` / `英` 按钮，iOS 在风语 App 中。

## 用户数据

自定义词组保存在 `custom_words.tsv`，词频保存在 `user_frequency.tsv`，三端格式相同。升级和卸载默认保留。

| 平台 | 位置 |
| --- | --- |
| macOS | `~/Library/Application Support/com.shendongchun.inputmethod.windwhisper/User` |
| Windows | `%LOCALAPPDATA%\WindWhisper\InputMethod` |
| iOS | 自定义词组在 App Group 共享目录（由 App 写入，键盘只读）；词频在键盘私有目录 |

## 开发

```text
Core/          C++ 引擎、C ABI 与 Swift 适配层（三端共享）
Platform/      macOS（InputMethodKit）与 Windows（TSF）平台实现
iOS/           iOS 宿主 App 与键盘扩展
Installer/     macOS PKG 脚本与 Windows WiX 安装包
Resources/     词库、图标与本地化资源
Scripts/       构建、打包、测试与资源生成脚本
docs/          设计规范、架构、测试计划与发布说明
```

快速构建：

```bash
./Scripts/build.sh Debug                         # macOS
cmake -S . -B build/windows -A x64               # Windows（Developer PowerShell）
xcodebuild -project iOS/WindWhisperiOS.xcodeproj -scheme WindWhisper \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  build CODE_SIGNING_ALLOWED=NO                  # iOS 模拟器
```

完整的编译、测试、签名和打包步骤见各平台说明。界面颜色与尺寸遵循 [视觉规范](docs/DESIGN_SYSTEM.md)，已知限制见 [KNOWN_ISSUES](docs/KNOWN_ISSUES.md)。
