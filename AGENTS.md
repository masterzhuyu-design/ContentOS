# ContentOS Lite 统一入口

1. 先读取 `.contentos/config.json`；若尚未初始化，读取 `config/contentos.example.json`。
2. 取得稳定 `TaskKind` 后运行：

```powershell
.\scripts\resolve-startup-lite.ps1 -TaskKind <kind>
```

3. 只有返回 `status=ready` 且 `generation_allowed=true` 才执行任务。缺输入、预算溢出、路径越界或权限不足时停在返回状态，不自由补写。
4. 任务结束只写用户授权的目标和 checkpoint；不得自动发布、删除、移动、登录账号、创建线程或启动自动任务。

## 核心不变量

- Markdown/JSON 是真相源；缓存、索引和运行回执不是。
- LearningTrack、KnowledgeAssetTrack、CreationTrack 分离。完成学习、收录资产或生成分享卡都不自动开启 CreationTrack。
- 学习顺序保持：材料拆解 → 直接教学 → 拆解问答 → 迁移问答 → 学习收束 → 复习计划；普通分享卡是可选的 detached export。
- 模型、案例、概念和本体关系先形成可回读对象，再进入复用索引；复用只先读摘要，选中后才读正文。
- 搜索与创作采用 `adaptive_mode`：默认值是柔性起点，不是固定配额。扩展由风险、证据缺口、复杂度或用户要求触发。
- `semantic_truncation_forbidden`：Token/byte 预算只能减少脚手架、重复候选和原始载荷，不能删除承重观点、完整案例、问答依赖或用户锁定内容。
- 分享卡默认只交正文；图文、视频、平台版本与发布均需独立明确请求。
- 本地大模型、Ollama、KnowledgeOS、向量索引和 GraphRAG 不属于 v0.1 默认运行依赖。

## TaskKind

稳定入口见 `core/profiles/task-profiles.json`。不要用聊天中临时名称替代 TaskKind，也不要为了方便同时加载全部规则。
