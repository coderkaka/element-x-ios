# Phase C: 御案信息架构落地(goal event + 政事/书信 + 命名 + 道)Design

Date: 2026-07-05
Anchor: `2026-07-05-product-northstar-design.md` §2(goal event)、§3(御案体命名)、§4(信息架构)、§8(协议演进)、§10(演进路径 C 行)。
Naming: UI copy uses 御案体;code identifiers stay functional English(Project/Goal/Messages)。

## Goal

Land the terminal information architecture: four tabs 政事/差事/书信/检索, the
`io.element.agent.goal` room state event as the project-room marker and metadata carrier,
project-aware room cards (差事进度 + 待批红点 + 排序), a cross-room 请旨待批 strip, and
the 道 switcher absorbing the Spaces tab.

Split into **two independently shippable plans**:

- **C-1(IA 与命名)**: tab renames, Spaces tab removal + 管理入口迁移, 书信 tab. No SDK
  or protocol dependency — pure client work.
- **C-2(goal 与政事增强)**: goal state event (SDK required_state + parser + index),
  project-aware 案卡片, sorting, 请旨待批 strip, protocol spec update for hermes.

C-1 can merge and be device-verified before C-2 starts.

## What exists (reuse, don't rebuild)

- `HomeTab` enum `{chats, tasks, spaces, search}` + `NavigationTabCoordinator` assembly in
  `UserSessionFlowCoordinator.swift:23,93-140`.
- **`SpaceTabBarView`**(fork 已建):政事 tab 顶部的横向道 chip 条(Main + 每道一 chip +
  过滤按钮),经 `spaceFilterPublisher` → `roomSummaryProvider.setFilter(.rooms(roomsIDs:))`
  完成按道过滤。**这就是道切换器**——northstar §4.2 描述的「当前道名 ▾」下拉面板被此替代
  (已建成、少一次点击;本 spec 记录此偏离并更新锚点认知)。
- `alternateRoomSummaryProvider`(`ClientProxy.swift:1491-1496`)— 同一 roomListService 上
  建第二个 provider 的先例;书信 tab 照此建第三个。
- `HomeScreenRoomCell` — 只依赖 `HomeScreenRoom` + `mediaProvider` + action 闭包,可在
  书信 screen 直接复用。
- `AgentTaskIndexService`(`Services/AgentTasks/`)— 跨房间 state event 索引模板:
  roomListPublisher 1s 防抖 → 每房间 `getRoomStateEventsRaw` → 解析 → publisher。
  goal 索引与 choice 索引都克隆此模式;`getRoomStateEventsRaw` 对 state_key="" 的
  单条事件同样适用,**无需新增 FFI**。
- `AgentTaskStateEvent`(`AgentTaskSummary.swift:28-66`)— 全事件解析模板
  (`init?(parsingFrom:)` 读 state_key + content),`AgentGoalStateEvent` 照此。
- SDK fork `AGENT_EXTRA_REQUIRED_STATE`(`room_list_service/mod.rs:115`,单一 const,
  两个消费点自动跟随)— 加一行 `("io.element.agent.goal", "*")` + 增量重编 xcframework。

## Wire format additions

### `io.element.agent.goal`(房间级 state event,state_key = "")

```json
{
  "name": "提分计划",
  "description": "高考数学 118 → 130",
  "status": "active"
}
```

- 存在(且 status ≠ "archived")即为**立案**:该房间是项目房间。
- `status`: `"active"`(在办,默认)| `"done"`(结案)| `"archived"`(D 阶段归档,C 仅解析)。
- 所有字段可选;缺 `name` 时用房间名。字段只增不改语义。

### `io.element.agent.choice_request` state event 的 pending 阶段(协议演进)

现状:state event 仅在用户朱批后由客户端/hermes 写入(`resolved_selection`)。跨房间
「请旨待批」聚合无法从"不存在的 state"推断 pending——**hermes 需在发问时即写**:

```json
{ "status": "pending", "question": "部署方式选哪个?" }
```

朱批后更新为 `{ "status": "resolved", "resolved_selection": ["canary"], "question": "…" }`。

- 客户端兼容规则:`resolved_selection` 非空 → 已批;否则 pending。房间内面板的
  消息驱动检测不变(未适配 hermes 的房间只是不出现在跨房间聚合里,优雅降级)。
