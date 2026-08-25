# 第三方组件清单

## librime 1.16.0

- 项目：https://github.com/rime/librime
- 固定 tag：`1.16.0`
- 固定 commit：`a251145d3aafa33871824a40bbec04c966bd8b56`
- 使用内容：官方 macOS universal 动态库、C API headers，以及同一 tag `data/minimal` 下的基础 Rime 数据。
- 许可证：BSD-3-Clause，完整文本见 `librime-BSD-3-Clause.txt`。
- 修改：未修改第三方二进制、headers 或最小数据；仅在本工程内重命名发布库副本为其 install name `librime.1.dylib`。
- 获取与校验：`Scripts/fetch-librime.sh`；锁定信息见 `Vendor/librime/LOCK.json`。

## Rime 基础数据

- 获取位置：librime `1.16.0` 固定提交的 `data/minimal`。
- 上游项目：`rime/rime-luna-pinyin`、`rime/rime-cangjie` 及 Rime essay 数据。
- 使用内容：`luna_pinyin`、`cangjie5`、`essay.txt`、标点和默认配置；M6 将全拼名称适配为“风语全拼”，并加入独立辅码 translator。
- 许可证：LGPL-3.0 及源文件内的数据专有声明，完整 LGPL 文本见 `rime-data-LGPL-3.0.txt`。
- 精确来源与文件清单：`Resources/Rime/DATA_LOCK.json` 和 `docs/RIME_DATA.md`。

## Rime double pinyin

- 项目：https://github.com/rime/rime-double-pinyin
- 固定 commit：`01a13287cbd27819be1c34fa1ddc1b3643d5001b`
- 使用内容：自然码、小鹤、微软、智能 ABC 四套 schema。
- 许可证：GPL-3.0，完整文本见 `rime-double-pinyin-GPL-3.0.txt`。
- 修改：名称改为简体中文；移除未随包提供的 stroke 反查依赖；增加风语辅码依赖、translator 和 recognizer。拼写代数保持上游原样。

## 风语辅码索引

- 派生来源：本包锁定的 `luna_pinyin.dict.yaml` 与 `cangjie5.dict.yaml`。
- 规则：完整拼音后附加仓颉首码；由 `Scripts/generate-aux-dictionary.swift` 可复现生成。
- 许可证：按兼容的 GPL-3.0 随包提供。

## 风语原创图标

当前应用图标、输入法菜单图标和切换器图标均为风语原创资源，不使用 Rime/鼠须管图标或其视觉元素。
