# M3 验收记录

日期：2026-08-24  
状态：代码与自动化验收通过；TextEdit 人工门禁待确认

## 已交付

- 进程级 `RimeRuntime`，负责正式用户数据目录中的初始化和快速部署。
- 每个 InputMethodKit controller 独立 Rime session，以及服务级串行化引擎访问。
- macOS 按键到 Rime key symbol/mask 的映射。
- Command 快捷键透传给应用；Control/Option 和 modifier 按下/释放映射给 Rime。左 Shift 遵循原配置 `commit_code`，右 Shift 与 Caps Lock 为 `noop`。
- marked text、光标范围、commit、Backspace、Escape、Space、Return 与停用提交。
- 可重复执行的 `--m3-smoke` 和 `Scripts/test-m3.sh`。
- 本机安装签名顺序修复：先嵌入 librime，再主程序，最后 app bundle。

## 自动化结果

Debug arm64 与 Release arm64+x86_64 均通过：

```text
keyMapping=passed
shortcutMapping=passed
modifierMapping=passed
compositionEditing=passed
shiftModeSwitch=passed
rimeShortcutRouting=passed
frontendCommit=passed
inputClientFlow=passed
```

M2 回归项也全部通过：librime 版本、schema、候选、提交、UTF-8/UTF-16 范围转换和 session 生命周期。`xcodebuild analyze` 成功，项目元数据、运行时依赖、架构和签名检查成功。

最终 Debug 构建已安装到 `~/Library/Input Methods/RimeInputMethod.app`。安装过程只使用本地 ad-hoc 签名和当前会话热刷新，没有注销、重启、Apple 公证或构建上传；安装后恢复了鼠须管输入源。

## 尚待人工确认

自动 TextEdit 验收尝试被 macOS 拒绝，原因是 `osascript` 未获“辅助功能”发送按键权限（错误 1002）。脚本已关闭临时文稿并恢复原输入法，没有保存测试内容。

请在 TextEdit 中选择“风语”，输入 `nihao` 后按 Space。预期：先显示行内组合文本和 M4 候选面板，随后上屏“你好”，且不残留 marked text。候选窗专项验证已迁移到 `M4_VALIDATION.md`。
