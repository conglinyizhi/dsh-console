// 提示条与通知历史：notice_* 那一套、令牌清洗（redact_tokens）、文案与回执拼装
// （action_receipt 及各 receipt / interpret_http / success_note / failure_note）。
//
// 2026-10-20 从 app.mbt 拆出来：提示的出口只有一个，那段文案逻辑却横跨文件头部与中部，
// 与动作处理纠缠；拆成一份之后「一句话怎么说」只在这一个文件里找。只搬位置，函数体一个字没改。

///|
/// 成功回执里的 outcome 对象。回执不是约定的形状就给 None ——
/// 拿不到结构就退回通用说法，不猜、也不编一个结果出来。
fn outcome_of(res : Result[String, Error]) -> Map[String, Json]? {
  let raw = match res {
    Err(_) => return None
    Ok(text) => text
  }
  let got = parse_http_result(raw)
  match open_envelope(got.body) {
    Err(_) => None
    Ok(data) => Some(obj_field(data, "outcome"))
  }
}

///|
/// 后端回执原文 → 悬停补充。正文只说人话，机器口径（pid=… / code=…）收在这里。
fn backend_hint(note : String) -> String {
  if note == "" {
    ""
  } else {
    "回执原文：" + note
  }
}

///|
/// 回收站条目的大小：文件数与体积。读不到就照实说读不到，不写 0。
fn outcome_size_text(outcome : Map[String, Json]) -> String {
  let files = int_field(outcome, "files")
  let bytes = num_field(outcome, "bytes")
  let base = trash_count_text(files) + " | " + trash_size_text(bytes)
  match (files, bytes) {
    (Some(_), Some(_)) => base
    _ => {
      let source = str_field(outcome, "sizeSource")
      if source == "" {
        base
      } else {
        base + "（" + source + "）"
      }
    }
  }
}

///|
/// 删除回执：正文只回答「删了会怎样、能不能捞回来」，并指路回收站；
/// 路径 / mode / hardDeleted 这些是实现细节，收进悬停，不许摊在正文上 ✗
///
/// 读不出 mode 就退回一句通用的（name 是这一行在界面上的名字），
/// 不拿一个空 mode 去编「这一版认不出这个值」。
fn delete_receipt(
  name : String,
  outcome : Map[String, Json]?,
) -> (String, String) {
  let outcome = match outcome {
    None => return (name + " 已删除。", "")
    Some(outcome) => outcome
  }
  let profile = str_field(outcome, "profile")
  let who = if profile == "" { name } else { profile }
  let mode = str_field(outcome, "mode")
  if mode == "" {
    return (who + " 已删除。", "")
  }
  let dir = str_field(outcome, "dir")
  let trash_path = str_field(outcome, "trashPath")
  let hard = bool_field(outcome, "hardDeleted")
  let text = if mode == "trash" {
    who + " 已移入回收站，可以从「回收站」里恢复。"
  } else if mode == "hard-delete" {
    who + " 已删除，无法恢复。"
  } else {
    who +
    " 已删除（回执里的 mode 是「" +
    mode +
    "」，这一版认不出这个值）。"
  }
  // home = 这一份是从哪个 home 删的；进回收站时它会连条目一起记下来，恢复按它归位。
  // 记不上时 originError 给原因 —— 那句话必须露出来，不然恢复落到别处时没人知道为什么。
  let home = str_field(outcome, "home")
  let origin_error = str_field(outcome, "originError")
  let hint = "profile=" +
    profile +
    " | dir=" +
    dir +
    " | mode=" +
    mode +
    " | trashPath=" +
    (if trash_path == "" {
      "（硬删，没有回收站落点）"
    } else {
      trash_path
    }) +
    " | hardDeleted=" +
    (if hard { "true" } else { "false" }) +
    (if home == "" { "" } else { " | home=" + home }) +
    (if origin_error == "" {
      ""
    } else {
      " | 来源 home 没记住：" + origin_error
    })
  (text, hint)
}

