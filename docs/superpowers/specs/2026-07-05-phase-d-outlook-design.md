# Phase D: 终局功能展望(看板/场景/归档/需要你)Design Draft

Date: 2026-07-05
Anchor: `2026-07-05-product-northstar-design.md` §6(差事 tab 终局)、§7(产出物架构)、§10(D 行)。
Status: **设计级草案,非实施 spec。** D 的多数决策依赖 C 上线后的真实使用反馈
(数据量、hermes 适配后的事件形态、用户在四 tab IA 下的实际动线),实施 spec 与 plan
在 C 验收后另写。本文锁定方向与数据基础,避免 C 期间做出堵死 D 的选择。

## D-1 差事看板(差事 tab 终局)

- 列表 → 看板:按案分列 ↔ 按状态分列(待办/在办/已结)可切换。
- 条目点击 → 直达对应房间的差事详情(`CanvasStepsScreen`),而非只进房间
  ——数据已具备(index 携带 roomID + taskID;详情页已支持 taskID 驱动的实时刷新),
  缺的是 RoomFlowCoordinator 的"跨 tab 深链到详情"路由。
- 依赖 C:无硬依赖;依赖 hermes 按 B' 协议写 state(否则看板数据不完整)。
- C 期间不堵死:差事 tab 保持独立 screen,不与政事耦合。已满足。

## D-2 场景预设(创业者/学生视图)

- 同一数据模型,展示层差异:名词集(御案体 ↔ 通俗版)、默认视图(看板 ↔ metric 趋势)、
  案卡片重点字段(最近动态 ↔ 分数进度条)。
- 载体:app 级设置项(AppSettings)+ goal event 可选 `scenario` 字段(hermes 可按房间指定)。
- 前置:`metric {current,target,unit}` 字段(northstar §7 schema 演进表)先进协议
  ——**建议在 hermes B' 适配包里一并保留字段位**,客户端 D 期再渲染。
- C 期间不堵死:所有文案已走 `UntranslatedL10n` 集中管理,换名词集只是换 key 映射。已满足。

## D-3 归档策略

- 触发:已结差事数量大(案卷折叠区变长)、结案的案挤占政事列表。
- 机制:goal `status: "archived"`(已解析,C-2 落地)→ 政事列表隐藏 + 检索可达;
  差事级别沿用 state event 的 `status: "done"` + 面板折叠,超阈值(如 30 天)客户端本地
  截断显示(state 历史仍在 Matrix,永不丢数据)。
- 决策留待有数据时:阈值、是否需要"归档"显式动作、结案的案是否自动 leave room。

## D-4 「需要你」聚合

- C-2 的请旨待批横条是其 V1(跨案 pending choices)。
- 终局扩展:pending choices + @提及 + 邀请 + 差事里标记 `needs_user` 的步骤,聚成一个
  收件箱式视图(Slack Activity 的改造,northstar §9)。
- 载体候选:政事 tab 顶部横条展开成页(现有 sheet 升级),或第五 tab(倾向不加 tab,
  保持四 tab 简洁——与用户的简洁诉求一致)。
- 前置协议:步骤级 `needs_user: true` 可选字段(照 §7 表加入保留字段)。

## D-6 标的(objective)—— 案内阶段目标,AgentOS 已开始服务端预写

- 协议(`~/homelab/docs/element-agent-protocol.md` §3.4,版本 2026-07-06c):新增
  `io.element.agent.objective`,state key = `objective_id`,**案内多实例**,粒度介于
  `goal`(单例/长期/案为什么存在)和 `canvas.steps`/`choice_request`(执行级)之间——
  回答"这个案当前在验证/达成什么阶段目标"。`success_metrics`/`exit_options` 是标的级
  质性判断字段,不等同于差事级 `metric{current,target,unit}`(前者回答阶段何时算完,
  后者回答量化进度)。
