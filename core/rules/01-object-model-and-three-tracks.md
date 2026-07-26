# 01｜对象模型与三轨

## 三条轨道

### LearningTrack

负责材料 intake、直接教学、拆解问答、迁移问答、学习结果和复习计划。对象包括 `LearningSession`、`TeachingDigest`、`QAReceipt`、`LearningResult`、`ReviewPlan`。

### KnowledgeAssetTrack

负责可复用知识对象的收录、合并、更新、分组与索引。对象包括 `ConceptCard`、`ModelCard`、`CaseCard`、`ReusableAsset`、`OntologyStatement` 和 `SourceCapsule`。

### CreationTrack

负责用户明确启动的 Topic、`ContentKernel`、成稿、载体版本和发布前交付。它不能由学习完成、资产收录、分享卡或热点自动触发。

## 核心对象

### LearningSession

记录材料指针、学习目标、当前阶段、已完成步骤、错误信号和下一动作。正文材料留在来源文件，不重复塞入每份回执。

### LearningResult

包含当前可解释的核心判断、已掌握部分、未掌握部分、边界、迁移表现、资产候选和 ReviewPlan 指针。它不是用户永久能力证明。

### ReusableAsset

统一描述可复用概念、模型、案例、论证结构、创作技巧或来源证据：

- `asset_id`、`asset_type`、标题和摘要；
- 输入、机制、输出和适用边界；
- 标签、对象、关系和反例；
- 来源指针与权利状态；
- 正文路径、索引状态、成熟度；
- 与其他资产的 same / variant / conflict / complement 关系。

### OntologyStatement

使用 `subject-predicate-object` 表达语义关系，并保存限定条件、来源、置信状态和反证。v0.1 是文件型本体，不要求图数据库。

### ContentKernel

创作唯一内核：读者问题、主判断、必要证据、案例岗位、模型岗位、结论边界和用户锁定项。载体变化不应复制一个平行内核。

## 状态转换

- 新材料默认只进入 LearningTrack。
- 学习中发现模型/案例可以形成 KnowledgeAssetTrack 候选，但不得未经核验覆盖既有核心对象。
- 普通分享卡不改变三轨状态。
- 只有用户明确要求“把这个主题做成内容/文章/视频”等，才进入 CreationTrack。
- 所有写入保留来源和前态；无法确认是新增、更新还是冲突时，先保留候选。
