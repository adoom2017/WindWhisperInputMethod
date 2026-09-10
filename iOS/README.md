# WindWhisper iOS 开发与测试

iOS 版本包含两个目标：

- `WindWhisper`：宿主 App，用于选择输入方案、显示安装说明并承载键盘扩展。
- `WindWhisperKeyboard`：`com.apple.keyboard-service` 扩展，负责显示键盘、候选和向当前 App 提交文字。

最低系统版本为 iOS 17。键盘词库随扩展离线打包，输入处理不依赖网络。为兼容第三方键盘
扩展中的系统触感服务，当前版本声明开放访问，并需要用户开启“允许完全访问”。

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

iOS 扩展使用按移动端输入场景裁剪的 `iOS/Resources/fy.dict.yaml`，共享的完整词库不会被修改。
更新完整词库后，先在仓库根目录执行以下命令，再重新生成 Xcode 工程：

```bash
./Scripts/generate-ios-dictionary.sh
```

内置词条的每个字符必须在固定的 8,105 字允许列表 `Resources/allowed_characters.txt` 中。
音形编码最多四码，语料权重不低于 1,000；拼音基础条目也受字表约束。
当前生成结果为音形 74,022 条、拼音 9,510 条、语料 8,545 条，共 92,077 条、
2,951,337 字节。生成器校验字表唯一性、校验和、行格式、条目数和体积，保持原始权重和顺序。
自定义词组不受这个字表限制。字表来源及许可见 `LICENSES/THIRD_PARTY_NOTICES.md`；
当前字表来自 MIT 许可的 `mozillazg/pinyin-data`，替代之前的 8,139 字 GPL 来源版本。
如需从上游重建字表，运行 `ruby Scripts/import-ios-characters.rb`；该脚本使用固定提交和
上游文件校验和，需要网络。常规词库生成仍完全离线。MIT 许可全文随键盘扩展打包，
但不改变合并词库中其他数据来源的再分发限制。

## 无限候选回归

iOS 使用 `candidateLimit: nil`，首次加载 32 条，横向滚动至剩余 8 条时再加载 32 条，
直到查询耗尽。候选栏使用 `UICollectionView` 复用单元，快捷标点共用该视图。
编码区间的排名索引与优先队列逐批产生候选，不会在短码查询时排序或复制全部匹配项。
改码和自定义词刷新会更换查询代次，丢弃旧批次并回到首项；点击使用绝对索引。
桌面端默认候选限制和分页保持不变。

启动一个模拟器后，从仓库根目录运行（可选传入模拟器 UUID）：

```bash
bash Scripts/test-ios-candidates.sh
```

该脚本运行 Release 引擎和 UIKit 测试，覆盖三种方案排序、长句、繁简去重、反查、
四码自动提交、自定义词热更新及表外字符、21,050 条候选耗尽、过期代次拒绝，
以及集合视图滚动复用和第 6/33/末项选词。输出首批和后续批次 P95、测试截图路径。
性能断言分别为 16 ms / 8 ms；模拟器结果不能替代真机 Time Profiler 验收。
测试 App 与正式键盘使用不同 Bundle ID，不会自动启用或替换正式键盘。

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
6. 在第三方键盘列表中选择“风语”，进入该键盘的设置并开启“允许完全访问”。
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
5. 在 iPhone 的“设置 → 通用 → 键盘 → 键盘 → 添加新键盘”中添加“风语”，并在风语的
   键盘设置中开启“允许完全访问”。
6. 在备忘录、信息或 Safari 普通文本框中切换到风语并执行下方用例。

真机能覆盖触摸、内存压力、扩展被系统终止后重启、横竖屏和不同 App 文本代理行为，发布前
不能只依赖模拟器结果。

## 基础验收用例

### 自定义词组（仅小鹤音形）

在宿主 App 打开“自定义词组”，点击右上角加号，填写词组及 1～4 个英文字母的快捷编码。
编码保存时自动转为小写；相同词组和编码不能重复添加。点击已有词组可编辑，向左滑动可删除。
保存后键盘自动加载更新，输入该编码即可选择词组；四码唯一候选遵循小鹤音形的自动上屏规则。
未提交编码仍显示在正文中。键盘可见时由运行时 actor 每 0.5 秒异步检查自定义词库；
按键回调不读取文件。更新会保留当前组合并刷新候选，无需重启扩展。
词库通过 App Group 保存在设备本地，键盘需开启“允许完全访问”。小鹤双拼和风语全拼不加载自定义词组。

引擎回归必须针对 iOS Simulator 编译，并在已启动的模拟器内运行；直接在 macOS 执行不覆盖 iOS 条件代码。Apple Silicon Mac 示例（仓库根目录）：

```bash
xcrun --sdk iphonesimulator swiftc -target arm64-apple-ios17.0-simulator \
  -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  iOS/Keyboard/FengYuSchema.swift Core/SwiftAdapter/InputEnginePlatform.swift \
  Core/SwiftAdapter/InputModels.swift Core/SwiftAdapter/InputService.swift \
  Platform/macOS/Configuration/CustomWords.swift Scripts/ios-custom-phrases-smoke.swift \
  -o /tmp/ios-custom-phrases-simulator
xcrun simctl spawn booted /tmp/ios-custom-phrases-simulator "$PWD/iOS/Resources/fy.dict.yaml"
```

上述引擎测试不验证 Keyboard Extension 的触摸事件、App Group 权限、UIInputViewController 生命周期或正文代理；这些必须在安装后的 iOS 键盘界面验证，不能用编译成功或引擎测试通过代替。

真机验收：添加词组后收起再打开键盘，验证候选和上屏；随后编辑、删除并重复验证。
切换至小鹤双拼和风语全拼，确认不会出现该自定义词组。

### 通用输入

| 场景 | 操作 | 预期结果 |
| --- | --- | --- |
| 键盘加载 | 在普通文本框切换到风语 | 显示字母键、候选区域和中英切换键，无“引擎不可用” |
| 全拼输入 | 选择风语全拼，输入 `nihao` | 组合区显示编码，候选区出现“你好”等候选 |
| 候选提交 | 点击候选或输入编码后按空格 | 候选文字只提交一次，组合区和候选区清空 |
| 编码直接提交 | 输入无中文候选的编码后按回车 | 原样提交英文编码并清空组合，不额外换行；组合为空时回车正常换行 |
| 组合退格 | 输入编码后按退格 | 每次删除一个未提交编码，不删除正文已有文字 |
| 正文退格 | 组合区为空时按退格 | 删除光标前一个正文字符 |
| 中英切换 | 点击“中英”，再输入字母 | 英文模式直接提交字母；再次切换后恢复中文候选 |
| 触感反馈 | 在真机上点击字母、功能键、标点和候选词 | 每次触摸按键时均产生轻微震动，滑出并取消输入时不会重复震动 |
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
