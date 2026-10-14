// 应用入口与更新循环。
//
// 三个只读接口在 init 里一次发出去；解析放在 update 里，失败的原因（不是 JSON / ok=false /
// 接口不可达）原样进 model，界面直接展示。三个读数都落地之后才拼一次实例列表 ——
// 与 Vue 版 Promise.all 之后再拼同一口径。

///|
pub fn app() -> @rabbita.Val[@html.Html] {
  let (model, emit) = @rabbita.create_state_with_init(
    init=fn(emit) { (initial_model(), load(emit)) },
    update=update,
  )
  model.view(fn(m) { page_view(m, emit) })
}

// ── 列表拼装 ────────────────────────────────────────────────

///|
fn dsh_home_of(model : Model) -> String {
  match model.profiles {
    Some(facts) => facts.dsh_home
    None =>
      match model.runtime {
        Some(facts) => facts.dsh_home
        None => "—"
      }
  }
}

///|
fn default_log_source(model : Model) -> String {
  match model.instances {
    Some(facts) =>
      if facts.instances.length() > 0 {
        "instance:" + facts.instances[0].id
      } else {
        "host"
      }
    None => "host"
  }
}

///|
/// 三个读数都落地之后拼一次：运行中（真实探测）/ 已停止（磁盘上的 profile）/ 归档区（演示）。
/// 任一读失败，对应的那一组退回演示数据，并保持自己的数据源标记。
fn rebuild(model : Model, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  if model.built || !(model.read_runtime && model.read_profiles && model.read_instances) {
    return (model, @cmd.none)
  }
  let profile_list = match model.profiles {
    Some(facts) => facts.profiles
    None => []
  }
  let running = match model.instances {
    Some(facts) => running_rows(facts.instances, profile_list)
    None => demo_running()
  }
  let stopped = match model.profiles {
    Some(facts) => profile_rows(facts.profiles, model.runtime, dsh_home_of(model))
    None => demo_stopped()
  }
  let rows : Array[Row] = []
  for row in running {
    rows.push(row)
  }
  for row in stopped {
    rows.push(row)
  }
  for row in demo_archived() {
    rows.push(row)
  }
  let source = if model.log_user_picked {
    model.log_source
  } else {
    default_log_source(model)
  }
  // 日志页已经开着、而默认来源刚刚才定下来：补一次读取，别让下拉与内容对不上
  let cmd = if model.page is Logs && source != model.log_source {
    @cmd.batch([load_logs(source, emit), scroll_bottom_after_render("dsh-log-box")])
  } else {
    @cmd.none
  }
  ({ ..model, rows, built: true, log_source: source }, cmd)
}

// ── 行操作 ─────────────────────────────────────────────────

///|
fn map_rows(model : Model, id : String, f : (Row) -> Row) -> Model {
  { ..model, rows: map_row(model.rows, id, f) }
}

///|
fn row_name(model : Model, id : String) -> String {
  match find_row(model.rows, id) {
    Some(row) => row.name
    None => id
  }
}

///|
/// 启动：先留在原分组显示等待态，再落成运行中（前端演示，不拉起真实进程）。
fn start_row(model : Model, id : String, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  (
    map_rows(model, id, fn(row) { { ..row, status: Starting, busy: true } }),
    @cmd.delay(emit(StartTick(id)), start_delay_ms),
  )
}

///|
/// 派生副本的编号：在 plugin-dev-N 里取第一个没被占用的号。
/// 按 id 判断占用而不是按 name，改名不会把 id 让出去，也就不会派生出重号。
fn next_fork_index(rows : Array[Row]) -> Int {
  let mut index = 2
  let mut used = true
  while used {
    used = false
    for row in rows {
      if row.id == "plugin-dev-" + index.to_string() {
        used = true
      }
    }
    if used {
      index = index + 1
    }
  }
  index
}

///|
/// url 尾部的端口号：http://127.0.0.1:8200 → 8200。读不出给 0。
fn port_of_url(url : String) -> Int {
  let mut last = -1
  let mut i = 0
  for c in url {
    if c == ':' {
      last = i
    }
    i = i + 1
  }
  if last < 0 {
    return 0
  }
  let digits = url[last + 1:].to_owned()
  let mut value = 0
  for c in digits {
    if c >= '0' && c <= '9' {
      value = value * 10 + (c.to_int() - 48)
    } else {
      return 0
    }
  }
  value
}

