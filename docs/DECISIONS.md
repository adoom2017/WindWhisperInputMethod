# 决策记录

## ADR-001：原生 macOS 输入法前端

- 状态：已接受
- 使用 InputMethodKit 管理系统会话，候选窗使用非激活 AppKit 面板，保持宿主应用焦点。

## ADR-002：原生 Swift 输入引擎

- 状态：已接受
- 输入组合、双拼转换、候选排序和用户词条均在 Swift 内完成，不依赖外部动态库、external runtime 或运行时部署工具。
- `NativeRuntime` 负责进程级服务，`InputSession` 负责会话级状态。

## ADR-003：单一合并词库

- 状态：已接受
- 应用只携带 `Resources/fy.dict.yaml`，每行保存词条、编码、权重、来源和原始顺序。
- 候选排序依次按完整编码、权重降序和原始顺序升序处理；自定义词条使用用户目录的 `custom_words.tsv`。
- 词库 SHA-256 由 `Scripts/verify-project.sh` 锁定，资源变更必须同步更新校验值和验证记录。

## ADR-004：内置输入模式

- 状态：已接受
- 默认“小鹤双拼（音形辅码）”，并提供“小鹤双拼（纯音码）”和“风语全拼”。
- 模式标识使用风语自身的 `flypyShape`、`flypyPhonetic` 和 `fullPinyin`，不暴露其他输入法的 schema 命名。

## ADR-005：用户数据隔离

- 状态：已接受
- 只读词库位于应用包 `Contents/Resources`；用户词条和设置位于
  `~/Library/Application Support/com.shendongchun.inputmethod.windwhisper/User`；日志单独存放。
- 启动时只创建缺失的用户文件，不覆盖已有词条或设置。
- 自定义词管理界面保存后重新读取用户词条；新服务构建成功后才替换旧服务，失败时保持现有输入能力。

## ADR-006：设置与降级

- 状态：已接受
- 设置通过输入法菜单和 `UserDefaults` 持久化，未知值回退到产品默认。
- 词库加载失败时输入事件透传、候选窗隐藏，并输出不含输入内容的诊断状态。

## ADR-007：构建与发布

- 状态：已接受
- 最低 macOS 13；Debug 使用本机架构，Release 构建 arm64 与 x86_64。
- 发布包包含应用、许可证、安装说明、发布说明和版本校验清单；校验脚本拒绝源码泄漏和未声明外部依赖。
