// 从读数派生出来的那些判据：状态灯（instance_light / profile_light / Light 档位）、
// profile 健康与体检、home 归属判定、时间与最近改动、版本与 URL 提示的文案。
//
// 2026-10-20 从 state.mbt 拆出来：这一族全是「读数 → 一句话 + 一个颜色」的纯函数，
// 与 Model 的状态转移不是一件事；拆开之后改判据只看这一份。只搬位置，函数体一个字没改。

///|
/// 卡片图标右上角那颗实心圆的档位（design/design-fixes.md §26.1：四档 + 一档「没读到」）。
///
/// 判据写死在这里，不发挥：
///   * 绿 LightRun   运行中 —— 实例在跑，且这只 profile 没有已知隐患
///   * 黄 LightWarn  有警告 —— 没在跑但有隐患（缺包等），或**在跑而 profile 有缺包等隐患**；
///                   也接住「端口在听、签名不通」这一档（它没在正常服务，是一种警告）
///   * 红 LightFault 上次启动失败 —— 这只 profile 最近一次 start-instance 失败，
///                   且失败之后从来没有成功启动过（判据来自审计流水，见 model 的
///                   ProfileLastStart）。缺包**不再**算故障，归黄。
///   * 无灯 LightStop 已停止 —— 没在跑，也没有警告。**这一档不画灯**（见 light_shown）
/// 另外两档是**状态灯自己需要的**，不属于上面四档：
///   * LightStart 正在起来（启动等待态）。用琥珀，但文案是「正在启动」，
///     不会被读成故障；它在动（dot-pulse），静止态一个动效都没有
///   * LightUnknown 读数里没有状态这一项。**这时不猜颜色**：
///     灯是空心的灰环，抽屉里写清「读不到状态，颜色不猜」
enum Light {
  LightRun
  LightWarn
  LightFault
  LightStart
  LightStop
  LightUnknown
} derive(Eq)

///|
pub extend Light with Eq::{not_equal, equal}

///|
/// 运行行配不上自家 profile 读数（它来自别处 home）时，插件数量 / 最近改动两格的悬停
/// （design/design-fixes.md §33.2）：两个值都是「—」，得说清为什么不是「没有」。
pub let not_in_console_home_note : String = "这只 profile 不在控制台的 DSH_HOME 里，读不到它的这些读数"

///|
/// 页脚那颗灯的轮询间隔（毫秒）与单次探测的超时（design/design-fixes.md §31.1）：
/// 每 5 秒查一次，单次超过 3 秒没有应答就算这一次失败。
pub let health_poll_ms : Int32 = 3000

///|
pub let health_timeout_ms : Int32 = 3000

///|
/// 灯的状态词。**颜色之外的第二条通道**：三档各有自己的说法，
/// 读屏与「看不出颜色」的场合都靠它（§31.1）。
fn health_label(state : ServerHealth) -> String {
  match state {
    HealthChecking => "正在检查…"
    HealthOnline => "服务端在线"
    HealthOffline => "服务端离线"
  }
}

///|
/// 灯与状态词一起用的那一档键（写进 data-state，样式与探针都按它认）。
fn health_key(state : ServerHealth) -> String {
  match state {
    HealthChecking => "checking"
    HealthOnline => "online"
    HealthOffline => "offline"
  }
}

///|
/// 悬停：在线说「多快答的、什么时候查的」，离线说「连挂了几次、最近一次为什么」。
/// 刚进页面还没有结果时说清「还没有第一次结果」—— 不把「还没查」写成「在线」。
pub fn health_hint(model : Model) -> String {
  match model.health_state {
    HealthChecking => "正在检查服务端：还没有第一次结果"
    HealthOnline =>
      "最近一次响应 " +
      model.health_ms.to_string() +
      " ms，检查于 " +
      model.health_at
    HealthOffline => {
      let reason = if model.health_reason == "" {
        "没给出原因"
      } else {
        model.health_reason
      }
      "连续失败 " +
      model.health_fails.to_string() +
      " 次，最近一次：" +
      reason +
      (if model.health_at == "" { "" } else { "（" + model.health_at + "）" })
    }
  }
}

///|
fn version_text(runtime : RuntimeFacts?) -> String {
  match runtime {
    None => "—"
    Some(facts) => facts.dsh_version + "（" + facts.dsh_source_label + "）"
  }
}

