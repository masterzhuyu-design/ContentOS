# 公共核心与私人实例

ContentOS 只有一条主接口：公共上游定义“系统会做什么”，实例定义“它在谁的数据和工具上做”。

## 公共上游负责

- 28 个 canonical TaskKind；
- Learning / KnowledgeAsset / Creation 等对象与状态边界；
- 输入闭合、最小 hydration、预算、质量门和停止状态；
- 适配器接口及其权限、幂等和回读要求；
- 匿名合同 fixture、干净安装、隐私和准入回归测试。

## 私人实例负责

- 个人笔记、材料、学习历史、项目和草稿；
- thread Registry、checkpoint、运行回执和数据库；
- 账号快照、cookie、token、平台登录和自动化绑定；
- KnowledgeOS、视觉渲染器、实验 runner 等具体安装与配置。

## 为什么不是导出器或镜像

长期维护一个“私有系统 → 公开副本”的导出器，会制造第三真相源：私有规则、导出逻辑和公开规则都可能漂移。这里改为公共上游 + 私人实例适配器。通用修复进入公共 owner；私人数据只留在实例。

`lite` 也不是第二真相源。它只是 canonical manifest 里的 task allowlist；旧 Lite 脚本只是薄转发器。

## 适配器如何接入

适配器实现外部读写，但不能改变 TaskKind 的目标、输入关系或停止条件。它至少提供 adapter ID/version、支持任务、读写范围、授权、幂等/重试、输出 schema、失败副作用和 readback。

其中 `authorization` 是权限范围或授权决定的描述，不是 API key、Cookie、访问令牌或密码字段。凭据必须由适配器在仓库之外按需取得，不得进入任务合同、checkpoint、回执、日志或公开 fixture。

没有适配器时，功能仍在能力图里，startup 明确返回缺口；即使调用方提交了结构完整的适配器声明，公共解析器也保持等待宿主权威，不能把自报授权当成已执行。
