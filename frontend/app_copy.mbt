// 剪贴板与开发指令：copy_url_action / copy_dev_action / parse_copy_result、
// dev_instruction_text、own_home_of，以及「打开 Web UI」那条 URL 回执（open_web_ui /
// hard_open_done / open_outcome_text）。
//
// 2026-10-20 从 app.mbt 拆出来：这几条都是「把字符串写去哪儿、怎么跟用户说」的活，
// 与动作分发不是一件事。只搬位置，函数体一个字没改。

///|
/// js_open_url（卡上的「打开 Web UI」/ 菜单的「在新标签页打开」）与提示条里那颗
/// 「打开 Web UI」共用的结局口径 → (成没成, 给用户看的一句话)。
/// 「被浏览器拦了」与「打开出错」分开说：这是两件事，处理办法也不一样。
fn open_outcome_text(outcome : String) -> (Bool, String) {
  if outcome == "ok" {
    (
      true, "已在新标签页打开带令牌的地址（能直接过握手，不是 401）",
    )
  } else if outcome == "blocked" {
    (
      false, "没能打开：浏览器把新标签页拦掉了（弹窗拦截）。地址是带令牌的那一条，可以自己去开",
    )
  } else {
    (false, "没能打开（" + outcome + "）")
  }
}

///|
/// 打开 Web UI / 在新标签页打开：两处都开**带令牌的那一条地址**（webUrl），
/// 也就是 dsh 启动横幅里那条能直接过首次握手的地址。
///
/// webUrl 读不到时**一个标签页都不开**：裸地址打开就是一个 401 页面，
/// 「给了链接但用不了」比「说清为什么没有链接」更糟。这时把原因与裸地址一起给人 ——
/// 他从启动它的那个终端里抄 ?token=… 自己拼，比点进一个 401 再回头找原因快。
///
/// 开没开成要看 js_open_url 的返回值：被弹窗拦截也要说清，不报一句空的「已打开」。
fn open_web_ui(model : Model, row_id : String) -> (Model, @cmd.Cmd) {
  let row = match find_row(model.rows, row_id) {
    None => return (model, @cmd.none)
    Some(row) => row
  }
  // 按住 Alt = 按那颗「硬开裸地址」（§15.2），**有没有 key 都一样**：
  // 抽屉里那颗按钮与这条快捷键是同一件事，两边给出的回执也不许长得不一样。
  // 用 Alt 不用 Shift：Shift+点击会被浏览器当成「开新窗口」，那是它自己的手势。
  if js_alt_held() {
    let hint = if row.web_url_source == "" {
      "读不到带令牌的地址，也没有说明原因；裸地址 " +
      row.url
    } else {
      row.web_url_source + "；裸地址 " + row.url
    }
    let outcome = js_open_url(row.url)
    let (ok, text) = if outcome == "ok" {
      (
        true,
        match row.web_url {
          // 这一支不说「带令牌的地址」：开的本来就是裸地址，拿另一套话会自相矛盾
          Some(_) =>
            row.name +
            " 已硬开裸地址（没带 key），打开后可能无法正常使用"
          None =>
            row.name +
            " 不是启动器拉起的，没有 key，已硬开裸地址，打开后可能无法正常使用"
        },
      )
    } else if outcome == "blocked" {
      (
        false,
        row.name +
        " 的裸地址被浏览器拦掉了（弹窗拦截），可以自己去开 " +
        row.url,
      )
    } else {
      (false, row.name + " 的裸地址没能打开（" + outcome + "）")
    }
    return (notice_put(model, ok, text, hint), @cmd.none)
  }
  match row.web_url {
    Some(url) => {
      let (ok, tail) = open_outcome_text(js_open_url(url))
      let text = row.name +
        " 的 Web UI " +
        tail +
        "。地址 " +
        url +
        "（令牌来源：" +
        row.web_url_source +
        "）"
      (notice_put(model, ok, text, ""), @cmd.none)
    }
    None => {
      // 正文只留一句人话，细节（地址、令牌从哪来、为什么没有）全进悬停。
      let hint = if row.web_url_source == "" {
        "读不到带令牌的地址，也没有说明原因；裸地址 " +
        row.url
      } else {
        row.web_url_source + "；裸地址 " + row.url
      }
      (
        notice_put(
          model,
          false,
          row.name +
          " 不是启动器拉起的，没有 key，没有打开（按住 Alt 可以硬开裸地址）",
          hint,
        ),
        @cmd.none,
      )
    }
  }
}

