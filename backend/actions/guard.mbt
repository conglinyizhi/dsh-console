// 写动作的守卫：自定义头 + Origin 校验（契约第一节）。
//
// 后端只绑 127.0.0.1，但本机其它程序与浏览器页面都能发请求：
//   1. X-DSH-Console: 1 —— 浏览器不允许跨源请求带自定义头，预检会先挡掉；
//   2. Origin 校验 —— 缺失（curl 直连 / 同源导航）放行，存在则必须是本机回环来源。
// 对「本机恶意进程」不设防：那一层不在这轮范围（契约里写明了）。

///|
/// 必须带的请求头。
pub let header_dsh_console : String = "X-DSH-Console"

///|
/// Origin 头。
pub let header_origin : String = "Origin"

///|
/// 请求头值是不是「是控制台前端」。
fn has_console_header(req : @moonback.Request) -> Bool {
  match req.headers.get(header_dsh_console) {
    Some(raw) => @json.trim_both(@json.owned(raw)) == "1"
    None => false
  }
}

///|
/// 从 "scheme://host[:port][/path]" 里取 host。取不出来给 None。
pub fn origin_host(origin : String) -> String? {
  let text = @json.trim_both(origin)
  if text == "" {
    return None
  }
  let rest = match text.find("://") {
    Some(i) => @json.slice_from(text, i + 3)
    None => return None
  }
  let host_port = match rest.find("/") {
    Some(i) => @json.slice(rest, 0, i)
    None => rest
  }
  if host_port == "" {
    return None
  }
  // 裸 IPv6（不带方括号、不带端口）单独认一次，免得被下面的端口切分切坏
  if host_port == "::1" {
    return Some("::1")
  }
  if host_port.has_prefix("[") {
    return match host_port.find("]") {
      Some(i) => Some(@json.slice(host_port, 1, i))
      None => None
    }
  }
  match host_port.rev_find(":") {
    Some(i) => Some(@json.slice(host_port, 0, i))
    None => Some(host_port)
  }
}

///|
/// Origin 是否可信：只认本机回环（127.0.0.1 / localhost / [::1]），端口不限 ——
/// 前端可能跑在别的端口上（vite 代理、另一个控制台实例），挡的是「外部站点」。
pub fn origin_allowed(origin : String) -> Bool {
  match origin_host(origin) {
    Some(host) => host == "127.0.0.1" || host == "localhost" || host == "::1"
    None => false
  }
}

///|
/// 守卫。不通过就抛 not-authorized（403）。
pub fn authorize(req : @moonback.Request) -> Unit raise ActionError {
  if !has_console_header(req) {
    fail(
      "not-authorized",
      "缺少 " +
      header_dsh_console +
      ": 1 请求头；写动作只接受控制台前端发起的请求",
    )
  }
  match req.headers.get(header_origin) {
    None => ()
    Some(raw) => {
      let origin = @json.owned(raw)
      if !origin_allowed(origin) {
        fail(
          "not-authorized",
          "Origin 不被信任：" +
          origin +
          "；写动作只接受本机同源页面（http://127.0.0.1 / http://localhost / http://[::1]）",
        )
      }
    }
  }
}
