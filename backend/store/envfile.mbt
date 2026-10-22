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
  options : EnvOptions
  /// 用户明确删掉的键名（原样大小写）：下次保存不再自动补出它的大小写对偶
  suppressed : Array[String]
}

///|
/// 生效方式（§62.2）：keep_system 是否继承控制台进程环境；merge 同键冲突时 override 覆盖 / append 拼接。
pub(all) struct EnvOptions {
  keep_system : Bool
  merge : String
}

///|
/// 缺省：继承 + 覆盖。
pub fn default_env_options() -> EnvOptions {
  { keep_system: true, merge: "override", }
}

///|
/// merge 只认两个值。
pub fn env_merge_allowed(merge : String) -> Bool {
  merge == "override" || merge == "append"
}

///|
/// 拼接用的分隔符：Unix 是冒号，Windows 是分号（§62.2）。
pub async fn env_path_separator() -> String noraise {
  match @json.env_value("OS") {
    Some(v) if v.to_lower().contains("windows") => ";"
    _ => ":"
  }
}

///|
/// 控制台自己必须管住的键：这些不许被启动环境覆盖（§61.2）。界面据此置灰。
pub fn reserved_env_keys() -> Array[String] {
  ["DSH_HOME", "PATH", "HOME", "PWD", "TMPDIR", "DSH_PROFILE"]
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
    let ok = (code >= 48 && code <= 57) ||
      (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      ch == '_'
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
  let empty : EnvFile = {
    global: Map([]),
    profiles: Map([]),
    options: default_env_options(),
    suppressed: [],
  }
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
        if entries.length() > 0 {
          profiles[pair.0] = entries
        }
      }
    None => ()
  }
  // options（§62.2）：缺一项就用缺省值；merge 只认 override / append，别的值退回 override
  let options = match field_of(json, "options") {
    Some(opts) => {
      let keep_system = match field_of(opts, "inherit") {
        Some(json) =>
          match as_bool(json) {
            Some(b) => b
            None => true
          }
        _ => true
      }
      let merge = match field_of(opts, "merge") {
        Some(json) =>
          match as_string(json) {
            Some(m) if env_merge_allowed(m) => m
            _ => "override"
          }
        _ => "override"
      }
      { keep_system, merge, }
    }
    None => default_env_options()
  }
  // suppressed：用户明确删掉的键名（原样大小写）
  let suppressed : Array[String] = []
  for item in @json.json_array(field_of(json, "suppressed")) {
    match @json.json_string(item) {
      Some(s) => suppressed.push(s)
      None => ()
    }
  }
  { global, profiles, options, suppressed, }
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

///|
/// 大小写成对补齐（§94）：全小写的键顺手写一份全大写，全大写的写一份全小写；
/// 显式写了混合大小写（FooBar）的键原样留着，不拆成两份 —— 那是使用者刻意的写法。
fn expand_case_variants(
  entries : Map[String, String],
  suppressed : Array[String],
) -> Map[String, String] {
  let out : Map[String, String] = Map([])
  for pair in entries.iter() {
    out[pair.0] = pair.1
  }
  for pair in entries.iter() {
    let key = pair.0
    let upper = key.to_upper()
    let lower = key.to_lower()
    let has_upper = upper != key
    let has_lower = lower != key
    if has_upper && !has_lower {
      // 全小写：补一份全大写
      if !entries.contains(upper) && !suppressed.contains(upper) {
        out[upper] = pair.1
      }
    } else if has_lower && !has_upper {
      // 全大写：补一份全小写
      if !entries.contains(lower) && !suppressed.contains(lower) {
        out[lower] = pair.1
      }
    }
  }
  out
}

