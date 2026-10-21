// 设置页的键表与取值。
//
// 键、分组、缺省、控件逐条来自 design/write-api-contract.md：
//
//   probe.timeoutMs          500     实例签名探测超时（毫秒）
//   probe.concurrency        8       探测并发
//   probe.maxCandidates      40      候选端口上限
//   instance.basePort        8400    启动/派生时找空闲端口的起点
//   process.detach           true    起实例时是否脱离控制台存活
//   process.stopGraceMs      5000    SIGTERM 到 SIGKILL 的宽限
//   logs.defaultTail         200     日志页默认尾部行数
//   ui.archiveOpenByDefault  false   归档区默认是否展开
//   ui.sidebarCollapsed      false   宽屏侧栏是否收成图标栏（窄屏不看这一项）
//   safety.deleteToTrash     true    删除进回收站还是硬删
//   profile.ignoreMissingBundles true 缺包是否参与状态灯（§40，缺省不报警）
//
// 这个文件只做三件事：列键（顺序、分组、控件、说明）、从 GET 的响应里取值、
// 拼 PUT 的请求体。**界面不编数值**：接口没给的键就写「接口未返回该键」，
// 契约缺省只作为控件的悬停提示，不当成当前值用。

///|
/// 一个设置项的取值。接口里只有数字、布尔、字符串三种。
enum SettingValue {
  VInt(Int)
  VBool(Bool)
  VText(String)
} derive(Eq)

pub extend SettingValue with Eq::{ not_equal, equal }

///|
/// 控件种类。数字给范围，开关给布尔，枚举给候选值。
enum ControlKind {
  CNum(Int, Int, String)
  CBool
  CList(Array[Int])
} derive(Eq)

pub extend ControlKind with Eq::{ not_equal, equal }

///|
struct SettingDef {
  key : String
  group : String
  label : String
  desc : String
  kind : ControlKind
  fallback : SettingValue
} derive(Eq)

pub extend SettingDef with Eq::{ not_equal, equal }

///|
struct SettingGroup {
  id : String
  label : String
  icon : String
  note : String
} derive(Eq)

pub extend SettingGroup with Eq::{ not_equal, equal }

///|
/// 左侧索引的分组（顺序即索引顺序）。
///
/// 最后一组「启动环境」不是设置项（一个键一个值的那套契约），而是任意键值表：
/// 分组照样是一个分组，条目那一块由 view_env.mbt 画（§61.5 说明了为什么分开）。
let settings_groups : Array[SettingGroup] = [
  {
    id: "instance",
    label: "实例与端口",
    icon: "server",
    note: "起实例时的端口起点，以及每次扫描要为签名探测付多少代价。",
  },
  {
    id: "process",
    label: "进程",
    icon: "refresh",
    note: "实例进程怎么活、怎么停。",
  },
  {
    id: "logs",
    label: "日志",
    icon: "text-box-outline",
    note: "日志页一次读多少行。",
  },
  {
    id: "ui",
    label: "界面",
    icon: "tune",
    note: "页面自己的默认状态。",
  },
  {
    id: "safety",
    label: "危险动作",
    icon: "shield-outline",
    note: "删除是不可逆的那一档：这里决定它进回收站还是直接落刀。",
  },
  {
    id: "env",
    label: "启动环境",
    icon: "key-variant",
    note: "起实例时挂进子进程的变量：全局一份，某只 profile 可以覆盖其中的键",
  },
]

