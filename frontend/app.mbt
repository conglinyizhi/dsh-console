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
/// 三个读数都落地之后拼一次：运行中（真实探测）/ 已停止（磁盘上的 profile）/ 归档区（本轮点过归档的行）。
/// 任一读失败，对应的那一组退回演示数据，并保持自己的数据源标记。
fn rebuild(model : Model, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  if model.built ||
    !(model.read_runtime &&
      model.read_profiles &&
      model.read_instances &&
      model.read_console) {
    return (model, @cmd.none)
  }
  let profile_list = match model.profiles {
    Some(facts) => facts.profiles
    None => []
  }
  let running = match model.instances {
    Some(facts) => running_rows(facts.instances, profile_list, model.console)
    None => demo_running()
  }
  // 已停止组要排除「正被某个运行中实例用着」的 profile——同一个东西不能既运行中又已停止
  let live_instances = match model.instances {
    Some(facts) => facts.instances
    None => []
  }
  let stopped = match model.profiles {
    Some(facts) =>
      profile_rows(facts.profiles, model.runtime, dsh_home_of(model), live_instances)
    None => demo_stopped()
  }
  let rows : Array[Row] = []
  for row in running {
    rows.push(row)
  }
  for row in stopped {
    rows.push(row)
  }
  // 归档区不是演示数据了：它由本轮真的点过「归档」的动作产生（archive.json 没有读接口，
  // 所以这份记录只在这次会话里有效）。行是按读数重建的，重建之后要把归档标记标回去。
  let rows = apply_archived_marks(model, rows)
  let source = if model.log_user_picked {
    model.log_source
  } else {
    default_log_source(model)
  }
  // 日志页已经开着、而默认来源刚刚才定下来：补一次读取，别让下拉与内容对不上
  let cmd = if model.page is Logs && source != model.log_source {
    @cmd.batch([
      load_logs(source, log_tail_of(model), emit),
      scroll_bottom_after_render("dsh-log-box"),
    ])
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
/// 这一行当前的备注（打开编辑框时预填它）。读不到就是空串 —— 编辑框从空白开始。
fn row_note(model : Model, id : String) -> String {
  match find_row(model.rows, id) {
    Some(row) => row.user_note
    None => ""
  }
}

///|
/// 备注的参数：{ profile, text }。text 用 json_text_literal 转义（备注是自由文本，
/// 里面什么字符都可能有）；空串是合法的 —— 契约里空串表示删掉那个文件。
/// 不给 trim：用户写的换行与行首空格是他自己的事，要不要拒由后端按上限判。
fn note_pairs(row : Row, text : String) -> Array[(String, String)] {
  match row.profile_name {
    Some(name) =>
      [("profile", json_text_literal(name)), ("text", json_text_literal(text))]
    None => []
  }
}

///|
/// 把若干 (键, 已渲染好的 JSON 值) 拼成 params 对象。空数组给空串 —— 调用方据此
/// 判定「这一行没有可用的目标」，在本地说清而不是发一个空 params 出去。
fn params_of(pairs : Array[(String, String)]) -> String {
  if pairs.length() == 0 {
    return ""
  }
  let buf = StringBuilder()
  buf.write_char('{')
  let mut first = true
  for pair in pairs {
    let (key, value) = pair
    if !first {
      buf.write_char(',')
    }
    buf.write_string(json_text_literal(key))
    buf.write_char(':')
    buf.write_string(value)
    first = false
  }
  buf.write_char('}')
  buf.to_string()
}

///|
/// 目标 profile 的参数。读不到目录名就给空数组：写动作一律以读数为准，
/// 不拿演示数据里那个名字去打真实的东西。
fn profile_pairs(row : Row) -> Array[(String, String)] {
  match row.profile_name {
    Some(name) => [("profile", json_text_literal(name))]
    None => []
  }
}

///|
/// 目标端口的参数（停止 / 重启按端口认）。
fn port_pairs(row : Row) -> Array[(String, String)] {
  match row.port_value {
    Some(port) => [("port", port.to_string())]
    None => []
  }
}

///|
/// 按行取动作目标：kind = "port" 取端口，其余取 profile。
fn params_for_row(model : Model, row_id : String, kind : String) -> String {
  match find_row(model.rows, row_id) {
    None => ""
    Some(row) =>
      if kind == "port" {
        params_of(port_pairs(row))
      } else {
        params_of(profile_pairs(row))
      }
  }
}

///|
/// 这一行对应的日志来源。
///
/// 日志来源的取值是 `instance:<实例 id>`，而卡片上的 id 是自己的口径
/// （运行中 `port:<端口>`、已停止 `profile:<名>`），两者不是一回事 ——
/// 所以这里按 instances 读数翻译，**不拼字符串**：拿端口或 profile 名去对，
/// 对上了才用那只实例的 id（日志接口只认白名单里的来源，拼错了它直接拒）。
/// 对上不止一只（同名 profile 起了多次）就取第一只，够用。
///
/// 返回 None = 这只 profile 现在没有在跑的实例：日志页的来源下拉只列运行中的实例，
/// 没有能读的实例日志可用。这时由调用方把这句话说清楚，不硬切过去。
fn log_source_for_row(model : Model, row : Row) -> String? {
  let facts = match model.instances {
    Some(instances) => instances.instances
    None => return None
  }
  for fact in facts {
    if matches_source_row(fact, row) {
      return Some("instance:" + fact.id)
    }
  }
  None
}

///|
/// 一只实例是不是这张卡对应的那一只：运行中按端口认，已停止按 profile 名认。
fn matches_source_row(fact : InstanceFact, row : Row) -> Bool {
  match row.port_value {
    Some(port) => fact.port == port
    None =>
      match (row.profile_name, fact.profile) {
        (Some(name), Some(used)) => used == name
        _ => false
      }
  }
}

///|
/// 打开工作目录 / 编辑配置：POST open-path。
///
/// 目标只有 profile 名与 kind 两个参数 —— **路径不由前端给**（契约里的硬要求），
/// 后端按枚举目标自己解析，前端连一个 path 字段都不拼。
/// 走 send_action 的同一条通道：这一行置忙、回执进 action_notice，
/// 失败时把后端给的 code 与 message 原样贴出来（not-found / io-error / not-authorized…），
/// 本地不放行、不假装打开成功。
fn open_path_action(
  model : Model,
  row_id : String,
  kind : String,
  label : String,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let pairs = match find_row(model.rows, row_id) {
    None => []
    Some(row) =>
      match row.profile_name {
        Some(name) => [
          ("profile", json_text_literal(name)),
          ("kind", json_text_literal(kind)),
        ]
        None => []
      }
  }
  send_action(
    { ..model, menu_open: "" },
    row_id,
    "open-path",
    label + " " + row_name(model, row_id),
    params_of(pairs),
    emit,
  )
}

///|
/// 打开 Web UI / 在新标签页打开：两处都开**带令牌的那一条地址**（webUrl），
/// 也就是 dsh 启动横幅里那条能直接过首次握手的地址。
///
/// webUrl 读不到时**一个标签页都不开**：裸地址打开就是一个 401 页面，
/// 「给了链接但用不了」比「说清为什么没有链接」更糟。这时把原因与裸地址一起给人 ——
/// 他从启动它的那个终端里抄 ?token=… 自己拼，比点进一个 401 再回头找原因快。
///
/// 开没开成要看 js_open_url 的返回值：被弹窗拦截也要说清，不报一句空的「已打开」。
fn open_web_ui(
  model : Model,
  row_id : String,
  label : String,
) -> (Model, @cmd.Cmd) {
  let row = match find_row(model.rows, row_id) {
    None => return (model, @cmd.none)
    Some(row) => row
  }
  match row.web_url {
    Some(url) => {
      let outcome = js_open_url(url)
      let (ok, tail) = if outcome == "ok" {
        (true, "已在新标签页打开带令牌的地址（能直接过握手，不是 401）")
      } else if outcome == "blocked" {
        (false, "浏览器把新标签页拦掉了（弹窗拦截）—— 地址是带令牌的那一条，可以自己去开")
      } else {
        (false, "打开新标签页失败（" + outcome + "）")
      }
      (
        {
          ..model,
          menu_open: "",
          act_notice: label + " " + row.name + "：" + tail + "。" + url + "（令牌来源：" +
            row.web_url_source + "）",
          act_notice_ok: ok,
        },
        @cmd.none,
      )
    }
    None => {
      let reason = if row.web_url_source == "" {
        "读不到带令牌的地址，后端也没给原因"
      } else {
        row.web_url_source
      }
      (
        {
          ..model,
          menu_open: "",
          act_notice: label + " " + row.name +
            "：读不到握手令牌，没有打开任何标签页 —— " + reason + "。裸地址 " + row.url +
            " 直接打开是 401；可以从启动它的那个终端里抄启动横幅里 ?token=… 的完整地址自己拼。",
          act_notice_ok: false,
        },
        @cmd.none,
      )
    }
  }
}

///|
/// 两条复制菜单：裸地址与带令牌的地址。
///
/// 复制的是读数里的原值（裸地址就是卡上那一行显示的、带令牌的就是 webUrl），
/// 前端不拼地址、不改写。成没成由剪贴板那一次调用的回执说了算（CopyDone），
/// 这里只负责把要复制的文本挑出来、没有内容时说清为什么。
fn copy_url_action(
  model : Model,
  row_id : String,
  label : String,
  with_token : Bool,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let row = match find_row(model.rows, row_id) {
    None => return (model, @cmd.none)
    Some(row) => row
  }
  let text = if with_token {
    match row.web_url {
      Some(url) => url
      None => ""
    }
  } else if row.url == "—" {
    ""
  } else {
    row.url
  }
  if text == "" {
    let why = if with_token {
      if row.web_url_source == "" {
        "读不到带令牌的地址"
      } else {
        "读不到带令牌的地址（" + row.web_url_source + "）"
      }
    } else {
      "这一行的读数里没有访问地址"
    }
    return (
      {
        ..model,
        menu_open: "",
        act_notice: label + " " + row.name + "：" + why + "，没有可复制的内容",
        act_notice_ok: false,
      },
      @cmd.none,
    )
  }
  (
    { ..model, menu_open: "", act_notice: "" },
    copy_cmd(label + " " + row.name, text, emit),
  )
}

///|
/// 剪贴板回执 → (成功?, 给用户看的一句话)。
/// 传输层给的是 { ok, how, error }：ok=true 时写出走的是哪条路，
/// ok=false 时把两个失败原因都带上（clipboard 的 reject 原因 + execCommand 的结果）。
fn parse_copy_result(text : String) -> (Bool, String) {
  let root = try @json.parse(text) catch {
    _ => return (false, "剪贴板调用返回的不是合法 JSON")
  }
  guard root is Json::Object(obj) else {
    return (false, "剪贴板调用返回的不是 JSON 对象")
  }
  if bool_field(obj, "ok") {
    let how = str_field(obj, "how")
    (true, if how == "" { "已写入剪贴板" } else { "已写入剪贴板（" + how + "）" })
  } else {
    let why = str_field(obj, "error")
    (false, if why == "" { "剪贴板写入失败，没有给出原因" } else { "剪贴板写入失败：" + why })
  }
}

///|
/// 一个写动作：发请求，并把这一行置成忙碌（同一行不会连点两次）。
/// 目标读不到就只在本地说一句，不发请求。
fn send_action(
  model : Model,
  id : String,
  action : String,
  label : String,
  params : String,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  if params == "" {
    (
      {
        ..model,
        act_notice: label +
          "：这一行的读数里没有可用的目标（profile 目录名或端口读不到），没有发请求",
        act_notice_ok: false,
      },
      @cmd.none,
    )
  } else {
    let busy = map_rows(model, id, fn(row) { { ..row, busy: true } })
    (
      { ..busy, act_notice: "" },
      action_cmd(id, action, label, action_body(action, params), emit),
    )
  }
}

///|
/// 删除的参数。契约：safety.deleteToTrash=false 时**必须**带 confirm=DELETE，否则 bad-params。
/// 设置还没读到（没打开过设置页）时按「可能要硬删」处理，也带上它 ——
/// 少带一次的代价是删不掉并弹一个 bad-params，多带一次的代价只是一个多余字段。
/// 明确读到 deleteToTrash=true（进回收站）时才不带。
fn delete_pairs(model : Model, row_id : String) -> Array[(String, String)] {
  let base = match find_row(model.rows, row_id) {
    None => []
    Some(row) => profile_pairs(row)
  }
  if base.length() == 0 {
    return base
  }
  if setting_bool_of(model, "safety.deleteToTrash") == Some(true) {
    base
  } else {
    let pairs = base.copy()
    pairs.push(("confirm", json_text_literal("DELETE")))
    pairs
  }
}

///|
/// 启动：先留在原分组显示等待态（状态点在动、三个按钮禁用），再按回执落定。
///
/// 等待态有下限（start_delay_ms）：真实请求可能 50ms 就回来了，但「启动中…」一闪而过
/// 比多等两秒更难用。回执与计时都到齐才收尾，收尾不等于宣布成功 ——
/// 成功的证据是重读 instances 之后那张真的运行中卡。
fn start_instance(model : Model, row : Row, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  let params = params_of(profile_pairs(row))
  let label = "启动 " + row.name
  if params == "" {
    return (
      {
        ..model,
        act_notice: label + "：读数里没有 profile 目录名，没有发请求",
        act_notice_ok: false,
      },
      @cmd.none,
    )
  }
  let busy = map_rows(model, row.id, fn(item) { { ..item, status: Starting, busy: true } })
  (
    {
      ..busy,
      act_pending: row.id,
      act_label: label,
      act_response: false,
      act_tick: false,
      act_ok: false,
      act_note: "",
      act_notice: "",
    },
    @cmd.batch([
      action_cmd(row.id, "start-instance", label, action_body("start-instance", params), emit),
      @cmd.delay(emit(StartTick(row.id)), start_delay_ms),
    ]),
  )
}

///|
/// 启动收尾：回执与计时都到齐才动。
fn finish_start(model : Model, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  if model.act_pending == "" || !model.act_response || !model.act_tick {
    return (model, @cmd.none)
  }
  let id = model.act_pending
  let label = model.act_label
  let ok = model.act_ok
  let note = model.act_note
  let cleared = map_rows(
    { ..model, act_pending: "", act_response: false, act_tick: false, act_label: "" },
    id,
    fn(row) { { ..row, busy: false, status: Stopped, port_note: "" } },
  )
  if ok {
    refresh_readings({ ..cleared, act_notice: label + "：" + note, act_notice_ok: true }, emit)
  } else {
    ({ ..cleared, act_notice: label + "失败：" + note, act_notice_ok: false }, @cmd.none)
  }
}

///|
/// 备注保存的回执。两条路分开：
///   成功 —— 关框（位置与触发元素都留着），重读 profiles，卡上那一行由读数给出；
///           提示条里那句 note 是后端写的「这次到底做了什么」。
///   失败 —— **框不关**，后端给的原因写进框内，用户改一改就能再存一次。
fn note_settled(
  model : Model,
  res : Result[String, Error],
  label : String,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let (ok, note) = interpret_http(res)
  let return_id = model.note_return
  let base = { ..model, note_saving: "" }
  if ok {
    let closed = {
      ..base,
      note_open: "",
      note_draft: "",
      note_error: "",
      act_notice: label + "：" + note,
      act_notice_ok: true,
    }
    let (next, cmd) = refresh_readings(closed, emit)
    (next, @cmd.batch([cmd, focus_after_render(return_id)]))
  } else {
    ({ ..base, note_error: note }, @cmd.none)
  }
}

///|
/// 写动作成功之后刷新读数：重发 profiles + instances。
/// 两份都先置回「未落地」再发 —— 否则先回来的那一份会拿着旧的另一份拼一次列表，
/// 而那时 built 已经是 true，后回来的那一份就白读了（卡上还是动作前的老样子）。
fn refresh_readings(model : Model, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  (
    { ..model, built: false, read_profiles: false, read_instances: false, read_console: false },
    @cmd.batch([load_readings(emit), load_console(emit)]),
  )
}

///|
/// 动作回执 → (成功?, 给用户看的一句话)。失败一律把后端给的码与消息带上，不吞。
fn interpret_http(res : Result[String, Error]) -> (Bool, String) {
  match res {
    Err(err) => (false, "请求没发出去（" + describe(err) + "）")
    Ok(text) => {
      let got = parse_http_result(text)
      if got.status == 0 {
        (false, "请求失败（" + got.transport_error + "）")
      } else if got.status >= 200 && got.status < 300 {
        match open_envelope(got.body) {
          Ok(data) => (true, success_note(data))
          Err(reason) =>
            (
              false,
              "HTTP " + got.status.to_string() + " · 响应不是约定的成功壳：" + reason,
            )
        }
      } else {
        (false, failure_note(got))
      }
    }
  }
}

///|
/// 成功回执里那句「这次到底发生了什么」：优先用 note，其次把 outcome 摊平。
fn success_note(data : Map[String, Json]) -> String {
  let note = str_field(data, "note")
  if note != "" {
    return note
  }
  match data.get("outcome") {
    Some(Json::Object(outcome)) => {
      let parts : Array[String] = []
      for entry in outcome.iter() {
        let (key, value) = entry
        parts.push(key + "=" + outcome_value_text(value))
      }
      if parts.length() > 0 {
        join_with(parts, " · ")
      } else {
        "完成（outcome 是空的）"
      }
    }
    Some(other) => outcome_value_text(other)
    None => "完成（回执里没有 note / outcome）"
  }
}

///|
fn outcome_value_text(value : Json) -> String {
  match value {
    Json::String(text) => text
    Json::Number(n, ..) => n.to_int().to_string()
    Json::True => "true"
    Json::False => "false"
    Json::Null => "null"
    other => other.stringify()
  }
}

///|
/// 失败回执：状态行 + 后端错误壳里的 code / message。
/// 后端还没提供接口时（例如 404 的空响应体）到这里也要说清「响应体不是约定的错误壳」。
fn failure_note(got : HttpResult) -> String {
  let head = http_status_text(got)
  let root = try @json.parse(got.body) catch {
    _ => return head + " · 响应体不是合法 JSON（后端可能还没提供这个接口）"
  }
  guard root is Json::Object(obj) else {
    return head + " · 响应外壳不是 JSON 对象"
  }
  match obj.get("error") {
    Some(Json::Object(err)) => {
      let code = str_field(err, "code")
      let message = str_field(err, "message")
      if code == "" && message == "" {
        head
      } else if code == "" {
        head + " · " + message
      } else if message == "" {
        head + " · " + code
      } else {
        head + " · " + code + "：" + message
      }
    }
    _ => head + " · 响应里没有 error 对象"
  }
}

// ── 设置页的状态转移 ────────────────────────────────────────

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
          tag_settings: fallback_tag("GET /api/local/settings " + reason),
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
            tag_settings: fallback_tag("GET /api/local/settings " + reason),
          },
          @cmd.none,
        )
      } else if got.status >= 200 && got.status < 300 {
        match parse_settings(got.body) {
          Ok(facts) => {
            let count = facts.values.length().to_string()
            (
              {
                ..base,
                settings: Some(facts),
                settings_status: got.status,
                settings_status_text: got.status_text,
                settings_error: "",
                settings_endpoint_missing: false,
                tag_settings: real_tag(
                  "GET /api/local/settings 读到 " + count + " 个键 · " + local_time_now() + " 读取",
                ),
                archived_open: default_archive_open(base, facts),
              },
              @cmd.none,
            )
          }
          Err(reason) => {
            let detail = http_status_text(got) + " · 响应不是约定的成功壳：" + reason
            (
              {
                ..base,
                settings: None,
                settings_status: got.status,
                settings_status_text: got.status_text,
                settings_error: detail,
                settings_endpoint_missing: false,
                tag_settings: fallback_tag("GET /api/local/settings " + detail),
              },
              @cmd.none,
            )
          }
        }
      } else {
        let missing = got.status == 404 || got.status == 501
        let detail = (if missing {
          "后端还没有这个接口。"
        } else {
          "后端返回了错误。"
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
              "GET /api/local/settings → " + http_status_text(got),
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
            {
              ..model,
              settings_draft: drop_draft(model.settings_draft, key),
              settings_feedback: def.label + " 没保存：" + reason,
              settings_feedback_ok: false,
            },
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
    Some(def) =>
      (
        {
          ..model,
          settings_saving: key,
          settings_pending: Some(value),
          settings_feedback: "正在保存 " + def.label + " …",
          settings_feedback_ok: true,
        },
        settings_put_cmd(key, settings_put_body(key, value), emit),
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
    return (
      {
        ..model,
        settings_saving: "",
        settings_pending: None,
        settings_draft: drafts,
        settings_feedback: label + " 没保存：" + note,
        settings_feedback_ok: false,
      },
      set_control_after_render(setting_control_id(key), back),
    )
  }
  let facts = merge_saved(model, key, res)
  let value_text = match model.settings_pending {
    Some(value) => setting_value_text(value)
    None => "已保存"
  }
  (
    {
      ..model,
      settings: Some(facts),
      settings_saving: "",
      settings_pending: None,
      settings_draft: drafts,
      settings_feedback: label + " 已保存：" + value_text + "（来源 文件）",
      settings_feedback_ok: true,
      tag_settings: real_tag(
        "PUT /api/local/settings " + key + " · " + local_time_now() + " 写入",
      ),
    },
    @cmd.none,
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
    ConsoleText(res) => {
      // 这一份读不到不算致命：卡片上的「由本控制台启动」与归档区会缺，别的读数照旧。
      // read_console 照样置 true —— 它挡住的是「列表拼装」，不该为一份读数卡住整页。
      let time = local_time_now()
      let next = match res {
        Ok(text) =>
          match parse_console(text) {
            Ok(facts) => {
              let archived = facts.archive.length()
              let registered = facts.runtime.length()
              {
                ..model,
                console: Some(facts),
                console_error: "",
                tag_archived: real_tag(
                  "GET /api/local/console 读 " + facts.archive_path + "：" +
                  archived.to_string() + " 条归档记录；runtime.json 里 " +
                  registered.to_string() + " 条登记 · " + time + " 读取",
                ),
                read_console: true,
              }
            }
            Err(reason) =>
              {
                ..model,
                console: None,
                console_error: reason,
                tag_archived: fallback_tag("/api/local/console 读取失败：" + reason),
                read_console: true,
              }
          }
        Err(err) => {
          let reason = "本地只读接口不可达（" + describe(err) + "）"
          {
            ..model,
            console: None,
            console_error: reason,
            tag_archived: fallback_tag("/api/local/console 读取失败：" + reason),
            read_console: true,
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
            load_logs(model.log_source, log_tail_of(model), emit),
            scroll_bottom_after_render("dsh-log-box"),
          ])
        }
        ({ ..next, log_loaded: true }, cmd)
      } else if page is Settings {
        // 设置是懒加载：只在第一次进设置页时发 GET。
        // 别在应用启动时顺手读它 —— 后端还没提供这个接口时，
        // 每次打开总览都会在控制台里留一条 404，而「控制台零问题」是验收项。
        if model.settings_loaded || model.settings_loading {
          (next, @cmd.none)
        } else {
          (
            { ..next, settings_loading: true, settings_error: "" },
            settings_get_cmd(emit),
          )
        }
      } else {
        (next, @cmd.none)
      }
    }
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
                  "停止 " + row.name,
                  params_of(port_pairs(row)),
                  emit,
                )
              } else if row.status is Stopped {
                start_instance(model, row, emit)
              } else {
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
                "重启 " + row.name,
                params_of(port_pairs(row)),
                emit,
              )
              (
                { ..next, restarting: id },
                @cmd.batch([cmd, @cmd.delay(emit(RestartTick), restart_lock_ms)]),
              )
            }
          }
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
        // 打开编辑框是纯前端的事，真正的写动作在保存那一步（NoteConfirm）
        Note => (model, emit(NoteOpen(id)))
        Archive =>
          send_action(
            model,
            id,
            "archive-profile",
            "归档 " + row_name(model, id),
            params_for_row(model, id, "profile"),
            emit,
          )
        Unarchive =>
          send_action(
            model,
            id,
            "unarchive-profile",
            "取消归档 " + row_name(model, id),
            params_for_row(model, id, "profile"),
            emit,
          )
        Fork =>
          send_action(
            model,
            id,
            "fork-profile",
            "派生 " + row_name(model, id),
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
                Some(source) => (
                  {
                    ..model,
                    page: Logs,
                    menu_open: "",
                    log_source: source,
                    // 这是用户自己挑的来源，rebuild 的缺省推导不许再压过它
                    log_user_picked: true,
                    log_loaded: true,
                  },
                  @cmd.batch([
                    load_logs(source, log_tail_of(model), emit),
                    scroll_bottom_after_render("dsh-log-box"),
                  ]),
                )
                // 没有在跑的实例可读：留在总览页把原因说清，不切到一个空日志页
                None => (
                  {
                    ..model,
                    menu_open: "",
                    act_notice: "查看日志 " + row.name +
                      "：这只 profile 现在没有在跑的实例，没有 instance:<id> 这个来源可读",
                    act_notice_ok: false,
                  },
                  @cmd.none,
                )
              }
          }
        // 打开 Web UI（卡上的主按钮）与「在新标签页打开」（行菜单）是同一件事：
        // 开带令牌的 webUrl。读不到令牌就不开标签页，把原因与裸地址说清（见 open_web_ui）。
        OpenUi => open_web_ui(model, id, "打开 Web UI")
        Tab => open_web_ui(model, id, "在新标签页打开")
        // 两条复制：裸地址（卡上「访问地址」那一行的原值）与带令牌的地址（webUrl）
        CopyUrl => copy_url_action(model, id, "复制访问地址", false, emit)
        CopyTokenUrl => copy_url_action(model, id, "复制带令牌的地址", true, emit)
        // 打开工作目录 / 编辑配置：都走 POST open-path，只有 kind 不同（cli 端不给路径）
        Dir => open_path_action(model, id, "dir", "打开工作目录", emit)
        Config => open_path_action(model, id, "config", "编辑配置", emit)
        // 没有兜底分支了：ActionKey 的每一项上面都接上了（以前那行兜底会把这个事实藏起来）
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
    // 启动的展示下限到了：等回执一起收尾（收尾里不伪造成「运行中」——
    // 真的起来了的那张卡由重读 instances 给出）
    StartTick(id) =>
      if model.act_pending == id {
        finish_start({ ..model, act_tick: true }, emit)
      } else {
        (model, @cmd.none)
      }
    RestartTick => ({ ..model, restarting: "" }, @cmd.none)
    RenameInput(text) => ({ ..model, rename_draft: text }, @cmd.none)
    // 改名不再是改一个显示字符串：它 POST rename-profile，改的是磁盘上的目录名。
    // 对话框照旧先关（语义没变），结果由提示条给出。
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
          "重命名 " + old + " → " + draft,
          params,
          emit,
        )
        (next, @cmd.batch([cmd, focus_after_render(return_id)]))
      }
    }
    RenameCancel => (
      { ..model, rename_id: "", rename_draft: "" },
      focus_after_render(model.rename_return),
    )
    // 编辑备注：与重命名同一套（预填、Esc 取消、关闭后焦点回触发元素）。
    // 焦点落在备注框、光标推到文末 —— 这里是接着改，不是整段覆盖。
    NoteOpen(id) => (
      {
        ..model,
        note_open: id,
        note_draft: row_note(model, id),
        note_return: trigger_id(id),
        note_error: "",
      },
      focus_end_after_render("dsh-note-input"),
    )
    NoteInput(text) => ({ ..model, note_draft: text, note_error: "" }, @cmd.none)
    // 保存失败**不关框**：后端给的原因（bad-params / io-error / not-authorized…）写在框里，
    // 用户改一改就能再存一次。关掉的话那句原因就成了一闪而过的提示条。
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
                note_error: "这一行的读数里没有 profile 目录名，保存不了 —— 没有目标就不发请求",
              },
              @cmd.none,
            )
          } else {
            // 这一行不置忙：备注保存时卡片本身还能用，忙碌态只锁保存键
            let label = "保存备注 " + row.name
            (
              { ..model, note_saving: row.id, note_error: "", act_notice: "" },
              action_cmd(
                row.id,
                "set-profile-note",
                label,
                action_body("set-profile-note", params_of(pairs)),
                emit,
              ),
            )
          }
        }
      }
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
    // 删除也是真实动作：POST delete-profile。删掉的行由重读 profiles 之后消失，
    // 不在这里先手动抹掉 —— 后端失败时列表不该少一行。
    DeleteConfirm => {
      let target = model.confirm_id
      let return_id = model.confirm_return
      let (next, cmd) = send_action(
        { ..model, confirm_id: "" },
        target,
        "delete-profile",
        "删除 " + row_name(model, target),
        params_of(delete_pairs(model, target)),
        emit,
      )
      (next, @cmd.batch([cmd, focus_after_render(return_id)]))
    }
    DeleteCancel => (
      { ..model, confirm_id: "" },
      focus_after_render(model.confirm_return),
    )
    // 手动折过就记一笔：ui.archiveOpenByDefault 之后不再覆盖用户的选择
    ToggleArchived => (
      { ..model, archived_open: !model.archived_open, archived_user_toggled: true },
      @cmd.none,
    )
    LogSourcePicked(value) => (
      { ..model, log_source: value, log_user_picked: true, log_loaded: true },
      @cmd.batch([
        load_logs(value, log_tail_of(model), emit),
        scroll_bottom_after_render("dsh-log-box"),
      ]),
    )
    LogRefresh => (
      model,
      @cmd.batch([
        load_logs(model.log_source, log_tail_of(model), emit),
        scroll_bottom_after_render("dsh-log-box"),
      ]),
    )
    // ── 设置页 ─────────────────────────────────────────────
    SettingsText(res) => settings_loaded_state(model, res)
    SettingsRetry => (
      { ..model, settings_loading: true, settings_error: "", settings_loaded: false },
      settings_get_cmd(emit),
    )
    SettingsGroupPicked(id) => ({ ..model, settings_group: id }, @cmd.none)
    SettingDraft(key, text) => (
      { ..model, settings_draft: put_draft(model.settings_draft, key, text) },
      @cmd.none,
    )
    SettingCommit(key, text) => commit_setting(model, key, text, emit)
    SettingToggle(key, next) => commit_setting_value(model, key, VBool(next), emit)
    SettingsSaved(key, res) => settings_saved_state(model, key, res)
    // ── 写动作的回执 ───────────────────────────────────────
    // 启动走「回执 + 展示下限」两条腿；其余动作拿到回执就落定，
    // 成功的动作一律重读 profiles / instances（刷新的是读数，不是弹个提示）。
    HttpDone(row_id, action, label, res) => {
      let (ok, note) = interpret_http(res)
      if action == "set-profile-note" {
        note_settled(model, res, label, emit)
      } else if action == "start-instance" && model.act_pending == row_id {
        finish_start(
          { ..model, act_response: true, act_ok: ok, act_note: note, act_label: label },
          emit,
        )
      } else {
        let cleared = map_rows(model, row_id, fn(row) { { ..row, busy: false } })
        if ok {
          // 本地不猜结果：归档记录与运行时登记都在后端的读数里，
          // 重读 console / profiles / instances 之后界面自己会变
          refresh_readings(
            { ..cleared, act_notice: label + "：" + note, act_notice_ok: true },
            emit,
          )
        } else {
          (
            { ..cleared, act_notice: label + "失败：" + note, act_notice_ok: false },
            @cmd.none,
          )
        }
      }
    }
    // 剪贴板回执：只说这一枪的真实结局（写进去了 / 两条路都失败），
    // 复制成功不改任何读数，所以这里不刷新列表。
    CopyDone(label, res) => {
      let (ok, note) = match res {
        Ok(text) => parse_copy_result(text)
        Err(err) => (false, "剪贴板调用没发出去（" + describe(err) + "）")
      }
      (
        { ..model, act_notice: label + "：" + note, act_notice_ok: ok },
        @cmd.none,
      )
    }
    Noop => (model, @cmd.none)
  }
}
