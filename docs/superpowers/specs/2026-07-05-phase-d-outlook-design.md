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

## D-5 既有 defer 项(D 期或更早顺手清)

PII 日志统一清理(AgentTasksScreen/AgentTaskPanelScreen 只打 case 名)、孤儿字符串 key、
index 服务改独立 provider(C-1 落地 messagesRoomSummaryProvider 后有现成先例)、
rebuildIndex cancel-previous、AgentTaskIndexService 与 AgentProjectIndexService 合并、
上游 SDK PR(四 + C-2 一共五个 fork commit)。

## 不做(诚实的边界)

实时协同编辑(artifact_url 跳出,northstar §7);多用户权限模型(单用户 + agent 假设
不变,直到真实多用户需求出现);场景特化数据模型(只做展示层预设)。
