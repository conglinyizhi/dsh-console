// 动作分发与各 action 的处理器：update / update_inner 那一大段 match、参数拼装、
// 请求发送，以及 delete / pin / job / start / settings 这些动作的回执落地。
//
// 2026-10-20 从 app.mbt 拆出来：那个文件 4639 行，页面骨架与动作处理混在一起，
// 翻一次要滚半屏；拆开之后改动作只看这一份。只搬位置，函数体一个字没改。

///|
/// 备注的参数：{ profile, text }。text 用 json_text_literal 转义（备注是自由文本，
/// 里面什么字符都可能有）；空串是合法的 —— 契约里空串表示删掉那个文件。
/// 不给 trim：用户写的换行与行首空格是他自己的事，要不要拒由后端按上限判。
fn note_pairs(row : Row, text : String) -> Array[(String, String)] {
  match row.profile_name {
    Some(name) =>
      [("profile", json_text_literal(name)), ("text", json_text_literal(text))]
    None => []
  }
}

///|
/// 把若干 (键, 已渲染好的 JSON 值) 拼成 params 对象。空数组给空串 —— 调用方据此
/// 判定「这一行没有可用的目标」，在本地说清而不是发一个空 params 出去。
fn params_of(pairs : Array[(String, String)]) -> String {
  if pairs.length() == 0 {
    return ""
  }
  let buf = StringBuilder()
  buf.write_char('{')
  let mut first = true
  for pair in pairs {
    let (key, value) = pair
    if !first {
      buf.write_char(',')
    }
    buf.write_string(json_text_literal(key))
    buf.write_char(':')
    buf.write_string(value)
    first = false
  }
  buf.write_char('}')
  buf.to_string()
}

///|
/// 目标 profile 的参数：{ profile } 或 { profile, home }。
///
/// home 是这一行**自己的** home（口径见 own_home_of）：带上它，后端才不用按自己的 home
/// 去猜这一只在哪 —— start-instance 的 home 参数后端早就有了，只是一直没有 UI 够得着。
/// 读不到自己的 home 就只发名字：**不拿控制台自己的 home 顶上** ✗，那等于指名去动别处那一份。
/// 读不到目录名同理给空数组：写动作一律以读数为准，不拿演示数据里那个名字去打真实的东西。
fn profile_pairs(row : Row) -> Array[(String, String)] {
  match row.profile_name {
    Some(name) => {
      let home = own_home_of(row)
      if home == "" {
        [("profile", json_text_literal(name))]
      } else {
        [("profile", json_text_literal(name)), ("home", json_text_literal(home))]
      }
    }
    None => []
  }
}

///|
/// 归档 / 取消归档的参数：{ profile, home }。
///
/// home 必须带上：一份档案的身份是 (home, 名字)。同名两份档案在两个 home 里时，
/// 只发名字后端分不出撤的是哪一条（那它只能按名字撤，会把另一份也撤掉）。
/// 归档孤行（磁盘上没有目录）的 home 来自归档记录本身，见 Row 的 archive_home。
/// 读不到 home（后端没给 / 这一行没有可比的值）就只发名字：**不猜一个 home 出来**，
/// 由后端按它自己的 home 认 —— 那是改动之前的兼容口径。
fn archive_pairs(row : Row) -> Array[(String, String)] {
  match row.profile_name {
    Some(name) => {
      let home = archive_home_of(row)
      if home == "" {
        [("profile", json_text_literal(name))]
      } else {
        [("profile", json_text_literal(name)), ("home", json_text_literal(home))]
      }
    }
    None => []
  }
}

///|
/// 目标端口的参数（停止 / 重启按端口认）。
fn port_pairs(row : Row) -> Array[(String, String)] {
  match row.port_value {
    Some(port) => [("port", port.to_string())]
    None => []
  }
}

///|
/// 按行取动作目标：kind = "port" 取端口，"archive" 取归档那一套（名字 + home），
/// 其余取 profile。
fn params_for_row(model : Model, row_id : String, kind : String) -> String {
  match find_row(model.rows, row_id) {
    None => ""
    Some(row) =>
      if kind == "port" {
        params_of(port_pairs(row))
      } else if kind == "archive" {
        params_of(archive_pairs(row))
      } else {
        params_of(profile_pairs(row))
      }
  }
}

