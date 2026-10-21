// 分发插件对话框的动作（design/backlog.md N）。

///|
/// 这一行对应的 profile 目录名：优先 profile_name；没有就用卡片名（实例名带端口不能用，
/// 但这一版只有 profile 行会开这个框）。
fn merge_row_name(row : Row) -> String {
  match row.profile_name {
    Some(n) => if n == "" { row.name } else { n }
    None => row.name
  }
}

///|
/// 打开对话框：记下源行与焦点返回点；目标默认空（要人自己勾）。
fn handle_merge_open(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    MergeOpen(id~, return_id~) =>
      match find_row(model.rows, id) {
        Some(row) => {
          // 磁盘目录名：profile_name 可能为空（隔离 home 的卡片），卡片名带端口也不能用（§77）
          let source = merge_row_name(row)
          (
            {
              ..model,
              merge_source: id,
              merge_targets: [],
              merge_confirm: "",
              merge_return: return_id,
              merge_plugins: [],
              merge_plugin_picked: [],
              merge_loading: true,
              merge_slide: 0,
              merge_step: 1,
            },
            merge_preview_cmd(source, emit),
          )
        }
        None => (model, @cmd.none)
      }
    _ => (model, @cmd.none)
  }
}

///|
/// 目标勾选（多选）。
fn handle_merge_plugin_toggle(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    MergePluginToggle(name) => {
      // 选插件是第一步：改了插件就把目标清空（目标列表与插件无关，但提交要成套）
      let next : Array[String] = []
      let mut had = false
      for item in model.merge_plugin_picked {
        if item == name {
          had = true
        } else {
          next.push(item)
        }
      }
      if !had {
        next.push(name)
      }
      ({ ..model, merge_plugin_picked: next }, @cmd.none)
    }
    _ => (model, @cmd.none)
  }
}

///|
/// 两步之间来回：选目标那一步只在选了插件之后可进。
fn handle_merge_step(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    MergeStepNext =>
      if model.merge_step == 1 && model.merge_plugin_picked.length() > 0 {
        ({ ..model, merge_step: 2, merge_slide: 0 }, @cmd.none)
      } else if model.merge_step == 2 && model.merge_targets.length() > 0 {
        ({ ..model, merge_step: 3, merge_slide: 0 }, @cmd.none)
      } else {
        (model, @cmd.none)
      }
    MergeStepPrev =>
      if model.merge_step > 1 {
        ({ ..model, merge_step: model.merge_step - 1, merge_slide: 0 }, @cmd.none)
      } else {
        (model, @cmd.none)
      }
    _ => (model, @cmd.none)
  }
}

///|
/// 预览接口的回执：填插件清单；失败就留在空态并记一句。
fn handle_merge_preview(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    MergePreviewText(res) => {
      // 不能用 interpret_http：它回的是给人看的一句话（§80），不是响应体。
      // 这里要的是 JSON，自己走 HTTP → body → envelope。
      let plugins : Array[(String, String, String, String)] = []
      match res {
        Ok(text) => {
          let got = parse_http_result(text)
          if got.status >= 200 && got.status < 300 {
            match open_envelope(got.body) {
              Ok(data) =>
                for item in arr_field(data, "plugins") {
                  match item {
                    Json::Object(obj) => {
                      let name = str_field(obj, "name")
                      let version = str_field(obj, "version")
                      let kind = str_field(obj, "kind")
                      let description = str_field(obj, "description")
                      if name != "" {
                        plugins.push((name, version, kind, description))
                      }
                    }
                    _ => ()
                  }
                }
              Err(_) => ()
            }
          }
        }
        Err(_) => ()
      }
      ({ ..model, merge_plugins: plugins, merge_loading: false }, @cmd.none)
    }
    _ => (model, @cmd.none)
  }
}

///|
/// 发一次预览（POST /api/local/merge-preview，只读）。
fn merge_preview_cmd(source : String, emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  let body = "{\"source\":\"" + source + "\"}"
  @cmd.attempt(
    fn(res : Result[String, Error]) { emit(MergePreviewText(res)) },
    async fn() {
      let text : String = js_http_call("POST", "/api/local/merge-preview", body, write_headers()).wait().cast()
      text
    },
  )
}

///|
/// 目标勾选（多选）。
fn handle_merge_toggle(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    MergeTargetToggle(name) => {
      let next : Array[String] = []
      let mut had = false
      for item in model.merge_targets {
        if item == name {
          had = true
        } else {
          next.push(item)
        }
      }
      if !had {
        next.push(name)
      }
      ({ ..model, merge_targets: next }, @cmd.none)
    }
    _ => (model, @cmd.none)
  }
}

