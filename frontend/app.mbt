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
          @cmd.batch([
            load_runtime(emit),
            load_readings(emit),
            load_console(emit),
            load_releases(emit),
          ]),
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
/// 写动作成功之后刷新读数：重发 profiles + instances。
/// 两份都先置回「未落地」再发 —— 否则先回来的那一份会拿着旧的另一份拼一次列表，
/// 而那时 built 已经是 true，后回来的那一份就白读了（卡上还是动作前的老样子）。
fn refresh_readings(model : Model, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  (
    { ..model, built: false, read_profiles: false, read_instances: false, read_console: false },
    @cmd.batch([load_readings(emit), load_console(emit)]),
  )
}