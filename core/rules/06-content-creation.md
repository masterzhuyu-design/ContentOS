# 06｜柔性内容创作

## Interface

`ContentKernel + selected_evidence + target_medium + user_locks + optional MediaExecutionPlan → DraftPackage`

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

## 共用阶段引导

`direct / guided / research-backed / revision` 四种模式都使用同一份瞬时 `StageGuide`；`guided` 不是唯一有引导的模式。每个实际经过的收件、内容内核、证据补强、装配、成稿、审阅、媒介规划、预演、扩展和交付阶段都编译：

- 当前阶段和目标；
- 会改变下一动作的已知材料；
- 系统推荐的下一步；
- 零至三个会实质改变判断、路线、成本、权利、扩展范围或成品效果的选择；
- 最多一个当前无法可靠代选的承重问题；
- 完成条件、下一阶段和 `auto_continue / wait_for_user / complete / paused`。

信息齐全且下一动作可逆或已获委托时直接 `auto_continue`，不再问一次“是否继续”；用户暂停立即 `paused`；交付完成使用 `complete`，不自动新建任务。只有真实待决才把引导呈现给用户；连续自动推进最多给一句有用进度，用户要求只给成品时把引导留在后台。StageGuide 不新增 TaskKind、状态 owner、回执、常驻阶段包或人工闸门，也不把摘要、验证器和治理术语写进成品。

## 载体执行（可选）

纯文字任务不创建 `MediaExecutionPlan`。只有交付需要镜头、时间线、动态画面或多段媒体时，才由既有 ContentCreation owner 编译这份可选计划，不另建第二套创作主线。

`MediaExecutionPlan` 至少包含：

- `mode`：`footage_edit / programmable_motion / longform_repurpose / generated_sequence / hybrid`；
- 来源素材、场景或片段单元、连续性与用户锁定项；
- 执行适配器与可编辑交付指针；
- `preview.kind`：`styleframe / shot_recipe / motion_canary / timeline_segment / candidate_reel / full_short`；
- `preview.validates / preview.cannot_prove / expansion_authority`；
- 来源、权利与生成过程的 provenance。

先根据素材、载体、可编辑交付和返工风险选表达路线，再选工具；不因安装了某个 skill 或供应商而反过来改写 ContentKernel。镜头目录、第三方 skill 和模型建议只是候选词汇，不能取得主线、采用或发布权。

预演不是固定十秒。应选择成本最低、却最能推翻高代价错误假设的可观察产物：视觉身份可先看 styleframe，镜头因果看 shot recipe，动态节奏看 motion canary，剪辑连续性看 timeline segment，长素材取舍看带时间码 candidate reel；整条短内容本来就便宜可逆时，可以直接看 full short。预演通过只证明 `validates` 中列出的关系，不自动授权整片扩展、批量生成或发布。

执行结果必须尽量保持可编辑，并能回溯来源、权利状态与采用决定。适配器可以完成局部实现选择，但不能改写主判断、用户锁定项或把“工具成功运行”冒充内容质量。

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
