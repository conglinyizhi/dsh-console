// 控制台状态文件的位置与读法。
//
// 状态目录：$XDG_STATE_HOME/dsh-console（XDG_STATE_HOME 缺省 ~/.local/state）。
// 这里放四份文件，各自只由对应的模块读写：
//   settings.json  设置值（原子写）
//   runtime.json   控制台起过的实例登记（原子写，只记我们起的）
//   archive.json   归档记录（原子写）
//   order.json     手动排序的显式顺序表：一个行 id 的字符串数组（原子写）
//   dsh-pin.json   用哪一版 dsh 起实例的指定记录（原子写，见 dshpin.mbt）
//   jobs/          维护作业（一条作业一份 <id>.json，原子写，见 jobs.mbt）
//   audit.jsonl    动作审计（平时只追加，超 8 MiB 滚动；归档在同目录 .archive/）
//   trash/         删除进回收站的落点（deleteToTrash=true 时的目标）
//   trash-origins.json  trash/ 里每一条是**从哪个 home 删的**：{ "<目录名>": "<home>" }（原子写）
//
// trash-origins.json 单独一份而不是塞进 trash/ 里：条目目录本身就是那只 profile 的目录，
// 恢复时会连里面的东西一起搬回去 —— 往里写一个标记文件，就等于给恢复回去的 profile 添了一个
// 它自己没写过的文件 ✗。放在状态目录里按目录名查，条目本身一个字节都不动。
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
  order : String
  /// 「用哪一版 dsh 起实例」的指定记录（dsh-pin.json）
  dsh_pin : String
  /// 维护作业的落盘目录（一条作业一份 <jobId>.json）
  jobs : String
  trash : String
  trash_origins : String
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
    order: @json.join_path(dir, "order.json"),
    dsh_pin: @json.join_path(dir, "dsh-pin.json"),
    jobs: @json.join_path(dir, "jobs"),
    trash: @json.join_path(dir, "trash"),
    trash_origins: @json.join_path(dir, "trash-origins.json"),
  }
}

///|
/// 把一段文本当成一个 home 路径来认，认得出给**归一化之后**的值，认不出给 None。
///
/// 认的条件：绝对路径、去掉末尾多余的斜杠之后非空且不是根、按斜杠切出来的段里
/// 没有单个点与双点。全都是为了同一个目的：home 会进归档记录的判重键、进回收站
/// 恢复时的目标路径 —— 一个方向不对的字符串在这儿被拦下，比它跑到「恢复到哪里」那一步
/// 再发现便宜得多。归一化（去尾斜杠）是为了让 /a/b 与 /a/b/ 认成同一个 home。
pub fn normalize_home(raw : String) -> String? {
  let text = @json.trim_both(raw)
  if !text.has_prefix("/") {
    return None
  }
  let mut end = text.length()
  while end > 1 && @json.slice(text, end - 1, end) == "/" {
    end = end - 1
  }
  let trimmed = @json.slice(text, 0, end)
  if trimmed == "/" {
    return None
  }
  for segment in trimmed.split("/") {
    let part = @json.owned(segment)
    if part == "." || part == ".." {
      return None
    }
  }
  Some(trimmed)
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
