// 写动作的取参与审计小件：字符串 / 布尔 / 整数取参、整份顺序表、home 归一、隔离 home 守卫、
// 审计行与「失败也带 outcome」的那套机制，以及起停实例几个 outcome → JSON 的转换。
//
// 2026-10-20 从 action.mbt 拆出来：那个文件 1285 行，`run_action` 一个 700 多行的 match 与
// 这些碎件混在一起；拆开之后「请求长什么样 / 审计怎么写」与「动作做什么」分开读。
// 只搬位置，函数体一个字没改。


///|
/// core Json -> 有序 JsonVal（审计行要按固定字段序输出，所以自己转一遍）。
pub fn json_to_val(json : Json) -> @json.JsonVal {
  match json {
    Null => @json.JNull
    True => @json.JBool(true)
    False => @json.JBool(false)
    Number(d, ..) => @json.JNum(d)
    String(s) => @json.JStr(s)
    Array(items) => {
      let out : Array[@json.JsonVal] = []
      for item in items {
        out.push(json_to_val(item))
      }
      @json.JArr(out)
    }
    Object(fields) => {
      let out : Array[(String, @json.JsonVal)] = []
      for k, v in fields {
        out.push((k, json_to_val(v)))
      }
      @json.JObj(out)
    }
  }
}

///|
/// 取一个必填字符串参数。
fn require_string(params : Json, key : String) -> String raise ActionError {
  match @json.json_field(params, key) {
    Some(v) =>
      match @json.json_string(v) {
        Some(s) =>
          if @json.trim_both(s) == "" {
            fail("bad-params", key + " 不能是空串")
            abort("unreachable: fail 一定抛错")
          } else {
            @json.trim_both(s)
          }
        None => {
          fail("bad-params", key + " 要是字符串")
          abort("unreachable: fail 一定抛错")
        }
      }
    None => {
      fail("bad-params", "缺少参数 " + key)
      abort("unreachable: fail 一定抛错")
    }
  }
}

///|
/// 取一个可选字符串参数（给了但为空串按没给算）。
fn optional_string(params : Json, key : String) -> String? {
  match @json.json_field(params, key) {
    Some(v) =>
      match @json.json_string(v) {
        Some(s) =>
          if @json.trim_both(s) == "" {
            None
          } else {
            Some(@json.trim_both(s))
          }
        None => None
      }
    None => None
  }
}

///|
/// 取一个可选布尔参数。
///
/// 与 optional_string 同一套严格：字段不在按缺省（false）算，给了但不是布尔就拒 ——
/// 一个 "true" 字符串被当成 false 吞下去，用户按了「确认执行」而系统只做了预演，
/// 那比报一个参数错误难查得多。
fn optional_bool(params : Json, key : String) -> Bool raise ActionError {
  match @json.json_field(params, key) {
    None => false
    Some(True) => true
    Some(False) => false
    Some(_) => {
      fail("bad-params", key + " 要是布尔值（true / false）")
      abort("unreachable: fail 一定抛错")
    }
  }
}

///|
/// 取一个可选整数参数：JSON 数字或十进制数字串都认（前端两种都可能发）。
fn optional_int(params : Json, key : String) -> Int? {
  match @json.json_field(params, key) {
    Some(v) =>
      match v {
        Number(d, ..) =>
          if d == d.to_int().to_double() {
            Some(d.to_int())
          } else {
            None
          }
        String(s) =>
          if @json.is_all_digits(s) {
            Some(@json.parse_dec(s))
          } else {
            None
          }
        _ => None
      }
    None => None
  }
}