///|
/// 十一个键（顺序即条目顺序）。
let settings_table : Array[SettingDef] = [
  {
    key: "instance.basePort",
    group: "instance",
    label: "启动端口起点",
    desc: "启动 / 派生实例时，从这个端口开始找第一个空闲的。",
    kind: CNum(1, 65535, ""),
    fallback: VInt(8400),
  },
  {
    key: "probe.timeoutMs",
    group: "instance",
    label: "签名探测超时",
    desc: "探测一个候选端口时等应答的上限（毫秒）。调大能容下慢实例，代价是扫描变慢。",
    kind: CNum(1, 60000, " 毫秒"),
    fallback: VInt(500),
  },
  {
    key: "probe.concurrency",
    group: "instance",
    label: "探测并发",
    desc: "同时探测多少个候选端口。调大扫得快，瞬时占用的文件描述符也更多。",
    kind: CNum(1, 64, " 路"),
    fallback: VInt(8),
  },
  {
    key: "probe.maxCandidates",
    group: "instance",
    label: "候选端口上限",
    desc: "一次扫描最多探测多少个本机 loopback 监听端口。",
    kind: CNum(1, 512, " 个"),
    fallback: VInt(40),
  },
  {
    key: "process.detach",
    group: "process",
    label: "脱离控制台存活",
    desc: "开：控制台退出后实例继续跑；关：实例跟着控制台的进程组一起结束。",
    kind: CBool,
    fallback: VBool(true),
  },
  {
    key: "process.stopGraceMs",
    group: "process",
    label: "停止宽限期",
    desc: "停止实例时，SIGTERM 之后等多久再 SIGKILL（毫秒）。0 表示不留宽限。",
    kind: CNum(0, 120000, " 毫秒"),
    fallback: VInt(5000),
  },
  {
    key: "logs.defaultTail",
    group: "logs",
    label: "默认尾部行数",
    desc: "打开日志页时默认读多少行尾部。日志页自己写着实际读到了多少行。",
    kind: CList([200, 500, 1000, 2000]),
    fallback: VInt(200),
  },
  {
    key: "ui.archiveOpenByDefault",
    group: "ui",
    label: "归档区默认展开",
    desc: "打开实例总览时，「已归档」分组是否直接展开。",
    kind: CBool,
    fallback: VBool(false),
  },
  {
    key: "ui.sidebarCollapsed",
    group: "ui",
    label: "侧栏收起",
    desc: "宽屏下把侧栏收成一列图标，主区更宽；悬停图标可以看到名字。窄屏不看这一项：那一档的侧栏从顶部汉堡滑出，不占位。",
    kind: CBool,
    fallback: VBool(false),
  },
  {
    key: "safety.deleteToTrash",
    group: "safety",
    label: "删除进回收站",
    desc: "开：删除时移入回收站，可以捞回来；关：直接删除，无法恢复。",
    kind: CBool,
    fallback: VBool(true),
  },
  {
    key: "profile.ignoreMissingBundles",
    group: "ui",
    label: "忽略缺包警告",
    desc: "声明了但没装的包不影响运行时不再报警",
    kind: CBool,
    fallback: VBool(true),
  },
]

///|
/// 这一项是不是开关（§51）：保存成功之后要把焦点送回那颗开关，别的控件不走这条路。
fn setting_is_switch(key : String) -> Bool {
  for def in settings_table {
    if def.key == key {
      return match def.kind {
        CBool => true
        _ => false
      }
    }
  }
  false
}

///|
/// 一个分组里有几条（索引行右侧那个数）。
///
/// 设置项那一档数的是键表；「启动环境」那一档数的是**全局那一段有几条**——
/// 它没有固定键表，条数是读数里的事实（还没读到时是 0，不编）。
fn settings_group_count(model : Model, group_id : String) -> Int {
  if group_id == "env" {
    return model.env_global.length()
  }
  settings_table.filter(fn(def) { def.group == group_id }).length()
}

///|
/// 一个键的取值。
struct SettingVal {
  key : String
  value : SettingValue
} derive(Eq)

pub extend SettingVal with Eq::{ not_equal, equal }

///|
/// GET /api/local/settings 的三个表：当前值、缺省值、来源（文件 / 默认）。
struct SettingsFacts {
  values : Array[SettingVal]
  defaults : Array[SettingVal]
  sources : Array[SettingVal]
} derive(Eq)

pub extend SettingsFacts with Eq::{ not_equal, equal }

///|
fn setting_value_text(value : SettingValue) -> String {
  match value {
    VInt(n) => n.to_string()
    VBool(b) =>
      if b {
        "开"
      } else {
        "关"
      }
    VText(t) => t
  }
}

///|
/// 契约缺省值的显示口径（只用在悬停提示里）。
fn setting_fallback_text(def : SettingDef) -> String {
  let range = match def.kind {
    CNum(min, max, unit) => "，取值 " + min.to_string() + "–" + max.to_string() + unit
    CBool => ""
    CList(options) =>
      "，候选 " +
      join_with(options.map(fn(n) { n.to_string() }), " / ")
  }
  "出厂缺省 " + setting_value_text(def.fallback) + range
}

///|
fn lookup_setting(list : Array[SettingVal], key : String) -> SettingValue? {
  for item in list {
    if item.key == key {
      return Some(item.value)
    }
  }
  None
}

