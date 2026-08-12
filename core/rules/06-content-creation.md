# 06｜柔性内容创作

## Interface

`ContentKernel + selected_evidence + target_medium + user_locks → DraftPackage`

DraftPackage 包含一份主成稿、所用证据/案例/模型指针、未解决风险和紧凑审阅回执。

## 主线

创作必须有当前最佳判断和清晰主线。世界复杂不要求作品平均铺开所有方向；只有能增加目标读者理解、感受或行动效果的分支才进入前台。

内部证据纪律不直接变成对外文风。成品不能默认写成审计报告、企业公文、平衡综述或免责说明书。必要不确定性自然融入表达，不抹掉力度、人物声音、叙事张力和媒介节奏。

历史、虚构或特殊世界观从作品内部的时代、地区、物种、寿命、成熟方式、权力关系、人物状态和因果逻辑推演，不擅自补入现代人类法律、年龄标准、报应或程序。

## adaptive_mode

- direct：用户已给主题、判断和材料，直接建立 ContentKernel；
- guided：主题确定，但主判断、案例岗位或结构仍需讨论；
- research-backed：承重事实或时效信息需先经过证据研究；
- revision：已有稿件，冻结合格部分并修最早失败层。

模式只在发现真实缺口后升级，不因后台规则多而默认走最长链。

## 装配

1. TopicBrief：读者、问题、载体和范围；
2. ContentKernel：主判断、必要关系、结论边界和用户锁定项；
3. Evidence/Case Map：来源、模型和案例各自承担什么岗位；
4. Reasoning Spine：各段如何把读者从问题带到结论；
5. Draft：默认只生成一份完整正文；
6. DeltaReview：只报告会造成读者损失的缺口。

模型和案例通过 AssetReusePlanner 柔性调用。没有固定数量；每个调用都要通过删除测试。

## 讨论差量

讨论前冻结 `canonical_source_digest`、`load_bearing_units`、ContentKernel 与用户锁定项。讨论项标记为 `confirmed_adjustment / candidate_option / rejected_option / clarification_only`。新稿只能应用 confirmed adjustment；未授权删除时，原承重单元不得消失。

## 修订成本

默认不并行生成多份全文。互斥策略先给差量 OptionCard；选择后再写全文。只有 ContentKernel 或 Reasoning Spine 失败才整篇重写，局部失败只修局部。

降低 AI 感不能变成随机口语、碎片标签或删除完整案例。可删重复、无岗位模型、不改变判断的背景和后台治理术语；不能删成立条件、案例过程、推理、反例、证据身份和用户锁定内容。

容量不足时拆分交付，不做语义截断。
