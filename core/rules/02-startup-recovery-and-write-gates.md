# 02｜启动、恢复与写入门

## 统一启动

1. 取得 TaskKind。
2. 读取当前 checkpoint 指针。
3. 运行 `scripts/resolve-contentos-startup.ps1`，提交 `contentos-task-execution-input-v1`：本轮身份、阶段和每项承重输入都必须有当前 turn 指针或已核验摘要的工作区文件指针。
4. 只在 `status=ready` 和 `generation_allowed=true` 时执行。

规则加载完成不等于输入闭合。缺材料、目标、既有工作处置、用户锁定项或证据时，必须返回缺口。旧 `InputsJson` 只保留为迁移诊断入口，不再取得执行权限；任意字符串不能冒充 checkpoint、用户作答或工作区资产。

`current_turn_inline` 的 source pointer 必须精确属于本轮；`workspace_artifact` 必须位于当前 ContentOS 根目录内、不能经过 symlink/junction 等 reparse 跳转，并在每次启动时复核文件摘要。输入值和总载荷受固定安全上限保护，超限应改用有摘要的工作区资产或拆分范围，不能把超大正文回显进启动 envelope。

适配器绑定只证明结构和调用方声明。公共解析器没有宿主信任根，因此结构有效的适配器任务停在 `ready_adapter_pending_host_authority`；只有真实宿主独立核验权限与副作用后，才能在自己的执行面继续。

## 恢复

checkpoint 保留：

- 当前 TaskKind 与阶段；
- 最近核验事实；
- 证据指针；
- 用户锁定项和权限；
- pending；
- 下一轮最小读取顺序。

禁止把完整会话、完整网页、整本材料或所有旧候选写进 checkpoint。旧稿必须明确 `reuse / targeted_repair / replace / reference_only`，不能只凭聊天印象另起炉灶。

## 路径与写入

- 所有配置路径都相对工作区根解析。
- 解析后的路径必须保持在工作区内。
- source 与 runtime 分离；正式对象写 `vault/`，回执写 `.contentos/runtime/`。
- 默认新建而非覆盖；同名对象先比较身份和摘要。
- 一次任务只允许一个写入者；写前明确目标路径，写后回读。

## 柔性预算

每个 profile 有：

- `soft_target_utf8_bytes`：正常目标；
- `advisory_ceiling_utf8_bytes`：允许有理由地扩展；
- `hard_safety_ceiling_utf8_bytes`：超过后必须拆分范围。

处于 soft target 与 advisory ceiling 之间不算失败，但执行回执要记录扩展原因。超过 advisory ceiling 时优先缩减未选候选、重复规则和原始载荷；不得缩减承重语义。

## 外部工具

相互独立、只读、无需审批且输出可聚合时，可以用原生批量或受限并行。写入、有依赖的决策、账号副作用、审批和未知效果保持串行。失败先核对副作用，不整批盲重试。
