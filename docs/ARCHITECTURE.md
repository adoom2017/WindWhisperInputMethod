# 架构说明

## 架构原则

1. InputMethodKit 处理系统会话；librime 处理输入语义；候选窗只处理表现与交互。
2. 全局引擎生命周期、每会话生命周期与 UI 生命周期分别管理。
3. C API 只在 `RimeBridge` 内出现，Swift 业务层只接触值类型快照和语义动作。
4. 任何耗时部署都不进入按键热路径，任何 AppKit 更新都回到主线程。
5. 前端不实现双拼或辅码算法，它们属于 Rime schema/词典配置。

## 组件边界

| 组件 | 输入 | 输出 | 明确不负责 |
|---|---|---|---|
| App/Server | 进程事件、IMK 连接 | controller、全局服务 | 候选布局、schema 算法 |
| InputController | NSEvent、client 状态 | commit、marked text、UI 快照 | 绘图、YAML 解析、部署构建 |
| RimeBridge | 规范化按键、会话动作 | 值类型 context/status/commit | AppKit、窗口定位 |
| CandidateWindow | 候选快照、光标矩形、主题 | 选择/翻页等语义动作 | 引擎访问、文本提交 |
| Configuration | 内置和用户配置 | 类型化配置快照 | 输入事件处理 |
| Installer | bundle 和输入源元数据 | 注册/启用/诊断结果 | 输入算法、候选 UI |

## 关键不变量

- 每个 controller 最多持有一个有效 Rime session。
- session 销毁后，所有异步 UI 快照即使到达也不得再作用于新 session。
- 每次成功读取 librime 所有权对象都必须配对释放。
- 不使用 Swift `String` 的字符下标直接解释 librime 的 UTF-8 byte offset。
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
       ├─ Maintenance/Deploying
       └─ Degraded/Error

Session Active ── deactivate ──► hide panel + commit/clear policy
Process Exit   ──► destroy sessions ──► finalize engine
```

## 数据目录策略

- Shared data：应用包内只读资源，含已审核 schema、词典源/预编译数据与 OpenCC 配置。
- User data：用户可写配置、用户词典、安装信息与覆盖文件。
- Staging/build：部署生成物，与源配置分离，可重建。
- Logs：独立目录并可清理；默认不含输入明文。

M2 已固定路径：shared data 为应用包的 `Contents/Resources/Rime`；user data 为 `~/Library/Application Support/com.shendongchun.inputmethod.rime.dev/Rime`；staging 为 user data 下的 `build`；日志为 `~/Library/Logs/com.shendongchun.inputmethod.rime.dev`。命令行集成测试改用 `/private/tmp` 隔离根目录，不读写正式用户数据。

## M2 桥接所有权

- `RimeBridge.c` 是唯一包含 `rime_api.h` 的本项目源文件；Swift 和 InputMethodKit 不直接接触 librime C 结构。
- C 层把 commit/context/status 深复制到 `RBSnapshot`，随后立即调用 librime 的配对 free API；`rb_snapshot_clear` 负责释放本项目快照。
- `RimeService` 持有进程级 engine；`RimeSession` 强持有 service 并在 `deinit` 销毁 session，防止先 finalize 后 destroy。
- C 层拒绝同一进程存在两个全局 service；部署保持在显式命令/后续后台路径，不进入按键热路径。
- Swift 快照只含值类型；组合串的 librime UTF-8 byte offset 在桥接边界转换为 Cocoa 使用的 UTF-16 范围。

## M3 输入闭环

- `RimeRuntime` 在输入法进程内持有唯一 `RimeService`；启动失败时 controller 退化为事件透传，不吞掉宿主按键。
- 每个 `RimeInputController` 延迟创建并独占一个 `RimeSession`；关闭 controller 时先结束组合，再释放 session。
- `RimeService` 使用递归锁串行化所有 librime 调用，避免多个 InputMethodKit 会话并发进入全局引擎。
- `RimeKeyMapper` 负责 macOS 键盘事件到 Rime/X11 key symbol 的转换；Command、Control、Option 快捷键在进入引擎前透传。
- `RimeClientUpdater` 是唯一的前端文本写入边界：有 commit 时调用 `insertText`，有 composition 时调用 `setMarkedText`，组合清空时移除 marked text。
- 停用输入源、client 请求提交或 controller 关闭时提交当前转换结果；Escape 明确清空当前组合。

## 候选窗定位

定位函数只接受光标矩形、目标屏幕 visible frame、窗口测量尺寸和布局方向，输出最终 frame。优先向下/右展开，空间不足时翻转，并将最终 frame 约束在当前屏幕可见区域。窗口测量必须在完成文本布局后进行。

## 错误降级

- 引擎不可用：输入事件透传，隐藏候选窗，展示不含输入内容的诊断状态。
- schema/部署失败：保留上一次可用构建；允许用户重新部署或打开配置目录。
- client 无效：终止当前 UI 更新，清理 session 前端状态。
- 主题配置损坏：回退系统动态主题，不影响输入。
