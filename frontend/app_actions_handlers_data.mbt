// 读数落地类 Msg（runtime / profiles / console / instances / logs / 通用 HTTP 回执）。

///|
/// RuntimeText 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_runtime_text(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    RuntimeText(res) => {
      let time = local_time_now()
      let next = match res {
        Ok(text) =>
          match parse_runtime(text) {
            Ok(facts) =>
              {
                ..model,
                runtime: Some(facts),
                runtime_error: "",
                runtime_time: time,
                tag_runtime: None,
                read_runtime: true,
              }
            Err(reason) =>
              {
                ..model,
                runtime: None,
                runtime_error: reason,
                runtime_time: time,
                tag_runtime: fallback_tag("控制台自身读数读取失败：" + reason),
                read_runtime: true,
              }
          }
        Err(err) => {
          let reason = "读不到本机数据（" + describe(err) + "）"
          {
            ..model,
            runtime: None,
            runtime_error: reason,
            runtime_time: time,
            tag_runtime: fallback_tag("控制台自身读数读取失败：" + reason),
            read_runtime: true,
          }
        }
      }
      rebuild(next, emit)
    }
    _ => (model, @cmd.none)
  }
}

///|
/// ProfilesText 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_profiles_text(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    ProfilesText(res) => {
      let next = match res {
        Ok(text) =>
          match parse_profiles(text) {
            Ok(facts) =>
              {
                ..model,
                profiles: Some(facts),
                profiles_error: "",
                tag_profiles: None,
                read_profiles: true,
              }
            Err(reason) =>
              {
                ..model,
                profiles: None,
                profiles_error: reason,
                tag_profiles: fallback_tag("profile 读数读取失败：" + reason),
                read_profiles: true,
              }
          }
        Err(err) => {
          let reason = "读不到本机数据（" + describe(err) + "）"
          {
            ..model,
            profiles: None,
            profiles_error: reason,
            tag_profiles: fallback_tag("profile 读数读取失败：" + reason),
            read_profiles: true,
          }
        }
      }
      rebuild(next, emit)
    }
    _ => (model, @cmd.none)
  }
}

///|
/// ConsoleText 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_console_text(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    ConsoleText(res) => {
      // 这一份读不到不算致命：卡片上的「由本控制台启动」与归档区会缺，别的读数照旧。
      // read_console 照样置 true —— 它挡住的是「列表拼装」，不该为一份读数卡住整页。
      let next = match res {
        Ok(text) =>
          match parse_console(text) {
            Ok(facts) =>
              {
                ..model,
                console: Some(facts),
                console_error: "",
                tag_archived: None,
                read_console: true,
                // 顺序表跟着读数一起换。**拖动换位之后不再重读这一份**：
                // 就地更新过的 order 才是使用者刚才摆的那一份，重读会把它盖回去
                //（后端写成功之后两者一致，写失败时 OrderDone 会回滚）。
                order: facts.order,
              }
            Err(reason) =>
              {
                ..model,
                console: None,
                console_error: reason,
                tag_archived: fallback_tag("归档与回收站读数读取失败：" + reason),
                read_console: true,
              }
          }
        Err(err) => {
          let reason = "读不到本机数据（" + describe(err) + "）"
          {
            ..model,
            console: None,
            console_error: reason,
            tag_archived: fallback_tag("归档与回收站读数读取失败：" + reason),
            read_console: true,
          }
        }
      }
      rebuild(next, emit)
    }
    _ => (model, @cmd.none)
  }
}

///|
/// InstancesText 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_instances_text(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    InstancesText(res) => {
      let next = match res {
        Ok(text) =>
          match parse_instances(text) {
            Ok(facts) =>
              {
                ..model,
                instances: Some(facts),
                instances_error: "",
                tag_instances: None,
                read_instances: true,
              }
            Err(reason) =>
              {
                ..model,
                instances: None,
                instances_error: reason,
                tag_instances: fallback_tag("实例读数读取失败：" + reason),
                read_instances: true,
              }
          }
        Err(err) => {
          let reason = "读不到本机数据（" + describe(err) + "）"
          {
            ..model,
            instances: None,
            instances_error: reason,
            tag_instances: fallback_tag("实例读数读取失败：" + reason),
            read_instances: true,
          }
        }
      }
      rebuild(next, emit)
    }
    _ => (model, @cmd.none)
  }
}

///|
/// LogsText 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_logs_text(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    LogsText(res) => {
      let time = local_time_now()
      let source = model.log_source
      let label = source_label(model, source)
      let next = match res {
        Ok(text) =>
          match parse_logs(text) {
            Ok(facts) =>
              if facts.read_ok {
                {
                  ..model,
                  logs: Some(facts),
                  log_error: "",
                  log_time: time,
                  log_tag: None,
                  log_loading: false,
                  // 这一份内容属于哪个来源：按接口回的 source 记账（前端不猜）
                  log_source_read: facts.source,
                }
              } else {
                let reason = match facts.read_error {
                  Some(text) => text
                  None => "未知原因"
                }
                {
                  ..model,
                  logs: Some(facts),
                  log_error: reason,
                  log_time: time,
                  log_tag: fallback_tag(label + "真实读取失败：" + reason),
                  log_loading: false,
                }
              }
            Err(reason) =>
              {
                ..model,
                logs: None,
                log_error: reason,
                log_time: time,
                log_tag: fallback_tag(label + "读取失败：" + reason),
                log_loading: false,
              }
          }
        Err(err) => {
          let reason = describe(err)
          {
            ..model,
            logs: None,
            log_error: reason,
            log_time: time,
            log_tag: fallback_tag(label + "读取失败：" + reason),
            log_loading: false,
          }
        }
      }
      // 从失败提示条跳过来的那一次：日志区此刻才真的在 DOM 里，焦点与滚底一起做。
      let pending = next.log_focus_pending
      let tail = if pending {
        @cmd.batch([
          scroll_bottom_after_render("dsh-log-box"),
          focus_after_render("dsh-log-box"),
        ])
      } else {
        scroll_bottom_after_render("dsh-log-box")
      }
      ({ ..next, log_focus_pending: false }, tail)
    }
    // 侧栏切页：状态与地址一起走。同一页连点两次不会攒出两条一样的历史（见 route.mbt）。
    _ => (model, @cmd.none)
  }
}

