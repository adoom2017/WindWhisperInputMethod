# 风语

风语（`windwhisper`）是一个原生 macOS 中文输入法，基于 Swift、AppKit 与 InputMethodKit 构建。它内置专用输入引擎，支持全拼、小鹤双拼纯音码和小鹤双拼音形，并提供原生毛玻璃候选窗。

## 主要功能

- 支持风语全拼、小鹤双拼纯音码与小鹤双拼音形
- 小鹤音形支持两键音码后继续输入形码缩小候选范围；按 `~` 可在候选右侧反查完整音形编码，例如 `ni~` 显示“你 nirx”
- 全拼和小鹤双拼支持长句输入，并使用内置二元、三元统计语言模型重排候选
- 支持简繁切换、全半角、候选横竖排及浅色、深色和跟随系统主题
- 支持在管理界面增删改自定义词条，并导入、导出 `custom_words.tsv`
- 候选窗跟随插入点显示，支持 PageUp/PageDown、`-`/`=`、鼠标与滚轮翻页选词

## 编译

### 环境要求

- macOS 13 或更高版本
- Xcode 26 或兼容版本
- Apple Silicon Mac 可构建 Debug 版本；Release 构建生成 arm64 与 x86_64 通用应用

项目已内置词典和编码数据，正常构建不需要 Homebrew 或网络连接。

在仓库根目录执行：

```bash
./Scripts/verify-project.sh
./Scripts/build.sh Debug
```

编译 Release 通用版本：

```bash
./Scripts/build.sh Release
```

构建产物位于：

```text
build/DerivedData/Build/Products/<Configuration>/windwhisper.app
```

## 正式签名与 Apple 公证

对 Mac 外部分发需使用 Apple Developer 账号中的 `Developer ID Application`
证书，`Apple Development` 证书仅适用于开发调试。先检查本机可用的签名身份：

```bash
security find-identity -v -p codesigning
```

输出中应包含类似下面的条目：

```text
Developer ID Application: Your Name (TEAMID)
```

如果显示 `0 valid identities found`，请在“钥匙串访问”中导入创建该证书时导出的
`.p12`，并确认证书下方有对应的私钥。仅安装从 Apple 下载的 `.cer`
不会构成可用 identity；如果私钥在另一台 Mac，需从那台 Mac 导出包含私钥的
`.p12` 再导入本机。

### 生成正式签名包

将下面的 identity 替换为上一步查到的完整证书名称：

```bash
WINDWHISPER_CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  Scripts/package-release.sh signed 0.1.0 2026090201
```

`signed` 模式会构建 arm64/x86_64 通用应用，启用 Hardened Runtime、时间戳并使用
Developer ID 签名，然后在 `dist/` 下生成 ZIP 和 SHA-256 文件。构建号必须为纯数字。
可用以下命令查看和验证签名：

```bash
codesign -dvv dist/windwhisper-0.1.0-2026090201-macos-universal/windwhisper.app
codesign --verify --deep --strict --verbose=2 \
  dist/windwhisper-0.1.0-2026090201-macos-universal/windwhisper.app
```

仅完成 Developer ID 签名的包可用于内部验证；面向用户分发时应继续完成 Apple 公证。
`Scripts/package-release.sh local ...` 只会使用 ad-hoc 签名，不是正式发布包。

### 生成已公证发布包

先在 Apple ID 账号页面创建 app-specific password，然后将公证凭据安全存入登录钥匙串：

```bash
xcrun notarytool store-credentials "windwhisper-notary" \
  --apple-id "your-apple-id@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

提交公证并将 ticket staple 到应用：

```bash
WINDWHISPER_CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
WINDWHISPER_NOTARY_PROFILE="windwhisper-notary" \
WINDWHISPER_NOTARY_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db" \
  Scripts/package-release.sh notarized 0.1.0 2026090201
```

`notarized` 模式会完成签名、上传公证、等待 Apple 结果、staple、
`stapler validate` 和最终发布包校验。安装后输入法位于：

```text
~/Library/Input Methods/windwhisper.app
```

不要将 `.p12`、证书密码、Apple ID app-specific password 或公证凭据提交到
Git。GitHub Actions 中的证书与公证凭据应保存为 Repository Secrets，详见
[`docs/GITHUB_RELEASE.md`](docs/GITHUB_RELEASE.md)。

## 自动发布

发布 `vMAJOR.MINOR.PATCH` 格式的 GitHub Release 后，GitHub Actions 会自动构建、
Developer ID 签名、公证并上传 macOS universal ZIP 与 SHA-256 文件。首次启用前需
配置签名与 Apple 公证 Secrets，详见
[`docs/GITHUB_RELEASE.md`](docs/GITHUB_RELEASE.md)。
