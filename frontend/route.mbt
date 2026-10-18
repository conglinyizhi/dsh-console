// URL 路由：页面状态 ↔ 地址栏。纯前端，history.pushState 写、popstate 读。
//
// 为什么是路径而不是 hash：后端静态服务带 SPA 回退（backend/dist_static 的
// history_fallback 指向 /index.html），/settings/process 这种没有对应文件的路径
// 刷新时拿到的还是同一份 index.html，应用起来之后按 pathname 复原页面 ——
// 不用改后端就能让刷新落回原处。换成 hash 也能落回，但地址里会永远挂一个 #。
//
// 路由表（唯一一份，解析与拼接都在这里）：
//   /                     实例总览
//   /maintenance          维护（作业台）
//   /logs[?source=…]      日志（来源是页面状态的一部分，跟着进 URL）
//   /settings             设置（第一个分组）
//   /settings/<分组 id>   设置（某个分组）
//   /trash                回收站
//   /about                关于
//
// 认不出来的地址不白屏：总览那一段回落总览，设置那一段回落设置首页，
// 并把「为什么回落」写成一句话交给界面显示（Model.route_notice）。

///|
/// 浏览器当前的 path + search。hash 不参与：状态全在 path 与 query 上。
extern "js" fn js_location_url() -> String =
  #| () => location.pathname + location.search

///|
/// 写一条历史记录。地址没变就不写 —— 同一个页面连点两次侧栏不该攒两条一样的记录。
extern "js" fn js_push_url(url : String) -> Unit =
  #| url => {
  #|   if (location.pathname + location.search !== url) history.pushState(null, '', url)
  #| }

///|
/// 改写当前这条记录。用在「回落」与「来源自动定下来」这两处：
/// 它们都不是用户走的一步，不该在后退里多出一格。
extern "js" fn js_replace_url(url : String) -> Unit =
  #| url => {
  #|   if (location.pathname + location.search !== url) history.replaceState(null, '', url)
  #| }

///|
/// query 值解码。解不出来（手写的坏转义）就原样返回：来源认不出会走默认那一档，
/// 不在这一层编一个值出来。
extern "js" fn js_decode_uri_component(text : String) -> String =
  #| text => {
  #|   try { return decodeURIComponent(text) } catch (e) { return text }
  #| }

///|
/// 等下一次 popstate。一次只等一个：回执走 RouteChanged，update 里读一次**当前**地址
/// （不是事件里那份 —— 连着点两次后退也只会读到最新的一条）再把监听挂回去。
extern "js" fn js_next_popstate() -> @js.Promise =
  #| () => new Promise((resolve) => {
  #|   const onPop = () => { window.removeEventListener('popstate', onPop); resolve('popstate') }
  #|   window.addEventListener('popstate', onPop)
  #| })

///|
/// 一条地址解析出来的路由。notice 非空 = 这个地址认不出来，已按上面几项回落。
priv struct Route {
  page : Page
  /// 设置页的分组 id（**只在 page 是 Settings 时有值**）。
  /// 别的页面上它是空串，不是「默认分组」—— 切到别的页面不该把用户记住的那个分组抹掉，
  /// 抹掉之后从「关于」再点回「设置」就跳回第一组了。
  group : String
  /// 日志来源；None = 地址里没写，按默认来源推导（用户没自己挑过就跟着读数走）
  source : String?
  /// 认不出这个地址的原因，界面上原样显示
  notice : String
}

///|
/// 按第一个分隔字符切成两段。找不到分隔符时右段是空串。
fn split_once(text : String, sep : Char) -> (String, String) {
  let left = StringBuilder()
  let right = StringBuilder()
  let mut seen = false
  for c in text {
    if !seen && c == sep {
      seen = true
      continue
    }
    if seen {
      right.write_char(c)
    } else {
      left.write_char(c)
    }
  }
  (left.to_string(), right.to_string())
}

///|
fn split_all(text : String, sep : Char) -> Array[String] {
  let out : Array[String] = []
  if text.length() == 0 {
    return out
  }
  let mut buf = StringBuilder()
  for c in text {
    if c == sep {
      out.push(buf.to_string())
      buf = StringBuilder()
    } else {
      buf.write_char(c)
    }
  }
  out.push(buf.to_string())
  out
}

///|
/// 路径切成段：重复的 / 与结尾的 / 都不算数（"/settings/" 与 "/settings" 同一条）。
fn path_segments(path : String) -> Array[String] {
  let out : Array[String] = []
  let mut buf = StringBuilder()
  for c in path {
    if c == '/' {
      let seg = buf.to_string()
      if seg.length() > 0 {
        out.push(seg)
      }
      buf = StringBuilder()
    } else {
      buf.write_char(c)
    }
  }
  let last = buf.to_string()
  if last.length() > 0 {
    out.push(last)
  }
  out
}

