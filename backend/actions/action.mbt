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
        "order 里有认不出的行 id：" + id + "（只认 port:<端口号> 与 profile:<名字>）",
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
      let started = start_instance(profile, target.home, target.port)
      @json.JObj([
        ("action", @json.JStr(action)),
        ("outcome", @json.JObj([
          ("stopped", stop_outcome_json(stopped, target, settings.process_stop_grace_ms)),
          ("started", spawn_outcome_json(started)),
        ])),
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
      // **正在跑的不许归档**：归档是「从台面上撤下来」，一只还在跑的实例撤下去，
      // 界面读起来就像它停了 —— 那是把「还在跑」说成了别的。
      // 界面里这一项已经藏了（见 view_overview 的 running_menu），这里再挡一道：
      // 少一层，就有人从别处（脚本、另一个标签页）打进来。
      let report = @instances.instances_report_with_settings()
      for item in report.instances {
        match item.profile {
          Some(name) =>
            if name == profile {
              fail(
                "conflict",
                profile + " 正在跑（端口 " + item.port.to_string() + "）；先停掉它再归档",
              )
            }
          None => ()
        }
      }
      let loaded = @store.load_archive()
      for r in loaded.entries {
        if r.profile == profile {
          fail("conflict", "profile " + profile + " 已经在归档区里了（先取消归档再归档）")
        }
      }
      let record : @store.ArchiveRecord = {
        profile,
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
          ("archivedAt", @json.JStr(record.archived_at)),
          ("archivePath", @json.JStr(paths.archive)),
          ("diskUntouched", @json.JBool(true)),
        ])),
        ("note", @json.JStr("归档只记一条记录，磁盘上的 profile 目录一个字节都没动")),
      ])
    }
    "unarchive-profile" => {
      let profile = require_string(params, "profile")
      let loaded = @store.load_archive()
      let kept : Array[@store.ArchiveRecord] = []
      let mut removed = false
      for r in loaded.entries {
        if r.profile == profile {
          removed = true
        } else {
          kept.push(r)
        }
      }
      if !removed {
        fail("not-found", "归档区里没有 " + profile)
      }
      match @store.save_archive(kept) {
        Ok(_) => ()
        Err(e) => fail("io-error", e)
      }
      @json.JObj([
        ("action", @json.JStr(action)),
        ("outcome", @json.JObj([
          ("profile", @json.JStr(profile)),
          ("removed", @json.JBool(true)),
          ("remaining", @json.jint(kept.length())),
          ("archivePath", @json.JStr(paths.archive)),
        ])),
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
      @json.JObj([
        ("action", @json.JStr(action)),
        ("outcome", @json.JObj([
          ("dir", @json.JStr(outcome.dir)),
          ("profile", @json.JStr(outcome.profile)),
          ("restoredTo", @json.JStr(outcome.to)),
          ("files", @json.int_or_null(outcome.files)),
          ("bytes", @json.int64_or_null(outcome.bytes)),
          ("sizeSource", @json.JStr(outcome.size_source)),
        ])),
        (
          "note",
          @json.JStr(
            "「" + outcome.profile + "」已经回到 profile 列表里（" + outcome.to + "），这一份共 " +
            size,
          ),
        ),
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
    _ => {
      fail("unknown-action", "没有这个动作：" + action)
      abort("unreachable: fail 一定抛错")
    }
  }
}

///|
/// 起实例的结果形状。
pub fn spawn_outcome_json(o : SpawnOutcome) -> @json.JsonVal {
  @json.JObj([
    ("pid", @json.jint(o.pid)),
    ("port", @json.jint(o.port)),
    ("profile", @json.JStr(o.profile)),
    ("home", @json.JStr(o.home)),
    ("logPath", @json.JStr(o.log_path)),
    ("detached", @json.JBool(o.detached)),
    ("bootMs", @json.jint(o.boot_ms)),
    ("command", @json.JStr(o.command)),
    ("url", @json.JStr(o.url)),
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
  // run_action 返回的就是 data：{ action, outcome, note? }
  let data = try {
    run_action(action, params, confirm)
  } catch {
    ActionError(code~, message~) => {
      let _ = audit(action, params_for_audit, false, Some(code), Some(message), @json.JNull)
      send_write_error(res, code, message, read_at)
      return
    }
  }
  let audit_note = audit(action, params_for_audit, true, None, None, data)
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
