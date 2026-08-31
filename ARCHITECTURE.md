# 双平台架构

WindWhisper uses one repository with explicit ownership boundaries:

| Directory | Responsibility | Platform |
| --- | --- | --- |
| `Core/` | C++17 engine, C ABI, shared golden tests, Swift adapter models | Shared |
| `Platform/macOS/` | InputMethodKit, AppKit candidate window, settings and installer integration | macOS |
| `Platform/Windows/` | TSF COM service, Win32/DirectWrite candidate window, registry settings | Windows |
| `CMakeLists.txt` | CMake entry point for shared and Windows targets | Shared |
| `Installer/Windows/` | x64 WiX MSI definition | Windows |
| `Resources/` | Dictionary, icons and localizations | Shared assets |
| `Scripts/` | macOS build, packaging and validation helpers | macOS |

The Xcode project references `Platform/macOS` and `Core/SwiftAdapter` directly;
Windows builds consume the root `CMakeLists.txt` and never depend on AppKit or
InputMethodKit sources.