///|
/// 恢复 / 彻底删除的回执：正文一句话说完，文件数 / 体积 / 路径收进悬停。
/// 后端这两条 note 里在括号里堆了数字（「…（108 个文件 · 526825 字节），无法恢复」），
/// 摊在正文上就是生硬；悬停里照旧能看到，一个字都没丢。
/// 返回空串 = 回执里没有 outcome，调用方退回通用说法。
fn trash_receipt(
  action : String,
  name : String,
  outcome : Map[String, Json]?,
) -> (String, String) {
  let outcome = match outcome {
    None => return ("", "")
    Some(outcome) => outcome
  }
  let profile = str_field(outcome, "profile")
  let who = if profile == "" { name } else { profile }
  if action == "restore-from-trash" {
    let to = str_field(outcome, "restoredTo")
    let hint = outcome_size_text(outcome) +
      (if to == "" { "" } else { " | 恢复到 " + to })
    (who + " 已恢复，回到 profile 列表里。", hint)
  } else {
    let path = str_field(outcome, "path")
    let hint = outcome_size_text(outcome) +
      (if path == "" { "" } else { " | 原路径 " + path })
    (who + " 已彻底删除。", hint)
  }
}

///|
/// 动作回执：谁 + 做了什么 + 结果。
///
/// **不让调用方拼「动作名 + 名字」那种标签**：它以前被贴在提示条句首
/// （label + "：" + 后端那句话），读起来像机翻，同一个名字还会在同一句里出现两遍 ✗
/// 正文只讲人话；后端回执原文与里面的数字、路径一并收进悬停 ✓
fn action_receipt(
  action : String,
  name : String,
  verb : String,
  note : String,
  res : Result[String, Error],
) -> (String, String) {
  let outcome = outcome_of(res)
  if action == "delete-profile" {
    return delete_receipt(name, outcome)
  }
  // 打开工作目录 / 打开配置：**到底是谁去开的，控制台不知道** —— xdg-open 按它自己的
  // 关联挑程序（目录可能是文件管理器，配置可能是 $EDITOR 里配的那一个）。
  // 所以正文只说「本机默认程序」，不猜一个具体的名字出来 ✗
  // 真正用了哪个（opener + pid）在后端回执里，照旧收进悬停。
  if action == "open-path" {
    return (
      name + " 已用本机默认程序" + verb + "。",
      backend_hint(note),
    )
  }
  // 补包（design/design-fixes.md §39.3）：正文就要后端那一句短的
  //（「<名> 的包已装齐（pnpm install --prefer-offline，3 秒）」），
  // 别再加一层「已安装缺的包」。logPath / 退出码 / 用时这些进悬停。
  if action == "repair-packages" {
    let hint = match outcome {
      Some(outcome) =>
        backend_hint(note) +
        (if str_field(outcome, "logPath") == "" {
          ""
        } else {
          "\n日志：" + str_field(outcome, "logPath")
        }) +
        (if str_field(outcome, "command") == "" {
          ""
        } else {
          "\n命令：" +
          str_field(outcome, "command") +
          "（退出码 " +
          int_or(outcome, "exitCode", -1).to_string() +
          "，" +
          (int_or(outcome, "durationMs", 0) / 1000).to_string() +
          " 秒）"
        })
      None => backend_hint(note)
    }
    return (if note == "" { name + " 的包已装齐" } else { note }, hint)
  }
  // 配置 home 两条：回执要把**从哪儿移到哪儿**说清楚，而且要说「这是移动」——
  // 光说「已隔离」的话，使用者还得自己翻读数去确认那份目录现在在哪。
  if action == "isolate-profile" {
    let (from, to) = match outcome {
      Some(outcome) =>
        (str_field(outcome, "movedFrom"), str_field(outcome, "movedTo"))
      None => ("", "")
    }
    let text = if to == "" {
      name + " 已经移至隔离 home。"
    } else {
      name +
      " 已经移至隔离 home：" +
      to +
      "（原来那份不再留在共用 home 里）。"
    }
    let hint = match outcome {
      Some(outcome) =>
        backend_hint(note) +
        (if from == "" { "" } else { "\n移动：" + from + " -> " + to }) +
        (if str_field(outcome, "deviceNote") == "" {
          ""
        } else {
          "\n" + str_field(outcome, "deviceNote")
        })
      None => backend_hint(note)
    }
    return (text, hint)
  }
  if action == "deisolate-profile" {
    let to = match outcome {
      Some(outcome) => str_field(outcome, "movedTo")
      None => ""
    }
    let trash = match outcome {
      Some(outcome) => str_field(outcome, "trashPath")
      None => ""
    }
    let size = match outcome {
      Some(outcome) => outcome_size_text(outcome)
      None => ""
    }
    let head = if to == "" {
      name + " 的目录已经移至共用 home。"
    } else {
      name + " 的目录已经移至共用 home：" + to + "。"
    }
    let tail = if trash == "" {
      ""
    } else {
      "这份额外 home 里剩下的会话与插件状态移到了回收站" +
      (if size == "" { "" } else { "（" + size + "）" }) +
      "，可以捞回来。"
    }
    return (head + tail, backend_hint(note))
  }
  // 配置快照（design/ops-maintenance-jobs.md §16.3）：回执说清这一趟存了什么 / 还原到哪一份，
  // 后端原文与快照目录收进悬停。
  if action == "snapshot-profile" {
    let (files, bytes, dir, at) = match outcome {
      Some(o) =>
        (
          int_or(o, "files", 0),
          num_field(o, "bytes"),
          str_field(o, "dir"),
          str_field(o, "at"),
        )
      None => (0, None, "", "")
    }
    let when = match js_short_time(at) {
      "" => ""
      short => "（" + short + "）"
    }
    let text = "已给 " +
      name +
      " 拍了一张快照" +
      when +
      "：" +
      files.to_string() +
      " 个文件 · " +
      trash_size_text(bytes) +
      "。"
    let hint = backend_hint(note) +
      (if dir == "" { "" } else { "\n快照目录：" + dir })
    return (text, hint)
  }
  if action == "restore-snapshot" {
    let (at, restored, pre_id, dir) = match outcome {
      Some(o) =>
        (
          str_field(o, "at"),
          str_array_field(o, "restored"),
          str_field(obj_field(o, "preSnapshot"), "id"),
          str_field(o, "dir"),
        )
      None => ("", [], "", "")
    }
    let when = match js_short_time(at) {
      "" => "这一份快照"
      short => short + " 那一份"
    }
    let text = if restored.length() == 0 {
      name +
      " 已还原到 " +
      when +
      "，但那三个文件快照里一个都没有，profile 里的内容没动。"
    } else {
      name +
      " 已还原到 " +
      when +
      "（写回 " +
      restored.join("、") +
      "）。"
    }
    let hint = backend_hint(note) +
      (if pre_id == "" { "" } else { "\n还原前那张快照：" + pre_id }) +
      (if dir == "" { "" } else { "\n这一份快照在：" + dir })
    return (text, hint)
  }
  // 整体替换（design/ops-maintenance-jobs.md §17.4）：正文照那一句原话，
  // 写了哪几份 / 搬了哪几个 / 跳过了哪些收进悬停（数字都在正文里，清单在悬停里）。
  if action == "promote-profile" {
    let (from, to, written, moved, skipped, snap_id) = match outcome {
      Some(o) =>
        (
          str_field(o, "from"),
          str_field(o, "to"),
          str_array_field(o, "written"),
          str_array_field(o, "packagesMoved"),
          str_array_field(o, "packagesSkipped"),
          str_field(obj_field(o, "snapshot"), "id"),
        )
      None => ("", "", [], [], [], "")
    }
    if to != "" && from != "" {
      let text = to +
        " 的配置已用 " +
        from +
        " 替换（写了 " +
        written.length().to_string() +
        " 份文件，搬了 " +
        moved.length().to_string() +
        " 个包，跳过 " +
        skipped.length().to_string() +
        " 个已存在的包）；替换前快照 " +
        snap_id
      let mut hint = backend_hint(note)
      match outcome {
        Some(o) => {
          let snap_dir = str_field(obj_field(o, "snapshot"), "dir")
          if snap_dir != "" {
            hint = hint + "\n替换前快照在：" + snap_dir
          }
          for item in str_array_field(o, "packageNotes") {
            hint = hint + "\n" + item
          }
        }
        None => ()
      }
      if written.length() > 0 {
        hint = hint + "\n写过去的文件：" + written.join("、")
      }
      if moved.length() > 0 {
        hint = hint + "\n搬过去的包：" + moved.join("、")
      }
      if skipped.length() > 0 {
        hint = hint +
          "\n同名已存在、没有覆盖的包：" +
          skipped.join("、")
      }
      return (text, hint)
    }
  }
  if action == "restore-from-trash" || action == "purge-trash-item" {
    let (text, hint) = trash_receipt(action, name, outcome)
    if text != "" {
      return (text, hint)
    }
  }
  // 改名与派生的结果里带着一个新名字：读得到就写进句子，读不到只说做了什么
  if action == "rename-profile" || action == "fork-profile" {
    let new_name = match outcome {
      Some(outcome) => str_field(outcome, "newName")
      None => ""
    }
    if new_name != "" {
      let text = if action == "rename-profile" {
        name + " 已改名为 " + new_name + "。"
      } else {
        // 副本里的外部软链接还指向原处（§60.2）：回执带一句短的，细节在悬停里
        let links = match outcome {
          Some(o) => int_or(o, "externalLinks", 0)
          None => 0
        }
        let suffix = if links > 0 {
          "（副本里还有 " +
          links.to_string() +
          " 个软链接指向原处）"
        } else {
          ""
        }
        name + " 已派生出 " + new_name + "。" + suffix
      }
      return (text, backend_hint(note))
    }
  }
  let text = if action == "fork-profile" {
    name + " 已派生出一份新 profile。"
  } else {
    name + " 已" + verb + "。"
  }
  (text, backend_hint(note))
}

