// 导航、行内动作、抽屉与其它零散 Msg 的回执落地。

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
    }
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
          match find_row(model.rows, id) {
            Some(row) =>
              if row.external_links > 0 {
                // 副本里那些链接还指向原处（§60.2）：先告知，不直接发请求
                handle_fork_open(
                  model,
                  ForkOpen(id=id, return_id="dsh-drawer-fork"),
                  emit,
                )
              } else {
                send_action(
                  model,
                  id,
                  "fork-profile",
                  row_name(model, id),
                  "派生",
                  params_for_row(model, id, "profile"),
                  emit,
                )
              }
            None => (model, @cmd.none)
          }
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
            "移至隔离 home",
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
fn handle_split_menu_toggle(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
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
fn handle_split_menu_close(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
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
/// 「派生开发副本」那颗按钮（§60.2）：有外部软链接时走确认框，没有就直接派生（那条在
/// handle_row_action 的 Fork 分支里）。
fn handle_fork_open(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    ForkOpen(id~, return_id~) =>
      match find_row(model.rows, id) {
        Some(_) =>
          (
            { ..model, fork_confirm_id: id, fork_confirm_return: return_id },
            focus_after_render("dsh-fork-dialog-ok"),
          )
        None => (model, @cmd.none)
      }
    _ => (model, @cmd.none)
  }
}

///|
/// 确认框里点了「取消」：什么都不发，焦点回抽屉那颗按钮。
fn handle_fork_cancel(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    ForkCancel =>
      if model.fork_confirm_id == "" {
        (model, @cmd.none)
      } else {
        let back = model.fork_confirm_return
        (
          { ..model, fork_confirm_id: "", fork_confirm_return: "" },
          if back == "" { @cmd.none } else { focus_after_render(back) },
        )
      }
    _ => (model, @cmd.none)
  }
}

///|
/// 确认框里点了「仍然派生」：清掉框，走与无链接时同一条 fork-profile。
fn handle_fork_confirm(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    ForkConfirm => {
      let id = model.fork_confirm_id
      let cleared = { ..model, fork_confirm_id: "", fork_confirm_return: "" }
      match find_row(cleared.rows, id) {
        Some(_) =>
          send_action(
            cleared,
            id,
            "fork-profile",
            row_name(cleared, id),
            "派生",
            params_for_row(cleared, id, "profile"),
            emit,
          )
        None => (cleared, @cmd.none)
      }
    }
    _ => (model, @cmd.none)
  }
}
