// 应用入口与更新循环。
//
// 三个只读接口在 init 里一次发出去；解析放在 update 里，失败的原因（不是 JSON / ok=false /
// 接口不可达）原样进 model，界面直接展示。三个读数都落地之后才拼一次实例列表 ——
// 与 Vue 版 Promise.all 之后再拼同一口径。
//
// 启动时先看地址栏（route.mbt）：深链进来的 /settings/process 直接落在设置的那一组上，
// 认不出来的地址回落并留一句说明。popstate 的监听在这里挂一次，之后由 update 接力。

///|
pub fn app() -> @rabbita.Val[@html.Html] {
  let (model, emit) = @rabbita.create_state_with_init(
    init=fn(emit) {
      let route = parse_route(js_location_url())
      let (model, enter) = route_into(initial_model(), route, emit)
      // 地址认不出来时把它改写回落后的那一条：地址栏与页面必须指着同一处，
      // 但这一步不是用户走的（不写历史，退回上一页还是他自己那一步）
      let settle = if route.notice == "" {
        @cmd.none
      } else {
        replace_route(route_url(model.page, model.settings_group, model.log_source))
      }
      (model, @cmd.batch([load(emit), enter, listen_popstate(emit), settle]))
    },
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
/// 按一条路由进入对应的页面：地址里写着的页面状态进 model，该页自己要拉起的那份读数在这里发。
///
/// 启动（init）与前进 / 后退（RouteChanged）都只走这一条 —— 两边各写一遍「进日志页要读一次
/// 日志、进设置页要读一次设置」迟早会分叉，而分叉出来的是「刷新之后这一页没数据」。
fn route_into(model : Model, route : Route, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  let base = {
    ..model,
    page: route.page,
    // 分组只在地址真写着设置页时才进 model：切到别的页面不该把用户记住的那一组抹掉
    settings_group: if route.page is Settings { route.group } else { model.settings_group },
    route_notice: route.notice,
  }
  match route.page {
    Logs => {
      // 地址里写了来源就按它读（并记成「用户自己挑的」，读数回来不许压过它）；
      // 没写就按默认来源推导 —— 与总览页拼列表时用的是同一个口径。
      let (picked, source) = match route.source {
        Some(value) => (true, value)
        None => (false, default_log_source(base))
      }
      let next = { ..base, log_source: source, log_user_picked: picked }
      // 内容已经是这个来源的就只滚到底（后退回到同一页不必重读）
      if next.log_source_read == source {
        (next, scroll_bottom_after_render("dsh-log-box"))
      } else {
        start_logs(next, source, emit)
      }
    }
    Settings =>
      // 设置是懒加载：只在真进设置页时发 GET。
      // 别在应用启动时顺手读它 —— 后端还没提供这个接口时，
      // 每次打开总览都会在控制台里留一条 404，而「控制台零问题」是验收项。
      if model.settings_loaded || model.settings_loading {
        (base, @cmd.none)
      } else {
        ({ ..base, settings_loading: true, settings_error: "" }, settings_get_cmd(emit))
      }
    Trash =>
      // 回收站是会变的（另一个标签页里删了东西、别处恢复了）：进来就重读一次控制台读数。
      // 只重发这一份，别的读数不动 —— 它读不到时的样子由这一页自己分档说清。
      (base, load_console(emit))
    _ => (base, @cmd.none)
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
      profile_rows(facts.profiles, model.runtime, dsh_home_of(model), live_instances, model.console)
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
  // 抽屉指着的那一行还在不在：重建之后行可能已经不是原来那一条了（停掉的实例变成
  // profile 行、归档把它移出分组、profile 被删掉）。行没了就把抽屉收掉 ——
  // 留一个指向不存在的行的 drawer_id，页面上会多出一个没有内容的浮层挡住底下。
  let drawer = if model.drawer_id == "" {
    ""
  } else {
    match find_row(rows, model.drawer_id) {
      Some(_) => model.drawer_id
      None => ""
    }
  }
  let source = if model.log_user_picked {
    model.log_source
  } else {
    default_log_source(model)
  }
  // 日志页已经开着、而默认来源刚刚才定下来：补一次读取，别让下拉与内容对不上。
  // 这一步是读数推出来的、不是用户走的：地址栏跟着改写（replace_route），不写新历史。
  let reload = model.page is Logs && source != model.log_source
  let cmd = if reload {
    @cmd.batch([
      replace_route(route_url(Logs, model.settings_group, source)),
      load_logs(source, log_tail_of(model), emit),
      scroll_bottom_after_render("dsh-log-box"),
    ])
  } else {
    @cmd.none
  }
  let next = {
    ..model,
    rows,
    drawer_id: drawer,
    built: true,
    log_source: source,
    // 刚补发了一次读取：加载态立起来，回执到了再放下去
    log_loading: if reload { true } else { model.log_loading },
  }
  // 列表拼好之后还有一件跟读数有关的事要办：启动成功的那只实例，
  // 它在点击那一栈里占下的标页正等着带令牌的地址（见 fill_start_tab）
  let (filled, waiting) = fill_start_tab(next, emit)
  (filled, @cmd.batch([cmd, waiting]))
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
  verb : String,
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
    model,
    row_id,
    "open-path",
    row_name(model, row_id),
    verb,
    params_of(pairs),
    emit,
  )
}

///|
/// js_open_url（卡上的「打开 Web UI」/ 菜单的「在新标签页打开」）与提示条里那颗
/// 「打开 Web UI」共用的结局口径 → (成没成, 给用户看的一句话)。
/// 「被浏览器拦了」与「打开出错」分开说：这是两件事，处理办法也不一样。
fn open_outcome_text(outcome : String) -> (Bool, String) {
  if outcome == "ok" {
    (true, "已在新标签页打开带令牌的地址（能直接过握手，不是 401）")
  } else if outcome == "blocked" {
    (false, "没能打开：浏览器把新标签页拦掉了（弹窗拦截）—— 地址是带令牌的那一条，可以自己去开")
  } else {
    (false, "没能打开（" + outcome + "）")
  }
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
) -> (Model, @cmd.Cmd) {
  let row = match find_row(model.rows, row_id) {
    None => return (model, @cmd.none)
    Some(row) => row
  }
  match row.web_url {
    Some(url) => {
      let (ok, tail) = open_outcome_text(js_open_url(url))
      (
        {
          ..model,
          act_notice: row.name + " 的 Web UI " + tail + "。地址 " + url + "（令牌来源：" +
            row.web_url_source + "）",
          act_notice_ok: ok,
        },
        @cmd.none,
      )
    }
    None => {
      let reason = if row.web_url_source == "" {
        "读不到带令牌的地址，也没有说明原因"
      } else {
        row.web_url_source
      }
      (
        {
          ..model,
          act_notice: row.name + " 的 Web UI 没有打开：读不到握手令牌，一个标签页都没开 —— " +
            reason + "。裸地址 " + row.url +
            " 直接打开会被挡在门外；可以从启动它的那个终端里，把启动横幅里带令牌的完整地址抄过来。",
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
  what : String,
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
        act_notice: row.name + " 的" + what + "没能复制：" + why + "，没有可复制的内容",
        act_notice_ok: false,
      },
      @cmd.none,
    )
  }
  (
    { ..model, act_notice: "" },
    copy_cmd(row.name + " 的" + what, text, emit),
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
    (true, if how == "" { "已写入剪贴板。" } else { "已写入剪贴板（" + how + "）。" })
  } else {
    let why = str_field(obj, "error")
    (
      false,
      if why == "" { "没能写进剪贴板，也没给出原因。" } else { "没能写进剪贴板：" + why + "。" },
    )
  }
}

///|
/// 这一行的 DSH_HOME：卡上那一格就是它（运行中的卡是那一只实例自己的，已停止的卡是
/// 控制台自己用的）。读不到（演示数据里的「—」）就不编，返回空串让调用方说清。
fn dev_home_of(model : Model, row : Row) -> String {
  if row.home != "" && row.home != "—" {
    return row.home
  }
  let fallback = dsh_home_of(model)
  if fallback == "—" {
    ""
  } else {
    fallback
  }
}

///|
/// 「复制开发指令」要复制的那段文本：一份**给另一个会话**的任务说明，粘过去就能用。
///
/// 为什么是「复制一段话」而不是「就地开个开发会话」：说明要被粘到**别的** profile 的会话里，
/// 让那边的 agent 针对这一只 profile 开发。开发会话与开发对象分开，改坏了也是坏在隔离的
/// 那一份上，主线不受影响 —— 这就是使用者要的稳妥隔离。
///
/// 五样缺一不可（缺哪样，粘过去那边都得回来问）：
///   1. profile 名；2. 它在磁盘上的目录；3. DSH_HOME；4. 起它做验证的命令；5. 只改这一份的约束。
/// 路径一律从当前读数推（目录 = <DSH_HOME>/profiles/<名>，与后端 profile_fs 同一口径），
/// 前端不另编一份路径 —— 编出来的路径粘过去就是个打不开的目录。
///
/// 起法与控制台的「启动」逐项对齐（见后端 actions/instance.mbt 的 start_instance）：
/// 它在 <profile 目录> 下、带着 DSH_HOME 起 dsh --profile <名> --no-open --port <端口>。
/// 命令里那个 8400 是 instance.basePort 的**缺省起点**（控制台也是从这一项往后找第一个
/// 空闲端口），正文里同时写明它可以换成任何一个空闲端口 —— 写死一个数而不说这句，
/// 端口被占时那条命令就是个起不来的命令。
fn dev_instruction_text(model : Model, row : Row, name : String) -> String {
  let home = dev_home_of(model, row)
  if home == "" {
    return ""
  }
  let dir = home + "/profiles/" + name
  let head = "【给另一个会话的插件开发任务】请在你当前这个会话里，针对下面这一只 profile 做开发，" +
    "不要切进它自己的会话来改。这段说明由 DSH 控制台的「复制开发指令」生成，粘过来直接可用。\n\n"
  let facts = "开发对象：profile「" + name + "」\n" +
    "它在磁盘上的目录：" + dir + "\n" +
    "DSH_HOME：" + home + "\n\n"
  let start = "起它做验证（与在控制台里点这只 profile 的「启动」等价）：\n" +
    "  cd " + dir + "\n" +
    "  DSH_HOME=" + home + " dsh --profile " + name + " --no-open --port 8400\n" +
    "  （8400 换成任何一个空闲端口都行；控制台自己也是从设置里的端口起点往后找第一个空闲的）\n\n"
  let rules = "约束（这一条是隔离的全部意义，务必守住）：\n" +
    "1. 只改 " + dir + " 这一份下的文件；\n" +
    "2. 不要动主线的 profile，也不要动别的 profile，各是各的一份；\n" +
    "3. 改完按上面那条命令把它起一次，确认这一份真能起来。"
  head + facts + start + rules
}

///|
/// 「复制开发指令」这一枪：文本现拼（见 dev_instruction_text），成没成由剪贴板那一次调用的
/// 回执说了算（CopyDone）。拼不出文本时先在本地说清原因，**不往剪贴板里塞一段缺斤少两的说明** ——
/// 那样粘过去那边还得回来问，比没复制更费事。
fn copy_dev_action(model : Model, row_id : String, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  let row = match find_row(model.rows, row_id) {
    None => return (model, @cmd.none)
    Some(row) => row
  }
  let name = match row.profile_name {
    Some(name) => name
    None => ""
  }
  let text = if name == "" {
    ""
  } else {
    dev_instruction_text(model, row, name)
  }
  if text == "" {
    let why = if name == "" {
      "这一行的读数里没有 profile 目录名"
    } else {
      "这一行的读数里没有 DSH_HOME"
    }
    return (
      {
        ..model,
        act_notice: row.name + " 的开发指令没能复制：" + why + "，拼不出可粘的说明",
        act_notice_ok: false,
      },
      @cmd.none,
    )
  }
  ({ ..model, act_notice: "" }, copy_cmd(row.name + " 的开发指令", text, emit))
}

///|
/// 一个写动作：发请求，并把这一行置成忙碌（同一行不会连点两次）。
/// 目标读不到就只在本地说一句，不发请求。
///
/// name 是这一行在界面上的名字（谁），verb 是这一步做了什么（「停止」）：
/// 回执按这两个词组句（见 action_receipt）。**不在这里拼「动作名 + 名字」那种标签** ——
/// 它以前被贴在提示条句首，读起来像机翻。
fn send_action(
  model : Model,
  id : String,
  action : String,
  name : String,
  verb : String,
  params : String,
  emit : @cmd.Emit[Msg],
  confirm? : String = "",
) -> (Model, @cmd.Cmd) {
  if params == "" {
    (
      {
        ..model,
        act_notice: name + " " + verb +
          "没执行：这一行的读数里没有可用的目标（profile 目录名或端口读不到）",
        act_notice_ok: false,
      },
      @cmd.none,
    )
  } else {
    let busy = map_rows(model, id, fn(row) { { ..row, busy: true } })
    (
      { ..busy, act_notice: "" },
      action_cmd(
        id,
        action,
        name,
        verb,
        if confirm == "" {
          action_body(action, params)
        } else {
          // 二次确认串在**顶层**（契约第一节的 destructive 要求），不在 params 里
          action_body_with_confirm(action, params, confirm)
        },
        emit,
      ),
    )
  }
}

///|
/// 删除的参数：只有 profile 这一项。
///
/// 二次确认串**不在这里** —— 它在 body 顶层，由 delete_confirm_of 给出、走
/// action_body_with_confirm。以前那个串被塞进 params，而后端读的是顶层，
/// 结果是硬删永远以 bad-params 告终（实测复现过 ✗）。
fn delete_pairs(model : Model, row_id : String) -> Array[(String, String)] {
  match find_row(model.rows, row_id) {
    None => []
    Some(row) => profile_pairs(row)
  }
}

///|
/// 删除要不要带二次确认串，带的话是什么。
///
/// 契约第一节：safety.deleteToTrash=false 时删除是硬删，**body 顶层**必须带 "confirm":"DELETE"。
/// 读不到删除方式时按「可能要硬删」处理，也带上它 —— 少带一次的代价是删不掉并弹一个 bad-params，
/// 多带一次只是一个多余字段（进回收站那条路后端根本不看它）。
///
/// 这个串走 action_body_with_confirm（放顶层），不再塞进 params：
/// 后端是从顶层读的（handle_action 里的 json_field(json, "confirm")），
/// 塞进 params 的结果是硬删永远以 bad-params 告终 —— 这条实测复现过 ✗
fn delete_confirm_of(model : Model) -> String {
  if delete_to_trash_of(model) == Some(true) {
    ""
  } else {
    "DELETE"
  }
}

///|
/// 回收站条目对应的 profile 名。
///
/// 恢复 / 彻底删除的提示条里用得到：目录名（zz-trash-a-1792071553106）是磁盘上的东西，
/// 提示条该说人话（zz-trash-a）。读数里没有这一条时退回目录名 —— 不编一个名字出来。
fn trash_profile_of(model : Model, dir : String) -> String {
  match model.console {
    None => dir
    Some(facts) => {
      let mut found = dir
      for entry in facts.trash {
        if entry.dir == dir {
          found = entry.profile
        }
      }
      found
    }
  }
}

///|
/// 成功回执里的 outcome 对象。回执不是约定的形状就给 None ——
/// 拿不到结构就退回通用说法，不猜、也不编一个结果出来。
fn outcome_of(res : Result[String, Error]) -> Map[String, Json]? {
  let raw = match res {
    Err(_) => return None
    Ok(text) => text
  }
  let got = parse_http_result(raw)
  match open_envelope(got.body) {
    Err(_) => None
    Ok(data) => Some(obj_field(data, "outcome"))
  }
}

///|
/// 后端回执原文 → 悬停补充。正文只说人话，机器口径（pid=… / code=…）收在这里。
fn backend_hint(note : String) -> String {
  if note == "" {
    ""
  } else {
    "回执原文：" + note
  }
}

///|
/// 回收站条目的大小：文件数与体积。读不到就照实说读不到，不写 0。
fn outcome_size_text(outcome : Map[String, Json]) -> String {
  let files = int_field(outcome, "files")
  let bytes = num_field(outcome, "bytes")
  let base = trash_count_text(files) + " | " + trash_size_text(bytes)
  match (files, bytes) {
    (Some(_), Some(_)) => base
    _ => {
      let source = str_field(outcome, "sizeSource")
      if source == "" {
        base
      } else {
        base + "（" + source + "）"
      }
    }
  }
}

///|
/// 删除回执：正文只回答「删了会怎样、能不能捞回来」，并指路回收站；
/// 路径 / mode / hardDeleted 这些是实现细节，收进悬停，不许摊在正文上 ✗
///
/// 读不出 mode 就退回一句通用的（name 是这一行在界面上的名字），
/// 不拿一个空 mode 去编「这一版认不出这个值」。
fn delete_receipt(name : String, outcome : Map[String, Json]?) -> (String, String) {
  let outcome = match outcome {
    None => return (name + " 已删除。", "")
    Some(outcome) => outcome
  }
  let profile = str_field(outcome, "profile")
  let who = if profile == "" { name } else { profile }
  let mode = str_field(outcome, "mode")
  if mode == "" {
    return (who + " 已删除。", "")
  }
  let dir = str_field(outcome, "dir")
  let trash_path = str_field(outcome, "trashPath")
  let hard = bool_field(outcome, "hardDeleted")
  let text = if mode == "trash" {
    who + " 已移入回收站，可以从「回收站」里恢复。"
  } else if mode == "hard-delete" {
    who + " 已删除，无法恢复。"
  } else {
    who + " 已删除（回执里的 mode 是「" + mode + "」，这一版认不出这个值）。"
  }
  let hint = "profile=" + profile + " | dir=" + dir + " | mode=" + mode + " | trashPath=" +
    (if trash_path == "" { "（硬删，没有回收站落点）" } else { trash_path }) +
    " | hardDeleted=" + (if hard { "true" } else { "false" })
  (text, hint)
}

///|
/// 恢复 / 彻底删除的回执：正文一句话说完，文件数 / 体积 / 路径收进悬停。
/// 后端这两条 note 里在括号里堆了数字（「…（108 个文件 · 526825 字节），无法恢复」），
/// 摊在正文上就是生硬；悬停里照旧能看到，一个字都没丢。
/// 返回空串 = 回执里没有 outcome，调用方退回通用说法。
fn trash_receipt(
  action : String,
  name : String,
  outcome : Map[String, Json]?,
) -> (String, String) {
  let outcome = match outcome {
    None => return ("", "")
    Some(outcome) => outcome
  }
  let profile = str_field(outcome, "profile")
  let who = if profile == "" { name } else { profile }
  if action == "restore-from-trash" {
    let to = str_field(outcome, "restoredTo")
    let hint = outcome_size_text(outcome) + (if to == "" { "" } else { " | 恢复到 " + to })
    (who + " 已恢复，回到 profile 列表里。", hint)
  } else {
    let path = str_field(outcome, "path")
    let hint = outcome_size_text(outcome) + (if path == "" { "" } else { " | 原路径 " + path })
    (who + " 已彻底删除。", hint)
  }
}

///|
/// 动作回执：谁 + 做了什么 + 结果。
///
/// **不让调用方拼「动作名 + 名字」那种标签**：它以前被贴在提示条句首
/// （label + "：" + 后端那句话），读起来像机翻，同一个名字还会在同一句里出现两遍 ✗
/// 正文只讲人话；后端回执原文与里面的数字、路径一并收进悬停 ✓
fn action_receipt(
  action : String,
  name : String,
  verb : String,
  note : String,
  res : Result[String, Error],
) -> (String, String) {
  let outcome = outcome_of(res)
  if action == "delete-profile" {
    return delete_receipt(name, outcome)
  }
  // 打开工作目录 / 打开配置：**到底是谁去开的，控制台不知道** —— xdg-open 按它自己的
  // 关联挑程序（目录可能是文件管理器，配置可能是 $EDITOR 里配的那一个）。
  // 所以正文只说「本机默认程序」，不猜一个具体的名字出来 ✗
  // 真正用了哪个（opener + pid）在后端回执里，照旧收进悬停。
  if action == "open-path" {
    return (name + " 已用本机默认程序" + verb + "。", backend_hint(note))
  }
  if action == "restore-from-trash" || action == "purge-trash-item" {
    let (text, hint) = trash_receipt(action, name, outcome)
    if text != "" {
      return (text, hint)
    }
  }
  // 改名与派生的结果里带着一个新名字：读得到就写进句子，读不到只说做了什么
  if action == "rename-profile" || action == "fork-profile" {
    let new_name = match outcome {
      Some(outcome) => str_field(outcome, "newName")
      None => ""
    }
    if new_name != "" {
      let text = if action == "rename-profile" {
        name + " 已改名为 " + new_name + "。"
      } else {
        name + " 已派生出 " + new_name + "。"
      }
      return (text, backend_hint(note))
    }
  }
  let text = if action == "fork-profile" {
    name + " 已派生出一份新 profile。"
  } else {
    name + " 已" + verb + "。"
  }
  (text, backend_hint(note))
}

///|
/// 备注保存的回执：清空与写入是两件事，后端在 outcome.removed 里说了；说了就照它说。
fn note_receipt(name : String, note : String, res : Result[String, Error]) -> (String, String) {
  let removed = match outcome_of(res) {
    Some(outcome) => bool_field(outcome, "removed")
    None => false
  }
  let text = if removed {
    name + " 的备注已清空。"
  } else {
    name + " 的备注已保存。"
  }
  (text, backend_hint(note))
}

///|
/// 占下的标页没有下文了（状态在点击与处理之间翻了、或那一行已经不在列表里）：
/// 当场关掉它。开着的白页比没开更糟 —— 用户会以为启动成功了。
fn close_held_tab(profile : String, tab : String) -> Unit {
  if tab == "held" && profile != "" {
    ignore(js_tab_close(profile))
  }
}

///|
/// 启动：先留在原分组显示等待态（状态点在动、三个按钮禁用），再按回执落定。
///
/// 等待态有下限（start_delay_ms）：真实请求可能 50ms 就回来了，但「启动中…」一闪而过
/// 比多等两秒更难用。回执与计时都到齐才收尾，收尾不等于宣布成功 ——
/// 成功的证据是重读 instances 之后那张真的运行中卡。
///
/// tab 是点击那一栈里同步开的占位标页的结局（见 view_overview 的 start_click）：
/// 启动成功之后由 fill_start_tab 把带令牌的地址填进去，失败就在收尾里关掉。
fn start_instance(
  model : Model,
  row : Row,
  profile : String,
  tab : String,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let params = params_of(profile_pairs(row))
  let name = row.name
  if params == "" {
    return (
      {
        ..model,
        act_notice: name + " 启动没执行：读数里没有 profile 目录名",
        act_notice_ok: false,
      },
      @cmd.none,
    )
  }
  // 上一次启动还挂着一个占位标页（同一时刻只跟一只）：先收掉它，不留一张悬空的白页
  if model.start_tab_waiting {
    ignore(js_tab_close(model.start_tab_profile))
  }
  let busy = map_rows(model, row.id, fn(item) { { ..item, status: Starting, busy: true } })
  (
    {
      ..busy,
      act_pending: row.id,
      act_response: false,
      act_tick: false,
      act_ok: false,
      act_note: "",
      act_notice: "",
      act_name: name,
      act_verb: "启动",
      start_tab: tab,
      start_tab_profile: profile,
      start_tab_waiting: false,
      start_tab_tries: 0,
      notice_url: None,
      notice_url_notice: "",
    },
    @cmd.batch([
      action_cmd(row.id, "start-instance", name, "启动", action_body("start-instance", params), emit),
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
  let name = model.act_name
  let verb = model.act_verb
  let ok = model.act_ok
  let note = model.act_note
  let cleared = map_rows(
    {
      ..model,
      act_pending: "",
      act_response: false,
      act_tick: false,
      act_name: "",
      act_verb: "",
    },
    id,
    fn(row) { { ..row, busy: false, status: Stopped, port_note: "" } },
  )
  if ok {
    // 启动成了：占位标页先留着 —— 带令牌的地址由 instances 读数给出（见 fill_start_tab）
    let text = name + " 已" + verb + "。"
    refresh_readings(
      {
        ..cleared,
        act_notice: text,
        act_notice_ok: true,
        act_notice_hint: backend_hint(note),
        act_notice_hint_for: text,
        start_tab_waiting: true,
      },
      emit,
    )
  } else {
    // 启动失败：占位标页没有下文了，当场关掉 —— **不留一张白页**，
    // 关没关成也要在提示条里说出来，不假装收干净了
    let tail = if model.start_tab == "held" {
      match js_tab_close(model.start_tab_profile) {
        "closed" => "；刚开的那个占位标页已经关掉，不留空白页"
        "none" => "；没有留下占位标页"
        other => "；关占位标页时出了岔子（" + other + "），请手动关掉它"
      }
    } else {
      ""
    }
    (
      {
        ..cleared,
        act_notice: name + " " + verb + "失败：" + note + tail,
        act_notice_ok: false,
        act_notice_hint: "",
        act_notice_hint_for: "",
        start_tab: "",
        start_tab_profile: "",
        start_tab_waiting: false,
        start_tab_tries: 0,
      },
      @cmd.none,
    )
  }
}

///|
/// 启动的那只 profile 现在有没有带令牌的地址。
///
/// 按 profile 名认，不按行 id：启动前后这一行会从「已停止」的 profile:<名> 变成
/// 运行中的 port:<端口>，id 对不上，名才对得上。
fn start_tab_url(rows : Array[Row], profile : String) -> String? {
  for row in rows {
    match row.profile_name {
      Some(name) =>
        if name == profile {
          match row.web_url {
            Some(url) => return Some(url)
            None => ()
          }
        }
      None => ()
    }
  }
  None
}

///|
/// 那只实例现在为什么没有带令牌的地址（后端原样给的那一句）；读数里还没有它就照实说。
fn start_tab_block_reason(rows : Array[Row], profile : String) -> String {
  for row in rows {
    match row.profile_name {
      Some(name) =>
        if name == profile {
          if row.web_url_source != "" {
            return row.web_url_source
          }
          return "读数里没有说明读不到令牌的原因"
        }
      None => ()
    }
  }
  "instances 读数里还没有这只 profile 的实例"
}

///|
/// 启动成功之后，instances 读数一落地就把带令牌的地址填进占位标页。
///
/// 为什么要等读数：令牌不在启动响应里 —— 它在实例日志的启动横幅里，由
/// /api/local/instances 现算（后端 weburl.mbt）。所以这一枪只能在读数回来之后打。
///
/// 一轮没读到不急着了结：端口先监听、横幅后落盘，在慢机器上是可能的，
/// 最多重读 start_tab_max_tries 轮。等满还读不到就认输 —— 认输也要把占位标页关掉、
/// 把原因写清，**不留白页**。
///
/// 地址到手之后提示条里仍摆一颗「打开 Web UI」（方案 B）：自动开标页可能被拦、
/// 也可能被用户自己关掉，那时再点一下就是新手势，一定开得成。
fn fill_start_tab(model : Model, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  if !model.start_tab_waiting {
    return (model, @cmd.none)
  }
  let profile = model.start_tab_profile
  match start_tab_url(model.rows, profile) {
    Some(url) => {
      let tail = if model.start_tab == "held" {
        match js_tab_goto(profile, url) {
          "ok" => "已在启动时自动打开的那个标页里填上带令牌的地址（能直接过握手，不是 401）"
          "closed" => "启动时占的那个标页已经被关掉了，没有标页可填"
          "gone" => "占了位的标页句柄找不到了（页面可能刷过），没有标页可填"
          other => "往占位标页里填地址失败（" + other + "）"
        }
      } else if model.start_tab == "blocked" {
        "浏览器把自动开的标页拦掉了（弹窗拦截），一个标页都没开"
      } else if model.start_tab == "" {
        "这一次没有开标页（没拿到 profile 目录名）"
      } else {
        "自动开标页没成（" + model.start_tab + "）"
      }
      let text = model.act_notice + "；" + tail + "。带令牌的地址：" + url
      (
        {
          ..model,
          act_notice: text,
          notice_url: Some(url),
          notice_url_notice: text,
          start_tab: "",
          start_tab_profile: "",
          start_tab_waiting: false,
          start_tab_tries: 0,
        },
        @cmd.none,
      )
    }
    None =>
      if model.start_tab_tries < start_tab_max_tries {
        (
          { ..model, start_tab_tries: model.start_tab_tries + 1 },
          @cmd.delay(emit(StartTabRetry), start_tab_retry_ms),
        )
      } else {
        let tail = if model.start_tab == "held" {
          match js_tab_close(profile) {
            "closed" => "已经把这个占位标页关掉，不留空白页"
            "none" => "没有留下空白标页"
            other => "关标页时出了岔子（" + other + "），请手动关掉它"
          }
        } else {
          "本来就没有开成标页"
        }
        let why = start_tab_block_reason(model.rows, profile)
        (
          {
            ..model,
            act_notice: model.act_notice + "；等不到带令牌的地址（" + why + "），" + tail +
              "。令牌由实例日志的启动横幅给出，稍后刷新读数再点卡上的「打开 Web UI」",
            act_notice_ok: false,
            start_tab: "",
            start_tab_profile: "",
            start_tab_waiting: false,
            start_tab_tries: 0,
          },
          @cmd.none,
        )
      }
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
  name : String,
  note : String,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let return_id = model.note_return
  let base = { ..model, note_saving: "" }
  let (ok, _) = interpret_http(res)
  if ok {
    let (text, hint) = note_receipt(name, note, res)
    let closed = {
      ..base,
      note_open: "",
      note_draft: "",
      note_error: "",
      act_notice: text,
      act_notice_ok: true,
      act_notice_hint: hint,
      act_notice_hint_for: text,
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
    Err(err) => (false, "这一步没发出去（" + describe(err) + "）")
    Ok(text) => {
      let got = parse_http_result(text)
      if got.status == 0 {
        (false, "这一步失败了（" + got.transport_error + "）")
      } else if got.status >= 200 && got.status < 300 {
        match open_envelope(got.body) {
          Ok(data) => (true, success_note(data))
          Err(reason) =>
            (
              false,
              "HTTP " + got.status.to_string() + " | 回执不是约定的格式：" + reason,
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
        join_with(parts, " | ")
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
    _ => return head + " | 回执不是合法 JSON（这一版可能还没有这个动作）"
  }
  guard root is Json::Object(obj) else {
    return head + " | 回执不是 JSON 对象"
  }
  match obj.get("error") {
    Some(Json::Object(err)) => {
      let code = str_field(err, "code")
      let message = str_field(err, "message")
      if code == "" && message == "" {
        head
      } else if code == "" {
        head + " | " + message
      } else if message == "" {
        head + " | " + code
      } else {
        head + " | " + code + "：" + message
      }
    }
    _ => head + " | 回执里没有失败原因"
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
          tag_settings: fallback_tag("设置读数读取失败：" + reason),
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
            tag_settings: fallback_tag("设置读数读取失败：" + reason),
          },
          @cmd.none,
        )
      } else if got.status >= 200 && got.status < 300 {
        match parse_settings(got.body) {
          Ok(facts) => {
            (
              {
                ..base,
                settings: Some(facts),
                settings_status: got.status,
                settings_status_text: got.status_text,
                settings_error: "",
                settings_endpoint_missing: false,
                // 读到了就不摆标记：连上一次失败留下的那一副也要清掉
                tag_settings: None,
                archived_open: default_archive_open(base, facts),
              },
              @cmd.none,
            )
          }
          Err(reason) => {
            let detail = http_status_text(got) + " | 响应不是约定的成功壳：" + reason
            (
              {
                ..base,
                settings: None,
                settings_status: got.status,
                settings_status_text: got.status_text,
                settings_error: detail,
                settings_endpoint_missing: false,
                tag_settings: fallback_tag("设置读数读取失败：" + detail),
              },
              @cmd.none,
            )
          }
        }
      } else {
        let missing = got.status == 404 || got.status == 501
        let detail = (if missing {
          "这台控制台还没有提供设置读数。"
        } else {
          "读设置时出错了。"
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
              "设置读数读取失败：" + http_status_text(got),
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
/// 「恢复默认」：把这一项写回**后端给的缺省值**（GET 里那份 defaults），走与手改完全同一条 PUT。
///
/// 缺省值读不到时什么都不做，只把原因说清 —— 退到本地契约表里的那个数去顶，
/// 就是在用户没要求的时候替他写了一个他不认识的数。
fn reset_setting(model : Model, key : String, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  let label = setting_label(key)
  let value = match model.settings {
    Some(facts) =>
      match lookup_setting(facts.defaults, key) {
        Some(value) => Some(value)
        None => None
      }
    None => None
  }
  match value {
    Some(value) => commit_setting_value(model, key, value, emit)
    None => (
      {
        ..model,
        settings_feedback: label + " 没能恢复默认：读数里没有这一项的缺省值",
        settings_feedback_ok: false,
      },
      @cmd.none,
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
      settings_feedback: label + " 已保存：" + value_text,
      settings_feedback_ok: true,
      tag_settings: None,
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
/// 更新循环的外壳。里面那一份照旧（update_inner），出来之后只补一件事：
/// 页面上新出现一条成功提示时，给它挂一个到期的计时。
///
/// **为什么挂在出口**：设置提示的地方有近二十处（act_notice 与 settings_feedback 各一条路），
/// 每一处都挂一次计时，就是二十处漏挂的机会；出口只有一个。
/// 判断只看「这一拍页面上正摆着哪条成功提示」：换了一条就重新计时，同一条不重挂。
/// 失败不在这一路上 —— 它不许自动消失（见 view_overview 的 action_notice）✗
fn update(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  let (next, cmd) = update_inner(model, msg, emit)
  let key = flash_key(next)
  if key == "" {
    if next.flash_serial == 0 {
      (next, cmd)
    } else {
      ({ ..next, flash_serial: 0, flash_fading: false }, cmd)
    }
  } else if key == flash_key(model) && next.flash_serial != 0 {
    // 同一条还在（或刚被鼠标重新计时过）：计时已经在跑，不重挂
    (next, cmd)
  } else {
    let serial = next.flash_serial + 1
    (
      { ..next, flash_serial: serial, flash_fading: false, flash_hover: false },
      @cmd.batch([cmd, @cmd.delay(emit(FlashExpire(serial)), flash_ms)]),
    )
  }
}

///|
/// 「这一拍页面上摆着哪条成功提示」的身份就是它的文字。
/// 空串 = 没有；有它才谈得上计时（见 update）。
fn flash_key(model : Model) -> String {
  let (text, _) = flash_text(model)
  text
}

///|
/// 把当前那条成功提示收掉（toast 到点了）。
/// 连悬停补充与那颗「打开 Web UI」一起收 —— 它们本来就跟这条文字绑在一起
/// （act_notice_hint_for / notice_url_notice），文字走了它们留着就是一段对不上号的东西。
fn clear_flash(model : Model) -> Model {
  let base = { ..model, flash_serial: 0, flash_fading: false, flash_hover: false }
  if model.page is Settings {
    { ..base, settings_feedback: "" }
  } else {
    // 悬停补充与那颗「打开 Web UI」跟着正文一起收：它们本来就只属于这一条文字
    {
      ..base,
      act_notice: "",
      act_notice_hint: "",
      act_notice_hint_for: "",
      notice_url: None,
      notice_url_notice: "",
    }
  }
}

///|
/// 把「这一次拖动」的过程状态全部清干净（表与回滚点不动）。
/// 起手、作废、收尾三处都走它 —— 三处各清一遍的话，漏掉一个字段就会留下
/// 一个撤不掉的占位块、或者永远抑制点击的僵尸状态。
///
/// `js_drop_clear` 也在这一处：冻结下来的那份格子坐标只属于这一次拖动，
/// 收尾不收的话，下一次拖动会拿着上一轮的坐标算落点。
fn reset_drag(model : Model) -> Model {
  js_drop_clear()
  {
    ..model,
    drag_id: "",
    drag_start_x: 0.0,
    drag_start_y: 0.0,
    drag_active: false,
    drag_group: "",
    drag_from: -1,
    drag_at: "",
    drag_at_index: -1,
    drag_ghost: false,
    drag_ghost_x: 0.0,
    drag_ghost_y: 0.0,
    drag_ghost_w: 0.0,
    drag_ghost_h: 0.0,
    drag_key_dir: 0,
  }
}

///|
fn update_inner(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
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
      (next, scroll_bottom_after_render("dsh-log-box"))
    }
    // 侧栏切页：状态与地址一起走。同一页连点两次不会攒出两条一样的历史（见 route.mbt）。
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
      let (next, enter) = route_into(model, route, emit)
      (
        next,
        @cmd.batch([
          enter,
          push_route(route_url(next.page, next.settings_group, next.log_source)),
        ]),
      )
    }
    // 浏览器前进 / 后退：地址是唯一的口径，页面按它复原（不写历史，也不清回落说明 ——
    // 退回的那一格地址可能就是个认不出来的，说明得跟着回来）。
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
        // 三个会开对话框的动作（重命名 / 删除 / 备注）都先把抽屉收掉：
        // 对话框在抽屉之上（z-index 60/61 > 抽屉 50/51），抽屉留在地上没有意义 ——
        // 而且取消之后焦点要回触发元素，那元素在抽屉里的话，焦点就落进一个盖在背后的面板。
        // 关掉抽屉之后焦点回那张卡，与「打开对话框的是这张卡」这件事一致。
        Rename => (
          {
            ..model,
            drawer_id: "",
            rename_id: id,
            rename_draft: row_name(model, id),
            rename_return: card_id(id),
          },
          focus_select_after_render("dsh-rename-input"),
        )
        Delete => (
          { ..model, drawer_id: "", confirm_id: id, confirm_return: card_id(id) },
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
            params_for_row(model, id, "profile"),
            emit,
          )
        Unarchive =>
          send_action(
            model,
            id,
            "unarchive-profile",
            row_name(model, id),
            "取消归档",
            params_for_row(model, id, "profile"),
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
                  {
                    ..model,
                    drawer_id: "",
                    act_notice: row.name +
                      " 现在没有在跑的实例，没有可读的日志来源（查看日志这一步没有执行）",
                    act_notice_ok: false,
                  },
                  @cmd.none,
                )
              }
          }
        // 打开 Web UI（卡上的主按钮）与「在新标签页打开」（行菜单）是同一件事：
        // 开带令牌的 webUrl。读不到令牌就不开标签页，把原因与裸地址说清（见 open_web_ui）。
        OpenUi => open_web_ui(model, id)
        Tab => open_web_ui(model, id)
        // 两条复制：裸地址（卡上「访问地址」那一行的原值）与带令牌的地址（webUrl）
        CopyUrl => copy_url_action(model, id, "访问地址", false, emit)
        CopyTokenUrl => copy_url_action(model, id, "带令牌的地址", true, emit)
        // 复制开发指令：一段给「另一个会话」的任务说明（粘到别的 profile 的会话里用）
        CopyDev => copy_dev_action(model, id, emit)
        // 打开工作目录 / 编辑配置：都走 POST open-path，只有 kind 不同（cli 端不给路径）
        Dir => open_path_action(model, id, "dir", "打开工作目录", emit)
        Config => open_path_action(model, id, "config", "打开配置", emit)
        // 没有兜底分支了：ActionKey 的每一项上面都接上了（以前那行兜底会把这个事实藏起来）
      }
    // 启动按钮的点击：占位标页已经在 DOM 监听器里同步开好（见 view_overview 的
    // start_click），tab 是那一枪的回执。这里只按状态放行 —— 不是「已停止」就什么都不做，
    // 但占下的标页要收掉：状态在这一栈与下一次渲染之间翻了的话，它就没有下文了。
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
    DeleteOpen(id, return_id) => (
      { ..model, confirm_id: id, confirm_return: return_id },
      focus_after_render("dsh-confirm-ok"),
    )
    // 点整张卡：开抽屉，焦点进抽屉里的关闭键。
    // 卡是 role=button + tabindex=0，键盘也能开（Enter / 空格，见 view_overview 的 card_attrs）。
    DrawerOpen(id) =>
      // 拖动与点击共用同一套按下-松开，靠位移阈值分开（见 DragDown / DragMove）。
      // 拖过的那一次松手之后浏览器仍会补一个 click，那一下不许再开抽屉。
      if model.drag_suppress_click {
        ({ ..model, drag_suppress_click: false }, @cmd.none)
      } else {
        // 又把抽屉打开了：正在收的那一只当场作废（同一行会撞出两个 #dsh-drawer-close），
        // 它那条计时回来时号对不上，自己会是空枪
        (
          { ..model, drawer_id: id, drawer_closing: "" },
          focus_after_render(drawer_close_id()),
        )
      }
    // 关抽屉：点外部 / Esc / 关闭键三条路都走这里，焦点一律回触发它的那张卡 ——
    // 焦点落在被卸载的节点上会掉到 body，键盘用户于是从页首重新 Tab。
    //
    // **焦点立刻就走**，不等滑出那一段：动画期间抽屉的节点还在文档里，
    // 那 220ms 里焦点要是还留在抽屉里（关闭键），键盘用户 Tab 一下又回到面板上。
    // 节点由 DrawerClosed 在动画走完之后撤掉（那之前它挂着 data-state="closing"，
    // 样式按它放滑出那一段，并把它对指针关掉 —— 半透明的面板不该再吃点击）。
    DrawerClose =>
      if model.drawer_id == "" {
        // 已经关了（连按两下 Esc、遮罩与键盘各来一次）：不动焦点，也不留空枪
        (model, @cmd.none)
      } else if prefers_reduced_motion() {
        // 「减少动效」：不做位移也不淡出，节点当场撤掉（样式里那条 media query 关的是
        // 开的那一半；收的这半边要连节点都不留，所以在这里判）
        (
          { ..model, drawer_id: "", drawer_closing: "" },
          focus_after_render(card_id(model.drawer_id)),
        )
      } else {
        (
          { ..model, drawer_id: "", drawer_closing: model.drawer_id },
          @cmd.batch([
            focus_after_render(card_id(model.drawer_id)),
            // 号用的是**正在收的那一行**（model.drawer_closing 此刻还是上一拍的值）
            @cmd.delay(emit(DrawerClosed(model.drawer_id)), drawer_anim_ms),
          ]),
        )
      }
    // 滑出走完了：这一枪的号还对得上才撤节点。中间又开过抽屉的话（号被清掉或换了一行）
    // 什么都不做 —— 不然会把刚开的那一只撤下去。
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
      }
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
        // 第一格（指针底下那条的 id）只用来查组：落点本身由 rank 定
        let (_, group, rank) = drop_target_of(x, y)
        let size = lift_sizes_of(model.drag_id)
        // 只有落在**同一组**里才算落点：两组是语义，跨组拖动不合并两组，
        // 画一个占位块在那儿等于答应了做不到的事。
        // 「指针进到另一组」在 dom.mbt 那一层就已经返回空（那一组的盒子冻在 others 里）；
        // 这里再按组名核一次，是同一件事的第二道 —— 那边管「指针在哪儿的盒子」，
        // 这边管「这个组名是不是被拖那一条的组」。
        let same_group = group != "" && group == group_of_row_id(model, model.drag_id)
        let ids = if same_group { current_group_ids(model, group) } else { [] }
        let n = ids.length()
        // 格子序号：**预览与落位用的是这一个数**（见 state.mbt 的 insert_at_index）。
        let k = if same_group && rank >= 0 && n > 1 {
          insert_at_index(n, rank)
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
      }
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
          Some(ids) => commit_order(cleared, dragged, ids, emit)
        }
      }
    // 指针被取消（触控被打断等）：这一次拖动作废。**不回滚也不提交** ——
    // 顺序还没动过，没有什么要回滚的。
    DragCancel =>
      (
        reset_drag(model),
        @cmd.batch([reorder_after_render(), clear_cells_after_render()]),
      )
    // 键盘换位：Ctrl+↑ / Ctrl+↓。与拖动走**同一条**提交路径，也走**同一个落点算法**：
    // 第一拍只把占位块摆出来（与拖动时那个块是同一个块），第二拍才真的换。
    // 这样键盘用户看到的也是「要落到哪儿」，而不是按下去才发现跳了一格。
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
        // 其余 n-1 条里，被换的那一条落在第 to 格 —— 空档序号就是 to。
        // 与指针那条路同一个 insert_at_index：它算出来的也是「其余 n-1 条的哪个空档」。
        let k = insert_at_index(ids.length(), to)
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
        }
      }
    OrderDone(res) => {
      let (ok, text) = interpret_http(res)
      if ok {
        // 成功：顺序在松手那一刻就已经就地生效了，这里只是报一句。
        //
        // 正文只留「顺序已保存」：后端那句话说的是「顺序表已写入 <落盘路径>（N 条）」——
        // 「顺序表」是内部的叫法，落盘路径也不是使用者要读的东西（第六轮契约第二节：
        // 细节收进悬停，正文说人话）。路径与条数一个字都没丢，它们在悬停里。
        (
          {
            ..model,
            act_notice: "顺序已保存",
            act_notice_ok: true,
            act_notice_hint: text,
            act_notice_hint_for: "顺序已保存",
            order_before: [],
          },
          @cmd.none,
        )
      } else {
        // 失败：**回滚到提交前那一份**。停在「看着是新的、其实没存下」比不做还糟 ——
        // 下一次刷新列表会跳回原样，而使用者不知道自己刚才拖的那一下去哪了。
        (
          {
            ..model,
            order: model.order_before,
            order_before: [],
            act_notice: "顺序没保存：" + text,
            act_notice_ok: false,
          },
          @cmd.none,
        )
      }
    }

    // 启动的展示下限到了：等回执一起收尾（收尾里不伪造成「运行中」——
    // 真的起来了的那张卡由重读 instances 给出）
    StartTick(id) =>
      if model.act_pending == id {
        finish_start({ ..model, act_tick: true }, emit)
      } else {
        (model, @cmd.none)
      }
    // 带令牌的地址还没到手：再重读一轮读数（有界，见 start_tab_max_tries）。
    // 地址到了就填、到不了就认输关标页 —— 两条路都在 fill_start_tab 里。
    StartTabRetry => refresh_readings(model, emit)
    // 提示条里那颗「打开 Web UI」：用户再点一下 = 新手势，一定不被弹窗拦截器吃掉。
    // 这是自动开标页被拦时的兜底入口（方案 B），地址是启动时读到的同一条 webUrl。
    NoticeOpenUi =>
      match model.notice_url {
        None => (model, @cmd.none)
        Some(url) => {
          let (ok, tail) = open_outcome_text(js_open_url(url))
          let text = "Web UI " + tail + "。" + url
          (
            {
              ..model,
              act_notice: text,
              act_notice_ok: ok,
              notice_url_notice: text,
            },
            @cmd.none,
          )
        }
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
          old,
          "重命名",
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
    // 与重命名 / 删除同一条口径：开框就把抽屉收掉（框在抽屉之上，抽屉留着没有意义，
    // 取消之后焦点还要回触发它的那张卡 —— 那元素在抽屉里的话焦点就落进背后的面板）
    NoteOpen(id) => (
      {
        ..model,
        drawer_id: "",
        note_open: id,
        note_draft: row_note(model, id),
        note_return: card_id(id),
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
                note_error: "这一行的读数里没有 profile 目录名，保存不了 —— 没有目标就什么都没做",
              },
              @cmd.none,
            )
          } else {
            // 这一行不置忙：备注保存时卡片本身还能用，忙碌态只锁保存键
            (
              { ..model, note_saving: row.id, note_error: "", act_notice: "" },
              action_cmd(
                row.id,
                "set-profile-note",
                row.name,
                "保存备注",
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
        row_name(model, target),
        "删除",
        params_of(delete_pairs(model, target)),
        emit,
        confirm=delete_confirm_of(model),
      )
      (next, @cmd.batch([cmd, focus_after_render(return_id)]))
    }
    DeleteCancel => (
      { ..model, confirm_id: "" },
      focus_after_render(model.confirm_return),
    )
    // ── 回收站 ─────────────────────────────────────────────
    // 恢复：把回收站里那一份移回 profile 目录。成功 / 失败都重读读数并出提示条，
    // 失败尤其要显示后端给的原因（已经有同名 profile 时是 conflict）。
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
    TrashPurgeOpen(dir, return_id) => (
      { ..model, trash_purge_dir: dir, trash_purge_return: return_id },
      focus_after_render("dsh-purge-ok"),
    )
    // 彻底删除：confirm 走顶层（缺了后端给 bad-params），与硬删同一风险等级
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
      }
    }
    TrashPurgeCancel => (
      { ..model, trash_purge_dir: "" },
      focus_after_render(model.trash_purge_return),
    )
    // 手动折过就记一笔：ui.archiveOpenByDefault 之后不再覆盖用户的选择
    ToggleArchived => (
      { ..model, archived_open: !model.archived_open, archived_user_toggled: true },
      @cmd.none,
    )
    // 换来源：来源是页面状态的一部分，跟着进地址（换来源 = 走一步，可以后退回来）
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
    LogRefresh => start_logs(model, model.log_source, emit)
    // ── 设置页 ─────────────────────────────────────────────
    SettingsText(res) => settings_loaded_state(model, res)
    SettingsRetry => (
      { ..model, settings_loading: true, settings_error: "", settings_loaded: false },
      settings_get_cmd(emit),
    )
    // 设置分组也是页面状态：切分组就换地址，刷新 / 后退都回到同一组
    SettingsGroupPicked(id) => (
      { ..model, settings_group: id, route_notice: "" },
      push_route(route_url(Settings, id, model.log_source)),
    )
    SettingDraft(key, text) => (
      { ..model, settings_draft: put_draft(model.settings_draft, key, text) },
      @cmd.none,
    )
    SettingCommit(key, text) => commit_setting(model, key, text, emit)
    SettingToggle(key, next) => commit_setting_value(model, key, VBool(next), emit)
    // 恢复默认走同一条 PUT（值取后端给的缺省值，不是前端自己填一个数）
    SettingReset(key) => reset_setting(model, key, emit)
    SettingsSaved(key, res) => settings_saved_state(model, key, res)
    // ── 写动作的回执 ───────────────────────────────────────
    // 启动走「回执 + 展示下限」两条腿；其余动作拿到回执就落定，
    // 成功的动作一律重读 profiles / instances（刷新的是读数，不是弹个提示）。
    HttpDone(row_id, action, name, verb, res) => {
      let (ok, note) = interpret_http(res)
      if action == "set-profile-note" {
        note_settled(model, res, name, note, emit)
      } else if action == "start-instance" && model.act_pending == row_id {
        finish_start({ ..model, act_response: true, act_ok: ok, act_note: note }, emit)
      } else {
        let cleared = map_rows(model, row_id, fn(row) { { ..row, busy: false } })
        if ok {
          // 回执说人话：谁 + 做了什么 + 结果（见 action_receipt）。
          // 后端回执原文与里面的数字、路径收进悬停，不摊在正文上。
          let (shown, hint) = action_receipt(action, name, verb, note, res)
          // 本地不猜结果：归档记录、运行时登记、回收站条目都在后端的读数里，
          // 重读 console / profiles / instances 之后界面自己会变
          refresh_readings(
            {
              ..cleared,
              act_notice: shown,
              act_notice_ok: true,
              act_notice_hint: hint,
              act_notice_hint_for: shown,
            },
            emit,
          )
        } else {
          (
            {
              ..cleared,
              act_notice: name + " " + verb + "失败：" + note,
              act_notice_ok: false,
              act_notice_hint: "",
              act_notice_hint_for: "",
            },
            @cmd.none,
          )
        }
      }
    }
    // 剪贴板回执：只说这一枪的真实结局（写进去了 / 两条路都失败），
    // 复制成功不改任何读数，所以这里不刷新列表。
    CopyDone(subject, res) => {
      let (ok, note) = match res {
        Ok(text) => parse_copy_result(text)
        Err(err) => (false, "剪贴板调用没发出去（" + describe(err) + "）")
      }
      (
        { ..model, act_notice: subject + note, act_notice_ok: ok },
        @cmd.none,
      )
    }
    // toast 到期：序号对不上说明这一条已经被换掉了，那一枪作废
    FlashExpire(serial) =>
      if serial != model.flash_serial {
        (model, @cmd.none)
      } else if model.flash_hover {
        // 鼠标正停在上面：这一拍不算数，重新计一遍 —— 不许它正好在眼皮底下消失
        (model, @cmd.delay(emit(FlashExpire(serial)), flash_ms))
      } else {
        (
          { ..model, flash_fading: true },
          @cmd.delay(emit(FlashRemove(serial)), flash_fade_ms),
        )
      }
    FlashRemove(serial) =>
      if serial != model.flash_serial {
        (model, @cmd.none)
      } else {
        (clear_flash(model), @cmd.none)
      }
    FlashHover(on) => ({ ..model, flash_hover: on }, @cmd.none)
    Noop => (model, @cmd.none)
  }
}
