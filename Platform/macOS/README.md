# macOS 编译、打包与使用

## 环境要求

- 运行：macOS 13 或更高版本，发布版同时支持 Apple Silicon 和 Intel
- 编译：Xcode 26 或兼容版本

以下命令均在仓库根目录执行。

## 安装与使用

1. 双击 DMG 中的 `安装风语.pkg`，按提示完成安装。升级时直接运行新版 PKG。
2. 打开“系统设置 → 键盘 → 文本输入 → 编辑”，在简体中文分类中添加“风语”。
3. 从菜单栏输入法菜单切换到风语；菜单未刷新时注销并重新登录。

菜单栏的风语菜单可以切换输入方案、全半角、繁简、候选排列（横/竖）和候选主题，
也可以管理自定义词组、打开用户目录、查看脱敏诊断和恢复默认设置。

用户数据位于 `~/Library/Application Support/com.shendongchun.inputmethod.windwhisper/User`，
升级和卸载默认保留。升级、回滚和卸载细节见 [发布版安装说明](../../docs/RELEASE_INSTALL.md)。

## 编译与本机安装

```bash
./Scripts/build.sh Debug
./Scripts/install-user.sh Debug
```

没有开发签名证书时使用本地签名：

```bash
WINDWHISPER_AD_HOC_SIGNING=1 ./Scripts/build.sh Debug
```

产物：`build/DerivedData/Build/Products/<Configuration>/windwhisper.app`。
`Debug` 仅构建 Apple Silicon；`Release` 构建通用二进制。

## 测试

```bash
Scripts/verify-project.sh
Scripts/test-m3.sh Debug    # 同样运行 test-m4 … test-m7（Debug）、test-m8（Release）
Scripts/test-m9.sh          # 安装事务与回滚
```

各测试使用隔离的临时用户目录，不读写真实用户数据。

## 打包

本地安装包（ad-hoc 签名，仅供本机测试）：

```bash
Scripts/package-release.sh local 0.1.0 2026091001
```

参数依次为模式、版本号和纯数字构建号。产物输出到 `dist/`，包含 PKG、DMG 和 SHA-256 文件。

### 签名与公证

需要 `Developer ID Application` 和 `Developer ID Installer` 证书（含私钥）已导入钥匙串。
首次使用时保存公证凭据：

```bash
xcrun notarytool store-credentials "windwhisper-notary"
```

然后打包：

```bash
WINDWHISPER_APP_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
WINDWHISPER_INSTALLER_SIGN_IDENTITY="Developer ID Installer: Your Name (TEAMID)" \
WINDWHISPER_NOTARY_PROFILE="windwhisper-notary" \
  Scripts/package-release.sh notarized 0.1.0 2026091001
```

仅签名不公证时把 `notarized` 改为 `signed`。公证凭据不在默认钥匙串时，设置
`WINDWHISPER_NOTARY_KEYCHAIN`。用 `security find-identity -v -p codesigning` 查看可用证书。

发布 `vMAJOR.MINOR.PATCH` 格式的 GitHub Release 也会自动签名打包，配置见
[自动发布说明](../../docs/GITHUB_RELEASE.md)。
