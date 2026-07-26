# 个人知识系统 Lite / ContentOS Lite

ContentOS Lite 是一套可复制给其他人使用的文件型个人知识系统。它保留完整学习、知识沉淀、复习、复用、搜索和创作能力，同时把运行依赖与上下文负担压到较低水平。

## 默认包含

- 材料 intake、直接教学、拆解问答、迁移问答、学习收束；
- 柔性复习计划；
- 普通分享卡正文；
- 概念、模型、案例、来源和本体关系收录；
- 收录资产的后续按需复用；
- 柔性网页搜索；
- 柔性内容创作与定向审阅；
- 相对路径、最小 startup、checkpoint、权限与写入保护。

## 默认不包含

- 本地大模型、模型权重、Ollama；
- KnowledgeOS、向量索引、图数据库、Python 环境；
- 账号登录、浏览器会话、自动发布、自动任务；
- 任何原作者的私人知识、学习记录、项目、账号数据、附件或运行回执。

系统以 UTF-8 Markdown/JSON 为真相源。Codex desktop 负责推理，PowerShell 负责确定性的初始化、最小上下文编译和验证，Git 用于版本管理。Obsidian 和 Codex 原生网页搜索是可选项。

## 快速开始

在发行目录中运行：

```powershell
.\scripts\init-contentos-lite.ps1 -Destination '.\my-knowledge-system'
```

进入新目录后验证：

```powershell
.\tests\validate-core-contract.ps1
.\tests\validate-task-budgets.ps1
.\tests\validate-no-private-state.ps1
```

查看功能与日常操作：

- [功能与操作流程](docs/功能与操作流程.md)
- [可升级模块地图](docs/可升级模块地图.md)
- [安装说明](docs/install.md)
- [更新与用户覆盖层](docs/update-and-user-overrides.md)
- [内容权利与分享](docs/rights-and-sharing.md)

## 核心设计

Lite 的节省来自按 TaskKind 加载最小规则、只传证据胶囊、默认生成一份全文和按失败点修复，而不是删掉承重功能或压缩正文意义。

搜索和创作使用柔性规则：数字是默认起点与软预算，不是来源数、案例数、模型数或审阅轮数的死配额。风险、证据缺口、任务复杂度和用户明确要求可以触发扩展；扩展必须留下理由，超出容量时拆分范围，不静默截断。

## 许可证

- 脚本、schema 和其他代码：MIT，见 `LICENSE-CODE`。
- 原创规则、模板和文档：CC BY-NC-SA 4.0，见 `LICENSE-DOCS.md`。
- 第三方内容：不随 v0.1 默认发行，见 `THIRD-PARTY-NOTICES.md`。
