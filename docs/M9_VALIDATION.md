# M9 签名、安装与发布候选验收

## 已实现流程

- `Scripts/lib/install-transaction.sh`：用户级原子替换、提交和回滚。
- `Scripts/package-release.sh`：local、Developer ID signed、Developer ID + notarized 三种模式。
- `Scripts/verify-release.sh`：从最终 ZIP 解包检查版本、校验值、通用架构、动态依赖、签名、许可证和发布文档。
- `Scripts/test-m9.sh`：隔离验证升级提交、完整回滚、全新安装回滚、仅 staging 完成时回滚、旧版已移到 previous 时回滚、路径冲突拒绝，以及 local 发布包。

## 本机结果

- universal Release 构建：通过，主程序与 librime 均含 arm64/x86_64。
- 升级提交、全新安装与三种升级回滚状态：通过；不安全的路径冲突会在移动前拒绝。
- local 0.1.0 build 9000001 发布包：通过。
- 当前保留 ZIP SHA-256：`3b33b87f1ac0ee7aa2d22350644523e66e135aa9f7cd3ca20e40c6df065eefd1`。
- 包内许可证、安装/回滚/卸载说明、发布说明、已知问题、JSON 版本清单：通过。
- Homebrew/`/usr/local` 动态依赖、源码泄漏和已移除 Flypy bin：未发现。
- 缺少 `WINDWHISPER_CODE_SIGN_IDENTITY` 时 signed 模式会在构建前失败：通过。

`dist/` 为忽略版本控制的本地产物目录，不提交 ZIP。

## 未执行的正式分发门禁

`security find-identity -v -p codesigning` 在本机返回 `0 valid identities found`，因此以下项目未执行：

- Developer ID Application 对 dylib、主程序和 app 的正式签名。
- Hardened Runtime + trusted timestamp 的实际启动验证。
- Apple notarization 提交、票据 staple 与 Gatekeeper 在线评估。
- 干净用户账户、干净机器的首次授权、升级、回滚和卸载。

获得证书和 notarytool keychain profile 后运行：

```bash
WINDWHISPER_CODE_SIGN_IDENTITY="Developer ID Application: ..." \
WINDWHISPER_NOTARY_PROFILE="windwhisper-notary" \
  ./Scripts/package-release.sh notarized 0.1.0 1
```

只有该命令和干净环境验收通过后，才能把 local 候选提升为可公开分发版本。
