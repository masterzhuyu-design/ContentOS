# ContentOS 开源发布长文

这份长文是 ContentOS 的正式发布主稿。中文原稿由项目作者于 2026-08-12 重新找回并提供；发布版只做了轻微的可读性整理，以及一处事实精度修正：把“基本消除了这种下降”改为更贴近论文结论的“大幅缓解了这种下降”。英文版不是逐句直译，而是在不削弱主线、力度和作者声音的前提下，为英文读者自然重写。

它适合发布为 X 长文、长线程、GitHub Discussion 或项目发布文章，不适合作为单条 280 字符帖子。中英文正文中的项目链接均已指向公开仓库。

## 中文发布版

我已经花了一百多亿个 token 来构建一些东西。

在接下来的几年里，我计划再投入一万亿个 token。

我并不是为了让 AI 再多帮我们做一点工作而花这些 token。

我想要构建的是：随着机器变得越来越强大，人类也应该随之成长——在智慧与决策能力上。

大多数人使用 AI，是为了把工作做得更快、更好。

每当有新模型出现，它似乎就能再帮你解决几个问题。

但当你几年后再回头看，在那些越来越精致的输出之外，真正留在你身上的是什么？

你今天费力发现的那些提示词和工作流，明天可能就会被产品吸收，变成人人都能使用的默认能力。

当“会用 AI”变成一种普遍能力时，真正的差异将在于：你是否能更好地理解问题、形成自己的判断，并做出选择。

GPS 帮我们记住路线是进步。我们关心的是到达目的地，而不是记住每一条街。

但如果 AI 不仅记住路线，还决定去哪里、为什么去，以及哪条路值得走，那么我们外包出去的就不再只是路线记忆。

我们外包的是思考与决策本身。

这就是问题所在：AI 替你完成某件事，并不意味着你学会了如何去做。

在一项涉及近 1000 名高中生的随机实验中，标准的 GPT 助手让练习表现提升了 48%。

但一旦移除 AI，这些学生在独立考试中的成绩比对照组低了 17%。

而加入学习保护机制、通过提示引导学生独立作答的版本，则大幅缓解了这种下降。

这就是我用那些 token 去构建一个开源个人知识系统的原因。

它不只是存储信息或生成答案。

当你把材料交给 AI 时，你不应该只带走一个成品输出。你还应该带走理解本身——并能把它用在下一个真实问题上。

当你丢入一段材料时，系统会先按照你当前的理解水平进行解释。

然后它会逐渐撤掉脚手架，直到你能自己解释这个概念，并把它应用到一个不同的问题上。

它还会安排定期复习。

如果你之后忘记了某些内容，它不会从头重讲整堂课。它会回到最早断裂的那个环节去修复。如果你已经掌握了，它就会提高难度。

我希望 AI 不只是交出答案。它应该参与理解、练习、复习、反思与迭代。

一次学习结束后，系统可以把你的理解——以及你如何把它应用到新问题上的方式——变成一张可以发到 X 上的分享卡片。

人们看到的不是 AI 摘要。

他们看到的是你最近学到了什么、想明白了什么，以及可以在哪里使用它。

你的学习变成了一种社交货币。

我也希望它能成为孩子们真正有用的学习工具。

当然，这并不意味着拒绝合理地使用工具。

如果你也想用它来写作，这个系统是专门针对 AI 最常见的写作失败设计的。

AI 往往不是缺乏材料，而是拒绝舍弃任何东西。

你想把一件事讲清楚，它却不断添加安全免责声明和反驳观点。让它进一步探索这个话题，它就把所有可能的方向都堆成一个列表，最终写出平淡、通用的东西。

这就是稀释效应：每一段单独看可能都合理，但随着较弱信息的累积，核心论点的整体冲击力反而变差。

为了解决这个问题，我专门调整了系统的架构和写作规则，让作品始终忠实于它选定的主线。

通用的安全免责声明会被收窄。

必要的边界尽可能放在背景里，而不是打断正文。

模型、案例和技巧不再被机械地堆砌在一起。

系统会围绕中心论点去寻找它们，从知识库中提取，必要时也会从外部来源补充。

只有当它们真正能深化正在形成的判断时，它们才会进入作品。

我们在这里改进的，不是某一个特定的内容模板。

而是创作背后的通用能力。

无论你是写一条 X 帖子、做视觉内容、进行复杂研究，还是写一本书，系统都能根据媒介重新组织材料，同时保留主线、判断和证据——让质量更加稳定。

我把它开源，是因为我想把这些想法真正落地。

去 GitHub 试一试，用你真正想学的东西来用它。

把焦点重新放回我们自己身上：

我们能不能理解得更好？

我们能不能把它应用到一个新问题上？

如果失败了，就开一个 Issue，附上材料、你卡在哪里，以及发生了什么。

项目：https://github.com/masterzhuyu-design/ContentOS

我会研究反复出现的问题，把它们变成测试，修复它们，并持续更新这个项目。

如果你有更好的方法，欢迎一起来建设。

关注我。

我也会把自己学习中提炼出的模型、案例和技巧，变成可以直接安装到你自己系统里的知识包。

