# 第三方组件清单

## librime 1.16.0

- 项目：https://github.com/rime/librime
- 固定 tag：`1.16.0`
- 固定 commit：`a251145d3aafa33871824a40bbec04c966bd8b56`
- 使用内容：官方 macOS universal 动态库、C API headers，以及同一 tag `data/minimal` 下的 M2 测试数据。
- 许可证：BSD-3-Clause，完整文本见 `librime-BSD-3-Clause.txt`。
- 修改：未修改第三方二进制、headers 或最小数据；仅在本工程内重命名发布库副本为其 install name `librime.1.dylib`。
- 获取与校验：`Scripts/fetch-librime.sh`；锁定信息见 `Vendor/librime/LOCK.json`。

M2 内置的 `luna_pinyin` 与 `cangjie5` 数据仅用于固定的桥接集成测试。面向产品的词库、双拼和辅码数据仍属于 M6，必须在对应 ADR 获得确认后进入发布范围。

## 现有图标来源待替换

M1 为验证 InputMethodKit 注册临时使用了本机 Squirrel 安装包中的图标资源。该资源不作为正式发布资产；在进入发布候选前必须替换为本项目自有图标，或补齐其精确来源与许可审查。
