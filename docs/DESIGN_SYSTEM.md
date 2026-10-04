# 风语视觉规范

三端（macOS、Windows、iOS）的候选窗、状态提示和设置界面都从这份规范取值。修改颜色或尺寸时先改这里，再同步到各平台的实现：

- macOS：`Platform/macOS/CandidateWindow/CandidateWindowTheme.swift`（`FengYuPalette`）
- Windows：`Platform/Windows/CandidateWindow/CandidateWindow.cpp`（`kLightPalette` / `kDarkPalette`）、`Platform/Windows/TSF/InputModeIcon.cpp`
- iOS：`iOS/Keyboard/KeyboardViewController.swift`（`KeyboardPalette`）

## 原则

1. **克制**：输入法是工具，不抢正文的注意力。不用渐变、高光描边、外发光、彩色阴影。
2. **一处强调**：高亮候选只用一块浅色底和一个强调色序号，不叠加描边、粗体、徽标。
3. **平整的面**：候选窗是接近不透明的平面，系统材质只作为很淡的底，保证在任何背景上文字可读。
4. **中性灰阶**：灰色略带暖意，不发蓝。品牌色只出现在高亮序号、中文状态和少量控件上。

## 颜色

品牌色取名“黛蓝”，比系统蓝更沉、更安静。

| 角色 | 浅色 | 深色 | 用途 |
| --- | --- | --- | --- |
| surface | `#FAFAF8` | `#252629` | 候选窗、状态提示底色 |
| border | `#DEDED9` | `#3A3C40` | 0.5～1px 外框、分隔线 |
| textPrimary | `#1F2023` | `#ECEDEF` | 候选词 |
| textSecondary | `#6E7076` | `#9A9DA3` | 注释、页码 |
| textTertiary | `#85878D` | `#7E8187` | 非高亮序号、不可用箭头 |
| accent | `#2F6B8A` | `#86B6CF` | 高亮序号、中文状态、主按钮 |
| highlightFill | `#E4EDF1` | `#33434D` | 高亮候选底色 |
| highlightText | `#163F55` | `#E3EEF4` | 高亮候选文字 |

对比度（WCAG）：textPrimary/surface 约 15:1，textSecondary/surface 约 4.7:1，textTertiary/surface 约 3.5:1，accent/surface 约 5.6:1，highlightText/highlightFill 约 9:1，accent/highlightFill 约 4.8:1。

高对比度模式下，border 改用系统分隔色并加粗到 1.5px，高亮底色加深一档，其余不变。Windows 高对比度主题直接使用系统色（`COLOR_WINDOW`、`COLOR_HIGHLIGHT` 等）。

## 尺寸（逻辑像素 / pt）

| 项 | 值 |
| --- | --- |
| 候选窗圆角 | 8（高对比度 6） |
| 高亮块圆角 | 5 |
| 候选窗内边距 | 4 |
| 候选项高度 | 30 |
| 候选项水平内边距 | 8 |
| 序号与候选词间距 | 5 |
| 候选词字号 | 16pt（macOS）/ 14pt ≈ 19px（Windows）/ 19pt（iOS） |
| 注释、序号字号 | 12pt（Windows 15px） |
| 状态提示 | 48×48，圆角 8，字号 20 |

## 候选窗

- 序号是普通文字，不加底色块。非高亮用 textTertiary，高亮用 accent。
- 注释紧跟候选词，字号小一档、颜色用 textSecondary。
- 翻页区与候选之间用一条 border 色竖线分隔。能拿到总页数时显示“2/5”，拿不到时只显示当前页。

## 中/英状态

- 中文：accent 底，白字“中”。
- 英文：surface 底，textPrimary 字“英”，外加 border 描边。
- 两种状态靠“实心/空心”区分，不依赖相近色相。

## 图标

- 图形：三道错落的横向弧线，表示“风”，左上角留出空白。不用 3D、玻璃、高光。
- 颜色：accent 底、白色线条；小尺寸（16/32px）时线条加粗、减少到两道。
- 由 `Scripts/generate-brand-icon.swift` 一次生成母版、macOS 各尺寸和 iOS 1024 图标：`swift Scripts/generate-brand-icon.swift Resources/Assets/WindWhisperIconMaster.png Resources/Assets.xcassets/AppIcon.appiconset iOS/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png`。Windows 语言栏图标是单色“风”字，由 `Scripts/generate-windows-profile-icon.ps1` 生成。