AI 会持续变强。

我们不需要回到没有 AI 的世界。

但人类也应该持续变强——在智慧、判断力和创造力上。

这就是我所说的：

Make humanity great again.

## English launch version

I’ve spent more than 10 billion tokens building something.

Over the next few years, I plan to spend another trillion.

I’m not spending those tokens just to make AI do a little more work for us.

I’m trying to build toward a different future: as machines become more capable, humans should grow with them—not only in productivity, but in wisdom and judgment.

Most people use AI to get work done faster and better.

Every new model seems to solve a few more problems for you.

But when you look back several years from now, beyond all the increasingly polished outputs, what will actually remain in you?

The prompts and workflows you struggled to discover today may be absorbed into products tomorrow and become default features available to everyone.

When “knowing how to use AI” becomes ordinary, the real difference will be whether you can understand problems more deeply, form your own judgment, and make better choices.

GPS remembering the route for us is progress. We care about reaching the destination, not memorizing every street.

But if AI not only remembers the route, but also decides where to go, why to go there, and which destination is worth choosing, then we are no longer outsourcing route memory.

We are outsourcing thought and judgment themselves.

That is the problem: AI completing something for you does not mean you learned how to do it.

In a randomized experiment involving nearly 1,000 high-school students, a standard GPT assistant improved practice performance by 48%.

But once access to AI was removed, those students scored 17% lower on an independent exam than the control group.

A tutor designed with learning safeguards—using hints to keep students doing the thinking—largely mitigated that decline.

That is why I’m using those tokens to build an open-source personal knowledge system.

It is not just a place to store information or generate answers.

When you give material to AI, you should not walk away with only a finished output. You should also walk away with the understanding itself—and the ability to use it on the next real problem.

When you add something new, the system first explains it at your current level of understanding.

Then it gradually removes the scaffolding until you can explain the idea yourself and apply it to a different problem.

It also schedules review.

If you later forget something, it does not restart the entire lesson. It returns to the earliest point where your understanding broke down and repairs it. If you already understand the material, it raises the difficulty.

I want AI to do more than deliver answers. It should take part in understanding, practice, review, reflection, and iteration.

After a learning session, the system can turn what you understood—and how you applied it to a new problem—into a share card for X.

What people see is not an AI summary.

They see what you learned, what you figured out, and where that understanding can be used.

Learning becomes a form of social currency.

I also want this to become a genuinely useful learning tool for children.

Of course, none of this means rejecting the sensible use of tools.

And if you want to use it for writing, the system is designed around one of AI writing’s most common failures.

AI often does not suffer from a lack of material. It suffers from an unwillingness to discard anything.

You ask it to make one idea clear, and it keeps adding safety disclaimers and counterarguments. You ask it to explore further, and it piles every possible direction into a list until the result becomes flat and generic.

I call this the dilution effect: every paragraph may look reasonable on its own, yet the accumulation of weaker information reduces the force of the central argument.

To fight that, I changed the system’s architecture and writing rules so a piece remains faithful to the main line it has chosen.

Generic safety disclaimers are narrowed.

Necessary boundaries stay in the background whenever possible instead of interrupting the work.

Models, cases, and techniques are no longer stacked together mechanically.

The system looks for them in service of the central argument—drawing from the knowledge base and, when necessary, from external sources.

They enter the work only when they genuinely deepen the judgment taking shape.

What we are improving here is not one content template.

It is the general capability behind creation.

Whether you are writing an X post, making visual content, conducting complex research, or writing a book, the system can reorganize the material for the medium while preserving the main line, the judgment, and the evidence—making quality more consistent.

I’m open-sourcing it because I want to turn these ideas into something real.

Try it on GitHub with something you genuinely want to learn.

Put the focus back on ourselves:

Can we understand it better?

Can we apply it to a new problem?

If it fails, open an Issue. Include the material, where you got stuck, and what happened.

Project: https://github.com/masterzhuyu-design/ContentOS

I’ll study the failures that repeat, turn them into tests, fix them, and keep improving the project.

If you have a better method, come help build it.

Follow me.

I’ll also turn the models, cases, and techniques I extract from my own learning into knowledge packs that you can install directly into your own system.

AI will keep getting stronger.

We do not need to return to a world without AI.

But humans should keep getting stronger too—in wisdom, judgment, and creativity.

This is what I mean by:

Make humanity great again.

## 事实来源说明（不属于帖子正文）

文中学习实验来自 Hamsa Bastani 等人的随机现场实验 *Generative AI Without Guardrails Can Harm Learning: Evidence from High School Mathematics*。论文摘要报告：研究涉及近 1000 名高中数学学生；GPT Base 将练习成绩提高 48%，但撤除 AI 后，其独立考试成绩比从未获得 AI 的对照组低 17%；带学习保护机制的 GPT Tutor 大幅缓解了负面影响。论文见 [PNAS（DOI）](https://doi.org/10.1073/pnas.2422633122) 与 [SSRN 摘要页](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4895486)。

“已投入一百多亿 token”与“计划再投入一万亿 token”是作者对自身项目投入和计划的第一人称陈述，不在本仓库中另作独立审计或认证。