///|
fn join_with(items : Array[String], sep : String) -> String {
  let buf = StringBuilder()
  let mut first = true
  for item in items {
    if !first {
      buf.write_string(sep)
    }
    buf.write_string(item)
    first = false
  }
  buf.to_string()
}

///|
/// 显示用换词：读数那句「这个值是从哪读出来的」里，**「字段」这类词要拿掉**。
///
/// 「字段」是数据形状的说法 —— 给改这个工具的人看的。使用者要的是「从哪读到的」，
/// 所以这里把「 字段」整段删掉（连前面那个空格一起，剩下的话照样通顺）：
/// 「入口包 package.json 的 version 字段：/path」→「入口包 package.json 的 version：/path」。
/// **路径、PID、文件名一个都不动**：那是这句话里真正有用的部分。
fn plain_source(text : String) -> String {
  let chars : Array[Char] = []
  for c in text {
    chars.push(c)
  }
  let out = StringBuilder()
  let mut i = 0
  while i < chars.length() {
    if i + 2 < chars.length() &&
      chars[i] == ' ' &&
      chars[i + 1] == '字' &&
      chars[i + 2] == '段' {
      i = i + 3
      continue
    }
    if i + 1 < chars.length() && chars[i] == '字' && chars[i + 1] == '段' {
      i = i + 2
      continue
    }
    out.write_char(chars[i])
    i = i + 1
  }
  out.to_string()
}

///|
/// 进程级原因码对应的短标签（卡上看得见的那一行）。空串 = 没有要说的。
/// 与后端 reason_text 同一套码；这里只缩短，不换意思。
fn process_note(fact : InstanceFact) -> String {
  match fact.process_reason_code {
    "port-join" =>
      if fact.profile is None {
        "cmdline 里没有 --profile"
      } else if fact.version is None {
        "入口包里读不到版本"
      } else {
        ""
      }
    "port-arg" => "进程是按 --port 匹配的，证据弱于 socket inode"
    "process-gone" =>
      "进程不可见：已退出，或不在本 PID 命名空间"
    "fd-unreadable" => "/proc/<pid>/fd 读不到（权限不足）"
    "cmdline-unreadable" => "进程在，但 cmdline 读不到"
    "unscanned" => "没拿到该端口的 socket inode"
    _ => ""
  }
}

///|
/// 这一条是不是本控制台起的：runtime.json 的登记里有同一个端口，且那个 pid 还活着。
/// 只看端口不够 —— 登记过、后来那个 pid 退了端口被别人接走的情况也长得一样。
fn console_started(console : ConsoleFacts?, port : Int32) -> Bool {
  match console {
    None => false
    Some(facts) => {
      let mut found = false
      for entry in facts.runtime {
        if entry.port == port && entry.alive {
          found = true
        }
      }
      found
    }
  }
}

// ── 状态灯（§26.1 四档） ────────────────────────────────────
//
// 卡片上只剩三样：图标与它右上角那颗实心圆、profile 名（左上，右上另有一格端口）、
// 下面一行备注。所以「这只实例怎么样」
// 全部压进那颗圆里，**颜色不能是唯一信息** —— 每一档都带一句为什么，在抽屉里展示，
// 卡片第一行还写着状态词（light_label），灰度截图里也读得出来。
//
// 每一档给两句话，读者不是同一个人：
//   * light_reason —— 抽屉正文那一行，说人话（「它正在 :3080 上应答」）；
//   * light_basis  —— 悬停里的技术依据（哪一条握手应答命中、探测回来的是什么）。
// 正文一个字都不摆内部术语：成因编号、应答标识、组件名这些是给改这个工具的人看的。
//
// 四档的判据来自 design/design-fixes.md §26.1，前端不改口径：
//   绿 = 在跑且没有已知隐患；黄 = 有警告（没在跑但有隐患 / 在跑但 profile 有隐患）；
//   红 = 上一次启动失败且之后没有成功过；无灯 = 已停止（没在跑也没有警告）。
// 状态由读数给。**读数没给的时候前端不猜**：
// 实例卡走 unknown（空心灰环 + 一句「读不到状态，颜色不猜」）；
// 已停止的 profile 卡不一样 —— 它本来就不是实例读数，它的黄/红判据（缺包、patch 在不在、
// 审计里最近一次启动的成败）全都在 profiles 读数里现成摆着，那是照判据算出来的事实，不是猜。

