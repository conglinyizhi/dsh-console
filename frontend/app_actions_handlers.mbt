// 各条 Msg 的回执落地：每一个 handler 对应 update_inner 里的一个分支，函数体是原样搬过来的，
// 外面那层 match 只留一行调用。
//
// 2026-10-20 从 app_actions.mbt 拆出来：update_inner 一个函数 1800 多行，改任何一条都会
// 滚很久；抽出来之后「哪条消息归谁处理」一眼可见。函数体逐字搬，不改逻辑。

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
    _ => (model, @cmd.none)
  }
}

///|
/// LogsText 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_logs_text(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
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
/// SidebarToggle 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_sidebar_toggle(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    SidebarToggle => toggle_sidebar(model, emit)
    _ => (model, @cmd.none)
  }
}

///|
/// SidebarOverlayOpen 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_sidebar_overlay_open(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    SidebarOverlayOpen => (
      { ..model, sidebar_overlay: true },
      // 焦点进第一个导航项：键盘接下来直接落在导航里，不用先 Tab 过顶栏
      focus_after_render(nav_dom_id(Overview)),
    )
    _ => (model, @cmd.none)
  }
}

///|
/// SidebarOverlayClose 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_sidebar_overlay_close(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    SidebarOverlayClose => 
      if model.sidebar_overlay {
        ({ ..model, sidebar_overlay: false }, focus_after_render(side_burger_id()))
      } else {
        (model, @cmd.none)
    _ => (model, @cmd.none)
  }
}

///|
/// Navigate 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_navigate(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    Navigate(page) => {
      let route : Route = {
        page,
        group: model.settings_group,
        // 用户自己挑过的日志来源在他点侧栏「日志」时要留着（地址里因此也带这个来源）；
        // 没挑过就按当时的读数推导默认来源，与总览页拼列表同一个口径。
        source: if page is Logs && model.log_user_picked {
          Some(model.log_source)
        } else {
          None
        },
        notice: "",
      }
      let from_overlay = model.sidebar_overlay
      let (next, enter) = route_into(model, route, emit)
      // 从覆盖层里点了一项：侧栏收起后焦点回汉堡（它就在顶栏那一行，接着按键盘不用重新找）
      let back = if from_overlay {
        focus_after_render(side_burger_id())
      } else {
        @cmd.none
      }
      (
        next,
        @cmd.batch([
          enter,
          push_route(route_url(next.page, next.settings_group, next.log_source)),
          back,
        ]),
      )
    }
    // 浏览器前进 / 后退：地址是唯一的口径，页面按它复原（不写历史，也不清回落说明 ——
    // 退回的那一格地址可能就是个认不出来的，说明得跟着回来）。
    _ => (model, @cmd.none)
  }
}

///|
/// RouteChanged 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_route_changed(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    RouteChanged => {
      let route = parse_route(js_location_url())
      let (next, enter) = route_into(model, route, emit)
      let settle = if route.notice == "" {
        @cmd.none
      } else {
        replace_route(route_url(next.page, next.settings_group, next.log_source))
      }
      (next, @cmd.batch([enter, settle, listen_popstate(emit)]))
    _ => (model, @cmd.none)
  }
}

///|
/// RowAction 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_row_action(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    RowAction(id, key) => 
      match key {
        // 行内的启动 / 停止 / 重启都是真实动作（POST /api/local/action）：
        // 启动要等回执 + 展示下限，其余的动作直接把这一行置忙等回执。
        Toggle =>
          match find_row(model.rows, id) {
            None => (model, @cmd.none)
            Some(row) =>
              if row.status is Running {
                send_action(
                  model,
                  id,
                  "stop-instance",
                  row.name,
                  "停止",
                  params_of(port_pairs(row)),
                  emit,
                )
              } else {
                // 已停止那一侧**不从这里启动**：启动要在点击的同一个同步栈里先占一个
                // 占位标页，所以那颗按钮发的是 StartClicked（见 view_overview 的 start_click）。
                // 这里留一个不带标页的启动分支，就是给「自动开标页」留一条悄悄漏掉的路。
                (model, @cmd.none)
              }
          }
        Restart =>
          match find_row(model.rows, id) {
            None => (model, @cmd.none)
            Some(row) => {
              let (next, cmd) = send_action(
                model,
                id,
                "restart-instance",
                row.name,
                "重启",
                params_of(port_pairs(row)),
                emit,
              )
              (
                { ..next, restarting: id },
                @cmd.batch([cmd, @cmd.delay(emit(RestartTick), restart_lock_ms)]),
              )
            }
          }
        // 三个会开对话框的动作（重命名 / 删除 / 备注）**保留抽屉**，只在上面开对话框
        // （§30.1）：抽屉是 z-index 50/51、对话框 60/61，框本来就在抽屉之上；
        // 收掉抽屉会把用户正在读的读数一起撤走。关框之后焦点回抽屉里那一颗按钮，
        // 那才是「按下它」的那颗元素（卡片在这种情况下根本没被点过）。
        Rename => (
          {
            ..model,
            rename_id: id,
            // 预填的是**目录名**（改名改的就是它），不是卡片上那一串：
            // 运行中的行 row.name 是「名字 :端口」，照它预填等于把一个带空格和冒号的名字塞进输入框。
            rename_draft: match find_row(model.rows, id) {
              Some(row) =>
                match row.profile_name {
                  Some(name) => name
                  None => row_name(model, id)
                }
              None => row_name(model, id)
            },
            rename_return: drawer_rename_id(),
          },
          focus_select_after_render("dsh-rename-input"),
        )
        Delete => (
          { ..model, confirm_id: id, confirm_return: drawer_delete_id() },
          focus_after_render("dsh-confirm-ok"),
        )
        // 打开编辑框是纯前端的事，真正的写动作在保存那一步（NoteConfirm）
        Note => (model, emit(NoteOpen(id)))
        Archive =>
          send_action(
            model,
            id,
            "archive-profile",
            row_name(model, id),
            "归档",
            params_for_row(model, id, "archive"),
            emit,
          )
        Unarchive =>
          send_action(
            model,
            id,
            "unarchive-profile",
            row_name(model, id),
            "取消归档",
            params_for_row(model, id, "archive"),
            emit,
          )
        Fork =>
          send_action(
            model,
            id,
            "fork-profile",
            row_name(model, id),
            "派生",
            params_for_row(model, id, "profile"),
            emit,
          )
        // 查看日志：切到日志页（这里是状态切页，**不开新页面**），来源设成这一行对应的实例，
        // 内容打开即读一次再滚到底（不靠"上一次读过的还在"，换来源必须真读一次）。
        Logs =>
          match find_row(model.rows, id) {
            None => (model, @cmd.none)
            Some(row) =>
              match log_source_for_row(model, row) {
                Some(source) => {
                  // 这是用户自己挑的来源，rebuild 的缺省推导不许再压过它
                  let (next, read) = start_logs(
                    { ..model, page: Logs, drawer_id: "", log_user_picked: true },
                    source,
                    emit,
                  )
                  (
                    next,
                    @cmd.batch([
                      read,
                      push_route(route_url(Logs, model.settings_group, source)),
                    ]),
                  )
                }
                // 没有在跑的实例可读：留在总览页把原因说清，不切到一个空日志页
                None => (
                  notice_err(
                    { ..model, drawer_id: "" },
                    row.name +
                    " 现在没有在跑的实例，没有可读的日志来源（查看日志这一步没有执行）",
                  ),
                  @cmd.none,
                )
              }
          }
        // 打开 Web UI：开带令牌的 webUrl。读不到令牌就不开标签页，把原因与裸地址说清（见 open_web_ui）。
        OpenUi => open_web_ui(model, id)
        // 两条复制：裸地址（卡上「访问地址」那一行的原值）与带令牌的地址（webUrl）
        CopyUrl => copy_url_action(model, id, "访问地址", false, emit)
        CopyTokenUrl => copy_url_action(model, id, "带令牌的地址", true, emit)
        // 复制开发指令：一段给「另一个会话」的任务说明（粘到别的 profile 的会话里用）
        CopyDev => copy_dev_action(model, id, emit)
        // 配置 home：共用 → 直接发「移到独立 home」；独立 → 先开确认框（移回会把剩下的东西送进回收站）。
        // 移进独立 home 这一条**抽屉不收**：按钮上要能看见「正在移动…」这一刻
        //（真实的目录移动，跨盘退回复制时尤其不是瞬时的）。
        IsolateHome => {
          let (next, cmd) = send_action(
            { ..model, home_move_id: id },
            id,
            "isolate-profile",
            row_name(model, id),
            "移到独立 home",
            match find_row(model.rows, id) {
              Some(row) => params_of(profile_name_pairs(row))
              None => ""
            },
            emit,
          )
          (next, cmd)
        }
        DeisolateHome => (model, emit(HomeDeisolateOpen(id, card_id(id))))
        // 打开工作目录 / 编辑配置：都走 POST open-path，只有 kind 不同（cli 端不给路径）
        Dir => open_path_action(model, id, "dir", "打开工作目录", emit)
        Config => open_path_action(model, id, "config", "打开配置", emit)
        // 没有兜底分支了：ActionKey 的每一项上面都接上了（以前那行兜底会把这个事实藏起来）
      }
    // 抽屉里「硬开裸地址」那一枪的回执（§15.2）：结局只有一句话要说，走全局提示。
    // 这一枪在 DOM 监听器里同步打完（见 view_overview 的 hard_open_click），
    // 这里只管把结局说成一句人话。
    _ => (model, @cmd.none)
  }
}

