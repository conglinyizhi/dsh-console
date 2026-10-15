// 控制台状态文件的位置与读法。
//
// 状态目录：$XDG_STATE_HOME/dsh-console（XDG_STATE_HOME 缺省 ~/.local/state）。
// 这里放四份文件，各自只由对应的模块读写：
//   settings.json  设置值（原子写）
//   runtime.json   控制台起过的实例登记（原子写，只记我们起的）
//   archive.json   归档记录（原子写）
//   audit.jsonl    动作审计（只追加，不轮转）
//   trash/         删除进回收站的落点（deleteToTrash=true 时的目标）
//
// GET 系列接口不碰这些文件的写路径：读就是读，坏文件回退到缺省并把原因写进 sources。

///|
/// 状态文件路径集合。
pub struct StatePaths {
  dir : String
  settings : String
  runtime : String
  archive : String
  audit : String
  trash : String
}

///|
/// 解析状态目录。XDG_STATE_HOME 只认绝对路径（相对路径按未设置处理，这是 XDG 的规定）。
pub async fn state_paths() -> StatePaths noraise {
  let base = match @json.env_value("XDG_STATE_HOME") {
    Some(v) if v.has_prefix("/") => v
    _ => @json.join_all([@json.home_dir(), ".local", "state"])
  }
  let dir = @json.join_path(base, "dsh-console")
  {
    dir,
    settings: @json.join_path(dir, "settings.json"),
    runtime: @json.join_path(dir, "runtime.json"),
    archive: @json.join_path(dir, "archive.json"),
    audit: @json.join_path(dir, "audit.jsonl"),
    trash: @json.join_path(dir, "trash"),
  }
}

///|
/// 读一份 JSON 状态文件，返回 (值, 原因)：
///   文件不存在 -> (None, None)：全新环境，不是错误，全部按缺省；
///   存在但读不动 / 解析失败 -> (None, Some(原因))：按缺省回退，但原因要能看见。
pub async fn read_state_json(path : String) -> (Json?, String?) noraise {
  if !@json.exists(path) {
    return (None, None)
  }
  let text = match @json.read_text_file(path) {
    Ok(t) => t
    Err(e) => return (None, Some("读不动 " + path + "：" + e))
  }
  match @json.json_parse(text) {
    Some(j) => (Some(j), None)
    None => (None, Some("解析不了 " + path + "：不是合法 JSON"))
  }
}

///|
/// 取对象的某个字段（不是对象给 None）。
pub fn field_of(json : Json, key : String) -> Json? {
  @json.json_field(json, key)
}

///|
/// 从 Json 取字符串；不是字符串给 None。
pub fn as_string(json : Json) -> String? {
  @json.json_string(json)
}

///|
/// 从 Json 取整数；非整数（含小数、字符串）给 None。
pub fn as_int(json : Json) -> Int? {
  match json {
    Number(d, ..) =>
      if d == d.to_int().to_double() {
        Some(d.to_int())
      } else {
        None
      }
    _ => None
  }
}

///|
/// 从 Json 取布尔。
pub fn as_bool(json : Json) -> Bool? {
  match json {
    True => Some(true)
    False => Some(false)
    _ => None
  }
}

///|
/// 对象字段迭代（不是对象给空数组），顺序为 Map 的迭代顺序。
pub fn object_entries(json : Json) -> Array[(String, Json)] {
  match json {
    Object(fields) => {
      let out : Array[(String, Json)] = []
      for k, v in fields {
        out.push((k, v))
      }
      out
    }
    _ => []
  }
}
