# Windows x64 开发交接

## 交接基线

- 分支：`feature/windows-tsf-port`
- macOS 目录重构提交：`0a3bc3d`
- Windows 当前状态：共享核心可在 macOS 用 CMake 编译并通过 golden test；TSF DLL、DirectWrite 候选窗和 MSI 尚未在 Windows SDK 环境编译。
- 目标系统：Windows 10/11 x64。ARM64 不属于首期范围。

## 2026-08-31 Windows 续作状态

Windows x64 的 TSF 输入链路、COM/TSF 注册器和 WiX 安装包已经可以进入真实机器安装测试：

- Debug/Release 均可构建，`golden`、`tsf_factory`、`windows_key_mapper` 均通过。
- `fy_tsf.dll` 已实现 COM class factory、thread/context sink、独立 session、异步 edit session、composition 更新/提交/取消和停用清理。
- MSI 包含 x64 `fy_engine.dll`、`fy_tsf.dll` 和 `fy_tsf_registration.exe`，并具有安装、卸载、升级失败回滚动作。
- 卸载不触碰 `%LOCALAPPDATA%\WindWhisper\InputMethod`。

构建安装包：

```powershell
pwsh -NoProfile -File Installer/Windows/build-msi.ps1 -Configuration Release
```

执行真实安装并自动检查 COM、DLL 加载和中文 TSF profile：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File Installer/Windows/Install-And-Test.ps1
```

安装或替换 DLL 后不需要注销。刷新语言栏和当前会话 profile：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File Installer/Windows/Refresh-Tsf.ps1
```

也可以直接双击 `Installer/Windows/Refresh-Tsf-OneClick.cmd`，无需打开 PowerShell。

该脚本会重启 `ctfmon.exe` 和 Windows 11 的 `TextInputHost.exe`，并重新激活 profile；已经打开的记事本、浏览器等仍需关闭后重新打开，以便宿主重新加载 DLL。需要同时刷新任务栏语言指示器时可追加 `-RestartExplorer`。如果 `activate` 因当前会话已经持有 profile 返回 `E_FAIL`，脚本会以 `status` 验证注册仍健康，不要求注销。

