# Rime 数据来源与更新

## 发布范围

风语随应用发布基础全拼/仓颉数据、四套官方双拼方案、用户本机已有的小鹤音形数据、通用辅码索引，以及简繁转换所需的 OpenCC 数据。机器可读锁文件为 `Resources/Rime/DATA_LOCK.json`。

## 固定来源

| 数据 | 来源 | 固定版本 | 说明 |
|---|---|---|---|
| librime minimal data | `rime/librime` | `1.16.0` / `a251145d3aafa33871824a40bbec04c966bd8b56` | 默认方案列表、显示名和辅码接入有本地修改 |
| 四套双拼 schema | `rime/rime-double-pinyin` | `01a13287cbd27819be1c34fa1ddc1b3643d5001b` | 拼写代数不变 |
| 风语通用辅码 | 随包的 `luna_pinyin` + `cangjie5` | 由生成器复现 | 完整拼音后附仓颉首码 |
| 小鹤音形 | `/Users/shendongchun/Documents/rime-origin` | 本地 `10.26.x` 配置 | 原目录未附再分发许可，仅限本机使用；主词典已从原 bin 恢复为文本词典 |
| OpenCC `t2s` | `BYVoid/OpenCC` / Squirrel 1.1.2 包 | `ver.1.1.9` / `556ed22496d650bd0b13b6c163be9814637970ae` | 文件摘要见数据锁 |

## 小鹤音形

`Resources/Rime/flypy.dict.yaml` 是主词典权威源。它由 `Scripts/dump-flypy-bin.c` 从原始 `table/prism/reverse` 穷举恢复，共 64,860 条记录；重新编译并再次穷举得到的候选映射与恢复文件逐字节一致。应用不再发布主词典 bin，首次启动和重新部署时由 librime 生成运行文件。

原始文本层 `flypy_top.txt`、`flypy_sys.txt`、`flypy_user.txt`、`flypy_full.txt`、`flypy_ok.txt` 继续按原 schema 加载。固定语料包括 `w → 我/位`、`d → 的/打`、`u → 是/时`、`ubu → 是不是`、`hdui → 还是`、`biru → 比如`。详细行为见 M6 验证记录。

恢复过程、原始 bin 摘要和完整往返验证见 `docs/FLYPY_MIGRATION_AUDIT.md`。

## 通用辅码

其他拼音方案仍可输入 `;` 后键入完整拼音和可选仓颉首码，例如 `;zuo` 后补 `k` 得到“左”。生成器从随包 `luna_pinyin` 与 `cangjie5` 生成 28,250 条索引，不改变各双拼方案的 spelling algebra。

## 更新流程

1. 升级上游前审查许可证、格式和行为变化，并更新 `DATA_LOCK.json`。
2. 更新官方 schema 后重新生成通用辅码，并运行 M6/M7 测试。
3. 更新小鹤音形时，从用户确认的源词典更新 `flypy.dict.yaml`；若来源仍只有 bin，则用 `Scripts/dump-flypy-bin.c` 重新恢复并执行全编码往返对比，同时更新摘要和真实候选回归。
4. 更新 OpenCC 时同时核对 tag、Squirrel 包摘要和三个输出文件摘要。
5. 更新第三方声明并单独提交数据升级。

应用更新只替换 bundle 内 shared data。用户 `.custom.yaml`、自动学习词典和其他 userdb 保存在 Application Support，不被覆盖。
