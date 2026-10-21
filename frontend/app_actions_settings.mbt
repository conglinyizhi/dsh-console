// 设置页那一族：草稿、控件 id、保存 / 重置 / 合并回执，以及侧栏收起（ui.sidebarCollapsed）\n// 与归档区默认展开（ui.archiveOpenByDefault）这两条界面偏好的落地。\n//\n// 2026-10-20 从 app_actions.mbt 拆出来：设置是一套完整的读写闭环（草稿 → PUT → 合并回显），\n// 跟别的动作不共用状态。只搬位置，函数体一个字没改。\n

///|
fn put_draft(drafts : Array[SettingDraft], key : String, text : String) -> Array[SettingDraft] {
  let out = drafts.filter(fn(draft) { draft.key != key })
  out.push({ key, text })
  out
}

///|
fn drop_draft(drafts : Array[SettingDraft], key : String) -> Array[SettingDraft] {
  drafts.filter(fn(draft) { draft.key != key })
}

///|
/// 控件在 DOM 上的 id（view_settings.mbt 建控件时用同一个口径）。
fn setting_control_id(key : String) -> String {
  "dsh-setting-" + key
}

///|
/// 这一项当前已保存的值在界面上的文本（控件要退回的那一个）。
fn setting_stored_text(model : Model, key : String) -> String {
  match model.settings {
    None => ""
    Some(facts) =>
      match setting_by_key(key) {
        None => ""
        Some(def) =>
          match setting_current(facts, def) {
            Some(value) => setting_value_text(value)
            None => ""
          }
      }
  }
}

///|
fn setting_label(key : String) -> String {
  match setting_by_key(key) {
    Some(def) => def.label
    None => key
  }
}

///|
/// 归档区默认展开只在那一次生效：用户自己折过之后就不再覆盖他的选择。
fn default_archive_open(model : Model, facts : SettingsFacts) -> Bool {
  if model.archived_user_toggled {
    model.archived_open
  } else {
    match lookup_setting(facts.values, "ui.archiveOpenByDefault") {
      Some(VBool(on)) => on
      _ => model.archived_open
    }
  }
}

///|
/// 宽屏侧栏的形态，**判据只有设置里的 ui.sidebarCollapsed**（design/sidebar-collapse.md）。
///
/// 读不到就是 false（展开）：契约缺省本来就是展开，而且「没读到就收起」会让
/// 一台还没提供设置接口的后端把导航藏成一条图标栏。
fn sidebar_collapsed_of(facts : SettingsFacts) -> Bool {
  match lookup_setting(facts.values, "ui.sidebarCollapsed") {
    Some(VBool(on)) => on
    _ => false
  }
}

///|
/// 设置里存着的形态（模型里那份副本写失败时要退回它）。
fn sidebar_collapsed_stored(model : Model) -> Bool {
  match model.settings {
    Some(facts) => sidebar_collapsed_of(facts)
    None => false
  }
}

///|
/// 宽屏顶栏的折叠按钮：**先翻界面，再写设置**。
///
/// 先翻是因为「点了没动」最容易被再点一次；写设置走的是设置页同一条 PUT
/// （commit_setting_value），回执失败时 settings_saved_state 会把形态退回存着的那一份，
/// 所以这里不必再挂一份回滚。
fn toggle_sidebar(model : Model, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  let next = !model.sidebar_collapsed
  let (saving, cmd) = commit_setting_value(model, "ui.sidebarCollapsed", VBool(next), emit)
  ({ ..saving, sidebar_collapsed: next }, cmd)
}

