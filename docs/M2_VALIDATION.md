# M2 验证记录

日期：2026-08-24  
环境：macOS 26.5.1，Apple Silicon，Xcode 26.4.1，Swift 6.3.1

## 依赖与可复现性

- 锁定官方 librime 1.16.0 / commit `a251145d3aafa33871824a40bbec04c966bd8b56`。
- 官方 macOS universal 归档 SHA-256 校验通过。
- `Scripts/fetch-librime.sh` 已从空临时目录重新下载归档与七个固定最小数据文件，逐项校验并恢复工程依赖。
- `Vendor/librime/LOCK.json` 记录版本、commit、URL、归档/内嵌库校验值、架构与许可证。
- 内嵌库只依赖 `/usr/lib/libSystem.B.dylib` 与 `/usr/lib/libc++.1.dylib`，没有 `/opt/homebrew` 或 `/usr/local` 依赖。

## 桥接闭环

Debug 与 Release 均执行 `Scripts/test-rime-bridge.sh`，结果：

```text
librimeVersion=1.16.0
schemaLoaded=true
candidateCountPositive=true
expectedCandidateFound=true
commitMatched=true
rangeConversion=passed
sessionLifecycle=passed
```

测试在 `/private/tmp` 隔离目录中完成全量部署，输入固定序列 `nihao`，验证生成目标中文候选、选词提交和 session 成对销毁；控制台只输出布尔断言，不记录原始用户输入或候选内容。

## 架构、签名与运行时

- Debug 主程序：arm64；内嵌 librime：arm64 + x86_64。
- Release 主程序与内嵌 librime：arm64 + x86_64。
- Debug/Release 均通过 `codesign --verify --deep --strict`。
- `xcodebuild analyze` Debug 通过，无项目代码分析问题。
- 当前 Debug 安装目标为 `~/Library/Input Methods/windwhisper.app`，嵌套 dylib 先签、app 后签；新 Bundle 身份首次启用需要 macOS 人工授权。
- 已安装 bundle 再次独立运行同一 M2 smoke，全部断言通过。

## 未包含

- InputMethodKit controller 仍为 passthrough；真实应用中的 marked text、中文 commit 和按键映射属于 M3。
- M2 数据仅为官方最小测试 fixture，不是最终产品词库；双拼、辅码和词库选择属于 M6。
- x86_64 slice 只做编译、链接、架构和依赖静态检查；为避免在 Apple Silicon 上触发 Rosetta/Intel 兼容提示，没有启动 x86_64 进程。
- Hardened Runtime、Developer ID 和公证仍属于 M9；本机 ad-hoc 构建按 ADR-017 关闭 Hardened Runtime。
