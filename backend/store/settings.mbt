// 设置：键、缺省、取值范围、读（含坏文件回退）与写（原子）。
//
// 键与缺省值照抄 design/write-api-contract.md 的第三节。凡是出现在这里的键，
// 都在后端有真实的接线点（各条见 README「设置接到哪里」一表）；接不上的键不许出现。

///|
/// 设置值。字段名是 MoonBit 的，JSON 里的键名见下面 key_* 常量。
pub struct Settings {
  probe_timeout_ms : Int32
  probe_concurrency : Int32
  probe_max_candidates : Int32
  instance_base_port : Int32
  process_detach : Bool
  process_stop_grace_ms : Int32
  logs_default_tail : Int32
  ui_archive_open_by_default : Bool
  /// 侧栏收起：宽屏下侧栏是展开成 190px，还是收成 56px 的图标栏（窄屏不看这一项，
  /// 那一档的侧栏从顶部汉堡滑出，不占位）。前端读它复原形态，后端只负责存取与回显。
  ui_sidebar_collapsed : Bool
  /// 调试开关：显示 beta 功能（N7）
  ui_show_beta : Bool
  safety_delete_to_trash : Bool
  /// 忽略缺包警告（design/design-fixes.md §40）：开（缺省）时缺包不参与状态灯判定、
  /// 也不产生「有警告」；关掉回到旧行为（缺包 → 黄）。缺包仍然可以在抽屉里修。
  profile_ignore_missing_bundles : Bool
}

///|
pub let key_probe_timeout_ms : String = "probe.timeoutMs"

///|
pub let key_probe_concurrency : String = "probe.concurrency"

///|
pub let key_probe_max_candidates : String = "probe.maxCandidates"

///|
pub let key_instance_base_port : String = "instance.basePort"

///|
pub let key_process_detach : String = "process.detach"

///|
pub let key_process_stop_grace_ms : String = "process.stopGraceMs"

///|
pub let key_logs_default_tail : String = "logs.defaultTail"

///|
pub let key_ui_archive_open_by_default : String = "ui.archiveOpenByDefault"

///|
pub let key_ui_sidebar_collapsed : String = "ui.sidebarCollapsed"

///|
pub let key_safety_delete_to_trash : String = "safety.deleteToTrash"

///|
/// 缺包默认不报警（§40.1）：布尔，缺省 true。
pub let key_profile_ignore_missing_bundles : String = "profile.ignoreMissingBundles"

///|
/// 调试开关：显示 beta 功能（N7）。布尔，缺省 false。
pub let key_ui_show_beta : String = "ui.showBetaFeatures"

///|
/// 契约里的键序（响应的 values / defaults / sources 都按这个顺序出）。
pub fn settings_keys() -> Array[String] {
  [
    key_probe_timeout_ms, key_probe_concurrency, key_probe_max_candidates, key_instance_base_port,
    key_process_detach, key_process_stop_grace_ms, key_logs_default_tail, key_ui_archive_open_by_default,
    key_ui_sidebar_collapsed, key_ui_show_beta, key_safety_delete_to_trash, key_profile_ignore_missing_bundles,
  ]
}

///|
/// 缺省值（唯一的定义处；探测 / 启动 / 停止 / 日志 / 删除都从这里取缺省）。
pub fn default_settings() -> Settings {
  {
    probe_timeout_ms: 500,
    probe_concurrency: 8,
    probe_max_candidates: 40,
    instance_base_port: 8400,
    process_detach: true,
    process_stop_grace_ms: 5000,
    logs_default_tail: 200,
    ui_archive_open_by_default: false,
    ui_sidebar_collapsed: false,
    ui_show_beta: false,
    safety_delete_to_trash: true,
    profile_ignore_missing_bundles: true,
  }
}

///|
/// 一次读取的结果：生效值 + 每个键的来源 + 文件级问题的原因（没有给 None）。
pub struct LoadedSettings {
  values : Settings
  sources : Map[String, String]
  note : String?
}