///|
/// 状态灯的类名后缀：样式表里 .dsh-dot.light-* 那一组。
fn light_class(light : Light) -> String {
  match light {
    LightRun => "light-run"
    LightWarn => "light-warn"
    LightFault => "light-fault"
    LightStart => "light-start"
    LightStop => "light-stop"
    LightUnknown => "light-unknown"
  }
}

///|
/// 状态灯写进 DOM 的档名（data-state）。探针与样式都按它认，不按颜色值猜。
fn light_key(light : Light) -> String {
  match light {
    LightRun => "running"
    LightWarn => "warn"
    LightFault => "fault"
    LightStart => "starting"
    LightStop => "stopped"
    LightUnknown => "unknown"
  }
}

///|
/// 这一档画不画灯（§26.1：已停止不显示灯）。
///
/// 返回 false 的档位，视图那边**一个节点都不产出**：不是画一颗透明的圆 ——
/// 透明的圆还在 DOM 里，几何上仍占着一个位置，读屏也还会念它。
/// 「不显示」就是没有。
fn light_shown(light : Light) -> Bool {
  match light {
    LightStop => false
    _ => true
  }
}

///|
/// 档位的人话标签（悬停、抽屉标题都用它）。
///
/// **只写状态，不写颜色**：颜色由那颗圆自己给（颜色不能是唯一信息，但颜色也不必
/// 在文字里再说一遍）。以前写成「绿 · 运行中」，读起来像在念色卡的编号。
fn light_label(light : Light) -> String {
  match light {
    LightRun => "运行中"
    LightWarn => "有警告"
    LightFault => "上次启动失败"
    LightStart => "正在启动"
    LightStop => "已停止"
    LightUnknown => "状态未知"
  }
}

///|
/// 一条握手应答的人话说明：把读数给的那句 describe 里**括号那半句**去掉。
///
/// 括号里写的是「这条应答是谁发的」（组件内部名），那是给改这个工具的人看的；
/// 前半句是真的探测到了什么，使用者看得懂，也正好回答了「哪一条应答命中」。
fn signature_plain(fact : InstanceFact) -> String {
  let buf = StringBuilder()
  let mut stop = false
  for c in fact.signature_describe {
    if stop {
      continue
    }
    if c == '（' || c == '(' {
      stop = true
      continue
    }
    buf.write_char(c)
  }
  buf.to_string()
}

///|
/// profile 那一侧的毛病（空串 = 没毛病，或者手上没有健康读数）。
///
/// 缺包优先说：一只缺包的 profile 比「补丁文件不在」更值得先看。
fn profile_trouble(health : InstanceHealth?, ignore_missing : Bool) -> String {
  match health {
    None => ""
    Some(h) =>
      if h.missing_bundles > 0 && !ignore_missing {
        "这只 profile 缺 " + h.missing_bundles.to_string() + " 个包"
      } else if !h.has_patch {
        "这只 profile 的 cordis.patch.yml 不在"
      } else {
        ""
      }
  }
}

///|
/// 「忽略缺包警告」这一项现在是什么（design/design-fixes.md §40）。
///
/// 三档：读到值 → 按它；读到但这一版后端不认识这个键 → 按缺省 true；
/// 设置读数还没到手 → 也按 true（缺省口径）。**缺省就是「不报警」**，
/// 所以没读到的时候宁可不报警，也不摆一堆黄灯吓人。
fn ignore_missing_bundles(model : Model) -> Bool {
  match model.settings {
    None => true
    Some(facts) =>
      match lookup_setting(facts.values, "profile.ignoreMissingBundles") {
        Some(VBool(v)) => v
        _ => true
      }
  }
}

///|
/// 实例的健康读数：先用实例自己带的那一份，没带就用同一只 profile 的读数顶上
/// （同一个目录，说的是同一件事）。两处都没有才是 None —— 不拿「0 个缺包」顶上：
/// 「读了、一个都不缺」与「没读到」不是一件事。
fn instance_health_facts(
  fact : InstanceFact,
  profile_fact : ProfileFact?,
) -> InstanceHealth? {
  match fact.profile_health {
    Some(health) => Some(health)
    None =>
      match profile_fact {
        Some(item) =>
          Some({
            missing_bundles: item.bundles.missing.length(),
            has_patch: item.patch_exists,
          })
        None => None
      }
  }
}

