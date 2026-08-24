# 风语

一个原生 macOS 中文输入法工程：产品名为“风语”，使用 InputMethodKit 连接 macOS 文本输入系统，以 librime 作为输入内核，并提供支持 Rime 词库、双拼和辅码的原生毛玻璃候选窗。

## 当前状态

**M1—M4 已完成实现和自动化验收；当前等待 M4 候选窗的 TextEdit 人工体验确认。**

应用现已自带官方 librime 1.16.0、最小 Rime 全拼测试数据和窄 C/Swift 桥接。InputMethodKit controller 已连接每会话 Rime session，可处理字母、数字选词、Space、Return、Backspace、Escape、方向键与 PageUp/PageDown，并通过 `setMarkedText` 显示行内组合、通过 `insertText` 提交中文。Command、Control、Option 组合保持透传。M4 已加入不抢焦点的原生候选面板，显示页码、候选序号、注释和 Rime 高亮；鼠标点击与键盘选词共用同一 Rime session，面板会跟随插入点、跨屏选择可见区域并在空间不足时翻转。

本机为 Apple Silicon，Debug 只构建 arm64；Release 应用和内置 librime 都包含 arm64 + x86_64。安装脚本使用本地签名、父输入法/子模式分阶段启用和当前会话热刷新；M3 最终 Debug 构建已成功热安装，没有上传构建包、注销或重启，并恢复了安装前使用的鼠须管输入源。

## 已确定方向

- 前端：Swift + AppKit + InputMethodKit
- 输入内核：librime C API
- 配置生态：Rime schema、词典、用户词典与部署机制
- 输入方案：全拼与多种双拼；辅码通过 schema/translator/filter 组合实现
- 候选窗：原生 AppKit 非激活面板，使用 `NSVisualEffectView` 呈现 macOS 毛玻璃效果
- 原则：前端只负责系统适配与表现，输入算法和数据能力尽量留在 Rime 层

## 文档入口

- [DEVELOPMENT_PLAN.md](DEVELOPMENT_PLAN.md)：完整实施计划、阶段门禁与验收标准
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)：系统边界、组件关系与关键数据流
- [docs/PRODUCT_SPEC.md](docs/PRODUCT_SPEC.md)：首版产品范围与交互要求
- [docs/TEST_PLAN.md](docs/TEST_PLAN.md)：测试矩阵、兼容性和发布验收
- [docs/DECISIONS.md](docs/DECISIONS.md)：已确定决策、待确认事项和 ADR 规则
- [docs/AI_AGENT_GUIDE.md](docs/AI_AGENT_GUIDE.md)：后续 AI Coding Agent 的执行约束

## 构建与验证

要求 Xcode 26 或兼容版本：

```bash
./Scripts/verify-project.sh
./Scripts/build.sh Debug
./Scripts/build.sh Release
./Scripts/test-rime-bridge.sh Debug
./Scripts/test-rime-bridge.sh Release
./Scripts/test-m3.sh Debug
./Scripts/test-m3.sh Release
./Scripts/test-m4.sh Debug
./Scripts/test-m4.sh Release
```

`test-rime-bridge.sh` 会在 `/private/tmp` 创建隔离数据目录，验证应用内嵌运行库、签名、动态依赖、部署、候选和提交闭环，然后清理该测试目录。`test-m3.sh` 进一步验证按键映射、快捷键透传、组合编辑以及生产 `IMKTextInput` 更新路径。`test-m4.sh` 覆盖候选模型、鼠标命中、非激活面板约束、多显示器定位、边界翻转，以及真实 librime 高亮、翻页和语义选择。需要从官方发布重新恢复锁定依赖时执行：

```bash
./Scripts/fetch-librime.sh
```

该脚本只访问 librime 官方 GitHub Release/源码文件，并逐项验证固定 SHA-256；正常构建不访问网络，也不要求安装 Homebrew。

Release 构建固定生成 arm64 + x86_64 通用产物。构建结果位于：

```text
build/DerivedData/Build/Products/<Configuration>/RimeInputMethod.app
```

本机开发安装不需要 Apple 公证凭据。每次验证只需：

```bash
./Scripts/build.sh Debug
./Scripts/install-user.sh Debug
```

脚本会完成本地签名、用户级原子替换、注册、启用和当前登录会话刷新。成功后不会注销，并恢复安装前选中的输入法。卸载使用：

```bash
./Scripts/uninstall-user.sh
```

卸载脚本不会直接删除应用，而是验证 Bundle ID 后移动到废纸篓。

安装固定使用 `~/Library/Input Methods/RimeInputMethod.app`，并拒绝同 Bundle ID 的系统级重复副本。Debug 只包含 arm64，不会启动 Rosetta 或触发 Intel App 兼容提示；通用 Release 产物仍保留给后续分发验证。

## 工程目录

工程已按规划分层；未进入当前里程碑的目录仍保留占位文件：

```text
RimeInputMethod/
├── App/                    # InputMethodKit 进程入口与生命周期（M1 已实现）
├── Sources/
│   ├── InputController/    # M3/M4 按键映射、IMK 会话、文本与候选协调
│   ├── RimeBridge/         # M2 已实现的 C shim、Swift RAII 与快照模型
│   ├── CandidateWindow/    # M4 基线非激活候选窗；M5 加入毛玻璃视觉
│   ├── Configuration/      # 配置解析与设置模型
│   ├── Installer/          # 注册命令和输入源元数据
│   └── Shared/             # 通用模型、日志、工具
├── Resources/
│   ├── Rime/               # 随包发布的 schema/词典源文件
│   └── Assets/             # 图标与视觉资源
├── Tests/
│   ├── Unit/
│   ├── Integration/
│   └── Manual/
├── Vendor/                 # librime 1.16.0 锁定产物、headers 与校验元数据
├── Scripts/                # 构建、安装、卸载、验收脚本
└── docs/
```

## 已采用的工程标识

- 产品显示名：风语
- 内部工程名：`RimeInputMethod`（为保持安装、输入源注册和用户数据兼容而保留）
- 开发 Bundle ID：`com.shendongchun.inputmethod.rime.dev`
- 简体输入模式 ID：`com.shendongchun.inputmethod.rime.dev.Hans`
- 最低版本：macOS 13
- Release 架构：arm64 + x86_64

默认双拼方案、首版辅码规则、词库来源与正式分发签名仍需在对应里程碑前确认。

## 品牌资源

- 主应用图标：`Resources/Assets/FengYuIconMaster.png`
- macOS App Icon 资源：`Resources/Assets.xcassets/AppIcon.appiconset`
- 输入法菜单图标：`Resources/FengYuInputModeIcon.pdf`（22×16pt 黑底、镂空白字输入源徽标）
- `Ctrl+Space` 切换器图标：`Resources/FengYuInputSwitcherIcon-v1.pdf`（独立版本名用于刷新系统图标缓存）

“风语”使用原创的风带与对话气泡组合标识，不使用 Rime/鼠须管图标或其视觉元素。