- 此改动写入 `~/homelab/element-agent-protocol.md`(C-2 任务),与 goal event 一并交付
  hermes 适配(B' 工作包扩容)。

## Architecture — C-1(IA 与命名)

### 1. Tab 重命名与移除

终局 tab:`[政事] [差事] [书信] [检索]`。

- `HomeTab` 变为 `{chats, tasks, messages, search}`(`chats` 标识符保留,减少无谓 churn;
  `spaces` case 删除)。
- 政事:`screen_home_tab_chats` 是上游 Localazy key(不可改)→ 新增 untranslated key
  `screen_home_tab_projects` = `政事`,chats tab 改用它。
- 差事:`screen_home_tab_tasks` 值 `Tasks` → `差事`。
- 书信:新 key `screen_home_tab_messages` = `书信`。
- 检索:`screen_home_tab_search` 值 `Search` → `检索`。
- 差事 tab 内文案落御案体:`screen_agent_tasks_section_active/done` → `在办`/`已结`,
  `screen_agent_tasks_empty` → `暂无差事`,navigationTitle → `差事`。

### 2. Spaces tab 移除 + 管理入口迁移

- `HomeTab.spaces` 与其 `TabDetails`/split coordinator 装配移除;
  `SpacesTabFlowCoordinator` 等界面代码**全部保留**(northstar:仅迁移入口)。
- `SpaceTabBarView` 末端(过滤按钮旁)加「管理」chip(gear 图标)→ 呈现现有 space
  管理流(以 sheet/push 挂到政事 tab 的导航栈,复用 `SpacesTabFlowCoordinator` 或其
  等价入口——plan 落地时按现有 coordinator 接口取最小接法)。
- 指向 spaces tab 的 `AppRoute` 深链改为:切到政事 tab 并打开管理入口(不 crash 即可,
  深链场景极少)。

### 3. 书信 tab(DM 列表)

- ClientProxy 增 `messagesRoomSummaryProvider`(照 `alternateRoomSummaryProvider` 先例,
  `setRoomList(allRooms)` 后一次性 `setFilter(.all(filters: [.people]))`,永不再变——
  与政事 tab 的动态 filter 互不干扰)。
- 新 `MessagesScreen` MVVM-C 四件套(模板照 `AgentTasksScreen` 的轻量结构):
  订阅 messagesProvider 的 roomListPublisher → `[HomeScreenRoom]`(复用现有
  `HomeScreenRoom(summary:)` 映射)→ List 复用 `HomeScreenRoomCell`(action 闭包只处理
  `.selectRoom`,映射到自身 `.presentRoom(roomID)` action)。
- 空态:「暂无书信」(key `screen_messages_empty`)。
- 政事 tab 排除 DM:`HomeScreenViewModel.updateFilter()` 的 filter 组合中恒加 `.rooms`
  (group rooms only)。DM 邀请横幅 V1 仍留在政事 tab(过渡期已知项,northstar 开放问题 1)。
- 转发/分享等指向 DM 的既有流程不动(它们不经过 home 列表)。

**过渡规则(northstar 开放问题 1 的 C 阶段答案)**:政事 = 全部群房间(有 goal 的显示
增强卡片,没有的是「未立案」普通卡片);书信 = 全部 DM。goal 只增强、不做成员资格门槛
——分类风险与 IA 改动解耦。

## Architecture — C-2(goal 与政事增强)

### 4. SDK:required_state 加 goal

`AGENT_EXTRA_REQUIRED_STATE` 加 `("io.element.agent.goal", "*")`(mod.rs 一行,两个消费点
自动跟随)+ 增量重编 xcframework + SDK fork 提交。验证:repro 式 STATECHECK(向测试房间
写 goal state,冷启动后 store 命中)。

### 5. Goal 解析与项目索引

- `AgentGoalStateEvent`(镜像 `AgentTaskStateEvent`):`eventType = "io.element.agent.goal"`,
  字段 `name?/description?/status?`(status 缺省 `"active"`)。
- `ProjectIndexService`(克隆 `AgentTaskIndexService`):每房间
  `getRoomStateEventsRaw(roomID:eventType:goal)` → `[ProjectSummary]`
  (`roomID/name?/description?/status`),`projectsPublisher: CurrentValuePublisher`。
- `ChoiceIndexService` 并入同一服务(一次房间遍历读两种 event type,避免两个服务
  各扫一遍):输出 `pendingChoicesPublisher: CurrentValuePublisher<[PendingChoiceSummary], Never>`
  (`roomID/eventID(state_key)/question`),pending 判定 = `resolved_selection` 缺失或空。
  服务定名 `AgentProjectIndexService`,与 `AgentTaskIndexService` 并列(合并两服务留给
  后续 follow-up,现有差事 tab 不动)。
- `UserSessionFlowCoordinator` init 中与 task index 同点位构建并 `start()`。

### 6. 政事案卡片增强 + 排序

- `HomeScreenRoom` 增可选字段:`activeTaskCount/doneTaskCount`(来自 task index 按 roomID
  聚合)、`pendingChoiceCount`(来自 choice index)、`isProject`(来自 project index)。
- `HomeScreenViewModel` 注入两个 index publisher,与 roomListPublisher 合流后在
  `updateRooms()` 中 join(纯函数,零额外 IO)。
- `HomeScreenRoomCell` footer badge 行增两个元素(有则显示):
  待批红点(`pendingChoiceCount > 0`,红色 badge)、差事进度 caption(`x/y 件`,
  activeTask 汇总)。视觉细节以 preview 迭代,不超出 footer 现有行高。
- 排序(client-side 稳定重排,在 updateRooms 内):有待批 → 有在办差事 → 其余按
  provider 原序(recency)。仅政事 tab;书信不受影响。

### 7. 请旨待批横条(政事 tab 顶部)

- `PendingChoicesStripView`:政事 room list 顶部(SpaceTabBarView 之下),有跨房间
  pending 请旨才显示:「N 件请旨待批 ›」。
- 点击:N == 1 直接打开该房间;N > 1 弹 sheet 列表(question + 房间名,行点击 → 开房间)。
  V1 不做滚动定位到卡片(房间内 chip → 案卷已有待批定位能力)。
- 数据:`pendingChoicesPublisher`,随当前道过滤(交 `spaceFilterPublisher` 的 descendants
  取交集;无道选中则全量)。

### 8. 协议 spec 更新(hermes 工作包)

`~/homelab/element-agent-protocol.md` 增补:goal event 全节(schema、立案/结案语义、
何时写)+ choice_request 的 pending 阶段写入义务 + 索引依赖说明(客户端跨房间聚合
只认 state event)。

### 9. Strings(Untranslated.strings 新增,C-2 部分)

| key | value |
|---|---|
| `screen_home_pending_choices_strip` | `%1$@ 件请旨待批` |
| `screen_home_pending_choices_sheet_title` | `请旨待批` |
| `screen_home_room_task_progress` | `差事 %1$@/%2$@` |

(C-1 的 key 见 §1/§3。)

## Error handling

- goal/choice state 解析失败:跳过该房间该事件,`MXLog.error`(既有模式;日志只打
  roomID/事件类型,不打 name/question——PII 规则)。
- index 单房间读失败:跳过不清空(既有模式)。
- 书信 provider 建立失败:书信 tab 显示空态,不影响其他 tab。

## Testing

- Unit:`AgentGoalStateEvent` 解析(全字段/缺省/status 各值/坏 JSON);
  `AgentProjectIndexService`(goal+choice 双类型、pending 判定、单房失败跳过);
  `HomeScreenViewModel` join 与排序(待批置顶/在办次之/稳定性);
  `MessagesScreenViewModel`(列表映射、selectRoom action)。
- Previews + TestablePreview:案卡片(未立案/有差事/有待批)、请旨横条、书信空态/列表。
- Device(user):四 tab 齐 + 名称;道 chip 过滤 + 管理入口;书信只见 DM;写 goal state
  后卡片增强出现;pending choice state 写入后横条出现、朱批后消失。

## Out of scope

看板、场景预设、归档策略、「需要你」聚合页(D);thread 侧任务状态条(D);
政事按 goal 过滤成员资格(过渡规则见 §3);DM 邀请横幅迁移;index 服务合并重构;
hermes 侧实现(B' 工作包,本阶段只交付 spec)。