///|
/// HardOpenDone 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_hard_open_done(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    HardOpenDone(id, url, outcome) => hard_open_done(model, id, url, outcome)
    // 启动按钮的点击：占位标页已经在 DOM 监听器里同步开好（见 view_overview 的
    // start_click），tab 是那一枪的回执。这里只按状态放行 —— 不是「已停止」就什么都不做，
    // 但占下的标页要收掉：状态在这一栈与下一次渲染之间翻了的话，它就没有下文了。
    _ => (model, @cmd.none)
  }
}

///|
/// StartClicked 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_start_clicked(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    StartClicked(id, profile, tab) => 
      match find_row(model.rows, id) {
        Some(row) =>
          if row.status is Stopped {
            start_instance(model, row, profile, tab, emit)
          } else {
            close_held_tab(profile, tab)
            (model, @cmd.none)
          }
        None => {
          close_held_tab(profile, tab)
          (model, @cmd.none)
        }
      }
    // 点开确认框：把那一刻的模式记进 model（hard = true 就是彻底删除）。
    // 确认框的标题 / 正文 / 确认键颜色与确认时发的请求都照这一格走，不事后重读设置。
    _ => (model, @cmd.none)
  }
}

///|
/// DeleteOpen 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_delete_open(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    DeleteOpen(id, return_id, hard) => (
      { ..model, confirm_id: id, confirm_return: return_id, confirm_hard: hard },
      focus_after_render("dsh-confirm-ok"),
    )
    // 移回共用 home 的确认：确认之后真发 deisolate-profile（confirm 走 body 顶层），
    // 关框与焦点回触发元素与删除确认框同一套。
    _ => (model, @cmd.none)
  }
}

///|
/// HomeDeisolateOpen 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_home_deisolate_open(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    HomeDeisolateOpen(id, return_id) => (
      {
        ..model,
        drawer_id: "",
        home_confirm_id: id,
        home_confirm_return: return_id,
      },
      focus_after_render("dsh-home-confirm-ok"),
    )
    _ => (model, @cmd.none)
  }
}

///|
/// HomeDeisolateConfirm 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_home_deisolate_confirm(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    HomeDeisolateConfirm => 
      match find_row(model.rows, model.home_confirm_id) {
        None => (
          { ..model, home_confirm_id: "" },
          focus_after_render(model.home_confirm_return),
        )
        Some(row) => {
          let params = params_of(profile_name_pairs(row))
          let return_id = model.home_confirm_return
          let confirm_id = model.home_confirm_id
          let (next, cmd) = send_action(
            {
              ..model,
              home_confirm_id: "",
              home_confirm_return: "",
              home_move_id: confirm_id,
            },
            confirm_id,
            "deisolate-profile",
            row.name,
            "移回共用 home",
            params,
            emit,
            confirm="DELETE",
          )
          (next, @cmd.batch([cmd, focus_after_render(return_id)]))
    _ => (model, @cmd.none)
  }
}

///|
/// HomeDeisolateCancel 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_home_deisolate_cancel(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    HomeDeisolateCancel => (
      { ..model, home_confirm_id: "" },
      focus_after_render(model.home_confirm_return),
    )
    // ── 配置历史（design/ops-maintenance-jobs.md §16.4）────────────
    // 创建快照是一条真实写动作：回执走全局提示，成功后重读读数 ——
    // 列表不在这里本地插一条，刷新的是读数，界面自己会变。
    _ => (model, @cmd.none)
  }
}

///|
/// SnapshotCreate 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_snapshot_create(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    SnapshotCreate(id) => 
      match find_row(model.rows, id) {
        None => (model, @cmd.none)
        Some(row) =>
          send_action(
            model,
            id,
            "snapshot-profile",
            row.name,
            "创建快照",
            params_of(profile_name_pairs(row)),
            emit,
          )
      }
    // 打开还原确认框：先把抽屉收掉（对话框在抽屉之上，背后那张留着没有意义），
    // 焦点回触发它的那张卡 —— 与删除 / 取消隔离同一套。
    _ => (model, @cmd.none)
  }
}

///|
/// SnapshotRestoreOpen 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_snapshot_restore_open(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    SnapshotRestoreOpen(id, snap, return_id) => (
      {
        ..model,
        drawer_id: "",
        snapshot_confirm_id: id,
        snapshot_confirm_snap: snap,
        snapshot_confirm_return: return_id,
      },
      focus_after_render("dsh-snapshot-confirm-ok"),
    )
    // 确认还原：params 带 profile 与 snapshot，二次确认串 RESTORE 走 body 顶层。
    _ => (model, @cmd.none)
  }
}

///|
/// SnapshotRestoreConfirm 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_snapshot_restore_confirm(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    SnapshotRestoreConfirm => 
      match find_row(model.rows, model.snapshot_confirm_id) {
        None => (
          {
            ..model,
            snapshot_confirm_id: "",
            snapshot_confirm_snap: "",
            snapshot_confirm_return: "",
          },
          focus_after_render(model.snapshot_confirm_return),
        )
        Some(row) => {
          let pairs = profile_name_pairs(row)
          pairs.push(("snapshot", json_text_literal(model.snapshot_confirm_snap)))
          let return_id = model.snapshot_confirm_return
          let confirm_id = model.snapshot_confirm_id
          let (next, cmd) = send_action(
            {
              ..model,
              snapshot_confirm_id: "",
              snapshot_confirm_snap: "",
              snapshot_confirm_return: "",
            },
            confirm_id,
            "restore-snapshot",
            row.name,
            "还原快照",
            params_of(pairs),
            emit,
            confirm="RESTORE",
          )
          (next, @cmd.batch([cmd, focus_after_render(return_id)]))
    _ => (model, @cmd.none)
  }
}

///|
/// SnapshotRestoreCancel 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_snapshot_restore_cancel(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    SnapshotRestoreCancel => (
      { ..model, snapshot_confirm_id: "", snapshot_confirm_snap: "" },
      focus_after_render(model.snapshot_confirm_return),
    )
    // ── 整体替换（design/ops-maintenance-jobs.md §17.3）────────────
    // 打开侧栏：先收抽屉（两个都是右侧浮层，叠着摆会互相挡），焦点进侧栏的关闭键。
    _ => (model, @cmd.none)
  }
}

///|
/// PromoteOpen 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_promote_open(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    PromoteOpen(id) => 
      match find_row(model.rows, id) {
        None => (model, @cmd.none)
        Some(row) =>
          match row.profile_name {
            None => (notice_err(model, row.name + " 的目录名读不到，没法替换配置"), @cmd.none)
            Some(_) =>
              (
                {
                  ..model,
                  drawer_id: "",
                  promote_row: id,
                  // 关掉侧栏之后焦点回这张卡（抽屉已经收了，那颗按钮不在页面上了）
                  promote_return: card_id(id),
                  promote_source: "",
                  promote_preview: None,
                  promote_preview_error: "",
                  promote_loading: false,
                  promote_confirm: false,
                },
                focus_after_render(promote_close_id()),
              )
          }
      }
    // 选一只源：就地发 promote-preview（只读），回执之前先摆「正在读差异…」
    _ => (model, @cmd.none)
  }
}

///|
/// PromoteSourcePicked 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_promote_source_picked(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    PromoteSourcePicked(name) => 
      match find_row(model.rows, model.promote_row) {
        None => (model, @cmd.none)
        Some(row) =>
          match row.profile_name {
            None => (notice_err(model, row.name + " 的目录名读不到，没法替换配置"), @cmd.none)
            Some(target) =>
              (
                {
                  ..model,
                  promote_source: name,
                  promote_preview: None,
                  promote_preview_error: "",
                  promote_loading: true,
                  promote_confirm: false,
                },
                promote_preview_cmd(name, target, emit),
              )
          }
      }
    // 预览回执：成功就把四段差异摆出来，失败把原因留在侧栏里原位（不发全局提示）
    _ => (model, @cmd.none)
  }
}

///|
/// PromotePreviewDone 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_promote_preview_done(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    PromotePreviewDone(res) => {
      let next = match res {
        Err(err) =>
          {
            ..model,
            promote_loading: false,
            promote_preview: None,
            promote_preview_error: "这一步没发出去（" + describe(err) + "）",
          }
        Ok(text) =>
          match parse_promote_preview(text) {
            Ok(preview) =>
              {
                ..model,
                promote_loading: false,
                promote_preview: Some(preview),
                promote_preview_error: "",
              }
            Err(reason) =>
              {
                ..model,
                promote_loading: false,
                promote_preview: None,
                promote_preview_error: reason,
              }
          }
      }
      // 焦点跟着这一屏走：能应用就落在「确认替换」上，不能就落在关闭键上
      let focus = match next.promote_preview {
        Some(preview) =>
          if preview.blockers.length() == 0 && model.promote_row != "" {
            "dsh-promote-apply"
          } else {
            promote_close_id()
          }
        None => promote_close_id()
      }
      (next, focus_after_render(focus))
    }
    // 「确认替换」：只开框，不发请求（破坏性动作要先看一眼标题与正文）
    _ => (model, @cmd.none)
  }
}

