// 「上一次启动的结局」：这只 (home, profile) 最近一次启动是成是败。
//
// 只给状态灯用一条判据（design/design-fixes.md §26.1、§27.1）：最近一次是失败、且失败
// 之后没有成功记录 → 红灯「上次启动失败」；最近一次成功 → 按其余三档。
// 「最近一次是失败、且它之后没有成功记录」与「最近一条就是失败」是同一件事 ——
// 只要后面有过一次成功，那一次成功自己就是最近那一条。所以这里只留每个
// (profile, home) 最近的那一笔，不另存「之后有没有成功」。
//
// **一次「启动」有两个入口**（§27.1）：start-instance（起一只）与 restart-instance
// （先停后起）。两种都写审计、都算数 —— 只读前者的时候，一次失败的重启改不了红灯判据。
// 取最新时把两种动作放在一起按 at 比，谁新算谁；读出来的 action 说清这一笔是哪一种。
//
// 数据只从控制台自己的审计流水里取（audit.jsonl），一个字都不编：
//   行 = { at, action, params, ok, code, message, outcome }
//   取 action 为上面那两种之一的那些行；ok 就是这一次的结局；
//   params.profile / params.home 是这一次起的是哪一只（home 可能没有，见下）；
//   code / message 是失败时后端写下的原因（成功时是 null）。
//
// 为什么不读 .archive/ 里的历史审计：滚动之后主文件保留最近 audit_retain_lines 条
// （缺省 2000），再往前的在 .archive/ 下。「最近一次启动」要的是**最近**那一条，
// 它必然在主文件里（除非这台机器 2000 条动作之内都没起过实例，那时就不给红灯，
// 不给灯也不说谎）。与 laststarted.mbt 同一套取舍。
//
// 同一个 (profile, home) 有多条：留 at 最大的那一条。at 都是本后端自己写的
// UTC ISO（iso_from_epoch_ms），字典序即时间序。

///|
/// 一条启动结局。
pub(all) struct StartAttempt {
  /// 起的是哪一只 profile（审计行里没有 profile 的那一笔直接跳过：认不出是谁的不算证据）
  profile : String
  /// 这一笔是哪种动作写下的：start-instance 或 restart-instance。
  /// 读数里的来源说明要用它说清「取到的这一条是哪一种启动」
  action : String
  /// 那一笔带的 home；空串 = 审计行里没带（改动之前的老记录，或调用方只发了名字）
  home : String
  /// 这一笔的时刻（UTC ISO）
  at : String
  /// 结局：true = 起成了，false = 这一次失败
  ok : Bool
  /// 失败码（conflict / not-found / spawn-failed / bad-params …）；成功时空串
  code : String
  /// 失败时后端写下的那句人话；成功时空串
  message : String
}

///|
/// 这个动作名算不算「一次启动」（§27.1：起一只与重启一只都算）。
fn is_start_action(name : String) -> Bool {
  name == "start-instance" || name == "restart-instance"
}

///|
/// 从一条审计行里取「启动结局」，取不到给 None。
fn start_attempt_of(line : Json) -> StartAttempt? {
  let action = match field_of(line, "action") {
    Some(v) =>
      match as_string(v) {
        Some(name) => name
        None => return None
      }
    None => return None
  }
  if !is_start_action(action) {
    return None
  }
  let ok = match field_of(line, "ok") {
    Some(v) =>
      match as_bool(v) {
        Some(b) => b
        None => return None
      }
    None => return None
  }
  let at = match field_of(line, "at") {
    Some(v) =>
      match as_string(v) {
        Some(s) => s
        None => return None
      }
    None => return None
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
  if profile == "" {
    return None
  }
  let home = match field_of(params, "home") {
    Some(v) =>
      match as_string(v) {
        Some(s) => s
        None => ""
      }
    None => ""
  }
  let code = match field_of(line, "code") {
    Some(v) =>
      match as_string(v) {
        Some(s) => s
        None => ""
      }
    None => ""
  }
  let message = match field_of(line, "message") {
    Some(v) =>
      match as_string(v) {
        Some(s) => s
        None => ""
      }
    None => ""
  }
  Some({ profile, action, home, at, ok, code, message })
}

///|
/// 同一个 (profile, home) 只留最近那一条：新的 at 更大才替换。
///
/// 同一个毫秒里的一起一停（at 相等）按流水顺序取后写的那一条：后写的才是最后发生的。
/// 这一档在 start-instance 与 restart-instance 混在一起比的时候会真碰上，所以写 >=。
fn put_latest_attempt(list : Array[StartAttempt], item : StartAttempt) -> Unit {
  for i = 0; i < list.length(); i = i + 1 {
    let old = list[i]
    if old.profile == item.profile && old.home == item.home {
      if @json.compare_code_units(item.at, old.at) >= 0 {
        list[i] = item
      }
      return
    }
  }
  list.push(item)
}

///|
/// 收集所有启动结局（按 at 降序）+ 读不动的原因。
///
/// 审计文件不存在只说明这一路没有贡献，不写成错误（全新环境本来就没有审计文件）；
/// 读不动 / 有行解析不出来时把原因带回去，由调用方原样放进读数里的来源说明。
pub async fn load_start_attempts() -> (Array[StartAttempt], Array[String]) noraise {
  let paths = state_paths()
  let list : Array[StartAttempt] = []
  let notes : Array[String] = []
  if @json.exists(paths.audit) {
    match @json.read_text_file(paths.audit) {
      Ok(text) => {
        let mut bad_lines = 0
        for raw in text.split("\n") {
          let line = @json.trim_both(@json.owned(raw))
          if line == "" {
            continue
          }
          match @json.json_parse(line) {
            Some(json) =>
              match start_attempt_of(json) {
                Some(item) => put_latest_attempt(list, item)
                None => ()
              }
            None => bad_lines = bad_lines + 1
          }
        }
        if bad_lines > 0 {
          notes.push("audit.jsonl 里有 " + bad_lines.to_string() + " 行解析不出来，已跳过")
        }
      }
      Err(e) => notes.push("读不动 " + paths.audit + "：" + e)
    }
  }
  list.sort_by(fn(a, b) { -@json.compare_code_units(a.at, b.at) })
  (list, notes)
}
