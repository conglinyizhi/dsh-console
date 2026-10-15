// GET /api/local/console —— 控制台自己的运行时读数（只读）。
//
// 为什么要有这个端点：runtime.json（哪些实例是本控制台起的）与 archive.json（归档记录）
// 是两份状态文件，前端拿不到文件系统。契约里那五个只读接口的形状一个字段都不许动，
// 所以这里另开一个只读端点把它们如实读出去；它本身不写任何东西（alive 是读 /proc 判的）。

///|
/// 生效的删除方式与它的来源（文件 / 默认）。
///
/// 为什么在这里出一份：设置是**懒加载**的（设置页打开过才读 GET /api/local/settings），
/// 而删除确认框在打开之前就得说清「删了会怎样」。这个端点是「控制台自身状态」的出口，
/// 页面加载时本来就会读，把生效值摆在这儿，前端不必先读过设置也能知道。
///
/// 值取自 @store.load_settings()，与删除动作（actions/profile_fs.mbt）用的是同一处 ——
/// 两处各算一遍迟早会分叉，分叉出来就是「确认框说进回收站、动作却硬删」。
async fn delete_mode_fields() -> Array[(String, @json.JsonVal)] noraise {
  let loaded = @store.load_settings()
  let source = match loaded.sources.get(@store.key_safety_delete_to_trash) {
    Some(s) => s
    None => "默认"
  }
  [
    ("deleteToTrash", @json.JBool(loaded.values.safety_delete_to_trash)),
    ("deleteToTrashSource", @json.JStr(source)),
  ]
}

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
  // 回收站条目（第六轮契约第一节）：trash/ 下每一份删除进回收站的 profile 目录一条。
  // profile 名与删除时刻都从目录名切（按最后一个 '-'，profile 名自己允许带 '-'）；
  // 文件数与体积是递归数出来的，数不动给 null 并把原因写在 sizeSource 里 —— 不编。
  let trash : Array[@json.JsonVal] = []
  for item in list_trash() {
    trash.push(@json.JObj([
      ("dir", @json.JStr(item.dir)),
      ("profile", @json.JStr(item.profile)),
      ("deletedAtMs", @json.int64_or_null(item.deleted_at_ms)),
      ("deletedAtSource", @json.JStr(item.deleted_at_source)),
      ("fileCount", @json.int_or_null(item.file_count)),
      ("bytes", @json.int64_or_null(item.bytes)),
      ("sizeSource", @json.JStr(item.size_source)),
    ]))
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
  let fields : Array[(String, @json.JsonVal)] = [
    ("stateDir", @json.JStr(paths.dir)),
    ("settingsPath", @json.JStr(paths.settings)),
    ("runtimePath", @json.JStr(paths.runtime)),
    ("archivePath", @json.JStr(paths.archive)),
    ("auditPath", @json.JStr(paths.audit)),
    ("trashDir", @json.JStr(paths.trash)),
  ]
  // 生效的删除方式摆在 trashDir 旁边：一处说「进回收站落到哪」，一处说「现在是不是进回收站」
  for pair in delete_mode_fields() {
    fields.push(pair)
  }
  fields.push(("runtime", @json.JArr(runtime)))
  fields.push(("archive", @json.JArr(archived)))
  fields.push(("trash", @json.JArr(trash)))
  fields.push(("notes", @json.jstr_array(notes)))
  @json.JObj(fields)
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
