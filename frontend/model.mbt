// 只读接口的数据模型与解析。
//
// 纪律（与后端、与 Vue 版一致）：读不到就写「未知」并把原因留在界面上，不编数字。
// 这里只做「外壳 → 字段」的取值，不做业务推导。

///|
/// GET /api/local/runtime 的 data 里关于页要的那几行。
pub(all) struct RuntimeFacts {
  dsh_version : String
  dsh_package_name : String
  console_version : String
  console_package_name : String
  platform : String
} derive(Eq)

pub extend RuntimeFacts with Eq::{ not_equal, equal }

///|
/// 一个被签名命中的运行中实例（data.instances[i]）。
///
/// 只留卡片真正要用的字段：探测走的是一次未授权 GET，实例自己的版本 /
/// DSH_HOME / 插件数都读不到，那几项在界面上如实写「未知」，不进这个结构。
pub(all) struct InstanceFact {
  port : Int
  url : String
  http_status : Int
  signature_id : String
  profile : String
  uptime_seconds : Int?
} derive(Eq)

pub extend InstanceFact with Eq::{ not_equal, equal }

///|
fn str_field(obj : Map[String, Json], key : String) -> String {
  match obj.get(key) {
    Some(Json::String(s)) => s
    _ => ""
  }
}

///|
/// 只读接口的 JSON 数值都是整数读法：带小数就取整，别处用不到小数。
fn int_field(obj : Map[String, Json], key : String) -> Int? {
  match obj.get(key) {
    Some(Json::Number(n, ..)) => Some(n.to_int())
    _ => None
  }
}

///|
/// 外壳里 ok=false 时的错误文案：优先用接口给的 message，其次 code，都没有才兜底。
fn envelope_error(envelope : Map[String, Json]) -> String {
  match envelope.get("error") {
    Some(Json::Object(err)) =>
      match (str_field(err, "code"), str_field(err, "message")) {
        ("", "") => "接口返回 ok=false"
        (code, "") => code
        ("", message) => message
        (code, message) => code + ": " + message
      }
    _ => "接口返回 ok=false"
  }
}

///|
/// 打开响应外壳，拿到 data 对象。
///
/// 三个失败点各自有话说：不是 JSON、不是外壳、ok=false —— 都带上能对上号的措辞，
/// 界面直接展示，不吞。
fn open_envelope(text : String) -> Result[Map[String, Json], String] {
  let root = try @json.parse(text) catch {
    _ => return Err("响应不是合法 JSON")
  }
  guard root is Json::Object(envelope) else {
    return Err("响应外壳不是 JSON 对象")
  }
  match envelope.get("ok") {
    Some(Json::True) => ()
    _ => return Err(envelope_error(envelope))
  }
  match envelope.get("data") {
    Some(Json::Object(data)) => Ok(data)
    _ => Err("响应里没有 data 对象")
  }
}

///|
pub fn parse_runtime(text : String) -> Result[RuntimeFacts, String] {
  let data = match open_envelope(text) {
    Ok(data) => data
    Err(reason) => return Err(reason)
  }
  Ok({
    dsh_version: str_field(data, "dshVersion"),
    dsh_package_name: str_field(data, "dshPackageName"),
    console_version: str_field(data, "consoleVersion"),
    console_package_name: str_field(data, "consolePackageName"),
    platform: str_field(data, "platform"),
  })
}

///|
pub fn parse_instances(text : String) -> Result[Array[InstanceFact], String] {
  let data = match open_envelope(text) {
    Ok(data) => data
    Err(reason) => return Err(reason)
  }
  let raw = match data.get("instances") {
    Some(Json::Array(items)) => items
    _ => return Err("响应里没有 instances 数组")
  }
  let out : Array[InstanceFact] = []
  for item in raw {
    guard item is Json::Object(fact) else { continue }
    let signature_id = match fact.get("signature") {
      Some(Json::Object(sig)) => str_field(sig, "id")
      _ => ""
    }
    out.push({
      port: match int_field(fact, "port") {
        Some(p) => p
        None => 0
      },
      url: str_field(fact, "url"),
      http_status: match int_field(fact, "httpStatus") {
        Some(s) => s
        None => 0
      },
      signature_id,
      profile: str_field(fact, "profile"),
      uptime_seconds: int_field(fact, "uptimeSeconds"),
    })
  }
  Ok(out)
}
