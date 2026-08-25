# 决策记录

本文件是轻量 ADR 索引。新决策按 `ADR-XXX` 追加，包含日期、状态、背景、选择、替代方案和后果；不得静默修改已生效决策。

## 已接受

### ADR-001：系统前端使用 InputMethodKit

- 状态：已接受
- 理由：原生接入 macOS 文本输入体系，按系统会话模型处理输入。

### ADR-002：输入内核使用 librime

- 状态：已接受
- 理由：复用成熟的组合、候选、部署、词典、用户词频和 schema 能力。

### ADR-003：候选窗采用原生 AppKit 毛玻璃

- 状态：已接受
- 选择：非激活 `NSPanel` + `NSVisualEffectView` + 自定义候选布局。
- 后果：获得完整视觉控制，但必须自行保证焦点、定位、点击、分页和可访问性。

### ADR-004：双拼与辅码属于 Rime 数据层

- 状态：已接受
- 理由：避免前端与 schema 产生两套输入规则，保持 Rime 生态兼容。

### ADR-005：M0 完成前禁止编码

- 状态：已履行
- 理由：用户已审阅规划并于 2026-08-24 明确确认开始编码。

### ADR-006：M1 工程标识

- 日期：2026-08-24
- 状态：已由 ADR-014 替代
- 选择：工作名 `RimeInputMethod`，Bundle ID `com.shendongchun.RimeInputMethod`，首个输入模式 ID `com.shendongchun.RimeInputMethod.Hans`。
- 理由：与用户现有 `com.shendongchun.*` 工程命名惯例一致，并保持输入源命名空间稳定。

### ADR-007：最低系统与架构

- 日期：2026-08-24
- 状态：已接受
- 选择：最低 macOS 13；Debug 构建当前架构，Release 固定为 arm64 + x86_64 通用构建。
- 验证：Xcode 26.4.1 Debug/Release 编译通过，Release 两个架构均可执行 `--diagnose`。

### ADR-011：开发阶段用户级安装

- 日期：2026-08-24
- 状态：已接受
- 选择：M1 开发安装目标为当前用户的 `~/Library/Input Methods`；安装前校验 Bundle ID，已有版本先备份；卸载移动到废纸篓。
- 后果：不需要写入系统级 `/Library/Input Methods`，但安装和启用仍需用户明确授权。

### ADR-014：macOS 26 本机开发注册流程

- 日期：2026-08-24
- 状态：已接受
- 背景：旧标识曾以不完整的 controller/资源元数据注册，可能留下无效缓存；开发目录中的同 ID `.app` 副本也会污染 TIS/LaunchServices。
- 选择：开发 Bundle ID 使用全新且含独立 `inputmethod` 段的 `com.shendongchun.inputmethod.rime.dev`，模式 ID 为其 `.Hans` 子项；controller 使用真实 Swift 运行时类名 `RimeInputMethod.RimeInputController`；本机安装采用 ad-hoc 本地签名，不上传构建包。
- 安装：只保留 `~/Library/Input Methods/RimeInputMethod.app` 一份；按父输入法、子输入模式顺序启用并刷新当前登录会话，不要求注销或重启。
- 后果：开发安装不需要 Apple 公证凭据；Developer ID、公证与 Gatekeeper 验证留到 M9 分发阶段。

### ADR-015：锁定官方 librime 1.16.0 universal 产物

- 日期：2026-08-24
- 状态：已接受
- 选择：固定 librime tag `1.16.0`、commit `a251145d3aafa33871824a40bbec04c966bd8b56` 和官方 `rime-a251145-macOS-universal.tar.bz2`；归档 SHA-256 为 `e4c9a8767a456f2550f1242921b7656c6e6be088c89a921274bd5d4404f58b99`。
- 集成：应用只嵌入核心 `librime.1.dylib`，不加载 Lua、octagram、predict 插件；构建不依赖 Homebrew，`Scripts/fetch-librime.sh` 可从官方来源按校验值恢复依赖。
- 数据：M2 从同一 tag 的 `data/minimal` 引入固定基础数据；M6 已在 ADR-023 中确定产品词库、双拼和辅码发布范围。
- 验证：库和 Release 应用均含 arm64/x86_64；`otool` 只显示系统库；Debug、Release、已安装 bundle 的输入/候选/提交测试通过。

### ADR-016：Rime 数据目录隔离

- 日期：2026-08-24
- 状态：已接受
- 选择：shared data 使用 bundle 内 `Resources/Rime`；正式 user data 使用 `~/Library/Application Support/com.shendongchun.inputmethod.rime.dev/Rime`；staging 为其 `build` 子目录；日志使用对应 `~/Library/Logs` 目录。
- 测试：M2 smoke 使用 `/private/tmp` 下的独立临时根目录并在测试后清理，不接触鼠须管或正式用户词典。
- 后果：应用更新不会覆盖用户 `.custom.yaml` 和用户词典；Bundle ID 正式化时需要制定一次明确的数据迁移策略。