///|
/// GET /api/local/settings 的结果落地。404 / 501 与别的失败分开记：
/// 前者是「后端还没提供这个接口」，页面要照实说。
fn settings_loaded_state(model : Model, res : Result[String, Error]) -> (Model, @cmd.Cmd) {
  let base = { ..model, settings_loading: false, settings_loaded: true }
  match res {
    Err(err) => {
      let reason = "请求没发出去（" + describe(err) + "）"
      (
        {
          ..base,
          settings: None,
          settings_status: 0,
          settings_status_text: "",
          settings_error: reason,
          settings_endpoint_missing: false,
          tag_settings: fallback_tag("设置读数读取失败：" + reason),
        },
        @cmd.none,
      )
    }
    Ok(text) => {
      let got = parse_http_result(text)
      if got.status == 0 {
        let reason = "请求失败（" + got.transport_error + "）"
        (
          {
            ..base,
            settings: None,
            settings_status: 0,
            settings_status_text: "",
            settings_error: reason,
            settings_endpoint_missing: false,
            tag_settings: fallback_tag("设置读数读取失败：" + reason),
          },
          @cmd.none,
        )
      } else if got.status >= 200 && got.status < 300 {
        match parse_settings(got.body) {
          Ok(facts) => {
            // 启动变量（§61 / §62）跟着同一份读数回来：reparse 一次拿 data 再取 env 段。
            // 设置项与 env 是两份文件、同一枪读；分成两枪会多一次「读到了设置、没读到 env」的中间态。
            // options 段同理：它有没有（env_options_known）决定界面摆不摆那两项。
            let env = env_facts_of_response(got.body)
            let parsed = {
              ..base,
              settings: Some(facts),
              settings_status: got.status,
              settings_status_text: got.status_text,
              settings_error: "",
              settings_endpoint_missing: false,
              // 读到了就不摆标记：连上一次失败留下的那一副也要清掉
              tag_settings: None,
              archived_open: default_archive_open(base, facts),
              sidebar_collapsed: sidebar_collapsed_of(facts),
              env_path: env.path,
              env_global: env.global,
              env_profiles: env.profiles,
              env_reserved: env.reserved,
              env_options_known: env.options_known,
              env_inherit: env.inherit_env,
              env_merge: env.merge,
            }
            // 读数跟上来之后，与它一样的草稿自动收掉（保存成功那一格就是这样退场的）；
            // 正在敲、还没存的那一格文本仍然不同，留着。
            (
              { ..parsed, env_draft: env_prune_drafts(parsed) },
              @cmd.none,
            )
          }
          Err(reason) => {
            let detail = http_status_text(got) + " | 响应不是约定的成功壳：" + reason
            (
              {
                ..base,
                settings: None,
                settings_status: got.status,
                settings_status_text: got.status_text,
                settings_error: detail,
                settings_endpoint_missing: false,
                tag_settings: fallback_tag("设置读数读取失败：" + detail),
              },
              @cmd.none,
            )
          }
        }
      } else {
        let missing = got.status == 404 || got.status == 501
        let detail = (if missing {
          "这台控制台还没有提供设置读数。"
        } else {
          "读设置时出错了。"
        }) + failure_note(got)
        (
          {
            ..base,
            settings: None,
            settings_status: got.status,
            settings_status_text: got.status_text,
            settings_error: detail,
            settings_endpoint_missing: missing,
            tag_settings: fallback_tag(
              "设置读数读取失败：" + http_status_text(got),
            ),
          },
          @cmd.none,
        )
      }
    }
  }
}

///|
/// 提交一个数字 / 枚举控件：先本地校验（越界不发请求，先说清哪里不对），再 PUT。
fn commit_setting(
  model : Model,
  key : String,
  text : String,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match setting_by_key(key) {
    None => (model, @cmd.none)
    Some(def) =>
      match setting_parse_input(def, text) {
        Err(reason) => {
          let back = setting_stored_text(model, key)
          (
            notice_err(
              { ..model, settings_draft: drop_draft(model.settings_draft, key) },
              def.label + " 没保存：" + reason,
            ),
            set_control_after_render(setting_control_id(key), back),
          )
        }
        Ok(value) => commit_setting_value(model, key, value, emit)
      }
  }
}

///|
/// 开关走这里（没有草稿）；数字与枚举校验通过之后也走这里。
/// 草稿先留着：保存回来之前控件上还是用户填的那个值，成功失败再决定去留。
fn commit_setting_value(
  model : Model,
  key : String,
  value : SettingValue,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match setting_by_key(key) {
    None => (model, @cmd.none)
    Some(_) =>
      // 「正在保存 …」不播报（§14.3 只认保存成功 / 失败）：这一句既不是结果，
      // 又会把刚才那条失败提示顶掉。控件自己在 settings_saving 期间是禁用的。
      (
        {
          ..model,
          settings_saving: key,
          settings_pending: Some(value),
        },
        settings_put_cmd(key, settings_put_body(key, value), emit),
      )
  }
}

