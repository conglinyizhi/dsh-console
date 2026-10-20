// 与实例本身有关的动作：打开目录 / 配置、起停与重启、启动占位页的填充、健康轮询的回执。\n//\n// 2026-10-20 从 app_actions.mbt 拆出来：动作分发那一份已经 3300 多行，实例这一族（启动 /\n// 占位页 / 健康）自成一条链，拆开之后改启动流程不必翻整份分发。只搬位置，函数体一个字没改。\n

///|
/// 打开工作目录 / 编辑配置：POST open-path。
///
/// 目标只有 profile 名与 kind 两个参数 —— **路径不由前端给**（契约里的硬要求），
/// 后端按枚举目标自己解析，前端连一个 path 字段都不拼。
/// 走 send_action 的同一条通道：这一行置忙、回执进全局提示（§14），
/// 失败时把后端给的 code 与 message 原样贴出来（not-found / io-error / not-authorized…），
/// 本地不放行、不假装打开成功。
fn open_path_action(
  model : Model,
  row_id : String,
  kind : String,
  verb : String,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let pairs = match find_row(model.rows, row_id) {
    None => []
    Some(row) =>
      match row.profile_name {
        Some(name) => [
          ("profile", json_text_literal(name)),
          ("kind", json_text_literal(kind)),
        ]
        None => []
      }
  }
  send_action(
    model,
    row_id,
    "open-path",
    row_name(model, row_id),
    verb,
    params_of(pairs),
    emit,
  )
}

///|
/// 页脚那颗灯的一次探测落地（design/design-fixes.md §31.1）。
///
/// 只写这几格 health_*：**页面上的其它读数一个字节都不动** —— 这一枪失败说的是
/// 「服务端没答上来」，不说明 profiles / instances 那几份读数也坏了（各有各的请求）。
///
/// 排下一次：可见时排 5 秒的定时器；已经隐藏了就不排（后台标签页不发请求），
/// 改成挂一个「等可见」的监听，可见那一刻立刻补一次。
fn health_settled(
  model : Model,
  res : Result[String, Error],
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let (ok, ms, reason) = match res {
    Err(err) => (false, 0, "请求没发出去：" + describe(err))
    Ok(text) => parse_health(text)
  }
  let next = {
    ..model,
    health_busy: false,
    health_state: if ok {
      HealthOnline
    } else {
      HealthOffline
    },
    health_ms: ms,
    health_at: local_time_now(),
    health_fails: if ok {
      0
    } else {
      model.health_fails + 1
    },
    health_reason: reason,
  }
  if js_page_hidden() {
    (
      { ..next, health_visible_wait: true },
      listen_visible(emit),
    )
  } else {
    (
      { ..next, health_visible_wait: false },
      @cmd.delay(emit(HealthTick), health_poll_ms),
    )
  }
}

///|
/// 探测回执 →（成没成, 往返毫秒, 失败原因）。回执不是约定形状就当失败，
/// 不拿「解析不出来」说成「在线」。
fn parse_health(text : String) -> (Bool, Int, String) {
  let root = try @json.parse(text) catch {
    _ => return (false, 0, "探测回执不是合法 JSON")
  }
  guard root is Json::Object(obj) else {
    return (false, 0, "探测回执不是 JSON 对象")
  }
  let ok = bool_field(obj, "ok")
  let ms = match int_field(obj, "ms") {
    Some(n) => n
    None => 0
  }
  let reason = str_field(obj, "error")
  (
    ok,
    ms,
    if ok {
      ""
    } else if reason == "" {
      "没给出原因"
    } else {
      reason
    },
  )
}

///|
/// 占下的标页没有下文了（状态在点击与处理之间翻了、或那一行已经不在列表里）：
/// 当场关掉它。开着的白页比没开更糟 —— 用户会以为启动成功了。
fn close_held_tab(profile : String, tab : String) -> Unit {
  if tab == "held" && profile != "" {
    ignore(js_tab_close(profile))
  }
}