///|
/// query 里的一个键。只认 source，别的键忽略：地址是给人看的，
/// 多带一个参数不该让页面出岔子。
fn query_value(query : String, key : String) -> String? {
  for pair in split_all(query, '&') {
    let (name, raw) = split_once(pair, '=')
    if name == key && raw.length() > 0 {
      return Some(js_decode_uri_component(raw))
    }
  }
  None
}

///|
/// 来源白名单的口径：固定来源 host / audit，加 instance:<实例 id>。
/// 形如实例来源就先收下 —— 实例列表这会儿可能还没读回来，真不在了由日志接口
/// 回一句错误、界面照实显示，不在这里猜一个「它不在了」出来。
fn known_log_source(source : String) -> Bool {
  if source == "host" || source == "audit" {
    return true
  }
  let prefix = "instance:"
  source.length() > prefix.length() && source[0:prefix.length()] == prefix
}

///|
/// 现有分组 id 的列举，写进回落提示里：说清「你要的那个不在，在的是这几个」。
fn settings_group_ids() -> String {
  join_with(settings_groups.map(fn(group) { group.id }), " / ")
}

///|
/// /logs：来源写在 query 上。写了个认不出来的来源就走默认来源，
/// 但要把原因说清 —— 悄悄换一个来源比说一句更糟。
fn logs_route(query : String) -> Route {
  match query_value(query, "source") {
    None => { page: Logs, group: "", source: None, notice: "" }
    Some(raw) =>
      if known_log_source(raw) {
        { page: Logs, group: "", source: Some(raw), notice: "" }
      } else {
        {
          page: Logs,
          group: "",
          source: None,
          notice: "地址里的日志来源「" + raw +
            "」认不出来（只认 host / audit / instance:<实例 id>），已按默认来源读。",
        }
      }
  }
}

///|
/// 地址 → 路由。认不出来的地址一律落到能看懂的那一页，并把原因写进 notice。
fn parse_route(url : String) -> Route {
  let (raw_path, query) = split_once(url, '?')
  let segs = path_segments(raw_path)
  let home = settings_groups[0].id
  if segs.length() == 0 {
    return { page: Overview, group: "", source: None, notice: "" }
  }
  match segs[0] {
    "maintenance" =>
      if segs.length() == 1 {
        { page: Maintenance, group: "", source: None, notice: "" }
      } else {
        unknown_route(segs)
      }
    "logs" =>
      if segs.length() == 1 {
        logs_route(query)
      } else {
        unknown_route(segs)
      }
    "settings" =>
      if segs.length() == 1 {
        { page: Settings, group: home, source: None, notice: "" }
      } else if segs.length() == 2 && settings_group_exists(segs[1]) {
        { page: Settings, group: segs[1], source: None, notice: "" }
      } else {
        {
          page: Settings,
          group: home,
          source: None,
          notice: "地址里的 /" + join_with(segs, "/") + " 对不上任何一个设置分组（现有分组：" +
            settings_group_ids() + "），已回到设置首页。",
        }
      }
    "trash" =>
      if segs.length() == 1 {
        { page: Trash, group: "", source: None, notice: "" }
      } else {
        unknown_route(segs)
      }
    "about" =>
      if segs.length() == 1 {
        { page: About, group: "", source: None, notice: "" }
      } else {
        unknown_route(segs)
      }
    _ => unknown_route(segs)
  }
}

///|
/// 认不出来的那一段：回落总览，并把认得的几条列出来。
fn unknown_route(segs : Array[String]) -> Route {
  {
    page: Overview,
    group: "",
    source: None,
    notice: "地址里的 /" + join_with(segs, "/") +
      " 不是本控制台的路由，已回到实例总览。现有路由：/ | /maintenance | /logs | /settings/<分组> | /trash | /about",
  }
}

///|
/// 页面状态 → 地址。与 parse_route 是同一张表的两个方向。
fn route_url(page : Page, group : String, source : String) -> String {
  match page {
    Overview => "/"
    Maintenance => "/maintenance"
    Logs =>
      if source == "" {
        "/logs"
      } else {
        "/logs?source=" + js_encode_uri_component(source)
      }
    Settings =>
      if settings_group_exists(group) {
        "/settings/" + group
      } else {
        "/settings"
      }
    Trash => "/trash"
    About => "/about"
  }
}

///|
/// 走一步：写一条历史记录。用户点出来的页面切换都走它，前进 / 后退因此可用。
fn push_route(url : String) -> @cmd.Cmd {
  @cmd.custom_cmd(fn(_scheduler) { js_push_url(url) })
}

///|
/// 不算一步：改写当前记录。回落与「来源自动定下来」用它。
fn replace_route(url : String) -> @cmd.Cmd {
  @cmd.custom_cmd(fn(_scheduler) { js_replace_url(url) })
}

///|
/// 挂上下一次 popstate 的监听。回执一进 update 就再挂一次，任何时刻只有一个在等。
fn listen_popstate(emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.attempt(
    fn(_res : Result[String, Error]) { emit(RouteChanged) },
    async fn() {
      let text : String = js_next_popstate().wait().cast()
      text
    },
  )
}
