//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

/// Which vocabulary set the 御案体 agent UI speaks in. Global, app-wide — not per-room
/// (a per-case `scenario` override was floated in the northstar design but explicitly
/// scoped out for the first pass, see `2026-07-05-phase-d-outlook-design.md` D-2).
nonisolated enum TerminologyScenario: String, CaseIterable, Codable {
    /// 御案体 imperial-court vocabulary (政事堂/道/案/差事/请旨/案卷/实录…), the default.
    case imperial
    /// Plain, ordinary vocabulary (项目/任务/待办事项…) for anyone who doesn't want the
    /// imperial framing.
    case plain
}

/// Maps the handful of user-facing agent-feature nouns that vary between `imperial` and
/// `plain` phrasing. Everything else (generic UI chrome like "Cancel"/"Settings") stays on
/// the normal L10n/UntranslatedL10n path untouched — this only covers the 御案体-specific
/// vocabulary catalogued in the 07-06 design discussion.
nonisolated struct AppTerminology {
    let scenario: TerminologyScenario
    
    private func pick(_ imperial: String, _ plain: String) -> String {
        switch scenario {
        case .imperial: imperial
        case .plain: plain
        }
    }
    
    var homeTitle: String {
        pick("政事堂", "工作台")
    }
    
    var tabProjects: String {
        pick("政事", "项目")
    }
    
    var tabTasks: String {
        pick("差事", "任务")
    }
    
    var tabMessages: String {
        pick("书信", "消息")
    }
    
    var tabSearch: String {
        pick("检索", "搜索")
    }
    
    var manageSpaces: String {
        pick("管理诸道", "管理分组")
    }
    
    var taskPanelTitle: String {
        pick("案卷", "任务清单")
    }
    
    var sectionPending: String {
        pick("待批", "待处理")
    }
    
    var sectionActive: String {
        pick("在办", "进行中")
    }
    
    var sectionDone: String {
        pick("已结", "已完成")
    }
    
    var taskPanelEmpty: String {
        pick("本案暂无差事", "本项目暂无任务")
    }
    
    var viewThread: String {
        pick("查看实录", "查看记录")
    }
    
    var agentTasksEmpty: String {
        pick("暂无差事", "暂无任务")
    }
    
    var messagesEmpty: String {
        pick("暂无书信", "暂无消息")
    }
    
    var pendingChoicesSheetTitle: String {
        pick("请旨待批", "待办事项")
    }
    
    /// D-2's "案卡片重点字段" split: 御案体 keeps the "差事 x/y" caption text; 通俗版 shows a
    /// percentage progress bar instead. Both read the exact same done/total counts — this is a
    /// rendering choice, not a wording one, which is why it's a `Bool` rather than another
    /// `pick(_:_:)` string pair.
    var prefersProgressBar: Bool {
        scenario == .plain
    }
    
    func roomTaskProgress(done: String, total: String) -> String {
        pick("差事 \(done)/\(total)", "任务 \(done)/\(total)")
    }
    
    func pendingChoicesStrip(count: String) -> String {
        pick("\(count) 件请旨待批", "\(count) 件待办事项")
    }
    
    func roomTaskChipMulti(count: String) -> String {
        pick("\(count) 件差事在办", "\(count) 件任务进行中")
    }
    
    func roomTaskChipPendingOnly(count: String) -> String {
        pick("\(count) 件请旨待批", "\(count) 件待办事项")
    }
    
    func roomTaskChipPendingSuffix(count: String) -> String {
        pick(" · \(count) 件请旨待批", " · \(count) 件待办事项")
    }
    
    /// The 差事 tab's kanban column for tasks whose room isn't under any joined 道 — same
    /// wording in both scenarios since it's a fallback bucket, not a piece of vocabulary.
    var kanbanUnassignedColumn: String {
        "其他"
    }
    
    var kanbanViewA11yLabel: String {
        pick("按道分列查看", "按分组查看")
    }
    
    var listViewA11yLabel: String {
        pick("查看清单", "查看列表")
    }
}