///|
/// 实例卡的状态灯（§26.1 的四档）：读数给的 state 是**事实**，四档是它加上
/// profile 体检之后落下来的那一格。
///
/// 读数没给状态就走 unknown —— 调用方据此说清「读不到」，不拿握手探测的结果去替它定色。
/// 返回三样：档位、抽屉正文那一句（人话）、悬停里的技术依据（这个结论是怎么来的）。
fn instance_light(
  fact : InstanceFact,
  profile_fact : ProfileFact?,
  ignore_missing : Bool,
) -> (Light, String, String) {
  let port = fact.port.to_string()
  let health = instance_health_facts(fact, profile_fact)
  let trouble = profile_trouble(health, ignore_missing)
  let signature = signature_plain(fact)
  // 绿灯那一句怎么说：体检读数在手上才说「正常」，读不到就如实说读不到 ——
  // 绿只由签名给，不替 profile 说一句没有读数支撑的话。
  let health_note = match health {
    Some(_) =>
      if ignore_missing {
        "；这只 profile 的体检没有别的毛病（cordis.patch.yml 在；缺包这一项按设置不参与判灯）。"
      } else {
        "；这只 profile 的体检也正常（缺包 0，cordis.patch.yml 在）。"
      }
    None =>
      "；这只 profile 的体检读不到（缺包与 patch 都没有读数），绿灯只由握手应答给，不替它说「正常」。"
  }
  match fact.state {
    Some("running") =>
      if trouble == "" {
        (
          LightRun,
          "它正在 :" + port + " 上应答",
          "判据：探测这个端口时命中了 dsh 的握手应答" +
          (if signature == "" { "" } else { "（" + signature + "）" }) +
          health_note,
        )
      } else {
        (
          LightWarn,
          "它正在 :" + port + " 上应答，但" + trouble,
          "判据：握手应答通过了" +
          (if signature == "" { "" } else { "（" + signature + "）" }) +
          "，但 profile 那一侧有一条已知隐患：" +
          trouble +
          "。绿灯只给「在跑且没有已知隐患」的那一档；有隐患归黄（§26.1）。",
        )
      }
    Some("fault") => {
      // 黄（有警告）的两个成因分开算：握手不应答（端口在听、进程像 dsh、应答对不上），
      // 与 profile 那一侧有毛病（缺包 / 补丁文件不在）。两句长得不一样，
      // 不会被一起读成一句含糊的「有点问题」。
      let handshake_failed = fact.signature_id == ""
      let parts : Array[String] = []
      if handshake_failed {
        parts.push("端口在听，但不应答 dsh 的握手")
      }
      if trouble != "" {
        parts.push(trouble)
      }
      let reason = if parts.length() == 0 {
        "读数把这一档判成有警告，但这一版界面读不出具体是哪一条"
      } else {
        join_with(parts, "；")
      }
      let basis = if handshake_failed {
        "判据：这个端口在监听，但探测时没有命中 dsh 的应答" +
        (if fact.http_status > 0 {
          "（回的是 HTTP " + fact.http_status.to_string() + "）"
        } else {
          ""
        }) +
        "。这一档不是红灯：红灯只给「上一次启动失败且之后没成功过」的那一只（§26.1）。"
      } else {
        "判据：握手应答是通的，这一档的隐患在 profile 那一侧。"
      }
      (LightWarn, reason, basis)
    }
    Some("starting") =>
      (
        LightStart,
        "正在起来，端口还没开始应答",
        "启动动作还没收尾：实例应答之后这一档会变成「运行中」。",
      )
    Some("stopped") =>
      (LightStop, "没有在跑", "这个端口上现在没有实例在跑。")
    Some(_) =>
      (
        LightUnknown,
        "读到的状态这一版界面认不出，颜色不猜",
        "读数里的状态取值这一版界面没有对应的档位，所以不上颜色。",
      )
    None =>
      (
        LightUnknown,
        "读不到状态，颜色不猜",
        "这一版读数里没有状态这一项，所以不上颜色。" +
        (if signature == "" {
          "已有的探测结论：这个端口没有命中 dsh 的应答。"
        } else {
          "已有的探测结论：这个端口命中了 dsh 的应答（" +
          signature +
          "）。"
        }),
      )
  }
}

