# 05｜柔性搜索 Lite

## Interface

`question + freshness + risk_class + scope → EvidencePacket`

支持两个 Adapter：

- `native_web_search`：当前工具可直接检索网页；
- `user_supplied_sources`：用户提供链接、文件或摘录。

无可用 Adapter 时返回缺口，不能把内部推测冒充外部搜索结果。

## adaptive_mode

默认先选择 `quick / standard / deep` 中最小够用模式：

- quick：单一低风险事实或已有明确来源；
- standard：需要多来源支持、时效核对或一般比较；
- deep：高风险、强争议、关系链、利益链或多种解释竞争。

模式由风险和证据结构决定，不由固定关键词决定。可以从 standard 降到 quick，也可以因 `evidence_gap` 升级。

## 柔性起点

通常从 1 个搜索轮、少量查询变体和少量高相关来源开始。它们不是固定配额：

- 一个权威来源足以支持窄事实时可以停止；
- 同一承重结论需要独立支持时增加来源；
- 领域来源高度集中时不强造“多样性”；
- 来源互相抄写不算独立；
- 新近事件同时核对发布日期和事件发生时间。

第二轮只由命名的证据缺口、冲突、时效失败、原始来源不可达或高风险验证触发。扩展写 `expansion_receipt`。

## SourceCapsule

主上下文只接收：

- 标题、作者/机构、日期、URL 或本地指针；
- 来源类型和独立性；
- 支持或反驳的主张；
- 关键限制、利益关系和不确定性；
- 需要回看原文的位置。

网页正文、搜索结果页、重复摘要和无关推荐留在工具侧。承重证据原物仍保留可回读指针。

## 判断与停止

输出区分：

- confirmed：来源直接支持；
- best_current_judgment：证据不足以完全证实，但有当前最佳判断；
- inference：由多项事实推演；
- unknown：当前无法核验。

停止条件是：每个承重主张已达到其风险等级所需的支持，最强替代解释已经被看见，继续搜索不太可能改变结论。不是“来源数达标”。

## 预算

`soft_target` 约束正常 startup 和证据胶囊总量。超出 soft target 时先去重、压缩重复描述和分离原始载荷；不得删掉证据身份、关键反例或不确定性。超过 advisory ceiling 时建议分阶段交付；超过 hard safety ceiling 必须拆分范围。