///|
/// 派生基线：现有实例里最大的端口号 + 1。
fn next_port(rows : Array[Row]) -> Int {
  let mut max = 0
  for row in rows {
    let port = port_of_url(row.url)
    if port > max {
      max = port
    }
  }
  max + 1
}

///|
/// 探一个候选端口：resolve 说明有人应答（占用），reject 说明这一次没听到（按空闲处理）。
fn probe_cmd(id : String, port : Int, emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.attempt(
    fn(res : Result[Bool, Error]) {
      let busy = match res {
        Ok(value) => value
        Err(_) => false
      }
      emit(ProbeTick(id, busy))
    },
    async fn() {
      let busy : Bool = js_probe_port_busy(port).wait().cast()
      busy
    },
  )
}

///|
/// 派生开发副本：新实例 plugin-dev-N，端口从「当前最大 +1」往下探（最多 20 个）。
fn fork(model : Model, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  let index = next_fork_index(model.rows)
  let name = "plugin-dev-" + index.to_string()
  let base = next_port(model.rows)
  let row : Row = {
    id: name,
    name,
    kind: "插件开发（试验）",
    kind_hint: "",
    tone: Violet,
    status: Starting,
    uptime: Some(0),
    uptime_hint: "",
    port_note: "端口 " + base.to_string() + " · 正在探测",
    idle_note: "",
    note: "",
    busy: true,
    version: "0.2.0-rc.2（本地源码）",
    profile: "dev",
    home: "/Users/you/.dsh/" + name,
    url: "http://127.0.0.1:0",
    plugin_count: "1 个（开发中）",
    plugin_detail: "",
    deletable: true,
    archived_at: None,
  }
  let rows = model.rows.map(fn(existing) { existing })
  rows.push(row)
  (
    { ..model, rows, probe_id: name, probe_base: base, probe_offset: 0, probe_skipped: -1 },
    @cmd.batch([
      @cmd.delay(emit(StartTick(name)), start_delay_ms),
      probe_cmd(name, base, emit),
    ]),
  )
}

///|
/// 端口探测的下一步：占用就往后试，20 个都被占用时给一个没探测过的号并说清。
fn probe_step(model : Model, id : String, busy : Bool, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  if model.probe_id != id {
    return (model, @cmd.none)
  }
  let port = model.probe_base + model.probe_offset
  let skipped = if model.probe_skipped < 0 { port } else { model.probe_skipped }
  if busy {
    let offset = model.probe_offset + 1
    if offset < port_probe_limit {
      (
        { ..model, probe_offset: offset, probe_skipped: skipped },
        probe_cmd(id, model.probe_base + offset, emit),
      )
    } else {
      let fallback = model.probe_base + port_probe_limit
      let note = model.probe_base.to_string() + " 起 20 个都被占用，暂用 " +
        fallback.to_string() + "（未探测）"
      (
        map_rows(
          { ..model, probe_id: "" },
          id,
          fn(row) { { ..row, url: "http://127.0.0.1:" + fallback.to_string(), port_note: note } },
        ),
        @cmd.none,
      )
    }
  } else {
    let note = if model.probe_skipped < 0 {
      "端口 " + port.to_string() + " · 已探测未被占用"
    } else {
      skipped.to_string() + " 被占用，改用 " + port.to_string()
    }
    (
      map_rows(
        { ..model, probe_id: "" },
        id,
        fn(row) { { ..row, url: "http://127.0.0.1:" + port.to_string(), port_note: note } },
      ),
      @cmd.none,
    )
  }
}

// ── 更新 ───────────────────────────────────────────────────

