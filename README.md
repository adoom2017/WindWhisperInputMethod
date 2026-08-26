# 风语

一个原生 macOS 中文输入法工程：产品名为“风语”，使用 InputMethodKit 连接 macOS 文本输入系统，以 librime 作为输入内核，并提供支持 Rime 词库、双拼和辅码的原生毛玻璃候选窗。

## 当前状态

**M1—M7 已完成实现和自动化验收；当前版本已进入 M7 本机使用确认。**

应用现已自带官方 librime 1.16.0、Rime 基础词库、风语全拼、自然码双拼、小鹤双拼（音形辅码与纯音码）、微软双拼、智能 ABC 双拼、OpenCC 1.1.9 繁简转换数据和可复现生成的辅码索引。InputMethodKit controller 已连接每会话 Rime session，可处理字母、数字选词、Space、Return、Backspace、Escape、方向键与 PageUp/PageDown，并通过 `setMarkedText` 显示行内组合、通过 `insertText` 提交中文。单按左 Shift 可切换中英文，并在插入点附近短暂显示带强调色徽章的“中/英”玻璃指示器；右 Shift 保持 `noop`，Shift 与字母或系统快捷键组合时不会误切换，中文模式下 `Shift+数字/标点` 可正常输入上档符号。候选面板不抢焦点并跟随插入点；macOS 26 使用系统 `NSGlassEffectView` clear 玻璃，旧系统回退到 `NSVisualEffectView`。窗口使用与状态指示器一致的 48pt 紧凑视觉，选中项采用浅强调色底、细描边与实色数字徽章；仅在需要翻页时显示分页胶囊，单页会回收其空间。鼠标点击、滚轮翻页和键盘选词共用同一 Rime session。M7 已加入持久化设置菜单，可切换方案、全/半角、简繁、横/竖排和系统/浅色/深色主题，并提供重新部署、用户目录、脱敏诊断和恢复默认设置。

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
./Scripts/test-m5.sh Debug
./Scripts/test-m5.sh Release
./Scripts/test-m6.sh Debug
./Scripts/test-m6.sh Release
./Scripts/test-m7.sh Debug
./Scripts/test-m7.sh Release
```

`test-rime-bridge.sh` 会在 `/private/tmp` 创建隔离数据目录，验证应用内嵌运行库、签名、动态依赖、部署、候选和提交闭环，然后清理该测试目录。`test-m3.sh` 进一步验证按键映射、快捷键透传、单按 Shift 中英文切换、Shift 组合键防误触、组合编辑以及生产 `IMKTextInput` 更新路径。`test-m4.sh` 覆盖候选模型、鼠标命中、非激活面板约束、多显示器定位、边界翻转，以及真实 librime 高亮、翻页和语义选择。`test-m5.sh` 覆盖主题降级、横向布局、长文本压缩、macOS 26 原生玻璃与旧系统材质回退配置，以及浅色/深色和普通/无障碍组合的离屏视觉快照。`test-m6.sh` 验证 6 套拼音输入方案固定语料、小鹤形码逐键缩小候选、`ubu → 是不是`、`hdui → 还是`、四码自动提交不退化、独立辅码注释、缺失方案保护、用户词典/覆盖文件升级保护，以及两类辅码词典的可复现生成。`test-m7.sh` 验证设置持久化、损坏值回退、多 session 同步、组合提交保护、真实繁简转换、横竖排布局、完整菜单、脱敏诊断和恢复默认值。需要从官方发布重新恢复锁定依赖时执行：

```bash
./Scripts/fetch-librime.sh
```

该脚本只访问 librime 官方 GitHub Release/源码文件，并逐项验证固定 SHA-256；正常构建不访问网络，也不要求安装 Homebrew。

Release 构建固定生成 arm64 + x86_64 通用产物。构建结果位于：

```text
build/DerivedData/Build/Products/<Configuration>/windwhisper.app
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

安装固定使用 `~/Library/Input Methods/windwhisper.app`，并拒绝同 Bundle ID 的系统级重复副本。首次从旧身份升级时，macOS 会要求在“系统设置 > 键盘 > 文本输入 > 编辑”中授权一次；授权完成前安装器会保留并恢复旧输入法，不会让当前输入源失效。Debug 只包含 arm64，不会启动 Rosetta 或触发 Intel App 兼容提示；通用 Release 产物仍保留给后续分发验证。

## 工程目录

工程已按规划分层；未进入当前里程碑的目录仍保留占位文件：

