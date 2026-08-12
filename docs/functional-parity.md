# 功能同等性与测试口径

“功能相同”不是文件名、规则数量或测试数量相同，而是同一任务目的、准入条件、来源权限、状态转换和可观察停止结果能够在公开版本重现。

## 三种结论

- **full**：公共核心直接提供任务合同和文件型实现边界；
- **public_adapter**：公共核心提供完整合同，外部系统行为由可替换适配器实现；
- **intentionally_private_instance_surface**：个人数据、账号、运行状态等不是产品能力，不进入公开仓库。

当前能力地图有 28 个 canonical TaskKind：21 个 full，7 个 public_adapter。用户作答后的旧模型/案例查询由随包文件索引直接支持；KnowledgeOS 只是可选加速器。没有用“私人数据未开源”伪装成“功能缺失”，也没有把 vendor-specific 实现硬塞进核心。

## 测试证明什么

`validate-public-capability-coverage.ps1` 检查 28 个入口一一对应、分类闭合、adapter ID 和 full/lite profile 不漂移。

`validate-functional-parity.ps1` 对每个入口运行匿名场景：缺必要输入必须阻断；完整输入时 full profile 必须 ready；lite 只允许明确子集；rule hydration、stage、track、implementation 和 parity 必须来自同一 canonical manifest；adapter-backed 任务不会在缺 adapter/authorization 时假装 ready。

`validate-clean-install.ps1` 在全新临时目录分别安装 full 与 lite，复跑核心测试，并确认二次初始化不覆盖用户文件。

`validate-no-private-state.ps1` 检查私人路径、UUID、数据库、缓存和运行状态没有进入发行包；同时扫描当前工作树、Git 暂存索引与完整可达历史中的常见 API key、访问令牌、私钥、凭据 URL、敏感文件名和非占位凭据字段。扫描失败会阻止发布，报告只暴露规则名与路径，不回显疑似密钥正文。

这些测试证明公开合同和确定性边界同等，不证明某个未安装平台适配器、模型质量或真实账号效果。后者必须由各自适配器和真实授权环境验证。
