# WindWhisper iOS 开发与测试

iOS 版本包含两个目标：

- `WindWhisper`：宿主 App，用于选择输入方案并承载键盘扩展。
- `WindWhisperKeyboard`：`com.apple.keyboard-service` 扩展，负责显示键盘、候选和向当前 App 提交文字。

最低系统版本为 iOS 17。键盘词库随扩展离线打包，当前不申请“允许完全访问”。

## 环境要求

- Xcode 26 或兼容版本
- 已安装对应的 iOS Simulator runtime
- XcodeGen，可通过 `brew install xcodegen` 安装
- 真机测试需要已登录 Apple Developer 账号，并为两个目标配置有效签名

以下命令均从仓库根目录执行。

## 生成工程

提交到仓库的 Xcode 工程可以直接打开。修改 `iOS/project.yml` 后，应重新生成工程：

```bash
cd iOS
xcodegen generate --spec project.yml
cd ..
```

不要直接修改生成后的 `iOS/WindWhisperiOS.xcodeproj/project.pbxproj`；目标、资源或签名配置
应写入 `iOS/project.yml` 后重新生成。

## 命令行编译验证

先查看本机可用模拟器：

```bash
xcrun simctl list devices available
```

使用已存在的设备名称编译，例如：

```bash
xcodebuild \
  -project iOS/WindWhisperiOS.xcodeproj \
  -scheme WindWhisper \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/iOSDerivedData \
  build CODE_SIGNING_ALLOWED=NO
```

成功时应看到 `** BUILD SUCCEEDED **`。产物位于：

```text
build/iOSDerivedData/Build/Products/Debug-iphonesimulator/WindWhisper.app
```

此步骤验证宿主 App、Keyboard Extension、词库资源和扩展嵌入关系，但不会自动启用系统键盘。

## 在模拟器中测试

1. 使用 Xcode 打开 `iOS/WindWhisperiOS.xcodeproj`。
2. 在顶部选择 `WindWhisper` scheme，不要直接选择 `WindWhisperKeyboard`。
3. 选择一个 iPhone 模拟器，按 `Command-R` 安装并运行宿主 App。
4. 在宿主 App 中选择“小鹤音形”“小鹤双拼”或“风语全拼”。
5. 打开模拟器的“设置 → 通用 → 键盘 → 键盘 → 添加新键盘”。
6. 在第三方键盘列表中选择“风语”。当前版本不需要启用“允许完全访问”。
7. 打开备忘录，新建笔记并聚焦正文文本框。
8. 长按系统键盘的地球图标，从输入法列表切换到“风语”。使用 Mac 硬件键盘测试时，也可用
   `Control-Space` 在已启用的输入法之间切换。

修改代码后再次按 `Command-R`。如果扩展仍显示旧版本，先在“设置 → 通用 → 键盘 →
键盘”中删除风语，再重新添加；仍未刷新时删除模拟器中的宿主 App 后重装。

## 在真机中测试

1. 在 Xcode 的 `Signing & Capabilities` 中，为 `WindWhisper` 和
   `WindWhisperKeyboard` 选择同一个 Development Team。
2. 确认两个目标均包含 `group.com.shendongchun.windwhisper` App Group。若该标识不属于
   当前团队，需要在 `iOS/project.yml`、两个 entitlements 文件和 Swift 源码中一起替换。
3. 连接已开启开发者模式的 iPhone，在 Xcode 中选择该设备并运行 `WindWhisper` scheme。
4. 首次运行时按系统提示信任开发者证书。
5. 在 iPhone 的“设置 → 通用 → 键盘 → 键盘 → 添加新键盘”中添加“风语”。
6. 在备忘录、信息或 Safari 普通文本框中切换到风语并执行下方用例。

真机能覆盖触摸、内存压力、扩展被系统终止后重启、横竖屏和不同 App 文本代理行为，发布前
不能只依赖模拟器结果。

## 基础验收用例