///|
/// 取备注文本。与 require_string 的区别只有一个但在这一轮是关键的：
/// 空串在这里是合法取值（= 删掉备注文件），所以不 trim、不把空串当缺参。
/// 缺 key 或不是字符串仍然拒绝 —— 那不是「清空」，是调用方写错了。
fn require_note_text(params : Json) -> String raise ActionError {
  match @json.json_field(params, "text") {
    Some(v) =>
      match @json.json_string(v) {
        Some(s) => s
        None => {
          fail("bad-params", "text 要是字符串（空串表示删掉备注）")
          abort("unreachable: fail 一定抛错")
        }
      }
    None => {
      fail("bad-params", "缺少参数 text（空串表示删掉备注）")
      abort("unreachable: fail 一定抛错")
    }
  }
}

///|
/// 归档 / 取消归档说的是**哪一份**档案：params.home 给了就用它，没给按控制台自己的 home。
///
/// 为什么必须能带 home：一份档案的身份是 (home, 名字)。控制台当前只列自己那个 home 的
/// profile，所以界面带上来的就是它读到的那个 home；等跨 home 聚合落地，这一路不用再改。
/// 给了但不像个路径一律拒 —— 这个值会进归档记录的判重键，写坏了以后分不清谁是谁。
async fn archive_target_home(params : Json) -> String raise ActionError {
  match optional_string(params, "home") {
    None => {
      let (home, _) = @runtime.resolve_dsh_home()
      home
    }
    Some(raw) =>
      match @store.normalize_home(raw) {
        Some(home) => home
        None => {
          fail("bad-params", "home 要是一个绝对的目录路径（不含 . 与 .. 段）：" + raw)
          abort("unreachable: fail 一定抛错")
        }
      }
  }
}

///|
/// 取「整份新顺序」参数：order 必须是一个字符串数组，每一项都是一个认得出的行 id。
///
/// 每一条都当场拒掉，一条都不放过：
///   · 缺参数 / 不是数组 / 元素不是字符串 —— 那是调用方写错了，不是「清空」
///   · id 形状不对（不是 port:<数字> 或 profile:<名字>）
///   · 同一个 id 出现两次 —— 带重复项的顺序表读的时候必然有一份是废的
///   · 条数超上限
/// 空数组是合法的：那是「清空顺序表」，页面回到自动排序。
///
/// 这里**不做合并**：调用方给的就是要落盘的那一份。增量式接口（「把 A 挪到 B 前」）
/// 要后端先读一份当前顺序再算，两次并发拖动就会互相覆盖；整份提交的语义是明确的 ——
/// 谁的请求后到，谁那一份算数。
fn require_order_ids(params : Json) -> Array[String] raise ActionError {
  let raw = match @json.json_field(params, "order") {
    Some(v) => v
    None => {
      fail("bad-params", "缺少参数 order（整份新顺序的行 id 数组）")
      abort("unreachable: fail 一定抛错")
    }
  }
  let items = match raw {
    Array(list) => list
    _ => {
      fail("bad-params", "order 要是一个字符串数组")
      abort("unreachable: fail 一定抛错")
    }
  }
  if items.length() > @store.order_max_ids {
    fail(
      "bad-params",
      "order 最多 " + @store.order_max_ids.to_string() + " 条，收到 " + items.length().to_string() +
      " 条",
    )
    abort("unreachable: fail 一定抛错")
  }
  let ids : Array[String] = []
  for item in items {
    let id = match @json.json_string(item) {
      Some(s) => @json.trim_both(s)
      None => {
        fail("bad-params", "order 的每一项都要是字符串")
        abort("unreachable: fail 一定抛错")
      }
    }
    if !@store.order_id_valid(id) {
      fail(
        "bad-params",
        "order 里有认不出的行 id：" + id +
        "（只认 port:<端口号> 与 profile:<名字>@<home>）",
      )
      abort("unreachable: fail 一定抛错")
    }
    if ids.contains(id) {
      fail("bad-params", "order 里有重复的行 id：" + id)
      abort("unreachable: fail 一定抛错")
    }
    ids.push(id)
  }
  ids
}

