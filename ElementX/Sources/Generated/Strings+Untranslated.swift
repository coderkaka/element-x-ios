// swiftlint:disable all
// Generated using SwiftGen — https://github.com/SwiftGen/SwiftGen

import Foundation

// swiftlint:disable superfluous_disable_command file_length implicit_return

// MARK: - Strings

// swiftlint:disable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:disable nesting type_body_length type_name vertical_whitespace_opening_braces
internal nonisolated enum UntranslatedL10n {
  /// Collapse tool calls
  internal static var a11yCollapseToolCalls: String { return UntranslatedL10n.tr("Untranslated", "a11y_collapse_tool_calls") }
  /// Expand tool calls
  internal static var a11yExpandToolCalls: String { return UntranslatedL10n.tr("Untranslated", "a11y_expand_tool_calls") }
  /// Show filters
  internal static var a11yRoomListFiltersButton: String { return UntranslatedL10n.tr("Untranslated", "a11y_room_list_filters_button") }
  /// 管理诸道
  internal static var actionManageSpaces: String { return UntranslatedL10n.tr("Untranslated", "action_manage_spaces") }
  /// 暂无差事
  internal static var screenAgentTasksEmpty: String { return UntranslatedL10n.tr("Untranslated", "screen_agent_tasks_empty") }
  /// 在办
  internal static var screenAgentTasksSectionActive: String { return UntranslatedL10n.tr("Untranslated", "screen_agent_tasks_section_active") }
  /// 已结
  internal static var screenAgentTasksSectionDone: String { return UntranslatedL10n.tr("Untranslated", "screen_agent_tasks_section_done") }
  /// 查看实录
  internal static var screenCanvasStepsViewThread: String { return UntranslatedL10n.tr("Untranslated", "screen_canvas_steps_view_thread") }
  /// 请旨待批
  internal static var screenHomePendingChoicesSheetTitle: String { return UntranslatedL10n.tr("Untranslated", "screen_home_pending_choices_sheet_title") }
  /// %1$@ 件请旨待批
  internal static func screenHomePendingChoicesStrip(_ p1: Any) -> String {
    return UntranslatedL10n.tr("Untranslated", "screen_home_pending_choices_strip", String(describing: p1))
  }
  /// 差事 %1$@/%2$@
  internal static func screenHomeRoomTaskProgress(_ p1: Any, _ p2: Any) -> String {
    return UntranslatedL10n.tr("Untranslated", "screen_home_room_task_progress", String(describing: p1), String(describing: p2))
  }
  /// 书信
  internal static var screenHomeTabMessages: String { return UntranslatedL10n.tr("Untranslated", "screen_home_tab_messages") }
  /// 政事
  internal static var screenHomeTabProjects: String { return UntranslatedL10n.tr("Untranslated", "screen_home_tab_projects") }
  /// 检索
  internal static var screenHomeTabSearch: String { return UntranslatedL10n.tr("Untranslated", "screen_home_tab_search") }
  /// 差事
  internal static var screenHomeTabTasks: String { return UntranslatedL10n.tr("Untranslated", "screen_home_tab_tasks") }
  /// 暂无书信
  internal static var screenMessagesEmpty: String { return UntranslatedL10n.tr("Untranslated", "screen_messages_empty") }
  /// %1$@ 件差事在办
  internal static func screenRoomTaskChipMulti(_ p1: Any) -> String {
    return UntranslatedL10n.tr("Untranslated", "screen_room_task_chip_multi", String(describing: p1))
  }
  /// %1$@ 件请旨待批
  internal static func screenRoomTaskChipPendingOnly(_ p1: Any) -> String {
    return UntranslatedL10n.tr("Untranslated", "screen_room_task_chip_pending_only", String(describing: p1))
  }
  ///  · %1$@ 件请旨待批
  internal static func screenRoomTaskChipPendingSuffix(_ p1: Any) -> String {
    return UntranslatedL10n.tr("Untranslated", "screen_room_task_chip_pending_suffix", String(describing: p1))
  }
  /// Confirm
  internal static var screenRoomTimelineAgentChoiceConfirmButton: String { return UntranslatedL10n.tr("Untranslated", "screen_room_timeline_agent_choice_confirm_button") }
  /// Selected
  internal static var screenRoomTimelineAgentChoiceSelectedPrefix: String { return UntranslatedL10n.tr("Untranslated", "screen_room_timeline_agent_choice_selected_prefix") }
  /// Plural format key: "%#@COUNT@"
  internal static func screenRoomTimelineAgentTurnToolCallsCount(_ p1: Int) -> String {
    return UntranslatedL10n.tr("Untranslated", "screen_room_timeline_agent_turn_tool_calls_count", p1)
  }
  /// View progress
  internal static var screenRoomTimelineCanvasTaskBannerAction: String { return UntranslatedL10n.tr("Untranslated", "screen_room_timeline_canvas_task_banner_action") }
  /// Task in progress
  internal static var screenRoomTimelineCanvasTaskBannerTitle: String { return UntranslatedL10n.tr("Untranslated", "screen_room_timeline_canvas_task_banner_title") }
  /// Filters
  internal static var screenRoomlistFiltersTitle: String { return UntranslatedL10n.tr("Untranslated", "screen_roomlist_filters_title") }
  /// Search for rooms
  internal static var screenSearchEmptyStateMessage: String { return UntranslatedL10n.tr("Untranslated", "screen_search_empty_state_message") }
  /// Start searching...
  internal static var screenSearchEmptyStateTitle: String { return UntranslatedL10n.tr("Untranslated", "screen_search_empty_state_title") }
  /// There are no results for “%1$@.” Try a new search term.
  internal static func screenSearchNoResultsMessage(_ p1: Any) -> String {
    return UntranslatedL10n.tr("Untranslated", "screen_search_no_results_message", String(describing: p1))
  }
  /// 本案暂无差事
  internal static var screenTaskPanelEmpty: String { return UntranslatedL10n.tr("Untranslated", "screen_task_panel_empty") }
  /// 在办
  internal static var screenTaskPanelSectionActive: String { return UntranslatedL10n.tr("Untranslated", "screen_task_panel_section_active") }
  /// 已结
  internal static var screenTaskPanelSectionDone: String { return UntranslatedL10n.tr("Untranslated", "screen_task_panel_section_done") }
  /// 待批
  internal static var screenTaskPanelSectionPending: String { return UntranslatedL10n.tr("Untranslated", "screen_task_panel_section_pending") }
  /// 案卷
  internal static var screenTaskPanelTitle: String { return UntranslatedL10n.tr("Untranslated", "screen_task_panel_title") }
  /// Clear all data currently stored on this device?
  /// Sign in again to access your account data and messages.
  internal static var softLogoutClearDataDialogContent: String { return UntranslatedL10n.tr("Untranslated", "soft_logout_clear_data_dialog_content") }
  /// Clear data
  internal static var softLogoutClearDataDialogTitle: String { return UntranslatedL10n.tr("Untranslated", "soft_logout_clear_data_dialog_title") }
  /// Warning: Your personal data (including encryption keys) is still stored on this device.
  /// 
  /// Clear it if you’re finished using this device, or want to sign in to another account.
  internal static var softLogoutClearDataNotice: String { return UntranslatedL10n.tr("Untranslated", "soft_logout_clear_data_notice") }
  /// Clear all data
  internal static var softLogoutClearDataSubmit: String { return UntranslatedL10n.tr("Untranslated", "soft_logout_clear_data_submit") }
  /// Clear personal data
  internal static var softLogoutClearDataTitle: String { return UntranslatedL10n.tr("Untranslated", "soft_logout_clear_data_title") }
  /// Sign in to recover encryption keys stored exclusively on this device. You need them to read all of your secure messages on any device.
  internal static var softLogoutSigninE2eWarningNotice: String { return UntranslatedL10n.tr("Untranslated", "soft_logout_signin_e2e_warning_notice") }
  /// Your homeserver (%1$s) admin has signed you out of your account %2$s (%3$s).
  internal static func softLogoutSigninNotice(_ p1: UnsafePointer<CChar>, _ p2: UnsafePointer<CChar>, _ p3: UnsafePointer<CChar>) -> String {
    return UntranslatedL10n.tr("Untranslated", "soft_logout_signin_notice", p1, p2, p3)
  }
  /// Sign in
  internal static var softLogoutSigninTitle: String { return UntranslatedL10n.tr("Untranslated", "soft_logout_signin_title") }
  /// Untranslated
  internal static var untranslated: String { return UntranslatedL10n.tr("Untranslated", "untranslated") }
  /// Plural format key: "%#@VARIABLE@"
  internal static func untranslatedPlural(_ p1: Int) -> String {
    return UntranslatedL10n.tr("Untranslated", "untranslated_plural", p1)
  }
}
// swiftlint:enable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:enable nesting type_body_length type_name vertical_whitespace_opening_braces

// MARK: - Implementation Details

nonisolated extension UntranslatedL10n {
  static func tr(_ table: String, _ key: String, _ args: CVarArg...) -> String {
    // No need to check languages, we always default to en for untranslated strings
    guard let bundle = Bundle.lprojBundle(for: "en") else { return key }
    let format = NSLocalizedString(key, tableName: table, bundle: bundle, comment: "")
    return String(format: format, locale: Locale(identifier: "en"), arguments: args)
  }
}

// swiftlint:enable all
