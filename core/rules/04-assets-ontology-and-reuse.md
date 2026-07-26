# 04｜资产、本体与后期复用

## 收录范围

可收录：

- Concept：清晰概念与边界；
- Model：输入、机制、输出和适用范围明确的模型；
- Case：事实过程、关键变量、结果和解释边界明确的案例；
- Structure：可复用论证结构；
- Technique：可复用学习或创作技巧；
- Source：来源胶囊；
- OntologyStatement：对象间关系。

收录不是把聊天原文整段复制。对象必须有自己的摘要、来源、机制、边界和正文指针。

## 模型与案例

ModelCard 至少记录：

- 解决什么问题；
- 输入、处理机制和输出；
- 适用条件、失效条件、误用方式；
- 相关概念、案例和反例；
- 来源和成熟度。

CaseCard 至少记录：

- 背景、参与对象和时间；
- 发生过程而非只有结论；
- 可确认事实与解释分开；
- 哪个模型能解释哪一段；
- 与目标情境的关键差异；
- 版权、隐私和来源状态。

## 文件型本体

OntologyStatement 使用：

- `subject`：对象；
- `predicate`：关系；
- `object`：另一对象或值；
- `qualifiers`：时间、范围、条件；
- `source_pointer`；
- `confidence_state`；
- `counterevidence`；
- `status`。

关系可以是 `is_a / part_of / causes / enables / constrains / conflicts_with / variant_of / evidenced_by / applies_to` 等。不要为了“建图”制造无意义关系。来源变化时更新 statement 状态，不静默覆盖旧证据。

v0.1 的本体由 JSON 对象和索引表达；GraphRAG、向量检索和图数据库只在真实瓶颈出现后升级。

## ReusableAsset 索引

索引只保存：

- ID、类型、标题、短摘要；
- 机制标签、对象标签、边界标签；
- 正文路径与来源指针；
- 成熟度与最近核验时间；
- 关系指针。

正文不进入索引。索引可重建，但对象正文是 source truth。

## AssetReusePlanner

Interface：

`reuse_goal + task_context + optional asset_types → ReusePlan`

内部流程：

1. 从索引按对象、机制、关系和边界召回少量摘要；
2. 比较候选与当前任务的真实连接；
3. 做删除测试和冲突检查；
4. 返回 `use / backstage / no_use`、岗位和理由；
5. 只读取 `use` 候选正文；`backstage` 只用于校准，`no_use` 不再加载。

没有固定调用数量。0 个合适候选优于硬塞 3 个；复杂任务也可以因净增益扩展。扩展必须记录 `expansion_receipt`。

## 在学习与迁移中的调用

- 教学：旧模型/案例帮助解释机制或边界，但不替代当前材料。
- 拆解问答：旧资产只用于必要对照，不泄漏答案。
- 迁移问答：优先比较机制同构和关键差异，拒绝表面类比。
- 复习：根据历史错误选择最能暴露误区的旧资产。
- 创作：先确定主线，再把资产绑定到具体论证岗位，不做模型陈列。

## 合并与冲突

- same：合并来源或表述；
- variant：保留差异条件；
- complement：建立互补关系；
- conflict：并列保留证据和争议；
- novel：新建对象。

核心对象覆盖、正式删除或移动仍需用户确认。自动处理只能作用于非核心、低风险的新增索引和明确同义合并。