///|
/// PromoteConfirmOpen 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_promote_confirm_open(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    PromoteConfirmOpen => 
      match model.promote_preview {
        Some(preview) =>
          if preview.blockers.length() > 0 {
            (model, @cmd.none)
          } else {
            ({ ..model, promote_confirm: true }, focus_after_render(promote_confirm_ok_id()))
          }
        None => (model, @cmd.none)
    _ => (model, @cmd.none)
  }
}

///|
/// PromoteConfirmCancel 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_promote_confirm_cancel(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    PromoteConfirmCancel => (
      { ..model, promote_confirm: false },
      focus_after_render("dsh-promote-apply"),
    )
    // 真的替换：body 顶层带 confirm: PROMOTE；回执走 HttpDone（成功后重读读数）
    _ => (model, @cmd.none)
  }
}

///|
/// PromoteConfirm 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_promote_confirm(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    PromoteConfirm => 
      match find_row(model.rows, model.promote_row) {
        None => (model, @cmd.none)
        Some(row) =>
          match row.profile_name {
            None => (notice_err(model, row.name + " 的目录名读不到，没法替换配置"), @cmd.none)
            Some(target) =>
              if model.promote_source == "" {
                (notice_err(model, "还没选源，替换没发出去"), @cmd.none)
              } else {
                let pairs : Array[(String, String)] = [
                  ("from", json_text_literal(model.promote_source)),
                  ("to", json_text_literal(target)),
                ]
                let (next, cmd) = send_action(
                  { ..model, promote_confirm: false },
                  model.promote_row,
                  "promote-profile",
                  target,
                  "替换配置",
                  params_of(pairs),
                  emit,
                  confirm="PROMOTE",
                )
                (next, cmd)
              }
          }
      }
    // 回去重新选源：清掉预览，卡片那一屏重新摆出来
    _ => (model, @cmd.none)
  }
}

///|
/// PromoteBack 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_promote_back(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    PromoteBack => (
      {
        ..model,
        promote_preview: None,
        promote_preview_error: "",
        promote_loading: false,
        promote_source: "",
      },
      focus_after_render(promote_close_id()),
    )
    _ => (model, @cmd.none)
  }
}

///|
/// PromoteClose 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_promote_close(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    PromoteClose => 
      if model.promote_row == "" {
        (model, @cmd.none)
      } else {
        (
          {
            ..model,
            promote_row: "",
            promote_return: "",
            promote_source: "",
            promote_preview: None,
            promote_preview_error: "",
            promote_loading: false,
            promote_confirm: false,
          },
          focus_after_render(model.promote_return),
        )
      }
    // 点整张卡：开抽屉，焦点进抽屉里的关闭键。
    // 卡是 role=button + tabindex=0，键盘也能开（Enter / 空格，见 view_overview 的 card_attrs）。
    _ => (model, @cmd.none)
  }
}

///|
/// DrawerOpen 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_drawer_open(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    DrawerOpen(id) => 
      // 拖动与点击共用同一套按下-松开，靠位移阈值分开（见 DragDown / DragMove）。
      // 拖过的那一次松手之后浏览器仍会补一个 click，那一下不许再开抽屉。
      if model.drag_suppress_click {
        ({ ..model, drag_suppress_click: false }, @cmd.none)
      } else {
        // 又把抽屉打开了：正在收的那一只当场作废（同一行会撞出两个 #dsh-drawer-close），
        // 它那条计时回来时号对不上，自己会是空枪
        //
        // 顺手把这页要用的设置读一次（只读一次，读过就不再发）：抽屉里那颗删除按钮
        // 按 safety.deleteToTrash 决定写「删除」还是「彻底删除」。
        // 打开抽屉时那份下拉菜单一定是收着的（同一时刻只有一份，换行也不带走）。
        let (next, read) = ensure_settings_read(
          { ..model, drawer_id: id, drawer_closing: "", split_menu_open: false },
          emit,
        )
        (next, @cmd.batch([read, focus_after_render(drawer_close_id())]))
      }
    // 关抽屉：点外部 / Esc / 关闭键三条路都走这里，焦点一律回触发它的那张卡 ——
    // 焦点落在被卸载的节点上会掉到 body，键盘用户于是从页首重新 Tab。
    //
    // **焦点立刻就走**，不等滑出那一段：动画期间抽屉的节点还在文档里，
    // 那 220ms 里焦点要是还留在抽屉里（关闭键），键盘用户 Tab 一下又回到面板上。
    // 节点由 DrawerClosed 在动画走完之后撤掉（那之前它挂着 data-state="closing"，
    // 样式按它放滑出那一段，并把它对指针关掉 —— 半透明的面板不该再吃点击）。
    _ => (model, @cmd.none)
  }
}

///|
/// DrawerClose 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_drawer_close(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    DrawerClose => 
      if model.drawer_id == "" {
        // 已经关了（连按两下 Esc、遮罩与键盘各来一次）：不动焦点，也不留空枪
        (model, @cmd.none)
      } else if prefers_reduced_motion() {
        // 「减少动效」：不做位移也不淡出，节点当场撤掉（样式里那条 media query 关的是
        // 开的那一半；收的这半边要连节点都不留，所以在这里判）
        (
          { ..model, drawer_id: "", drawer_closing: "", split_menu_open: false },
          focus_after_render(card_id(model.drawer_id)),
        )
      } else {
        (
          { ..model, drawer_id: "", drawer_closing: model.drawer_id, split_menu_open: false },
          @cmd.batch([
            focus_after_render(card_id(model.drawer_id)),
            // 号用的是**正在收的那一行**（model.drawer_closing 此刻还是上一拍的值）
            @cmd.delay(emit(DrawerClosed(model.drawer_id)), drawer_anim_ms),
          ]),
        )
      }
    // 「打开 Web UI」右段 chevron：开 ↔ 收。焦点跟着走 ——
    // 展开落进菜单项（键盘直接 Enter 就能走「强制启动」），收起回 chevron。
    _ => (model, @cmd.none)
  }
}

///|
/// SplitMenuToggle 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_split_menu_toggle(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    SplitMenuToggle => 
      if model.split_menu_open {
        (
          { ..model, split_menu_open: false },
          focus_after_render(split_menu_btn_id(model.drawer_id)),
        )
      } else {
        (
          { ..model, split_menu_open: true },
          focus_after_render(split_menu_item_id(model.drawer_id)),
        )
      }
    // 收菜单：点外部 / Esc / 选了菜单项都走这一条。焦点一律回 chevron ——
    // 菜单项一撤，焦点落在被卸载的节点上会掉到 body。
    _ => (model, @cmd.none)
  }
}

///|
/// SplitMenuClose 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_split_menu_close(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    SplitMenuClose => 
      if model.split_menu_open {
        (
          { ..model, split_menu_open: false },
          focus_after_render(split_menu_btn_id(model.drawer_id)),
        )
      } else {
        (model, @cmd.none)
      }
    // ── 页脚「服务端在线」灯（design/design-fixes.md §31.1）─────────
    //
    // 三拍：到点（HealthTick）→ 探测 → 落地（HealthDone）→ 排下一次。
    // 页面隐藏时不排 5 秒定时器，改成挂一个「等可见」的监听；可见之后由 HealthVisible
    // 立刻补一次 —— 后台标签页里不发请求，回到页面时一眼看到的是新结论。
    _ => (model, @cmd.none)
  }
}

///|
/// HealthTick 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_health_tick(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    HealthTick => 
      if model.health_busy {
        // 上一枪还没回来：这一拍什么都不做（别让两枪同时飞）
        (model, @cmd.none)
      } else if js_page_hidden() {
        if model.health_visible_wait {
          (model, @cmd.none)
        } else {
          ({ ..model, health_visible_wait: true }, listen_visible(emit))
        }
      } else {
        ({ ..model, health_busy: true }, health_ping_cmd(emit))
    _ => (model, @cmd.none)
  }
}

///|
/// HealthDone 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_health_done(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    HealthDone(res) => health_settled(model, res, emit)
    _ => (model, @cmd.none)
  }
}

///|
/// HealthVisible 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_health_visible(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    HealthVisible => 
      if model.health_busy {
        ({ ..model, health_visible_wait: false }, @cmd.none)
      } else {
        ({ ..model, health_busy: true, health_visible_wait: false }, health_ping_cmd(emit))
      }
    // 滑出走完了：这一枪的号还对得上才撤节点。中间又开过抽屉的话（号被清掉或换了一行）
    // 什么都不做 —— 不然会把刚开的那一只撤下去。
    _ => (model, @cmd.none)
  }
}