///|
/// 取一个字符串数组字段（不是数组 / 元素不是字符串都按空处理）。
fn str_array_field(obj : Map[String, Json], key : String) -> Array[String] {
  let out : Array[String] = []
  for item in arr_field(obj, key) {
    match item {
      Json::String(s) => out.push(s)
      _ => ()
    }
  }
  out
}

///|
/// 备注保存的回执：清空与写入是两件事，后端在 outcome.removed 里说了；说了就照它说。
fn note_receipt(
  name : String,
  note : String,
  res : Result[String, Error],
) -> (String, String) {
  let removed = match outcome_of(res) {
    Some(outcome) => bool_field(outcome, "removed")
    None => false
  }
  let text = if removed {
    name + " 的备注已清空。"
  } else {
    name + " 的备注已保存。"
  }
  (text, backend_hint(note))
}

///|
/// 动作回执 → (成功?, 给用户看的一句话)。失败一律把后端给的码与消息带上，不吞。
fn interpret_http(res : Result[String, Error]) -> (Bool, String) {
  match res {
    Err(err) => (false, "这一步没发出去（" + describe(err) + "）")
    Ok(text) => {
      let got = parse_http_result(text)
      if got.status == 0 {
        (false, "这一步失败了（" + got.transport_error + "）")
      } else if got.status >= 200 && got.status < 300 {
        match open_envelope(got.body) {
          Ok(data) => (true, success_note(data))
          Err(reason) =>
            (
              false,
              "HTTP " +
              got.status.to_string() +
              " | 回执不是约定的格式：" +
              reason,
            )
        }
      } else {
        (false, failure_note(got))
      }
    }
  }
}

