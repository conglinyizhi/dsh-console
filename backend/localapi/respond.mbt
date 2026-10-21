// 本地只读接口的响应外壳。
//
// 形状与 Node 版 dsh-console/server/localApi.mjs 逐字段一致：
//   成功 { ok: true, readOnly: true, readAt, data }
//   失败 { ok: false, readOnly: true, [readAt], error: { code, message } }
// 每个响应都带 Content-Type / Cache-Control: no-store / X-Local-Api: read-only。

///|
pub let header_content_type : String = "Content-Type"

///|
pub let header_cache_control : String = "Cache-Control"

///|
pub let header_local_api : String = "X-Local-Api"

///|
pub let header_allow : String = "Allow"

///|
pub let content_type_json : String = "application/json; charset=utf-8"

///|
pub let cache_control_no_store : String = "no-store"

///|
pub let local_api_read_only : String = "read-only"

///|
/// 拼响应头。base_headers 放 Content-Type，extra 依次追加。
fn build_headers(extra : Array[(String, String)]) -> @moonback.Headers {
  let h = @moonback.MutHeaders::MutHeaders()
  h.set(header_content_type, content_type_json)
  h.set(header_cache_control, cache_control_no_store)
  h.set(header_local_api, local_api_read_only)
  for pair in extra {
    h.set(pair.0, pair.1)
  }
  h.to_immut()
}

///|
/// 写 JSON 响应体。
pub async fn send_json(
  res : @moonback.Responder,
  status : Int32,
  payload : @json.JsonVal,
  extra_headers~ : Array[(String, String)] = [],
) -> Unit {
  let headers = match extra_headers {
    [] => build_headers([])
    extra => build_headers(extra)
  }
  let writer = res.respond(status~, headers~)
  writer.write(@json.encode(payload))
}

///|
/// 成功外壳：{ ok, readOnly, readAt, data }。
pub async fn send_ok(
  res : @moonback.Responder,
  data : @json.JsonVal,
  read_at : String,
) -> Unit {
  send_json(
    res,
    200,
    @json.JObj([
      ("ok", @json.JBool(true)),
      ("readOnly", @json.JBool(true)),
      ("readAt", @json.JStr(read_at)),
      ("data", data),
    ]),
  )
}

///|
/// 失败外壳：{ ok, readOnly, readAt?, error }。readAt 只有读到一半失败时才带。
pub async fn send_error(
  res : @moonback.Responder,
  status : Int32,
  code : String,
  message : String,
  read_at~ : String? = None,
  extra_headers~ : Array[(String, String)] = [],
) -> Unit {
  let fields : Array[(String, @json.JsonVal)] = [
    ("ok", @json.JBool(false)),
    ("readOnly", @json.JBool(true)),
  ]
  match read_at {
    Some(t) => fields.push(("readAt", @json.JStr(t)))
    None => ()
  }
  fields.push(
    (
      "error",
      @json.JObj([("code", @json.JStr(code)), ("message", @json.JStr(message))]),
    ),
  )
  send_json(res, status, @json.JObj(fields), extra_headers~)
}