///|
pub async fn save_env_file(file : EnvFile) -> Result[Unit, String] noraise {
  let path = env_file_path()
  let file = {
    ..file,
    global: expand_case_variants(file.global, file.suppressed),
  }
  let profiles_fields : Array[(String, @json.JsonVal)] = []
  for pair in file.profiles.iter() {
    if pair.1.length() > 0 {
      profiles_fields.push(
        (pair.0, env_map_json(expand_case_variants(pair.1, file.suppressed))),
      )
    }
  }
  let json = @json.JObj([
    ("global", env_map_json(file.global)),
    ("profiles", @json.JObj(profiles_fields)),
    (
      "options",
      @json.JObj([
        ("inherit", @json.JBool(file.options.keep_system)),
        ("merge", @json.JStr(file.options.merge)),
      ]),
    ),
    ("suppressed", @json.jstr_array(file.suppressed)),
  ])
  match @fsx.ensure_dir_fs(@json.dirname(path)) {
    Ok(_) => ()
    Err(e) => return Err("建目录失败：" + e.summary)
  }
  match @fsx.write_text_atomic_fs(path, @json.encode(json) + "\n") {
    Ok(_) => ()
    Err(e) => return Err("写文件失败：" + e.summary)
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
pub async fn env_for_spawn(
  home : String,
  profile : String,
) -> Map[String, String] noraise {
  let (_, extra) = env_plan(home, profile)
  extra
}

///|
/// 起实例时的完整方案（§62.4）：(是否继承控制台环境, 要额外设置的变量)。
/// · keep_system=true：extra 只放 global 与该 profile 的键；merge=override 原样覆盖，
///   merge=append 时同键拼成「继承值 + 分隔符 + global 值」（profile 仍覆盖 global）。
/// · keep_system=false：extra 要自带保留键（从控制台进程环境抄一份），子进程不继承。
pub async fn env_plan(
  home : String,
  profile : String,
) -> (Bool, Map[String, String]) noraise {
  let file = load_env_file()
  let opts = file.options
  let sep = env_path_separator()
  let out : Map[String, String] = Map([])
  // 先把要用的继承值抄一份（env_value 是 async，闭包里不能再 await）。
  // 除了保留键，还要把 global 与该 profile 里出现的所有键预读进来：
  // append 的拼接要用「继承来的同键值」，只读保留键会让 FOO 这类键永远拼不上（§62 bug）。
  let inherited : Map[String, String] = Map([])
  let preload = fn(entries : Map[String, String]) {
    for pair in entries.iter() {
      if !inherited.contains(pair.0) {
        inherited[pair.0] = ""
      }
    }
  }
  for key in reserved_env_keys() {
    inherited[key] = ""
  }
  preload(file.global)
  match file.profiles.get(profile_env_key(home, profile)) {
    Some(entries) => preload(entries)
    None => ()
  }
  // 先收键名再逐个赋值：边遍历边改同一个 Map 容易踩到迭代器的假设
  let keys : Array[String] = []
  for pair in inherited.iter() {
    keys.push(pair.0)
  }
  for key in keys {
    match @json.env_value(key) {
      Some(v) => inherited[key] = v
      None => ()
    }
  }
  if !opts.keep_system {
    // 不继承：保留键由我们显式给（拿不到就不写，子进程自然没有）
    for key in reserved_env_keys() {
      match inherited.get(key) {
        Some(v) => out[key] = v
        None => ()
      }
    }
  }
  let take = fn(entries : Map[String, String], append : Bool) {
    for pair in entries.iter() {
      if !env_key_allowed(pair.0) {
        continue
      }
      let base = if opts.keep_system {
        match inherited.get(pair.0) {
          Some(v) => v
          None => ""
        }
      } else {
        ""
      }
      // append 只对「继承来的同键」拼接；不继承时没有可拼的东西
      if append && opts.keep_system && base != "" {
        out[pair.0] = base + sep + pair.1
      } else {
        out[pair.0] = pair.1
      }
    }
  }
  take(file.global, opts.merge == "append")
  let key = profile_env_key(home, profile)
  match file.profiles.get(key) {
    // profile 永远覆盖 global：append 不再叠加
    Some(entries) => take(entries, false)
    None => ()
  }
  (opts.keep_system, out)
}

///|
/// 合并后的键值表（按「global 在前、profile 覆盖」的顺序给界面与开发指令用）。
pub async fn merged_env(
  home : String,
  profile : String,
) -> Map[String, String] noraise {
  env_for_spawn(home, profile)
}