///|
/// 已停止的 profile 卡：四档的判据全在读数里，前端只按 §26.1 落格。
///
/// 这不是「猜颜色」：没有在跑是这一组的分组条件（in_use_by 已经排掉了正在被用的那几只），
/// 缺包与补丁文件在不在来自这份 profiles 读数，红灯那条来自审计流水里这一只
/// 最近一次启动的结局（后端给的 lastStart，前端不自己判）。
///
/// 优先级：红灯（上次启动失败）> 黄（有警告）> 已停止（不画灯）。
/// 红灯排在最前：一只上一次起不来、之后也没起来过的 profile，缺包只是它的成因之一，
/// 说成「有警告」会把真正的那件事（它起不来）压过去。
fn profile_light(
  fact : ProfileFact,
  ignore_missing : Bool,
) -> (Light, String, String) {
  let missing = fact.bundles.missing
  let source = if fact.last_start_source == "" {
    ""
  } else {
    "来源：" + fact.last_start_source + "。"
  }
  match fact.last_start {
    Some(attempt) =>
      if !attempt.ok {
        let when = js_short_time(attempt.at)
        let codes = if attempt.code == "" {
          ""
        } else {
          "（" + attempt.code + "）"
        }
        let why = if attempt.message == "" {
          ""
        } else {
          "：" + attempt.message
        }
        return (
          LightFault,
          "上一次启动失败" +
          (if when == "" { "" } else { "（" + when + "）" }) +
          "，之后没有成功启动过",
          "判据：audit.jsonl 里这只 profile 最近一条启动的结局是失败（action 是 start-instance 或 restart-instance）" +
          codes +
          why +
          "；它之后没有成功启动的记录，所以这一只是红灯。" +
          source,
        )
      }
    None => ()
  }
  // 「最近一次启动」这句话按手上有没有记录说，不拿「没有记录」说成「没有失败」
  let start_note = match fact.last_start {
    Some(_) => "最近一次启动是成功的"
    None => "审计里没有这只 profile 的启动失败记录"
  }
  if missing.length() > 0 && !ignore_missing {
    (
      LightWarn,
      "没有在跑，但这只 profile 缺 " +
      missing.length().to_string() +
      " 个包",
      "判据：这只 profile 声明的包里有这些没装上：" +
      join_with(missing, "、") +
      "。缺包归黄，不是红：红灯只给「上一次启动失败且之后没成功过」（§26.1）。" +
      source,
    )
  } else if !fact.patch_exists {
    (
      LightWarn,
      "没有在跑，但这只 profile 的 cordis.patch.yml 不在",
      "判据：cordis.patch.yml 不在，这只 profile 起不来。这一条归黄，不是红（§26.1）。" +
      source,
    )
  } else {
    (
      LightStop,
      "没有在跑",
      (if ignore_missing && missing.length() > 0 {
        "这只 profile 缺 " +
        missing.length().to_string() +
        " 个包（按设置不参与判灯，可以在抽屉里装）、cordis.patch.yml 也在，"
      } else {
        "这只 profile 的包都装上了、cordis.patch.yml 也在，"
      }) +
      start_note +
      "；只是现在没有实例在用它。" +
      source,
    )
  }
}

///|
/// 抽屉「profile 健康」那一块的正文：只说人话 —— 缺几个包（拿得到名字就带上名字）、
/// 补丁文件在不在。
///
/// 包名清单从 profiles 读数里拿（实例那一侧只给个数）：**名字的个数与手上这个数对得上才用**，
/// 对不上就只说个数 —— 宁可少一句，也不拿另一份读数里的名字去配这一份的个数。
fn instance_health(
  fact : InstanceFact,
  profile_fact : ProfileFact?,
  ignore_missing : Bool,
) -> HealthNote {
  match fact.profile_health {
    Some(health) =>
      health_note_of(
        health.has_patch,
        health.missing_bundles,
        matching_names(profile_fact, health.missing_bundles),
        ignore_missing,
      )
    None =>
      match profile_fact {
        Some(item) =>
          health_note_of(
            item.patch_exists,
            item.bundles.missing.length(),
            join_with(item.bundles.missing, "、"),
            ignore_missing,
          )
        None => no_reading_note()
      }
  }
}

///|
/// profiles 读数里的包名清单，仅当它的个数与手上这个数目一致时才用（见 instance_health）。
fn matching_names(profile_fact : ProfileFact?, count : Int32) -> String {
  match profile_fact {
    Some(item) =>
      if item.bundles.missing.length() == count {
        join_with(item.bundles.missing, "、")
      } else {
        ""
      }
    None => ""
  }
}