### ADR-017：本机 ad-hoc 构建暂不启用 Hardened Runtime

- 日期：2026-08-24
- 状态：已接受
- 背景：ad-hoc 签名的通用 Release 主程序与嵌套 dylib 在 Hardened Runtime 下会因 Team ID 不一致被 dyld 拒绝；这与 Apple 公证无关。
- 选择：本机 Debug/Release 均关闭 Hardened Runtime，并对嵌套 dylib 与 app 依次 ad-hoc 签名。M9 使用真实 Developer ID 时重新开启并执行正式签名、公证和 Gatekeeper 验证。
- 后果：当前方案仅面向用户已确认的本机开发使用，不代表正式分发安全配置。

### ADR-018：M3 快捷键、会话与停用策略

- 日期：2026-08-24
- 状态：已接受
- 选择：每个 `IMKInputController` 持有一个 Rime session，进程内所有 librime 调用通过服务级递归锁串行化；Command、Control、Option 组合直接透传，Shift 与 Caps Lock 传入 Rime。
- 组合：有 composition 时使用 `setMarkedText`，有 commit 时使用 `insertText`；Backspace 编辑组合，Escape 清空组合，Space/Return 交给 Rime 决定提交。
- 生命周期：client 请求提交、输入源停用或 controller 关闭时提交当前转换结果并清理 marked text；引擎或 session 不可用时安全透传。
- 验证：Debug/Release `--m3-smoke` 覆盖键位、快捷键、组合编辑、中文提交和生产 `IMKTextInput` 更新器；真实 TextEdit 输入仍保留人工门禁。

### ADR-019：本机签名先处理嵌套运行库

- 日期：2026-08-24
- 状态：已接受
- 背景：对 app 主可执行文件签名前，嵌入的 linker-signed librime 仍可能被 `codesign` 判定为未完整签名。
- 选择：安装脚本固定按“Frameworks 内嵌代码 → MacOS 主程序 → app bundle”顺序进行 ad-hoc 签名，再执行 deep/strict 校验。
- 后果：每次 M3 热安装都能原子替换当前用户版本，无需注销、重启或 Apple 公证凭据。

### ADR-020：产品品牌采用“风语”及原创图标

- 日期：2026-08-24
- 状态：已接受
- 选择：用户可见产品名统一为“风语”；主图标采用原创的蓝青色风带与对话气泡组合。输入法菜单图标使用系统输入源一致的 22×16pt 黑色圆角徽标，以透明镂空呈现居中的“风”字，不使用 Rime/鼠须管图标或其视觉元素。
- 本地化：为父输入法 ID 与简体输入模式 ID 同时提供 `zh-Hans`、`zh_CN`、`en` 名称映射，避免菜单显示内部 Bundle ID。
- 缓存：菜单图标与 `Ctrl+Space` 切换器图标使用独立资源名；切换器资源名带版本。热安装同时刷新 `TextInputMenuAgent`、`TextInputSwitcher` 与光标提示器 `CursorUIViewService`，让 macOS 的三套输入源界面都从当前 TIS 注册记录重新读取名称和图标，无需注销。
- 兼容：内部 Xcode target、可执行文件、安装包目录、Bundle ID、输入模式 ID 与 Rime 用户数据路径保持不变。
- 后果：当前登录会话可继续热更新，不产生第二个输入源，不重置用户配置或词库；未来正式改 Bundle ID 时另行设计迁移。
- 验证：工程校验脚本检查显示名、新图标文件和旧图标引用；Debug/Release 构建检查最终 bundle 的 `Info.plist` 与资源清单。

### ADR-021：M4 使用自定义非激活基线候选面板

- 日期：2026-08-24
- 状态：已接受
- 选择：M4 使用 `.nonactivatingPanel` 的 `NSPanel` 和轻量自绘候选列表，以非激活窗口样式保持宿主焦点。系统 `IMKCandidates` 仅作为行为对照，不作为最终界面依赖。
- 状态所有权：页码、候选和高亮只来自不可变 Rime 快照；鼠标点击只回传本页候选索引，由 controller 调用 Rime 后重新读取快照。CandidateWindow 不访问引擎、不提交文本。
- 定位：优先从 `IMKTextInput.attributes(forCharacterIndex:lineHeightRectangle:)` 获取当前输入行矩形；`firstRect` 仅作为多级兼容回退。随后按该矩形选择对应显示器的 visible frame，默认向下展开，空间不足向上翻转，最终约束在可见区域内。
- 视觉边界：M4 只建立可用、可测的系统色基线；`NSVisualEffectView`、毛玻璃材质、横排视觉和可访问性主题细化属于 M5。
- 验证：Debug/Release `--m4-smoke` 覆盖模型、鼠标命中、非激活约束、多屏边界、Rime 高亮、翻页和选择；真实 TextEdit 焦点与鼠标体验保留人工门禁。

