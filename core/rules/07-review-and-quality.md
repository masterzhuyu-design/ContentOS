# 07｜审阅与质量

## 审阅前提

先确认审阅对象、用户要求、ContentKernel 或来源指针，以及哪些内容已经通过。只要求“审查”时不自动重写。

## 失败信号

按实际信号选择镜头，不把所有检查都跑一遍：

- factual：事实、日期、引用或来源不成立；
- semantic：承重意义丢失、关系失真、确定性漂移；
- reasoning：段落之间没有推动关系；
- scope：切入面过散或超出授权；
- case：案例被压成标签、缺过程或不能支持主张；
- qa：问题缺输入、答案错位或推理被省略；
- authorship：多个独立信号共同造成模板感和读者距离；
- rights：表达、隐私、平台或再分发风险；
- medium：载体结构损害信息完整性。

一个禁词、一个标点或单一“AI 分数”不能独立判定失败。

## 修复顺序

1. 找到最早失效层；
2. 冻结已经通过的意义与用户锁定项；
3. 只修最强 1–3 个读者损失；
4. 回读语义、事实和结构差量；
5. 仍有阻断失败才追加一轮。

返工不能把失败稿当真源，也不能为了“换一种感觉”重写全部合格内容。

## 分享卡质量

普通学习分享卡应可独立阅读，并保留问题、回答、迁移案例和边界。后台评分、状态机字段和治理术语不进入正文。载体容量不足时让用户选择分卡或范围，不把完整问答压成关键词。

## 创作质量

成稿至少满足：

- 读者承诺明确；
- 主判断可辨；
- 论证有连续递进；
- 案例和模型有岗位；
- 反例和边界与主线相关；
- 信息密度来自内容，不来自堆砌；
- 结论强度与证据强度匹配。

## 回执

ReviewReceipt 只记录：

- 结论：pass / targeted_repair / return_upstream；
- 最早失败层；
- 承重缺口；
- 已冻结部分；
- 修改范围；
- 证据指针；
- 是否需要扩展预算。

## 可执行质量门

相关 TaskKind 的 startup 会投射同一个只读 Interface：

`QualityObservation → QualityDecision`

`QualityObservation` 只提交当前成品上可观察的事实，不提交完整材料或工具原始输出。`QualityDecision` 返回：

- `pass`：可以继续；
- `targeted_repair`：冻结已通过表面，只修命名缺口；
- `return_upstream`：返回最早责任层，例如教学、ContentKernel 或 Reasoning Spine；
- `blocked`：缺真源、越权或正在做语义截断，必须先解除阻断。

Module 不生成正文、不写状态、不发布，也不授予整篇重写。只有 ContentKernel 或 Reasoning Spine 失败时，`full_rewrite_allowed` 才能为 true。

### discussion_delta_integrity

分享卡、创作和返工都把讨论视为差量，不把最近聊天当真源。调用前绑定：

- `canonical_source_digest`；
- `load_bearing_units`；
- `confirmed_adjustment`；
- `candidate_option`；
- `rejected_option`；
- `clarification_only`。

新稿应用项必须是 confirmed adjustment 的子集。任何 candidate option、rejected option 或 clarification only 进入正文，均记 `unconfirmed_discussion_applied`；没有明确删除授权却丢失 load bearing units，记 `canonical_content_dropped`。修复时重新绑定 canonical source，只应用确认差量并恢复遗漏单元，不能靠整篇重写重新猜原意。
