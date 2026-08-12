# 更新与用户实例

ContentOS 把公共程序和私人实例分开：

1. `core/`、`scripts/`、`templates/` 和 `tests/` 是公共上游；
2. `.contentos/config.json` 是当前实例的配置，至少决定使用 `full` 还是 `lite`；
3. `vault/` 和 `.contentos/runtime/` 是用户内容与运行状态，不应被上游更新覆盖。

`config/contentos.example.json` 中的 `user_overrides` 是保留给实例适配器的用户扩展位置。v0.2.0-rc.1 的 canonical startup 不会擅自解释任意 override 字段，避免一个未定义的本地文件静默改写任务合同。

## 推荐更新流程

1. 备份或提交当前实例；
2. 在临时目录获取并初始化新版；
3. 运行新版的 `tests/run-all.ps1`；
4. 比较 release notes、task profile、Schema 和 module registry；
5. 用匿名 fixture 验证旧数据仍可读，再迁移公共上游文件；
6. 回读 `.contentos/config.json`、vault、checkpoint 和关键用户资产；
7. 有破坏性 Schema 变化时，必须同时提供迁移和恢复办法。

回退只回退公共上游，不删除或回退用户 vault。`lite` 和 `full` 共用同一 canonical manifest，因此切换 profile 不需要搬迁知识资产。

## 适配器升级

账号、平台、实验 runner、Registry、视觉渲染、KnowledgeOS 等能力通过实例适配器接入。升级适配器前应明确它支持的 TaskKind、读取和写入范围、授权、失败副作用、幂等策略与回读方式。适配器不能重新定义公共任务目标。