///|
/// 取值范围（含端点）。越界即 bad-params —— 不静默夹取，前端要看得到自己填错了。
fn range_of(key : String) -> (Int32, Int32) {
  match key {
    "probe.timeoutMs" => (50, 60000)
    "probe.concurrency" => (1, 64)
    "probe.maxCandidates" => (1, 1000)
    "instance.basePort" => (1, 65535)
    "process.stopGraceMs" => (0, 600000)
    "logs.defaultTail" => (1, 1000)
    _ => (0, 0)
  }
}

///|
/// 一个键的取值校验 + 落到 Settings 上。失败给人话原因。
fn apply_one(
  current : Settings,
  key : String,
  json : Json,
) -> Result[Settings, String] {
  match key {
    "probe.timeoutMs"
    | "probe.concurrency"
    | "probe.maxCandidates"
    | "instance.basePort"
    | "process.stopGraceMs"
    | "logs.defaultTail" => {
      let value = match as_int(json) {
        Some(v) => v
        None => return Err("要整数，收到 " + describe(json))
      }
      let (lo, hi) = range_of(key)
      if value < lo || value > hi {
        return Err(
          "超出取值范围 " +
          lo.to_string() +
          ".." +
          hi.to_string() +
          "，收到 " +
          value.to_string(),
        )
      }
      match key {
        "probe.timeoutMs" => Ok({ ..current, probe_timeout_ms: value, })
        "probe.concurrency" => Ok({ ..current, probe_concurrency: value, })
        "probe.maxCandidates" => Ok({ ..current, probe_max_candidates: value, })
        "instance.basePort" => Ok({ ..current, instance_base_port: value, })
        "process.stopGraceMs" =>
          Ok({ ..current, process_stop_grace_ms: value, })
        _ => Ok({ ..current, logs_default_tail: value, })
      }
    }
    "process.detach"
    | "ui.archiveOpenByDefault"
    | "ui.sidebarCollapsed"
    | "ui.showBetaFeatures"
    | "safety.deleteToTrash"
    | "profile.ignoreMissingBundles" => {
      let value = match as_bool(json) {
        Some(v) => v
        None => return Err("要布尔值，收到 " + describe(json))
      }
      match key {
        "process.detach" => Ok({ ..current, process_detach: value, })
        "ui.archiveOpenByDefault" =>
          Ok({ ..current, ui_archive_open_by_default: value, })
        "ui.sidebarCollapsed" => Ok({ ..current, ui_sidebar_collapsed: value, })
        "ui.showBetaFeatures" => Ok({ ..current, ui_show_beta: value, })
        "profile.ignoreMissingBundles" =>
          Ok({ ..current, profile_ignore_missing_bundles: value, })
        _ => Ok({ ..current, safety_delete_to_trash: value, })
      }
    }
    _ => Err("未知的设置键：" + key)
  }
}

///|
/// 给一个 Json 值一句人话描述，用于报错（不带原始值以外的信息）。
pub fn describe(json : Json) -> String {
  match json {
    Null => "null"
    True => "true"
    False => "false"
    Number(d, ..) =>
      if d == d.to_int().to_double() {
        "整数 " + d.to_int().to_string()
      } else {
        "小数 " + d.to_string()
      }
    String(s) => "字符串 \"" + s + "\""
    Array(_) => "数组"
    Object(_) => "对象"
  }
}

///|
/// 读设置。文件坏了 / 值非法都不让接口挂掉：那一项按缺省，原因写进 sources。
pub async fn load_settings() -> LoadedSettings noraise {
  let paths = state_paths()
  let (file, file_error) = read_state_json(paths.settings)
  let sources : Map[String, String] = Map([])
  for key in settings_keys() {
    sources[key] = "默认"
  }
  let mut values = default_settings()
  let mut note = file_error
  match file {
    None => ()
    Some(json) =>
      match json {
        Object(_) =>
          for key in settings_keys() {
            match field_of(json, key) {
              None => ()
              Some(v) =>
                match apply_one(values, key, v) {
                  Ok(next) => {
                    values = next
                    sources[key] = "文件"
                  }
                  Err(reason) =>
                    sources[key] = "默认（" +
                      paths.settings +
                      " 里的值不可用：" +
                      reason +
                      "）"
                }
            }
          }
        _ =>
          note = Some(
            "settings.json 顶层不是对象，全部按缺省：" +
            paths.settings,
          )
      }
  }
  { values, sources, note, }
}

