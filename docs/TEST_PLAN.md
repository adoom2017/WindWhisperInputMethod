# 测试计划

## 测试层级

| 层级 | 目的 | 是否自动化 |
|---|---|---|
| 单元 | 键位、字符串范围、布局、配置、模型转换 | 必须 |
| Bridge 集成 | librime 初始化、session、候选、提交、释放 | 必须 |
| 输入法集成 | InputMethodKit 生命周期与真实 client | 部分自动 + 手工 |
| 视觉 | 主题、屏幕边界、可访问性 | 截图基线 + 手工 |
| 发布 | 安装、签名、升级、回滚、卸载 | 脚本检查 + 干净机手工 |

## 系统矩阵

- 最低支持 macOS 版本。
- 当前最新稳定 macOS。
- arm64；如 D-04 确认通用构建，再覆盖 x86_64。
- 单屏、多屏、不同缩放、全屏 Space。
- 浅色、深色、减少透明度、增强对比度。

## 应用矩阵

| 类别 | 应用/场景 | 关键检查 |
|---|---|---|
| Cocoa | TextEdit、Notes | marked text、选区、撤销、长句 |
| 浏览器 | Safari 地址栏和网页输入框 | 焦点切换、快捷键、密码框 |
| 开发 | Terminal、Xcode | 控制键、命令键、等宽文本 |
| 跨平台 | 一个 Electron 应用 | 光标矩形、候选定位、组合兼容 |
| 系统 | Spotlight/系统搜索（若可用） | 短生命周期 client、快速切换 |

## 输入用例族

- 基本：单字、词组、长句、连续上屏、取消。
- 编辑：退格、光标移动、选区替换、撤销/重做。
- Unicode：Emoji、扩展汉字、组合字符、中英混排。
- 候选：数字选词、鼠标选词、高亮、首尾页、空页保护。
- 会话：切应用、切窗口、切输入源、休眠唤醒、进程重启。
- 方案：每个双拼固定编码样例；辅码命中、不命中、歧义和回退。
- 异常：资源缺失、配置损坏、部署失败、磁盘只读、session 失效。

## M3—M5 自动化与人工门禁

- `Scripts/test-m3.sh Debug|Release` 覆盖按键映射、Command/Control/Option 透传、Backspace、Escape、`nihao + Space` 提交“你好”，以及生产 `RimeClientUpdater` 对 `IMKTextInput` 的 marked/commit 调用。
- `xcodebuild analyze` 必须无诊断失败；Release 主程序和 librime 必须同时包含 arm64、x86_64。
- `Scripts/test-textedit-m3.sh` 只创建并关闭一个不保存的 TextEdit 临时文稿；它需要运行终端/宿主获得 macOS“辅助功能”发送按键权限。
- `Scripts/test-m4.sh Debug|Release` 覆盖候选展示模型、本页序号、鼠标行命中、非激活面板配置、下方/上方翻转、可见区域约束、多显示器选择，以及真实 librime 的方向键高亮、PageDown 翻页和语义选词提交。
- M4 候选窗显示已由用户在实际输入中确认；完整键盘、鼠标和多屏检查项保留在 `docs/M4_VALIDATION.md` 作为后续回归清单。
- `Scripts/test-m5.sh Debug|Release` 覆盖正常/无障碍主题 fallback、横向布局边界、候选间不重叠、短正文优先与长文本公平压缩、macOS 26 `NSGlassEffectView` 和旧系统 `NSVisualEffectView` 回退配置，以及 Aqua/Dark Aqua × 普通/降低透明度与增强对比度的离屏 PNG 渲染。
- M5 本机视觉门禁按 `docs/M5_VALIDATION.md` 执行，重点确认实际桌面内容下的毛玻璃、候选截断、快速输入稳定性和系统无障碍显示设置。

## 性能记录

每次发布候选记录：

- 冷启动与首次可输入时间。
- 首次部署和增量部署耗时。
- 普通按键处理 P50/P95/P99。
- context 到候选窗刷新耗时。
- 空闲/持续输入 CPU 与内存。
- 一小时压力测试后的 session、窗口和内存状态。

具体阈值以 `DEVELOPMENT_PLAN.md` 的建议为起点，在首个可测版本后确认。

## 发布阻断缺陷

- 可复现崩溃、死锁或持续高 CPU。
- 输入事件重复提交、错误吞键或 Command 快捷键失效。
- 候选窗抢焦点、跨应用残留或严重越屏。
- 用户词典/配置在普通升级中丢失。
- Release 包在干净机缺少动态库或签名无效。
- 日志包含明文按键、组合串、候选或提交内容。