///|
/// 抽屉里「硬开裸地址」那一枪的回执落地（§15.2）。
///
/// 这一枪本身在 DOM 监听器里同步打完（见 view_overview 的 hard_open_click），
/// 这里只按结局说话：开成了、被弹窗拦了、还是报错 —— 三档分开说，不报一句空的「已打开」。
fn hard_open_done(
  model : Model,
  row_id : String,
  url : String,
  outcome : String,
) -> (Model, @cmd.Cmd) {
  let name = row_name(model, row_id)
  let (ok, text) = if outcome == "ok" {
    (true, name + " 已硬开裸地址，打开后可能无法正常使用")
  } else if outcome == "blocked" {
    (
      false,
      name +
      " 的裸地址被浏览器拦掉了（弹窗拦截），可以自己去开 " +
      url,
    )
  } else {
    (false, name + " 的裸地址没能打开（" + outcome + "）")
  }
  (
    notice_put(
      model,
      ok,
      text,
      "裸地址 " +
      url +
      "；这一颗不管有没有 key，直接开裸地址",
    ),
    @cmd.none,
  )
}

///|
/// 两条复制菜单：裸地址与带令牌的地址。
///
/// 复制的是读数里的原值（裸地址就是卡上那一行显示的、带令牌的就是 webUrl），
/// 前端不拼地址、不改写。成没成由剪贴板那一次调用的回执说了算（CopyDone），
/// 这里只负责把要复制的文本挑出来、没有内容时说清为什么。
fn copy_url_action(
  model : Model,
  row_id : String,
  what : String,
  with_token : Bool,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let row = match find_row(model.rows, row_id) {
    None => return (model, @cmd.none)
    Some(row) => row
  }
  // 第二道（第一道是按钮置灰）：裸地址这一枪只认行上那个「有地址可复制」标记。
  // 停用行的 url 是「已停用，无法访问」这个占位串，照着复制的就是把一句占位话写进剪贴板
  // （design/ops-maintenance-jobs.md §13.1）。
  if !with_token && !row.url_copyable {
    return (
      notice_err(
        model,
        row.name +
        " 的" +
        what +
        "没能复制：没在跑，没有访问地址可复制",
      ),
      @cmd.none,
    )
  }
  let text = if with_token {
    match row.web_url {
      Some(url) => url
      None => ""
    }
  } else if row.url == "—" {
    ""
  } else {
    row.url
  }
  if text == "" {
    let why = if with_token {
      if row.web_url_source == "" {
        "读不到带令牌的地址"
      } else {
        "读不到带令牌的地址（" + row.web_url_source + "）"
      }
    } else {
      "这一行的读数里没有访问地址"
    }
    return (
      notice_err(
        model,
        row.name +
        " 的" +
        what +
        "没能复制：" +
        why +
        "，没有可复制的内容",
      ),
      @cmd.none,
    )
  }
  (notice_clear(model), copy_cmd(row.name + " 的" + what, text, emit))
}

///|
/// 剪贴板回执 → (成功?, 给用户看的一句话)。
/// 传输层给的是 { ok, how, error }：ok=true 时写出走的是哪条路，
/// ok=false 时把两个失败原因都带上（clipboard 的 reject 原因 + execCommand 的结果）。

