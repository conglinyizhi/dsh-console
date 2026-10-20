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
      // 设置**启动时读一次**（这一轮起）：侧栏的形态存在 ui.sidebarCollapsed 里，
      // 不读就不知道刷新之后该画展开还是收起 —— 先画展开再收一下，那一下是跳的。
      // 这一枪与「进设置页才拉」不冲突：ensure_settings_read 自带去重，
      // route_into 落在设置页时这里什么都不发。
      let (boot, read_settings) = ensure_settings_read(model, emit)
      // Shift 监视在启动时装一次（删除按钮的「按住 Shift = 彻底删除」由它打标记，见 dom.mbt）。
      js_shift_watch()
      (
        boot,
        @cmd.batch([
          load(emit),
          enter,
          read_settings,
          listen_popstate(emit),
          settle,
          // 页脚那颗灯：进页面先查一次，之后每 5 秒一次（§31.1）。
          // 第一条回执到了才排下一次，所以这里只发这一枪、不排定时器。
          health_ping_cmd(emit),
        ]),
      )
    },
    update=update,
  )
  model.view(fn(m) { page_view(m, emit) })
}

// ── 列表拼装 ────────────────────────────────────────────────

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
/// 设置读数的懒加载入口（唯一的一处）：还没读到、也没在读，才发这一枪。
///
/// 两个地方要它：进设置页（那一页整页靠这份读数），以及**开抽屉**时
/// （抽屉里那颗删除按钮按 safety.deleteToTrash 决定写「删除」还是「彻底删除」）。
/// 启动时不预拉：后端没提供这个接口时，每次打开总览都会在控制台里留一条 404，
/// 而「控制台零问题」是验收项。读过一次（成功或失败）就不再自动重发，
/// 失败之后要重试走设置页那颗「重新读取」。
fn ensure_settings_read(model : Model, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  if model.settings_loaded || model.settings_loading {
    (model, @cmd.none)
  } else {
    ({ ..model, settings_loading: true, settings_error: "" }, settings_get_cmd(emit))
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
    // 进一页就把窄屏的覆盖层收掉：它盖在页面上，新的一页不该从它下面出来。
    // 三条关闭路径里的「点导航项」与浏览器前进 / 后退都经过这里。
    sidebar_overlay: false,
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
      // 设置是懒加载：只在真进设置页（或开抽屉）时发 GET，见 ensure_settings_read。
      ensure_settings_read(base, emit)
    Trash =>
      // 回收站是会变的（另一个标签页里删了东西、别处恢复了）：进来就重读一次控制台读数。
      // 只重发这一份，别的读数不动 —— 它读不到时的样子由这一页自己分档说清。
      (base, load_console(emit))
    Maintenance => {
      // 作业也在 console 读数里（jobs[]）。进这一页就重读一次：作业可能是在另一个
      // 标签页里推进的，页面上那份是上一次读到的。
      let console = load_console(emit)
      // 版本来源：那条 GET 现在只读后端进程内的缓存、秒回（§10.1），
      // 进这一页重读一次不再有等待代价。补问计数每次进来清零 ——
      // 「还在拉」最多补问 releases_poll_cap 次，不是每进一次页就多攒一份定时器。
      (
        {
          ..base,
          releases_ticks: 0,
          releases_poll_pending: false,
          releases_loading: base.releases == None,
        },
        @cmd.batch([console, load_releases(emit)]),
      )
    }
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
  // 这批 profile 是从哪个 home 的 profiles/ 下读出来的（profiles 读数的 dshHome）。
  // 空串 = 读数没给 home：那种卡片上那一格写「未知」、开发指令不发（见 profile_rows / own_home_of）——
  // **不拿控制台自己的 home 顶替**，那会把这一只说到别的 home 上去。
  let profiles_home = match model.profiles {
    Some(facts) => facts.dsh_home
    None => ""
  }
  let profile_list = match model.profiles {
    Some(facts) => facts.profiles
    None => []
  }
  // 缺包排不排进状态灯，由设置项 profile.ignoreMissingBundles 决定（§40.2）；
  // 设置还没读到时按缺省（不报警）—— 缺省就是「缺包不吓人」。
  let ignore_missing = ignore_missing_bundles(model)
  let running = match model.instances {
    Some(facts) =>
      running_rows(facts.instances, profile_list, model.console, profiles_home, ignore_missing)
    None => demo_running()
  }
  // 已停止组要排除「正被某个运行中实例用着」的 profile——同一个东西不能既运行中又已停止
  let live_instances = match model.instances {
    Some(facts) => facts.instances
    None => []
  }
  let stopped = match model.profiles {
    Some(facts) =>
      profile_rows(
        facts.profiles,
        model.runtime,
        profiles_home,
        live_instances,
        model.console,
        ignore_missing,
      )
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
  // 列表拼好之后还有两件跟读数有关的事要办：
  //   ① 启动成功的那只实例，它在点击那一栈里占下的标页正等着带令牌的地址（见 fill_start_tab）；
  //   ② 刚创建出来的那份 profile 的卡，焦点要落在它身上（§19.1）。
  //      「刚创建」那一枪的回执里只有名字，卡是这一次重读之后才有的 —— 所以只能在这里收。
  let (focused, focus_new) = focus_new_card(next)
  let (filled, waiting) = fill_start_tab(focused, emit)
  (filled, @cmd.batch([cmd, waiting, focus_new]))
}

///|
/// 新建实例之后那把焦点：读数落地、列表里真有那只 profile 的卡，才把焦点送过去。
///
/// 找不到就只清掉这一格：读数已经重读过了，列表里没有它就是真没有（派生那一步
/// 可能没成），留着一个指不到的 id 只会让下一次重读也来发一枪空焦点。
fn focus_new_card(model : Model) -> (Model, @cmd.Cmd) {
  if model.new_focus == "" {
    return (model, @cmd.none)
  }
  let mut target = ""
  for row in model.rows {
    match row.profile_name {
      Some(name) => if name == model.new_focus {
        target = row.id
      }
      None => ()
    }
  }
  if target == "" {
    return ({ ..model, new_focus: "" }, @cmd.none)
  }
  ({ ..model, new_focus: "" }, focus_after_render(card_id(target)))
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
/// 目标 profile 的参数：{ profile } 或 { profile, home }。
///
/// home 是这一行**自己的** home（口径见 own_home_of）：带上它，后端才不用按自己的 home
/// 去猜这一只在哪 —— start-instance 的 home 参数后端早就有了，只是一直没有 UI 够得着。
/// 读不到自己的 home 就只发名字：**不拿控制台自己的 home 顶上** ✗，那等于指名去动别处那一份。
/// 读不到目录名同理给空数组：写动作一律以读数为准，不拿演示数据里那个名字去打真实的东西。
fn profile_pairs(row : Row) -> Array[(String, String)] {
  match row.profile_name {
    Some(name) => {
      let home = own_home_of(row)
      if home == "" {
        [("profile", json_text_literal(name))]
      } else {
        [("profile", json_text_literal(name)), ("home", json_text_literal(home))]
      }
    }
    None => []
  }
}

///|
/// 归档 / 取消归档的参数：{ profile, home }。
///
/// home 必须带上：一份档案的身份是 (home, 名字)。同名两份档案在两个 home 里时，
/// 只发名字后端分不出撤的是哪一条（那它只能按名字撤，会把另一份也撤掉）。
/// 归档孤行（磁盘上没有目录）的 home 来自归档记录本身，见 Row 的 archive_home。
/// 读不到 home（后端没给 / 这一行没有可比的值）就只发名字：**不猜一个 home 出来**，
/// 由后端按它自己的 home 认 —— 那是改动之前的兼容口径。
fn archive_pairs(row : Row) -> Array[(String, String)] {
  match row.profile_name {
    Some(name) => {
      let home = archive_home_of(row)
      if home == "" {
        [("profile", json_text_literal(name))]
      } else {
        [("profile", json_text_literal(name)), ("home", json_text_literal(home))]
      }
    }
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
/// 按行取动作目标：kind = "port" 取端口，"archive" 取归档那一套（名字 + home），
/// 其余取 profile。
fn params_for_row(model : Model, row_id : String, kind : String) -> String {
  match find_row(model.rows, row_id) {
    None => ""
    Some(row) =>
      if kind == "port" {
        params_of(port_pairs(row))
      } else if kind == "archive" {
        params_of(archive_pairs(row))
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
/// 走 send_action 的同一条通道：这一行置忙、回执进全局提示（§14），
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
    (false, "没能打开：浏览器把新标签页拦掉了（弹窗拦截）。地址是带令牌的那一条，可以自己去开")
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
  // 按住 Alt = 按那颗「硬开裸地址」（§15.2），**有没有 key 都一样**：
  // 抽屉里那颗按钮与这条快捷键是同一件事，两边给出的回执也不许长得不一样。
  // 用 Alt 不用 Shift：Shift+点击会被浏览器当成「开新窗口」，那是它自己的手势。
  if js_alt_held() {
    let hint = if row.web_url_source == "" {
      "读不到带令牌的地址，也没有说明原因；裸地址 " + row.url
    } else {
      row.web_url_source + "；裸地址 " + row.url
    }
    let outcome = js_open_url(row.url)
    let (ok, text) = if outcome == "ok" {
      (
        true,
        match row.web_url {
          // 这一支不说「带令牌的地址」：开的本来就是裸地址，拿另一套话会自相矛盾
          Some(_) => row.name + " 已硬开裸地址（没带 key），打开后可能无法正常使用"
          None => row.name + " 不是启动器拉起的，没有 key，已硬开裸地址，打开后可能无法正常使用"
        },
      )
    } else if outcome == "blocked" {
      (false, row.name + " 的裸地址被浏览器拦掉了（弹窗拦截），可以自己去开 " + row.url)
    } else {
      (false, row.name + " 的裸地址没能打开（" + outcome + "）")
    }
    return (notice_put(model, ok, text, hint), @cmd.none)
  }
  match row.web_url {
    Some(url) => {
      let (ok, tail) = open_outcome_text(js_open_url(url))
      let text = row.name + " 的 Web UI " + tail + "。地址 " + url + "（令牌来源：" +
        row.web_url_source + "）"
      (notice_put(model, ok, text, ""), @cmd.none)
    }
    None => {
      // 正文只留一句人话，细节（地址、令牌从哪来、为什么没有）全进悬停。
      let hint = if row.web_url_source == "" {
        "读不到带令牌的地址，也没有说明原因；裸地址 " + row.url
      } else {
        row.web_url_source + "；裸地址 " + row.url
      }
      (
        notice_put(
          model,
          false,
          row.name + " 不是启动器拉起的，没有 key，没有打开（按住 Alt 可以硬开裸地址）",
          hint,
        ),
        @cmd.none,
      )
    }
  }
}

///|
/// 抽屉里「硬开裸地址」那一枪的回执落地（§15.2）。
///
/// 这一枪本身在 DOM 监听器里同步打完（见 view_overview 的 hard_open_click），
/// 这里只按结局说话：开成了、被弹窗拦了、还是报错 —— 三档分开说，不报一句空的「已打开」。
fn hard_open_done(
  model : Model,
  row_id : String,
  url : String,
  outcome : String,
) -> (Model, @cmd.Cmd) {
  let name = row_name(model, row_id)
  let (ok, text) = if outcome == "ok" {
    (true, name + " 已硬开裸地址，打开后可能无法正常使用")
  } else if outcome == "blocked" {
    (false, name + " 的裸地址被浏览器拦掉了（弹窗拦截），可以自己去开 " + url)
  } else {
    (false, name + " 的裸地址没能打开（" + outcome + "）")
  }
  (notice_put(model, ok, text, "裸地址 " + url + "；这一颗不管有没有 key，直接开裸地址"), @cmd.none)
}

///|
/// 页脚那颗灯的一次探测落地（design/design-fixes.md §31.1）。
///
/// 只写这几格 health_*：**页面上的其它读数一个字节都不动** —— 这一枪失败说的是
/// 「服务端没答上来」，不说明 profiles / instances 那几份读数也坏了（各有各的请求）。
///
/// 排下一次：可见时排 5 秒的定时器；已经隐藏了就不排（后台标签页不发请求），
/// 改成挂一个「等可见」的监听，可见那一刻立刻补一次。
fn health_settled(
  model : Model,
  res : Result[String, Error],
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let (ok, ms, reason) = match res {
    Err(err) => (false, 0, "请求没发出去：" + describe(err))
    Ok(text) => parse_health(text)
  }
  let next = {
    ..model,
    health_busy: false,
    health_state: if ok {
      HealthOnline
    } else {
      HealthOffline
    },
    health_ms: ms,
    health_at: local_time_now(),
    health_fails: if ok {
      0
    } else {
      model.health_fails + 1
    },
    health_reason: reason,
  }
  if js_page_hidden() {
    (
      { ..next, health_visible_wait: true },
      listen_visible(emit),
    )
  } else {
    (
      { ..next, health_visible_wait: false },
      @cmd.delay(emit(HealthTick), health_poll_ms),
    )
  }
}

///|
/// 探测回执 →（成没成, 往返毫秒, 失败原因）。回执不是约定形状就当失败，
/// 不拿「解析不出来」说成「在线」。
fn parse_health(text : String) -> (Bool, Int, String) {
  let root = try @json.parse(text) catch {
    _ => return (false, 0, "探测回执不是合法 JSON")
  }
  guard root is Json::Object(obj) else {
    return (false, 0, "探测回执不是 JSON 对象")
  }
  let ok = bool_field(obj, "ok")
  let ms = match int_field(obj, "ms") {
    Some(n) => n
    None => 0
  }
  let reason = str_field(obj, "error")
  (
    ok,
    ms,
    if ok {
      ""
    } else if reason == "" {
      "没给出原因"
    } else {
      reason
    },
  )
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
  // 第二道（第一道是按钮置灰）：裸地址这一枪只认行上那个「有地址可复制」标记。
  // 停用行的 url 是「已停用，无法访问」这个占位串，照着复制的就是把一句占位话写进剪贴板
  // （design/ops-maintenance-jobs.md §13.1）。
  if !with_token && !row.url_copyable {
    return (
      notice_err(model, row.name + " 的" + what + "没能复制：没在跑，没有访问地址可复制"),
      @cmd.none,
    )
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
      notice_err(model, row.name + " 的" + what + "没能复制：" + why + "，没有可复制的内容"),
      @cmd.none,
    )
  }
  (
    notice_clear(model),
    copy_cmd(row.name + " 的" + what, text, emit),
  )
}

///|
/// 剪贴板回执 → (成功?, 给用户看的一句话)。
/// 传输层给的是 { ok, how, error }：ok=true 时写出走的是哪条路，
/// ok=false 时把两个失败原因都带上（clipboard 的 reject 原因 + execCommand 的结果）。
///|
/// 剪贴板回执 → (成没成, 正文, 悬停补充)。
///
/// 正文只说结局，**不提是哪条浏览器接口写进去的**（navigator.clipboard / execCommand
/// 对用户没有意义，而且换个环境就变）。技术原因进悬停，正文保持一句话。
fn parse_copy_result(text : String) -> (Bool, String, String) {
  let root = try @json.parse(text) catch {
    _ => return (false, "没能复制到剪贴板", "剪贴板调用返回的不是合法 JSON")
  }
  guard root is Json::Object(obj) else {
    return (false, "没能复制到剪贴板", "剪贴板调用返回的不是 JSON 对象")
  }
  if bool_field(obj, "ok") {
    let how = str_field(obj, "how")
    (true, "已复制到剪贴板", if how == "" { "" } else { "写入方式：" + how })
  } else {
    let why = str_field(obj, "error")
    (false, "没能复制到剪贴板", if why == "" { "" } else { why })
  }
}

///|
/// 这一行**自己的** DSH_HOME：卡上那一格就是它。
///
/// 三种行各有各的出处，都只认它自己那一份：运行中的卡是那一只实例读出来的 home、
/// 已停止的卡是 profiles 读数列它出来的那个 home、归档孤行是归档记录里的那个。
/// 读不到（「—」/「未知」/ 空串）就返回空串让调用方说清 ——
/// **绝不回落到控制台自己的 home** ✗：多 home 之后那正是这个功能要防的事（把开发会话引回主线）。
/// 口径与后端 a 那一条一致：认不出就说认不出。
fn own_home_of(row : Row) -> String {
  if home_is_path(row.home) {
    row.home
  } else {
    ""
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
/// home 用的是**这一行自己的**那一个（见 own_home_of）：读不到就一份都不产出，
/// 由调用方如实说「拼不出来」—— 拿控制台自己的 home 顶上，粘过去那边就会去动主线那一份。
///
/// 起法与控制台的「启动」逐项对齐（见后端 actions/instance.mbt 的 start_instance）：
/// 它在 <profile 目录> 下、带着 DSH_HOME 起 dsh --profile <名> --no-open --port <端口>。
/// 命令里那个 8400 是 instance.basePort 的**缺省起点**（控制台也是从这一项往后找第一个
/// 空闲端口），正文里同时写明它可以换成任何一个空闲端口 —— 写死一个数而不说这句，
/// 端口被占时那条命令就是个起不来的命令。
fn dev_instruction_text(row : Row, name : String) -> String {
  let home = own_home_of(row)
  if home == "" {
    return ""
  }
  let dir = home + "/profiles/" + name
  // 不再带「【给另一个会话的插件开发任务】」那一行头部（§47）：
  // 粘过去的那一端不需要被分类，它要的是事实 —— 目标、目录、home、状态、能不能动进程。
  let head = ""
  let facts = "目标 profile：" + name + "\n" +
    "目录：" + dir + "\n" +
    "DSH_HOME：" + home + "\n"
  // 状态按这一行**现在的事实**分两支：在跑的时候绝不能让它再起一只，
  // 也不该由它去重启用户正在用的进程（design/design-fixes.md §34）。
  let state = match (row.status, row.port_value) {
    (Running, Some(port)) =>
      "状态：正在运行，端口 " + port.to_string() + "（" +
      (if row.console_started { "由本控制台起的" } else { "不是本控制台起的" }) +
      (match row.web_url {
        Some(_) => "）"
        None => "；令牌在启动它的终端里）"
      }) + "\n\n" +
      "不要动这只进程，也不要再起第二只。\n" +
      "改完配置之后告诉用户：需要重启 :" + port.to_string() +
      " 那一只才会生效，重启由用户来做。\n\n"
    _ =>
      "状态：没在跑\n\n" +
      "需要起它做验证时（与在控制台里点「启动」等价）：\n" +
      "  DSH_HOME=" + home + " dsh --profile " + name + " --no-open --port <空闲端口>\n" +
      "  <空闲端口> 换成当前任意空闲端口。留意在哪个目录下起：会话会记在那一份目录的桶里。\n" +
      "起好的那只进程归你管，可以停、可以重启；除它之外别动别的进程。\n\n"
  }
  let rules = "只改 " + dir + " 这一份下的文件。别的 profile 与主线各是各的，不要碰。"
  head + facts + state + rules
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
    dev_instruction_text(row, name)
  }
  if text == "" {
    let why = if name == "" {
      "这一行的读数里没有 profile 目录名"
    } else {
      "这一行的读数里给不出它自己的 DSH_HOME（home 那一格：「" + row.home +
      "」）。指令里的 DSH_HOME 与 profile 目录都得按它自己的 home 拼，" +
      "拿控制台自己的 home 顶上就会把开发会话引回主线，所以这一枪不发"
    }
    return (
      notice_err(model, row.name + " 的开发指令没能复制：" + why + "，拼不出可粘的说明"),
      @cmd.none,
    )
  }
  (notice_clear(model), copy_cmd(row.name + " 的开发指令", text, emit))
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
      notice_err(
        model,
        name + " " + verb + "没执行：这一行的读数里没有可用的目标（profile 目录名或端口读不到）",
      ),
      @cmd.none,
    )
  } else {
    let busy = map_rows(model, id, fn(row) { { ..row, busy: true } })
    (
      notice_clear(busy),
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
/// 只带 profile 名的参数：{ profile }。
///
/// 隔离 / 取消隔离只认这一个键（后端 ensure_action_params 会拒掉多余的），
/// 所以不能复用 profile_pairs —— 那一条会顺手带上 home，多出来的键就是 bad-params。
fn profile_name_pairs(row : Row) -> Array[(String, String)] {
  match row.profile_name {
    Some(name) =>
      if name == "" {
        []
      } else {
        [("profile", json_text_literal(name))]
      }
    None => []
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
/// 删除要不要带二次确认串，带的话是什么 —— **按确认框打开那一刻记下来的模式**（§13.2）。
///
/// 契约第一节：safety.deleteToTrash=false 时删除是硬删，**body 顶层**必须带 "confirm":"DELETE"。
/// 认的是 model.confirm_hard（点开确认框时定下的那一格），不是此刻的设置页读数：
/// 框开着的这几秒里设置被改了，请求该照当时那个决定发，而不是悄悄换一种删法。
///
/// 这个串走 action_body_with_confirm（放顶层），不再塞进 params：
/// 后端是从顶层读的（handle_action 里的 json_field(json, "confirm")），
/// 塞进 params 的结果是硬删永远以 bad-params 告终 —— 这条实测复现过 ✗
fn delete_confirm_of(model : Model) -> String {
  if model.confirm_hard {
    "DELETE"
  } else {
    ""
  }
}

///|
/// 点下删除按钮那一刻是哪种模式：按住 Shift（读文档级打的那个标记），**或**回收站关着。
///
/// 由 DOM 监听器同步调用（见 view_overview 的 delete_click）：Shift 状态不进 model、
/// 不走状态回环 —— CSS 那边也是按同一个标记直接换色换字（§13.2）。
fn delete_mode_now(model : Model) -> Bool {
  if js_shift_held() {
    true
  } else {
    // 回收站没开时删除就是彻底删除，不管按没按 Shift；读不到设置也按可能要硬删处理
    delete_to_trash_of(model) != Some(true)
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
  // home = 这一份是从哪个 home 删的；进回收站时它会连条目一起记下来，恢复按它归位。
  // 记不上时 originError 给原因 —— 那句话必须露出来，不然恢复落到别处时没人知道为什么。
  let home = str_field(outcome, "home")
  let origin_error = str_field(outcome, "originError")
  let hint = "profile=" + profile + " | dir=" + dir + " | mode=" + mode + " | trashPath=" +
    (if trash_path == "" { "（硬删，没有回收站落点）" } else { trash_path }) +
    " | hardDeleted=" + (if hard { "true" } else { "false" }) +
    (if home == "" { "" } else { " | home=" + home }) +
    (if origin_error == "" { "" } else { " | 来源 home 没记住：" + origin_error })
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
/// 关于页「用这一版」：把这一份 dsh 指定成起实例用的那一版（POST pin-dsh）。
///
/// 这条动作不挂在任何一行实例上：row_id 给空串，回执按动作名分派（见 update 里的 HttpDone），
/// 不走总览页那条提示条 —— 那一页说的是实例，这里说的是安装。
fn pin_dsh_version(
  model : Model,
  dir : String,
  version : String,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  if dir == "" {
    return (
      notice_err(model, "这一份 dsh 的目录没读到，没法指定（读数里那一格是空的）"),
      @cmd.none,
    )
  }
  let params = params_of([("dir", json_text_literal(dir))])
  (
    notice_clear({ ..model, dsh_pin_busy: dir }),
    action_cmd("", "pin-dsh", version, "用这一版", action_body("pin-dsh", params), emit),
  )
}

///|
/// 关于页「回到自动」：撤掉指定（POST unpin-dsh，没有参数）。
fn unpin_dsh_version(model : Model, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  (
    notice_clear({ ..model, dsh_pin_busy: "auto" }),
    action_cmd("", "unpin-dsh", "", "回到自动", action_body("unpin-dsh", "{}"), emit),
  )
}

///|
/// 「用这一版 / 回到自动」的回执：把结果写进关于页那一格，并重读 runtime 读数。
///
/// **重读就是这条动作的正文**：能不能指定、指定之后生效的是哪一版，都由
/// /api/local/runtime 说了算（dshVersion / dshPinState / dshCandidates）。
/// 本地不猜结果 —— 猜一个「已切换」出去，重读完界面又变回去，比不换更糟。
fn dsh_pin_settled(
  model : Model,
  action : String,
  ok : Bool,
  note : String,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let text = if ok {
    note
  } else if action == "pin-dsh" {
    "没能指定这个版本：" + note
  } else {
    "没能回到自动：" + note
  }
  (
    notice_put({ ..model, dsh_pin_busy: "" }, ok, text, ""),
    if ok { load_runtime(emit) } else { @cmd.none },
  )
}


// ── 维护页（作业台） ─────────────────────────────────────────
//
// 这一页的动作全部走 POST /api/local/action，回执带着整份作业（outcome.job）。
// 页面只在**回执之后**改文案，不本地猜「成功了」：作业到底到哪一步，由后端写下的
// 那份记录说了算（下一次 console 读数回来也是同一份事实）。

///|
/// 动作名 → 给使用者看的名字（失败提示的句首用它，不把内部动作名摆到正文里）。
fn job_action_label(action : String) -> String {
  match action {
    "job-start" => "开始作业"
    "job-install" => "安装新版本"
    "job-trial" => "把新版本跑起来"
    "job-verdict" => "记下结论"
    "job-trial-stop" => "停掉试跑实例"
    "job-commit" => "切到新版本"
    "job-cleanup-preview" => "清理预演"
    "job-cleanup" => "清理旧版本"
    "job-abort" => "中止作业"
    _ => "这一步"
  }
}

///|
/// 回执里的 outcome 对象（成功才是 Some）。
fn job_outcome_of(res : Result[String, Error]) -> Map[String, Json]? {
  match res {
    Err(_) => None
    Ok(text) => {
      let got = parse_http_result(text)
      if got.status < 200 || got.status >= 300 {
        return None
      }
      match open_envelope(got.body) {
        Ok(data) =>
          match data.get("outcome") {
            Some(Json::Object(outcome)) => Some(outcome)
            _ => None
          }
        Err(_) => None
      }
    }
  }
}

///|
/// 回执里那条作业的 id（没有给空串）。
fn job_id_of(outcome : Map[String, Json]?) -> String {
  match outcome {
    Some(o) =>
      match o.get("job") {
        Some(Json::Object(job)) => str_field(job, "id")
        _ => ""
      }
    None => ""
  }
}

///|
/// 成功的正文。**只写结论**（命令、路径、输出尾部都收进悬停）：
/// 这一页的正文要能一眼看懂「现在到哪一步了」，不是给人读日志的。
fn job_success_text(action : String, outcome : Map[String, Json]?) -> String {
  let o = match outcome {
    Some(o) => o
    None => Map([])
  }
  match action {
    "job-start" => "作业已创建，第 1 步（锁定当前版本）已经做完。"
    "job-install" =>
      if !bool_field(o, "executed") {
        "预演完成：还没有装任何东西。"
      } else {
        match int_field(o, "exitCode") {
          Some(0) => "安装命令跑完了（退出码 0）。下一步把新版本跑起来。"
          Some(code) => "安装命令退出码 " + code.to_string() + "，这一步记为不通过。"
          None => "安装命令没跑完，这一步记为不通过。"
        }
      }
    "job-trial" =>
      if bool_field(o, "started") {
        let url = str_field(o, "url")
        "新版本在一次性 home 里起来了：" + (if url == "" { "见下面的地址" } else { url }) +
        "。你去用一用，收尾时这只实例会停掉、这份 home 会删掉。"
      } else {
        "新版本没跑起来，这一步记为不通过。原因在悬停里。"
      }
    "job-verdict" =>
      match str_field(o, "verdict") {
        "good" => "记下了：好用。下一步是切到新版本。"
        "bad" =>
          "回滚了：起实例还是用 " + str_field(o, "anchorVersion") +
          "；新装的那份留着没删，要删单独清理"
        "later" => "记下了：先放着。试跑实例、一次性 home 与版本指定都没动。"
        _ => "结论记下了。"
      }
    "job-trial-stop" => "试跑实例已经收掉了，一次性 home 也删了；作业还停在这一步。"
    "job-commit" =>
      "已经切到 " + str_field(o, "version") +
      "；起实例会用这一版。旧版本留着当回滚锚，确认稳定后再清理"
    "job-cleanup-preview" => "预演完成：这一步会删掉旧版本的包目录，还没有删。"
    "job-cleanup" =>
      if bool_field(o, "deleted") {
        "旧版本的包目录已删掉。"
      } else {
        "旧版本的包目录本来就不在了，这一步没有可删的。"
      }
    "job-abort" => "作业已中止，试跑实例与一次性 home 都收掉了；已经做完的步骤都留着。"
    _ => "这一步完成了。"
  }
}

///|
/// POST 一条作业动作，回执走 JobDone）。
fn job_cmd(action : String, params : String, emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.attempt(
    fn(res : Result[String, Error]) { emit(JobDone(action, res)) },
    async fn() {
      let text : String = js_http_call(
        "POST",
        "/api/local/action",
        action_body(action, params),
        write_headers(),
      ).wait().cast()
      text
    },
  )
}

///|
/// 开始一条作业。目标版本必须是使用者填的 —— 留空就在这里拦住，
/// 不拿「本机装着的最新一份」顶上（§4：版本由前端选，别在后端猜；这里连前端也不猜）。
fn job_start_command(model : Model, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  let version = model.job_version.trim().to_owned()
  if version == "" {
    return (notice_err(model, "先填上要装的目标版本，再点开始。"), @cmd.none)
  }
  // profile 必填（后端也拦）：试跑要从这只 profile 复制一份配置到一次性 home（§9.4）。
  // 名称取自「在跑的 → web → 第一份」里第一只**可用**的，与页面下拉里显示的是同一个函数。
  let profile = job_profile_choice(model)
  if profile == "" {
    let text = if job_profile_names(model).length() == 0 {
      "先选一只试跑用的 profile：这一页没读到任何 profile 读数。"
    } else {
      "没有可用的试跑 profile：这一只配置要么读不到，要么起不了网页实例。"
    }
    return (notice_err(model, text), @cmd.none)
  }
  let params = params_of([
    ("kind", json_text_literal("upgrade-dsh")),
    ("version", json_text_literal(version)),
    ("profile", json_text_literal(profile)),
  ])
  (notice_clear({ ..model, job_busy: "new" }), job_cmd("job-start", params, emit))
}

///|
/// 某条作业的一步。安装与清理的「确认执行」必须在**这一次会话里先预演过**：
/// 没预演就点执行，这里当场拦住，不把请求发出去 —— 会后端一次 conflict 也能挡住，
/// 但那要等一个来回，而且用户会以为「点了没反应」。
fn job_step_command(
  model : Model,
  id : String,
  step : String,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  if id == "" {
    return (model, @cmd.none)
  }
  let refuse = fn(text : String) { (notice_err(model, text), @cmd.none) }
  let params_with = fn(confirm_key : String, confirm_value : String) {
    params_of([("id", json_text_literal(id)), (confirm_key, confirm_value)])
  }
  match step {
    "install-preview" => (
      notice_clear({ ..model, job_busy: id }),
      job_cmd("job-install", params_with("confirm", "false"), emit),
    )
    "install-confirm" =>
      if model.job_previewed != id || model.job_previewed_step != "install" {
        refuse("先点「预演这一步」，看过确切命令再确认执行。")
      } else {
        (notice_clear({ ..model, job_busy: id }), job_cmd("job-install", params_with("confirm", "true"), emit))
      }
    "trial" => (
      notice_clear({ ..model, job_busy: id }),
      job_cmd("job-trial", params_of([("id", json_text_literal(id))]), emit),
    )
    "verdict-good" => (
      notice_clear({ ..model, job_busy: id }),
      job_cmd(
        "job-verdict",
        params_of([("id", json_text_literal(id)), ("verdict", json_text_literal("good"))]),
        emit,
      ),
    )
    "verdict-bad" => (
      notice_clear({ ..model, job_busy: id }),
      job_cmd(
        "job-verdict",
        params_of([("id", json_text_literal(id)), ("verdict", json_text_literal("bad"))]),
        emit,
      ),
    )
    "verdict-later" => (
      notice_clear({ ..model, job_busy: id }),
      job_cmd(
        "job-verdict",
        params_of([("id", json_text_literal(id)), ("verdict", json_text_literal("later"))]),
        emit,
      ),
    )
    "trial-stop" => (
      notice_clear({ ..model, job_busy: id }),
      job_cmd("job-trial-stop", params_of([("id", json_text_literal(id))]), emit),
    )
    "commit" => (
      notice_clear({ ..model, job_busy: id }),
      job_cmd("job-commit", params_of([("id", json_text_literal(id))]), emit),
    )
    "cleanup-preview" => (
      notice_clear({ ..model, job_busy: id }),
      job_cmd("job-cleanup-preview", params_of([("id", json_text_literal(id))]), emit),
    )
    "cleanup" =>
      if model.job_previewed != id || model.job_previewed_step != "cleanup" {
        refuse("先点「清理旧版本」，看过会删掉什么再确认执行。")
      } else {
        (notice_clear({ ..model, job_busy: id }), job_cmd("job-cleanup", params_with("confirm", "DELETE"), emit))
      }
    "abort" => (
      notice_clear({ ..model, job_busy: id }),
      job_cmd("job-abort", params_of([("id", json_text_literal(id))]), emit),
    )
    _ => refuse("认不出这一步，没有发出请求。")
  }
}

///|
/// 作业动作的回执。
///
/// 出口分两处、各说一半（§14.3）：
///   - 全局提示：一条结论（成功 toast / 失败常驻），切到哪一页都看得见
///   - 作业卡：这次动作的**细节**（确切命令 / 包目录 / 输出尾部），跟着那条作业留在页面上
/// 两处的话不重叠，所以同一句话不会在页面上出现两遍（§14.4）。
/// 成功之后重读 console —— 作业的真实状态在那份读数里，不在本地猜。
fn job_settled(
  model : Model,
  action : String,
  res : Result[String, Error],
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let (ok, note) = interpret_http(res)
  let outcome = job_outcome_of(res)
  if !ok {
    return (
      // 失败不往作业卡里写细节：原因在常驻提示条上（一句话，§32.1），历史在后端写的步骤表里。
      notice_failed_action(
        { ..model, job_busy: "", job_detail: "", job_detail_for: "" },
        job_action_label(action) + "没成功：" + note,
      ),
      // 失败也可能改过作业记录（例如清理没删掉时那一步被记成 failed）：
      // 重读一次 console，让步骤表与后端那份记录对上，而不是停在动作前的样子。
      load_console(emit),
    )
  }
  let body = job_success_text(action, outcome)
  let job_id = job_id_of(outcome)
  let preview_install = action == "job-install" && !bool_field(match outcome {
    Some(o) => o
    None => Map([])
  }, "executed")
  let preview_cleanup = action == "job-cleanup-preview"
  let mut next = notice_ok(
    { ..model, job_busy: "", job_detail: note, job_detail_for: job_id },
    body,
    "",
  )
  if action == "job-start" {
    next = { ..next, job_version: "" }
    next = {
      ..next,
      job_collapsed: next.job_collapsed.filter(fn(collapsed) { collapsed != job_id }),
    }
  }
  if preview_install {
    next = { ..next, job_previewed: job_id, job_previewed_step: "install" }
  } else if preview_cleanup {
    next = { ..next, job_previewed: job_id, job_previewed_step: "cleanup" }
  } else if model.job_previewed == job_id && job_id != "" {
    // 预演过的那一步已经执行（或作业被别的动作推进了）：这一份预演作废。
    // 留着它会让下一次「确认执行」拿一份旧的预演去放行。
    next = { ..next, job_previewed: "", job_previewed_step: "" }
  }
  // 试跑起了一只实例、收掉它、切了版本 —— 这三类动作会把「本机有哪些实例 / 哪一版生效」
  // 一起改掉，所以连 profiles 与 instances 读数一起重读（否则总览页还停在动作前）。
  if action == "job-trial" || action == "job-trial-stop" || action == "job-verdict" {
    refresh_readings(next, emit)
  } else if action == "job-commit" {
    let (after, cmd) = refresh_readings(next, emit)
    (after, @cmd.batch([cmd, load_runtime(emit)]))
  } else {
    (next, load_console(emit))
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
  // 补包（design/design-fixes.md §39.3）：正文就要后端那一句短的
  //（「<名> 的包已装齐（pnpm install --prefer-offline，3 秒）」），
  // 别再加一层「已安装缺的包」。logPath / 退出码 / 用时这些进悬停。
  if action == "repair-packages" {
    let hint = match outcome {
      Some(outcome) =>
        backend_hint(note) +
        (if str_field(outcome, "logPath") == "" {
          ""
        } else {
          "\n日志：" + str_field(outcome, "logPath")
        }) +
        (if str_field(outcome, "command") == "" {
          ""
        } else {
          "\n命令：" + str_field(outcome, "command") + "（退出码 " +
          int_or(outcome, "exitCode", -1).to_string() + "，" +
          (int_or(outcome, "durationMs", 0) / 1000).to_string() + " 秒）"
        })
      None => backend_hint(note)
    }
    return (if note == "" { name + " 的包已装齐" } else { note }, hint)
  }
  // 配置 home 两条：回执要把**从哪儿移到哪儿**说清楚，而且要说「这是移动」——
  // 光说「已隔离」的话，使用者还得自己翻读数去确认那份目录现在在哪。
  if action == "isolate-profile" {
    let (from, to) = match outcome {
      Some(outcome) => (str_field(outcome, "movedFrom"), str_field(outcome, "movedTo"))
      None => ("", "")
    }
    let text = if to == "" {
      name + " 已经移到独立 home。"
    } else {
      name + " 已经移到独立 home：" + to + "（原来那份不再留在共用 home 里）。"
    }
    let hint = match outcome {
      Some(outcome) =>
        backend_hint(note) + (if from == "" { "" } else { "\n移动：" + from + " -> " + to }) +
        (if str_field(outcome, "deviceNote") == "" {
          ""
        } else {
          "\n" + str_field(outcome, "deviceNote")
        })
      None => backend_hint(note)
    }
    return (text, hint)
  }
  if action == "deisolate-profile" {
    let to = match outcome {
      Some(outcome) => str_field(outcome, "movedTo")
      None => ""
    }
    let trash = match outcome {
      Some(outcome) => str_field(outcome, "trashPath")
      None => ""
    }
    let size = match outcome {
      Some(outcome) => outcome_size_text(outcome)
      None => ""
    }
    let head = if to == "" {
      name + " 的目录已经移回共用 home。"
    } else {
      name + " 的目录已经移回共用 home：" + to + "。"
    }
    let tail = if trash == "" {
      ""
    } else {
      "这份额外 home 里剩下的会话与插件状态移到了回收站" +
      (if size == "" { "" } else { "（" + size + "）" }) + "，可以捞回来。"
    }
    return (head + tail, backend_hint(note))
  }
  // 配置快照（design/ops-maintenance-jobs.md §16.3）：回执说清这一趟存了什么 / 还原到哪一份，
  // 后端原文与快照目录收进悬停。
  if action == "snapshot-profile" {
    let (files, bytes, dir, at) = match outcome {
      Some(o) =>
        (int_or(o, "files", 0), num_field(o, "bytes"), str_field(o, "dir"), str_field(o, "at"))
      None => (0, None, "", "")
    }
    let when = match js_short_time(at) {
      "" => ""
      short => "（" + short + "）"
    }
    let text = "已给 " + name + " 拍了一张快照" + when + "：" + files.to_string() + " 个文件 · " +
      trash_size_text(bytes) + "。"
    let hint = backend_hint(note) + (if dir == "" { "" } else { "\n快照目录：" + dir })
    return (text, hint)
  }
  if action == "restore-snapshot" {
    let (at, restored, pre_id, dir) = match outcome {
      Some(o) =>
        (
          str_field(o, "at"),
          str_array_field(o, "restored"),
          str_field(obj_field(o, "preSnapshot"), "id"),
          str_field(o, "dir"),
        )
      None => ("", [], "", "")
    }
    let when = match js_short_time(at) {
      "" => "这一份快照"
      short => short + " 那一份"
    }
    let text = if restored.length() == 0 {
      name + " 已还原到 " + when + "，但那三个文件快照里一个都没有，profile 里的内容没动。"
    } else {
      name + " 已还原到 " + when + "（写回 " + restored.join("、") + "）。"
    }
    let hint = backend_hint(note) + (if pre_id == "" { "" } else { "\n还原前那张快照：" + pre_id }) +
      (if dir == "" { "" } else { "\n这一份快照在：" + dir })
    return (text, hint)
  }
  // 整体替换（design/ops-maintenance-jobs.md §17.4）：正文照那一句原话，
  // 写了哪几份 / 搬了哪几个 / 跳过了哪些收进悬停（数字都在正文里，清单在悬停里）。
  if action == "promote-profile" {
    let (from, to, written, moved, skipped, snap_id) = match outcome {
      Some(o) =>
        (
          str_field(o, "from"),
          str_field(o, "to"),
          str_array_field(o, "written"),
          str_array_field(o, "packagesMoved"),
          str_array_field(o, "packagesSkipped"),
          str_field(obj_field(o, "snapshot"), "id"),
        )
      None => ("", "", [], [], [], "")
    }
    if to != "" && from != "" {
      let text = to + " 的配置已用 " + from + " 替换（写了 " + written.length().to_string() +
        " 份文件，搬了 " + moved.length().to_string() + " 个包，跳过 " +
        skipped.length().to_string() + " 个已存在的包）；替换前快照 " + snap_id
      let mut hint = backend_hint(note)
      match outcome {
        Some(o) => {
          let snap_dir = str_field(obj_field(o, "snapshot"), "dir")
          if snap_dir != "" {
            hint = hint + "\n替换前快照在：" + snap_dir
          }
          for item in str_array_field(o, "packageNotes") {
            hint = hint + "\n" + item
          }
        }
        None => ()
      }
      if written.length() > 0 {
        hint = hint + "\n写过去的文件：" + written.join("、")
      }
      if moved.length() > 0 {
        hint = hint + "\n搬过去的包：" + moved.join("、")
      }
      if skipped.length() > 0 {
        hint = hint + "\n同名已存在、没有覆盖的包：" + skipped.join("、")
      }
      return (text, hint)
    }
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
/// 取一个字符串数组字段（不是数组 / 元素不是字符串都按空处理）。
fn str_array_field(obj : Map[String, Json], key : String) -> Array[String] {
  let out : Array[String] = []
  for item in arr_field(obj, key) {
    match item {
      Json::String(s) => out.push(s)
      _ => ()
    }
  }
  out
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
      notice_err(model, name + " 启动没执行：读数里没有 profile 目录名"),
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
      notice_ok({ ..cleared, start_tab_waiting: true }, text, backend_hint(note)),
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
    // 启动失败也走「一句结论 + 查看日志」（§32.1）：这一枪同样写了审计行，
    // 完整原文（pid / argv / 日志路径 / 错误行）在 audit.jsonl 里，悬停里也留着全文。
    // 占位标页那半句（tail）从正文里让出去：它进悬停，正文只留结论。
    (
      notice_failed_action(
        { ..cleared, start_tab: "", start_tab_profile: "", start_tab_waiting: false, start_tab_tries: 0 },
        name + " " + verb + "失败：" + note + tail,
      ),
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
      let (base_text, base_hint) = notice_parts(model)
      // 正文里**不许出现地址**：那条地址带着令牌，提示条会留在屏幕上、也会进通知历史。
      // 要打开就用提示条右侧那颗「打开 Web UI」（它拿的是内存里的 notice_url，不上屏）。
      let text = base_text + "；" + tail
      (
        {
          ..notice_put(model, true, text, base_hint),
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
        let (base_text, _) = notice_parts(model)
        (
          notice_err(
            { ..model, start_tab: "", start_tab_profile: "", start_tab_waiting: false, start_tab_tries: 0 },
            base_text + "；等不到带令牌的地址（" + why + "），" + tail +
            "。令牌由实例日志的启动横幅给出，稍后刷新读数再点卡上的「打开 Web UI」",
          ),
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
    let closed = notice_ok(
      { ..base, note_open: "", note_draft: "", note_error: "" },
      text,
      hint,
    )
    let (next, cmd) = refresh_readings(closed, emit)
    (next, @cmd.batch([cmd, focus_after_render(return_id)]))
  } else {
    ({ ..base, note_error: note }, @cmd.none)
  }
}

///|
/// 「＋新建实例」这一枪的回执（design/design-fixes.md §19.1）。
///
/// 成：回执写新名字与它隔离到哪儿，框关掉，重读读数；新卡要等读数落地才有，
/// 所以焦点不在这里发 —— 把名字记进 new_focus，由 rebuild 在列表拼好之后送过去。
/// 败：**框不关**，后端原话写在框里。用户改个名字就能再点一次创建；
/// 关掉的话那句原因就成了一闪而过的提示条。
///
/// 两条路都不在本地插一条卡：新卡是重读 profiles 之后由读数给出的，本地先插一条
/// 会让「看着有、其实没派生」和「派生成功」长得一样。
fn new_instance_settled(
  model : Model,
  res : Result[String, Error],
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let (ok, note) = interpret_http(res)
  if !ok {
    return ({ ..model, new_busy: false, new_error: note }, @cmd.none)
  }
  let outcome = match outcome_of(res) {
    Some(fields) => fields
    None =>
      return (
        { ..model, new_busy: false, new_error: "回执里没有 outcome，这一版认不出派生结果" },
        @cmd.none,
      )
  }
  // 新名字以**回执**为准：重名时后端会自动加序号，前端猜不出它加到几
  let created = str_field(outcome, "newName")
  let source = str_field(outcome, "profile")
  let home = obj_field(outcome, "home")
  let home_path = str_field(home, "path")
  let home_error = str_field(home, "error")
  let name = if created == "" { model.new_name_draft.trim().to_owned() } else { created }
  // 隔离建成与没建成是两件事：没建成时不能说「已隔离到」，那是假报
  let text = if home_path != "" {
    "已创建 " + name + "（已隔离到 " + home_path + "）"
  } else if home_error != "" {
    "已创建 " + name + "（隔离 home 没建成：" + home_error + "，它现在与别的 profile 共用 DSH_HOME）"
  } else {
    "已创建 " + name
  }
  let hint = backend_hint(note) + (if source == "" { "" } else { "\n源配置：" + source })
  let closed = notice_ok(
    {
      ..model,
      new_open: false,
      new_source: "",
      new_base: false,
      new_name_draft: "",
      new_name_dirty: false,
      new_error: "",
      new_busy: false,
      new_focus: name,
    },
    text,
    hint,
  )
  refresh_readings(closed, emit)
}

///|
/// 「从基础实例开始」这一枪的回执（design/design-fixes.md 第 20 节）。
///
/// 成：回执照规格写「已从基础模板新建 <名字>（已隔离到 <路径>）」，隔离没建成时那一支
/// 照实说「共用 DSH_HOME」；框关掉，重读读数，新卡出现之后焦点再送过去（与派生同一套）。
/// 败：**框不关**，后端原话写在框里 —— 那句原因要能对着改名字（同名 conflict 尤其常见）。
fn base_profile_settled(
  model : Model,
  res : Result[String, Error],
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let (ok, note) = interpret_http(res)
  if !ok {
    return ({ ..model, new_busy: false, new_error: note }, @cmd.none)
  }
  let outcome = match outcome_of(res) {
    Some(fields) => fields
    None =>
      return (
        { ..model, new_busy: false, new_error: "回执里没有 outcome，这一版认不出新建结果" },
        @cmd.none,
      )
  }
  let created = str_field(outcome, "name")
  let home = obj_field(outcome, "home")
  let home_path = str_field(home, "path")
  let home_error = str_field(home, "error")
  let name = if created == "" { model.new_name_draft.trim().to_owned() } else { created }
  // 隔离建成与没建成是两件事：没建成时不能说「已隔离到」，那是假报（与派生那一支同一口径）
  let text = if home_path != "" {
    "已从基础模板新建 " + name + "（已隔离到 " + home_path + "）"
  } else if home_error != "" {
    "已从基础模板新建 " + name + "（隔离 home 没建成：" + home_error +
    "，它与别的 profile 共用 DSH_HOME）"
  } else {
    "已从基础模板新建 " + name
  }
  let closed = notice_ok(
    {
      ..model,
      new_open: false,
      new_source: "",
      new_base: false,
      new_name_draft: "",
      new_name_dirty: false,
      new_error: "",
      new_busy: false,
      new_focus: name,
    },
    text,
    backend_hint(note),
  )
  refresh_readings(closed, emit)
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
/// 宽屏侧栏的形态，**判据只有设置里的 ui.sidebarCollapsed**（design/sidebar-collapse.md）。
///
/// 读不到就是 false（展开）：契约缺省本来就是展开，而且「没读到就收起」会让
/// 一台还没提供设置接口的后端把导航藏成一条图标栏。
fn sidebar_collapsed_of(facts : SettingsFacts) -> Bool {
  match lookup_setting(facts.values, "ui.sidebarCollapsed") {
    Some(VBool(on)) => on
    _ => false
  }
}

///|
/// 设置里存着的形态（模型里那份副本写失败时要退回它）。
fn sidebar_collapsed_stored(model : Model) -> Bool {
  match model.settings {
    Some(facts) => sidebar_collapsed_of(facts)
    None => false
  }
}

///|
/// 宽屏顶栏的折叠按钮：**先翻界面，再写设置**。
///
/// 先翻是因为「点了没动」最容易被再点一次；写设置走的是设置页同一条 PUT
/// （commit_setting_value），回执失败时 settings_saved_state 会把形态退回存着的那一份，
/// 所以这里不必再挂一份回滚。
fn toggle_sidebar(model : Model, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  let next = !model.sidebar_collapsed
  let (saving, cmd) = commit_setting_value(model, "ui.sidebarCollapsed", VBool(next), emit)
  ({ ..saving, sidebar_collapsed: next }, cmd)
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
                sidebar_collapsed: sidebar_collapsed_of(facts),
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
            notice_err(
              { ..model, settings_draft: drop_draft(model.settings_draft, key) },
              def.label + " 没保存：" + reason,
            ),
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
    Some(_) =>
      // 「正在保存 …」不播报（§14.3 只认保存成功 / 失败）：这一句既不是结果，
      // 又会把刚才那条失败提示顶掉。控件自己在 settings_saving 期间是禁用的。
      (
        {
          ..model,
          settings_saving: key,
          settings_pending: Some(value),
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
      notice_err(model, label + " 没能恢复默认：读数里没有这一项的缺省值"),
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
    let failed = { ..model, settings_saving: "", settings_pending: None, settings_draft: drafts }
    // 侧栏那一次点击是**先动界面、再写设置**的：写失败就把界面退回设置里存着的那一份，
    // 不能停在「看着收起了、其实没存下」的状态（与拖动换位的回滚同一条规矩）。
    let failed = if key == "ui.sidebarCollapsed" {
      { ..failed, sidebar_collapsed: sidebar_collapsed_stored(model) }
    } else {
      failed
    }
    return (
      notice_err(failed, label + " 没保存：" + note),
      set_control_after_render(setting_control_id(key), back),
    )
  }
  let facts = merge_saved(model, key, res)
  let value_text = match model.settings_pending {
    Some(value) => setting_value_text(value)
    None => "已保存"
  }
  let saved = {
    ..model,
    settings: Some(facts),
    settings_saving: "",
    settings_pending: None,
    settings_draft: drafts,
    tag_settings: None,
  }
  // 设置页那颗开关与外壳那颗折叠按钮是同一个键：两边都得跟着读数走
  let saved = if key == "ui.sidebarCollapsed" {
    { ..saved, sidebar_collapsed: sidebar_collapsed_of(facts) }
  } else {
    saved
  }
  // 开关保存成功之后把焦点送回那一颗（§51.4）：这一行会因为「恢复默认」按钮的出现
  // 而改变节点结构，焦点会掉到 body —— 键盘用户按一次空格就再也接不上第二下。
  let refocus = if setting_is_switch(key) {
    focus_after_render(setting_switch_id(key))
  } else {
    @cmd.none
  }
  (
    notice_ok(
      saved,
      label + " 已保存：" + value_text,
      "",
    ),
    refocus,
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
/// 发一条**成功**提示：底部 toast，flash_ms 之后自己走（悬停在上面时顺延，见 update）。
///
/// 这是动作结果的唯一出口（§14）：设置页保存、关于页切版本、总览的启动 / 复制、
/// 维护页的每一条回执都走它，页面里不再各留一份。
fn notice_ok(model : Model, text : String, hint : String) -> Model {
  notice_put(model, true, text, hint)
}

///|
/// 发一条**失败**提示：常驻提示条，直到下一条动作替换它（不挂到期计时）。
///
/// 失败与成功同住一条出口，但**读取失败不进这里** —— 那解释的是「这一块为什么是空的」，
/// 留在页面原位（§14.4）。
fn notice_err(model : Model, text : String) -> Model {
  notice_put(model, false, text, "")
}

///|
/// 动作失败的正文最多几个字（design/design-fixes.md §32.1）。
pub let failure_text_max : Int = 56

///|
/// 失败提示的正文：**只留第一句**（§32.1）。
///
/// 按「。」或「；」切第一刀，取前段；切完还超过 56 个字再截断并补「…」。
/// 被砍掉的不是丢掉：完整原文挂在悬停里，也留在 audit.jsonl 的 message 里
/// （走动作的那一类失败一定有一条审计线，「查看日志」就是去那儿看）。
fn failure_headline(text : String) -> String {
  let buf = StringBuilder()
  let mut n = 0
  let mut truncated = false
  for c in text {
    if c == '。' || c == '；' {
      break
    }
    if n >= failure_text_max {
      truncated = true
      break
    }
    buf.write_char(c)
    n = n + 1
  }
  let head = buf.to_string()
  // 开头就是句号这种（形状坏了）不交一个空正文出去
  if head == "" {
    return text
  }
  if truncated {
    head + "…"
  } else {
    head
  }
}

///|
/// 一条**动作失败**的提示：一句结论 + 一颗「查看日志」（§32.1）。
///
/// 只有这一路带 audit=true：它走的是 POST /api/local/action，后端一定往 audit.jsonl
/// 追了一行（ok=false + code + message）。剪贴板、读数、设置校验那些失败没有审计线，
/// 也就别摆一颗点了看不到东西的按钮。
fn notice_failed_action(model : Model, full : String) -> Model {
  notice_put(model, false, failure_headline(full), full, audit=true)
}

///|
/// 把正文 / 悬停里带令牌的地址洗掉（design/design-fixes.md §32、§36）：
/// `token=xxxx` 整段换成 `…`（连参数名一起去掉），其余一个字不动。
///
/// 为什么在 notice_put 这一处洗：提示条会留在屏幕上、toast 会被回看、通知历史会整条存下来 ——
/// 与其在每个拼文案的地方各记一遍，不如在唯一的出口上守一道。
/// 令牌原值仍然在内存里（notice_url），也仍在实例日志里，只是不上屏。
fn redact_tokens(text : String) -> String {
  let chars : Array[Char] = []
  for c in text {
    chars.push(c)
  }
  let out = StringBuilder()
  let n = chars.length()
  let mut i = 0
  while i < n {
    let matched = i + 6 <= n &&
      chars[i] == 't' &&
      chars[i + 1] == 'o' &&
      chars[i + 2] == 'k' &&
      chars[i + 3] == 'e' &&
      chars[i + 4] == 'n' &&
      chars[i + 5] == '='
    if matched {
      // 整个 token=<值> 换成「…」：令牌原值不上屏，连参数名也不留 ——
      // 正文与历史里因此连 "token=" 这个串都搜不到（§36.1 的验收就是这么查的）。
      i = i + 6
      while i < n && is_token_char(chars[i]) {
        i = i + 1
      }
      out.write_string("…")
      continue
    }
    out.write_char(chars[i])
    i = i + 1
  }
  out.to_string()
}

///|
/// 令牌值的字符集：base64url 那一套（字母数字与 - _ . ~ + / =）。
/// 用「像令牌的字符」而不是「像终止符的字符」来划边界：边界写反了会把后面的中文一起吃掉。
fn is_token_char(c : Char) -> Bool {
  (c >= '0' && c <= '9') ||
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  c == '-' || c == '_' || c == '.' || c == '~' || c == '+' || c == '/' || c == '='
}
///|
/// 换掉当前这条提示：序号 +1，外壳与到期计时都按序号认人。
fn notice_put(
  model : Model,
  ok : Bool,
  text : String,
  hint : String,
  audit? : Bool = false,
) -> Model {
  let seq = model.notice_serial + 1
  // 末尾句号在这里统一去掉：提示条说的是一句结论，不是一段话
  let body = js_trim_tail_period(text)
  // 带令牌的地址不上屏（§32 / §36）：正文与悬停都洗一遍，历史跟着同一份走
  let safe_text = redact_tokens(body)
  let safe_hint = redact_tokens(hint)
  let at = local_time_now()
  // 通知历史（§36）：新到旧留最近 notice_history_max 条。只在内存里，刷新就清空。
  // 顺序是「新的插在最前面」，侧栏直接照这个顺序摆，不再排一遍。
  let history : Array[NoticeRecord] = [{ at, ok, text: safe_text, hint: safe_hint, audit }]
  let mut kept = 1
  for item in model.notice_history {
    if kept < notice_history_max {
      history.push(item)
      kept = kept + 1
    }
  }
  {
    ..model,
    notice_serial: seq,
    notice: Some({ seq, ok, text: safe_text, hint: safe_hint, at, audit }),
    notice_history: history,
    notice_unread: model.notice_unread + 1,
    flash_fading: false,
    flash_hover: false,
  }
}

///|
/// 把提示收掉：成功 toast 到期，或者下一次动作开始前清场。
/// 悬停补充与那颗「打开 Web UI」跟着正文一起收 —— 它们只属于当前这一条文字。
fn notice_clear(model : Model) -> Model {
  {
    ..model,
    notice: None,
    flash_fading: false,
    flash_hover: false,
    notice_url: None,
    notice_url_notice: "",
  }
}

///|
/// 当前那条提示的（正文, 悬停补充）。没有就是两个空串。
/// 启动收尾那一段要把新地址接在原来的正文后面，所以需要一个读回来的口子。
fn notice_parts(model : Model) -> (String, String) {
  match model.notice {
    None => ("", "")
    Some(n) => (n.text, n.hint)
  }
}

///|
/// 当前那条提示的序号（0 = 没有）。到期消息带着序号回来，对不上就作废。
fn notice_seq(model : Model) -> Int {
  match model.notice {
    Some(n) => n.seq
    None => 0
  }
}

///|
/// 更新循环的外壳。里面那一份照旧（update_inner），出来之后只补一件事：
/// 新出现一条**成功**提示时给它挂一个到期的计时。
///
/// **为什么挂在出口**：发提示的地方有二十多处，每一处都挂一次计时就是二十处漏挂的机会；
/// 出口只有一个。判断只看序号：换了一条就重新计时，同一条不重挂。
/// 失败不在这一路上 —— 它不许自动消失（§14.1）✗
fn update(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  let (next, cmd) = update_inner(model, msg, emit)
  match next.notice {
    None => (next, cmd)
    Some(n) =>
      if !n.ok {
        // 失败常驻：不挂计时，也不重置任何东西
        (next, cmd)
      } else if n.seq == notice_seq(model) {
        // 同一条还在（悬停重新计时也走这里）：计时已经在跑，不重挂
        (next, cmd)
      } else {
        (next, @cmd.batch([cmd, @cmd.delay(emit(FlashExpire(n.seq)), flash_ms)]))
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
    SidebarToggle => toggle_sidebar(model, emit)
    SidebarOverlayOpen => (
      { ..model, sidebar_overlay: true },
      // 焦点进第一个导航项：键盘接下来直接落在导航里，不用先 Tab 过顶栏
      focus_after_render(nav_dom_id(Overview)),
    )
    SidebarOverlayClose =>
      if model.sidebar_overlay {
        ({ ..model, sidebar_overlay: false }, focus_after_render(side_burger_id()))
      } else {
        (model, @cmd.none)
      }
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
    HardOpenDone(id, url, outcome) => hard_open_done(model, id, url, outcome)
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
    // 点开确认框：把那一刻的模式记进 model（hard = true 就是彻底删除）。
    // 确认框的标题 / 正文 / 确认键颜色与确认时发的请求都照这一格走，不事后重读设置。
    DeleteOpen(id, return_id, hard) => (
      { ..model, confirm_id: id, confirm_return: return_id, confirm_hard: hard },
      focus_after_render("dsh-confirm-ok"),
    )
    // 移回共用 home 的确认：确认之后真发 deisolate-profile（confirm 走 body 顶层），
    // 关框与焦点回触发元素与删除确认框同一套。
    HomeDeisolateOpen(id, return_id) => (
      {
        ..model,
        drawer_id: "",
        home_confirm_id: id,
        home_confirm_return: return_id,
      },
      focus_after_render("dsh-home-confirm-ok"),
    )
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
        }
      }
    HomeDeisolateCancel => (
      { ..model, home_confirm_id: "" },
      focus_after_render(model.home_confirm_return),
    )
    // ── 配置历史（design/ops-maintenance-jobs.md §16.4）────────────
    // 创建快照是一条真实写动作：回执走全局提示，成功后重读读数 ——
    // 列表不在这里本地插一条，刷新的是读数，界面自己会变。
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
        }
      }
    SnapshotRestoreCancel => (
      { ..model, snapshot_confirm_id: "", snapshot_confirm_snap: "" },
      focus_after_render(model.snapshot_confirm_return),
    )
    // ── 整体替换（design/ops-maintenance-jobs.md §17.3）────────────
    // 打开侧栏：先收抽屉（两个都是右侧浮层，叠着摆会互相挡），焦点进侧栏的关闭键。
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
    PromoteConfirmOpen =>
      match model.promote_preview {
        Some(preview) =>
          if preview.blockers.length() > 0 {
            (model, @cmd.none)
          } else {
            ({ ..model, promote_confirm: true }, focus_after_render(promote_confirm_ok_id()))
          }
        None => (model, @cmd.none)
      }
    PromoteConfirmCancel => (
      { ..model, promote_confirm: false },
      focus_after_render("dsh-promote-apply"),
    )
    // 真的替换：body 顶层带 confirm: PROMOTE；回执走 HttpDone（成功后重读读数）
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
      }
    HealthDone(res) => health_settled(model, res, emit)
    HealthVisible =>
      if model.health_busy {
        ({ ..model, health_visible_wait: false }, @cmd.none)
      } else {
        ({ ..model, health_busy: true, health_visible_wait: false }, health_ping_cmd(emit))
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
    StartTick(id) =>
      if model.act_pending == id {
        finish_start({ ..model, act_tick: true }, emit)
      } else {
        (model, @cmd.none)
      }
    // 带令牌的地址还没到手：再重读一轮读数（有界，见 start_tab_max_tries）。
    // 地址到了就填、到不了就认输关标页 —— 两条路都在 fill_start_tab 里。
    StartTabRetry => refresh_readings(model, emit)
    // 抽屉里「安装缺的包（N）」：先开确认框（写 node_modules 是真动作，§39.1）。
    // 焦点进「安装」键；关掉之后回那颗按钮（见 RepairCancel 与原位按钮的 id）。
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
    CliHelpOpen(id) => ({ ..model, cli_help_id: id }, focus_after_render("dsh-cli-help-ok"))
    CliHelpClose => ({ ..model, cli_help_id: "" }, @cmd.none)
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
    // 与重命名 / 删除同一条口径（§30.1）：抽屉留着，关框之后焦点回抽屉里那颗「备注」。
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
    // ── 新建实例框（design/design-fixes.md §19.1）─────────────
    // 开框：清掉上一次的错与草稿。没有可用源时「从基础实例开始」默认勾上（§21.4）：
    // 这时它是唯一能走的路，名字预填 base-NN、焦点直接进名字格。
    // 有可用源就照旧把焦点落在第一张可点的源卡上；读数还没落地时卡都点不了，落在复选框上。
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
    NewInstanceNameInput(text) => (
      { ..model, new_name_draft: text, new_name_dirty: true, new_error: "" },
      @cmd.none,
    )
    // 创建：走既有 fork-profile（新副本默认隔离）。名字按输入框的原话发，
    // 空名字不带 newName —— 后端自己会按 <源>-dev 起一个。
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
      }
    NewInstanceDone(res) => {
      let (next, cmd) = new_instance_settled(model, res, emit)
      // 失败时把焦点拉回名字那一格：要改的就是那里
      if next.new_error != "" {
        (next, @cmd.batch([cmd, focus_select_after_render(new_instance_name_id())]))
      } else {
        (next, cmd)
      }
    }
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
    // ── 维护页（作业台） ──
    // 打开版本侧栏（§12.1）：清空搜索框、焦点进搜索框，并再读一次缓存。
    // 那一条接口现在只读后端进程内的缓存（秒回），所以「每次打开都读」不再是一笔等待。
    // 过滤与排序**不重置**：它们是使用者上一次挑的读法，关掉再开回来还该是那一套。
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
    VersionSidebarClose =>
      if !model.version_sidebar {
        (model, @cmd.none)
      } else {
        ({ ..model, version_sidebar: false, version_query: "" }, focus_after_render(version_choose_id()))
      }
    VersionQueryInput(text) => ({ ..model, version_query: text }, @cmd.none)
    // 过滤 chip：all = 全部（清空选择）；其余是开关，多选之间「或」。
    // 不认识的值一律不动模型 —— 界面只发那四个键，多一个也不该把过滤状态弄成空的。
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
    VersionSortPicked(key) =>
      if version_sort_known(key) {
        ({ ..model, version_sort: key }, @cmd.none)
      } else {
        (model, @cmd.none)
      }
    // 选中：回填表单并关闭侧栏，焦点回「选择版本」那颗按钮
    JobVersionPicked(version) => (
      { ..model, job_version: version, version_sidebar: false, version_query: "" },
      focus_after_render(version_choose_id()),
    )
    // 打开配置侧栏：焦点落在第一张可点的卡上（一张都没有时落在关闭键上）
    ProfileSidebarOpen => {
      let first = job_profile_first_usable(model)
      let focus = if first == "" {
        profile_sidebar_close_id()
      } else {
        job_profile_card_id(first)
      }
      ({ ..model, profile_sidebar: true }, focus_after_render(focus))
    }
    ProfileSidebarClose =>
      if !model.profile_sidebar {
        (model, @cmd.none)
      } else {
        ({ ..model, profile_sidebar: false }, focus_after_render(profile_choose_id()))
      }
    // 点一张可用的卡：回填并关闭侧栏，焦点回「选择配置」那颗按钮
    JobProfilePicked(name) => (
      { ..model, job_profile: name, profile_sidebar: false },
      focus_after_render(profile_choose_id()),
    )
    // 空态那颗「开始一条作业」：先滚到表单，再把焦点送进「当前版本」那一格。
    // 两步都是 after_render —— 顺序由 batch 保证：先滚（视口到位），后聚焦
    // （聚焦也会自己滚一次，那时已经离得很近了，不会再跳）。
    JobStartFocus => (
      model,
      @cmd.batch([
        scroll_into_view_after_render(version_choose_id()),
        focus_after_render(version_choose_id()),
      ]),
    )
    // 总览空态那颗「刷新读数」：与写动作成功之后同一条路（两份读数都重读）。
    // 特意不弹提示条：这是个「再读一遍」的动作，结果本来就会落在列表或空态上。
    RefreshReadings => refresh_readings(model, emit)
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
    ReleasesTick =>
      if releases_still_loading(model) && model.page is Maintenance {
        ({ ..model, releases_poll_pending: false }, load_releases(emit))
      } else {
        ({ ..model, releases_poll_pending: false }, @cmd.none)
      }
    // 手动重拉（§11.3）：立刻把按钮按成「正在重新拉取」（loading），排一趟后台刷新。
    // 补问计数清零：这是使用者亲手要的一次刷新，轮询预算该从头算。
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
    ReleasesRefreshDone(res) => {
      let (ok, note) = interpret_http(res)
      if !ok {
        (
          notice_err({ ..model, releases_loading: false }, "重新拉取没成：" + note),
          @cmd.none,
        )
      } else {
        (model, load_releases(emit))
      }
    }
    JobStart => job_start_command(model, emit)
    JobAction(id, step) => job_step_command(model, id, step, emit)
    JobToggle(id) => {
      let kept = model.job_collapsed.filter(fn(collapsed) { collapsed != id })
      if kept.length() == model.job_collapsed.length() {
        // 现在展开着 → 收起
        kept.push(id)
      }
      ({ ..model, job_collapsed: kept }, @cmd.none)
    }
    JobDone(action, res) => job_settled(model, action, res, emit)
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
    // 设置分组也是页面状态：切分组就换地址，刷新 / 后退都回到同一组。
    // 窄屏上这一步是「进第二级」：焦点落到返回键上，键盘接下来直接能退出去。
    // 宽屏两列同屏，点索引只是换右边的内容 —— 焦点留在点过的那一行才顺手，不挪。
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
    SettingsBack => (
      { ..model, settings_group: "", route_notice: "" },
      @cmd.batch([
        push_route(route_url(Settings, "", model.log_source)),
        focus_after_render(settings_row_dom_id(setting_group_of(model.settings_group).id)),
      ]),
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
    CopyDone(subject, res) => {
      let (ok, note, detail) = match res {
        Ok(text) => parse_copy_result(text)
        Err(err) => (false, "没能复制到剪贴板", "剪贴板调用没发出去：" + describe(err))
      }
      (notice_put(model, ok, subject + note, detail), @cmd.none)
    }
    // toast 到期：序号对不上说明这一条已经被换掉了（或已经收掉了），那一枪作废
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
          }
      }
    FlashRemove(serial) =>
      match model.notice {
        None => (model, @cmd.none)
        Some(n) => if n.seq == serial { (notice_clear(model), @cmd.none) } else { (model, @cmd.none) }
      }
    FlashHover(on) => ({ ..model, flash_hover: on }, @cmd.none)
    // 关于页：把某一份 dsh 指定成起实例用的那一版 / 撤掉指定回到自动
    DshVersionPin(dir, version) => pin_dsh_version(model, dir, version, emit)
    DshVersionUnpin => unpin_dsh_version(model, emit)
    Noop => (model, @cmd.none)
  }
}
