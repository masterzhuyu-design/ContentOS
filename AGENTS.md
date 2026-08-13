# ContentOS 统一入口

## 启动

1. 读取 `.contentos/config.json`；未初始化时读取 `config/contentos.example.json`。
2. 从 `core/profiles/task-profiles.json` 选择稳定 TaskKind，不用聊天临时名称替代。
3. 从宿主取得真实当前 turn，按 `core/schemas/task-execution-input.schema.json` 构造完整输入。当前消息用 `current_turn_inline`，文件资产用 `workspace_artifact` 并绑定实际 SHA256。
4. 运行：

```powershell
.\scripts\resolve-contentos-startup.ps1 -Profile <full|lite> -TaskKind <kind> -TaskExecutionInputJson <json>
```

5. 只有 `status=ready`、`task_execution.status=ready` 和 `generation_allowed=true` 才执行。`ready_adapter_pending_host_authority` 只表示适配器结构可读，不能执行。规则已加载不等于输入、适配器或权限已经闭合。

## 工作方式

- 先判断任务是讨论、直接成品、执行修改还是组合；内部审查不直接污染对外成品。
- 默认先给当前最佳判断或干净成品。只展示会改变结论、行动或风险的依据，不倾倒流程日志和治理术语。
- LearningTrack、KnowledgeAssetTrack、CreationTrack 分离。学习完成、资产收录和普通分享都不自动启动创作或发布。
- 每次有效学习作答后触发一次轻量旧知识增益检查；只在有净增益时读取具体候选，不把知识库常驻进上下文。
- 折叠界面不是“没有内容”。评分、迁移、恢复和非教学任务都必须绑定本轮完整承重输入；暂停或续接后重新核对当前 turn 或工作区资产摘要，不能拿摘要猜答案或静默跳过。
- 搜索、模型、案例、轮次和字节预算都是柔性起点，不是平均化配额。极端风险任务先守 ruin boundary；普通任务不套重大决策仪式。
- 历史、虚构或特殊世界观从作品内部逻辑推演，不擅自补现代人类法律、年龄标准、报应或说教。

## 写入与维护

- `vault/` 内的 Markdown/JSON 是实例真相源；`.contentos/runtime/` 只保存可恢复状态和紧凑回执。
- 只写当前明确授权的目标。发布、账号写入、实验执行、调度和不可逆删除都需要独立授权。
- 公共核心拥有 TaskKind、对象、状态转换和适配器接口；私人实例拥有个人资料、Registry、checkpoint、凭据和平台绑定。
- 发现重复问题时在唯一 owner 修根因：重复的合并，冲突的修改，失效的删除；不要继续堆补丁、helper 或第二真相源。
- 完成必须有实际修改、回读、行为验证和副作用检查。计划、测试数量和回执数量不能冒充功能结果。

## 兼容与 profile

`full` 和 `lite` 都读取同一份 canonical task manifest。Lite 兼容脚本只转发到 canonical 入口，不拥有独立规则。适配器缺失时明确阻断，不得把“可选加载”解释成“这项功能以后不用”。

WorkBuddy、Trae 或其他外部客户端只走 `.agents/skills/contentos-external-proposal/SKILL.md` 与 proposal-only 入口；宿主当前 turn 必须与输入逐值相同，外部会话不会取得 checkpoint、写入或采用权。
