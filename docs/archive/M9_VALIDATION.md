# M9 签名、安装与发布候选验收

## 已实现流程

- `Scripts/lib/install-transaction.sh`：用户级原子替换、提交和回滚。
- `Scripts/package-release.sh`：local、Developer ID signed、Developer ID + notarized 三种模式，同时生成 PKG 和安装 DMG。
- `Scripts/create-pkg.sh` / `Scripts/verify-pkg.sh`：生成系统安装器，验证 `/Library/Input Methods` payload、升级前停止进程、安装后注册服务和 Developer ID Installer 签名。
- `Scripts/create-dmg.sh` / `Scripts/verify-dmg.sh`：生成包含 `安装风语.pkg` 的 Finder 界面，并验证内嵌 PKG。
- `Scripts/verify-release.sh`：检查版本、校验值、通用架构、动态依赖、应用签名、许可证和发布文档。
- `Scripts/test-m9.sh`：隔离验证升级提交、完整回滚、全新安装回滚、仅 staging 完成时回滚、旧版已移到 previous 时回滚、路径冲突拒绝，以及 local 发布包。

## 本机结果

- universal Release 构建：通过，主程序与 input-engine 均含 arm64/x86_64。
- 升级提交、全新安装与三种升级回滚状态：通过；不安全的路径冲突会在移动前拒绝。
- local 1.0.0 build 2026090307 universal 构建与 PKG：通过；固定系统安装路径、禁止 relocation、升级脚本和嵌入许可证均通过。
- 旧版 ZIP SHA-256 仅作为历史记录：`3b33b87f1ac0ee7aa2d22350644523e66e135aa9f7cd3ca20e40c6df065eefd1`。
- 包内许可证、安装/回滚/卸载说明、发布说明、已知问题、JSON 版本清单：通过。
- Homebrew/`/usr/local` 动态依赖、源码泄漏和已移除旧词库文件：未发现。
- 缺少 `WINDWHISPER_APP_SIGN_IDENTITY` 或 `WINDWHISPER_INSTALLER_SIGN_IDENTITY` 时 signed 模式会在构建前失败：通过。

`dist/` 为忽略版本控制的本地产物目录，不提交 PKG 或 DMG。

## 未执行的正式分发门禁

本机已存在有效的 Developer ID Application 与 Developer ID Installer identity。当前执行环境访问 Apple timestamp 服务时 TLS 握手失败，因此以下正式分发门禁尚未完成：

- 带可信时间戳的 Developer ID Application 应用签名。
- 带可信时间戳的 Developer ID Installer PKG 签名。
- Hardened Runtime + trusted timestamp 的实际启动验证。
- Apple notarization 提交、票据 staple 与 Gatekeeper 在线评估。
- 干净用户账户、干净机器的首次授权、升级、回滚和卸载。
- 最终 DMG 生成与挂载校验；受限沙箱无法配置 `hdiutil` 设备。

在能够正常访问 Apple 时间戳与公证服务的环境中运行：

```bash
WINDWHISPER_APP_SIGN_IDENTITY="Developer ID Application: ..." \
WINDWHISPER_INSTALLER_SIGN_IDENTITY="Developer ID Installer: ..." \
WINDWHISPER_NOTARY_PROFILE="windwhisper-notary" \
  ./Scripts/package-release.sh notarized 0.1.0 1
```

只有该命令和干净环境验收通过后，才能把 local 候选提升为可公开分发版本。