///|
/// 把 values 对象里的每个键校验后合并到 current 上。
/// 返回 (新值, 错误)：错误是 (code, message)，code 一律 bad-params。
pub fn apply_patch(
  current : Settings,
  values : Json,
) -> Result[Settings, (String, String)] {
  let entries = object_entries(values)
  match values {
    Object(_) => ()
    _ => return Err(("bad-params", "values 必须是对象"))
  }
  if entries.length() == 0 {
    return Err(("bad-params", "values 里没有任何键"))
  }
  let mut next = current
  for entry in entries {
    let key = entry.0
    if !settings_keys().any(fn(k) { k == key }) {
      return Err(("bad-params", "未知的设置键：" + key))
    }
    match apply_one(next, key, entry.1) {
      Ok(updated) => next = updated
      Err(reason) => return Err(("bad-params", key + "：" + reason))
    }
  }
  Ok(next)
}

///|
/// 值对象（JSON 编码用），键序与契约一致。
pub fn settings_values_json(s : Settings) -> @json.JsonVal {
  @json.JObj([
    (key_probe_timeout_ms, @json.jint(s.probe_timeout_ms)),
    (key_probe_concurrency, @json.jint(s.probe_concurrency)),
    (key_probe_max_candidates, @json.jint(s.probe_max_candidates)),
    (key_instance_base_port, @json.jint(s.instance_base_port)),
    (key_process_detach, @json.JBool(s.process_detach)),
    (key_process_stop_grace_ms, @json.jint(s.process_stop_grace_ms)),
    (key_logs_default_tail, @json.jint(s.logs_default_tail)),
    (key_ui_archive_open_by_default, @json.JBool(s.ui_archive_open_by_default)),
    (key_ui_sidebar_collapsed, @json.JBool(s.ui_sidebar_collapsed)),
    (key_ui_show_beta, @json.JBool(s.ui_show_beta)),
    (key_safety_delete_to_trash, @json.JBool(s.safety_delete_to_trash)),
    (
      key_profile_ignore_missing_bundles,
      @json.JBool(s.profile_ignore_missing_bundles),
    ),
  ])
}

///|
/// 按契约键序取一个键的生效值（响应里要逐个键列出时用）。
pub fn value_of(s : Settings, key : String) -> @json.JsonVal {
  match key {
    "probe.timeoutMs" => @json.jint(s.probe_timeout_ms)
    "probe.concurrency" => @json.jint(s.probe_concurrency)
    "probe.maxCandidates" => @json.jint(s.probe_max_candidates)
    "instance.basePort" => @json.jint(s.instance_base_port)
    "process.detach" => @json.JBool(s.process_detach)
    "process.stopGraceMs" => @json.jint(s.process_stop_grace_ms)
    "logs.defaultTail" => @json.jint(s.logs_default_tail)
    "ui.archiveOpenByDefault" => @json.JBool(s.ui_archive_open_by_default)
    "ui.sidebarCollapsed" => @json.JBool(s.ui_sidebar_collapsed)
    "ui.showBetaFeatures" => @json.JBool(s.ui_show_beta)
    "safety.deleteToTrash" => @json.JBool(s.safety_delete_to_trash)
    "profile.ignoreMissingBundles" =>
      @json.JBool(s.profile_ignore_missing_bundles)
    _ => @json.JNull
  }
}

///|
/// 按契约键序取一个键的缺省值。
pub fn default_of(s : Settings, key : String) -> @json.JsonVal {
  value_of(s, key)
}

///|
/// 落盘（原子写）。
pub async fn save_settings(s : Settings) -> Result[Unit, String] noraise {
  let paths = state_paths()
  match
    @fsx.write_text_atomic_fs(
      paths.settings,
      @json.encode(settings_values_json(s)) + "\n",
    ) {
    Ok(_) => Ok(())
    Err(e) => {
      note_raw(e.raw)
      Err("写文件失败")
    }
  }
}
