# M1 验证记录

日期：2026-08-24  
环境：macOS（Apple Silicon），Xcode 26.4.1，Swift 6.3.1

## 已完成

- Xcode 工程和共享 scheme 可被 `xcodebuild` 正确识别。
- `Resources/Info.plist` 通过 `plutil -lint`。
- InputMethodKit server 入口、应用生命周期和 `IMKInputController` 子类编译通过。
- controller 声明接收 keyDown/flagsChanged，但始终返回 `false`，保持 passthrough。
- 曾用 Release 的 x86_64 slice 完成一次架构诊断；后续本机开发不再启动 Rosetta 版本。
- Debug 构建通过（arm64）。
- Release 构建通过，产物包含 `arm64` 与 `x86_64`。
- Debug/Release 应用通过签名结构校验。
- 源码树不包含第三方动态库或 framework；输入引擎代码完全位于项目自身。
- Debug 进程在非沙箱环境成功创建 InputMethodKit server 并保持运行，随后主动停止。
- 输入模式已补齐矢量菜单图标和 InputMethodKit 图标元数据。
- 最终本机开发流程固定使用 arm64 Debug 与 ad-hoc 本地签名；分发公证留到 M9。

## 实际命令

```text
./Scripts/verify-project.sh
./Scripts/build.sh Debug
./Scripts/build.sh Release
lipo -archs <Release app executable>
codesign --verify --deep --strict <Debug/Release app>
<app executable> --diagnose
arch -x86_64 <Release app executable> --diagnose
```

说明：InputMethodKit 的 NSConnection/Mach 服务不能在受限命令沙箱内注册；同一产物在正常用户会话环境中启动成功。

## 安装测试状态

- 早期不完整元数据与旧 Bundle ID 的测试副本未进入 TIS；相关副本和手工偏好修改已移走或从备份恢复。
- 最终开发标识 `com.shendongchun.inputmethod.windwhisper.local` 使用 ad-hoc 本地签名后，首次调用注册即生成父输入法与 `.Hans` 子模式。
- 父输入法与子模式均达到 `enabled=true`，子模式达到 `selectCapable=true`，并成功切换为当前输入源。
- 已执行第二次完整构建和热替换，注册、启用、临时选择、恢复原输入法全流程再次成功；未注销、未重启、未上传构建包。
- 原生 `NSTextView` 测试宿主通过当前 `NSTextInputContext` 输入 `abc`，结果保持为 `abc`，证明 passthrough 不吞键。
- 自动控制 TextEdit 被系统辅助功能权限拒绝，因此没有为了测试扩大权限；测试结束后恢复原输入源。
- 当前本机安装目标为 `~/Library/Input Methods/windwhisper.app`；Debug 主程序仅包含 arm64。

本机开发安装流程已验收完成，不需要 Apple 公证凭据。M1 仅保留用户在 TextEdit 中人工输入一段文字的最终确认。
