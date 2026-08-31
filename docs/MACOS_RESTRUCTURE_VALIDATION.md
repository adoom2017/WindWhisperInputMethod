# macOS 双平台重构验证

## 验证环境

- 日期：2026-08-31
- 架构：Apple Silicon arm64
- 配置：Debug 与 Release
- 工具链：Xcode 26.4.1，macOS SDK 26.4

## 已执行

```text
Scripts/verify-project.sh
Scripts/build.sh Debug
Scripts/build.sh Release
windwhisper --engine-smoke
windwhisper --m3-smoke
windwhisper --m4-smoke
windwhisper --m5-smoke
windwhisper --m7-smoke --user-data-root <isolated-directory>
windwhisper --m8-smoke --user-data-root <isolated-directory> --stress-seconds 2
cmake -S . -B <temporary-build-directory>
cmake --build <temporary-build-directory>
ctest --test-dir <temporary-build-directory> --output-on-failure
```

目录重构后 Xcode Debug 与 Release 构建、资源打包、ad-hoc 签名和 runtime 校验通过；Release 主程序包含 arm64 和 x86_64。输入核心、M3、M4、M5、M7 和共享 C++ golden tests 通过。验证时修复了 M7 命令误路由到 engine smoke 的问题，并确认设置持久化、迁移、菜单、繁简、诊断脱敏和恢复默认均实际执行。M5 的离屏视觉快照需要可访问 WindowServer 的执行环境；受限沙箱内会在断言完成后退出，非沙箱图形会话中 `visualSnapshots=passed`。

M8 两秒短压力测试通过：普通按键路径 P95 为 2.338 ms，测试结束时活跃 session、快照分配和 RSS 增长均为零。该短测试只用于目录重构回归，不替代 Release 3600 秒门禁、Intel、macOS 13、多显示器和真实应用矩阵。