///|
/// 成功回执里那句「这次到底发生了什么」：优先用 note，其次把 outcome 摊平。
fn success_note(data : Map[String, Json]) -> String {
  let note = str_field(data, "note")
  if note != "" {
    return note
  }
  match data.get("outcome") {
    Some(Json::Object(outcome)) => {
      let parts : Array[String] = []
      for entry in outcome.iter() {
        let (key, value) = entry
        parts.push(key + "=" + outcome_value_text(value))
      }
      if parts.length() > 0 {
        join_with(parts, " | ")
      } else {
        "完成（outcome 是空的）"
      }
    }
    Some(other) => outcome_value_text(other)
    None => "完成（回执里没有 note / outcome）"
  }
}

///|
fn outcome_value_text(value : Json) -> String {
  match value {
    Json::String(text) => text
    Json::Number(n, ..) => n.to_int().to_string()
    Json::True => "true"
    Json::False => "false"
    Json::Null => "null"
    other => other.stringify()
  }
}

///|
/// 失败回执：状态行 + 后端错误壳里的 code / message。
/// 后端还没提供接口时（例如 404 的空响应体）到这里也要说清「响应体不是约定的错误壳」。
fn failure_note(got : HttpResult) -> String {
  let head = http_status_text(got)
  let root = @json.parse(got.body) catch {
    _ =>
      return head +
        " | 回执不是合法 JSON（这一版可能还没有这个动作）"
  }
  guard root is Json::Object(obj) else {
    return head + " | 回执不是 JSON 对象"
  }
  match obj.get("error") {
    Some(Json::Object(err)) => {
      let code = str_field(err, "code")
      let message = str_field(err, "message")
      if code == "" && message == "" {
        head
      } else if code == "" {
        head + " | " + message
      } else if message == "" {
        head + " | " + code
      } else {
        // 原始错误文本（若有）接在结论后面：提示条正文只取第一句（「。」「；」之前），
        // 悬停与通知历史拿到的是整句 —— raw 不上正文（批注 5）。
        let raw = str_field(err, "raw")
        if raw == "" {
          head + " | " + code + "：" + message
        } else {
          head + " | " + code + "：" + message + "；原始错误：" + raw
        }
      }
    }
    _ => head + " | 回执里没有失败原因"
  }
}

