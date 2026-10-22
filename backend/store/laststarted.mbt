// 「上次启动」：这只实例 / 这只 profile 最后一次被启动是什么时候。
//
// 卡片第二行的第三顺位用它：**有备注写备注**，没有备注才写它；两个都没有就空着。
// 数据只从控制台自己的记录里取，一个字都不编：
//   ① runtime.json 的 startedAt —— 控制台自己起过的实例的登记（本文件读 registry）
//   ② audit.jsonl 里 action 为 start-instance 或 restart-instance、且 ok == true 的行 —— 审计流水
//      （design/design-fixes.md §28.1：一次成功的重启也是一次启动；口径与 store/startattempt 一致）
// 正在跑的那一只不在这里：它的真实启动时刻在 /api/local/instances 的 startedAt 里
// （由 /proc 的进程起始时间推出来），前端优先用它，这里只是兜底。
//
// 为什么不读 .archive/ 里的历史审计：滚动之后主文件保留最近 audit_retain_lines 条
// （缺省 2000），再往前的历史在 .archive/ 下。多读一份归档就多一份路径与上限的
// 处理，而「上次启动」要的是**最近**那一次 —— 最近的必然在主文件里（除非这台机器
// 2000 条动作之内都没起过实例，那时卡片就不写时间，不写也不说谎）。
//
// 同一个 id 有多条（runtime + audit 各一条、audit 里起过多次）：留 at 最大的那一条。
// at 都是本后端自己写的 UTC ISO（iso_from_epoch_ms），字典序即时间序。

///|
/// 一条「上次启动」。
pub struct LastStarted {
  /// 行 id，与 order.json / 前端 row.id 同一套：port:<端口号> / profile:<名字>@<home>
  /// （登记里读不到 home 时才退回老形状 profile:<名字>，见 order.mbt 的 profile_row_id）
  id : String
  /// 启动时刻（UTC ISO）
  at : String
  /// 这个时刻是从哪读出来的（人话，直接进悬停）
  source : String
}

///|
/// 一个值看起来像不像本后端写的 ISO 时刻。
///
/// 判据故意宽（只看长度与第 11 个字符是不是 T），因为这里要挡的是
/// 「根本不是时刻的东西」——比如空串、或者某天写进来的别的文本。
/// 挡不住的那些由「取最大值」这一条兜：真的都是 ISO 时字典序就是时间序。
fn looks_like_iso(s : String) -> Bool {
  if s.length() < 19 {
    return false
  }
  match s.find("T") {
    Some(i) => i == 10
    None => false
  }
}

///|
/// 往结果里放一条：同 id 已在的时候，只有新的 at 更大才替换。
fn put_latest(
  list : Array[LastStarted],
  id : String,
  at : String,
  source : String,
) -> Unit {
  if id == "" || !looks_like_iso(at) {
    return
  }
  for i = 0; i < list.length(); i = i + 1 {
    if list[i].id == id {
      if @json.compare_code_units(at, list[i].at) > 0 {
        list[i] = { id, at, source, }
      }
      return
    }
  }
  list.push({ id, at, source, })
}

