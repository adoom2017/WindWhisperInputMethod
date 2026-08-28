# 架构说明

## 架构原则

1. InputMethodKit 处理系统会话；原生 Swift 引擎处理输入语义；候选窗只处理表现与交互。
2. 全局引擎生命周期、每会话生命周期与 UI 生命周期分别管理。
3. 输入引擎内部只暴露值类型快照和语义动作，Swift 业务层不依赖外部运行库。
4. 任何磁盘读取和配置解析都不进入按键热路径，任何 AppKit 更新都回到主线程。
5. 前端不实现双拼或辅码算法，它们由输入引擎根据词库索引处理。

## 组件边界

| 组件 | 输入 | 输出 | 明确不负责 |
|---|---|---|---|
| App/Server | 进程事件、IMK 连接 | controller、全局服务 | 候选布局、编码算法 |
| InputController | NSEvent、client 状态 | commit、marked text、UI 快照 | 绘图、词库解析 |
| InputEngine | 规范化按键、会话动作 | 值类型 context/status/commit | AppKit、窗口定位 |
| CandidateWindow | 候选快照、光标矩形、主题 | 选择/翻页等语义动作 | 引擎访问、文本提交 |
| Configuration | 内置和用户配置 | 类型化配置快照 | 输入事件处理 |
| Installer | bundle 和输入源元数据 | 注册/启用/诊断结果 | 输入算法、候选 UI |

## 关键不变量

- 每个 controller 最多持有一个有效 input engine session。
- session 销毁后，所有异步 UI 快照即使到达也不得再作用于新 session。
- 不使用 Swift `String` 的字符下标直接解释引擎的 UTF-8 byte offset。
- 候选窗不成为 key window，不从宿主应用夺取焦点。
- deactivation 必须隐藏窗口，并按已确认策略提交或清空组合。
- 未被引擎消费的事件必须回到宿主应用。

## 状态机草案

```text
Process Start
  └─ Engine Initializing
       ├─ Ready
       │   ├─ Session Inactive
       │   └─ Session Active
       │        ├─ Idle
       │        ├─ Composing
       │        └─ Selecting Candidate
       └─ Degraded/Error

Session Active ── deactivate ──► hide panel + commit/clear policy
Process Exit   ──► destroy sessions ──► finalize engine
```

## 数据目录策略

- Shared data：应用包内只读资源，仅含合并后的 `fy.dict.yaml`。
- User data：用户可写配置、用户词典、安装信息与覆盖文件。
- Logs：独立目录并可清理；默认不含输入明文。

当前路径：shared data 为应用包的 `Contents/Resources`；user data 为 `~/Library/Application Support/com.shendongchun.inputmethod.windwhisper.local/User`；日志为 `~/Library/Logs/com.shendongchun.inputmethod.windwhisper.local`。命令行集成测试使用 `/private/tmp` 隔离根目录，不读写正式用户数据。

## 输入引擎所有权

- `InputService` 持有进程级原生输入引擎；`InputSession` 强持有 service 并在 `deinit` 释放 session。
- `fy.dict.yaml` 的词条、编码、权重和原始顺序在启动时一次性解析为内存索引。
- Swift 快照只含值类型；组合串的 UTF-8/UTF-16 范围转换集中在 `RangeConverter`。

## M3 输入闭环

- `NativeRuntime` 在输入法进程内持有唯一 `InputService`；启动失败时 controller 退化为事件透传，不吞掉宿主按键。
- 每个 `WindWhisperInputController` 延迟创建并独占一个 `InputSession`；关闭 controller 时先结束组合，再释放 session。
- `InputService` 使用递归锁串行化所有 input-engine 调用，避免多个 InputMethodKit 会话并发进入全局引擎。
- `KeyMapper` 负责 macOS 键盘事件到 input engine/X11 key symbol 的转换；Command、Control、Option 快捷键在进入引擎前透传。
- `ClientUpdater` 是唯一的前端文本写入边界：有 commit 时调用 `insertText`，有 composition 时调用 `setMarkedText`，组合清空时移除 marked text。
- 停用输入源、client 请求提交或 controller 关闭时提交当前转换结果；Escape 明确清空当前组合。

## 候选窗定位

定位函数只接受光标矩形、目标屏幕 visible frame、窗口测量尺寸和布局方向，输出最终 frame。优先向下/右展开，空间不足时翻转，并将最终 frame 约束在当前屏幕可见区域。窗口测量必须在完成文本布局后进行。

## M4/M5 候选窗闭环

