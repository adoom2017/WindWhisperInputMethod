# librime 运行时

本目录锁定官方 librime 1.16.0 macOS universal 发布产物。应用链接并复制 `lib/librime.1.dylib` 到自身 `Contents/Frameworks`，运行时不依赖 Homebrew。

来源、commit、产物校验值和架构记录在 `LOCK.json`。执行 `Scripts/fetch-librime.sh` 可从官方 GitHub Release 重新获取同一产物并校验，同时恢复 M2 使用的官方最小 Rime 数据。

M2 只使用 librime 核心库，不加载发布包内的 Lua、octagram 或 predict 插件。第三方许可见 `LICENSES/librime-BSD-3-Clause.txt` 与 `LICENSES/THIRD_PARTY_NOTICES.md`。
