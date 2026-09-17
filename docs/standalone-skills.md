# 两个可单独使用的 skills / Standalone skills

不必安装整个 ContentOS，也不需要私人知识库、API key 或 Gemini。这两个 skill 是从现有公开规则中提炼出的独立入口，不是两个另起炉灶的系统。

## 安装与使用

复制所需的 skill 文件夹（包含 `SKILL.md`）到你的 agent 支持的 skills 目录，再按该客户端的方式启用。若客户端不支持 skills，可把 `SKILL.md` 作为本次任务说明交给它；这属于手动使用，不代表自动触发已验证。

### 学习迁移教练

文件：[`learning-transfer-coach/SKILL.md`](../.agents/skills/learning-transfer-coach/SKILL.md)

你提供材料、希望学会什么，以及已有理解。教练先解释，再根据你的实际回答找出卡点，逐渐撤掉提示，用真正换了问题结构的练习检查迁移，而不是换几个名字再考一遍。

试用：

> 使用 learning-transfer-coach。我要学会区分平均风险与极端风险，用来判断我的项目投入。先了解我现在的理解，再教我；不要一上来替我答题。

学习结束可以留下简短学习记录和复习建议；只有客户端确实支持、且你授权时，才会写文件或设置提醒。它不会把答过一道题说成永久掌握。

### 成稿审阅与定向修复

文件：[`focused-draft-review/SKILL.md`](../.agents/skills/focused-draft-review/SKILL.md)

你提供原稿、读者和用途。它先找真正影响读者理解、感受或行动的问题，再按你的要求提出修法或修改正文，不把鲜明表达磨成中立套话。

试用：

> 使用 focused-draft-review。下面是我准备发给普通读者的文章。先判断哪里削弱主线，只提最值得改的地方，不要直接重写。

> 按刚才确认的改法修改，保留我的语气，只给完整成品。

## 怎么判断有没有用

| 场景 | 应有行为 |
| --- | --- |
| 学习者已经给出完整回答 | 先读完整回答，再定位卡点，不重启整套问答 |
| 迁移练习 | 改变需要判断的关系，不能只是改名字和数字 |
| 没有访问旧知识库 | 不编造旧案例，不声称已检索 |
| 只要求审阅 | 给具体问题与改法，不擅自重写 |
| 改一个事实错误 | 修正事实及必要依赖，保留原稿声音与主线 |
| 虚构作品 | 按作品内部因果审阅，不强加说教或报应 |

这些是行为验收场景，不是模型能力保证。最终效果仍需用真实材料和实际输出判断。独立 skill 不提供完整 ContentOS 的持久状态、调度、权限校验或自动发布功能。

## English quick start

Copy either skill folder into a skills directory supported by your agent. Enable it using that client's instructions. Alternatively, supply its `SKILL.md` as task instructions. No private vault, external service, or API credential is required by these skills.

- **learning-transfer-coach**: explain, inspect the learner's actual answer, repair the earliest misunderstanding, and test meaningful transfer without answering for the learner.
- **focused-draft-review**: review a specific draft against its reader and purpose; repair consequential weaknesses while preserving its voice and central argument.

These are portable instructions, not a bundled inference service or the full ContentOS runtime. Client integration and output quality must be checked in the intended environment.

## License

Skills and this guide: [CC BY-SA 4.0](../LICENSE-DOCS.md). Retain attribution to [ContentOS](https://github.com/masterzhuyu-design/ContentOS) when redistributing or adapting them. Repository code retains its separate MIT license.