// ── 设置页的状态转移 ────────────────────────────────────────

///|
/// 发一条**成功**提示：底部 toast，flash_ms 之后自己走（悬停在上面时顺延，见 update）。
///
/// 这是动作结果的唯一出口（§14）：设置页保存、关于页切版本、总览的启动 / 复制、
/// 维护页的每一条回执都走它，页面里不再各留一份。
fn notice_ok(model : Model, text : String, hint : String) -> Model {
  notice_put(model, true, text, hint)
}

///|
/// 发一条**失败**提示：常驻提示条，直到下一条动作替换它（不挂到期计时）。
///
/// 失败与成功同住一条出口，但**读取失败不进这里** —— 那解释的是「这一块为什么是空的」，
/// 留在页面原位（§14.4）。
fn notice_err(model : Model, text : String) -> Model {
  notice_put(model, false, text, "")
}

///|
/// 动作失败的正文最多几个字（design/design-fixes.md §32.1）。
pub let failure_text_max : Int32 = 56

///|
/// 失败提示的正文：**只留第一句**（§32.1）。
///
/// 按「。」或「；」切第一刀，取前段；切完还超过 56 个字再截断并补「…」。
/// 被砍掉的不是丢掉：完整原文挂在悬停里，也留在 audit.jsonl 的 message 里
/// （走动作的那一类失败一定有一条审计线，「查看日志」就是去那儿看）。
fn failure_headline(text : String) -> String {
  let buf = StringBuilder()
  let mut n = 0
  let mut truncated = false
  for c in text {
    if c == '。' || c == '；' {
      break
    }
    if n >= failure_text_max {
      truncated = true
      break
    }
    buf.write_char(c)
    n = n + 1
  }
  let head = buf.to_string()
  // 开头就是句号这种（形状坏了）不交一个空正文出去
  if head == "" {
    return text
  }
  if truncated {
    head + "…"
  } else {
    head
  }
}

///|
/// 一条**动作失败**的提示：一句结论 + 一颗「查看日志」（§32.1）。
///
/// 只有这一路带 audit=true：它走的是 POST /api/local/action，后端一定往 audit.jsonl
/// 追了一行（ok=false + code + message）。剪贴板、读数、设置校验那些失败没有审计线，
/// 也就别摆一颗点了看不到东西的按钮。
fn notice_failed_action(model : Model, full : String) -> Model {
  notice_put(model, false, failure_headline(full), full, audit=true)
}

