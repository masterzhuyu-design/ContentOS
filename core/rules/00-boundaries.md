# 00｜总边界

## 单一真相源

用户知识、学习状态、资产和本体关系以 `vault/` 内的 UTF-8 Markdown/JSON 为真相源。`.contentos/runtime/` 只保存可恢复 checkpoint 与紧凑回执；缓存和以后可能接入的索引都可重建，不能反向覆盖真相源。

## 权限

- 读取、分析和生成候选不等于获得写入、发布或账号操作权限。
- 只写用户本轮要求的对象。删除、移动、覆盖核心规则、发布、账号登录和自动任务必须另有明确授权。
- LearningTrack、KnowledgeAssetTrack、CreationTrack 分离。学习通过、资产值得收录、内容适合分享都不自动启动 CreationTrack。
- 普通分享卡是 `detached_share_export`：默认只返回正文，不自动生成图片、视频、平台版本或持久创作状态。

## 最小上下文

- 每个任务只加载对应 TaskKind 的规则与已选择对象。
- 原始网页、完整工具输出、全库正文和未选候选不进入主上下文。
- 先读索引摘要，确认采用后再读对象正文。
- checkpoint 只保存状态、边界、未完事项和证据指针，不复制完整会话。

## 柔性与质量

`adaptive_mode` 是默认运行方式。默认数量、轮次、时间间隔和 byte 预算是起点或软线，不是固定配额。可以更少，也可以因风险、证据缺口、复杂度、学习表现或用户要求而扩展。

扩展要有 `expansion_receipt`，至少说明触发信号、增加的范围、预期净增益和停止条件。没有净增益就不扩展。

`semantic_truncation_forbidden`：不得为了满足 Token/byte 预算，删除承重观点、完整案例、问题输入、答案推理、证据身份、边界条件或用户锁定内容。容量不足时拆分范围或请用户选择。

## 状态与错误

- 输入未闭合：`blocked_missing_inputs`。
- 证据摘要过期：`blocked_stale_digest`。
- 路径越界：`blocked_path_escape`。
- 超过硬安全上限：`blocked_budget_overflow`，返回可拆分范围。
- 工具失败或结果未知：先核对副作用；不盲目重试。
