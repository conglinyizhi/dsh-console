// 「用哪一版 dsh 起实例」的指定记录：dsh-pin.json。
//
// 形状（与 runtime 那边的候选 DshPackage 对得上，只多一个写入时刻）：
//   { "dir": "<包目录>", "version": "0.2.0-rc.2", "pinnedAt": "2026-10-18T04:00:00.000Z" }
//
// 为什么只存「包目录 + 版本号」两条：包目录是起实例唯一要用的东西（argv 里的
// <包目录>/lib/bin.js），版本号是拿来核对「这一份还是不是当初指定的那一份」的 ——
// pnpm 换布局、目录被重装成另一个版本，都会在这里被抓到，而不是悄悄换了一个 dsh 去起实例。
// 只存包目录不存版本的话，目录没变、里面那份被升级了，用户以为还在用旧版。
//
// 读的口径（这一条比写得重要）：
//   · 文件不存在 —— 没指定过，不是错误，回 auto；
//   · 读不动 / 不是合法 JSON / 三个字段缺一个 —— 同样按「没指定」办，**不报错、也不偷偷写回**。
//     一份坏掉的指定记录不该把整个 runtime 读数拖成 500：它只是「没指定」这一档。
//   · 「指定的那一份还在不在」不在这里判 —— 那要看这台机器上实际装了哪些（runtime 那边有候选表）。
//     这里只回答「用户指定过什么」。
//
// 这一份与 runtime.json / archive.json / order.json 同一套状态目录口径（state_paths）。

///|
/// 一份指定记录。
pub(all) struct DshPin {
  /// dsh 包目录（…/node_modules/@deepseek-ai/dsh）
  dir : String
  /// 指定那一刻这个目录里 package.json 的 version
  version : String
  /// 指定的时刻（UTC ISO8601）
  pinned_at : String
}

///|
/// 对象里的一个字符串字段；字段不在、或不是字符串，给 None。
fn field_string(json : Json, key : String) -> String? {
  match field_of(json, key) {
    Some(v) => as_string(v)
    None => None
  }
}

///|
/// 读指定记录。三种「当没指定」的情形都回 None：文件不在、读不动 / 解析不了、字段不全。
pub async fn load_dsh_pin() -> DshPin? noraise {
  let paths = state_paths()
  let (file, _reason) = read_state_json(paths.dsh_pin)
  let json = match file {
    Some(j) => j
    None => return None
  }
  match (field_string(json, "dir"), field_string(json, "version"), field_string(json, "pinnedAt")) {
    (Some(dir), Some(version), Some(pinned_at)) => {
      let d = @json.trim_both(dir)
      let v = @json.trim_both(version)
      let p = @json.trim_both(pinned_at)
      // 三个字段都在但都是空串，等于什么都没指定
      if d == "" || v == "" || p == "" {
        None
      } else {
        Some({ dir: d, version: v, pinned_at: p })
      }
    }
    _ => None
  }
}

///|
/// 指定记录的形状。
pub fn dsh_pin_json(pin : DshPin) -> @json.JsonVal {
  @json.JObj([
    ("dir", @json.JStr(pin.dir)),
    ("version", @json.JStr(pin.version)),
    ("pinnedAt", @json.JStr(pin.pinned_at)),
  ])
}

///|
/// 写指定记录（原子写）。写不进去把原因原样交回去 ——
/// 回一句「已指定」而盘上没有这份记录，下一次起实例用的还是自动挑出来的那份。
pub async fn save_dsh_pin(pin : DshPin) -> Result[Unit, String] noraise {
  let paths = state_paths()
  @fsx.write_text_atomic(paths.dsh_pin, @json.encode(dsh_pin_json(pin)) + "\n")
}

///|
/// 删掉指定记录（回到自动）。文件本来就不在也算成功 —— 目标状态已经成立。
pub async fn clear_dsh_pin() -> Result[Unit, String] noraise {
  let paths = state_paths()
  if !@json.exists(paths.dsh_pin) {
    return Ok(())
  }
  @fsx.remove_file(paths.dsh_pin)
}
