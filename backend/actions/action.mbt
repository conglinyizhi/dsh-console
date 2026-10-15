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
/// 取一个可选布尔参数。
fn optional_bool(params : Json, key : String) -> Bool? {
  match @json.json_field(params, key) {
    Some(v) =>
      match v {
        True => Some(true)
        False => Some(false)
        _ => None
      }
    None => None
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
      let fields : Array[(String, @json.JsonVal)] = [
        ("profile", @json.JStr(outcome.profile)),
        ("newName", @json.JStr(outcome.new_name)),
        ("dir", @json.JStr(outcome.dir)),
        ("filesCopied", @json.jint(outcome.files)),
        ("dirsCreated", @json.jint(outcome.dirs)),
        ("skipped", @json.jstr_array(outcome.skipped)),
      ]
      match outcome.started {
        Some(s) => fields.push(("started", spawn_outcome_json(s)))
        None => ()
      }
      @json.JObj([
        ("action", @json.JStr(action)),
        ("outcome", @json.JObj(fields)),
        (
          "note",
          @json.JStr("派生只复制 profile 自己的文件（跳过 node_modules：那是安装产物，提升目录仍解析得到）"),
        ),
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
    "archive-profile" => {
      let profile = require_string(params, "profile")
      let merged = match optional_bool(params, "merged") {
        Some(v) => v
        None => false
      }
      let loaded = @store.load_archive()
      for r in loaded.entries {
        if r.profile == profile {
          fail("conflict", "profile " + profile + " 已经在归档区里了（先取消归档再归档）")
        }
      }
      let record : @store.ArchiveRecord = {
        profile,
        merged,
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
          ("merged", @json.JBool(merged)),
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
