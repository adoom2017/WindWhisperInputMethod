# GitHub Release 自动发布

`.github/workflows/release-macos.yml` 在 GitHub Release 发布后自动构建 macOS
arm64/x86_64 通用应用，执行 Developer ID 签名、Apple 公证、staple 和发布包校验，
最后将 ZIP 与 SHA-256 文件上传到该 Release。

## 标签约定

Release tag 必须使用 `vMAJOR.MINOR.PATCH`，例如 `v0.2.0`。workflow 从 tag
派生应用版本，使用 GitHub run number 和 attempt 生成纯数字 build number。

## Repository secrets

在 GitHub 仓库的 **Settings > Secrets and variables > Actions** 配置：

| Secret | 内容 |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | Developer ID Application `.p12` 的 Base64 内容 |
| `MACOS_CERTIFICATE_PASSWORD` | 导出 `.p12` 时使用的密码 |
| `MACOS_SIGNING_IDENTITY` | 完整签名身份，如 `Developer ID Application: Name (TEAMID)` |
| `APPLE_ID` | Apple Developer 账号 |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `APPLE_APP_SPECIFIC_PASSWORD` | Apple ID 的 app-specific password |

生成证书 Secret：

```bash
base64 < DeveloperIDApplication.p12 | tr -d '\n'
```

不要把证书、密码或公证凭据提交到仓库。缺少任意 Secret 时 workflow 会失败，
不会降级上传 ad-hoc 签名包。

## 发布步骤

1. 将目标提交合并到默认分支，确保该分支包含 release workflow。
2. 创建并推送标签，例如 `git tag v0.2.0 && git push origin v0.2.0`。
3. 在 GitHub 创建该 tag 对应的 Release，并点击 **Publish release**。
4. 在 Actions 中查看 `Release macOS`；成功后 Release 会出现 ZIP 和 `.sha256`。

也可以在 Actions 页面手动运行 workflow，并填写已经存在的 GitHub Release tag。
手动运行不会创建 Release，只会构建并上传到指定的现有 Release。

## Windows 状态

Windows TSF、候选窗与 MSI 目前仍是开发骨架，未通过 Windows 构建和安装门禁，
因此 workflow 不会发布 Windows 产物。Windows 端完成构建、TSF 集成、安装、升级、
回滚和卸载门禁后再增加独立 job，禁止把当前工程骨架作为可安装版本发布。
