// 本地写接口的传输层：POST /api/local/action、GET/PUT /api/local/settings。
//
// 为什么不用 @http：rabbita 的 http 层在非 2xx 上把响应体丢掉，只留一句
// "HTTP 404 Not Found"；而契约要求把后端的错误码（conflict / not-authorized /
// spawn-failed …）与消息原样显示出来 —— 吞掉就违背了「失败要显示后端具体原因」。
// 它也没有给请求加自定义头的入口，而写接口必须带 X-DSH-Console。
//
// 所以这一层直接走 fetch，把 (状态码, 状态文本, 响应体) 一起带回来。
// 纪律：这里只负责把请求发出去、把原始结果拿回来；判定成败与拼文案都在 update 里做。

///|
/// 一次调用的结果。status = 0 表示请求根本没发出去（原因在 transport_error）。
struct HttpResult {
  status : Int
  status_text : String
  body : String
  transport_error : String
} derive(Eq)

pub extend HttpResult with Eq::{ not_equal, equal }

///|
/// 唯一的传输原语。响应收敛成一段 JSON 文本回来，
/// 免得在 MoonBit 这边跟 JS 对象与字段取值打交道。
extern "js" fn js_http_call(
  http_method : String,
  url : String,
  body : String,
  headers_json : String,
) -> @js.Promise =
  #| (method, url, body, headersJson) => {
  #|   const options = { method: method, headers: JSON.parse(headersJson) }
  #|   if (body !== '') { options.body = body }
  #|   return fetch(url, options).then(
  #|     async (res) => JSON.stringify({
  #|       status: res.status,
  #|       statusText: res.statusText,
  #|       body: await res.text(),
  #|       transportError: '',
  #|     }),
  #|     (err) => JSON.stringify({
  #|       status: 0,
  #|       statusText: '',
  #|       body: '',
  #|       transportError: String((err && err.message) || err),
  #|     }),
  #|   )
  #| }

///|
fn parse_http_result(text : String) -> HttpResult {
  let root = try @json.parse(text) catch {
    _ =>
      return {
        status: 0,
        status_text: "",
        body: "",
        transport_error: "传输层返回的不是合法 JSON",
      }
  }
  guard root is Json::Object(obj) else {
    return {
      status: 0,
      status_text: "",
      body: "",
      transport_error: "传输层返回的不是 JSON 对象",
    }
  }
  {
    status: int_or(obj, "status", 0),
    status_text: str_field(obj, "statusText"),
    body: str_field(obj, "body"),
    transport_error: str_field(obj, "transportError"),
  }
}

///|
/// 状态行的显示口径：「HTTP 404 Not Found」；读不到原因短语就只写数字。
fn http_status_text(result : HttpResult) -> String {
  if result.status_text == "" {
    "HTTP " + result.status.to_string()
  } else {
    "HTTP " + result.status.to_string() + " " + result.status_text
  }
}

///|
/// JSON 字符串字面量。只转义必须有转义的那几个字符：反斜杠、双引号、控制字符。
/// profile 名字的合法字符由后端把关（非法字符会被拒），这里不重复那套规则。
fn json_text_literal(text : String) -> String {
  let buf = StringBuilder()
  buf.write_char('"')
  for c in text {
    if c == '\\' {
      buf.write_string("\\\\")
    } else if c == '"' {
      buf.write_string("\\\"")
    } else if c.to_int() < 32 {
      buf.write_char(' ')
    } else {
      buf.write_char(c)
    }
  }
  buf.write_char('"')
  buf.to_string()
}

///|
/// POST /api/local/action 的请求体：{ action, params }。
fn action_body(action : String, params : String) -> String {
  "{\"action\":" + json_text_literal(action) + ",\"params\":" + params + "}"
}

///|
/// 带二次确认串的请求体：{ action, params, confirm }。
///
/// confirm 在**顶层**：契约第一节写的是「body 里还必须带 "confirm":"DELETE"」，
/// 后端也是从顶层读的（handle_action 里的 json_field(json, "confirm")）。
/// 塞进 params 里后端读不到，硬删与彻底删除都会以 bad-params 告终 ✗。
fn action_body_with_confirm(action : String, params : String, confirm : String) -> String {
  "{\"action\":" + json_text_literal(action) + ",\"params\":" + params + ",\"confirm\":" +
  json_text_literal(confirm) + "}"
}

///|
/// 写接口的固定头。X-DSH-Console 是契约里的跨源闸门：浏览器不允许跨源带自定义头，
/// 本机别的页面因此发不出这个请求。Origin 由浏览器自己带（同源 POST 会带）。
fn write_headers() -> String {
  "{\"Content-Type\":\"application/json\",\"X-DSH-Console\":\"1\"}"
}

///|
/// GET /api/local/settings。要状态码的那种读法：404 / 501 得如实显示出来，
/// 不能像 @http 那样只留一句「HTTP 404」把响应体丢掉。
fn settings_get_cmd(emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.attempt(
    fn(res : Result[String, Error]) { emit(SettingsText(res)) },
    async fn() {
      let text : String = js_http_call("GET", "/api/local/settings", "", "{}").wait().cast()
      text
    },
  )
}

///|
/// PUT /api/local/settings。
fn settings_put_cmd(key : String, body : String, emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.attempt(
    fn(res : Result[String, Error]) { emit(SettingsSaved(key, res)) },
    async fn() {
      let text : String = js_http_call(
        "PUT",
        "/api/local/settings",
        body,
        write_headers(),
      ).wait().cast()
      text
    },
  )
}

///|
/// POST /api/local/action。row_id / label 原样带回 update，用来决定这一枪打中了谁。
fn action_cmd(
  row_id : String,
  action : String,
  label : String,
  body : String,
  emit : @cmd.Emit[Msg],
) -> @cmd.Cmd {
  @cmd.attempt(
    fn(res : Result[String, Error]) { emit(HttpDone(row_id, action, label, res)) },
    async fn() {
      let text : String = js_http_call(
        "POST",
        "/api/local/action",
        body,
        write_headers(),
      ).wait().cast()
      text
    },
  )
}
