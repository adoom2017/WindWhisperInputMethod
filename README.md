# 风语

风语（`windwhisper`）是一个原生 macOS 中文输入法，基于 Swift、AppKit 与 InputMethodKit 构建。它内置专用输入引擎，支持全拼、小鹤双拼纯音码和小鹤双拼音形，并提供原生毛玻璃候选窗。

## 主要功能

- 支持风语全拼、小鹤双拼纯音码与小鹤双拼音形
- 小鹤音形支持两键音码后继续输入形码缩小候选范围
- 全拼和小鹤双拼支持长句输入，并使用内置二元、三元统计语言模型重排候选
- 支持简繁切换、全半角、候选横竖排及浅色、深色和跟随系统主题
- 支持在管理界面增删改自定义词条，并导入、导出 `custom_words.tsv`
- 候选窗跟随插入点显示，支持键盘、鼠标与滚轮选词

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