///|
/// 抽屉「profile 健康」那一块要的三个值：正文 / 悬停全文 / 是不是自由文本。
///
/// 分类的判据是**我们预先知不知道它长什么样**，不是内容长短：
///   已知且可枚举（缺 N 个包 / cordis.patch.yml 在不在）→ 正文一行摘要，清单进悬停；
///   自由文本（后端报回来的错误串）→ 正文最多两行，原文进悬停。
/// 两类的正文都不许自己长高 —— 形状在 view 那边（.dsh-problem）定死。
priv struct HealthNote {
  text : String
  hint : String
  free : Bool
}

///|
/// 已知且可枚举的那一类：正文一句摘要，**完整内容进悬停**。
///
/// 缺包优先报（一只缺包的 profile 比「补丁文件不在」更值得先看），都不缺才说「都对」。
/// names 为空串 = 手上没有包名清单，这时正文只说个数，悬停也就没什么可补的
/// （为什么没有名字是这一版怎么实现的，不写在给使用者看的那句话里）。
fn health_note_of(
  has_patch : Bool,
  missing_count : Int32,
  names : String,
  ignore_missing : Bool,
) -> HealthNote {
  if missing_count > 0 && !ignore_missing {
    let count = "缺 " + missing_count.to_string() + " 个包"
    {
      text: count,
      hint: count + (if names == "" { "" } else { "：" + names }),
      free: false,
    }
  } else if !has_patch {
    settled_note("没有 cordis.patch.yml")
  } else if ignore_missing && missing_count > 0 {
    // 缺包按设置不报警（§40.2）：状态组不说「缺 N 个包」，但也不能说「都装齐了」——
    // 缺口还在，那句是假话。只留另一半体检结论，缺口在配置组那一行里。
    settled_note("cordis.patch.yml 也在")
  } else {
    settled_note("声明的包都已安装，cordis.patch.yml 也在")
  }
}

///|
/// 一句话说完、没什么可补的已知项（悬停就不挂了：与正文逐字相同的一句不留）。
fn settled_note(text : String) -> HealthNote {
  { text, hint: "", free: false, }
}

///|
/// 手里没有这只 profile 的健康读数：正文一个「—」，**不编一个「都对」顶上**。
fn no_reading_note() -> HealthNote {
  settled_note("—")
}

///|
/// 这一行属于哪一组。判据与总览页分两组那一处是同一把尺子（status 是 Running 的进
/// 「运行中」，其余含启动等待中进「已停止」）—— 两处各写一遍迟早会分叉，
/// 分组一旦分叉，拖动就会把一条行挪进它不在的那一组里。
fn group_of(row : Row) -> String {
  match row.status {
    Running => "running"
    _ => "stopped"
  }
}

///|
/// 已停止那一组的行 id：名字 + home（与后端 store/order.mbt 的 profile_row_id 一字不差）。
///
/// 顺序表是**按键逐字比对**的，两端拼法必须完全一致；home 是文件系统路径（绝对路径），
/// 直接拼进去，不加任何编码 —— 后端那边同样按原文拼、同样按原文校验。
/// home 为空串时给老形状（profile:<名字>）：那是「这一行没有 home 可比」的如实写法。
fn profile_row_id(name : String, home : String) -> String {
  if home == "" {
    "profile:" + name
  } else {
    "profile:" + name + "@" + home
  }
}

///|
/// 归档孤行的行 id：归档记录的名字 + 它属于哪个 home。
///
/// 与 profile 行的 id 分开一套前缀（archived:）：它是另一类行（磁盘上没有目录），
/// 不参与排序，也不该跟同名的那只已停止行撞 id。
fn archived_row_id(name : String, home : String) -> String {
  if home == "" {
    "archived:" + name
  } else {
    "archived:" + name + "@" + home
  }
}

///|
/// 一行「档案在哪」的 home：归档孤行用记录自带的那个，其余行用它自己那一格的值。
///
/// 空串 = 没有可比的值（读数为空 / 后端没给）：调用方据此退回「只按名字认」。
/// 卡片那一格显示的 home 文本是不是一个真路径。
///
/// 「—」与「未知」都是**显示文本**（不适用 / 读不到），不是路径：
/// 拿它们去拼 <home>/profiles/<名>、或者塞进 params.home，就是编一个不存在的目录出来 ✗
/// 凡是要把那一格当路径用（拼目录 / 发参数 / 比 home）都从这一个判断过。
fn home_is_path(text : String) -> Bool {
  text != "" && text != "—" && text != "未知"
}

