// GET /api/local/console —— 控制台自己的运行时读数（只读）。
//
// 为什么要有这个端点：runtime.json（哪些实例是本控制台起的）与 archive.json（归档记录）
// 是两份状态文件，前端拿不到文件系统。契约里那五个只读接口的形状一个字段都不许动，
// 所以这里另开一个只读端点把它们如实读出去；它本身不写任何东西（alive 是读 /proc 判的）。

///|
/// 控制台状态响应。
async fn console_payload() -> @json.JsonVal noraise {
  let paths = @store.state_paths()
  let registry = @store.load_registry()
  let archive = @store.load_archive()
  let runtime : Array[@json.JsonVal] = []
  for r in registry.entries {
    runtime.push(@json.JObj([
      ("pid", @json.jint(r.pid)),
      ("port", @json.jint(r.port)),
      ("home", @json.JStr(r.home)),
      ("profile", @json.JStr(r.profile)),
      ("startedAt", @json.JStr(r.started_at)),
      ("logPath", @json.JStr(r.log_path)),
      ("detached", @json.JBool(r.detached)),
      ("alive", @json.JBool(process_alive(r.pid))),
    ]))
  }
  let archived : Array[@json.JsonVal] = []
  for r in archive.entries {
    archived.push(@store.archive_json(r))
  }
  let notes : Array[String] = []
  match registry.note {
    Some(n) => notes.push(n)
    None => ()
  }
  match archive.note {
    Some(n) => notes.push(n)
    None => ()
  }
  @json.JObj([
    ("stateDir", @json.JStr(paths.dir)),
    ("settingsPath", @json.JStr(paths.settings)),
    ("runtimePath", @json.JStr(paths.runtime)),
    ("archivePath", @json.JStr(paths.archive)),
    ("auditPath", @json.JStr(paths.audit)),
    ("trashDir", @json.JStr(paths.trash)),
    ("runtime", @json.JArr(runtime)),
    ("archive", @json.JArr(archived)),
    ("notes", @json.jstr_array(notes)),
  ])
}

///|
/// 只答 GET。
pub async fn handle_console(req : @moonback.Request, res : @moonback.Responder, read_at : String) -> Unit {
  let verb = @localapi.method_name(req.meth)
  if verb != "GET" {
    send_method_not_allowed(res, "GET", verb, read_at)
    return
  }
  @localapi.send_ok(res, console_payload(), read_at)
}