///|
/// 一个写动作：发请求，并把这一行置成忙碌（同一行不会连点两次）。
/// 目标读不到就只在本地说一句，不发请求。
///
/// name 是这一行在界面上的名字（谁），verb 是这一步做了什么（「停止」）：
/// 回执按这两个词组句（见 action_receipt）。**不在这里拼「动作名 + 名字」那种标签** ——
/// 它以前被贴在提示条句首，读起来像机翻。
fn send_action(
  model : Model,
  id : String,
  action : String,
  name : String,
  verb : String,
  params : String,
  emit : @cmd.Emit[Msg],
  confirm? : String = "",
) -> (Model, @cmd.Cmd) {
  if params == "" {
    (
      notice_err(
        model,
        name + " " + verb + "没执行：这一行的读数里没有可用的目标（profile 目录名或端口读不到）",
      ),
      @cmd.none,
    )
  } else {
    let busy = map_rows(model, id, fn(row) { { ..row, busy: true } })
    (
      notice_clear(busy),
      action_cmd(
        id,
        action,
        name,
        verb,
        if confirm == "" {
          action_body(action, params)
        } else {
          // 二次确认串在**顶层**（契约第一节的 destructive 要求），不在 params 里
          action_body_with_confirm(action, params, confirm)
        },
        emit,
      ),
    )
  }
}

///|
/// 只带 profile 名的参数：{ profile }。
///
/// 隔离 / 取消隔离只认这一个键（后端 ensure_action_params 会拒掉多余的），
/// 所以不能复用 profile_pairs —— 那一条会顺手带上 home，多出来的键就是 bad-params。
fn profile_name_pairs(row : Row) -> Array[(String, String)] {
  match row.profile_name {
    Some(name) =>
      if name == "" {
        []
      } else {
        [("profile", json_text_literal(name))]
      }
    None => []
  }
}

///|
/// 更新循环的外壳。里面那一份照旧（update_inner），出来之后只补一件事：
/// 新出现一条**成功**提示时给它挂一个到期的计时。
///
/// **为什么挂在出口**：发提示的地方有二十多处，每一处都挂一次计时就是二十处漏挂的机会；
/// 出口只有一个。判断只看序号：换了一条就重新计时，同一条不重挂。
/// 失败不在这一路上 —— 它不许自动消失（§14.1）✗
fn update(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  let (next, cmd) = update_inner(model, msg, emit)
  match next.notice {
    None => (next, cmd)
    Some(n) =>
      if !n.ok {
        // 失败常驻：不挂计时，也不重置任何东西
        (next, cmd)
      } else if n.seq == notice_seq(model) {
        // 同一条还在（悬停重新计时也走这里）：计时已经在跑，不重挂
        (next, cmd)
      } else {
        (next, @cmd.batch([cmd, @cmd.delay(emit(FlashExpire(n.seq)), flash_ms)]))
      }
  }
}

///|
/// 把「这一次拖动」的过程状态全部清干净（表与回滚点不动）。
/// 起手、作废、收尾三处都走它 —— 三处各清一遍的话，漏掉一个字段就会留下
/// 一个撤不掉的占位块、或者永远抑制点击的僵尸状态。
///
/// `js_drop_clear` 也在这一处：冻结下来的那份格子坐标只属于这一次拖动，
/// 收尾不收的话，下一次拖动会拿着上一轮的坐标算落点。
fn reset_drag(model : Model) -> Model {
  js_drop_clear()
  {
    ..model,
    drag_id: "",
    drag_start_x: 0.0,
    drag_start_y: 0.0,
    drag_active: false,
    drag_group: "",
    drag_from: -1,
    drag_at: "",
    drag_at_index: -1,
    drag_ghost: false,
    drag_ghost_x: 0.0,
    drag_ghost_y: 0.0,
    drag_ghost_w: 0.0,
    drag_ghost_h: 0.0,
    drag_key_dir: 0,
  }
}