///|
/// DrawerClosed 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_drawer_closed(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    DrawerClosed(id) => 
      if model.drawer_closing == id {
        ({ ..model, drawer_closing: "" }, @cmd.none)
      } else {
        (model, @cmd.none)
      }

    // ── 拖动排序（第十轮）──────────────────────────────────
    //
    // 一次拖动分四拍：按下记起点 → 位移过阈值才算拖动 → 松开落位并写回 → 回执。
    // 「单击开抽屉」与「拖动换位」共用同一套按下-松开，靠**位移阈值**分开：
    // 没过阈值的那一次顺序一个字节都不动，只是把抽屉打开（随后那个 click 走 DrawerOpen）。
    _ => (model, @cmd.none)
  }
}

///|
/// DragDown 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_drag_down(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    DragDown(id, x, y) => 
      // 窄屏（单列那一档）不启动拖动：那一档里纵向拖动与页面滚动落在同一个手势上，
      // 拖一次条目页面跟着滚。断点与样式里那条 media query 是同一个数。
      if js_viewport_width() < drag_min_viewport_width {
        (model, @cmd.none)
      } else {
        (
          {
            ..model,
            drag_id: id,
            drag_start_x: x,
            drag_start_y: y,
            drag_active: false,
            drag_group: "",
            drag_from: -1,
            drag_at: "",
            drag_at_index: -1,
            drag_ghost: false,
            drag_ghost_x: x,
            drag_ghost_y: y,
            drag_ghost_w: 0.0,
            drag_ghost_h: 0.0,
            drag_key_dir: 0,
            // 上一次拖动留下的抑制标记在这里清掉：留着会吃掉这一次真正的点击
            drag_suppress_click: false,
          },
          @cmd.none,
        )
    _ => (model, @cmd.none)
  }
}

///|
/// DragMove 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_drag_move(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    DragMove(x, y, buttons) => 
      if model.drag_id == "" {
        // 没按下过：划过卡片也会冒泡到这里，什么都不做
        (model, @cmd.none)
      } else if buttons == 0 {
        // 没有任何键按着：这一次的抬起没收到（松手在页面之外，抬到窗口外面那一下不送到页面），
        // 当作作废。**顺序不动** —— 没提交过的东西没有什么要回滚的。
        (
          reset_drag(model),
          @cmd.batch([reorder_after_render(), clear_cells_after_render()]),
        )
      } else if js_drop_scrolled() == 1 {
        // 这一次拖动期间页面滚过：冻下来的那份坐标是视口坐标，已经在说别处的格子了。
        // 拿它算落点会得到一个**看着对、落错格**的位置，所以当场作废（顺序一个字节不动）。
        (
          reset_drag(model),
          // 摆过的格子要撤（见 clear_cells_after_render）：不撤的话这一组会停在
          // 拖动时那个形状上，而这一次已经作废了。
          @cmd.batch([reorder_after_render(), clear_cells_after_render()]),
        )
      } else if !model.drag_active &&
        !drag_past_threshold(model.drag_start_x, model.drag_start_y, x, y) {
        // 还没过阈值，还算不上拖动。**状态一个都不改** ——
        // 在这里就把 active 置上的话，一次轻轻的点击会变成一次换位。
        (model, @cmd.none)
      } else {
        // 刚过阈值的那一拍：把这一组的格子坐标冻下来。
        // **必须在这一拍冻**（不是在按下那一拍）：库没有补上拖动态的那一次 DOM 变更，
        // 所以此刻量到的还是按下前的老布局，正好是落点判定该用的那一份；
        // 再晚一拍，占位块已经插进去、条目已经让位，量到的是挪开后的位置。
        if !model.drag_active {
          ignore(js_drop_freeze(model.drag_id))
        }
        // 指针底下那一格：卡片 id 只用来查组，落点就是那个格子序号
        let (_, group, cell) = drop_target_of(x, y)
        let size = lift_sizes_of(model.drag_id)
        // 只有落在**同一组**里才算落点：两组是语义，跨组拖动不合并两组，
        // 画一个占位块在那儿等于答应了做不到的事。
        // 「指针进到另一组」在 dom.mbt 那一层就已经返回空（那一组的盒子冻在 others 里）；
        // 这里再按组名核一次，是同一件事的第二道 —— 那边管「指针在哪儿的盒子」，
        // 这边管「这个组名是不是被拖那一条的组」。
        let same_group = group != "" && group == group_of_row_id(model, model.drag_id)
        let ids = if same_group { current_group_ids(model, group) } else { [] }
        let n = ids.length()
        // 格子序号：**预览与落位用的是这一个数**（见 state.mbt 的 drop_cell）。
        let k = if same_group && cell >= 0 && n > 1 {
          drop_cell(n, cell)
        } else {
          -1
        }
        (
          {
            ..model,
            drag_active: true,
            drag_group: if same_group { group } else { "" },
            drag_from: if same_group { index_of_row(ids, model.drag_id) } else { -1 },
            drag_at: if k >= 0 { anchor_at(ids, k) } else { "" },
            drag_at_index: k,
            drag_ghost: true,
            // 虚影**以指针为中心**：落点按指针在哪一格算，虚影也压在指针上，
            // 两者说的是同一处，不会一个偏上半格、一个偏下半格。
            drag_ghost_x: x,
            drag_ghost_y: y,
            drag_ghost_w: size.0,
            drag_ghost_h: size.1,
          },
          @cmd.batch([
            @cmd.custom_cmd(fn(_scheduler) { js_drag_ghost_move(x, y) }, kind=@cmd.after_render),
            // 摆格子与让位那一段都排在这一拍之后：DOM 刚补完，量到的正是新格子。
            // 顺序不能反 —— 先摆格子（位置变了），再让 FLIP 把这段变化演出来。
            preview_cells_after_render(group, model.drag_id, k),
            reorder_after_render(),
          ]),
        )
    _ => (model, @cmd.none)
  }
}

///|
/// DragUp 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_drag_up(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    DragUp => 
      if model.drag_id == "" {
        (model, @cmd.none)
      } else if !model.drag_active {
        // 按下了但没拖动：起点清掉就完事，抽屉由随后的 click 打开。
        // 这一档本来就什么都没摆过，格子那一下是空枪（撤一次是幂等的）。
        (reset_drag(model), clear_cells_after_render())
      } else {
        let k = model.drag_at_index
        let moved = moved_group_ids(model, model.drag_id, k)
        let dragged = model.drag_id
        let cleared = {
          ..reset_drag(model),
          // 拖动之后的这一次 click 不许再开抽屉（下一次按下会把它清掉）
          drag_suppress_click: true,
        }
        match moved {
          // 横向出栅格 / 跨组 / 组里只有这一条：这一次拖动作废，顺序不动，也不发请求
          None => (cleared, @cmd.batch([reorder_after_render(), clear_cells_after_render()]))
          // 落点就是原位（指针在被拖的那张自己身上）：顺序逐格没变，同样不发请求
          Some(ids) =>
            if same_order(current_group_ids(model, group_of_row_id(model, dragged)), ids) {
              (cleared, @cmd.batch([reorder_after_render(), clear_cells_after_render()]))
            } else {
              commit_order(cleared, dragged, ids, emit)
            }
        }
      }
    // 指针被取消（触控被打断等）：这一次拖动作废。**不回滚也不提交** ——
    // 顺序还没动过，没有什么要回滚的。
    _ => (model, @cmd.none)
  }
}

///|
/// DragCancel 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_drag_cancel(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    DragCancel => 
      (
        reset_drag(model),
        @cmd.batch([reorder_after_render(), clear_cells_after_render()]),
      )
    // 键盘换位：Ctrl+↑ / Ctrl+↓。与拖动走**同一条**提交路径，也走**同一个落点算法**：
    // 第一拍只把占位块摆出来（与拖动时那个块是同一个块），第二拍才真的换。
    // 这样键盘用户看到的也是「要落到哪儿」，而不是按下去才发现跳了一格。
    _ => (model, @cmd.none)
  }
}

///|
/// ReorderKey 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_reorder_key(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    ReorderKey(id, dir) => {
      let group = group_of_row_id(model, id)
      let ids = current_group_ids(model, group)
      let at = index_of_row(ids, id)
      let to = at + dir
      if at < 0 || to < 0 || to >= ids.length() {
        // 已经在头 / 尾：没有可换的位置，一个节点都不动。
        // **上一次按键留下的预览也要收掉** —— 不然它会一直挂在那儿，
        // 而这一次按下的方向并没有可去的地方。
        (
          { ..reset_drag(model), drag_key_dir: 0 },
          clear_cells_after_render(),
        )
      } else {
        // 目标格就是 to：卡槽语义下「换到第 to 格」= 被拖的那一条落在第 to 格。
        // 与指针那条路同一个 drop_cell，预览与落位因此不会分叉。
        let k = drop_cell(ids.length(), to)
        (
          {
            ..model,
            drag_id: id,
            drag_active: true,
            drag_ghost: false,
            drag_group: group,
            drag_from: at,
            drag_at: anchor_at(ids, k),
            drag_at_index: k,
            drag_key_dir: dir,
          },
          @cmd.batch([
            // 与指针那条路**同一套摆格子**：键盘用户看到的也是「将要落到哪一格」
            preview_cells_after_render(group, id, k),
            // 预览摆够了才落位（这两拍就是键盘换位的「先看见、再落下」）
            @cmd.delay(emit(ReorderCommit(dir)), reorder_preview_ms),
          ]),
        )
      }
    }
    // 键盘换位第二拍：预览摆够了，落位。
    // 号（方向）对不上就作废 —— 这中间使用者可能又按了别的方向，那时预览已经跟着换了，
    // 这一枪还是按它出发时的方向落，就会落在一个**看不到**的格子上（预览与结果分叉）。
    _ => (model, @cmd.none)
  }
}

