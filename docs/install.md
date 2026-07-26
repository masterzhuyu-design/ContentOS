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

## 让 Codex 从 ZIP 安装

把发行 ZIP 上传给 Codex 后，同时发送：

> 请先检查这个 ContentOS Lite ZIP，把它安装到一个新文件夹，不要覆盖我的现有知识库；安装后运行自带验证，并告诉我安装路径、验证结果和下一步怎么开始使用。

Codex 需要知道目标路径，并可能请求该目录的写入权限。只上传 ZIP 不等于授权自动安装。对于已有知识库，应先安装到新目录，再按升级说明合并用户覆盖层。

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
