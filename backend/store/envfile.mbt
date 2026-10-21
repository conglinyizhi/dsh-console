// 启动环境变量：全局一份 + 每个 profile 可覆盖（design/design-fixes.md §61）。
//
// 位置：$XDG_CONFIG_HOME/dsh-console/env.json（缺省 ~/.config/dsh-console/env.json），权限 600，
// 原子写（临时文件 + rename）。结构：
//   { "global": { "K": "V" }, "profiles": { "<home>|<profile>": { "K": "V" } } }
//
// 为什么单独一份文件而不塞进 settings.json：设置项是「一个键一个值」的封闭契约，
// 这里是任意键值表，塞进去会把那一套读法 / 校验 / 回显全撑变形（§61.5）。

///|
/// 读出来的两份表。profiles 的键是 `home + "|" + profile`（与行 id 同一口径，隔离的同名不会混）。
pub(all) struct EnvFile {
  global : Map[String, String]
  profiles : Map[String, Map[String, String]]
}

///|
/// 控制台自己必须管住的键：这些不许被启动环境覆盖（§61.2）。界面据此置灰。
pub fn reserved_env_keys() -> Array[String] {
  [
    "DSH_HOME",
    "PATH",
    "HOME",
    "PWD",
    "TMPDIR",
    "DSH_PROFILE",
  ]
}

///|
/// 这个键能不能被启动环境覆盖。
pub fn env_key_allowed(key : String) -> Bool {
  if key == "" {
    return false
  }
  // 只认「字母 / 数字 / 下划线」的键名：别把奇怪东西塞进子进程环境
  for ch in key {
    let code = ch.to_int()
    let ok = (code >= 48 && code <= 57) || (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) || ch == '_'
    if !ok {
      return false
    }
  }
  !reserved_env_keys().contains(key)
}

///|
/// profiles 表里的一把键。
pub fn profile_env_key(home : String, profile : String) -> String {
  home + "|" + profile
}

///|
/// env.json 的落点。
pub async fn env_file_path() -> String noraise {
  let base = match @json.env_value("XDG_CONFIG_HOME") {
    Some(v) if v.has_prefix("/") => v
    _ =>
      match @json.home_dir() {
        "" => "/tmp"
        home => home + "/.config"
      }
  }
  @json.join_all([base, "dsh-console", "env.json"])
}

///|
/// 读一份（文件不在 / 读不动 / 解析不了 → 空表；坏文件不让接口挂掉）。
pub async fn load_env_file() -> EnvFile noraise {
  let empty : EnvFile = { global: Map([]), profiles: Map([]) }
  let path = env_file_path()
  let text = match @json.read_text_file(path) {
    Ok(t) => t
    Err(_) => return empty
  }
  let json = match @json.json_parse(text) {
    Some(j) => j
    None => return empty
  }
  let global = parse_env_map(field_of(json, "global"))
  let profiles : Map[String, Map[String, String]] = Map([])
  match field_of(json, "profiles") {
    Some(profiles_json) =>
      for pair in object_entries(profiles_json) {
        let entries = parse_env_map(Some(pair.1))
        if entries.size() > 0 {
          profiles[pair.0] = entries
        }
      }
    None => ()
  }
  { global, profiles }
}

///|
/// 一个 JSON 对象 → 键值表（只收字符串值；别的类型跳过，不猜）。
fn parse_env_map(json : Json?) -> Map[String, String] {
  let out : Map[String, String] = Map([])
  match json {
    Some(v) =>
      for pair in object_entries(v) {
        match @json.json_string(pair.1) {
          Some(s) => out[pair.0] = s
          None => ()
        }
      }
    None => ()
  }
  out
}

///|
/// 一份键值表 → JSON 对象。
pub fn env_map_json(entries : Map[String, String]) -> @json.JsonVal {
  let fields : Array[(String, @json.JsonVal)] = []
  for pair in entries.iter() {
    fields.push((pair.0, @json.JStr(pair.1)))
  }
  @json.JObj(fields)
}

///|
/// 原子写：临时文件 + rename，权限 600（§61.1）。失败如实返回原因。
pub async fn save_env_file(file : EnvFile) -> Result[Unit, String] noraise {
  let path = env_file_path()
  let profiles_fields : Array[(String, @json.JsonVal)] = []
  for pair in file.profiles.iter() {
    if pair.1.size() > 0 {
      profiles_fields.push((pair.0, env_map_json(pair.1)))
    }
  }
  let json = @json.JObj([
    ("global", env_map_json(file.global)),
    ("profiles", @json.JObj(profiles_fields)),
  ])
  match @fsx.ensure_dir(@json.dirname(path)) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  match @fsx.write_text_atomic(path, @json.encode(json) + "\n") {
    Ok(_) => ()
    Err(e) => return Err("写不进 " + path + "：" + e)
  }
  // 权限：先按 600 建，失败也要报（这个文件里是可能含密钥的环境值）
  match @fsx.chmod_path(path, 0o600) {
    Ok(_) => Ok(())
    Err(e) => Err("写好了但改不成 600：" + e)
  }
}

///|
/// 起实例时真正要用的一份：继承的进程环境 → global → 该 profile。
/// 保留键（reserved_env_keys）一律跳过；返回的是「要额外覆盖的那几项」，
/// 子进程本身仍然继承当前进程环境（inherit_env=true）。
pub async fn env_for_spawn(home : String, profile : String) -> Map[String, String] noraise {
  let file = load_env_file()
  let out : Map[String, String] = Map([])
  let take = fn(entries : Map[String, String]) {
    for pair in entries.iter() {
      if env_key_allowed(pair.0) {
        out[pair.0] = pair.1
      }
    }
  }
  take(file.global)
  let key = profile_env_key(home, profile)
  match file.profiles.get(key) {
    Some(entries) => take(entries)
    None => ()
  }
  out
}

///|
/// 合并后的键值表（按「global 在前、profile 覆盖」的顺序给界面与开发指令用）。
pub async fn merged_env(home : String, profile : String) -> Map[String, String] noraise {
  env_for_spawn(home, profile)
}