///|
/// ReorderCommit 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_reorder_commit(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    ReorderCommit(dir) => 
      if model.drag_key_dir != dir || model.drag_id == "" || model.drag_at_index < 0 {
        (model, @cmd.none)
      } else {
        let dragged = model.drag_id
        let k = model.drag_at_index
        // 落位这一拍**先把「等着的那一步」清掉**（drag_key_dir 归 0）：
        // 连着按两次方向键时，第一拍留下的那条计时回来会看到号对不上，自己作废，
        // 不会多换一次位。
        let settled = { ..reset_drag(model), drag_key_dir: 0 }
        match moved_group_ids(model, dragged, k) {
          None => (settled, clear_cells_after_render())
          Some(ids) => commit_order(settled, dragged, ids, emit)
    _ => (model, @cmd.none)
  }
}

///|
/// OrderDone 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_order_done(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    OrderDone(res) => {
      let (ok, text) = interpret_http(res)
      if ok {
        // 成功：顺序在松手那一刻就已经就地生效了，这里只是报一句。
        //
        // 正文只留「顺序已保存」：后端那句话说的是「顺序表已写入 <落盘路径>（N 条）」——
        // 「顺序表」是内部的叫法，落盘路径也不是使用者要读的东西（第六轮契约第二节：
        // 细节收进悬停，正文说人话）。路径与条数一个字都没丢，它们在悬停里。
        (
          notice_ok({ ..model, order_before: [] }, "顺序已保存", text),
          @cmd.none,
        )
      } else {
        // 失败：**回滚到提交前那一份**。停在「看着是新的、其实没存下」比不做还糟 ——
        // 下一次刷新列表会跳回原样，而使用者不知道自己刚才拖的那一下去哪了。
        (
          notice_err({ ..model, order: model.order_before, order_before: [] },
            "顺序没保存：" + text),
          @cmd.none,
        )
      }
    }

    // 启动的展示下限到了：等回执一起收尾（收尾里不伪造成「运行中」——
    // 真的起来了的那张卡由重读 instances 给出）
    _ => (model, @cmd.none)
  }
}

///|
/// StartTick 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_start_tick(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    StartTick(id) => 
      if model.act_pending == id {
        finish_start({ ..model, act_tick: true }, emit)
      } else {
        (model, @cmd.none)
      }
    // 带令牌的地址还没到手：再重读一轮读数（有界，见 start_tab_max_tries）。
    // 地址到了就填、到不了就认输关标页 —— 两条路都在 fill_start_tab 里。
    _ => (model, @cmd.none)
  }
}

///|
/// StartTabRetry 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_start_tab_retry(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    StartTabRetry => refresh_readings(model, emit)
    // 抽屉里「安装缺的包（N）」：先开确认框（写 node_modules 是真动作，§39.1）。
    // 焦点进「安装」键；关掉之后回那颗按钮（见 RepairCancel 与原位按钮的 id）。
    _ => (model, @cmd.none)
  }
}

///|
/// RepairOpen 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_repair_open(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    RepairOpen(id~, return_id~) => 
      match find_row(model.rows, id) {
        None => (model, @cmd.none)
        Some(_) =>
          (
            { ..model, repair_confirm_id: id, repair_confirm_return: return_id },
            focus_after_render(repair_dialog_ok_id()),
          )
      }
    // 命令行型 profile 的启动说明（§42）：只开一句说明，不发任何请求。
    _ => (model, @cmd.none)
  }
}

///|
/// CliHelpOpen 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_cli_help_open(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    CliHelpOpen(id) => ({ ..model, cli_help_id: id }, focus_after_render("dsh-cli-help-ok"))
    _ => (model, @cmd.none)
  }
}

///|
/// CliHelpClose 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_cli_help_close(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    CliHelpClose => ({ ..model, cli_help_id: "" }, @cmd.none)
    _ => (model, @cmd.none)
  }
}

///|
/// RepairCancel 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_repair_cancel(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    RepairCancel => 
      if model.repair_confirm_id == "" {
        (model, @cmd.none)
      } else {
        let back = model.repair_confirm_return
        (
          { ..model, repair_confirm_id: "", repair_confirm_return: "" },
          if back == "" { @cmd.none } else { focus_after_render(back) },
        )
      }
    // 确认：发 repair-packages（profile + home）。这一笔走 send_action：
    // 行置忙 → 抽屉里其余写动作跟着禁用，提示条清空等回执。
    _ => (model, @cmd.none)
  }
}

///|
/// RepairConfirm 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_repair_confirm(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    RepairConfirm => {
      let id = model.repair_confirm_id
      match find_row(model.rows, id) {
        None => (model, @cmd.none)
        Some(row) => {
          let name = row.name
          let params = match (row.profile_name, row.repair_home) {
            (Some(profile), home) =>
              if profile == "" || home == "" {
                ""
              } else {
                params_of([
                  ("profile", json_text_literal(profile)),
                  ("home", json_text_literal(home)),
                ])
              }
            _ => ""
          }
          let (next, cmd) = send_action(
            { ..model, repair_confirm_id: "", repair_confirm_return: "" },
            id,
            "repair-packages",
            name,
            "安装缺的包",
            params,
            emit,
          )
          (
            { ..next, repair_id: id },
            @cmd.batch([cmd, focus_after_render(drawer_repair_id())]),
          )
        }
      }
    }
    // 顶栏「通知」（§36）：开侧栏看历史。未读角标在这一拍清零 ——
    // 「看过了」就是打开过，不另设已读按钮。焦点进侧栏的关闭键（与抽屉那一套一致）。
    _ => (model, @cmd.none)
  }
}

///|
/// NoticePanelOpen 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_notice_panel_open(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    NoticePanelOpen => 
      if model.notice_panel {
        (model, @cmd.none)
      } else {
        (
          { ..model, notice_panel: true, notice_unread: 0 },
          focus_after_render(notice_panel_close_id()),
        )
      }
    // 关闭键 / 遮罩 / Esc 三条路都走这里，焦点一律回顶栏那颗铃铛 ——
    // 焦点落在被卸载的节点上会掉到 body，键盘用户于是从页首重新 Tab。
    _ => (model, @cmd.none)
  }
}

///|
/// NoticePanelClose 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_notice_panel_close(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    NoticePanelClose => 
      if model.notice_panel {
        ({ ..model, notice_panel: false }, focus_after_render(notice_bell_id()))
      } else {
        (model, @cmd.none)
      }
    // 失败提示条里那颗「查看日志」（§32.1）：跳到「控制台审计」那一份日志、读一次、
    // 落到底部，焦点送进日志区。那里最后一条就是这次失败，message 是完整原文。
    //
    // 注意来源是 actions 不是 audit：日志页原来那个「审计日志」指的是 linxi-guard 的
    // 守卫审计（~/.dsh/linxi-guard-audit.jsonl），与控制台自己的 audit.jsonl 是两个文件。
    // 失败原文在后者的 message 里，所以为它单开了一条来源（后端 logs 的 actions）。
    // 顺带把抽屉收掉：跳到别的页还挂着一个详情抽屉，那属于「上一步没走完」。
    _ => (model, @cmd.none)
  }
}

///|
/// NoticeOpenLogs 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_notice_open_logs(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    NoticeOpenLogs => {
      let (next, read) = start_logs(
        {
          ..model,
          page: Logs,
          drawer_id: "",
          // 点了「查看日志」= 这条提示已经处理掉了：常驻的失败提示条不该跟着用户
          // 跳到日志页、盖在他要读的那几行上。清掉当前这条，历史里仍留着（§36）。
          notice: None,
          notice_url: None,
          notice_url_notice: "",
          log_user_picked: true,
          // 日志区要等读数回来才存在：焦点那一步只能等落地再做（见 LogsText）
          log_focus_pending: true,
        },
        "actions",
        emit,
      )
      (
        next,
        // 地址写路径写法 /logs/actions（§32.2）：刷新、分享、后退回来都落回同一个来源。
        @cmd.batch([read, push_route("/logs/actions")]),
      )
    }
    // 提示条里那颗「打开 Web UI」：用户再点一下 = 新手势，一定不被弹窗拦截器吃掉。
    // 这是自动开标页被拦时的兜底入口（方案 B），地址是启动时读到的同一条 webUrl。
    _ => (model, @cmd.none)
  }
}

///|
/// NoticeOpenUi 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_notice_open_ui(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    NoticeOpenUi => 
      match model.notice_url {
        None => (model, @cmd.none)
        Some(url) => {
          let (ok, tail) = open_outcome_text(js_open_url(url))
          let text = "Web UI " + tail + "。" + url
          (
            { ..notice_put(model, ok, text, ""), notice_url_notice: text },
            @cmd.none,
          )
    _ => (model, @cmd.none)
  }
}

///|
/// RestartTick 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_restart_tick(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    RestartTick => ({ ..model, restarting: "" }, @cmd.none)
    _ => (model, @cmd.none)
  }
}