- 关联方向跟 `canvas.steps`/`choice_request` 一致:**子级(差事/请旨)带可选
  `objective_id` 指认父级**,标的本身不维护子级列表——同一套"客户端查询时 join、
  避免双写竞态"模式,零新设计成本。
- **SDK 侧已完成**(07-06 本地会话):`io.element.agent.objective` 加入
  `AGENT_EXTRA_REQUIRED_STATE`(`matrix-sdk-ui/src/room_list_service/mod.rs`),
  fork 已重编。数据现在能进本地 store 了,但 **Swift 侧解析/索引/渲染仍留 Phase D**——
  跟 `metric`/`needs_user`/`scenario` 同一套"协议先落地,客户端不消费"policy,不因为
  hermes 已经在写就提前实现。
- **呈现方向已定(07-06 讨论,写入设计但不实现)**:
  - 案卷面板(房间内):按 `objective_id` 分组差事/请旨,标的作为可折叠 section,
    `success_metrics` 展示为只读清单(不做可勾选组件,标的完成与否权威来源是
    `status` 字段);`exit_options` 也只读展示,真正的阶段决策仍走已有的
    `choice_request` 卡片,不为标的单独发明新交互组件。
  - 政事堂案卡片(跨房间列表)—— **07-06 修正:不挑单一标的做标题**。原方案是取
    `priority` 最高的 `active` 标的标题当副标题,但 `priority` 的方向连协议文档自己
    都没写清楚(见下),挑出来的"代表"本质是随机的,会给用户一个"这案子现在只干这一件
    事"的假单线叙事。改成按数量分两种情况诚实呈现:
    - 恰好 1 个 `active` 标的 → 直接显示它的标题(无歧义,该显示)
    - ≥2 个 `active` 标的 → 不挑标题,只显示中性提示,如「2 个标的并行推进」,具体是
      哪两个留给点进案卷面板看分组明细
    - 没有任何 `active` 标的(旧协议房间/尚未立标的)→ 卡片退回现状,只显示差事 x/y
  - **`priority` 方向待办,但不再阻塞上面这条**:协议文档没写清楚 `priority`(int)
    数字方向(越大越优先,还是越小越优先),需要跟 hermes/AgentOS 对齐写回协议文档,
    否则客户端和服务端各自猜方向,排序会"看起来随机错乱"但不报错——跟协议自己列的
    "已知坑"是同一种隐蔽 bug。**建议**:凡是能用 `updated_at`(时间戳,方向天然无歧义)
    替代的排序场景(如案卷面板内标的 section 顺序,取"最近有动静的排前面"),优先用
    `updated_at` 不用 `priority`,减少对这条未对齐字段的依赖面。
- 一旦 Phase D 要做标的消费,会是**第三个**"debounce 订阅 roomListPublisher → 逐房间
  fetch state → parse → publish sorted list"的索引服务,跟下面 D-5 的合并诉求是同一件事,
  优先级因此更高——不要在合并之前先加第三份重复实现。

## D-5 既有 defer 项(D 期或更早顺手清)

PII 日志统一清理(AgentTasksScreen/AgentTaskPanelScreen 只打 case 名,**已修**,07-06
本地会话)、孤儿字符串 key、index 服务改独立 provider(C-1 落地
messagesRoomSummaryProvider 后有现成先例)、rebuildIndex cancel-previous(**已修**,
07-06 本地会话)、AgentTaskIndexService 与 AgentProjectIndexService 合并(**优先级
提升**,见上 D-6——第三个同构索引服务即将出现)、上游 SDK PR(四 + C-2 一共五个 fork
commit,07-06 新增 objective required_state 一行 + x86_64 target 精简两个 commit,
现为七个)。

## 不做(诚实的边界)

实时协同编辑(artifact_url 跳出,northstar §7);多用户权限模型(单用户 + agent 假设
不变,直到真实多用户需求出现);场景特化数据模型(只做展示层预设)。
