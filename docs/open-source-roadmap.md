# 开源发布路线

## 本地 release candidate

1. 公共上游与私人实例拆分；
2. 28 个 TaskKind 和 full/lite profile 收敛到一个 manifest；
3. MIT + CC BY-SA 4.0 双许可证；
4. 匿名功能同等、干净安装、隐私和 manifest 回归；
5. GitHub CI 在 Windows PowerShell 上复跑验证；
6. 生成 README、口语使用说明、中英双语发布长文和活动申请草稿。

## 远端发布前仍需确认

- GitHub 用户名/组织与仓库名；
- 仓库 description、topics 和公开可见性；
- 首个 tag/release 文案；
- OpenAI 申请所用 ChatGPT 邮箱、OpenAI Organization ID 与是否勾选 API credits / Codex Security。

本地 RC 通过不自动创建远端、推送或提交表单。

## 发布文案

作者于 2026-08-12 重新找回并提供了原始长稿。它现在作为项目的正式发布主稿保存在 [`launch-post.md`](launch-post.md)，其中包括轻度校准后的中文发布版、自然英文改写和不进入正文的事实来源说明。此前的文件与 Git 历史搜索确实没有找到这份原文；它是由作者重新提供的，不冒充从仓库恢复所得。

仓库 URL 与最终平台排版在远端发布前补齐。长稿适合 X 长文或线程，不应为了迁就单条短帖而稀释成一份无关的架构功能清单。
