# 安装说明

## 依赖

必需：

- Codex desktop；
- Windows PowerShell 5.1 或 PowerShell 7；
- Git。

可选：

- Obsidian；
- Codex 原生网页搜索或内置浏览器。

不需要本地大模型、模型权重、Ollama、KnowledgeOS、Python、数据库服务器或账号登录。

## 初始化

```powershell
.\scripts\init-contentos-lite.ps1 -Destination '.\my-knowledge-system' -Pretty
```

目标目录必须位于发行源之外。初始化只新建缺失文件；已有同名文件会跳过，不覆盖用户内容。

## 验证

```powershell
Set-Location '.\my-knowledge-system'
.\tests\validate-core-contract.ps1
.\tests\validate-task-budgets.ps1
.\tests\validate-no-private-state.ps1
```

## Git

初始化通过后，可以自行运行：

```powershell
git init
git add .
git commit -m 'Initialize ContentOS Lite'
```

Git 操作不由安装脚本自动执行。