///|
/// 「恢复默认」：把这一项写回**后端给的缺省值**（GET 里那份 defaults），走与手改完全同一条 PUT。
///
/// 缺省值读不到时什么都不做，只把原因说清 —— 退到本地契约表里的那个数去顶，
/// 就是在用户没要求的时候替他写了一个他不认识的数。
fn reset_setting(model : Model, key : String, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  let label = setting_label(key)
  let value = match model.settings {
    Some(facts) =>
      match lookup_setting(facts.defaults, key) {
        Some(value) => Some(value)
        None => None
      }
    None => None
  }
  match value {
    Some(value) => commit_setting_value(model, key, value, emit)
    None => (
      notice_err(model, label + " 没能恢复默认：读数里没有这一项的缺省值"),
      @cmd.none,
    )
  }
}

///|
/// 保存结果落地：成功用后端回的新值更新这一项（PUT 回的壳与 GET 同形就用它，
/// 不然按提交值算并把来源写成「文件」）；失败把草稿退回已保存的值并显示后端给的原因。
fn settings_saved_state(
  model : Model,
  key : String,
  res : Result[String, Error],
) -> (Model, @cmd.Cmd) {
  let label = setting_label(key)
  let (ok, note) = interpret_http(res)
  let drafts = drop_draft(model.settings_draft, key)
  if !ok {
    let back = setting_stored_text(model, key)
    let failed = { ..model, settings_saving: "", settings_pending: None, settings_draft: drafts }
    // 侧栏那一次点击是**先动界面、再写设置**的：写失败就把界面退回设置里存着的那一份，
    // 不能停在「看着收起了、其实没存下」的状态（与拖动换位的回滚同一条规矩）。
    let failed = if key == "ui.sidebarCollapsed" {
      { ..failed, sidebar_collapsed: sidebar_collapsed_stored(model) }
    } else {
      failed
    }
    return (
      notice_err(failed, label + " 没保存：" + note),
      set_control_after_render(setting_control_id(key), back),
    )
  }
  let facts = merge_saved(model, key, res)
  let value_text = match model.settings_pending {
    Some(value) => setting_value_text(value)
    None => "已保存"
  }
  let saved = {
    ..model,
    settings: Some(facts),
    settings_saving: "",
    settings_pending: None,
    settings_draft: drafts,
    tag_settings: None,
  }
  // 设置页那颗开关与外壳那颗折叠按钮是同一个键：两边都得跟着读数走
  let saved = if key == "ui.sidebarCollapsed" {
    { ..saved, sidebar_collapsed: sidebar_collapsed_of(facts) }
  } else {
    saved
  }
  // 开关保存成功之后把焦点送回那一颗（§51.4）：这一行会因为「恢复默认」按钮的出现
  // 而改变节点结构，焦点会掉到 body —— 键盘用户按一次空格就再也接不上第二下。
  let refocus = if setting_is_switch(key) {
    focus_after_render(setting_switch_id(key))
  } else {
    @cmd.none
  }
  (
    notice_ok(
      saved,
      label + " 已保存：" + value_text,
      "",
    ),
    refocus,
  )
}

///|
/// 保存成功之后这一项的取值：后端回了同形的壳就以它为准，否则记下提交的值。
fn merge_saved(model : Model, key : String, res : Result[String, Error]) -> SettingsFacts {
  let base = match model.settings {
    Some(facts) => facts
    None => { values: [], defaults: [], sources: [] }
  }
  let from_body = match res {
    Ok(text) => {
      let got = parse_http_result(text)
      match parse_settings(got.body) {
        Ok(facts) => Some(facts)
        Err(_) => None
      }
    }
    Err(_) => None
  }
  match from_body {
    Some(facts) =>
      match lookup_setting(facts.values, key) {
        Some(_) => facts
        None => put_setting(base, key, model.settings_pending)
      }
    None => put_setting(base, key, model.settings_pending)
  }
}

///|
fn put_setting(facts : SettingsFacts, key : String, value : SettingValue?) -> SettingsFacts {
  match value {
    None => facts
    Some(value) => {
      let values = facts.values.filter(fn(item) { item.key != key })
      values.push({ key, value })
      let sources = facts.sources.filter(fn(item) { item.key != key })
      sources.push({ key, value: VText("文件") })
      { values, defaults: facts.defaults, sources }
    }
  }
}


// ── 更新 ───────────────────────────────────────────────────
