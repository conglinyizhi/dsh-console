// 派生拷贝的进度（§72）：一条共享状态，供 GET /api/local/fork-progress 读。
//
// 为什么不做成流：派生是一个阻塞动作，前端要看到「拷到第几个文件」只能靠另一个读接口，
// 而它读的就是这里。拷完把 done 置真、active 置假；失败把 error 写上。
//
// 只记计数，不记路径：路径会泄漏主机目录结构，回执与界面都用不到。

///|
pub(all) struct ForkProgress {
  mut active : Bool
  /// 这一趟派生的是哪一只（回执用；空串 = 没有在跑）
  mut profile : String
  mut files : Int32
  mut total : Int32
  mut done : Bool
  mut error : String
}

///|
let fork_progress : Ref[ForkProgress] = {
  val: {
    active: false,
    profile: "",
    files: 0,
    total: 0,
    done: true,
    error: "",
  },
}

///|
pub fn fork_progress_start(profile : String, total : Int32) -> Unit {
  fork_progress.val = {
    active: true,
    profile,
    files: 0,
    total,
    done: false,
    error: "",
  }
}

///|
pub fn fork_progress_step(files : Int32) -> Unit {
  let current = fork_progress.val
  fork_progress.val = { ..current, files, }
}

///|
pub fn fork_progress_finish(error : String) -> Unit {
  let current = fork_progress.val
  fork_progress.val = { ..current, active: false, done: true, error, }
}

///|
pub fn fork_progress_json() -> @json.JsonVal {
  let p = fork_progress.val
  @json.JObj([
    ("active", @json.JBool(p.active)),
    ("profile", @json.JStr(p.profile)),
    ("files", @json.JNum(p.files.to_double())),
    ("total", @json.JNum(p.total.to_double())),
    ("done", @json.JBool(p.done)),
    ("error", @json.JStr(p.error)),
  ])
}

///|
/// GET /api/local/fork-progress —— 派生拷贝进度（只读）。
pub async fn handle_fork_progress(
  req : @moonback.Request,
  res : @moonback.Responder,
  read_at : String,
) -> Unit {
  let verb = @localapi.method_name(req.meth)
  if verb != "GET" {
    send_method_not_allowed(res, "GET", verb, read_at)
    return
  }
  @localapi.send_ok(res, fork_progress_json(), read_at)
}
