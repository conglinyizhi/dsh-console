// 写动作的唯一入口：POST /api/local/action（契约第一、二、五节）。
//
// 分发顺序：方法 -> 守卫 -> 解析 body -> 执行 -> 审计 -> 应答。任何一步不过都在这里收敛成
// 契约里那七个错误码之一，并且同样往 audit.jsonl 追一行（失败也要留痕）。

///|
/// 纯路径（不含查询串）。
pub fn path_of(path : StringView) -> String {
  let url = @json.owned(path)
  match url.find("?") {
    Some(i) => @json.slice(url, 0, i)
    None => url
  }
}

///|
/// 这个路径归写侧管吗。写侧只有三条：动作入口、设置、控制台状态（只读）。
pub fn handles_path(path : StringView) -> Bool {
  let p = path_of(path)
  p == "/api/local/action" || p == "/api/local/settings" || p == "/api/local/console"
}

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
/// 执行一个动作。返回 data（action / outcome / note?）。
pub async fn run_action(
  action : String,
  params : Json,
  confirm : String?,
) -> @json.JsonVal raise ActionError {
  let paths = @store.state_paths()
  match action {
    "start-instance" => {
      let profile = require_string(params, "profile")
      let outcome = start_instance(
        profile,
        optional_string(params, "home"),
        optional_int(params, "port"),
      )
      @json.JObj([
        ("action", @json.JStr(action)),
        ("outcome", spawn_outcome_json(outcome)),
        // 用的是哪一版 dsh：回执里说清，用户点了「用这一版」之后能对上号
        ("note", @json.JStr(spawn_version_note(outcome))),
      ])
    }
    "stop-instance" => {
      let target = resolve_target(optional_int(params, "pid"), optional_int(params, "port"))
      let settings = @store.load_settings().values
      let stopped = stop_pid(target.pid, settings.process_stop_grace_ms)
      let _ = @store.remove_by_pid(target.pid)
      @json.JObj([
        ("action", @json.JStr(action)),
        ("outcome", stop_outcome_json(stopped, target, settings.process_stop_grace_ms)),
      ])
    }
    "restart-instance" => {
      let target = resolve_target(optional_int(params, "pid"), optional_int(params, "port"))
      let settings = @store.load_settings().values
      let stopped = stop_pid(target.pid, settings.process_stop_grace_ms)
      let _ = @store.remove_by_pid(target.pid)
      let profile = match target.profile {
        Some(p) => p
        None => {
          fail(
            "not-found",
            "PID " + target.pid.to_string() + " 的 profile 认不出来，重启要先知道起哪个 profile",
          )
          abort("unreachable: fail 一定抛错")
        }
      }
      // 重启沿用**这一只原来那个 home**（target.home），不重新按默认挑：
      // 它的会话与状态都在老 home 里，重启时把它悄悄搬到另一份 home，等于把那一份会话丢在身后。
      // 想让它换到隔离 home 的：先停，再从抽屉里隔离，然后启动。
      let started = start_instance(profile, target.home, target.port)
      @json.JObj([
        ("action", @json.JStr(action)),
        ("outcome", @json.JObj([
          ("stopped", stop_outcome_json(stopped, target, settings.process_stop_grace_ms)),
          ("started", spawn_outcome_json(started)),
        ])),
        ("note", @json.JStr(spawn_version_note(started))),
      ])
    }
    "fork-profile" => {
      let outcome = fork_profile(
        require_string(params, "profile"),
        optional_string(params, "newName"),
        optional_int(params, "port"),
      )
      // 这一轮的派生口径要写在结果里，不能只写在文档里：整目录拷贝，但排除 node_modules，
      // 文件数是这一趟真实拷过去的个数（node_modules 整棵不在其中）。
      // 备注第一行就是"从 <源> 派生 · <时间>"，提示里直接引它，不另抄一份
      let mut note_head = ""
      for line in outcome.note_text.split("\n") {
        note_head = line.to_owned()
        break
      }
      let mut copy_note = "已拷 " + outcome.files.to_string() +
        " 个文件，未拷 node_modules；新 profile 会显示缺包，装一次即可"
      let other_skipped = outcome.skipped.filter(fn(s) { s != "node_modules" })
      if other_skipped.length() > 0 {
        copy_note = copy_note + "（另有跳过：" + other_skipped.join("、") + "）"
      }
      // 使用者的原话里有「那我点这个按钮呢是否有效」——所以提示要说清结果落在哪：
      // 新名字、它在列表最上面（口径是最近改动，不是创建时间）、以及备注写着从哪来。
      let mut note_text = "新 profile「" + outcome.new_name + "」已派生，出现在列表最上面" +
        "（列表按最近改动排序，刚派生的一定最新）。"
      match outcome.note_error {
        Some(reason) =>
          note_text = note_text +
            "备注没写进去（" + reason + "），派生本身成功；" +
            "备注本该在 " + outcome.note_path + " 里写着从 " + outcome.profile + " 派生"
        None =>
          note_text = note_text +
            "它的备注（" + outcome.note_path + "）第一行写着来历：" + note_head
      }
      // 派生的 profile 默认隔离（规格第 8 节）：回执里点名说清落到哪，
      // 没建成也要说清「派生本身成功、隔离没成」—— 两件事不能混成一句。
      match outcome.home_path {
        Some(home) =>
          note_text = note_text + "。已隔离到 " + home + "（以后用这只 profile 起的实例都在里面跑）"
        None =>
          match outcome.home_error {
            Some(reason) =>
              note_text = note_text + "。隔离 home 没建成（" + reason + "），派生本身成功；" +
                "它现在与其它 profile 共用 DSH_HOME"
            None => ()
          }
      }
      note_text = note_text + "。" + copy_note
      let fields : Array[(String, @json.JsonVal)] = [
        ("profile", @json.JStr(outcome.profile)),
        ("newName", @json.JStr(outcome.new_name)),
        ("dir", @json.JStr(outcome.dir)),
        ("filesCopied", @json.jint(outcome.files)),
        ("dirsCreated", @json.jint(outcome.dirs)),
        ("skipped", @json.jstr_array(outcome.skipped)),
        (
          "noteFile",
          @json.JObj([
            ("path", @json.JStr(outcome.note_path)),
            ("text", @json.JStr(outcome.note_text)),
            ("written", @json.JBool(outcome.note_error is None)),
            ("error", @json.str_or_null(outcome.note_error)),
          ]),
        ),
        ("dirMtimeMs", @json.int64_or_null(outcome.dir_mtime_ms)),
        ("dirMtimeSource", @json.JStr(outcome.dir_mtime_source)),
        ("listPosition", @json.JStr("第一个（列表按最近改动降序）")),
        // 派生顺手建的隔离 home：建成了给路径，没建成给原因（派生本身照旧成功）
        ("home", @json.JObj([
          ("path", @json.str_or_null(outcome.home_path)),
          ("error", @json.str_or_null(outcome.home_error)),
        ])),
        ("note", @json.JStr(copy_note)),
      ]
      match outcome.started {
        Some(s) => fields.push(("started", spawn_outcome_json(s)))
        None => ()
      }
      @json.JObj([
        ("action", @json.JStr(action)),
        ("outcome", @json.JObj(fields)),
        ("note", @json.JStr(note_text)),
      ])
    }
    // ── 从基础模板新建（design/design-fixes.md 第 20 节）────────────
    // 现有 profile 全坏 / 全不可用时的备用入口：用 dsh 自带的基础模板新建一份，
    // 不读任何现有配置。新建出来的这份默认隔离（与派生同一档），隔离没建成照实说 ——
    // 「建成了」与「隔离成了」是两件事，不能混成一句。
    "create-base-profile" => {
      ensure_action_params(params, "从基础模板新建", ["name"])
      let outcome = create_base_profile(require_string(params, "name"))
      let home_text = match outcome.home_path {
        Some(path) =>
          "新 profile 默认隔离，已经落到 " + path + "（以后用这只 profile 起的实例都在里面跑）"
        None =>
          match outcome.home_error {
            Some(reason) =>
              "隔离 home 没建成（" + reason + "），它与别的 profile 共用 DSH_HOME"
            None => "隔离 home 没建成，它与别的 profile 共用 DSH_HOME"
          }
      }
      let note_text = "用 dsh " + outcome.dsh_version + "（" + outcome.package_dir +
        "）自带的基础模板 " + base_template_profile + " 新建；核对过三条：package.json 读得出、" +
        "bundles 里有 " + @profiles.web_app_bundle + "、cordis.patch.yml 在；" +
        "dsh 那一步用了 " + outcome.ms.to_string() + " 毫秒。" + home_text
      @json.JObj([
        ("action", @json.JStr(action)),
        ("outcome", @json.JObj([
          ("name", @json.JStr(outcome.name)),
          ("dir", @json.JStr(outcome.dir)),
          // 建的是哪一份模板、用哪一份 dsh 跑的：核对时对得上号
          ("template", @json.JStr(base_template_profile)),
          ("dshVersion", @json.JStr(outcome.dsh_version)),
          ("dshPackageDir", @json.JStr(outcome.package_dir)),
          ("bundles", @json.jstr_array(outcome.bundles)),
          ("ms", @json.jint(outcome.ms)),
          // 隔离建成与没建成是两件事：建成了给路径，没建成给原因（建本身照旧成功）
          ("home", @json.JObj([
            ("path", @json.str_or_null(outcome.home_path)),
            ("error", @json.str_or_null(outcome.home_error)),
          ])),
        ])),
        ("note", @json.JStr(note_text)),
      ])
    }
    "rename-profile" => {
      let outcome = rename_profile(
        require_string(params, "profile"),
        require_string(params, "newName"),
      )
      @json.JObj([
        ("action", @json.JStr(action)),
        ("outcome", @json.JObj([
          ("profile", @json.JStr(outcome.profile)),
          ("newName", @json.JStr(outcome.new_name)),
          ("from", @json.JStr(outcome.from)),
          ("to", @json.JStr(outcome.to)),
        ])),
      ])
    }
    "set-profile-note" => {
      // text 是用户原话，不 trim：前后空格是用户写的，不是噪声；空串是「删掉备注」的语义
      let outcome = set_profile_note(require_string(params, "profile"), require_note_text(params))
      @json.JObj([
        ("action", @json.JStr(action)),
        ("outcome", @json.JObj([
          ("profile", @json.JStr(outcome.profile)),
          ("dir", @json.JStr(outcome.dir)),
          ("path", @json.JStr(outcome.path)),
          ("removed", @json.JBool(outcome.removed)),
          ("chars", @json.jint(outcome.chars)),
          ("maxChars", @json.jint(@profiles.note_max_chars)),
        ])),
        (
          "note",
          @json.JStr(
            if outcome.removed {
              "备注已清空（空串 = 删掉 " + @profiles.note_file_name + "）"
            } else {
              "备注写进 " + outcome.path + "（" + outcome.chars.to_string() + " 字符）"
            },
          ),
        ),
      ])
    }
    // ── 配置快照（design/ops-maintenance-jobs.md 第 16 节）────────────
    // 拍照读 package.json / cordis.patch.yml / pnpm-workspace.yaml，还原写它们；
    // 两条都先过「这只 profile 有实例在跑就拒」的守卫（见 actions/snapshots.mbt）。
    "snapshot-profile" => snapshot_profile_action(params)
    "restore-snapshot" => restore_snapshot_action(params, confirm)
    // ── 整体替换（design/ops-maintenance-jobs.md 第 17 节）────────────
    // 预览只读；应用要先重跑一遍 blockers 再动磁盘（见 actions/promote.mbt）。
    "promote-preview" => promote_preview_action(params)
    "promote-profile" => promote_profile_action(params, confirm)
    "open-path" => {
      // 这个动作的参数只有 profile 与 kind：多一个键就拒，免得有人塞个 path 还以为它生效了
      ensure_only_keys(params, ["profile", "kind"])
      let outcome = open_path(
        require_string(params, "profile"),
        optional_string(params, "kind"),
      )
      let how = match outcome.exit_code {
        Some(code) =>
          "；" + outcome.opener + "（pid " + outcome.pid.to_string() + "）已经退出，退出码 " +
          code.to_string()
        None => "；" + outcome.opener + "（pid " + outcome.pid.to_string() + "）还在跑，没等它"
      }
      @json.JObj([
        ("action", @json.JStr(action)),
        ("outcome", @json.JObj([
          ("what", @json.JStr(outcome.what)),
          ("path", @json.JStr(outcome.path)),
          ("opener", @json.JStr(outcome.opener)),
          ("pid", @json.jint(outcome.pid)),
          ("exitCode", @json.int_or_null(outcome.exit_code)),
          ("detail", @json.JStr(outcome.detail)),
        ])),
        (
          "note",
          @json.JStr(
            "用 " + outcome.opener + " 打开 " + outcome.path + "（直接 exec，不经 shell）" + how,
          ),
        ),
      ])
    }
    "archive-profile" => {
      let profile = require_string(params, "profile")
      // 说的是哪一份：params.home 给了就用它，没给按控制台自己的 home。
      // 这一步必须在「正在跑」守卫之前 —— 守卫比的也是 (home, 名字)。
      let home = archive_target_home(params)
      // **正在跑的不许归档**：归档是「从台面上撤下来」，一只还在跑的实例撤下去，
      // 界面读起来就像它停了 —— 那是把「还在跑」说成了别的。
      // 界面里这一项已经藏了（见 view_overview 的 running_menu），这里再挡一道：
      // 少一层，就有人从别处（脚本、另一个标签页）打进来。
      //
      // 判据是 **(home, 名字)**，与起实例那一侧同一口径：别的 home 里同名的那只是另一只，
      // 不该把这一份挡下来（只比名字时，W1 的 iso 会被 W2 在跑的 iso 挡回 —— 实测过）。
      match running_for_profile_in(profile, Some(home)) {
        Some(hit) => {
          let port_text = match hit.port {
            Some(p) => "端口 " + p.to_string()
            None => "端口未识别"
          }
          fail(
            "conflict",
            profile + " 正在跑（PID " + hit.pid.to_string() + "，" + port_text + "，home " +
            home + "）；先停掉它再归档",
          )
        }
        None => ()
      }
      // 判重按 (home, 名字)：同名不同 home 是两份档案，各归各的 ——
      // 从前只看名字，第二份会被当成「已经在归档区里了」挡回去。
      let loaded = @store.load_archive()
      for r in loaded.entries {
        if @store.archive_target_matches(r, home, profile) {
          fail(
            "conflict",
            "profile " + profile + " 已经在归档区里了（home：" + home + "；先取消归档再归档）",
          )
        }
      }
      let record : @store.ArchiveRecord = {
        profile,
        home,
        archived_at: @json.iso_from_epoch_ms(@async.now()),
      }
      let entries = loaded.entries.copy()
      entries.push(record)
      match @store.save_archive(entries) {
        Ok(_) => ()
        Err(e) => fail("io-error", e)
      }
      @json.JObj([
        ("action", @json.JStr(action)),
        ("outcome", @json.JObj([
          ("profile", @json.JStr(profile)),
          ("home", @json.JStr(record.home)),
          ("archivedAt", @json.JStr(record.archived_at)),
          ("archivePath", @json.JStr(paths.archive)),
          ("diskUntouched", @json.JBool(true)),
        ])),
        ("note", @json.JStr("归档只记一条记录，磁盘上的 profile 目录一个字节都没动")),
      ])
    }
    "unarchive-profile" => {
      let profile = require_string(params, "profile")
      // 取消归档只撤**这一份**：同名另一 home 的记录原样留着。
      // 没带 home 的旧客户端按名字撤（archive_target_matches 里有兼容口径）。
      let home = archive_target_home(params)
      let loaded = @store.load_archive()
      let kept : Array[@store.ArchiveRecord] = []
      let mut removed = false
      for r in loaded.entries {
        if @store.archive_target_matches(r, home, profile) {
          removed = true
        } else {
          kept.push(r)
        }
      }
      if !removed {
        fail("not-found", "归档区里没有 " + profile + "（home：" + home + "）")
      }
      match @store.save_archive(kept) {
        Ok(_) => ()
        Err(e) => fail("io-error", e)
      }
      @json.JObj([
        ("action", @json.JStr(action)),
        ("outcome", @json.JObj([
          ("profile", @json.JStr(profile)),
          ("home", @json.JStr(home)),
          ("removed", @json.JBool(true)),
          ("remaining", @json.jint(kept.length())),
          ("archivePath", @json.JStr(paths.archive)),
        ])),
      ])
    }
    // ── 配置 home（design/deep-home-isolation.md 第 3、9 节）──────────
    // 隔离 = 把 <DSH_HOME>/profiles/<名字> **移**进 <root>/<名字>/profiles/<名字>；
    // 取消隔离 = 移回，剩下的东西进回收站。两条都只碰 homes root 下的 <root>/<名字>
    // 与 DSH_HOME 下那一条（路径核对在 profiles/homes.mbt），不碰别处。
    "isolate-profile" => {
      ensure_action_params(params, "移到独立 home：", ["profile"])
      let profile = require_string(params, "profile")
      validate_profile_name(profile)
      isolated_home_guard(profile)
      let outcome = match @profiles.isolate_profile(profile) {
        Ok(o) => o
        Err((code, message)) => {
          fail(code, message)
          abort("unreachable: fail 一定抛错")
        }
      }
      @json.JObj([
        ("action", @json.JStr(action)),
        ("outcome", @json.JObj([
          ("profile", @json.JStr(outcome.profile)),
          ("path", @json.JStr(outcome.path)),
          ("profileDir", @json.JStr(outcome.profile_dir)),
          // 移动是真的：从哪儿移到哪儿，两段路径都进回执（核对时不用自己拼）
          ("movedFrom", @json.JStr(outcome.from)),
          ("movedTo", @json.JStr(outcome.profile_dir)),
          ("verified", @json.JBool(outcome.verified)),
          ("deviceNote", @json.JStr(outcome.device_note)),
          ("nodeModulesTarget", @json.JStr(outcome.node_modules_target)),
          ("skillsLinked", @json.JBool(outcome.skills_linked)),
          // 凭证只写路径：键与值都进回执，核对时不用猜用的是哪一个键
          ("credentialsKey", @json.JStr(outcome.credentials_key)),
          ("credentialsPath", @json.JStr(outcome.credentials_path)),
          ("createdAt", @json.str_or_null(outcome.created_at)),
        ])),
        (
          "note",
          @json.JStr(
            "已把 " + outcome.from + " 移到 " + outcome.profile_dir + "（移动前核对：" +
            outcome.device_note + "；移动后核对过三条：目录在、package.json 读得出、" +
            "node_modules 有就指得通）；凭证只在 cordis.patch.yml 里写了路径（" +
            outcome.credentials_key + " -> " + outcome.credentials_path +
            "），密钥本身没有复制、也没有软链过来",
          ),
        ),
      ])
    }
    "deisolate-profile" => {
      ensure_action_params(params, "移回共用 home：", ["profile"])
      let profile = require_string(params, "profile")
      validate_profile_name(profile)
      let given = match confirm {
        Some(v) => @json.trim_both(v)
        None => ""
      }
      if given != "DELETE" {
        fail(
          "bad-params",
          "移回共用 home 会把这份额外 home 里剩下的会话与插件状态移到回收站；" +
          "这是破坏性动作，body 顶层必须带 confirm 字段，值是 DELETE",
        )
      }
      isolated_home_guard(profile)
      let outcome = match @profiles.deisolate_profile(profile) {
        Ok(o) => o
        Err((code, message)) => {
          fail(code, message)
          abort("unreachable: fail 一定抛错")
        }
      }
      let size = match (outcome.files, outcome.bytes) {
        (Some(files), Some(bytes)) => files.to_string() + " 个文件 · " + bytes.to_string() + " 字节"
        _ => "文件数读不到（" + outcome.size_source + "）"
      }
      @json.JObj([
        ("action", @json.JStr(action)),
        ("outcome", @json.JObj([
          ("profile", @json.JStr(outcome.profile)),
          ("path", @json.JStr(outcome.home)),
          // 移回哪儿、剩下的东西进了回收站哪一条：两件事分开报
          ("movedTo", @json.JStr(outcome.to)),
          ("trashPath", @json.JStr(outcome.trash_path)),
          ("trashNote", @json.JStr(outcome.trash_note)),
          ("files", @json.int_or_null(outcome.files)),
          ("bytes", @json.int64_or_null(outcome.bytes)),
          ("sizeSource", @json.JStr(outcome.size_source)),
        ])),
        (
          "note",
          @json.JStr(
            "已把 " + outcome.to + " 移回共用 home；这份额外 home 里剩下的东西（会话、插件状态、日志）" +
            "移到回收站 " + outcome.trash_path + "（" + size + "，可以捞回来）。" + outcome.trash_note,
          ),
        ),
      ])
    }
    "delete-profile" => {
      let outcome = delete_profile(require_string(params, "profile"), confirm)
      @json.JObj([
        ("action", @json.JStr(action)),
        ("outcome", @json.JObj([
          ("profile", @json.JStr(outcome.profile)),
          ("dir", @json.JStr(outcome.dir)),
          ("mode", @json.JStr(outcome.mode)),
          ("trashPath", @json.JStr(outcome.trash_path)),
          // 从哪个 home 删的：进回收站时这一条也会被记进 trash-origins.json，
          // 恢复按它归位。记不上时 originError 给出原因（删除本身照旧算成功）。
          ("home", @json.JStr(outcome.home)),
          ("originError", @json.str_or_null(outcome.origin_error)),
          ("confirm", @json.JStr(outcome.confirm)),
          ("hardDeleted", @json.JBool(outcome.mode == "hard-delete")),
        ])),
      ])
    }
    // ── 回收站（第六轮契约第一节）────────────────────────────
    // 恢复：把 trash/<dir> 移回 <profilesRoot>/<profile>。目标已存在一律拒（conflict）——
    // 恢复不是覆盖，盖掉一份同名 profile 是事后无法解释的操作。
    "restore-from-trash" => {
      ensure_only_keys(params, ["dir"])
      let outcome = restore_from_trash(require_string(params, "dir"))
      let size = match (outcome.files, outcome.bytes) {
        (Some(files), Some(bytes)) =>
          files.to_string() + " 个文件 · " + bytes.to_string() + " 字节"
        _ => "文件数读不到（" + outcome.size_source + "）"
      }
      // 「回到 profile 列表里」这句话只有在这一份回到**本控制台看得见的地方**时才成立：
      //   · 控制台自己的 home → 列表里就有它；
      //   · 它自己的隔离 home（<homes root>/<名字>/profiles/<名字>）→ 也列得出来
      //     （真移动之后总览会把隔离的那几只一起列上，见 profiles 的 read_profiles）；
      //   · 别的 home → 本控制台的列表根本不列它，照旧说「回到列表里」就是一句谎。
      let (console_home, _) = @runtime.resolve_dsh_home()
      let landed = if outcome.home == console_home {
        "「" + outcome.profile + "」已经回到 profile 列表里（" + outcome.to + "）"
      } else if @profiles.isolated_home_of(outcome.profile) is Some(iso) &&
        iso == outcome.home {
        "「" + outcome.profile + "」已经回到它自己那个隔离 home（" + outcome.to +
        "），总览里照样看得见它"
      } else {
        "「" + outcome.profile + "」已经回到它自己那个 home（" + outcome.to +
        "）。那不是本控制台的 home，列表里不会出现它"
      }
      let fallback = if outcome.home_recorded {
        ""
      } else {
        "；这一条没有来源 home 记录，是按本控制台的 home 恢复的"
      }
      let forget = match outcome.origin_error {
        Some(e) => "；来源记录没能清掉：" + e
        None => ""
      }
      @json.JObj([
        ("action", @json.JStr(action)),
        ("outcome", @json.JObj([
          ("dir", @json.JStr(outcome.dir)),
          ("profile", @json.JStr(outcome.profile)),
          ("restoredTo", @json.JStr(outcome.to)),
          ("home", @json.JStr(outcome.home)),
          ("homeSource", @json.JStr(outcome.home_source)),
          ("homeRecorded", @json.JBool(outcome.home_recorded)),
          ("originError", @json.str_or_null(outcome.origin_error)),
          ("files", @json.int_or_null(outcome.files)),
          ("bytes", @json.int64_or_null(outcome.bytes)),
          ("sizeSource", @json.JStr(outcome.size_source)),
        ])),
        ("note", @json.JStr(landed + "，这一份共 " + size + fallback + forget)),
      ])
    }
    // 彻底删除：与 delete-profile 的硬删同一风险等级，必须带 confirm = "PURGE"（缺了给 bad-params）。
    "purge-trash-item" => {
      ensure_only_keys(params, ["dir"])
      let outcome = purge_trash_item(require_string(params, "dir"), confirm)
      let size = match (outcome.files, outcome.bytes) {
        (Some(files), Some(bytes)) => files.to_string() + " 个文件 · " + bytes.to_string() + " 字节"
        _ => "文件数读不到（" + outcome.size_source + "）"
      }
      @json.JObj([
        ("action", @json.JStr(action)),
        ("outcome", @json.JObj([
          ("dir", @json.JStr(outcome.dir)),
          ("profile", @json.JStr(outcome.profile)),
          ("path", @json.JStr(outcome.path)),
          ("originError", @json.str_or_null(outcome.origin_error)),
          ("files", @json.int_or_null(outcome.files)),
          ("bytes", @json.int64_or_null(outcome.bytes)),
          ("sizeSource", @json.JStr(outcome.size_source)),
          ("hardDeleted", @json.JBool(true)),
        ])),
        (
          "note",
          @json.JStr(
            "回收站里的「" + outcome.profile + "」已经彻底删掉（" + size + "），无法恢复",
          ),
        ),
      ])
    }
    // ── 手动排序（第十轮）────────────────────────────────
    // 使用者拖着条目换位置，前端把**整份新顺序**提交上来。落盘是原子写，写不进去就
    // 如实失败（io-error）—— 顺序没存下而回一句「已保存」，页面刷新后列表会跳回原样，
    // 而使用者不知道为什么。params 原样进审计：那一行流水就是这份顺序表的变更记录。
    "set-row-order" => {
      let ids = require_order_ids(params)
      match @store.save_order(ids) {
        Ok(_) => ()
        Err(e) => {
          fail("io-error", "顺序没能写进 " + paths.order + "：" + e)
          abort("unreachable: fail 一定抛错")
        }
      }
      @json.JObj([
        ("action", @json.JStr(action)),
        ("outcome", @json.JObj([
          ("count", @json.jint(ids.length())),
          ("orderPath", @json.JStr(paths.order)),
        ])),
        (
          "note",
          @json.JStr(
            if ids.length() == 0 {
              "顺序表已清空，列表回到自动排序"
            } else {
              "顺序表已写入 " + paths.order + "（" + ids.length().to_string() + " 条）"
            },
          ),
        ),
      ])
    }
    // ── 版本切换（回退）────────────────────────────────────
    // 指定 / 撤销「用哪一版 dsh 起实例」。只改控制台自己的记录（dsh-pin.json），
    // 不碰系统上的 dsh 命令、不碰 pnpm 全局安装：起实例时换的只是 argv 里那个包目录。
    // 这两个动作的候选来自 runtime 的 installed_dsh_candidates（就是读数里列出来的那几份）。
    "pin-dsh" => {
      ensure_action_params(params, "指定用哪一版", ["dir"])
      let outcome = pin_dsh(require_string(params, "dir"))
      @json.JObj([
        ("action", @json.JStr(action)),
        ("outcome", @json.JObj([
          ("dir", @json.JStr(outcome.dir)),
          ("version", @json.JStr(outcome.version)),
          ("pinPath", @json.JStr(outcome.pin_path)),
        ])),
        (
          "note",
          @json.JStr(
            "以后起实例（启动 / 重启）用 dsh " + outcome.version +
            "；这一条不走系统上的 dsh 命令，也不动已经装好的东西",
          ),
        ),
      ])
    }
    "unpin-dsh" => {
      ensure_action_params(params, "撤掉指定", [])
      let outcome = unpin_dsh()
      let note = if outcome.removed {
        "指定已经撤掉" +
        (if outcome.previous_version == "" {
          ""
        } else {
          "（原来指定的是 " + outcome.previous_version + "）"
        }) +
        "，以后起实例按自动挑的那一份"
      } else {
        "本来就没有指定过版本，起实例一直是按自动挑的那一份"
      }
      @json.JObj([
        ("action", @json.JStr(action)),
        ("outcome", @json.JObj([
          ("removed", @json.JBool(outcome.removed)),
          ("previousVersion", @json.JStr(outcome.previous_version)),
          ("pinPath", @json.JStr(outcome.pin_path)),
        ])),
        ("note", @json.JStr(note)),
      ])
    }
    // ── 版本列表手动重拉（§11.3）────────────
    // 只排一趟后台刷新，回的是**现在**的缓存（通常 state=loading）；不 await 三个源，
    // 否则这个动作会被网络拖住。刷新结果照旧靠前端的轮询接上。
    "refresh-releases" => {
      ensure_action_params(params, "重新拉取版本列表", [])
      let snapshot = @releases.refresh_releases()
      @json.JObj([
        ("action", @json.JStr(action)),
        ("outcome", @json.JObj([("releases", snapshot)])),
        (
          "note",
          @json.JStr(
            "已经在后台重新拉取版本列表；这里回的是当前缓存那一份，拉完由页面轮询接上新读数",
          ),
        ),
      ])
    }
    // ── 维护作业（design/ops-maintenance-jobs.md §4）────────────
    // 一条作业的五个步骤各有一个动作；install / cleanup 先预演、再带确认执行。
    // 这些动作的 outcome 形状由 job.mbt 的 job_outcome_json 统一套（里面带整份作业，
    // 前端拿到回执就能对上号，不必等下一次读数）。
    "job-start" => {
      let kind = require_string(params, "kind")
      // profile 必填：试跑起的是用户真实 home 里那一份配置，开工时就选定
      let outcome = job_start(
        kind,
        optional_string(params, "version"),
        optional_string(params, "profile"),
      )
      job_outcome_json(action, outcome)
    }
    "job-install" => {
      let id = require_string(params, "id")
      let outcome = job_install(id, optional_bool(params, "confirm"))
      job_outcome_json(action, outcome)
    }
    "job-trial" => {
      let id = require_string(params, "id")
      let outcome = job_trial(id)
      job_outcome_json(action, outcome)
    }
    "job-verdict" => {
      let id = require_string(params, "id")
      let outcome = job_verdict(id, require_string(params, "verdict"))
      job_outcome_json(action, outcome)
    }
    "job-trial-stop" => {
      let id = require_string(params, "id")
      let outcome = job_trial_stop(id)
      job_outcome_json(action, outcome)
    }
    "job-commit" => {
      let id = require_string(params, "id")
      let outcome = job_commit(id)
      job_outcome_json(action, outcome)
    }
    "job-cleanup-preview" => {
      let id = require_string(params, "id")
      let outcome = job_cleanup_preview(id)
      job_outcome_json(action, outcome)
    }
    "job-cleanup" => {
      let id = require_string(params, "id")
      let outcome = job_cleanup(id, optional_string(params, "confirm"))
      job_outcome_json(action, outcome)
    }
    "job-abort" => {
      let id = require_string(params, "id")
      let outcome = job_abort(id)
      job_outcome_json(action, outcome)
    }
    _ => {
      fail("unknown-action", "没有这个动作：" + action)
      abort("unreachable: fail 一定抛错")
    }
  }
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
/// POST /api/local/action 的处理。
async fn handle_action(req : @moonback.Request, res : @moonback.Responder, read_at : String) -> Unit {
  let verb = @localapi.method_name(req.meth)
  if verb != "POST" {
    send_method_not_allowed(res, "POST", verb, read_at)
    return
  }
  let body = req.body.text()
  let parsed = @json.json_parse(body)
  let json = match parsed {
    Some(j) =>
      match j {
        Object(_) => j
        _ => {
          send_write_error(res, "bad-params", "body 要是一个 JSON 对象", read_at)
          return
        }
      }
    None => {
      send_write_error(res, "bad-params", "body 不是合法 JSON", read_at)
      return
    }
  }
  let action = match @json.json_field(json, "action") {
    Some(v) =>
      match @json.json_string(v) {
        Some(s) => @json.trim_both(s)
        None => ""
      }
    None => ""
  }
  if action == "" {
    send_write_error(res, "bad-params", "body 里缺少 action", read_at)
    return
  }
  let params = match @json.json_field(json, "params") {
    Some(v) =>
      match v {
        Object(_) => v
        Null => @json.empty_object()
        _ => {
          send_write_error(res, "bad-params", "params 要是一个对象", read_at)
          return
        }
      }
    None => @json.empty_object()
  }
  let confirm = match @json.json_field(json, "confirm") {
    Some(v) => @json.json_string(v)
    None => None
  }
  // 守卫在解析之后、执行之前：解析本身不产生副作用，先给出「body 不对」比先给 403 更好排查
  let params_for_audit = json_to_val(params)
  let auth_result = try {
    authorize(req)
    Ok(())
  } catch {
    ActionError(code~, message~) => Err((code, message))
  }
  match auth_result {
    Err(pair) => {
      let _ = audit(action, params_for_audit, false, Some(pair.0), Some(pair.1), @json.JNull)
      send_write_error(res, pair.0, pair.1, read_at)
      return
    }
    Ok(_) => ()
  }
  // 审计行里的 params：重启那一档另补 profile / home（见 audit_params_for）。
  // 放在守卫之后：没通过守卫的请求不去解目标，那一笔审计照旧用原始 params。
  let audit_params = audit_params_for(action, params)
  // run_action 返回的就是 data：{ action, outcome, note? }
  let data = try {
    run_action(action, params, confirm)
  } catch {
    ActionError(code~, message~) => {
      let _ = audit(action, audit_params, false, Some(code), Some(message), @json.JNull)
      send_write_error(res, code, message, read_at)
      return
    }
  }
  let audit_note = audit(action, audit_params, true, None, None, data)
  send_write_ok(
    res,
    match audit_note {
      Some(reason) => with_note(data, "审计追加失败：" + reason)
      None => data
    },
    read_at,
  )
}

///|
/// 给 data 补一条 note（审计追加失败时用；已经带了 note 就追加在后面）。
fn with_note(data : @json.JsonVal, note : String) -> @json.JsonVal {
  match data {
    @json.JObj(fields) => {
      let out : Array[(String, @json.JsonVal)] = []
      let mut merged = false
      for pair in fields {
        if pair.0 == "note" {
          match pair.1 {
            @json.JStr(old) => out.push(("note", @json.JStr(old + "；" + note)))
            _ => out.push(("note", @json.JStr(note)))
          }
          merged = true
        } else {
          out.push(pair)
        }
      }
      if !merged {
        out.push(("note", @json.JStr(note)))
      }
      @json.JObj(out)
    }
    other => other
  }
}

///|
/// 写侧总入口。三个端点各按自己的方法表判定，别的路径不该走到这里。
pub async fn dispatch(req : @moonback.Request, res : @moonback.Responder, read_at : String) -> Unit {
  let path = path_of(req.path)
  match path {
    "/api/local/action" => handle_action(req, res, read_at)
    "/api/local/settings" => handle_settings(req, res, read_at)
    "/api/local/console" => handle_console(req, res, read_at)
    _ => send_method_not_allowed(res, "GET", @localapi.method_name(req.meth), read_at)
  }
}