///|
fn update(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  // 行内动作一律先收起菜单：菜单项点下去之后菜单不该留在原地
  let model = match msg {
    RowAction(_, _) => { ..model, menu_open: "" }
    _ => model
  }
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
                tag_runtime: real_tag(
                  "dsh " + facts.dsh_version + " · 后端 " + facts.backend_runtime + " " +
                  facts.backend_version + " · DSH_HOME " + facts.dsh_home + "（" +
                  facts.dsh_home_source + "） · " + time + " 读取",
                ),
                read_runtime: true,
              }
            Err(reason) =>
              {
                ..model,
                runtime: None,
                runtime_error: reason,
                runtime_time: time,
                tag_runtime: fallback_tag("/api/local/runtime 读取失败：" + reason),
                read_runtime: true,
              }
          }
        Err(err) => {
          let reason = "本地只读接口不可达（" + describe(err) + "）"
          {
            ..model,
            runtime: None,
            runtime_error: reason,
            runtime_time: time,
            tag_runtime: fallback_tag("/api/local/runtime 读取失败：" + reason),
            read_runtime: true,
          }
        }
      }
      rebuild(next, emit)
    }
    ProfilesText(res) => {
      let next = match res {
        Ok(text) =>
          match parse_profiles(text) {
            Ok(facts) =>
              {
                ..model,
                profiles: Some(facts),
                profiles_error: "",
                tag_profiles: real_tag(
                  "/api/local/profiles 扫 " + facts.profiles_root + "，" +
                  facts.profiles.length().to_string() + " 个 profile",
                ),
                read_profiles: true,
              }
            Err(reason) =>
              {
                ..model,
                profiles: None,
                profiles_error: reason,
                tag_profiles: fallback_tag("/api/local/profiles 读取失败：" + reason),
                read_profiles: true,
              }
          }
        Err(err) => {
          let reason = "本地只读接口不可达（" + describe(err) + "）"
          {
            ..model,
            profiles: None,
            profiles_error: reason,
            tag_profiles: fallback_tag("/api/local/profiles 读取失败：" + reason),
            read_profiles: true,
          }
        }
      }
      rebuild(next, emit)
    }
    InstancesText(res) => {
      let next = match res {
        Ok(text) =>
          match parse_instances(text) {
            Ok(facts) =>
              {
                ..model,
                instances: Some(facts),
                instances_error: "",
                tag_instances: real_tag(
                  "/api/local/instances 读 " + join_with(facts.sources, " + ") + "：扫 " +
                  facts.candidate_count.to_string() + " 个 loopback LISTEN 端口，命中 DSH 签名 " +
                  facts.probe_hits.to_string() + " 个（判据 " +
                  join_with(facts.signature_ids, " / ") + "）· 进程补充：" + facts.process_note +
                  " · " + local_time_now() + " 读取",
                ),
                read_instances: true,
              }
            Err(reason) =>
              {
                ..model,
                instances: None,
                instances_error: reason,
                tag_instances: fallback_tag("/api/local/instances 读取失败：" + reason),
                read_instances: true,
              }
          }
        Err(err) => {
          let reason = "本地只读接口不可达（" + describe(err) + "）"
          {
            ..model,
            instances: None,
            instances_error: reason,
            tag_instances: fallback_tag("/api/local/instances 读取失败：" + reason),
            read_instances: true,
          }
        }
      }
      rebuild(next, emit)
    }
    LogsText(res) => {
      let time = local_time_now()
      let source = model.log_source
      let label = source_label(model, source)
      let query = "GET /api/local/logs?source=" + js_encode_uri_component(source)
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
                  log_tag: real_tag(
                    query + " 读 " +
                    (match facts.path {
                      Some(path) => path
                      None => "—"
                    }) +
                    " 尾部 " + facts.window_bytes.to_string() + " 字节窗口，返回 " +
                    facts.lines.length().to_string() + " 行 · " + time + " 读取",
                  ),
                  log_loaded: true,
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
                  log_loaded: true,
                }
              }
            Err(reason) =>
              {
                ..model,
                logs: None,
                log_error: reason,
                log_time: time,
                log_tag: fallback_tag(query + " 失败：" + reason),
                log_loaded: true,
              }
          }
        Err(err) => {
          let reason = describe(err)
          {
            ..model,
            logs: None,
            log_error: reason,
            log_time: time,
            log_tag: fallback_tag(query + " 失败：" + reason),
            log_loaded: true,
          }
        }
      }
      (next, scroll_bottom_after_render("dsh-log-box"))
    }
    Navigate(page) => {
      let next = { ..model, page }
      if page is Logs {
        let cmd = if model.log_loaded {
          scroll_bottom_after_render("dsh-log-box")
        } else {
          @cmd.batch([
            load_logs(model.log_source, emit),
            scroll_bottom_after_render("dsh-log-box"),
          ])
        }
        ({ ..next, log_loaded: true }, cmd)
      } else {
        (next, @cmd.none)
      }
    }
    RowAction(id, key) =>
      match key {
        Toggle =>
          match find_row(model.rows, id) {
            None => (model, @cmd.none)
            Some(row) =>
              if row.status is Running {
                (map_rows(model, id, fn(item) { { ..item, status: Stopped } }), @cmd.none)
              } else if row.status is Stopped {
                start_row(model, id, emit)
              } else {
                (model, @cmd.none)
              }
          }
        Restart => (
          { ..model, restarting: id },
          @cmd.delay(emit(RestartTick), restart_lock_ms),
        )
        Rename => (
          {
            ..model,
            rename_id: id,
            rename_draft: row_name(model, id),
            rename_return: trigger_id(id),
          },
          focus_select_after_render("dsh-rename-input"),
        )
        Delete => (
          { ..model, confirm_id: id, confirm_return: trigger_id(id) },
          focus_after_render("dsh-confirm-ok"),
        )
        Archive => (
          map_rows(model, id, fn(row) { { ..row, archived_at: Some(demo_archived_at) } }),
          @cmd.none,
        )
        Unarchive => (
          map_rows(
            model,
            id,
            fn(row) { { ..row, archived_at: None, status: Stopped } },
          ),
          @cmd.none,
        )
        Fork => fork(model, emit)
        // 归档行上的删除：触发元素是那一行自己的删除键，不是菜单触发器

        _ => (model, @cmd.none)
      }
    DeleteOpen(id, return_id) => (
      { ..model, confirm_id: id, confirm_return: return_id },
      focus_after_render("dsh-confirm-ok"),
    )
    MenuToggle(id) =>
      if model.menu_open == id {
        ({ ..model, menu_open: "" }, @cmd.none)
      } else {
        ({ ..model, menu_open: id }, focus_first_after_render(menu_id(id), ".dsh-menu-item"))
      }
    MenuClose => ({ ..model, menu_open: "" }, @cmd.none)
    MenuCloseBack(id) => (
      { ..model, menu_open: "" },
      focus_after_render(trigger_id(id)),
    )
    StartTick(id) => {
      let cleared = map_rows(model, id, fn(row) { { ..row, busy: false, port_note: "" } })
      let next = match find_row(cleared.rows, id) {
        Some(row) =>
          if row.archived_at is None && row.status is Starting {
            map_rows(cleared, id, fn(item) { { ..item, status: Running, uptime: Some(0) } })
          } else {
            cleared
          }
        None => cleared
      }
      (next, @cmd.none)
    }
    RestartTick => ({ ..model, restarting: "" }, @cmd.none)
    RenameInput(text) => ({ ..model, rename_draft: text }, @cmd.none)
    RenameConfirm => {
      let draft = model.rename_draft.trim().to_owned()
      if draft.length() == 0 {
        (model, @cmd.none)
      } else {
        let updated = map_rows(model, model.rename_id, fn(row) { { ..row, name: draft } })
        (
          { ..updated, rename_id: "", rename_draft: "" },
          focus_after_render(model.rename_return),
        )
      }
    }
    RenameCancel => (
      { ..model, rename_id: "", rename_draft: "" },
      focus_after_render(model.rename_return),
    )
    DeleteConfirm => {
      let target = model.confirm_id
      (
        {
          ..model,
          rows: model.rows.filter(fn(row) { row.id != target }),
          confirm_id: "",
        },
        focus_after_render(model.confirm_return),
      )
    }
    DeleteCancel => (
      { ..model, confirm_id: "" },
      focus_after_render(model.confirm_return),
    )
    ToggleArchived => ({ ..model, archived_open: !model.archived_open }, @cmd.none)
    LogSourcePicked(value) => (
      { ..model, log_source: value, log_user_picked: true, log_loaded: true },
      @cmd.batch([load_logs(value, emit), scroll_bottom_after_render("dsh-log-box")]),
    )
    LogRefresh => (
      model,
      @cmd.batch([
        load_logs(model.log_source, emit),
        scroll_bottom_after_render("dsh-log-box"),
      ]),
    )
    ProbeTick(id, busy) => probe_step(model, id, busy, emit)
    Noop => (model, @cmd.none)
  }
}