### ADR-022：M5 首版采用原生横排毛玻璃布局

- 日期：2026-08-24
- 状态：已接受
- 选择：macOS 26 候选窗根视图使用 `NSGlassEffectView` 的 `.clear` 样式，连续圆角由系统玻璃自身生成，并关闭会产生矩形尖角的 panel 阴影；macOS 13—15 回退到 `NSVisualEffectView` 的 `.popover` 材质、`.behindWindow` 混合和 `.active` 状态。首版只交付横排布局，竖排作为后续可选策略，不阻塞 M6。
- 主题：动态系统色与系统强调色为唯一颜色来源；降低透明度切换到不透明系统背景，增强对比度加强边框和实色高亮，减少动态效果完全关闭淡入。
- 布局：面板宽度限制在 220—760pt，候选按内容测量后公平压缩；短正文获得优先保留宽度，注释/辅码和超长正文再分别尾部截断。候选命中区域、页码和翻页按钮由同一纯布局模型生成，避免绘制与点击坐标漂移。
- 交互：点击候选、点击翻页、滚轮/触控板翻页均只产生 `CandidateWindowAction`，controller 再调用 Rime 并读取新快照；首次显示允许 80ms 可中断淡入，输入更新与隐藏不等待动画。
- 验证：`--m5-smoke` 覆盖主题降级、布局边界、长文本、材质配置，以及浅/深色和普通/无障碍模式的离屏渲染。

### ADR-023：M6 内置方案、词库与独立辅码模式

- 日期：2026-08-25
- 状态：已接受
- 方案：默认使用“小鹤双拼”，同时内置风语全拼、自然码、微软和智能 ABC；仓颉保留为兼容方案。双拼配置固定到 `rime/rime-double-pinyin` commit `01a13287cbd27819be1c34fa1ddc1b3643d5001b`。默认值由用户于 2026-08-25 明确指定。
- 辅码：使用 `;` 进入独立模式，编码为“完整拼音＋仓颉首码”。索引由锁定的 `luna_pinyin.dict.yaml` 和 `cangjie5.dict.yaml` 生成，不在 Swift 前端转换；正常全拼和纯双拼不受影响。
- 数据保护：bundle 内 shared data 与 Application Support 下的 user data 保持隔离；桥接层只允许切换到部署清单中的方案。全量重新部署不得覆盖 `.custom.yaml` 和 `luna_pinyin.userdb`。
- 许可：官方双拼配置及其风语适配按 GPL-3.0 随附；基础 Rime 数据及派生索引的来源、许可和修改记录见 `Resources/Rime/DATA_LOCK.json`、`docs/RIME_DATA.md` 与 `LICENSES/`。
- 验证：`Scripts/test-m6.sh` 覆盖五套方案语料、辅码候选从 7 个缩到 1 个、候选注释、缺失方案拒绝、纯双拼无回退、用户数据升级保护与生成结果复现。

### ADR-024：M7 使用 InputMethodKit 菜单与进程内持久化设置

- 日期：2026-08-25
- 状态：已接受
- 入口：复用 `IMKInputController.menu()` 提供的系统输入法菜单，不新增长期占用菜单栏空间的独立状态项。
- 设置：方案、全/半角、简繁、横/竖排和系统/浅色/深色主题保存到输入法自身 `UserDefaults`；未知值回退到小鹤双拼、半角、简体、横排和跟随系统。
- 一致性：变更通知发给进程内所有 controller；每个 controller 先提交现有组合，再对自己的 Rime session 应用同一快照。重新部署先释放 session，后台完成后重建。
- 维护：提供重新部署、打开用户目录、脱敏诊断和恢复默认设置。恢复默认不删除用户词典或 `.custom.yaml`；诊断不包含输入内容、候选、提交文本、完整用户路径或原始引擎错误。
- 简繁数据：随包加入 OpenCC 1.1.9 的 `t2s` 配置和词典，来源为与当前 librime 配套的官方 Squirrel 1.1.2 发布包，并固定包及文件 SHA-256。
- 验证：`Scripts/test-m7.sh` 覆盖持久化、多 session、组合保护、真实繁简转换、横竖布局、菜单、诊断和重置。

## 待用户确认

- ADR-013：正式发布签名、notarization 与分发渠道。


## 决策模板

```text
### ADR-XXX：标题
- 日期：YYYY-MM-DD
- 状态：提议 / 已接受 / 已替代
- 背景：
- 选择：
- 替代方案：
- 后果：
- 验证方式：
```