///|
/// 剪贴板回执 → (成没成, 正文, 悬停补充)。
///
/// 正文只说结局，**不提是哪条浏览器接口写进去的**（navigator.clipboard / execCommand
/// 对用户没有意义，而且换个环境就变）。技术原因进悬停，正文保持一句话。
fn parse_copy_result(text : String) -> (Bool, String, String) {
  let root = @json.parse(text) catch {
    _ =>
      return (
        false, "没能复制到剪贴板", "剪贴板调用返回的不是合法 JSON",
      )
  }
  guard root is Json::Object(obj) else {
    return (
      false, "没能复制到剪贴板", "剪贴板调用返回的不是 JSON 对象",
    )
  }
  if bool_field(obj, "ok") {
    let how = str_field(obj, "how")
    (
      true,
      "已复制到剪贴板",
      if how == "" {
        ""
      } else {
        "写入方式：" + how
      },
    )
  } else {
    let why = str_field(obj, "error")
    (false, "没能复制到剪贴板", if why == "" { "" } else { why })
  }
}

///|
/// 这一行**自己的** DSH_HOME：卡上那一格就是它。
///
/// 三种行各有各的出处，都只认它自己那一份：运行中的卡是那一只实例读出来的 home、
/// 已停止的卡是 profiles 读数列它出来的那个 home、归档孤行是归档记录里的那个。
/// 读不到（「—」/「未知」/ 空串）就返回空串让调用方说清 ——
/// **绝不回落到控制台自己的 home** ✗：多 home 之后那正是这个功能要防的事（把开发会话引回主线）。
/// 口径与后端 a 那一条一致：认不出就说认不出。
fn own_home_of(row : Row) -> String {
  if home_is_path(row.home) {
    row.home
  } else {
    ""
  }
}

///|
/// 「复制开发指令」要复制的那段文本：一份**给另一个会话**的任务说明，粘过去就能用。
///
/// 为什么是「复制一段话」而不是「就地开个开发会话」：说明要被粘到**别的** profile 的会话里，
/// 让那边的 agent 针对这一只 profile 开发。开发会话与开发对象分开，改坏了也是坏在隔离的
/// 那一份上，主线不受影响 —— 这就是使用者要的稳妥隔离。
///
/// 五样缺一不可（缺哪样，粘过去那边都得回来问）：
///   1. profile 名；2. 它在磁盘上的目录；3. DSH_HOME；4. 起它做验证的命令；5. 只改这一份的约束。
/// 路径一律从当前读数推（目录 = <DSH_HOME>/profiles/<名>，与后端 profile_fs 同一口径），
/// 前端不另编一份路径 —— 编出来的路径粘过去就是个打不开的目录。
/// home 用的是**这一行自己的**那一个（见 own_home_of）：读不到就一份都不产出，
/// 由调用方如实说「拼不出来」—— 拿控制台自己的 home 顶上，粘过去那边就会去动主线那一份。
///
/// 起法与控制台的「启动」逐项对齐（见后端 actions/instance.mbt 的 start_instance）：
/// 它在 <profile 目录> 下、带着 DSH_HOME 起 dsh --profile <名> --no-open --port <端口>。
/// 命令里那个 8400 是 instance.basePort 的**缺省起点**（控制台也是从这一项往后找第一个
/// 空闲端口），正文里同时写明它可以换成任何一个空闲端口 —— 写死一个数而不说这句，
/// 端口被占时那条命令就是个起不来的命令。
fn dev_instruction_text(
  row : Row,
  name : String,
  env : Array[(String, String)],
) -> String {
  let home = own_home_of(row)
  if home == "" {
    return ""
  }
  let dir = home + "/profiles/" + name
  // 不再带「【给另一个会话的插件开发任务】」那一行头部（§47）：
  // 粘过去的那一端不需要被分类，它要的是事实 —— 目标、目录、home、状态、能不能动进程。
  let head = ""
  let facts = "目标 profile：" +
    name +
    "\n" +
    "目录：" +
    dir +
    "\n" +
    "DSH_HOME：" +
    home +
    "\n"
  // 启动环境（§61.3）：全局 + 这一只合并之后的那几行，值为空的不写。
  // 摆在状态前面 —— 「起它之前先设置」这句话要在那条命令之前读到，不是之后。
  // 这一段是给另一个会话照着设的，所以不带控制台的任何解释：只有 KEY=VALUE。
  let env_lines : Array[String] = []
  for pair in env {
    env_lines.push("  " + pair.0 + "=" + pair.1)
  }
  let env_block = if env_lines.length() == 0 {
    ""
  } else {
    "起它之前先设置：\n" + join_with(env_lines, "\n") + "\n\n"
  }
  // 状态按这一行**现在的事实**分两支：在跑的时候绝不能让它再起一只，
  // 也不该由它去重启用户正在用的进程（design/design-fixes.md §34）。
  let state = match (row.status, row.port_value) {
    (Running, Some(port)) =>
      "状态：正在运行，端口 " +
      port.to_string() +
      "（" +
      (if row.console_started {
        "由本控制台起的"
      } else {
        "不是本控制台起的"
      }) +
      (match row.web_url {
        Some(_) => "）"
        None => "；令牌在启动它的终端里）"
      }) +
      "\n\n" +
      "不要动这只进程，也不要再起第二只。\n" +
      "改完配置之后告诉用户：需要重启 :" +
      port.to_string() +
      " 那一只才会生效，重启由用户来做。\n\n"
    _ =>
      "状态：没在跑\n\n" +
      "需要起它做验证时（与在控制台里点「启动」等价）：\n" +
      "  DSH_HOME=" +
      home +
      " dsh --profile " +
      name +
      " --no-open --port <空闲端口>\n" +
      "  <空闲端口> 换成当前任意空闲端口。留意在哪个目录下起：会话会记在那一份目录的桶里。\n" +
      "起好的那只进程归你管，可以停、可以重启；除它之外别动别的进程。\n\n"
  }
  let rules = "只改 " +
    dir +
    " 这一份下的文件。别的 profile 与主线各是各的，不要碰。"
  head + facts + env_block + state + rules
}