///|
/// 从一条审计行里取「上次启动」，取不到给空数组。
///
/// 只认 action 为 start-instance 或 restart-instance、且 ok == true 的行：失败的那一笔
/// 启动没有把实例起起来，拿它当「上次启动」会把一次没成的事说成启动过。
/// 来源那句点名这一笔是哪种动作（§28.1：重启也算启动，读数里要说清取的是哪一种）。
/// 端口的两条来源（params.port 是请求里指定的、outcome.port 是实际用的）都可能没有 ——
/// 都没有就只产出 profile 那一条，**不拿别的端口顶上**。
fn audit_start_entries(line : Json) -> Array[LastStarted] {
  let out : Array[LastStarted] = []
  let action = match field_of(line, "action") {
    Some(v) =>
      match as_string(v) {
        Some(name) => name
        None => return out
      }
    None => return out
  }
  if !is_start_action(action) {
    return out
  }
  match field_of(line, "ok") {
    Some(v) =>
      match as_bool(v) {
        Some(true) => ()
        _ => return out
      }
    None => return out
  }
  let at = match field_of(line, "at") {
    Some(v) =>
      match as_string(v) {
        Some(s) => s
        None => return out
      }
    None => return out
  }
  let params = match field_of(line, "params") {
    Some(v) => v
    None => @json.empty_object()
  }
  let profile = match field_of(params, "profile") {
    Some(v) =>
      match as_string(v) {
        Some(s) => s
        None => ""
      }
    None => ""
  }
  let source = "audit.jsonl 里 " + action + " 那一笔的时间"
  if profile != "" {
    // 审计行里可能没有 home（start-instance 常常只带 profile 与 port；restart-instance
    // 的 params 由 actions/action.mbt 的 audit_params_for 补上了 home）：
    // 没有 home 时按老形状产 id（profile:<名字>）。登记里那一路有 home，用那一路的。
    // 硬安一个默认 home 上去就等于猜，而猜错的行 id 会对到另一份档案的「上次启动」上。
    let home = match field_of(params, "home") {
      Some(v) =>
        match as_string(v) {
          Some(s) => s
          None => ""
        }
      None => ""
    }
    out.push({ id: profile_row_id(profile, home), at, source, })
  }
  let port = match field_of(params, "port") {
    Some(v) =>
      match as_int(v) {
        Some(n) => Some(n)
        None => None
      }
    None => None
  }
  let port = match port {
    Some(n) => Some(n)
    None =>
      match field_of(line, "outcome") {
        Some(o) =>
          match field_of(o, "port") {
            Some(v) =>
              match as_int(v) {
                Some(n) => Some(n)
                None => None
              }
            None => None
          }
        None => None
      }
  }
  match port {
    Some(n) =>
      out.push({ id: order_id_port_prefix + n.to_string(), at, source, })
    None => ()
  }
  out
}

///|
/// 收集所有「上次启动」条目（按 at 降序）+ 读不动的原因。
pub async fn load_last_started() -> (Array[LastStarted], Array[String]) noraise {
  let paths = state_paths()
  let list : Array[LastStarted] = []
  let notes : Array[String] = []
  // ① runtime.json：控制台自己起过的实例。登记里同时有 port 与 profile，
  // 两条 id 都产出 —— 一只实例停掉之后它会变成 profile 行，那时按 profile 认。
  let registry = load_registry()
  for r in registry.entries {
    if looks_like_iso(r.started_at) {
      let source = "runtime.json 里这条登记的 startedAt"
      put_latest(list, port_row_id(r.port), r.started_at, source)
      if r.profile != "" {
        put_latest(
          list,
          profile_row_id(r.profile, r.home),
          r.started_at,
          source,
        )
      }
    }
  }
  match registry.note {
    Some(n) => notes.push(n)
    None => ()
  }
  // ② audit.jsonl：审计流水。文件可能很大也可能不在；不在只说明这一路没有贡献，
  // 不写成错误（全新环境本来就没有审计文件）。
  if @json.exists(paths.audit) {
    match @json.read_text_file_fs(paths.audit) {
      Ok(text) => {
        let mut bad_lines = 0
        for raw in text.split("\n") {
          let line = @json.trim_both(@json.owned(raw))
          if line == "" {
            continue
          }
          match @json.json_parse(line) {
            Some(json) =>
              for entry in audit_start_entries(json) {
                put_latest(list, entry.id, entry.at, entry.source)
              }
            None => bad_lines = bad_lines + 1
          }
        }
        if bad_lines > 0 {
          notes.push(
            "audit.jsonl 里有 " +
            bad_lines.to_string() +
            " 行解析不出来，已跳过",
          )
        }
      }
      Err(_) => notes.push("读不动 " + paths.audit)
    }
  }
  list.sort_by(fn(a, b) { -@json.compare_code_units(a.at, b.at) })
  (list, notes)
}

///|
/// 「上次启动」这几条的 JSON 形状。
pub fn last_started_json(items : Array[LastStarted]) -> @json.JsonVal {
  let out : Array[@json.JsonVal] = []
  for item in items {
    out.push(
      @json.JObj([
        ("id", @json.JStr(item.id)),
        ("at", @json.JStr(item.at)),
        ("source", @json.JStr(item.source)),
      ]),
    )
  }
  @json.JArr(out)
}