///|
/// 启动：先留在原分组显示等待态（状态点在动、三个按钮禁用），再按回执落定。
///
/// 等待态有下限（start_delay_ms）：真实请求可能 50ms 就回来了，但「启动中…」一闪而过
/// 比多等两秒更难用。回执与计时都到齐才收尾，收尾不等于宣布成功 ——
/// 成功的证据是重读 instances 之后那张真的运行中卡。
///
/// tab 是点击那一栈里同步开的占位标页的结局（见 view_overview 的 start_click）：
/// 启动成功之后由 fill_start_tab 把带令牌的地址填进去，失败就在收尾里关掉。
fn start_instance(
  model : Model,
  row : Row,
  profile : String,
  tab : String,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let params = params_of(profile_pairs(row))
  let name = row.name
  if params == "" {
    return (
      notice_err(model, name + " 启动没执行：读数里没有 profile 目录名"),
      @cmd.none,
    )
  }
  // 上一次启动还挂着一个占位标页（同一时刻只跟一只）：先收掉它，不留一张悬空的白页
  if model.start_tab_waiting {
    ignore(js_tab_close(model.start_tab_profile))
  }
  let busy = map_rows(model, row.id, fn(item) { { ..item, status: Starting, busy: true } })
  (
    {
      ..busy,
      act_pending: row.id,
      act_response: false,
      act_tick: false,
      act_ok: false,
      act_note: "",
      act_name: name,
      act_verb: "启动",
      start_tab: tab,
      start_tab_profile: profile,
      start_tab_waiting: false,
      start_tab_tries: 0,
      notice_url: None,
      notice_url_notice: "",
    },
    @cmd.batch([
      action_cmd(row.id, "start-instance", name, "启动", action_body("start-instance", params), emit),
      @cmd.delay(emit(StartTick(row.id)), start_delay_ms),
    ]),
  )
}

///|
/// 启动收尾：回执与计时都到齐才动。
fn finish_start(model : Model, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  if model.act_pending == "" || !model.act_response || !model.act_tick {
    return (model, @cmd.none)
  }
  let id = model.act_pending
  let name = model.act_name
  let verb = model.act_verb
  let ok = model.act_ok
  let note = model.act_note
  let cleared = map_rows(
    {
      ..model,
      act_pending: "",
      act_response: false,
      act_tick: false,
      act_name: "",
      act_verb: "",
    },
    id,
    fn(row) { { ..row, busy: false, status: Stopped, port_note: "" } },
  )
  if ok {
    // 启动成了：占位标页先留着 —— 带令牌的地址由 instances 读数给出（见 fill_start_tab）
    let text = name + " 已" + verb + "。"
    refresh_readings(
      notice_ok({ ..cleared, start_tab_waiting: true }, text, backend_hint(note)),
      emit,
    )
  } else {
    // 启动失败：占位标页没有下文了，当场关掉 —— **不留一张白页**，
    // 关没关成也要在提示条里说出来，不假装收干净了
    let tail = if model.start_tab == "held" {
      match js_tab_close(model.start_tab_profile) {
        "closed" => "；刚开的那个占位标页已经关掉，不留空白页"
        "none" => "；没有留下占位标页"
        other => "；关占位标页时出了岔子（" + other + "），请手动关掉它"
      }
    } else {
      ""
    }
    // 启动失败也走「一句结论 + 查看日志」（§32.1）：这一枪同样写了审计行，
    // 完整原文（pid / argv / 日志路径 / 错误行）在 audit.jsonl 里，悬停里也留着全文。
    // 占位标页那半句（tail）从正文里让出去：它进悬停，正文只留结论。
    (
      notice_failed_action(
        { ..cleared, start_tab: "", start_tab_profile: "", start_tab_waiting: false, start_tab_tries: 0 },
        name + " " + verb + "失败：" + note + tail,
      ),
      @cmd.none,
    )
  }
}

///|
/// 启动的那只 profile 现在有没有带令牌的地址。
///
/// 按 profile 名认，不按行 id：启动前后这一行会从「已停止」的 profile:<名> 变成
/// 运行中的 port:<端口>，id 对不上，名才对得上。
fn start_tab_url(rows : Array[Row], profile : String) -> String? {
  for row in rows {
    match row.profile_name {
      Some(name) =>
        if name == profile {
          match row.web_url {
            Some(url) => return Some(url)
            None => ()
          }
        }
      None => ()
    }
  }
  None
}