- `CandidateWindowModel` 只接收不可变 `MenuSnapshot`，生成页码、1—9 本页序号、候选正文、注释与高亮索引；展示层不持有或查询 input engine session。
- `CandidateWindowCoordinator` 持有 `.nonactivatingPanel`，用非激活窗口样式保持宿主文本焦点；面板仅通过 `CandidateWindowAction` 向 controller 回传语义选择或翻页。
- `WindWhisperInputController` 在文本状态写入 client 后读取插入点屏幕矩形，再刷新候选窗；优先使用 `attributes(forCharacterIndex:lineHeightRectangle:)` 返回的输入行矩形，并以当前插入点、selected range 和 marked range 的 `firstRect` 作为兼容回退。鼠标选择由 controller 调用 session，重新读取完整快照并同时更新文本和窗口。
- 键盘数字、方向键和 PageUp/PageDown 仍经过统一按键映射进入 input-engine。前端不自行计算页码或高亮，因此键盘和鼠标不会形成第二套候选状态。
- controller 停用、关闭、提交、client/session 缺失或快照读取失败时立即隐藏面板，避免跨应用残留。
- macOS 26 以 `NSGlassEffectView` clear 样式作为内容根视图，由系统玻璃直接控制圆角且关闭矩形 panel 阴影；macOS 13—15 回退到 popover / behind-window / active 的 `NSVisualEffectView`。`CandidateWindowTheme` 集中提供圆角、间距、字体、颜色、宽度上限和动画时长，并根据降低透明度、增强对比度和减少动态效果生成安全降级。
- `CandidateHorizontalLayout` 是不依赖 window/session 的纯布局边界：先测量候选正文和注释，再在 760pt 上限内按比例压缩，输出候选、页码和前后翻页命中区域。竖排不进入首版，但布局边界已独立，后续可新增策略而不改 input engine 或 controller。
- 候选窗首次出现只做 80ms 可中断淡入；后续按键更新直接替换快照并重排，隐藏立即执行，因此动画不在输入热路径上形成等待。

## M7 设置、状态与维护

- `FengYuSettingsStore` 是设置唯一来源，使用版本化 `UserDefaults` key 保存方案、全角、简繁、候选方向和颜色主题；未知枚举值自动回退产品默认，不让损坏偏好阻止输入。
- `IMKInputController.menu()` 返回风语设置菜单，设置只出现在系统输入法菜单中，不创建额外常驻状态栏图标。方案、候选排列和候选主题以顶层叶子按分组排列，规避 `TextInputMenuAgent` 不转发嵌套叶子 action 的限制；菜单 target 不访问 marked text 或候选内容。
- 新输入引擎 session 由 `NativeRuntime.makeSession()` 统一应用设置；现有 controller 监听进程内通知，在设置变化前先提交组合，再更新自身 session。刷新配置时先完整加载新词库，成功后原子替换服务并重建所有 session；加载失败则继续使用旧服务。
- Swift 直接设置简繁、全角等运行时选项，不依赖桥接层或外部词库。
- 横排与竖排是两个纯布局策略，共享同一候选模型、绘制、点击和翻页动作；主题只固定系统/浅色/深色 appearance，不绕过系统降低透明度、增强对比度和减少动态效果。
- 脱敏诊断只输出版本、架构、设置值、引擎就绪状态及目录是否存在；不接收输入快照，也不输出完整 Home 路径或 input-engine 原始错误正文。

## M8 性能与可靠性

- `CandidateWindowUpdateGate` 为每个异步候选窗展示或隐藏任务分配单调代次；新任务会使旧任务失效，避免快速切换 client 后旧候选窗重新出现或旧隐藏任务遮掉新候选。
- `InputEngine` 只暴露计数型诊断：活跃 session、桥接快照分配和进程 RSS。诊断不包含按键、组合、候选或提交内容，并复用 service 锁保持一致性。
- M8 smoke 在隔离 user data 中测量 engine 初始化、配置刷新、`process_key + snapshot + 纯布局` 的 P50/P95/P99，并按可配置时长反复创建/销毁 session。
- 快照分配由 C 层在深复制和 `rb_snapshot_clear` 两端配对计数；任何测试结束后的非零余额都直接阻断阶段验收。

## M9 发布与安装事务

- `Scripts/lib/install-transaction.sh` 是用户级安装的原子替换边界，明确区分 source、installing、installed 和 previous 四个路径；完整失败和两个中间失败状态都能恢复旧应用与新构建。
- `package-release.sh` 先构建固定版本/构建号的 universal Release，再按 local、Developer ID signed 或 notarized 模式处理签名。正式模式按 Frameworks、主程序、app 的顺序启用 Hardened Runtime 和可信时间戳。
- 发布目录包含 app、许可证、安装/回滚/卸载说明、发布说明、已知问题和 JSON 版本清单；外层 ZIP 另有 SHA-256。
- `verify-release.sh` 从最终 ZIP 重新解包检查 Bundle ID、版本、arm64/x86_64、动态依赖、清单校验值、源码泄漏、签名链、Hardened Runtime，并在 notarized 模式执行 stapler 与 Gatekeeper。

## 错误降级

- 引擎不可用：输入事件透传，隐藏候选窗，展示不含输入内容的诊断状态。
- 词库加载失败：输入事件透传，隐藏候选窗，并展示不含输入内容的诊断状态。
- client 无效：终止当前 UI 更新，清理 session 前端状态。
- 主题配置损坏：回退系统动态主题，不影响输入。
