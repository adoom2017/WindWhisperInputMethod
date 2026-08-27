# 风语

风语（`windwhisper`）是一个原生 macOS 中文输入法，基于 Swift、AppKit、InputMethodKit 与 librime 构建。它支持 Rime 词库、多种拼音方案、双拼和辅码输入，并提供原生毛玻璃候选窗。

## 主要功能

- 支持风语全拼、自然码、微软双拼、智能 ABC 与小鹤双拼
- 默认使用小鹤双拼（音形辅码），同时提供纯音码模式
- 支持简繁切换、全半角、候选横竖排及浅色、深色和跟随系统主题
- 支持 Rime 用户词典与自定义配置
- 候选窗跟随插入点显示，支持键盘、鼠标与滚轮选词

## 编译

### 环境要求

- macOS 13 或更高版本
- Xcode 26 或兼容版本
- Apple Silicon Mac 可构建 Debug 版本；Release 构建生成 arm64 与 x86_64 通用应用

项目已内置锁定版本的 librime 和 Rime 数据，正常构建不需要 Homebrew 或网络连接。

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

如需从官方发布源恢复锁定的 librime 依赖，可执行：

```bash
./Scripts/fetch-librime.sh
```