///|
fn update_inner(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    RuntimeText(_) => handle_runtime_text(model, msg, emit)
    ProfilesText(_) => handle_profiles_text(model, msg, emit)
    ConsoleText(_) => handle_console_text(model, msg, emit)
    InstancesText(_) => handle_instances_text(model, msg, emit)
    LogsText(_) => handle_logs_text(model, msg, emit)
    SidebarToggle => handle_sidebar_toggle(model, msg, emit)
    SidebarOverlayOpen => handle_sidebar_overlay_open(model, msg, emit)
    SidebarOverlayClose => handle_sidebar_overlay_close(model, msg, emit)
    Navigate(_) => handle_navigate(model, msg, emit)
    RouteChanged => handle_route_changed(model, msg, emit)
    RowAction(_, _) => handle_row_action(model, msg, emit)
    HardOpenDone(_, _, _) => handle_hard_open_done(model, msg, emit)
    StartClicked(_, _, _) => handle_start_clicked(model, msg, emit)
    DeleteOpen(_, _, _) => handle_delete_open(model, msg, emit)
    HomeDeisolateOpen(_, _) => handle_home_deisolate_open(model, msg, emit)
    HomeDeisolateConfirm => handle_home_deisolate_confirm(model, msg, emit)
    HomeDeisolateCancel => handle_home_deisolate_cancel(model, msg, emit)
    SnapshotCreate(_) => handle_snapshot_create(model, msg, emit)
    SnapshotRestoreOpen(_, _, _) => handle_snapshot_restore_open(model, msg, emit)
    SnapshotRestoreConfirm => handle_snapshot_restore_confirm(model, msg, emit)
    SnapshotRestoreCancel => handle_snapshot_restore_cancel(model, msg, emit)
    PromoteOpen(_) => handle_promote_open(model, msg, emit)
    PromoteSourcePicked(_) => handle_promote_source_picked(model, msg, emit)
    PromotePreviewDone(_) => handle_promote_preview_done(model, msg, emit)
    PromoteConfirmOpen => handle_promote_confirm_open(model, msg, emit)
    PromoteConfirmCancel => handle_promote_confirm_cancel(model, msg, emit)
    PromoteConfirm => handle_promote_confirm(model, msg, emit)
    PromoteBack => handle_promote_back(model, msg, emit)
    PromoteClose => handle_promote_close(model, msg, emit)
    DrawerOpen(_) => handle_drawer_open(model, msg, emit)
    DrawerClose => handle_drawer_close(model, msg, emit)
    SplitMenuToggle => handle_split_menu_toggle(model, msg, emit)
    SplitMenuClose => handle_split_menu_close(model, msg, emit)
    HealthTick => handle_health_tick(model, msg, emit)
    HealthDone(_) => handle_health_done(model, msg, emit)
    HealthVisible => handle_health_visible(model, msg, emit)
    DrawerClosed(_) => handle_drawer_closed(model, msg, emit)
    DragDown(_, _, _) => handle_drag_down(model, msg, emit)
    DragMove(_, _, _) => handle_drag_move(model, msg, emit)
    DragUp => handle_drag_up(model, msg, emit)
    DragCancel => handle_drag_cancel(model, msg, emit)
    ReorderKey(_, _) => handle_reorder_key(model, msg, emit)
    ReorderCommit(_) => handle_reorder_commit(model, msg, emit)
    OrderDone(_) => handle_order_done(model, msg, emit)
    StartTick(_) => handle_start_tick(model, msg, emit)
    StartTabRetry => handle_start_tab_retry(model, msg, emit)
    ForkOpen(..) => handle_fork_open(model, msg, emit)
    ForkConfirm => handle_fork_confirm(model, msg, emit)
    ForkCancel => handle_fork_cancel(model, msg, emit)
    RepairOpen(..) => handle_repair_open(model, msg, emit)
    CliHelpOpen(_) => handle_cli_help_open(model, msg, emit)
    CliHelpClose => handle_cli_help_close(model, msg, emit)
    RepairCancel => handle_repair_cancel(model, msg, emit)
    RepairConfirm => handle_repair_confirm(model, msg, emit)
    NoticePanelOpen => handle_notice_panel_open(model, msg, emit)
    NoticePanelClose => handle_notice_panel_close(model, msg, emit)
    NoticeOpenLogs => handle_notice_open_logs(model, msg, emit)
    NoticeOpenUi => handle_notice_open_ui(model, msg, emit)
    RestartTick => handle_restart_tick(model, msg, emit)
    RenameInput(_) => handle_rename_input(model, msg, emit)
    RenameConfirm => handle_rename_confirm(model, msg, emit)
    RenameCancel => handle_rename_cancel(model, msg, emit)
    NoteOpen(_) => handle_note_open(model, msg, emit)
    NoteInput(_) => handle_note_input(model, msg, emit)
    NoteConfirm => handle_note_confirm(model, msg, emit)
    NoteCancel => handle_note_cancel(model, msg, emit)
    NewInstanceOpen => handle_new_instance_open(model, msg, emit)
    NewInstanceClose => handle_new_instance_close(model, msg, emit)
    NewInstanceStatePicked(_) => handle_new_instance_state_picked(model, msg, emit)
    NewInstanceNameInput(_) => handle_new_instance_name_input(model, msg, emit)
    NewInstanceConfirm => handle_new_instance_confirm(model, msg, emit)
    NewInstanceBaseToggled(_) => handle_new_instance_base_toggled(model, msg, emit)
    NewInstanceDone(_) => handle_new_instance_done(model, msg, emit)
    NewInstanceBaseDone(_) => handle_new_instance_base_done(model, msg, emit)
    DeleteConfirm => handle_delete_confirm(model, msg, emit)
    DeleteCancel => handle_delete_cancel(model, msg, emit)
    TrashRestore(_) => handle_trash_restore(model, msg, emit)
    TrashPurgeOpen(_, _) => handle_trash_purge_open(model, msg, emit)
    TrashPurgeConfirm => handle_trash_purge_confirm(model, msg, emit)
    TrashPurgeCancel => handle_trash_purge_cancel(model, msg, emit)
    VersionSidebarOpen => handle_version_sidebar_open(model, msg, emit)
    VersionSidebarClose => handle_version_sidebar_close(model, msg, emit)
    VersionQueryInput(_) => handle_version_query_input(model, msg, emit)
    VersionFilterToggle(_) => handle_version_filter_toggle(model, msg, emit)
    VersionSortPicked(_) => handle_version_sort_picked(model, msg, emit)
    JobVersionPicked(_) => handle_job_version_picked(model, msg, emit)
    ProfileSidebarOpen => handle_profile_sidebar_open(model, msg, emit)
    ProfileSidebarClose => handle_profile_sidebar_close(model, msg, emit)
    JobProfilePicked(_) => handle_job_profile_picked(model, msg, emit)
    JobStartFocus => handle_job_start_focus(model, msg, emit)
    RefreshReadings => handle_refresh_readings(model, msg, emit)
    ReleasesText(_) => handle_releases_text(model, msg, emit)
    ReleasesTick => handle_releases_tick(model, msg, emit)
    ReleasesRefresh => handle_releases_refresh(model, msg, emit)
    ReleasesRefreshDone(_) => handle_releases_refresh_done(model, msg, emit)
    JobStart => handle_job_start(model, msg, emit)
    JobAction(_, _) => handle_job_action(model, msg, emit)
    JobToggle(_) => handle_job_toggle(model, msg, emit)
    JobDone(_, _) => handle_job_done(model, msg, emit)
    ToggleArchived => handle_toggle_archived(model, msg, emit)
    LogSourcePicked(_) => handle_log_source_picked(model, msg, emit)
    LogRefresh => handle_log_refresh(model, msg, emit)
    SettingsText(_) => handle_settings_text(model, msg, emit)
    SettingsRetry => handle_settings_retry(model, msg, emit)
    SettingsGroupPicked(_) => handle_settings_group_picked(model, msg, emit)
    SettingsBack => handle_settings_back(model, msg, emit)
    SettingDraft(_, _) => handle_setting_draft(model, msg, emit)
    SettingCommit(_, _) => handle_setting_commit(model, msg, emit)
    SettingToggle(_, _) => handle_setting_toggle(model, msg, emit)
    SettingReset(_) => handle_setting_reset(model, msg, emit)
    SettingsSaved(_, _) => handle_settings_saved(model, msg, emit)
    // 启动变量（§61.3 / §62.3）：改值 / 删行 / 添行 / 添行那两格输入 / 生效方式 /
    // 显示隐藏 / 对话框 / 回执
    EnvDraft(_, _, _) => handle_env_draft(model, msg, emit)
    EnvCommit(_, _, _) => handle_env_commit(model, msg, emit)
    EnvDelete(_, _) => handle_env_delete(model, msg, emit)
    EnvAdd(_) => handle_env_add(model, msg, emit)
    EnvAddKeyInput(_) => handle_env_add_input(model, msg, emit)
    EnvAddValueInput(_) => handle_env_add_input(model, msg, emit)
    EnvInheritToggled(_) => handle_env_options(model, msg, emit)
    EnvMergePicked(_) => handle_env_options(model, msg, emit)
    EnvReveal(_, _) => handle_env_reveal(model, msg, emit)
    EnvProfileOpen(_) => handle_env_profile_open(model, msg, emit)
    EnvProfileClose => handle_env_profile_close(model, msg, emit)
    EnvSaved(_, _) => handle_env_saved(model, msg, emit)
    HttpDone(_, _, _, _, _) => handle_http_done(model, msg, emit)
    CopyDone(_, _) => handle_copy_done(model, msg, emit)
    FlashExpire(_) => handle_flash_expire(model, msg, emit)
    FlashRemove(_) => handle_flash_remove(model, msg, emit)
    FlashHover(_) => handle_flash_hover(model, msg, emit)
    DshVersionPin(_, _) => handle_dsh_version_pin(model, msg, emit)
    DshVersionUnpin => handle_dsh_version_unpin(model, msg, emit)
    Noop => handle_noop(model, msg, emit)
  }
}
