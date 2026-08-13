# 安装说明

## 需要什么

- Windows PowerShell 5.1 或 PowerShell 7；
- Git（从 GitHub 获取和更新时使用）；
- 一个能读取 `AGENTS.md`、执行 PowerShell 并按任务合同工作的智能代理。Codex 是推荐运行面，但不是文件格式的唯一消费者；
- Obsidian 可选。知识正文仍是普通 Markdown/JSON，不安装 Obsidian也能使用。

不需要预装本地模型、Ollama、向量数据库、KnowledgeOS、账号登录或自动发布工具。

## 从 GitHub 获取

```powershell
git clone https://github.com/masterzhuyu-design/ContentOS.git
Set-Location .\ContentOS
```

也可以下载 Release ZIP 并解压。不要把发行源直接覆盖到已有私人知识库。

## 初始化一个新实例

完整功能档：

```powershell
.\scripts\init-contentos.ps1 `
  -Destination '..\ContentOS-Workspace' `
  -Profile full `
  -Pretty
```

低上下文档：

```powershell
.\scripts\init-contentos.ps1 `
  -Destination '..\ContentOS-Workspace-Lite' `
  -Profile lite `
  -Pretty
```

`lite` 只是同一套合同的常用任务预设，不是另一套产品。以后可在 `.contentos/config.json` 中把 `active_profile` 改为 `full`。

发行源和实例必须是两个目录。初始化只创建新实例；检测到已有 `.contentos/config.json` 时会返回 `existing_instance_unchanged`，不会把初始化器伪装成更新器。它不联网、不安装模型、不登录账号、不创建任务，也不发布任何内容。

新实例的 `.gitignore` 默认忽略整个 `vault/` 和本地 `.contentos/config.json`，避免私人笔记或本机配置被误提交。若目标目录已自带 `.gitignore` 却没有这两条保护，初始化会在写入前停止并要求先补齐，而不是静默继续。

## 验证

进入新实例后运行：

```powershell
.\tests\run-all.ps1
```

完整验证包括合同、28 项合同覆盖、启动负例、历史问题回归、预算、隐私和真实干净安装。安装后的实例会把仅适用于发行源的两项检查报告为 skipped，而不是假装执行过。

## 交给 Codex 安装时怎么说

可以直接发送：

> 请把这份 ContentOS 安装到一个新目录，使用 full profile，不要覆盖我现有的知识库。安装后运行全部自带测试，并把安装路径、测试结果和第一步用法告诉我。

安装完成不等于允许它导入你的私人资料。需要迁移旧资产时，应另做只读盘点、映射和可回滚导入。