///|
/// 那只实例现在为什么没有带令牌的地址（后端原样给的那一句）；读数里还没有它就照实说。
fn start_tab_block_reason(rows : Array[Row], profile : String) -> String {
  for row in rows {
    match row.profile_name {
      Some(name) =>
        if name == profile {
          if row.web_url_source != "" {
            return row.web_url_source
          }
          return "读数里没有说明读不到令牌的原因"
        }
      None => ()
    }
  }
  "instances 读数里还没有这只 profile 的实例"
}

///|
/// 启动成功之后，instances 读数一落地就把带令牌的地址填进占位标页。
///
/// 为什么要等读数：令牌不在启动响应里 —— 它在实例日志的启动横幅里，由
/// /api/local/instances 现算（后端 weburl.mbt）。所以这一枪只能在读数回来之后打。
///
/// 一轮没读到不急着了结：端口先监听、横幅后落盘，在慢机器上是可能的，
/// 最多重读 start_tab_max_tries 轮。等满还读不到就认输 —— 认输也要把占位标页关掉、
/// 把原因写清，**不留白页**。
///
/// 地址到手之后提示条里仍摆一颗「打开 Web UI」（方案 B）：自动开标页可能被拦、
/// 也可能被用户自己关掉，那时再点一下就是新手势，一定开得成。
fn fill_start_tab(model : Model, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  if !model.start_tab_waiting {
    return (model, @cmd.none)
  }
  let profile = model.start_tab_profile
  match start_tab_url(model.rows, profile) {
    Some(url) => {
      let tail = if model.start_tab == "held" {
        match js_tab_goto(profile, url) {
          "ok" => "已在启动时自动打开的那个标页里填上带令牌的地址（能直接过握手，不是 401）"
          "closed" => "启动时占的那个标页已经被关掉了，没有标页可填"
          "gone" => "占了位的标页句柄找不到了（页面可能刷过），没有标页可填"
          other => "往占位标页里填地址失败（" + other + "）"
        }
      } else if model.start_tab == "blocked" {
        "浏览器把自动开的标页拦掉了（弹窗拦截），一个标页都没开"
      } else if model.start_tab == "" {
        "这一次没有开标页（没拿到 profile 目录名）"
      } else {
        "自动开标页没成（" + model.start_tab + "）"
      }
      let (base_text, base_hint) = notice_parts(model)
      // 正文里**不许出现地址**：那条地址带着令牌，提示条会留在屏幕上、也会进通知历史。
      // 要打开就用提示条右侧那颗「打开 Web UI」（它拿的是内存里的 notice_url，不上屏）。
      let text = base_text + "；" + tail
      (
        {
          ..notice_put(model, true, text, base_hint),
          notice_url: Some(url),
          notice_url_notice: text,
          start_tab: "",
          start_tab_profile: "",
          start_tab_waiting: false,
          start_tab_tries: 0,
        },
        @cmd.none,
      )
    }
    None =>
      if model.start_tab_tries < start_tab_max_tries {
        (
          { ..model, start_tab_tries: model.start_tab_tries + 1 },
          @cmd.delay(emit(StartTabRetry), start_tab_retry_ms),
        )
      } else {
        let tail = if model.start_tab == "held" {
          match js_tab_close(profile) {
            "closed" => "已经把这个占位标页关掉，不留空白页"
            "none" => "没有留下空白标页"
            other => "关标页时出了岔子（" + other + "），请手动关掉它"
          }
        } else {
          "本来就没有开成标页"
        }
        let why = start_tab_block_reason(model.rows, profile)
        let (base_text, _) = notice_parts(model)
        (
          notice_err(
            { ..model, start_tab: "", start_tab_profile: "", start_tab_waiting: false, start_tab_tries: 0 },
            base_text + "；等不到带令牌的地址（" + why + "），" + tail +
            "。令牌由实例日志的启动横幅给出，稍后刷新读数再点卡上的「打开 Web UI」",
          ),
          @cmd.none,
        )
      }
  }
}