```text
RimeInputMethod/
├── App/                    # InputMethodKit 进程入口与生命周期（M1 已实现）
├── Sources/
│   ├── InputController/    # M3—M5 按键映射、IMK 会话、文本与候选协调
│   ├── RimeBridge/         # M2 已实现的 C shim、Swift RAII 与快照模型
│   ├── CandidateWindow/    # M4/M5 非激活候选窗、布局、主题与毛玻璃视觉
│   ├── Configuration/      # M7 持久化设置、输入法菜单、诊断与验收
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

- 中文显示名：风语
- 英文名、构建目标与应用包：`windwhisper`
- Xcode 工程容器：`RimeInputMethod.xcodeproj`（只作为源码工程文件名保留）
- Bundle ID：`com.shendongchun.inputmethod.windwhisper.local`
- 简体输入模式 ID：`com.shendongchun.inputmethod.windwhisper.local.Hans`
- 最低版本：macOS 13
- Release 架构：arm64 + x86_64

默认方案为“小鹤双拼（音形辅码）”；同时保留纯音码小鹤双拼、风语全拼、自然码、微软和智能 ABC 双拼。小鹤方案直接在两键音码后追加一至两位小鹤形码；原有 `;`＋全拼＋仓颉首码作为其他拼音方案可用的独立辅助入口继续保留。正式分发签名仍留到 M9 决策。

## 输入方案与辅码

- 默认：小鹤双拼（音形辅码）。主词典直接复用 `rime-origin/build` 的三个预编译文件，不再根据公开词表推导。例如 `ni → 你`、`nir → 倪`、`nirx → 你`（自动上屏），行为与原始码表一致。
- 简码、短语与候选顺序：全部以原始 bin 为准；固定回归包括 `w → 我/位`、`d → 的/打`、`u → 是/时`、`ubu → 是不是`、`hdui → 还是`、`biru → 比如`。
- 四字词：直接使用原始主词典及 `top/sys/user/full` 的层级，例如 `ahqi` 首选“昂起”，`sys` 中“爱恨情仇”为后续候选。
- 词库层级：`top` 用于置顶词，`sys` 包含符号编码与二重简码，`user` 用于日常用户词，`full` 补全全码字；四者都由 Rime 独立加载，不再重复合并进主词典。
- 纯音码：菜单中保留“小鹤双拼（纯音码）”，例如“你好”输入 `nihc`。
- 设置入口：切换到“风语”后点击菜单栏输入法图标，即可在风语菜单中切换方案、全角、简繁、候选排列和主题；设置会立即同步到所有会话并在重启后恢复。
- 其他方案：风语全拼、自然码、微软、智能 ABC 和仓颉五代均列在“输入方案”顶层分组中，可直接选择。
- 通用辅码：在其他拼音方案中可先输入 `;`，再输入完整拼音和可选的仓颉首码，例如 `;zuok` 定位“左”。它与小鹤音形四码互不干扰。
- 中英文：遵循原配置：左 Shift 为 `commit_code`，右 Shift、Caps Lock 不执行切换；Control/Option 快捷键交给 Rime 处理。
- 用户词典和 `.custom.yaml` 保存在 `~/Library/Application Support/com.shendongchun.inputmethod.windwhisper.local/Data`。首次运行时若新目录尚不存在，会从旧目录 `~/Library/Application Support/com.shendongchun.inputmethod.rime.dev/Rime` 完整复制；旧目录保留不删，已有新目录也绝不会被迁移覆盖。
- `/Users/shendongchun/Documents/rime-origin/build` 中的 `flypy.table.bin`、`flypy.prism.bin`、`flypy.reverse.bin` 已逐字节纳入应用，并在部署后强制恢复，避免 librime 重新生成改变候选行为。
- 数据来源、固定提交、许可证和修改见 `Resources/Rime/DATA_LOCK.json`、`docs/RIME_DATA.md` 与 `LICENSES/`。

## 添加自定义词

默认“小鹤双拼（音形辅码）”可直接维护文本词库：

1. 切换到“风语”，在输入法菜单选择“打开用户目录”。
2. 用 UTF-8 纯文本编辑器打开 `flypy_user.txt`；普通自定义词加在这个文件末尾，需要置顶的词加到 `flypy_top.txt`。
3. 每行写成 `词条<Tab>编码`，可选第三列权重，例如 `词条<Tab>编码<Tab>100`。分隔符必须是真正的 Tab，不能用空格替代。
4. 保存后在输入法菜单选择“重新部署输入引擎”，新词即可生效。

不要编辑用户目录内的 `build/`；它是可重新生成的部署结果。正常选词产生的词频学习会自动写入用户数据库，无需手工维护。当前手工文本入口针对默认小鹤方案，其他拼音方案仍会自动学习用户选词。

## 设置与维护

- “全角字符”未勾选时为半角；“简体中文”未勾选时为传统汉字。
- 候选排列可选横排或竖排；主题可跟随系统，或固定浅色/深色。降低透明度等系统辅助功能仍有最高优先级。
- “重新部署输入引擎”会先提交当前组合，再在后台部署配置；完成后自动恢复输入 session。
- “查看脱敏诊断”只显示版本、设置和目录是否存在，不包含按键、组合、候选、提交文本或完整用户路径。
- “恢复默认设置”恢复小鹤双拼（音形辅码）、半角、简体、横排和跟随系统主题，不删除用户词典或 `.custom.yaml`。

## 品牌资源

- 主应用图标：`Resources/Assets/WindWhisperIconMaster.png`
- macOS App Icon 资源：`Resources/Assets.xcassets/AppIcon.appiconset`
- 输入源图标：菜单、`Control + Space` 切换器和 palette 统一使用 `Resources/WindWhisperInputIcon-v1.pdf`（22×16pt 黑底白字）。统一资源标识可避免部分宿主在 macOS 光标输入源 HUD 中切换不同图标对象时触发系统兼容问题。

“风语”使用原创的风带与对话气泡组合标识，不使用 Rime/鼠须管图标或其视觉元素。
