// 设置与界面偏好的回执落地（设置读写、侧栏、归档区、版本锁定）。

///|
/// SidebarToggle 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_sidebar_toggle(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    SidebarToggle => toggle_sidebar(model, emit)
    _ => (model, @cmd.none)
  }
}

///|
/// SidebarOverlayOpen 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_sidebar_overlay_open(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    SidebarOverlayOpen =>
      (
        { ..model, sidebar_overlay: true, },
        // 焦点进第一个导航项：键盘接下来直接落在导航里，不用先 Tab 过顶栏
        focus_after_render(nav_dom_id(Overview)),
      )
    _ => (model, @cmd.none)
  }
}

///|
/// SidebarOverlayClose 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_sidebar_overlay_close(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    SidebarOverlayClose =>
      if model.sidebar_overlay {
        (
          { ..model, sidebar_overlay: false, },
          focus_after_render(side_burger_id()),
        )
      } else {
        (model, @cmd.none)
      }
    _ => (model, @cmd.none)
  }
}

///|
/// ToggleArchived 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_toggle_archived(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    ToggleArchived =>
      (
        {
          ..model,
          archived_open: !model.archived_open,
          archived_user_toggled: true,
        },
        @cmd.none,
      )
    // 换来源：来源是页面状态的一部分，跟着进地址（换来源 = 走一步，可以后退回来）
    _ => (model, @cmd.none)
  }
}

///|
/// SettingsText 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_settings_text(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    SettingsText(res) => settings_loaded_state(model, res)
    _ => (model, @cmd.none)
  }
}

///|
/// SettingsRetry 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_settings_retry(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    SettingsRetry =>
      (
        {
          ..model,
          settings_loading: true,
          settings_error: "",
          settings_loaded: false,
        },
        settings_get_cmd(emit),
      )
    // 设置分组也是页面状态：切分组就换地址，刷新 / 后退都回到同一组。
    // 窄屏上这一步是「进第二级」：焦点落到返回键上，键盘接下来直接能退出去。
    // 宽屏两列同屏，点索引只是换右边的内容 —— 焦点留在点过的那一行才顺手，不挪。
    _ => (model, @cmd.none)
  }
}

///|
/// SettingsGroupPicked 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_settings_group_picked(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    SettingsGroupPicked(id) =>
      (
        { ..model, settings_group: id, route_notice: "", },
        @cmd.batch([
          push_route(route_url(Settings, id, model.log_source)),
          if narrow_settings_page() {
            focus_after_render(settings_back_dom_id())
          } else {
            @cmd.none
          },
        ]),
      )
    // 窄屏第二级的返回键：回第一级，焦点还给刚进来的那一行
    _ => (model, @cmd.none)
  }
}

///|
/// SettingsBack 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_settings_back(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    SettingsBack =>
      (
        { ..model, settings_group: "", route_notice: "", },
        @cmd.batch([
          push_route(route_url(Settings, "", model.log_source)),
          focus_after_render(
            settings_row_dom_id(setting_group_of(model.settings_group).id),
          ),
        ]),
      )
    _ => (model, @cmd.none)
  }
}

///|
/// SettingDraft 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_setting_draft(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    SettingDraft(key, text) =>
      (
        { ..model, settings_draft: put_draft(model.settings_draft, key, text), },
        @cmd.none,
      )
    _ => (model, @cmd.none)
  }
}

///|
/// SettingCommit 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_setting_commit(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    SettingCommit(key, text) => commit_setting(model, key, text, emit)
    _ => (model, @cmd.none)
  }
}

///|
/// SettingToggle 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_setting_toggle(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    SettingToggle(key, next) =>
      commit_setting_value(model, key, VBool(next), emit)
    // 恢复默认走同一条 PUT（值取后端给的缺省值，不是前端自己填一个数）
    _ => (model, @cmd.none)
  }
}

///|
/// SettingReset 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_setting_reset(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    SettingReset(key) => reset_setting(model, key, emit)
    _ => (model, @cmd.none)
  }
}

///|
/// SettingsSaved 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_settings_saved(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    SettingsSaved(key, res) => settings_saved_state(model, key, res)
    // ── 写动作的回执 ───────────────────────────────────────
    // 启动走「回执 + 展示下限」两条腿；其余动作拿到回执就落定，
    // 成功的动作一律重读 profiles / instances（刷新的是读数，不是弹个提示）。
    _ => (model, @cmd.none)
  }
}

///|
/// DshVersionPin 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_dsh_version_pin(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    DshVersionPin(dir, version) => pin_dsh_version(model, dir, version, emit)
    _ => (model, @cmd.none)
  }
}

///|
/// DshVersionUnpin 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_dsh_version_unpin(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    DshVersionUnpin => unpin_dsh_version(model, emit)
    _ => (model, @cmd.none)
  }
}