脚本会请求一次 UAC，并把完整日志写到 `build/windows/Installer/install.log`。安装包尚未数字签名，本机开发测试时 Windows 会显示“未知发布者”。卸载并验证用户数据保留：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File Installer/Windows/Install-And-Test.ps1 -Uninstall
```

2026-08-31 回归更新：Windows C++ 核心已读取同一份 `Resources/fy.dict.yaml`，并覆盖全拼、小鹤双拼、小鹤音形、长句分词、候选排序、反查辅码、四键自动提交、方向键/分页和简繁转换；MSI 同时携带词库与用户词典覆盖。Release 自动化通过 `golden`、`dictionary_smoke`、`tsf_factory` 和 `windows_key_mapper`。输入指示器兼容性已注册 `GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT` 与 `GUID_TFCAT_TIPCAP_SYSTRAYSUPPORT`，并从 `fy_tsf.dll` 提供品牌/模式图标资源。

候选窗目前是 Win32/GDI 非激活实现，鼠标选词、DPI 自适应和多屏边界仍需在真实 Windows 桌面按下方人工矩阵确认。Windows 只注册一个“风语输入法” profile；通过输入指示器旁的模式按钮（`GUID_LBI_INPUTMODE`）选择小鹤音形（默认，四码自动上屏）、小鹤双拼或全拼，选项保存到当前用户注册表。Windows 11 会忽略自定义 GUID 的语言栏项目，因此不能再注册三个独立 profile 来模拟模式。

## 环境准备

安装 Visual Studio 2022，并选择：

- Desktop development with C++
- MSVC v143 x64 toolset
- Windows 10 或 Windows 11 SDK
- CMake tools for Windows
- WiX Toolset 4（安装阶段再启用）

使用 x64 Native Tools Command Prompt 或 Developer PowerShell。仓库路径尽量不包含中文和空格。

## 第一轮构建

```powershell
git switch feature/windows-tsf-port
cmake -S . -B build/windows -A x64
cmake --build build/windows --config Debug
ctest --test-dir build/windows -C Debug --output-on-failure
cmake --build build/windows --config Release
ctest --test-dir build/windows -C Release --output-on-failure
```

预期生成 `fy_engine.dll`、`fy_tsf.dll` 和 `fy_engine_golden.exe`。首次构建很可能暴露 MSVC、Windows SDK 或 COM 接口签名问题；先保存完整 CMake configure 和 build 输出，不要绕过失败文件。

## 当前代码边界

| 路径 | 当前内容 | 接下来负责的工作 |
| --- | --- | --- |
| `Core/include/fy_engine.h` | UTF-8 C ABI | 保持 ABI 稳定，补错误码、快照所有权和配置刷新 |
| `Core/src/fy_engine.cpp` | 最小候选和 golden fixtures | 从 Swift 引擎迁移完整词典、beam search、语言模型、简繁、全半角和用户词典 |
| `Platform/Windows/TSF` | COM 对象和 class factory 骨架 | 完成 sink 注册、edit session、composition、commit、停用清理和 DLL 生命周期 |
| `Platform/Windows/CandidateWindow` | 非激活 Win32 窗口骨架 | DirectWrite 绘制、DPI、多屏、插入点定位、鼠标选择和滚轮翻页 |
| `Platform/Windows/Settings` | 注册表布尔设置与数据目录 | 用户词典管理和更完整的设置 UI |
| `Installer/Windows` | WiX 文件与注册参考 | COM/TSF profile 注册、x64 MSI、升级/回滚/卸载和用户数据保留 |

`Core/SwiftAdapter` 仍是 macOS 当前生产输入算法，不能删除。C++ 核心达到同等 golden 覆盖后，才通过 C ABI 替换 macOS 的 Swift 算法实现。

## 必须完成的 TSF 链路

1. `ActivateEx` 中获取并保存 `ITfThreadMgr`，通过 `ITfKeystrokeMgr::AdviseKeyEventSink` 注册 key sink；`Deactivate` 对称解除。
2. 为每个活动 `ITfContext` 管理独立 `fy_session`，焦点切换和停用时清理 composition，禁止跨应用复用状态。
3. `OnTestKeyDown` 只判断是否可能消费；`OnKeyDown` 将 Windows virtual key 和 modifiers 映射到 C ABI，并在不支持的上下文安全透传。
4. 使用异步 `ITfEditSession` 调用 `ITfContextComposition::StartComposition`、更新 range 文本并在提交时 `EndComposition`。
5. 处理 context 销毁、输入源切换、应用退出和 edit-session 拒绝，保证没有残留 marked text 或重复 commit。
6. 支持 Space/Return/数字选词、Backspace/Escape、PageUp/PageDown、`-`/`=` 和小鹤音形 `~` 反查。
7. 单独按下并释放 Shift 切换中/英文；已有组合先将编码原样上屏，Shift+字母以及 Ctrl/Alt/Win+Shift 不得误切换。
8. 任务栏风语按钮左键直接切换中/英文，右键显示原生设置菜单；键盘 Shift 与按钮必须共享同一个模式状态。
9. 右键菜单提供输入方案、全角/半角和简体/繁体，移除额外设置窗口入口；切到中文自动全角，切到英文自动半角。

## 共享核心差距

当前 C++ 实现只是验证 ABI 的最小实现，不等价于 macOS Swift 引擎。Windows 可用前必须迁移并用同一套 fixtures 覆盖：

- 从 `Resources/fy.dict.yaml` 读取全拼、小鹤纯音码、小鹤音形和 essay 数据。
- 长句 beam search、二元/三元统计重排及稳定排序。
- `nihao`、`haishiyiyang`、`womenkeyiyiqi` 的首选和 commit。
- `ni~ -> 你 / nirx`、`ni~r -> 倪 / nire`，注释不得进入 commit。
- 候选分页、高亮、数字选择、`-` 上翻和 `=` 下翻。
- 简繁转换、全半角、非法编码、空候选、超长输入。
- `%LOCALAPPDATA%\\WindWhisper\\InputMethod\\custom_words.tsv` 的覆盖、刷新和升级保留。

## 候选窗和 DPI

- 创建 `WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW` 窗口，不夺取宿主焦点。
- 通过 TSF range/view 获取插入点矩形；失败时隐藏候选窗，不使用固定屏幕坐标。
- 启用 Per-Monitor DPI Awareness V2，处理 `WM_DPICHANGED` 和跨屏移动。
- 使用 DirectWrite 绘制候选正文、注释、高亮、序号和页码。
- 鼠标点击调用 `fy_session_select_candidate`，滚轮调用 `fy_session_page`。

## 安装器门禁

MSI 至少需要：

- x64 COM InprocServer32 注册，路径指向实际安装目录，`ThreadingModel=Both`。
- 使用 `ITfInputProcessorProfiles` 注册 text service、中文语言 profile、显示名和图标。
- 升级前后 profile 可用；安装失败能回滚旧 DLL 和注册项。
- 卸载删除组件/profile，但保留 `%LOCALAPPDATA%\\WindWhisper\\InputMethod`。
- DLL 被应用加载时给出明确的重启/注销策略，不能静默留下半升级状态。

## Windows 验证顺序

1. Debug/Release CMake configure、build、CTest 全部通过。
2. 用测试程序验证 `CoCreateInstance(CLSID_FengYuTextService)` 成功，接口查询和释放无泄漏。
3. 手工注册开发 profile，只在测试机启用；先验证 Notepad 的输入、composition、commit 和停用清理。
4. 验证 WordPad（若系统提供）、WPF textbox、Chromium/Edge 网页输入框。
5. 验证快速切换输入法、应用焦点切换、窗口关闭、休眠恢复和进程退出。
6. 验证 100%、150%、200% DPI、双显示器和跨屏候选定位。
7. 最后构建 MSI，执行全新安装、覆盖升级、失败回滚、卸载和用户词典保留。

任何 composition 残留、重复提交、吞掉宿主快捷键、候选窗抢焦点或卸载删除用户词典，都属于阻断缺陷。

## 问题回传

Windows 上首次验证后，保留并回传：

- Windows 版本与 build number、Visual Studio/MSVC、Windows SDK、CMake 和 WiX 版本。
- 执行的完整命令、首个失败的完整错误以及其前后至少 30 行输出。
- `build/windows/CMakeCache.txt` 中的 generator、architecture 和 compiler 信息。
- 若能加载 DLL：宿主应用、输入步骤、预期/实际结果、是否残留 composition，以及 Event Viewer 中对应错误。
- 安装问题：MSI verbose log（`msiexec /i WindWhisper.msi /L*V install.log`），不要包含真实输入内容或用户词典正文。