///|
/// RenameInput 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_rename_input(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    RenameInput(text) => ({ ..model, rename_draft: text }, @cmd.none)
    // 改名不再是改一个显示字符串：它 POST rename-profile，改的是磁盘上的目录名。
    // 对话框照旧先关（语义没变），结果由提示条给出。
    _ => (model, @cmd.none)
  }
}

///|
/// RenameConfirm 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_rename_confirm(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    RenameConfirm => {
      let draft = model.rename_draft.trim().to_owned()
      let id = model.rename_id
      let return_id = model.rename_return
      if draft.length() == 0 {
        (model, @cmd.none)
      } else {
        let old = row_name(model, id)
        let params = match find_row(model.rows, id) {
          None => ""
          Some(row) =>
            match row.profile_name {
              None => ""
              Some(name) =>
                params_of([
                  ("profile", json_text_literal(name)),
                  ("newName", json_text_literal(draft)),
                ])
            }
        }
        let cleared = { ..model, rename_id: "", rename_draft: "" }
        let (next, cmd) = send_action(
          cleared,
          id,
          "rename-profile",
          old,
          "重命名",
          params,
          emit,
        )
        (next, @cmd.batch([cmd, focus_after_render(return_id)]))
    _ => (model, @cmd.none)
  }
}

///|
/// RenameCancel 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_rename_cancel(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    RenameCancel => (
      { ..model, rename_id: "", rename_draft: "" },
      focus_after_render(model.rename_return),
    )
    // 编辑备注：与重命名同一套（预填、Esc 取消、关闭后焦点回触发元素）。
    // 焦点落在备注框、光标推到文末 —— 这里是接着改，不是整段覆盖。
    // 与重命名 / 删除同一条口径（§30.1）：抽屉留着，关框之后焦点回抽屉里那颗「备注」。
    _ => (model, @cmd.none)
  }
}

///|
/// NoteOpen 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_note_open(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    NoteOpen(id) => (
      {
        ..model,
        note_open: id,
        note_draft: row_note(model, id),
        note_return: drawer_note_id(),
        note_error: "",
      },
      focus_end_after_render("dsh-note-input"),
    )
    _ => (model, @cmd.none)
  }
}

///|
/// NoteInput 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_note_input(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    NoteInput(text) => ({ ..model, note_draft: text, note_error: "" }, @cmd.none)
    // 保存失败**不关框**：后端给的原因（bad-params / io-error / not-authorized…）写在框里，
    // 用户改一改就能再存一次。关掉的话那句原因就成了一闪而过的提示条。
    _ => (model, @cmd.none)
  }
}

///|
/// NoteConfirm 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_note_confirm(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    NoteConfirm => 
      match find_row(model.rows, model.note_open) {
        // 框开着却找不到那一行（列表刚被重建掉）：把框收掉，不留一个悬空的编辑框
        None => (
          { ..model, note_open: "", note_draft: "", note_error: "", note_return: "" },
          @cmd.none,
        )
        Some(row) => {
          let pairs = note_pairs(row, model.note_draft)
          if pairs.length() == 0 {
            (
              {
                ..model,
                note_error: "这一行的读数里没有 profile 目录名，保存不了。没有目标就什么都没做",
              },
              @cmd.none,
            )
          } else {
            // 这一行不置忙：备注保存时卡片本身还能用，忙碌态只锁保存键
            (
              notice_clear({ ..model, note_saving: row.id, note_error: "" }),
              action_cmd(
                row.id,
                "set-profile-note",
                row.name,
                "保存备注",
                action_body("set-profile-note", params_of(pairs)),
                emit,
              ),
            )
    _ => (model, @cmd.none)
  }
}

///|
/// NoteCancel 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_note_cancel(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    NoteCancel => {
      // 保存中不许关：请求已经出去了，关掉框会让人以为没存上（回执到了会把框关掉）
      if model.note_saving != "" {
        (model, @cmd.none)
      } else {
        let return_id = model.note_return
        (
          { ..model, note_open: "", note_draft: "", note_error: "", note_return: "" },
          focus_after_render(return_id),
        )
      }
    }
    // ── 新建实例框（design/design-fixes.md §19.1）─────────────
    // 开框：清掉上一次的错与草稿。没有可用源时「从基础实例开始」默认勾上（§21.4）：
    // 这时它是唯一能走的路，名字预填 base-NN、焦点直接进名字格。
    // 有可用源就照旧把焦点落在第一张可点的源卡上；读数还没落地时卡都点不了，落在复选框上。
    _ => (model, @cmd.none)
  }
}

///|
/// NewInstanceOpen 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_new_instance_open(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    NewInstanceOpen => {
      let first = new_instance_first_usable(model)
      let default_base = new_instance_no_usable_source(model)
      (
        {
          ..model,
          new_open: true,
          new_source: "",
          new_base: default_base,
          new_name_draft: if default_base { new_instance_base_name(model) } else { "" },
          new_name_dirty: false,
          new_error: "",
          new_busy: false,
        },
        if default_base {
          // 勾上了：名字格已经预填 base-NN，焦点与光标送进去，接着打字就是改名
          focus_select_after_render(new_instance_name_id())
        } else if first == "" {
          // 读数还没到、或一只可用的都没有：焦点落在复选框上 ——
          // 它是这一刻框里唯一能点的东西（「创建」还锁着，「取消」谁都知道在哪儿）。
          focus_after_render(new_instance_base_id())
        } else {
          focus_after_render(new_instance_card_id(first))
        },
      )
    }
    // 取消 / Esc / 点遮罩：框关掉，草稿与错误一起清掉，焦点回页头那颗按钮。
    // 创建中不许关：请求已经出去了，关掉框会让人以为没创建（回执照样会把它关掉）。
    _ => (model, @cmd.none)
  }
}

///|
/// NewInstanceClose 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_new_instance_close(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    NewInstanceClose => 
      if model.new_busy {
        (model, @cmd.none)
      } else {
        (
          {
            ..model,
            new_open: false,
            new_source: "",
            new_base: false,
            new_name_draft: "",
            new_name_dirty: false,
            new_error: "",
          },
          focus_after_render(new_instance_btn_id()),
        )
      }
    // 选中一只源：名字默认填 <源>-dev。已经亲手改过名字的（不等于上一个默认值）就不覆盖，
    // 换源不该把人家刚打的字抹掉。
    _ => (model, @cmd.none)
  }
}

///|
/// NewInstanceStatePicked 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_new_instance_state_picked(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    NewInstanceStatePicked(name) => {
      let draft = model.new_name_draft.trim().to_owned()
      let keep = draft != "" &&
        !(model.new_source != "" && draft == model.new_source + "-dev")
      let next = {
        ..model,
        new_source: name,
        // 选了具体的源就走派生：从基础模板那一档退出来
        new_base: false,
        new_name_draft: if keep { model.new_name_draft } else { name + "-dev" },
        new_error: "",
      }
      // 焦点与光标送进名字那一格，默认那段选上：接着打字就是改名
      (next, focus_select_after_render(new_instance_name_id()))
    }
    // 名字框的输入事件：脏标记置位（§21）。勾上复选框时靠它判断「用户已经输入过任何字符」——
    // 预填不走这条消息，所以预填不会把标记点亮。
    _ => (model, @cmd.none)
  }
}

///|
/// NewInstanceNameInput 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_new_instance_name_input(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    NewInstanceNameInput(text) => (
      { ..model, new_name_draft: text, new_name_dirty: true, new_error: "" },
      @cmd.none,
    )
    // 创建：走既有 fork-profile（新副本默认隔离）。名字按输入框的原话发，
    // 空名字不带 newName —— 后端自己会按 <源>-dev 起一个。
    _ => (model, @cmd.none)
  }
}

///|
/// NewInstanceConfirm 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_new_instance_confirm(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    NewInstanceConfirm => {
      let source = model.new_source
      let base = model.new_base
      let draft = model.new_name_draft.trim().to_owned()
      if (!base && source == "") || draft == "" || model.new_busy {
        (
          {
            ..model,
            new_error: if !base && source == "" {
              "先选一只源配置，或者勾上「从基础实例开始」"
            } else {
              "名字不能为空"
            },
          },
          @cmd.none,
        )
      } else {
        (
          { ..model, new_busy: true, new_error: "" },
          if base {
            // 源是基础模板：不派生，直接用 dsh 自带的基础模板新建一份
            base_profile_cmd(draft, emit)
          } else {
            new_instance_cmd(source, draft, emit)
          },
        )
      }
    }
    // 勾上「从基础实例开始」（§21）：源换成基础模板、选中的源卡让位（卡片自己由视图锁上）、
    // 名字**只在它现在是空的、而且用户一个字都没输入过**时预填 base-<两位序号>；
    // 焦点进名字格。勾掉：卡片恢复可选，名字框一个字都不动 —— 两条都不看文本框的内容去还原 / 清空。
    _ => (model, @cmd.none)
  }
}