///|
/// 「复制开发指令」这一枪：文本现拼（见 dev_instruction_text），成没成由剪贴板那一次调用的
/// 回执说了算（CopyDone）。拼不出文本时先在本地说清原因，**不往剪贴板里塞一段缺斤少两的说明** ——
/// 那样粘过去那边还得回来问，比没复制更费事。
fn copy_dev_action(
  model : Model,
  row_id : String,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let row = match find_row(model.rows, row_id) {
    None => return (model, @cmd.none)
    Some(row) => row
  }
  let name = match row.profile_name {
    Some(name) => name
    None => ""
  }
  // 启动环境：全局那一段 + 这一只覆盖的那一段（env_merged_pairs 负责次序与覆盖，
  // 值为空的不写）。home 与上面那句 DSH_HOME 用同一个（own_home_of）——
  // 两处一旦不是同一份，「先设置」那几行就挂到了另一只的配置上。
  let env = if name == "" {
    []
  } else {
    // 保留键（DSH_HOME / PATH …）逐条剔掉：控制台起实例时本来就跳过它们（后端
    // env_for_spawn 同一张名单），照抄进指令里就会出现「上面写着 DSH_HOME=<这只的 home>、
    // 下面又 export 了一个 DSH_HOME」这种自相矛盾的两行 —— 而那一个是不会生效的。
    env_merged_pairs(
      model.env_global,
      env_profile_pairs(env_facts_of_model(model), own_home_of(row), name),
    ).filter(fn(pair) { !env_is_reserved(model, pair.0) })
  }
  let text = if name == "" { "" } else { dev_instruction_text(row, name, env) }
  if text == "" {
    let why = if name == "" {
      "这一行的读数里没有 profile 目录名"
    } else {
      "这一行的读数里给不出它自己的 DSH_HOME（home 那一格：「" +
      row.home +
      "」）。指令里的 DSH_HOME 与 profile 目录都得按它自己的 home 拼，" +
      "拿控制台自己的 home 顶上就会把开发会话引回主线，所以这一枪不发"
    }
    return (
      notice_err(
        model,
        row.name +
        " 的开发指令没能复制：" +
        why +
        "，拼不出可粘的说明",
      ),
      @cmd.none,
    )
  }
  (notice_clear(model), copy_cmd(row.name + " 的开发指令", text, emit))
}