///|
/// 滑动确认：指针把滑块推到某个百分比；到 95 以上松手才提交（低于就弹回）。
fn handle_merge_slide(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    MergeSlideStart => ({ ..model, merge_dragging: true }, @cmd.none)
    MergeSlide(v) =>
      if !model.merge_dragging {
        (model, @cmd.none)
      } else {
        ({ ..model, merge_slide: if v < 0 { 0 } else if v > 100 { 100 } else { v } }, @cmd.none)
      }
    MergeSlideRelease => {
      let stopped = { ..model, merge_dragging: false }
      // 提交区起点按「轨道宽度 - 72px」算出来存在 merge_zone_pct 里（按下时更新）
      if stopped.merge_slide >= stopped.merge_zone_pct {
        handle_merge_submit({ ..stopped, merge_slide: 100 }, MergeSubmit, emit)
      } else {
        (
          notice_err({ ..stopped, merge_slide: 0 }, "没到右侧，这次迁移取消了"),
          @cmd.none,
        )
      }
    }
    MergeSlideKey(key) =>
      if key == "End" || (key == "Enter" && model.merge_slide >= 95) {
        handle_merge_submit({ ..model, merge_slide: 100 }, MergeSubmit, emit)
      } else if key == "ArrowRight" || key == "ArrowUp" || key == "Space" {
        let next = model.merge_slide + 10
        if next >= 100 {
          handle_merge_submit({ ..model, merge_slide: 100 }, MergeSubmit, emit)
        } else {
          ({ ..model, merge_slide: next }, @cmd.none)
        }
      } else {
        (model, @cmd.none)
      }
    _ => (model, @cmd.none)
  }
}

///|
/// 取消：什么都不发，焦点回抽屉那颗按钮。
fn handle_merge_cancel(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    MergeCancel =>
      if model.merge_source == "" {
        (model, @cmd.none)
      } else {
        let back = model.merge_return
        (
          { ..model, merge_source: "", merge_targets: [], merge_confirm: "", merge_slide: 0 },
          if back == "" { @cmd.none } else { focus_after_render(back) },
        )
      }
    _ => (model, @cmd.none)
  }
}

///|
/// 提交：确认串不对就不发（按钮也灰着，这里再拦一道）。
fn handle_merge_submit(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    MergeSubmit => {
      let source = model.merge_source
      let targets = model.merge_targets
      let confirm = model.merge_confirm
      let back = model.merge_return
      let _ = confirm
      if source == "" || targets.length() == 0 || model.merge_plugin_picked.length() == 0 {
        (model, @cmd.none)
      } else {
        // 用磁盘目录名（web），不是卡片上带端口的那串（web :3080）：后端按 profile 目录找源。
        let name = match find_row(model.rows, source) {
          Some(row) =>
            match row.profile_name {
              Some(profile) => profile
              None => row_name(model, source)
            }
          None => row_name(model, source)
        }
        let ids : Array[String] = []
        for t in targets {
          ids.push("\"" + t + "\"")
        }
        let picks : Array[String] = []
        for p in model.merge_plugin_picked {
          picks.push("\"" + p + "\"")
        }
        let body = "{\"action\":\"merge-plugins\",\"params\":{\"profile\":\"" +
          name + "\",\"targets\":[" + ids.join(",") + "],\"plugins\":[" +
          picks.join(",") + "],\"confirm\":\"MERGE\"}}"
        let closed = {
          ..model,
          merge_source: "",
          merge_targets: [],
          merge_confirm: "",
          merge_slide: 0,
          merge_busy: true,
        }
        (
          { ..closed, merge_return: back },
          merge_post(body, emit),
        )
      }
    }
    _ => (model, @cmd.none)
  }
}

///|
/// 发一次 merge-plugins（与 settings 那套同一形状的 POST）。
fn merge_post(body : String, emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.attempt(
    fn(res : Result[String, Error]) { emit(MergeDone(res)) },
    async fn() {
      let text : String = js_http_call("POST", "/api/local/action", body, write_headers()).wait().cast()
      text
    },
  )
}
///|
/// merge-plugins 的回执：成功报「分发了 N 只」，失败把后端的原话摆出来。
fn handle_merge_done(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    MergeDone(res) => {
      let (ok, note) = interpret_http(res)
      let cleared = { ..model, merge_busy: false }
      if ok {
        (notice_ok(cleared, note, "分发插件"), @cmd.none)
      } else {
        (notice_err(cleared, note), @cmd.none)
      }
    }
    _ => (model, @cmd.none)
  }
}