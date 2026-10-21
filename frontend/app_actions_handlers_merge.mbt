// 分发插件对话框的四个动作（design/backlog.md N）。

///|
/// 打开对话框：记下源行与焦点返回点；目标默认空（要人自己勾）。
fn handle_merge_open(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    MergeOpen(id~, return_id~) =>
      match find_row(model.rows, id) {
        Some(row) => {
          let source = match row.profile_name {
            Some(n) => n
            None => row.name
          }
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
/// 预览接口的回执：填插件清单；失败就留在空态并记一句。
fn handle_merge_preview(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    MergePreviewText(res) => {
      let (ok, text) = interpret_http(res)
      let plugins : Array[(String, String, Bool)] = []
      if ok {
        match open_envelope(text) {
          Ok(data) => {
            for item in arr_field(data, "plugins") {
              match item {
                Json::Object(obj) => {
                  let name = str_field(obj, "name")
                  let version = str_field(obj, "version")
                  let link = match obj.get("link") {
                    Some(Json::True) => true
                    _ => false
                  }
                  if name != "" {
                    plugins.push((name, version, link))
                  }
                }
                _ => ()
              }
            }
            ()
          }
          Err(_) => ()
        }
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
/// 确认串输入。
fn handle_merge_input(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    MergeConfirmInput(text) => ({ ..model, merge_confirm: text }, @cmd.none)
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
          { ..model, merge_source: "", merge_targets: [], merge_confirm: "" },
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
      if source == "" || targets.length() == 0 || confirm != "MERGE" ||
        model.merge_plugin_picked.length() == 0 {
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