///|
/// 两个 home 说的是不是同一个 home。
///
/// 只做「逐字相等，或只差一个尾部斜杠」：/a/b 与 /a/b/ 是同一个目录，
/// 多一个斜杠就判成两处，会把同一份档案拆成两份（卡上多一条、组里少一条）。
/// **不解析软链接**（浏览器里做不到，硬猜等于编）；空串（未知 / 没有）一律不算相等 ——
/// 不知道就不认，这正是本文件对 home 的一贯口径。
fn same_home(a : String, b : String) -> Bool {
  if a == "" || b == "" {
    return false
  }
  a == b || a + "/" == b || b + "/" == a
}

///|
/// 一行「档案在哪」的 home：归档孤行用记录自带的那个，其余行用它自己那一格的值。
///
/// 空串 = 没有可比的值（读数为空 / 后端没给 / 那一格写的是显示文本）：调用方据此退回
/// 「只按名字认」。**那一格是「—」/「未知」时不能当路径用**，见 home_is_path。
fn archive_home_of(row : Row) -> String {
  if row.archive_home != "" {
    row.archive_home
  } else if !home_is_path(row.home) {
    // 那一格是「值不存在 / 读不到」的显示文本，不是路径：拿它当 home 用就是编
    ""
  } else {
    row.home
  }
}

///|
/// 一条归档记录说的是不是这一行：名字要对上，home 也要对上。
///
/// 两种「只按名字认」的情形（与后端 archive_target_matches 同一口径）：
///   · 记录没带 home —— 本次改动之前的旧记录，那时只有一个 home 口径，说的就是它；
///   · 这一行给不出 home —— 没有可比的东西，硬比只会把该标成已归档的那一行漏掉。
/// 除了这两种，home 必须相等：同名两份档案在两个 home 里时，正是靠它分开。
fn archive_record_matches_row(
  record : ConsoleArchive,
  name : String,
  home : String,
) -> Bool {
  if record.profile != name {
    return false
  }
  if home == "" || record.home == "" {
    return true
  }
  record.home == home
}

///|
/// 有值时那一格的悬停：说清这是什么数，并写明口径为什么是「最近改动」。
fn mtime_value_hint(ms : Double, source : String) -> String {
  let iso = js_iso_time_ms(ms)
  "这只 profile 目录的最近改动时刻（mtime" +
  (if iso == "" { "" } else { " " + iso }) +
  "，卡上按浏览器本地时间显示）。" +
  "口径是「最近改动」不是「创建时间」：多数文件系统上可靠的创建时间拿不到" +
  "（ctime 会在 chmod / 改名时变，birth time 不通用）；刚派生出来的 profile 一定是最新的。" +
  (if source == "" { "" } else { "来源：" + source })
}

///|
/// 读不到时那一格的悬停：把后端给的 dirMtimeSource 原样带上，不吞、也不换成一句空话。
fn mtime_missing_hint(source : String) -> String {
  "读不到这只 profile 目录的最近改动：" +
  (if source == "" { "读数里没写原因" } else { source })
}

///|
/// 降序比较「最近改动」。None **不是 0**：读不到的要沉到最后，不许跟真有值的混在一起比 ✗
fn mtime_desc(a : Double?, b : Double?) -> Int32 {
  match (a, b) {
    (Some(x), Some(y)) => if x > y { -1 } else if x < y { 1 } else { 0 }
    (Some(_), None) => -1
    (None, Some(_)) => 1
    (None, None) => 0
  }
}

///|
/// 名字升序：同一档里（都没有 mtime）的兜底顺序，让刷新前后是同一个样子。
///
/// **必须用 lexical_compare，不能用 `<`**：MoonBit 的 `Compare` 对 String 是
/// shortlex —— 先比长度、长度相同再逐字符比。于是 `"web-dev" < "headless"` 成立
/// （7 < 8），排出来是「短的在前」，不是人说的「名字升序」。
/// lexical_compare 才是逐字符的字典序（同 Java 的 String.compareTo）。
/// 实测踩过：三张卡按名字升序排成了 web-dev / headless / review-dev。
fn name_asc(a : String, b : String) -> Int32 {
  a.lexical_compare(b)
}
