# 小鹤音形迁移差异审计

审计日期：2026-08-25

## 权威基线

唯一行为基线为用户目录 `/Users/shendongchun/Documents/rime-origin`。风语直接随包携带并逐字节安装以下文件：

| 文件 | SHA-256 |
|---|---|
| `flypy.table.bin` | `66d7151fe0dbcf2b1f40e0431b158bf630e2f0743ac1ceb45c7aceb17fd64eb7` |
| `flypy.prism.bin` | `7ebbff4c8d6d199e03cd4a16229b41a27b930d5eafb58b19855a2fa937d4d7a0` |
| `flypy.reverse.bin` | `2d06614b32a22dbf2cbb26f8799231d5628b0131e8e6e0be6314d688706fb4f5` |

这些文件是 Rime 数据，不是 Intel 可执行代码；已验证当前 arm64 librime 1.16 可直接加载。原目录没有与主词典等价的 `flypy.dict.yaml`，因此从其他公开词表重建会改变收词、简码及候选优先级，现已删除该近似生成链。随包的同名 YAML 只有一个哨兵词条，用于让全量部署完成，不能作为主词典来源。

## 已验证行为

- 单键顺序：`w → 我/位`、`d → 的/打`、`u → 是/时`。
- 常用词：`ubu → 是不是`、`hdui → 还是`、`biru → 比如`。
- 音形码：`ni → 你`、`nir → 倪`、`nirx → 你`并自动上屏。
- 四字及分层：`ahqi` 首选“昂起”，`sys` 的“爱恨情仇”为后续候选；`anui → 按时`。
- `flypy_top.txt`、`flypy_sys.txt`、`flypy_user.txt`、`flypy_full.txt` 和 `flypy_ok.txt` 与原目录保持一致并继续按原 schema 独立加载。

部署前后都会核对并恢复这三个 bin，防止全量部署尝试重编译 `flypy` 后覆盖权威数据。用户的 `.custom.yaml` 与 userdb 仍保留在用户目录，不被覆盖。

## 尚未包含

原配置依赖 Lua 的日期、时间、计算器等动态功能，以及尚未确认入口的 `ok...` 拆字功能，不因复用 bin 自动获得。它们应分别实现和测试，不能用第三方近似词库替代。

这些本地小鹤文件未附明确再分发许可，当前仅用于用户本机安装；公开发布前需另行确认授权。
