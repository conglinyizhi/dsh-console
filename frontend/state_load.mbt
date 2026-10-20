// 读数加载：runtime / releases / console / profiles / instances 那一组 GET 命令，日志页的
// 读取与来源默认值，以及「这份读数是不是还在路上」的数据源标记（fallback_tag / pending_tag）。
//
// 2026-10-20 从 state_rows.mbt 拆出来：请求发送与行构造不是一件事，拆开之后改行构造
// 不必翻一屏的 cmd。只搬位置，函数体一个字没改。


///|
/// 只重读 /api/local/runtime。
///
/// 单独一条是为了「改完生效版本」那一处（见 app.mbt 的 dsh_pin_settled）：
/// 版本变了只需要重读这一份读数，不该顺带把列表用的那三份读数重拼一遍 ——
/// 重拼会让总览页白白闪一次，而实例一只都没变。
fn load_runtime(emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @http.get("/api/local/runtime").expect_text(emit.map(fn(res) { RuntimeText(res) }))
}

///|
/// 「还在拉」时补问的间隔与上限（design/ops-maintenance-jobs.md §10.1）。
///
/// 后端那条 GET 只回进程内缓存、秒回，所以第一趟可能还没落地：读到 loading 就隔一拍
/// 再问一次。上限 10 拍约 8 秒，长过三个源各自 6 秒的硬超时，也够网络慢的那一档回来；
/// 再读不到就停手，把「正在拉版本列表」留在页面上，等下一次打开侧栏或进这一页再问。
let releases_poll_ms : Int = 800

///|
let releases_poll_cap : Int = 10

///|
/// 读数里还写着「有一趟在路上」没有。没有读数（接口都没读到）不算在拉 —— 那一档
/// 走 releases_error，页面上有自己的说法，不该被轮询盖住。
fn releases_still_loading(model : Model) -> Bool {
  match model.releases {
    Some(facts) => facts.state == "loading"
    None => false
  }
}

///|
/// GET /api/local/dsh-releases：能装哪一版 dsh。
///
/// 后端起来时就在后台拉一次，这条接口只读进程内缓存、秒回；缓存空时也立刻回
/// state=loading（同时确保后台在拉）。所以这一条请求不会拖住首屏或侧栏 ——
/// 「还在拉」由上面的补问接上（见 app.mbt 的 ReleasesText / ReleasesTick）。
/// 三个源全没答上来也算读到了（回执里 sources 全是 ok=false，state=failed 带原因）。
fn load_releases(emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @http.get("/api/local/dsh-releases").expect_text(emit.map(fn(res) { ReleasesText(res) }))
}

///|
/// 版本表过滤 chip 的键（§12.3）：installed / stable / prerelease。
/// 「全部」不在这里 —— 它是**清空选择**，不是一个与另外三个并列的过滤条件
/// （并列的话「全部 + 已安装」会互相打架）。
fn version_filter_known(key : String) -> Bool {
  key == "installed" || key == "stable" || key == "prerelease"
}

///|
/// 排序三档（§12.3）：new 从新到旧 / old 从旧到新 / published 按发布时间。
fn version_sort_known(key : String) -> Bool {
  key == "new" || key == "old" || key == "published"
}

///|
/// GET /api/local/console：运行时登记 + 归档记录。卡片上的「由本控制台启动」与归档区
/// 都按这份读数来；它读不到不影响别的读数，只是少这两处标记。
fn load_console(emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @http.get("/api/local/console").expect_text(emit.map(fn(res) { ConsoleText(res) }))
}

///|
/// profiles + instances 两个读数。写动作成功之后单独重发这一对：
/// 「刷新读数」刷新的是这两份，runtime 不随动作变。
///
/// 重发之前要把 read_profiles / read_instances 重新置回未落地（见 app.mbt 的 refresh_readings）——
/// 否则先回来的那一份会拿着旧的另一份把列表拼一次，而 built 已经是 true，后回来的那份就白读了。
fn load_readings(emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.batch([
    @http.get("/api/local/profiles").expect_text(emit.map(fn(res) { ProfilesText(res) })),
    @http.get("/api/local/instances").expect_text(emit.map(fn(res) { InstancesText(res) })),
  ])
}

///|
/// 日志页的读数：尾部行数由设置决定（读不到就是契约缺省 200），上限由接口负责截断并说明。
fn load_logs(source : String, tail : Int, emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  let query = "/api/local/logs?source=" + js_encode_uri_component(source) + "&tail=" +
    tail.to_string()
  @http.get(query).expect_text(emit.map(fn(res) { LogsText(res) }))
}

///|
/// 发起一次日志读取：先把加载态立起来（回执 LogsText 再放下去），读完滚到底。
///
/// 打开日志页、换来源、点刷新、点卡上的「查看日志」都走这一条 —— 四处各写一遍
/// 「记得置 log_loading」迟早会漏一处，漏掉的那处就会把「正在读」显示成「没有行」。
fn start_logs(model : Model, source : String, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  (
    { ..model, log_source: source, log_loading: true },
    @cmd.batch([
      load_logs(source, log_tail_of(model), emit),
      scroll_bottom_after_render("dsh-log-box"),
    ]),
  )
}

///|
/// 日志页默认尾部行数：设置读到就用设置里的 logs.defaultTail，读不到用契约缺省 200。
/// 这一项是「真能配置」的：它在日志页的请求串上真的生效，不是只显示一个数字。
fn log_tail_of(model : Model) -> Int {
  match model.settings {
    Some(facts) =>
      match lookup_setting(facts.values, "logs.defaultTail") {
        Some(VInt(n)) => n
        _ => 200
      }
    None => 200
  }
}