///|
/// 当前值：读数里没给这个键就是 None（界面写「读数里没有这一项」，不拿缺省顶上）。
fn setting_current(facts : SettingsFacts, def : SettingDef) -> SettingValue? {
  lookup_setting(facts.values, def.key)
}

///|
/// 来源：后端给的是「文件」或「默认」，原样显示。
fn setting_source(facts : SettingsFacts, def : SettingDef) -> String {
  match lookup_setting(facts.sources, def.key) {
    Some(VText(text)) => text
    _ => "读数里没有这一项"
  }
}

///|
/// 一个键的取值：数字 / 布尔 / 字符串；别的形状一律当成「接口没给」。
fn read_setting_value(json : Json) -> SettingValue? {
  match json {
    Json::Number(n, ..) => Some(VInt(n.to_int()))
    Json::True => Some(VBool(true))
    Json::False => Some(VBool(false))
    Json::String(text) => Some(VText(text))
    _ => None
  }
}

///|
fn read_setting_table(raw : Map[String, Json]) -> Array[SettingVal] {
  let out : Array[SettingVal] = []
  for def in settings_table {
    match raw.get(def.key) {
      Some(json) =>
        match read_setting_value(json) {
          Some(value) => out.push({ key: def.key, value })
          None => ()
        }
      None => ()
    }
  }
  out
}

///|
fn parse_settings(text : String) -> Result[SettingsFacts, String] {
  let data = match open_envelope(text) {
    Ok(data) => data
    Err(reason) => return Err(reason)
  }
  Ok({
    values: read_setting_table(obj_field(data, "values")),
    defaults: read_setting_table(obj_field(data, "defaults")),
    sources: read_setting_table(obj_field(data, "sources")),
  })
}

///|
fn setting_value_json(value : SettingValue) -> String {
  match value {
    VInt(n) => n.to_string()
    VBool(b) =>
      if b {
        "true"
      } else {
        "false"
      }
    VText(text) => json_text_literal(text)
  }
}

///|
/// PUT /api/local/settings 的请求体：一次一个键。
fn settings_put_body(key : String, value : SettingValue) -> String {
  "{\"values\":{" + json_text_literal(key) + ":" + setting_value_json(value) + "}}"
}

///|
/// 整数文本解析：非数字、空、超长一律判不合法（不猜、不截断）。
fn parse_int_text(text : String) -> Int? {
  let t = text.trim().to_owned()
  if t.length() == 0 {
    return None
  }
  if t.length() > 9 {
    return None
  }
  let mut value = 0
  for c in t {
    if c < '0' || c > '9' {
      return None
    }
    value = value * 10 + (c.to_int() - 48)
  }
  Some(value)
}

///|
/// 控件里的文本 → 取值。范围由本地的键表把关，越界不发请求，先说清哪里不对。
fn setting_parse_input(def : SettingDef, text : String) -> Result[SettingValue, String] {
  match def.kind {
    CNum(min, max, unit) =>
      match parse_int_text(text) {
        None => Err("要填一个整数")
        Some(n) =>
          if n < min || n > max {
            Err(
              "取值要在 " + min.to_string() + "–" + max.to_string() + unit + " 之间，收到 " +
              n.to_string(),
            )
          } else {
            Ok(VInt(n))
          }
      }
    CList(options) =>
      match parse_int_text(text) {
        None => Err("要选一个候选值")
        Some(n) =>
          if options.contains(n) {
            Ok(VInt(n))
          } else {
            Err("候选值里没有 " + n.to_string())
          }
      }
    CBool => Err("开关不用文本输入")
  }
}

///|
fn setting_by_key(key : String) -> SettingDef? {
  for def in settings_table {
    if def.key == key {
      return Some(def)
    }
  }
  None
}

///|
/// 模型里读一个布尔设置：设置没读到、键没返回、类型不对都是 None
/// （调用方据此决定「按可能要硬删处理」这类保守动作）。
fn setting_bool_of(model : Model, key : String) -> Bool? {
  match model.settings {
    None => None
    Some(facts) =>
      match lookup_setting(facts.values, key) {
        Some(VBool(value)) => Some(value)
        _ => None
      }
  }
}