| 场景 | 操作 | 预期结果 |
| --- | --- | --- |
| 键盘加载 | 在普通文本框切换到风语 | 显示字母键、候选区域和中英切换键，无“引擎不可用” |
| 全拼输入 | 选择风语全拼，输入 `nihao` | 组合区显示编码，候选区出现“你好”等候选 |
| 候选提交 | 点击候选或输入编码后按空格 | 候选文字只提交一次，组合区和候选区清空 |
| 组合退格 | 输入编码后按退格 | 每次删除一个未提交编码，不删除正文已有文字 |
| 正文退格 | 组合区为空时按退格 | 删除光标前一个正文字符 |
| 中英切换 | 点击“中英”，再输入字母 | 英文模式直接提交字母；再次切换后恢复中文候选 |
| 方案共享 | 在宿主 App 切换方案，重新加载键盘 | 键盘使用新方案生成候选 |
| 多 App | 分别在备忘录和 Safari 输入 | 两个 App 都能加载键盘并正常提交文字 |
| 生命周期 | 切到其他键盘再切回，或将宿主 App 退到后台 | 键盘可重新加载，不保留上一次未提交组合 |
| 横竖屏 | 旋转设备后继续输入 | 按键可点击，文字和候选不重叠或超出屏幕 |

建议额外检查连续快速输入、连续退格、候选为空和长文本。

## iOS 系统限制

以下情况是 iOS 对第三方键盘的系统限制，不代表风语加载失败：

- 密码和其他安全文本框会强制切换到系统键盘。
- 电话号码等特定键盘类型可能使用系统专用键盘。
- App 可以禁止第三方键盘，因此部分 App 中不会出现风语。
- Keyboard Extension 不能直接控制宿主 App 的光标、选择范围或键盘切换策略。
- 系统可随时终止键盘扩展；扩展重新出现时必须重新初始化。

排查问题时优先使用备忘录的普通正文文本框，不要在密码框中验证。

## 当前实现限制

- 当前键盘尚未提供调用 `advanceToNextInputMode()` 的地球键。在模拟器中可用
  `Control-Space` 切换；真机测试结束后，可在系统键盘可用的输入框中切换，或暂时从键盘设置中
  移除风语。补齐地球键是发布前的必做项。
- 方案设置只在新的键盘会话初始化时读取。修改方案后若没有立即生效，需要让系统重新加载扩展。
- 当前键盘只覆盖字母输入、候选、空格、退格和中英切换，尚未实现数字、符号、回车、Shift、
  大小写、语音等完整系统键盘功能。

## 常见问题

### 添加新键盘时看不到风语

确认运行的是 `WindWhisper` 宿主 App scheme，并检查构建产物中是否存在：

```text
WindWhisper.app/PlugIns/WindWhisperKeyboard.appex
```

删除已安装的宿主 App，重新运行后再进入键盘设置页面。

### 键盘显示“引擎不可用”

检查扩展产物内是否包含 `fy.dict.yaml`，并确认 App Group 配置一致。修改 entitlements 后需要
重新签名和安装，单纯重启键盘不会更新权限。

### 修改输入方案后没有生效

方案在键盘会话创建时读取。切换到另一个系统键盘后再切回风语；必要时关闭并重新打开当前
输入 App，使 Keyboard Extension 建立新会话。

### Xcode 报找不到目标模拟器

确认打开的是 `iOS/WindWhisperiOS.xcodeproj`，而不是仓库根目录的
`WindWhisperInputMethod.xcodeproj`。顶部 scheme 应选择宿主 App `WindWhisper`；
`windwhisper` 是 macOS 输入法，`WindWhisperKeyboard` 是不能单独安装运行的扩展。

使用 `xcrun simctl list devices available` 获取准确设备名称，并替换构建命令中的
`iPhone 17 Pro`。如果没有可用设备，在 Xcode 的 Settings → Components 中安装对应 iOS runtime。