///|
/// 把正文 / 悬停里带令牌的地址洗掉（design/design-fixes.md §32、§36）：
/// `token=xxxx` 整段换成 `…`（连参数名一起去掉），其余一个字不动。
///
/// 为什么在 notice_put 这一处洗：提示条会留在屏幕上、toast 会被回看、通知历史会整条存下来 ——
/// 与其在每个拼文案的地方各记一遍，不如在唯一的出口上守一道。
/// 令牌原值仍然在内存里（notice_url），也仍在实例日志里，只是不上屏。
fn redact_tokens(text : String) -> String {
  let chars : Array[Char] = []
  for c in text {
    chars.push(c)
  }
  let out = StringBuilder()
  let n = chars.length()
  let mut i = 0
  while i < n {
    let matched = i + 6 <= n &&
      chars[i] == 't' &&
      chars[i + 1] == 'o' &&
      chars[i + 2] == 'k' &&
      chars[i + 3] == 'e' &&
      chars[i + 4] == 'n' &&
      chars[i + 5] == '='
    if matched {
      // 整个 token=<值> 换成「…」：令牌原值不上屏，连参数名也不留 ——
      // 正文与历史里因此连 "token=" 这个串都搜不到（§36.1 的验收就是这么查的）。
      i = i + 6
      while i < n && is_token_char(chars[i]) {
        i = i + 1
      }
      out.write_string("…")
      continue
    }
    out.write_char(chars[i])
    i = i + 1
  }
  out.to_string()
}

///|
/// 令牌值的字符集：base64url 那一套（字母数字与 - _ . ~ + / =）。
/// 用「像令牌的字符」而不是「像终止符的字符」来划边界：边界写反了会把后面的中文一起吃掉。
fn is_token_char(c : Char) -> Bool {
  (c >= '0' && c <= '9') ||
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  c == '-' ||
  c == '_' ||
  c == '.' ||
  c == '~' ||
  c == '+' ||
  c == '/' ||
  c == '='
}

///|
/// 换掉当前这条提示：序号 +1，外壳与到期计时都按序号认人。
fn notice_put(
  model : Model,
  ok : Bool,
  text : String,
  hint : String,
  audit~ : Bool = false,
) -> Model {
  let seq = model.notice_serial + 1
  // 末尾句号在这里统一去掉：提示条说的是一句结论，不是一段话
  let body = js_trim_tail_period(text)
  // 带令牌的地址不上屏（§32 / §36）：正文与悬停都洗一遍，历史跟着同一份走
  let safe_text = redact_tokens(body)
  let safe_hint = redact_tokens(hint)
  let at = local_time_now()
  // 通知历史（§36）：新到旧留最近 notice_history_max 条。只在内存里，刷新就清空。
  // 顺序是「新的插在最前面」，侧栏直接照这个顺序摆，不再排一遍。
  let history : Array[NoticeRecord] = [
    { at, ok, text: safe_text, hint: safe_hint, audit, },
  ]
  let mut kept = 1
  for item in model.notice_history {
    if kept < notice_history_max {
      history.push(item)
      kept = kept + 1
    }
  }
  {
    ..model,
    notice_serial: seq,
    notice: Some({ seq, ok, text: safe_text, hint: safe_hint, at, audit, }),
    notice_history: history,
    notice_unread: model.notice_unread + 1,
    flash_fading: false,
    flash_hover: false,
  }
}

///|
/// 把提示收掉：成功 toast 到期，或者下一次动作开始前清场。
/// 悬停补充与那颗「打开 Web UI」跟着正文一起收 —— 它们只属于当前这一条文字。
fn notice_clear(model : Model) -> Model {
  {
    ..model,
    notice: None,
    flash_fading: false,
    flash_hover: false,
    notice_url: None,
    notice_url_notice: "",
  }
}

///|
/// 当前那条提示的（正文, 悬停补充）。没有就是两个空串。
/// 启动收尾那一段要把新地址接在原来的正文后面，所以需要一个读回来的口子。
fn notice_parts(model : Model) -> (String, String) {
  match model.notice {
    None => ("", "")
    Some(n) => (n.text, n.hint)
  }
}

///|
/// 当前那条提示的序号（0 = 没有）。到期消息带着序号回来，对不上就作废。
fn notice_seq(model : Model) -> Int32 {
  match model.notice {
    Some(n) => n.seq
    None => 0
  }
}