///|
/// 移动这份 profile 之前的那道守卫：同一个 profile 不许有实例在跑。
///
/// 理由（规格 9.2 第 2 条）：移动是把目录从进程脚下搬走，在跑的那只实例下一次读配置、
/// 读会话、写日志就会落空。两个 home 都查 —— 移进独立 home 前实例跑在控制台的 home 里，
/// 移回共用 home 前则跑在隔离 home 里。
async fn isolated_home_guard(profile : String) -> Unit raise ActionError {
  let (console_home, _) = @runtime.resolve_dsh_home()
  let homes : Array[String] = [console_home]
  match @profiles.isolated_home_of(profile) {
    Some(isolated) =>
      if isolated != console_home {
        homes.push(isolated)
      }
    None => ()
  }
  for home in homes {
    match running_for_profile_in(profile, Some(home)) {
      Some(hit) => {
        let port_text = match hit.port {
          Some(p) => "端口 " + p.to_string()
          None => "端口未识别"
        }
        fail(
          "conflict",
          "profile " + profile + " 有实例在跑（PID " + hit.pid.to_string() + "，" + port_text +
          "，home " + home + "）；移动会把这份目录从它脚下搬走，先停掉它再移",
        )
      }
      None => ()
    }
  }
}

///|
/// 写一行审计（失败不让动作失败，把原因回给调用方拼进 note）。
async fn audit(
  action : String,
  params : @json.JsonVal,
  ok : Bool,
  code : String?,
  message : String?,
  outcome : @json.JsonVal,
) -> String? noraise {
  let line = @store.audit_line(
    @json.iso_from_epoch_ms(@async.now()),
    action,
    params,
    ok,
    code,
    message,
    outcome,
  )
  match @store.append_audit(line) {
    Ok(_) => None
    Err(e) => Some(e)
  }
}

///|
/// 审计行里的 params：`restart-instance` 的请求体只带 pid 或 port，看不出这一次重启的
/// 是哪一只 profile。startattempt 的读取靠 params.profile / params.home 认人，失败那一笔
/// 更要认得出（红灯判据就看它，design/design-fixes.md §27.1），所以跑动作之前先把目标
/// 解出来，把 profile / home 补进审计 params。
///
/// 解不出来（pid 认不出、参数不全）就退回原始 params：那一笔审计照样留痕，只是认不出
/// 是哪一只。认不出是谁的不算证据，读取那边会跳过它。
async fn audit_params_for(action : String, params : Json) -> @json.JsonVal {
  let raw = json_to_val(params)
  // 启动环境（§61.2）：审计只留键名，**值一个字节都不进审计**（值里可能含密钥）。
  if action == "save-env" {
    let fields : Array[(String, @json.JsonVal)] = []
    for pair in @store.object_entries(params) {
      if pair.0 == "entries" {
        let names : Array[String] = []
        for entry in @store.object_entries(pair.1) {
          names.push(entry.0)
        }
        fields.push(("entries", @json.jstr_array(names)))
      } else {
        fields.push((pair.0, json_to_val(pair.1)))
      }
    }
    return @json.JObj(fields)
  }
  if action != "restart-instance" {
    return raw
  }
  let target = try {
    resolve_target(optional_int(params, "pid"), optional_int(params, "port"))
  } catch {
    ActionError(code~, message~) => {
      let _ = code
      let _ = message
      return raw
    }
  }
  // 调用方给的是 pid 还是 port，照原样留着：审计行要能对回请求
  let fields : Array[(String, @json.JsonVal)] = []
  match optional_int(params, "pid") {
    Some(p) => fields.push(("pid", @json.jint(p)))
    None => ()
  }
  match optional_int(params, "port") {
    Some(p) => fields.push(("port", @json.jint(p)))
    None => ()
  }
  match target.profile {
    Some(name) => fields.push(("profile", @json.JStr(name)))
    None => ()
  }
  match target.home {
    Some(home) =>
      if home != "" {
        fields.push(("home", @json.JStr(home)))
      }
    None => ()
  }
  @json.JObj(fields)
}

