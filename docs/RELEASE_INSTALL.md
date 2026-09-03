# 风语发布版安装说明

## 安装与升级

1. 解压发布包，将 `windwhisper.app` 移到当前用户的 `~/Library/Input Methods/`。
2. 打开应用一次，或注销并重新登录，让 macOS 注册输入法。
3. 在“系统设置 > 键盘 > 文本输入 > 编辑”中添加“风语”。
4. 升级时用新版本替换同一路径中的应用；用户词典和设置位于 Application Support，不会被覆盖。

Developer ID 公证版应能通过 Gatekeeper。标记为 `local` 的候选包只有 ad-hoc 签名，仅用于本机测试，不应对外分发。

## 回滚

退出正在运行的 `windwhisper` 进程，用先前版本替换 `~/Library/Input Methods/windwhisper.app`，然后重新登录或刷新输入法服务。回滚应用不会降级或删除用户词典；若旧版本不能读取新配置，可先备份用户数据后只恢复风语设置。

## 卸载

先在系统设置中移除“风语”，再把 `~/Library/Input Methods/windwhisper.app` 移到废纸篓。默认保留以下用户数据：

```text
~/Library/Application Support/com.shendongchun.inputmethod.windwhisper/User
```

需要彻底删除数据时，应先备份自定义词典和 `.custom.yaml`，再由用户单独删除该明确目录。
