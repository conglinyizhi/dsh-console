// 提示条、通知面板、toast 计时类 Msg 的回执落地。

///|
/// NoticePanelOpen 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_notice_panel_open(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    NoticePanelOpen =>
      if model.notice_panel {
        (model, @cmd.none)
      } else {
        (
          { ..model, notice_panel: true, notice_unread: 0, },
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
fn handle_notice_panel_close(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    NoticePanelClose =>
      if model.notice_panel {
        (
          { ..model, notice_panel: false, },
          focus_after_render(notice_bell_id()),
        )
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
fn handle_notice_open_logs(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
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
fn handle_notice_open_ui(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    NoticeOpenUi =>
      match model.notice_url {
        None => (model, @cmd.none)
        Some(url) => {
          let (ok, tail) = open_outcome_text(js_open_url(url))
          let text = "Web UI " + tail + "。" + url
          (
            { ..notice_put(model, ok, text, ""), notice_url_notice: text, },
            @cmd.none,
          )
        }
      }
    _ => (model, @cmd.none)
  }
}

///|
/// FlashExpire 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_flash_expire(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
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
              { ..model, flash_fading: true, },
              @cmd.delay(emit(FlashRemove(serial)), flash_fade_ms),
            )
          }
      }
    _ => (model, @cmd.none)
  }
}

///|
/// FlashRemove 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_flash_remove(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    FlashRemove(serial) =>
      match model.notice {
        None => (model, @cmd.none)
        Some(n) =>
          if n.seq == serial {
            (notice_clear(model), @cmd.none)
          } else {
            (model, @cmd.none)
          }
      }
    _ => (model, @cmd.none)
  }
}

///|
/// FlashHover 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_flash_hover(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    FlashHover(on) => ({ ..model, flash_hover: on, }, @cmd.none)
    // 关于页：把某一份 dsh 指定成起实例用的那一版 / 撤掉指定回到自动
    _ => (model, @cmd.none)
  }
}

///|
/// Noop 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_noop(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    Noop => (model, @cmd.none)
    _ => (model, @cmd.none)
  }
}
