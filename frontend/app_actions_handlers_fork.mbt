// 派生拷贝的进度框（§72）。
//
// 派生是一个阻塞请求：点下去之后控制台要拷整个目录（带 node_modules），几秒到几十秒。
// 那条 POST 带不回中间进度，所以另开一条 GET 轮询；拷完（done）就把框收掉，
// 成功失败仍由原本那条 POST 的回执去说 —— 这里只负责「拷到哪儿了」。

///|
let fork_poll_ms : Int32 = 400

///|
/// 开始一轮轮询：把框摆出来，立刻读第一枪。
fn fork_progress_begin(
  model : Model,
  name : String,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  (
    {
      ..model,
      fork_progress_active: true,
      fork_progress_name: name,
      fork_progress_files: 0,
      fork_progress_total: 0,
      fork_progress_error: "",
    },
    fork_progress_cmd(emit),
  )
}

///|
fn handle_fork_progress(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    ForkProgressTick => (model, fork_progress_cmd(emit))
    ForkProgressText(text) => {
      let mut next = model
      if text != "" {
        let parsed = @json.parse(text) catch { _ => return (next, @cmd.none) }
        guard parsed is Json::Object(envelope) else { return (next, @cmd.none) }
        match envelope.get("data") {
          Some(Json::Object(data)) => {
            let active = bool_field(data, "active")
            let files = match int_field(data, "files") {
              Some(v) => v
              None => 0
            }
            let total = match int_field(data, "total") {
              Some(v) => v
              None => 0
            }
            next = {
              ..next,
              fork_progress_name: str_field(data, "profile"),
              fork_progress_files: files,
              fork_progress_total: total,
              fork_progress_error: str_field(data, "error"),
              fork_progress_active: active,
            }
          }
          _ => ()
        }
      }
      if next.fork_progress_active {
        (next, @cmd.delay(emit(ForkProgressTick), fork_poll_ms))
      } else {
        (next, @cmd.none)
      }
    }
    _ => (model, @cmd.none)
  }
}
