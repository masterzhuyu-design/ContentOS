# 10｜独立语义审阅、冻结实验与适配器

## 独立语义审阅

`artifact_semantic_review` 的 reviewer 只接收 review objective、source/evidence boundary 和 current artifact。生产者计划、自评、期望答案和旧审阅不具有说服力。

结果只有：

- `pass`：可见产物在授权边界内形成了所需语义闭包；
- `needs_rework`：关系矛盾或产物失真；
- `blocked_evidence`：承重关系缺少可判断证据。

静态 validator、schema 齐全、消费者能解析都不能单独冒充 semantic pass。

## 实证预注册

观察前冻结：研究问题、对照/干预、未见 holdout、指标、阈值、遥测、每个 cell 的尝试规则、停止规则和最大结论。预注册通过不自动授权执行。

## 冻结执行

`empirical_research_execution` 只通过显式 runner adapter 执行一个已冻结合同。执行前重新核验合同和 source binding；执行中保存实际尝试、失败、缺失观察和遥测；执行后不能因结果不好而改阈值、补跑或扩大结论。

模型、HTTP/provider、平台或 transport 内部行为，只能在实际遥测覆盖的层级作结论。

## 适配器合同

公共核心定义 capability、输入、权限、输出和停止状态；实例适配器负责外部系统细节。每个适配器至少声明：

- `adapter_id` 和版本；
- 支持的 canonical TaskKind；
- 读取和写入范围；
- 所需授权；
- 幂等/重试语义；
- 可回读输出；
- 失败后的副作用状态。

适配器缺失时返回明确 blocked 状态，不能静默把 canonical 功能解释成“不需要”。适配器存在或自报授权也不等于宿主已经核验；公共解析器只做到结构准入，实际宿主必须另行建立权限、执行和回读事实。

## Registry 与历史迁移

Registry 由实例的 single-writer adapter 持有。学习任务产生 source-bound receipt；同步任务幂等投影，不能由多个学习线程直接改共享表。

历史 backfill 只结构化已有记录，不改旧题、答案、分数、资产成熟度或来源。迁移后保留旧指针和回滚基线。
