# 小鹤音形迁移差异审计

审计日期：2026-08-27

## 权威基线

原始行为基线为用户目录 `/Users/shendongchun/Documents/rime-origin` 的以下预编译文件：

| 文件 | SHA-256 |
|---|---|
| `flypy.table.bin` | `66d7151fe0dbcf2b1f40e0431b158bf630e2f0743ac1ceb45c7aceb17fd64eb7` |
| `flypy.prism.bin` | `7ebbff4c8d6d199e03cd4a16229b41a27b930d5eafb58b19855a2fa937d4d7a0` |
| `flypy.reverse.bin` | `2d06614b32a22dbf2cbb26f8799231d5628b0131e8e6e0be6314d688706fb4f5` |

使用 `Scripts/dump-flypy-bin.c` 通过锁定的 librime 1.16 穷举全部 475,254 个一至四位字母编码，恢复出 64,860 条“词条＋编码”记录。当前权威源为 `Resources/Rime/flypy.dict.yaml`，加入升级版本标识后的 SHA-256 为 `ea284029473466e10ee752748626f19c579da3d3a868250d61f3b457bacfa5d6`。应用不再携带原始三个 bin。

恢复词典经过完整往返验证：由 librime 重新编译为 `table/prism/reverse` 后再次穷举全部编码，输出与首次恢复文件逐字节一致。新生成的 bin 哈希不必与原始 bin 相同，因为编译产物包含与原文件不同的构建表示；对外候选映射和同码顺序保持一致。

## 已验证行为

- 单键顺序：`w → 我/位`、`d → 的/打`、`u → 是/时`（其中“位”等补充简码来自 `flypy_sys.txt`）。
- 常用词：`ubu → 是不是`、`hdui → 还是`、`biru → 比如`。
- 音形码：`ni → 你`、`nir → 倪`、`nirx → 你`并自动上屏。
- 四字及分层：`ahqi` 首选“昂起”，`sys` 的“爱恨情仇”为后续候选；`anui → 按时`。
- `flypy_top.txt`、`flypy_sys.txt`、`flypy_user.txt`、`flypy_full.txt` 和 `flypy_ok.txt` 与原目录保持一致并继续按原 schema 独立加载。

首次启动或重新部署时，librime 从 `flypy.dict.yaml` 生成运行所需的三个 bin。用户的 `.custom.yaml` 与 userdb 仍保留在用户目录，不被覆盖。

## 尚未包含

原配置依赖 Lua 的日期、时间、计算器等动态功能，以及尚未确认入口的 `ok...` 拆字功能，不因复用 bin 自动获得。它们应分别实现和测试，不能用第三方近似词库替代。

这些本地小鹤文件未附明确再分发许可，当前仅用于用户本机安装；公开发布前需另行确认授权。
