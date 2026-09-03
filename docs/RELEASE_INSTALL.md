# 风语发布版安装说明

## 安装与升级

1. 双击发布的 DMG，再双击其中的 `安装风语.pkg`。
2. 按 macOS 安装器提示输入管理员密码并完成安装。
3. 安装器会将当前输入源切换到 ABC、停止旧版 `windwhisper`，然后安装新版到 `/Library/Input Methods/`。
4. 在“系统设置 > 键盘 > 文本输入 > 编辑”中添加“风语”；若输入法菜单未立即刷新，再注销并重新登录。

升级直接运行新版 PKG，不要再从 DMG 手动拖拽覆盖应用。安装前后脚本负责停止旧进程、注册新版并刷新输入法服务，用户词典和设置位于 Application Support，不会被覆盖。若安装过早期的用户级版本，请先移除 `~/Library/Input Methods/windwhisper.app`，避免系统同时发现两个副本。

Developer ID 公证版应能通过 Gatekeeper。标记为 `local` 的候选包只有 ad-hoc 签名，仅用于本机测试，不应对外分发。

## 回滚

运行先前版本对应的已签名 PKG，然后重新选择风语；必要时注销并重新登录。回滚应用不会降级或删除用户词典；若旧版本不能读取新配置，可先备份用户数据后只恢复风语设置。

## 卸载

先在系统设置中移除“风语”，再把 `/Library/Input Methods/windwhisper.app` 移到废纸篓。默认保留以下用户数据：

```text
~/Library/Application Support/com.shendongchun.inputmethod.windwhisper/User
```

需要彻底删除数据时，应先备份自定义词典和 `.custom.yaml`，再由用户单独删除该明确目录。