///|
/// NewInstanceBaseToggled 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_new_instance_base_toggled(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    NewInstanceBaseToggled(on) => 
      if model.new_busy {
        (model, @cmd.none)
      } else if on {
        let prefill = !model.new_name_dirty && model.new_name_draft == ""
        let draft = if prefill {
          new_instance_base_name(model)
        } else {
          model.new_name_draft
        }
        (
          {
            ..model,
            new_source: "",
            new_base: true,
            new_name_draft: draft,
            new_error: "",
          },
          // 刚预填的那一段整段选上（接着打字就是改名）；用户自己的字只落焦点，不动选区
          if prefill {
            focus_select_after_render(new_instance_name_id())
          } else {
            focus_after_render(new_instance_name_id())
          },
        )
      } else {
        ({ ..model, new_base: false, new_error: "" }, @cmd.none)
    _ => (model, @cmd.none)
  }
}

///|
/// NewInstanceDone 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_new_instance_done(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    NewInstanceDone(res) => {
      let (next, cmd) = new_instance_settled(model, res, emit)
      // 失败时把焦点拉回名字那一格：要改的就是那里
      if next.new_error != "" {
        (next, @cmd.batch([cmd, focus_select_after_render(new_instance_name_id())]))
      } else {
        (next, cmd)
    _ => (model, @cmd.none)
  }
}

///|
/// NewInstanceBaseDone 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_new_instance_base_done(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    NewInstanceBaseDone(res) => {
      let (next, cmd) = base_profile_settled(model, res, emit)
      // 失败同样不关框、焦点回名字格（同名 conflict 就是在那儿改）
      if next.new_error != "" {
        (next, @cmd.batch([cmd, focus_select_after_render(new_instance_name_id())]))
      } else {
        (next, cmd)
      }
    }

    // 删除也是真实动作：POST delete-profile。删掉的行由重读 profiles 之后消失，
    // 不在这里先手动抹掉 —— 后端失败时列表不该少一行。
    _ => (model, @cmd.none)
  }
}

///|
/// DeleteConfirm 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_delete_confirm(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    DeleteConfirm => {
      let target = model.confirm_id
      let return_id = model.confirm_return
      // 动词照记下来的模式说：彻底删除与进回收站是两件事，回执里说错就是骗人
      let verb = if model.confirm_hard { "彻底删除" } else { "删除" }
      let (next, cmd) = send_action(
        { ..model, confirm_id: "" },
        target,
        "delete-profile",
        row_name(model, target),
        verb,
        params_of(delete_pairs(model, target)),
        emit,
        confirm=delete_confirm_of(model),
      )
      (next, @cmd.batch([cmd, focus_after_render(return_id)]))
    _ => (model, @cmd.none)
  }
}

///|
/// DeleteCancel 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_delete_cancel(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    DeleteCancel => (
      { ..model, confirm_id: "" },
      focus_after_render(model.confirm_return),
    )
    // ── 回收站 ─────────────────────────────────────────────
    // 恢复：把回收站里那一份移回 profile 目录。成功 / 失败都重读读数并出提示条，
    // 失败尤其要显示后端给的原因（已经有同名 profile 时是 conflict）。
    _ => (model, @cmd.none)
  }
}

///|
/// TrashRestore 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_trash_restore(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    TrashRestore(dir) => {
      let params = params_of([("dir", json_text_literal(dir))])
      send_action(
        model,
        trash_row_id(dir),
        "restore-from-trash",
        trash_profile_of(model, dir),
        "恢复",
        params,
        emit,
      )
    }
    // 真删之前先开确认框（走既有那套 dialog()），焦点落在确认键上
    _ => (model, @cmd.none)
  }
}

///|
/// TrashPurgeOpen 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_trash_purge_open(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    TrashPurgeOpen(dir, return_id) => (
      { ..model, trash_purge_dir: dir, trash_purge_return: return_id },
      focus_after_render("dsh-purge-ok"),
    )
    // 彻底删除：confirm 走顶层（缺了后端给 bad-params），与硬删同一风险等级
    _ => (model, @cmd.none)
  }
}

///|
/// TrashPurgeConfirm 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_trash_purge_confirm(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    TrashPurgeConfirm => {
      let dir = model.trash_purge_dir
      let return_id = model.trash_purge_return
      if dir == "" {
        (model, @cmd.none)
      } else {
        let params = params_of([("dir", json_text_literal(dir))])
        let (next, cmd) = send_action(
          { ..model, trash_purge_dir: "" },
          trash_row_id(dir),
          "purge-trash-item",
          trash_profile_of(model, dir),
          "彻底删除",
          params,
          emit,
          confirm="PURGE",
        )
        (next, @cmd.batch([cmd, focus_after_render(return_id)]))
    _ => (model, @cmd.none)
  }
}

///|
/// TrashPurgeCancel 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_trash_purge_cancel(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    TrashPurgeCancel => (
      { ..model, trash_purge_dir: "" },
      focus_after_render(model.trash_purge_return),
    )
    // ── 维护页（作业台） ──
    // 打开版本侧栏（§12.1）：清空搜索框、焦点进搜索框，并再读一次缓存。
    // 那一条接口现在只读后端进程内的缓存（秒回），所以「每次打开都读」不再是一笔等待。
    // 过滤与排序**不重置**：它们是使用者上一次挑的读法，关掉再开回来还该是那一套。
    _ => (model, @cmd.none)
  }
}

///|
/// VersionSidebarOpen 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_version_sidebar_open(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    VersionSidebarOpen => (
      {
        ..model,
        version_sidebar: true,
        version_query: "",
        releases_ticks: 0,
        releases_poll_pending: false,
      },
      @cmd.batch([load_releases(emit), focus_after_render(version_search_id())]),
    )
    _ => (model, @cmd.none)
  }
}

///|
/// VersionSidebarClose 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_version_sidebar_close(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    VersionSidebarClose => 
      if !model.version_sidebar {
        (model, @cmd.none)
      } else {
        ({ ..model, version_sidebar: false, version_query: "" }, focus_after_render(version_choose_id()))
    _ => (model, @cmd.none)
  }
}

///|
/// VersionQueryInput 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_version_query_input(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    VersionQueryInput(text) => ({ ..model, version_query: text }, @cmd.none)
    // 过滤 chip：all = 全部（清空选择）；其余是开关，多选之间「或」。
    // 不认识的值一律不动模型 —— 界面只发那四个键，多一个也不该把过滤状态弄成空的。
    _ => (model, @cmd.none)
  }
}

///|
/// VersionFilterToggle 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_version_filter_toggle(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    VersionFilterToggle(key) => {
      let current = model.version_filters
      let next = if key == "all" {
        []
      } else if !version_filter_known(key) {
        current
      } else if current.contains(key) {
        current.filter(fn(item) { item != key })
      } else {
        let out = current.copy()
        out.push(key)
        out
      }
      ({ ..model, version_filters: next }, @cmd.none)
    }
    // 排序档：只认三档，认不出的保持原样
    _ => (model, @cmd.none)
  }
}

///|
/// VersionSortPicked 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_version_sort_picked(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    VersionSortPicked(key) => 
      if version_sort_known(key) {
        ({ ..model, version_sort: key }, @cmd.none)
      } else {
        (model, @cmd.none)
      }
    // 选中：回填表单并关闭侧栏，焦点回「选择版本」那颗按钮
    _ => (model, @cmd.none)
  }
}

///|
/// JobVersionPicked 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_job_version_picked(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    JobVersionPicked(version) => (
      { ..model, job_version: version, version_sidebar: false, version_query: "" },
      focus_after_render(version_choose_id()),
    )
    // 打开配置侧栏：焦点落在第一张可点的卡上（一张都没有时落在关闭键上）
    _ => (model, @cmd.none)
  }
}

///|
/// ProfileSidebarOpen 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_profile_sidebar_open(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    ProfileSidebarOpen => {
      let first = job_profile_first_usable(model)
      let focus = if first == "" {
        profile_sidebar_close_id()
      } else {
        job_profile_card_id(first)
      }
      ({ ..model, profile_sidebar: true }, focus_after_render(focus))
    _ => (model, @cmd.none)
  }
}

///|
/// ProfileSidebarClose 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_profile_sidebar_close(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    ProfileSidebarClose => 
      if !model.profile_sidebar {
        (model, @cmd.none)
      } else {
        ({ ..model, profile_sidebar: false }, focus_after_render(profile_choose_id()))
      }
    // 点一张可用的卡：回填并关闭侧栏，焦点回「选择配置」那颗按钮
    _ => (model, @cmd.none)
  }
}

///|
/// JobProfilePicked 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_job_profile_picked(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    JobProfilePicked(name) => (
      { ..model, job_profile: name, profile_sidebar: false },
      focus_after_render(profile_choose_id()),
    )
    // 空态那颗「开始一条作业」：先滚到表单，再把焦点送进「当前版本」那一格。
    // 两步都是 after_render —— 顺序由 batch 保证：先滚（视口到位），后聚焦
    // （聚焦也会自己滚一次，那时已经离得很近了，不会再跳）。
    _ => (model, @cmd.none)
  }
}

