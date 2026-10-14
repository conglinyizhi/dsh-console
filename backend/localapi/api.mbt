// 路由分发。与 Node 版 localApi.mjs 的守卫顺序一致：
//   1. 非 GET        -> 405 + Allow: GET + method-not-allowed
//   2. 未注册路径    -> 404 + not-found
//   3. 命中          -> 200 + { ok, readOnly, readAt, data }
//   4. 读取抛错      -> 500 + { ok, readOnly, readAt, error: { code, message } }

///|
/// 一个只读接口。
pub struct Api {
  path : String
  handler : async () -> @json.JsonVal raise ReadError
}

///|
/// 构造一条路由。
pub fn api(path : String, handler : async () -> @json.JsonVal raise ReadError) -> Api {
  { path, handler }
}

///|
/// 需要读查询串的只读接口（logs 要 source / tail）。
pub struct QueryApi {
  path : String
  handler : async (@moonback.Request) -> @json.JsonVal raise ReadError
}

///|
/// 构造一条带查询串的路由。
pub fn query_api(
  path : String,
  handler : async (@moonback.Request) -> @json.JsonVal raise ReadError,
) -> QueryApi {
  { path, handler }
}

///|
/// 取查询参数（已做 percent-decode）。
/// Node 版用 URL.searchParams.get()：参数出现但没值时给空串，不区分「没有」和「空」。
pub fn query_param(req : @moonback.Request, name : String) -> String? {
  req.query().get(name)
}

///|
/// 读取失败的携带码错误。code 为空时按 read-failed 处理（与 Node 版一致）。
pub(all) suberror ReadError {
  ReadError(code~ : String, message~ : String)
}

///|
/// 抛一个带 code 的读错误。
pub fn fail_read(code : String, message : String) -> Unit raise ReadError {
  raise ReadError(code~, message~)
}

///|
/// 从路由表里找 handler。
fn find_api(apis : Array[Api], path : String) -> (async () -> @json.JsonVal raise ReadError)? {
  for r in apis {
    if r.path == path {
      return Some(r.handler)
    }
  }
  None
}

///|
/// 从带查询串的路由表里找 handler。
fn find_query_api(
  apis : Array[QueryApi],
  path : String,
) -> (async (@moonback.Request) -> @json.JsonVal raise ReadError)? {
  for r in apis {
    if r.path == path {
      return Some(r.handler)
    }
  }
  None
}

///|
/// HTTP 方法名的大写形式，与 Node 版 req.method 一致（GET / POST / ...）。
pub fn method_name(meth : @async_http.RequestMethod) -> String {
  match meth {
    @async_http.Get => "GET"
    @async_http.Head => "HEAD"
    @async_http.Post => "POST"
    @async_http.Put => "PUT"
    @async_http.Delete => "DELETE"
    @async_http.Connect => "CONNECT"
    @async_http.Options => "OPTIONS"
    @async_http.Trace => "TRACE"
    @async_http.Patch => "PATCH"
  }
}

///|
/// 纯路径匹配（不含 query），对应 Node 版 req.url.split('?')[0]。
fn path_of(path : StringView) -> String {
  let url = path.to_owned()
  match url.find("?") {
    Some(i) => url[:i].to_owned()
    None => url
  }
}

///|
/// 分发一个请求。
pub async fn dispatch(
  req : @moonback.Request,
  res : @moonback.Responder,
  apis : Array[Api],
  query_apis : Array[QueryApi],
  read_at : String,
) -> Unit {
  let path = path_of(req.path)
  if req.meth != @async_http.Get {
    send_error(
      res,
      405,
      "method-not-allowed",
      "本地接口只提供 GET，收到 " + method_name(req.meth),
      extra_headers=[(header_allow, "GET")],
    )
    return
  }
  let query_handler = find_query_api(query_apis, path)
  match query_handler {
    Some(f) => {
      try {
        let data = f(req)
        send_ok(res, data, read_at)
      } catch {
        ReadError(code~, message~) => {
          let code = if code == "" { "read-failed" } else { code }
          send_error(res, status_for(code), code, message, read_at=Some(read_at))
        }
        err => send_error(res, 500, "read-failed", err.to_string(), read_at=Some(read_at))
      }
      return
    }
    None => ()
  }
  let handler = find_api(apis, path)
  match handler {
    None =>
      send_error(res, 404, "not-found", "没有这个只读接口：" + path)
    Some(f) =>
      try {
        let data = f()
        send_ok(res, data, read_at)
      } catch {
        ReadError(code~, message~) => {
          let code = if code == "" { "read-failed" } else { code }
          send_error(res, status_for(code), code, message, read_at=Some(read_at))
        }
        err => send_error(res, 500, "read-failed", err.to_string(), read_at=Some(read_at))
      }
  }
}

///|
/// 与 Node 版一致的 HTTP 状态映射：只有 source/tail 类参数错误是 400，其余 500。
fn status_for(code : String) -> Int {
  match code {
    "unknown-source" | "bad-tail" | "missing-source" => 400
    _ => 500
  }
}