///|
/// 生效的删除方式：这一次删除会不会把 profile 移进回收站。
///
/// 两个来源，按新鲜度排：
///   1. 设置页读到的那一份（用户可能刚在这里改过）；
///   2. 控制台状态里的生效值（GET /api/local/console，页面加载时就读了）。
/// 两个都没有才是真读不到 —— 那种情况界面只写「暂时读不到删除方式」，
/// 不解释「为什么读不到」（懒加载、缓存状态这些是说给实现者听的）。
fn delete_to_trash_of(model : Model) -> Bool? {
  match setting_bool_of(model, "safety.deleteToTrash") {
    Some(value) => Some(value)
    None =>
      match model.console {
        Some(facts) => facts.delete_to_trash
        None => None
      }
  }
}

///|
/// 这个分组 id 在不在表里。路由用它判定「地址里那一组还存不存在」——
/// 存不存在是路由要不要回落的事，与「认不出退回第一组」是两件事。
fn settings_group_exists(id : String) -> Bool {
  for group in settings_groups {
    if group.id == id {
      return true
    }
  }
  false
}

///|
/// 分组查找：认不出的 id 退回第一个分组，右侧不留空白。
fn setting_group_of(id : String) -> SettingGroup {
  for group in settings_groups {
    if group.id == id {
      return group
    }
  }
  settings_groups[0]
}
///|
/// 启动环境（design/design-fixes.md §61）：global 一份 + 每只 profile 一份。
/// 值可能含密钥：界面默认打码，审计只记键名。
pub struct EnvFacts {
  path : String
  global : Array[(String, String)]
  profiles : Array[(String, Array[(String, String)])]
  reserved : Array[String]
} derive(Eq)

pub extend EnvFacts with Eq::{ not_equal, equal }

///|
/// 一份 JSON 对象 → 有序键值对（保持文件里的顺序，界面不重排）。
fn env_pairs_of(obj : Map[String, Json]) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  for pair in obj.iter() {
    match pair.1 {
      Json::String(v) => out.push((pair.0, v))
      _ => ()
    }
  }
  out
}

///|
/// 从 settings 响应里取 env 段（没有这一段 = 旧后端，给空表）。
fn parse_env_facts(data : Map[String, Json]) -> EnvFacts {
  let empty : EnvFacts = { path: "", global: [], profiles: [], reserved: [] }
  if !data.contains("env") {
    return empty
  }
  let env = obj_field(data, "env")
  let profiles : Array[(String, Array[(String, String)])] = []
  for pair in obj_field(env, "profiles").iter() {
    match pair.1 {
      Json::Object(inner) => profiles.push((pair.0, env_pairs_of(inner)))
      _ => ()
    }
  }
  {
    path: str_field(env, "path"),
    global: env_pairs_of(obj_field(env, "global")),
    profiles,
    reserved: str_array_field(env, "reserved"),
  }
}

///|
/// 这份 profile 单独设的那张表（没有 = 空）。
fn env_profile_pairs(facts : EnvFacts, home : String, profile : String) -> Array[(String, String)] {
  let key = home + "|" + profile
  for pair in facts.profiles {
    if pair.0 == key {
      return pair.1
    }
  }
  []
}

///|
/// save-env 的请求体：entries 整份替换。
fn env_put_body(scope : String, home : String, profile : String, entries : Array[(String, String)]) -> String {
  let fields : Array[String] = []
  for pair in entries {
    fields.push(json_text_literal(pair.0) + ":" + json_text_literal(pair.1))
  }
  let params = if scope == "global" {
    "{\"scope\":\"global\",\"entries\":{" + join_with(fields, ",") + "}}"
  } else {
    "{\"scope\":\"profile\",\"home\":" + json_text_literal(home) +
    ",\"profile\":" + json_text_literal(profile) + ",\"entries\":{" +
    join_with(fields, ",") + "}}"
  }
  "{\"action\":\"save-env\",\"params\":" + params + "}"
}

///|
/// 合并后的启动环境（§61.3 第 6 条：复制开发指令里那一段）。
/// 顺序：global 在前、profile 覆盖同键（键留在第一次出现的位置），值为空的不写。
fn env_merged_pairs(global : Array[(String, String)], own : Array[(String, String)]) -> Array[(String, String)] {
  let order : Array[String] = []
  let values : Map[String, String] = Map([])
  let put = fn(list : Array[(String, String)]) {
    for pair in list {
      if pair.1 == "" {
        continue
      }
      if !values.contains(pair.0) {
        order.push(pair.0)
      }
      values[pair.0] = pair.1
    }
  }
  put(global)
  put(own)
  let out : Array[(String, String)] = []
  for key in order {
    match values.get(key) {
      Some(v) => out.push((key, v))
      None => ()
    }
  }
  out
}