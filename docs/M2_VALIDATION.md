# M2 验证记录

M2 验证原生 Swift 输入引擎和单一内置词库资源。

## 验证内容

- `Resources/fy.dict.yaml` 是唯一随包词库资源，应用包不包含分散词典、schema、动态库或 external runtime。
- 词库行格式为 `词条<TAB>编码<TAB>权重<TAB>来源<TAB>原始顺序`。
- 候选排序先匹配完整编码，再按权重降序，最后按原始顺序升序；相同词条只保留首个候选。
- `InputService` 启动时解析词库并建立前缀索引，运行时不需要部署或生成额外文件。
- 自定义词条保存在用户目录的 `custom_words.tsv`，不会修改内置词库。

## 结果

- `Scripts/verify-project.sh` 通过，词库 SHA-256 锁定为
  `656ac1929458eae577ae372ec158a725e158392ebf80ddd7a94a34976b8a0bc2`。
- Debug 构建通过，资源阶段只复制 `fy.dict.yaml`。
- 引擎 smoke 通过：全拼、小鹤纯音码、小鹤音形、四键自动提交、多候选排序和自定义词条均正常。
