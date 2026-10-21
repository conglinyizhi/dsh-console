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
  // suppressed（N9 增补）：上次有的键、这次没有、但它的对偶还在 → 记成「用户明确删掉的」，
  // 下次保存不再自动补回；这次显式写回的键从名单里移除。
  let prev_entries = if scope == "global" {
    loaded.global
  } else {
    let h = require_string(params, "home")
    let p = require_string(params, "profile")
    match loaded.profiles.get(@store.profile_env_key(h, p)) {
      Some(m) => m
      None => Map([])
    }
  }
  let suppressed : Array[String] = []
  for key in loaded.suppressed {
    if !entries.contains(key) {
      suppressed.push(key)
    }
  }
  for pair in prev_entries.iter() {
    let name = pair.0
    if entries.contains(name) {
      continue
    }
    let upper = name.to_upper()
    let lower = name.to_lower()
    let dual = if name == upper && upper != lower {
      lower
    } else if name == lower && upper != lower {
      upper
    } else {
      ""
    }
    if dual != "" && entries.contains(dual) && !suppressed.contains(name) {
      suppressed.push(name)
    }
  }
  let file = if scope == "global" {
    { ..loaded, global: entries, suppressed }
  } else {
    home = require_string(params, "home")
    profile = require_string(params, "profile")
    let key = @store.profile_env_key(home, profile)
    let profiles = Map(loaded.profiles.iter().collect())
    profiles[key] = entries
    { ..loaded, profiles, suppressed }
  }
  // options（§62.2）：可选；只认 keep_system 与 merge，别的值 bad-params
  let options = match @json.json_field(params, "options") {
    Some(opts_json) => {
      let keep_system = match @store.field_of(opts_json, "inherit") {
        Some(v) =>
          match @store.as_bool(v) {
            Some(b) => b
            None => {
              fail("bad-params", "options.inherit 要是布尔值")
              abort("unreachable: fail 一定抛错")
            }
          }
        None => loaded.options.keep_system
      }
      let merge = match @store.field_of(opts_json, "merge") {
        Some(v) =>
          match @store.as_string(v) {
            Some(m) =>
              if @store.env_merge_allowed(m) {
                m
              } else {
                fail("bad-params", "options.merge 只认 override 或 append，收到 " + m)
                abort("unreachable: fail 一定抛错")
              }
            None => {
              fail("bad-params", "options.merge 要是字符串")
              abort("unreachable: fail 一定抛错")
            }
          }
        None => loaded.options.merge
      }
      @store.EnvOptions::{ keep_system: keep_system, merge: merge }
    }
    None => loaded.options
  }
  let file = { ..file, options }
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