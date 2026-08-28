# 风语开发计划

## 当前架构

- InputMethodKit 负责系统输入法生命周期。
- `NativeRuntime` 和 `InputService` 提供原生 Swift 输入引擎。
- `CandidateWindow` 只负责候选展示、定位和交互。
- 应用资源只包含 `Resources/fy.dict.yaml` 及品牌和本地化资源。

## 词库计划

- 词库行格式：`词条<TAB>编码<TAB>权重<TAB>来源<TAB>原始顺序`。
- 启动时一次性解析并建立前缀索引。
- 候选先匹配完整编码，再按权重降序、原始顺序升序排列。
- 用户词条写入 `custom_words.tsv`，使用更高权重参与排序。
- 菜单中的“刷新配置”在后台重新加载用户词条，成功后立即切换全部输入会话。

## 功能状态

- [x] 小鹤音形、 小鹤纯音码、风语全拼。
- [x] 四键唯一候选自动提交。
- [x] 辅码候选过滤和候选注释。
- [x] 设置持久化、简繁选项、候选窗横竖排和主题。
- [x] 输入事件透传、会话生命周期和候选窗失效保护。
- [x] Debug/Release 构建、资源校验和发布包校验。

## 验证命令

```text
Scripts/verify-project.sh
Scripts/test-m3.sh Debug
Scripts/test-m4.sh Debug
Scripts/test-m5.sh Debug
Scripts/test-m6.sh Debug
Scripts/test-m7.sh Debug
Scripts/test-m8.sh Release
```

所有测试使用隔离的临时用户目录，不读取或生成项目外的词库文件。

## 后续工作

- 在 macOS 13、Intel 和干净用户账户执行安装与发布验收。
- 获得正式签名与公证凭据后验证 signed/notarized 发布模式。
