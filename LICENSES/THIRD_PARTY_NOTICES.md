# 第三方组件清单

## 风语词库

`Resources/fy.dict.yaml` 是项目内置的合并词库，包含全拼、双拼、音形和辅助候选数据。文件中的 `weight` 与 `original-order` 列保留合并前的候选优先级。

词库来源、许可和生成规则以项目提交记录及 `docs/DICTIONARY_AUDIT.md` 为准。小鹤音形部分为用户自行提供的本地词库。

## iOS 小字集

`iOS/Resources/allowed_characters.txt` 派生自
[mozillazg/pinyin-data](https://github.com/mozillazg/pinyin-data) 的
[`tools/china-8105-06062014.txt`](https://github.com/mozillazg/pinyin-data/blob/923b108dc5d45dee061324c011b478fb649f8b73/tools/china-8105-06062014.txt)，
固定提交为 `923b108dc5d45dee061324c011b478fb649f8b73`。该字表包含完整的 8,105 个唯一字符，
用作 iOS 内置词库的字符边界，不包含之前 GPL 来源版本额外收录的字符。

上游许可证为 MIT，Copyright (c) 2016 mozillazg；完整原文保存在
[`pinyin-data-MIT.txt`](pinyin-data-MIT.txt)，并随 iOS 键盘扩展打包。
`Scripts/import-ios-characters.rb` 校验上游文件 SHA256 后提取 Unicode 码点，保留源文件顺序。
此 MIT 许可仅适用于字表来源，不改变合并词库中其他数据的来源及适用许可。

## 风语代码

应用代码由项目维护者编写，使用 Apple InputMethodKit、AppKit 和 Swift 系统框架。

## 风语图标

应用图标、输入法菜单图标和切换器图标均为风语原创资源。
