# M8 兼容性、性能与可靠性验收

## 自动化环境

- 日期：2026-08-27
- 主机：Apple Silicon
- 系统：macOS 26.5.1（25F80）
- 工具链：Xcode 26.4.1（17E202）
- 输入引擎：原生 Swift `native-1.0`

## 覆盖范围

`Scripts/test-m8.sh Debug|Release [stress-seconds]` 在隔离 user data 中覆盖：

- ASCII、Emoji、组合字符、CJK 扩展字符和非法 UTF-8 byte offset 到 UTF-16 的换算。
- Command 快捷键透传、一次 engine commit 只写入 client 一次。
- 候选窗异步展示与隐藏按代次互相失效，防止快速焦点切换后的残留或新候选被旧任务隐藏。
- service/session 创建销毁、快照深复制与清理的余额计数。
- engine 初始化、配置刷新、普通按键 + 快照 + 候选布局的 P50/P95/P99。
- 按指定时长反复创建 session、输入、读取多次快照、清理和销毁后的 RSS。

## 实测结果

性能输出字段已更新为 `engineInitializationMs` 和 `configurationRefreshMs`。此前外部引擎的部署数据不再作为当前实现基线；下一个 Release 候选需要重新记录完整表格。

Release P95 低于 16 ms 门禁；测试结束时活跃 session 和桥接快照分配均为 0。

## 外部人工项目

以下项目不能由当前单台主机的命令行 smoke 代替，仍是发布前人工门禁：

- `Scripts/test-m8.sh Release 3600` 一小时压力测试。
- macOS 13 真机、Intel 真机、干净用户账户。
- TextEdit、Notes、Safari、Terminal、Xcode、Electron、Spotlight 的完整输入矩阵。
- Secure Input、休眠唤醒、全屏、多显示器、不同缩放与远程桌面。

这些项目未执行，不记录为通过。