///|
/// JobStartFocus 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_job_start_focus(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    JobStartFocus => (
      model,
      @cmd.batch([
        scroll_into_view_after_render(version_choose_id()),
        focus_after_render(version_choose_id()),
      ]),
    )
    // 总览空态那颗「刷新读数」：与写动作成功之后同一条路（两份读数都重读）。
    // 特意不弹提示条：这是个「再读一遍」的动作，结果本来就会落在列表或空态上。
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
/// ReleasesText 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_releases_text(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    ReleasesText(res) => {
      // 三个源全没答上来**不是失败**：那是读数里的一个事实，照实摆在页面上（spec §1.3）。
      // 真正的失败只有一种：这一条接口没读到（网络、后端没这个路由）。
      let next = match res {
        Ok(text) =>
          match parse_releases(text) {
            Ok(facts) =>
              { ..model, releases: Some(facts), releases_error: "", releases_loading: false }
            Err(reason) =>
              { ..model, releases: None, releases_error: reason, releases_loading: false }
          }
        Err(err) =>
          {
            ..model,
            releases: None,
            releases_error: "读不到版本来源（" + describe(err) + "）",
            releases_loading: false,
          }
      }
      // 后端那条 GET 只回缓存：读到「还在拉」就隔一拍再问一次，结果才能落到页面上。
      // **同一时刻只排一个定时器**（releases_poll_pending）：进页面与打开侧栏会各发一次
      // GET，两个回执各排一个的话补问会翻倍，几拍就把上限吃完。
      // 上限 releases_poll_cap 拍（≈8 秒，长过三个源最坏 6 秒），不会变成永动机。
      if releases_still_loading(next) && !next.releases_poll_pending &&
        next.releases_ticks < releases_poll_cap && next.page is Maintenance {
        (
          {
            ..next,
            releases_ticks: next.releases_ticks + 1,
            releases_poll_pending: true,
          },
          @cmd.delay(emit(ReleasesTick), releases_poll_ms),
        )
      } else {
        (next, @cmd.none)
      }
    }
    // 补问一次：还在拉就再读一遍缓存（这一条请求不花网络时间）。
    // 定时器在这时候才放开，回执回来再决定排不排下一拍 —— 一拍一个，不叠加。
    _ => (model, @cmd.none)
  }
}

///|
/// ReleasesTick 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_releases_tick(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    ReleasesTick => 
      if releases_still_loading(model) && model.page is Maintenance {
        ({ ..model, releases_poll_pending: false }, load_releases(emit))
      } else {
        ({ ..model, releases_poll_pending: false }, @cmd.none)
      }
    // 手动重拉（§11.3）：立刻把按钮按成「正在重新拉取」（loading），排一趟后台刷新。
    // 补问计数清零：这是使用者亲手要的一次刷新，轮询预算该从头算。
    _ => (model, @cmd.none)
  }
}

///|
/// ReleasesRefresh 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_releases_refresh(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    ReleasesRefresh => (
      {
        ..model,
        releases_loading: true,
        releases_ticks: 0,
        releases_poll_pending: false,
      },
      refresh_releases_cmd(emit),
    )
    // 刷新那一枪的回执：排上了就读回当前缓存（state 应当是 loading），
    // 之后照旧由 ReleasesText / ReleasesTick 的轮询接上新读数；没排上就写进侧栏底部。
    _ => (model, @cmd.none)
  }
}

///|
/// ReleasesRefreshDone 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_releases_refresh_done(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    ReleasesRefreshDone(res) => {
      let (ok, note) = interpret_http(res)
      if !ok {
        (
          notice_err({ ..model, releases_loading: false }, "重新拉取没成：" + note),
          @cmd.none,
        )
      } else {
        (model, load_releases(emit))
    _ => (model, @cmd.none)
  }
}

///|
/// JobStart 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_job_start(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    JobStart => job_start_command(model, emit)
    _ => (model, @cmd.none)
  }
}

///|
/// JobAction 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_job_action(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    JobAction(id, step) => job_step_command(model, id, step, emit)
    _ => (model, @cmd.none)
  }
}

///|
/// JobToggle 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_job_toggle(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    JobToggle(id) => {
      let kept = model.job_collapsed.filter(fn(collapsed) { collapsed != id })
      if kept.length() == model.job_collapsed.length() {
        // 现在展开着 → 收起
        kept.push(id)
      }
      ({ ..model, job_collapsed: kept }, @cmd.none)
    _ => (model, @cmd.none)
  }
}

///|
/// JobDone 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_job_done(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    JobDone(action, res) => job_settled(model, action, res, emit)
    // 手动折过就记一笔：ui.archiveOpenByDefault 之后不再覆盖用户的选择
    _ => (model, @cmd.none)
  }
}

///|
/// ToggleArchived 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_toggle_archived(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    ToggleArchived => (
      { ..model, archived_open: !model.archived_open, archived_user_toggled: true },
      @cmd.none,
    )
    // 换来源：来源是页面状态的一部分，跟着进地址（换来源 = 走一步，可以后退回来）
    _ => (model, @cmd.none)
  }
}

///|
/// LogSourcePicked 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_log_source_picked(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    LogSourcePicked(value) => {
      let (next, read) = start_logs({ ..model, log_user_picked: true }, value, emit)
      (
        next,
        @cmd.batch([
          read,
          push_route(route_url(Logs, model.settings_group, value)),
        ]),
      )
    }
    // 刷新不是走一步：地址不变，只是重读一遍当前来源
    _ => (model, @cmd.none)
  }
}

///|
/// LogRefresh 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_log_refresh(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    LogRefresh => start_logs(model, model.log_source, emit)
    // ── 设置页 ─────────────────────────────────────────────
    _ => (model, @cmd.none)
  }
}

///|
/// SettingsText 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_settings_text(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    SettingsText(res) => settings_loaded_state(model, res)
    _ => (model, @cmd.none)
  }
}

///|
/// SettingsRetry 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_settings_retry(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    SettingsRetry => (
      { ..model, settings_loading: true, settings_error: "", settings_loaded: false },
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
fn handle_settings_group_picked(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    SettingsGroupPicked(id) => (
      { ..model, settings_group: id, route_notice: "" },
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
fn handle_settings_back(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    SettingsBack => (
      { ..model, settings_group: "", route_notice: "" },
      @cmd.batch([
        push_route(route_url(Settings, "", model.log_source)),
        focus_after_render(settings_row_dom_id(setting_group_of(model.settings_group).id)),
      ]),
    )
    _ => (model, @cmd.none)
  }
}

///|
/// SettingDraft 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_setting_draft(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    SettingDraft(key, text) => (
      { ..model, settings_draft: put_draft(model.settings_draft, key, text) },
      @cmd.none,
    )
    _ => (model, @cmd.none)
  }
}

///|
/// SettingCommit 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_setting_commit(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    SettingCommit(key, text) => commit_setting(model, key, text, emit)
    _ => (model, @cmd.none)
  }
}

///|
/// SettingToggle 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_setting_toggle(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    SettingToggle(key, next) => commit_setting_value(model, key, VBool(next), emit)
    // 恢复默认走同一条 PUT（值取后端给的缺省值，不是前端自己填一个数）
    _ => (model, @cmd.none)
  }
}

///|
/// SettingReset 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_setting_reset(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    SettingReset(key) => reset_setting(model, key, emit)
    _ => (model, @cmd.none)
  }
}

///|
/// SettingsSaved 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_settings_saved(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    SettingsSaved(key, res) => settings_saved_state(model, key, res)
    // ── 写动作的回执 ───────────────────────────────────────
    // 启动走「回执 + 展示下限」两条腿；其余动作拿到回执就落定，
    // 成功的动作一律重读 profiles / instances（刷新的是读数，不是弹个提示）。
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
fn handle_copy_done(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
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
/// FlashExpire 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_flash_expire(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    FlashExpire(serial) => 
      match model.notice {
        None => (model, @cmd.none)
        Some(n) =>
          if n.seq != serial {
            (model, @cmd.none)
          } else if model.flash_hover {
            // 鼠标正停在上面：这一拍不算数，重新计一遍 —— 不许它正好在眼皮底下消失
            (model, @cmd.delay(emit(FlashExpire(serial)), flash_ms))
          } else {
            (
              { ..model, flash_fading: true },
              @cmd.delay(emit(FlashRemove(serial)), flash_fade_ms),
            )
    _ => (model, @cmd.none)
  }
}

///|
/// FlashRemove 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_flash_remove(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    FlashRemove(serial) => 
      match model.notice {
        None => (model, @cmd.none)
        Some(n) => if n.seq == serial { (notice_clear(model), @cmd.none) } else { (model, @cmd.none) }
    _ => (model, @cmd.none)
  }
}

///|
/// FlashHover 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_flash_hover(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    FlashHover(on) => ({ ..model, flash_hover: on }, @cmd.none)
    // 关于页：把某一份 dsh 指定成起实例用的那一版 / 撤掉指定回到自动
    _ => (model, @cmd.none)
  }
}

///|
/// DshVersionPin 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_dsh_version_pin(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    DshVersionPin(dir, version) => pin_dsh_version(model, dir, version, emit)
    _ => (model, @cmd.none)
  }
}

///|
/// DshVersionUnpin 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_dsh_version_unpin(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    DshVersionUnpin => unpin_dsh_version(model, emit)
    _ => (model, @cmd.none)
  }
}

///|
/// Noop 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_noop(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    Noop => (model, @cmd.none)
  }
    _ => (model, @cmd.none)
  }
}
