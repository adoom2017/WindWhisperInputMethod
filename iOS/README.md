# iOS 编译、打包与使用

## 环境要求

- iOS 17 或更高版本
- Xcode 26 或兼容版本
- 模拟器运行需要安装对应的 iOS runtime
- XcodeGen（`brew install xcodegen`）
- 真机安装和分发需要有效的 Apple 开发签名

以下命令均从仓库根目录执行。

## 准备工程

可直接打开 `iOS/WindWhisperiOS.xcodeproj`。修改工程配置时，编辑 `iOS/project.yml` 后重新生成：

```bash
xcodegen generate --spec iOS/project.yml
```

更新共享词库后，重新生成 iOS 词库：

```bash
./Scripts/generate-ios-dictionary.sh
```

## 编译与模拟器安装

```bash
xcodebuild \
  -project iOS/WindWhisperiOS.xcodeproj \
  -scheme WindWhisper \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/iOSDerivedData \
  build CODE_SIGNING_ALLOWED=NO
```

产物：`build/iOSDerivedData/Build/Products/Debug-iphonesimulator/WindWhisper.app`。

在 Xcode 中选择 `WindWhisper` scheme 和一个 iPhone 模拟器，按 `Command-R` 安装并运行。
不要选择无法单独安装的 `WindWhisperKeyboard` 扩展。没有可用模拟器时，
在 Xcode 的 Settings → Components 中安装 iOS runtime。

## 真机安装

1. 在 Xcode 的 Signing & Capabilities 中，为 `WindWhisper` 和 `WindWhisperKeyboard`
   选择同一个 Development Team。
2. 为两个目标配置可用的 Bundle ID 和 `group.com.shendongchun.windwhisper` App Group。
   如需替换标识，同步修改 `iOS/project.yml`、两个 entitlements 文件及源码中的对应标识，再生成工程。
3. 连接已开启开发者模式的 iPhone，选择该设备并运行 `WindWhisper` scheme。
4. 首次运行时按系统提示信任开发者证书。

## 打包与分发

完成签名配置后，在 Xcode 中选择 `WindWhisper` scheme 和通用 iOS 设备目标，
执行 Product → Archive。也可在命令行归档：

```bash
xcodebuild \
  -project iOS/WindWhisperiOS.xcodeproj \
  -scheme WindWhisper \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/WindWhisperiOS.xcarchive \
  archive
```

在 Xcode Organizer 中打开归档，选择 Distribute App，根据账号权限上传至
App Store Connect / TestFlight，或导出用于已注册设备的安装包。
模拟器构建产物不能直接安装到 iPhone。

## 启用与使用

1. 打开宿主 App，选择“小鹤音形”“小鹤双拼”或“风语全拼”。
2. 在“设置 → 通用 → 键盘 → 键盘 → 添加新键盘”中添加“风语”。
3. 进入风语的键盘设置，开启“允许完全访问”。
4. 在备忘录等普通文本框中，长按系统键盘的地球图标并选择风语。

- 输入编码后，点击候选或按空格提交中文；横向滚动候选栏查看更多候选。
- 按回车直接提交当前英文编码并清空候选，不额外换行；无编码时正常换行。
- 按退格删除一个未提交编码；没有编码时删除正文文字。
- 点击“中英”切换输入模式。
- 修改输入方案后若未生效，切换键盘或重新打开输入 App。

### 自定义词组

仅小鹤音形使用自定义词组。在宿主 App 打开“自定义词组”，点击加号，填写词组和
1～4 个英文字母的快捷编码。点击已有词组可编辑，向左滑动可删除。
编码自动保存为小写，同词组和编码不能重复添加。

保存后键盘自动加载更新，无需重装。自定义词组保存在设备本地，需开启“允许完全访问”。

## 常见问题

- **找不到风语键盘**：确认已安装宿主 App；必要时删除 App 后重新安装，再添加键盘。
- **键盘显示“引擎不可用”**：检查扩展是否包含 `fy.dict.yaml`，并确认两个目标的 App Group
  配置一致。修改权限配置后需重新签名安装。
- **升级后仍显示旧版本**：在系统键盘设置中移除风语并重新添加，必要时重装宿主 App。
- **密码框或部分 App 无法使用**：iOS 会在安全文本框等场景切换到系统键盘，App 也可禁止第三方键盘。
