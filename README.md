# ContentOS

ContentOS 是一个文件优先、规则驱动的个人知识系统：它把学习、知识资产、证据研究、创作、审阅和恢复做成可检查的任务合同，同时让你的 Markdown/JSON 文件继续作为真相源。

当前分支是 `v0.2.0-rc.2` 公开候选版。公共核心从私人实例中抽离，不包含任何原作者的笔记、学习记录、Registry、checkpoint、账号数据、凭据、附件或运行数据库。

**English summary:** ContentOS is a file-first, rule-driven personal knowledge system for learning, evidence research, reusable knowledge assets, creation, review, and recoverable agent workflows. The public repository contains one canonical 28-task contract with full and lite profiles while keeping private instance data outside the project.

## 它解决什么问题

- 学完的内容不只停在聊天里：教学、问答、迁移、复习和资产候选有连续状态；
- 已有模型、案例和知识会在合适的环节按需召回，帮助改进回答，但不会常驻污染上下文；
- 搜索先服务于真实问题和证据缺口，不用来源数量冒充研究质量；
- 创作保留主线、声音和力度，内部判断纪律不会变成对外成品的审计腔；
- 审阅定位最早失效层，优先局部修复，不默认整篇重写；
- 维护从真实 owner 修根因，避免一层层追加规则和回执。

## 一个公共核心，两个配置档

- `full`：公开的 28 个 canonical TaskKind 全部可见。21 项可以在公共启动合同内直接准入；7 项属于适配器合同，公共解析器只验证结构，并保持 `ready_adapter_pending_host_authority`，直到真实宿主独立核验权限和副作用。
- `lite`：同一合同的低上下文预设，默认开放 15 个常用任务。它不是第二套产品或真相源。

平台、账号、实验 runner、视觉渲染、Registry 和 KnowledgeOS 可以作为实例适配器接入；适配器只负责外部系统细节，不能改写 canonical 任务语义。仓库不捆绑模型推理引擎，也不把匿名合同测试冒充真实领域输出。

## 快速开始

在发行目录中安装完整档：

```powershell
.\scripts\init-contentos.ps1 -Destination '..\ContentOS-Workspace' -Profile full
```

想先从小配置开始：

```powershell
.\scripts\init-contentos.ps1 -Destination '..\ContentOS-Workspace-Lite' -Profile lite
```

进入新目录后运行：

```powershell
.\tests\run-all.ps1
```

启动一个任务的例子。承重输入不是一组随意的字符串，而是绑定到真实当前 turn 的结构化对象：

```powershell
$turn = 'your-host-current-turn-id'
$input = @{
  schema = 'contentos-task-execution-input-v1'
  scope_id = 'extreme-risk-article'
  current_turn_id = $turn
  task_kind = 'direct_topic_creation'
  task_stage = 'creation_planning'
  bindings = @(
    @{role='topic'; adapter='current_turn_inline'; source_pointer="current_turn:${turn}:topic"; value='为什么平均值会掩盖极端风险'},
    @{role='target_medium'; adapter='current_turn_inline'; source_pointer="current_turn:${turn}:target_medium"; value='article'},
    @{role='user_locks'; adapter='current_turn_inline'; source_pointer="current_turn:${turn}:user_locks"; value=@('保留鲜明判断','不用企业公文腔')}
  )
} | ConvertTo-Json -Compress -Depth 8

.\scripts\resolve-contentos-startup.ps1 `
  -Profile full `
  -TaskKind direct_topic_creation `
  -TaskExecutionInputJson $input `
  -Pretty
```

只有 `status=ready` 且 `generation_allowed=true` 才继续执行。空白承重内容、错误 turn、额外字段、超大输入、摘要漂移、路径越界或 reparse 跳转都会明确阻断。适配器对象里的 `authorization` 只是调用方声明，不是宿主已经授权的证明，因此公共解析器不会据此开放执行。

学习材料可使用任何 UTF-8 语言。`.contentos/config.json` 中的 `language` 是默认教学与输出语言；当前任务里的明确语言要求优先，关键术语和不能无损翻译的表达保留原文。英文、日文或混合语言材料不会另建一套学习状态。

外部 AI 客户端使用 `.agents/skills/contentos-external-proposal/SKILL.md` 和 `scripts/invoke-contentos-external-client-boundary.ps1`。它们可以得到 proposal-only 结果，但不能借外部会话 ID 选择 checkpoint、写文件或声称采用。

## 功能和边界

公开能力清单在 [`core/capabilities/public-capability-map.json`](core/capabilities/public-capability-map.json)，合同覆盖和测试能证明什么见 [`docs/functional-parity.md`](docs/functional-parity.md)。

这套仓库提供任务合同、对象模型、状态边界、初始化脚本和确定性验证；实际推理可由 Codex 或其他能遵循 `AGENTS.md` 与 task envelope 的 agent 完成。它不会自动登录账号、发布内容、运行实验、恢复定时任务或覆盖你的已有知识库。

## 密钥安全

不要把 API key、访问令牌、Cookie、密码或私钥写进仓库、任务输入、checkpoint、回执或 Issue。适配器绑定里的 `authorization` 只描述获准的读写权限，不承载凭据；真正的凭据应由适配器从进程环境或实例专用、已忽略的本地密钥存储中读取。

发布测试会扫描工作树、Git 暂存索引和完整可达历史中的常见密钥格式与敏感文件名，命中时直接阻止发布且不回显密钥正文。如果密钥曾经进入提交历史，仅从最新文件删除是不够的：应先撤销并轮换密钥，再清理历史。

## 文档

- [口语化功能流程](docs/对外聊天简要说明.md)
- [完整功能与操作流程](docs/功能与操作流程.md)
- [公共核心与私人实例接口](docs/architecture-and-instance-seam.md)
- [合同覆盖与测试口径](docs/functional-parity.md)
- [安装说明](docs/install.md)
- [更新与用户覆盖层](docs/update-and-user-overrides.md)
- [可升级模块地图](docs/可升级模块地图.md)
- [权利与分享](docs/rights-and-sharing.md)
- [中英双语开源发布长文](docs/launch-post.md)

## 许可证

- 代码、脚本、schema 和运行配置：MIT，见 [`LICENSE`](LICENSE)。
- 原创规则、模板和文档：CC BY-SA 4.0，见 [`LICENSE-DOCS.md`](LICENSE-DOCS.md)。
- 第三方对象：按各自许可证处理；默认发行不捆绑书课正文、平台内容、模型权重或私人资料。