///|
/// 起实例这件事里「用的是哪一版」那句话（进回执的 note，悬停里能看到）。
///
/// 三种口径分开说：按你指定的 / 没指定过（自动挑的那一份）/ 你指定过但那份不在了（回落自动挑）。
/// 最后一种必须点名说清 —— 用户以为自己指定了旧版，实际起的是新版，这件事不能靠猜。
pub fn spawn_version_note(o : SpawnOutcome) -> String {
  let how = if o.dsh_pin_state == @runtime.pin_state_pinned {
    "（按你指定的版本）"
  } else if o.dsh_pin_state == @runtime.pin_state_missing {
    "；" + o.dsh_pin_note
  } else {
    "（没指定过版本，按自动挑的那一份）"
  }
  "起实例用的 dsh 是 " + o.dsh_version + how
}

///|
/// 起实例的结果形状。
pub fn spawn_outcome_json(o : SpawnOutcome) -> @json.JsonVal {
  @json.JObj([
    ("pid", @json.jint(o.pid)),
    ("port", @json.jint(o.port)),
    ("profile", @json.JStr(o.profile)),
    ("home", @json.JStr(o.home)),
    // isolated / shared：这一只落在自己的隔离 home 里，还是与控制台共用 DSH_HOME
    ("homeKind", @json.JStr(o.home_kind)),
    ("logPath", @json.JStr(o.log_path)),
    ("detached", @json.JBool(o.detached)),
    ("bootMs", @json.jint(o.boot_ms)),
    ("command", @json.JStr(o.command)),
    ("url", @json.JStr(o.url)),
    // 起的是哪一版、为什么是它：点了「用这一版」之后，结果里要能对上号。
    // dshPinNote 只在「你指定过的那一版不在了、这次按自动挑」时非空。
    ("dshVersion", @json.JStr(o.dsh_version)),
    ("dshPackageDir", @json.JStr(o.dsh_package_dir)),
    ("dshPinState", @json.JStr(o.dsh_pin_state)),
    ("dshPinNote", @json.JStr(o.dsh_pin_note)),
  ])
}

///|
/// 停实例的结果形状。
pub fn stop_outcome_json(
  o : StopOutcome,
  target : Target,
  grace_ms : Int,
) -> @json.JsonVal {
  @json.JObj([
    ("pid", @json.jint(o.pid)),
    ("port", @json.int_or_null(target.port)),
    ("profile", @json.str_or_null(target.profile)),
    ("signal", @json.JStr(o.signal)),
    ("sigtermMs", @json.jint(o.sigterm_ms)),
    ("sigkillSent", @json.JBool(o.sigkill)),
    ("waitedMs", @json.jint(o.waited_ms)),
    ("stopGraceMs", @json.jint(grace_ms)),
    ("exited", @json.JBool(o.exited)),
  ])
}

///|
/// 失败那笔审计的结构化细节（§39.2）。ActionError 只有 code 与 message 两个格，
/// 装不下「命令 / 退出码 / 用时 / 日志路径 / 修前修后缺几个」这些字段；
/// 动作在 fail 之前把这些放进这里，handle_action 的 catch 取走写进审计。
///
/// 这么放是安全的：写入点与抛出点之间没有 await（同一个协程一口气跑完），
/// 取走点紧跟 catch —— 两笔并发失败不会互串。
let failure_outcome : Ref[@json.JsonVal] = { val: @json.JNull }

///|
/// 动作失败之前登记这一笔的 outcome（见 failure_outcome）。
pub fn set_failure_outcome(v : @json.JsonVal) -> Unit {
  failure_outcome.val = v
}

///|
/// 取走失败 outcome（取走即清）。
fn take_failure_outcome() -> @json.JsonVal {
  let v = failure_outcome.val
  failure_outcome.val = @json.JNull
  v
}