///|
/// RefreshReadings 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_refresh_readings(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    RefreshReadings => refresh_readings(model, emit)
    _ => (model, @cmd.none)
  }
}

///|
/// HttpDone 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_http_done(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    HttpDone(row_id, action, name, verb, res) => {
      let (ok, note) = interpret_http(res)
      if action == "set-profile-note" {
        note_settled(model, res, name, note, emit)
      } else if action == "pin-dsh" || action == "unpin-dsh" {
        dsh_pin_settled(model, action, ok, note, emit)
      } else if action == "start-instance" && model.act_pending == row_id {
        finish_start({ ..model, act_response: true, act_ok: ok, act_note: note }, emit)
      } else {
        let mut cleared = map_rows(model, row_id, fn(row) { { ..row, busy: false } })
        // 移动这一枪的回执到了：抽屉里那颗按钮的「正在移动…」随之收掉（成没成都收）。
        if action == "isolate-profile" || action == "deisolate-profile" {
          cleared = { ..cleared, home_move_id: "" }
        }
        // 补包这一枪的回执到了（§39.3）：「正在安装…」收掉；成功那条下面走
        // refresh_readings，重读之后缺包数会归零、灯也不再是黄。
        if action == "repair-packages" {
          cleared = { ..cleared, repair_id: "" }
        }
        // 还原这一枪的回执到了：确认框那三格随之清空（成没成都清）
        if action == "restore-snapshot" {
          cleared = {
            ..cleared,
            snapshot_confirm_id: "",
            snapshot_confirm_snap: "",
            snapshot_confirm_return: "",
          }
        }
        if ok {
          // 改名落地：抽屉跟着这一行走（§30.2 要抽屉标题跟着变）。行 id 里带着 profile 名，
          // 名字一换 id 就换了；不重算的话抽屉会挂在一个已经不存在的 id 上，等于被这次改名关掉。
          // 行 id 里带着 profile 名，新 id 用新名字 + 这一格原来的 home 拼（与 build 那条同一把尺子）。
          if action == "rename-profile" &&
            cleared.drawer_id == row_id &&
            row_id.has_prefix("profile:") {
            let new_name = match outcome_of(res) {
              Some(outcome) => str_field(outcome, "newName")
              None => ""
            }
            if new_name != "" {
              let home = match find_row(model.rows, row_id) {
                Some(row) => row.home
                None => ""
              }
              cleared = {
                ..cleared,
                drawer_id: profile_row_id(new_name, home),
              }
            }
          }
          // 删掉的那一行已经不在了：抽屉跟着收（没有可显示的行，留着只会挂一个空壳）。
          if action == "delete-profile" && cleared.drawer_id == row_id {
            cleared = { ..cleared, drawer_id: "" }
          }
          // 回执说人话：谁 + 做了什么 + 结果（见 action_receipt）。
          // 后端回执原文与里面的数字、路径收进悬停，不摊在正文上。
          let (shown, hint) = action_receipt(action, name, verb, note, res)
          // 本地不猜结果：归档记录、运行时登记、回收站条目都在后端的读数里，
          // 重读 console / profiles / instances 之后界面自己会变
          let (next, cmd) = refresh_readings(notice_put(cleared, true, shown, hint), emit)
          if action == "promote-profile" {
            // 替换落地了：侧栏收掉（它的预览已经过期），焦点回那张卡
            let return_id = model.promote_return
            (
              {
                ..next,
                promote_row: "",
                promote_return: "",
                promote_source: "",
                promote_preview: None,
                promote_preview_error: "",
                promote_loading: false,
                promote_confirm: false,
              },
              @cmd.batch([cmd, focus_after_render(return_id)]),
            )
          } else {
            (next, cmd)
          }
        } else {
          // 失败只留一句结论（§32.1）：完整原文进悬停，也留在这次动作写的审计行里。
          (notice_failed_action(cleared, name + " " + verb + "失败：" + note), @cmd.none)
        }
      }
    }
    // 剪贴板回执：只说这一枪的真实结局（写进去了 / 两条路都失败），
    // 复制成功不改任何读数，所以这里不刷新列表。
    _ => (model, @cmd.none)
  }
}

///|
/// CopyDone 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_copy_done(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    CopyDone(subject, res) => {
      let (ok, note, detail) = match res {
        Ok(text) => parse_copy_result(text)
        Err(err) => (false, "没能复制到剪贴板", "剪贴板调用没发出去：" + describe(err))
      }
      (notice_put(model, ok, subject + note, detail), @cmd.none)
    }
    // toast 到期：序号对不上说明这一条已经被换掉了（或已经收掉了），那一枪作废
    _ => (model, @cmd.none)
  }
}

///|
/// 把 Error 说成一句人话（读失败提示里用；state.mbt 那次拆分后这里补一份）。
fn describe(err : Error) -> String {
  err.to_string()
}
