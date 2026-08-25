# Rime 数据来源与更新

## 发布范围

风语随应用发布基础 `luna_pinyin`/`cangjie5` 数据、全拼方案、四套官方双拼方案、用户本机已有的小鹤音形配置、由基础码表生成的通用辅码索引，以及 M7 简繁切换需要的 OpenCC 数据。机器可读锁文件为 `Resources/Rime/DATA_LOCK.json`，第三方许可证位于 `LICENSES/`。

## 固定来源

| 数据 | 来源 | 固定版本 | 许可证 | 本地修改 |
|---|---|---|---|---|
| librime minimal data | `rime/librime` | tag `1.16.0` / `a251145d3aafa33871824a40bbec04c966bd8b56` | LGPL-3.0 与文件内数据声明 | 默认方案列表、全拼显示名、风语辅码接入 |
| 四套双拼 schema | `rime/rime-double-pinyin` | `01a13287cbd27819be1c34fa1ddc1b3643d5001b` | GPL-3.0 | 简体显示名；移除 stroke 反查依赖；加入辅码依赖和 translator；拼写代数不变 |
| 风语辅码索引 | 上述 `luna_pinyin` + `cangjie5` | 随当前仓库生成器固定 | GPL-3.0 | 规则为“完整拼音＋仓颉首码” |
| 小鹤音形本地配置 | 用户已有 Rime 配置（方案设计标注为何海峰 / flypy.cc） | `10.26.x` | 原目录未附再分发许可，仅限本机使用 | 由四码单字表和补充词表生成当前 librime 可编译的 `flypy.dict.yaml` |
| OpenCC `t2s` 数据 | `BYVoid/OpenCC`，由官方 Squirrel 1.1.2 包提供匹配的编译数据 | tag `ver.1.1.9` / `556ed22496d650bd0b13b6c163be9814637970ae` | Apache-2.0 | 无；只选择 `t2s.json`、`TSCharacters.ocd2`、`TSPhrases.ocd2` |

官方项目地址：

- https://github.com/rime/librime
- https://github.com/rime/rime-luna-pinyin
- https://github.com/rime/rime-cangjie
- https://github.com/rime/rime-double-pinyin
- https://github.com/BYVoid/OpenCC

## 小鹤音形辅助码

默认 `flypy` 方案采用“小鹤双拼两键音码＋最多两位小鹤形码”。两键即可出候选，第三、第四键逐步收窄；例如 `ni` 为音码，`nir` 加第一形码，`nirx` 为“你”的完整码并自动上屏。生成器保留用户原配置中的简码、词组和排序，再从 `flypydz.dict.yaml` 为每个单字生成两键、三键和四键记录，当前共 36,253 条。

该批本地文件没有随附明确再分发许可，`DATA_LOCK.json` 将其标为 `local-use-only`。当前应用可供本机安装使用；若以后公开发布，必须先确认小鹤数据授权或改由用户安装后自行导入。

## 通用辅码规则

辅码是独立模式，不改变全拼或双拼的 spelling algebra。用户输入 `;` 后键入完整拼音；候选注释显示可补充的仓颉首码。继续输入首码即可缩小候选，例如：

```text
;zuo   → 多个 zuo 同音字
;zuok  → 左
```

生成器只连接两个已有码表中相同的单字：从 `luna_pinyin` 取完整拼音，从 `cangjie5` 取首个英文字母。当前生成 28,250 条记录，不启用独立用户词典；正常拼音 translator 继续使用 librime 的 `luna_pinyin.userdb` 学习词频。

## 更新流程

1. 明确要升级的上游提交，先审查许可证、数据格式和 breaking changes。
2. 更新 `Resources/Rime/DATA_LOCK.json` 的提交和文件清单。
3. 将四套上游双拼 schema 同步到本地，再重新应用本文件记录的三类修改；不得改变其 spelling algebra 而不增加新回归语料。
4. 运行：

   ```bash
   ./Scripts/generate-aux-dictionary.swift \
     Resources/Rime/luna_pinyin.dict.yaml \
     Resources/Rime/cangjie5.dict.yaml \
     Resources/Rime/fengyu_aux.dict.yaml
   ```

   再生成本机小鹤音形词典：

   ```bash
   ./Scripts/generate-flypy-dictionary.swift \
     Resources/Rime/flypydz.dict.yaml \
     Resources/Rime/flypy.dict.yaml \
     Resources/Rime/flypy_top.txt \
     Resources/Rime/flypy_sys.txt \
     Resources/Rime/flypy_user.txt \
     Resources/Rime/flypy_full.txt
   ```

   生成器会保留原码表的单键/双键简码、三键短语简码和四键四字词，并在补充码表中缺少简码或四字词时停止生成。文本码表可以从用户的 `rime-origin` 目录复用；不要复制其中 `build/*.bin` 或用户数据库，必须由当前捆绑的 librime 重新部署。

5. OpenCC 数据从锁定 SHA-256 的官方 `Squirrel-1.1.2.pkg` 提取；更新时同时核对 OpenCC tag、Squirrel 包摘要和三个输出文件摘要。
6. 执行 `Scripts/test-m6.sh Debug|Release` 和 `Scripts/test-m7.sh Debug|Release`。前者再次生成两类辅码词典并逐字节比较，后者验证“漢字”与“汉字”的真实候选转换。
7. 更新 `LICENSES/THIRD_PARTY_NOTICES.md` 与对应里程碑验收文档，单独提交数据升级。

应用更新只替换 bundle 内 shared data。用户 `.custom.yaml`、自动学习词典和部署产物位于 Application Support 目录；全量部署会重建 `build`，但不得覆盖用户源文件和 userdb。
