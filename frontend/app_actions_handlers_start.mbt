// 启动、打开与健康轮询类 Msg 的回执落地。

///|
/// HardOpenDone 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_hard_open_done(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
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
fn handle_start_clicked(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
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
/// HealthTick 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_health_tick(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    HealthTick =>
      if model.health_busy {
        // 上一枪还没回来：这一拍什么都不做（别让两枪同时飞）
        (model, @cmd.none)
      } else if js_page_hidden() {
        if model.health_visible_wait {
          (model, @cmd.none)
        } else {
          ({ ..model, health_visible_wait: true, }, listen_visible(emit))
        }
      } else {
        ({ ..model, health_busy: true, }, health_ping_cmd(emit))
      }
    _ => (model, @cmd.none)
  }
}

///|
/// HealthDone 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_health_done(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    HealthDone(res) => health_settled(model, res, emit)
    _ => (model, @cmd.none)
  }
}

///|
/// HealthVisible 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_health_visible(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    HealthVisible =>
      if model.health_busy {
        ({ ..model, health_visible_wait: false, }, @cmd.none)
      } else {
        (
          { ..model, health_busy: true, health_visible_wait: false, },
          health_ping_cmd(emit),
        )
      }
    // 滑出走完了：这一枪的号还对得上才撤节点。中间又开过抽屉的话（号被清掉或换了一行）
    // 什么都不做 —— 不然会把刚开的那一只撤下去。
    _ => (model, @cmd.none)
  }
}

///|
/// StartTick 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_start_tick(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    StartTick(id) =>
      if model.act_pending == id {
        finish_start({ ..model, act_tick: true, }, emit)
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
fn handle_start_tab_retry(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    StartTabRetry => refresh_readings(model, emit)
    // 抽屉里「安装缺的包（N）」：先开确认框（写 node_modules 是真动作，§39.1）。
    // 焦点进「安装」键；关掉之后回那颗按钮（见 RepairCancel 与原位按钮的 id）。
    _ => (model, @cmd.none)
  }
}

///|
/// RepairOpen 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_repair_open(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    RepairOpen(id~, return_id~) =>
      match find_row(model.rows, id) {
        None => (model, @cmd.none)
        Some(_) =>
          (
            {
              ..model,
              repair_confirm_id: id,
              repair_confirm_return: return_id,
            },
            focus_after_render(repair_dialog_ok_id()),
          )
      }
    // 命令行型 profile 的启动说明（§42）：只开一句说明，不发任何请求。
    _ => (model, @cmd.none)
  }
}

///|
/// RepairCancel 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_repair_cancel(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    RepairCancel =>
      if model.repair_confirm_id == "" {
        (model, @cmd.none)
      } else {
        let back = model.repair_confirm_return
        (
          { ..model, repair_confirm_id: "", repair_confirm_return: "", },
          if back == "" {
            @cmd.none
          } else {
            focus_after_render(back)
          },
        )
      }
    // 确认：发 repair-packages（profile + home）。这一笔走 send_action：
    // 行置忙 → 抽屉里其余写动作跟着禁用，提示条清空等回执。
    _ => (model, @cmd.none)
  }
}

///|
/// RepairConfirm 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_repair_confirm(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
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
            { ..model, repair_confirm_id: "", repair_confirm_return: "", },
            id,
            "repair-packages",
            name,
            "安装缺的包",
            params,
            emit,
          )
          (
            { ..next, repair_id: id, },
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
/// RestartTick 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_restart_tick(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    RestartTick => ({ ..model, restarting: "", }, @cmd.none)
    _ => (model, @cmd.none)
  }
}
