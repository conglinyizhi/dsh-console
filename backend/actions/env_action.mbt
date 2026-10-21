// 启动环境变量的写入口（design/design-fixes.md §61）。
//
// 一个动作 `save-env`：{ scope: "global" | "profile", home?, profile?, entries: {K: V} }，
// 整份替换该 scope 的表（界面上是一次增删改后的提交）。审计只记键名，不记值。

///|
/// 保存一份启动环境。返回回执用的 data（{action, outcome, note}），审计跟着它走。
pub async fn save_env_action(params : Json, action : String) -> @json.JsonVal raise ActionError {
  let scope = require_string(params, "scope")
  if scope != "global" && scope != "profile" {
    fail("bad-params", "scope 只认 global 或 profile，收到 " + scope)
    abort("unreachable: fail 一定抛错")
  }
  let entries_json = match @json.json_field(params, "entries") {
    Some(v) => v
    None => {
      fail("bad-params", "缺少参数 entries（{键: 值} 的对象）")
      abort("unreachable: fail 一定抛错")
    }
  }
  let entries : Map[String, String] = Map([])
  let keys : Array[String] = []
  for pair in @store.object_entries(entries_json) {
    let key = pair.0
    if !@store.env_key_allowed(key) {
      // 保留键（DSH_HOME / PATH …）与非法键名都不收：说清是哪一个
      fail("bad-params", "这个键不能由启动环境设置：" + key + "（控制台自己管它，或键名非法）")
      abort("unreachable: fail 一定抛错")
    }
    let value = match @json.json_string(pair.1) {
      Some(s) => s
      None => {
        fail("bad-params", "值要是字符串：" + key)
        abort("unreachable: fail 一定抛错")
      }
    }
    entries[key] = value
    keys.push(key)
  }
  let loaded = @store.load_env_file()
  let mut home = ""
  let mut profile = ""
  let file = if scope == "global" {
    { ..loaded, global: entries }
  } else {
    home = require_string(params, "home")
    profile = require_string(params, "profile")
    let key = @store.profile_env_key(home, profile)
    let profiles = Map(loaded.profiles.iter().collect())
    profiles[key] = entries
    { ..loaded, profiles }
  }
  match @store.save_env_file(file) {
    Ok(_) => ()
    Err(e) => {
      fail("io-error", e)
      abort("unreachable: fail 一定抛错")
    }
  }
  @json.JObj([
    ("action", @json.JStr(action)),
    (
      "outcome",
      @json.JObj([
        ("scope", @json.JStr(scope)),
        ("home", @json.JStr(home)),
        ("profile", @json.JStr(profile)),
        // 只记键名：值可能含密钥（§61.2）
        ("keys", @json.JStr(keys.join("、"))),
        ("count", @json.jint(keys.length())),
        ("path", @json.JStr(@store.env_file_path())),
      ]),
    ),
    (
      "note",
      @json.JStr(
        if scope == "global" {
          "启动环境（全局）已保存 " + keys.length().to_string() + " 个键"
        } else {
          profile + " 的启动环境已保存 " + keys.length().to_string() + " 个键"
        },
      ),
    ),
  ])
}
