// 维护作业「升级 dsh」的状态机与动作（design/ops-maintenance-jobs.md §4）。
//
// 一条作业 = 七个按顺序做的步骤，每步都要留下结论（规格第二版：验收由用户自己试）：
//   1 lock     锁定当前版本：把现在生效的那份 dsh 记成回退锚。**不写 dsh-pin.json** ——
//              它说的是「退回哪里」，不是「现在用哪一版」。
//   2 install  安装新版本：pnpm add -g @deepseek-ai/dsh@<版本>。先预演（回确切命令），
//              confirm=true 才执行。装完不会自动切过去。
//   3 trial    **只负责把新版起成一只真用的实例**：作业里那份新版包目录 + 一份一次性 home
//              （homes root 下的 trial-<作业 id 末 6 位>，铺法照 design/deep-home-isolation.md
//              第 2 节）+ 用户选的 profile + 空闲端口，等监听 + 签名通过，把 pid / port / url /
//              home 记进 trial。这一步不判定好坏 —— 好不好用由用户说了算。
//   4 verdict  用户来试：good / bad / later 三条分支。good 停掉试跑实例、step=commit
//              （**先不写 dsh-pin**）；bad 停掉试跑实例、把 dsh-pin.json 恢复成开工前的样子、
//              step=rollback；later 什么都不动，留在 verdict 步等用户。
//   5 commit   切到新版本：verdict=good 才允许，改 dsh-pin.json 指到新版（复用 pin-dsh 的写法）。
//   6 rollback 回滚已经发生（由 verdict=bad 那一步做完并留证）：旧版还在用，新版留着没删。
//   7 cleanup  清理旧版本：先预演（旧包目录 / 体积 / 有没有实例在跑），confirm=DELETE 才删，
//              而且只删回滚锚记的那一份包目录。
//
// **试跑实例不被作业自动收掉**：用户可能要试一阵。verdict 步时它还在跑，页面要显示它的地址，
// 并防止再起第二只；要收掉它只能靠 job-trial-stop 或 job-abort（§4）。
//
// 五档状态是硬口径（§3）：running / passed / failed / skipped / not-run。
// 这里**没有**「默认通过」：没跑到的步骤一直是 not-run，读不出来的状态在界面上是「没验到」。
//
// 所有写动作都走 POST /api/local/action（守卫在 action.mbt 那一层，照旧）。
// 落盘走 @store.save_job（原子写）；重启后从文件恢复，不靠内存。

///|
/// 作业种类：升级 dsh。
pub let job_kind_upgrade : String = "upgrade-dsh"

///|
/// 作业标题（进文件、进界面卡片）。
let job_title_upgrade : String = "升级 dsh"

///|
/// 包目录在路径里的那一段（与 runtime.mbt 同一个判据）。
let package_marker : String = "/node_modules/@deepseek-ai/dsh"

///|
/// pnpm 安装的超时上限（10 分钟）。网络慢的时候 pnpm 会慢慢来，但不会无限等：
/// 一个卡住的安装不该把整条动作请求挂死。
let install_timeout_ms : Int = 600000

///|
/// verdict 的三个合法取值。表外的值一律 bad-params —— 写进一份读不出来的结论，
/// 比拒掉一个拼错的词难查得多。
pub let verdict_values : Array[String] = ["good", "bad", "later"]

///|
/// 一条动作的结果：作业本身 + 这一步额外的字段 + 一句人话（进悬停）。
///
/// 为什么把字段摊在这里而不是在 action.mbt 里按动作名拼：状态机在哪个包里，
/// 「这一步到底看到了什么」就归哪个包说；action.mbt 只负责套信封。
pub(all) struct JobOutcome {
  job : @store.Job
  fields : Array[(String, @json.JsonVal)]
  note : String
}

///|
/// 结果包成回执：{ action, outcome: { job, ...fields }, note }。
pub fn job_outcome_json(action : String, o : JobOutcome) -> @json.JsonVal {
  let fields : Array[(String, @json.JsonVal)] = [("job", @store.job_list_json(o.job))]
  for pair in o.fields {
    fields.push(pair)
  }
  @json.JObj([
    ("action", @json.JStr(action)),
    ("outcome", @json.JObj(fields)),
    ("note", @json.JStr(o.note)),
  ])
}

///|
/// 当前时刻（ISO8601，UTC）。
fn now_iso() -> String {
  @json.iso_from_epoch_ms(@async.now())
}

///|
/// 作业 id 里的那一段：epoch 秒。
///
/// **必须先做 64 位除法再 to_int**：now() 是毫秒级的 Int64（约 1.7e12），
/// 先塞进 Int 会溢出成一个两千年前的数（实测第一次就拿到了 1304835）。
fn epoch_seconds() -> String {
  ((@async.now() / 1000L).to_int()).to_string()
}

///|
/// 取一条作业；读不出来 / 不存在都按动作错误报回去（原因不吞）。
async fn require_job(id_in : String) -> @store.Job raise ActionError {
  let id = @json.trim_both(id_in)
  if !@store.job_id_valid(id) {
    fail("not-found", "作业 id 认不出来：" + id)
    abort("unreachable: fail 一定抛错")
  }
  let (job, reason) = @store.load_job(id)
  match job {
    Some(j) => j
    None => {
      match reason {
        Some(why) => fail("io-error", "作业记录读不出来（" + id + "）：" + why)
        None => fail("not-found", "没有这条作业：" + id)
      }
      abort("unreachable: fail 一定抛错")
    }
  }
}

// ── 在跑实例的读数（清理预演与 profile 推导都要用） ─────────────

///|
/// 一只在跑的实例：进程号 / 端口 / profile / home / 包目录 / 版本。
priv struct RunningSnapshot {
  pid : Int
  port : Int?
  profile : String
  home : String
  dir : String
  version : String
}

///|
/// 从 argv 里切出 @deepseek-ai/dsh 包目录（与 runtime 那边同一套判据，这里留一份）。
fn package_dir_in(argv : String) -> String? {
  match @json.index_of(argv, package_marker) {
    Some(at) => {
      let mut start = at
      while start > 0 {
        let ch = argv.unsafe_get(start - 1).unsafe_to_char()
        let stop = ch == ' ' ||
          ch == '\t' ||
          ch == '\n' ||
          ch == '\r' ||
          ch == '"' ||
          ch == '\'' ||
          ch == '=' ||
          ch == '(' ||
          ch == '\\'
        if stop {
          break
        }
        start = start - 1
      }
      let prefix = @json.slice(argv, start, at)
      if prefix.has_prefix("/") {
        Some(prefix + package_marker)
      } else {
        None
      }
    }
    None => None
  }
}

///|
/// 一份包装目录的真实路径（读不出来给原串）。
async fn job_real_dir(path : String) -> String noraise {
  match @json.real_path(path) {
    Some(p) => p
    None => path
  }
}

///|
/// 一个包目录里 package.json 的版本（读不到给 None）。试跑之前拿它核对
/// 「要试的确实是作业里写的那一版」——目录被换过的时候，不核对就会拿另一版去验收。
async fn package_version_of(dir : String) -> String? noraise {
  let file = @json.join_path(dir, "package.json")
  let text = match @json.read_text_file(file) {
    Ok(t) => t
    Err(_) => return None
  }
  let json = match @json.json_parse(text) {
    Some(j) => j
    None => return None
  }
  match @json.json_field(json, "version") {
    Some(v) => @json.json_string(v)
    None => None
  }
}

///|
/// 候选里版本等于 version 的那一份的目录（没有给 None）。
async fn find_version_dir(version : String) -> String? noraise {
  let candidates = @runtime.installed_dsh_candidates()
  for c in candidates {
    if c.version == version {
      return Some(c.dir)
    }
  }
  None
}

///|
/// 在跑的实例快照（只认 argv 里解得出包目录的那些 —— 版本 / 包目录都从读数来，不猜）。
async fn running_snapshots() -> Array[RunningSnapshot] noraise {
  let candidates = @runtime.installed_dsh_candidates()
  let out : Array[RunningSnapshot] = []
  let report = @processes.read_processes()
  for item in report.instances {
    match package_dir_in(item.exe_path) {
      Some(dir) => {
        let real = job_real_dir(dir)
        let mut version = ""
        for c in candidates {
          if job_real_dir(c.dir) == real {
            version = c.version
          }
        }
        out.push({
          pid: item.pid,
          port: item.port,
          profile: match item.profile {
            Some(p) => p
            None => ""
          },
          home: match item.dsh_home {
            Some(h) => h
            None => ""
          },
          dir,
          version,
        })
      }
      None => ()
    }
  }
  out
}

///|
/// 有没有在跑的实例用的是这个包目录（真实路径比）。
async fn running_users_of(dir : String) -> Array[RunningSnapshot] noraise {
  let real = job_real_dir(dir)
  let mine : Array[RunningSnapshot] = []
  for item in running_snapshots() {
    if job_real_dir(item.dir) == real {
      mine.push(item)
    }
  }
  mine
}

///|
/// 在跑实例在悬停里的形状。
fn running_json(list : Array[RunningSnapshot]) -> @json.JsonVal {
  let items : Array[@json.JsonVal] = []
  for item in list {
    items.push(
      @json.JObj([
        ("pid", @json.jint(item.pid)),
        ("port", @json.int_or_null(item.port)),
        ("profile", @json.JStr(item.profile)),
        ("home", @json.JStr(item.home)),
        ("dir", @json.JStr(item.dir)),
        ("version", @json.JStr(item.version)),
      ]),
    )
  }
  @json.JArr(items)
}

// ── 进程：跑命令、拼输出尾部 ──────────────────────────────────

///|
/// 跑一条命令，三个流分开收：stdout / stderr 都要（--dump-config 的解析错误走 stderr）。
/// 有超时上限：卡住的命令不能把动作请求挂死。
async fn run_capture(
  argv : Array[String],
  extra_env : Map[String, String],
  cwd : String,
  timeout_ms : Int,
) -> Result[(Int, String, String), String] noraise {
  if argv.length() == 0 {
    return Err("命令是空的")
  }
  let prog = argv[0]
  let args = argv[1:].to_owned()
  let attempt : async () -> (Int, String, String) raise = async fn () {
    let input = @process.redirect_from_file("/dev/null")
    let (code, stdout, stderr) = @process.collect_output(
      prog,
      args,
      extra_env~,
      inherit_env=true,
      stdin=input,
      cwd~,
    )
    (code, stdout.text(), stderr.text())
  }
  let result = try {
    @async.with_timeout_opt(timeout_ms, attempt)
  } catch {
    err => return Err(err.to_string())
  }
  match result {
    Some(triple) => Ok(triple)
    None => Err("命令超过 " + (timeout_ms / 1000).to_string() + " 秒还没结束，已放弃等待")
  }
}

///|
/// 取文本末尾若干非空行（失败信息只带证据，不把整份日志丢出去）。
fn job_tail_lines(text : String, lines : Int) -> String {
  let kept : Array[String] = []
  for line in text.split("\n") {
    let trimmed = @json.trim_both(@json.owned(line))
    if trimmed != "" {
      kept.push(trimmed)
    }
  }
  let start = if kept.length() > lines { kept.length() - lines } else { 0 }
  let tail = kept[start:].to_owned()
  let joined = tail.join(" / ")
  @json.utf8_prefix(joined, 2000)
}


///|
/// 试跑实例现在跑的是不是这条作业起的那一只（进程表读得到 argv 时对上号）。
///
/// 返回 None = 没发现对不上（进程表里没这个 pid，或者对得上）；
/// Some(原因) = 对不上。为什么要认这一道：pid 会被系统回收再利用，
/// 真要收的是一只不属于这条作业的进程，那是这个控制台最不该做的事 ——
/// 宁可留下一只收不掉的实例并如实说清，也不拿 pid 数字直接下手。
async fn trial_owner_mismatch(job : @store.Job, pid : Int) -> String? noraise {
  let target_dir = match job.target {
    Some(t) => @json.trim_both(t.dir)
    None => ""
  }
  let report = @processes.read_processes()
  for item in report.instances {
    if item.pid != pid {
      continue
    }
    let dir_ok = if target_dir == "" {
      false
    } else {
      match package_dir_in(item.exe_path) {
        Some(dir) => job_real_dir(dir) == job_real_dir(target_dir)
        None => false
      }
    }
    let profile_ok = match item.profile {
      Some(p) => p == job.profile
      None => false
    }
    if !dir_ok && !profile_ok {
      return Some(
        "PID " + pid.to_string() + " 现在跑的不是这条作业的试跑实例（进程表里它的 profile 与包目录都对不上），没有动它",
      )
    }
  }
  None
}

///|
/// 收尾时删掉试跑那份一次性 home（作业里记了才删）。返回一句人话（进正文 / 证据）。
///
/// 只删作业记录里的那一条路径，还得先过 homes.mbt 的核对（<homes root>/trial-…）：
/// 记录里的人为改动、旧版本留下的空值，都在那一道挡掉，不拿它去删别的东西。
async fn remove_trial_home_of(job : @store.Job) -> String noraise {
  let t = match job.trial {
    Some(t) => t
    None => return ""
  }
  if @json.trim_both(t.home) == "" {
    // 第三版之前的记录：那时试跑借的是真实 home，没有一次性 home 可删
    return "这条作业没有记一次性 home（旧记录），没有要删的临时目录"
  }
  match @profiles.remove_trial_home(t.home) {
    Ok(note) => note
    Err((_code, message)) => "一次性 home 没删成：" + message
  }
}

///|
/// 收掉试跑实例：SIGTERM -> 宽限 -> SIGKILL（沿用 stop-instance 的口径），再从运行登记里摘掉；
/// 然后删掉这份试跑用的一次性 home（design/deep-home-isolation.md 第 6 节）。
/// 返回一句人话（进正文 / 证据）。
///
/// **只有四个地方会走到它**：job-verdict（good / bad）、job-trial-stop、job-abort。
/// 试跑实例不会被作业自动收掉 —— 用户可能要试一阵，收到 verdict 步之后还留着才合理；
/// 而一旦收掉，这次试跑用的 home 也就没有留着的理由了，一起删。
async fn stop_trial(job : @store.Job) -> String noraise {
  let t = match job.trial {
    Some(t) => t
    None => return "作业里没有试跑实例的记录"
  }
  let stop_note = if !process_alive(t.pid) {
    "试跑实例（PID " + t.pid.to_string() + "）已经不在了"
  } else {
    match trial_owner_mismatch(job, t.pid) {
      Some(reason) => reason
      None => {
        let settings = @store.load_settings().values
        let attempt = try {
          Ok(stop_pid(t.pid, settings.process_stop_grace_ms))
        } catch {
          // 停不成的原因只进正文；错误码在这里没有用处
          ActionError(message~, ..) => Err(message)
        }
        match attempt {
          Err(message) => "试跑实例没停成：" + message
          Ok(stopped) => {
            let _ = @store.remove_by_pid(t.pid)
            t.stopped_at = now_iso()
            "试跑实例已收掉（PID " + stopped.pid.to_string() + "，" + stopped.signal + "）"
          }
        }
      }
    }
  }
  // 实例还活着就不动它脚下的 home：删一份正被用着的 home 比留着它糟得多
  if process_alive(t.pid) {
    return stop_note + "；一次性 home 先留着：这只实例还在跑（PID " + t.pid.to_string() + "）"
  }
  let home_note = remove_trial_home_of(job)
  if home_note == "" {
    stop_note
  } else {
    stop_note + "；" + home_note
  }
}

///|
/// 开工那一刻 dsh-pin.json 的样子。
///
/// 文件在不在、在的话里面是那一条，都照原样记下来：回滚要按它恢复，
/// 「原来没指定」与「原来指定的是那一份」不能都办成同一件事。
async fn capture_pin_before() -> @store.JobPinBefore noraise {
  let paths = @store.state_paths()
  let existed = @json.exists(paths.dsh_pin)
  match @store.load_dsh_pin() {
    Some(pin) => {
      existed: true,
      dir: pin.dir,
      version: pin.version,
      pinned_at: pin.pinned_at,
    }
    None => { existed, dir: "", version: "", pinned_at: "" }
  }
}

///|
/// dsh-pin.json 的原文（读不到给一句说明）。回执与证据里拿它做「前 / 后」对照 ——
/// 「恢复成开工前」这句话，只有把前后两份内容摆出来才验得了。
async fn pin_file_text() -> String noraise {
  let paths = @store.state_paths()
  if !@json.exists(paths.dsh_pin) {
    return "（没有这份文件）"
  }
  match @json.read_text_file(paths.dsh_pin) {
    Ok(t) => @json.trim_both(t)
    Err(e) => "（读不出来：" + e + "）"
  }
}

///|
/// 把 dsh-pin.json 恢复成开工前的样子。只做这一件事，不碰任何包目录。
async fn restore_pin_before(before : @store.JobPinBefore) -> Result[String, String] noraise {
  if !before.existed {
    match @store.clear_dsh_pin() {
      Ok(_) => Ok("开工前没有这份记录，已经删掉")
      Err(e) => Err("开工前没有这份记录，但删不掉：" + e)
    }
  } else if before.dir == "" || before.version == "" {
    Err(
      "开工前那份 dsh-pin.json 读不出来（dir / version 缺失），没法按原样恢复；文件没有动",
    )
  } else {
    let pin : @store.DshPin = {
      dir: before.dir,
      version: before.version,
      pinned_at: if before.pinned_at == "" { now_iso() } else { before.pinned_at },
    }
    match @store.save_dsh_pin(pin) {
      Ok(_) => Ok("已按开工前的样子写回")
      Err(e) => Err("写不回去：" + e)
    }
  }
}

///|
/// 试跑这一步没做成：把 trial 记成 failed（原因与证据照实留着），写盘，把作业交回去。
/// 不是抛错 —— 失败也是这一步的结论，页面上要看得见。
async fn trial_failed(
  job : @store.Job,
  note : String,
  evidence : Array[(String, String)],
  now : String,
) -> JobOutcome raise ActionError {
  @store.mark_step(job, "trial", "failed", note, evidence, now)
  match @store.save_job(job) {
    Ok(_) => ()
    Err(e) => fail("io-error", "试跑没做成，作业也没能写进磁盘：" + e)
  }
  { job, fields: [("started", @json.JBool(false))], note }
}

// ── 1. job-start ─────────────────────────────────────────────

///|
/// 建一条作业：第 1 步 lock 立刻做（记回滚锚），然后停在 install。
///
/// 目标版本由前端给，留空就是留空 —— 后端不替你挑一个版本装上（§4）。
/// profile 必填：试跑**从这份 DSH_HOME 里的这只 profile 复制配置**到一次性 home
/// （design/deep-home-isolation.md 第 6 节），所以开工时就得选定，并且这一份在这里就核对
/// （不是到试跑那一步才发现不存在）。
///
/// 同时把开工前的 dsh-pin.json 记进作业（pinBefore）：bad 分支能不能真恢复，全看它。
pub async fn job_start(
  kind_in : String,
  version : String?,
  profile_in : String?,
) -> JobOutcome raise ActionError {
  let kind = @json.trim_both(kind_in)
  if kind != job_kind_upgrade {
    fail("bad-params", "这一版只认识一种作业：" + job_kind_upgrade + "，收到 " + kind)
  }
  let target_version = match version {
    Some(v) => @json.trim_both(v)
    None => ""
  }
  let profile = match profile_in {
    Some(v) => @json.trim_both(v)
    None => ""
  }
  if profile == "" {
    fail("bad-params", "要选一只试跑用的 profile：试跑要从这份 home 里的那只 profile 复制一份配置")
  }
  validate_profile_name(profile)
  let (home, home_source) = @runtime.resolve_dsh_home()
  let profile_dir = @json.join_all([home, "profiles", profile])
  if !@json.is_dir(profile_dir) {
    fail(
      "not-found",
      "这份 DSH_HOME 里没有 profile「" + profile + "」：" + profile_dir,
    )
  }
  let (jobs, _bad, _notes) = @store.load_jobs()
  match @store.unfinished_of_kind(jobs, kind) {
    Some(existing) =>
      fail(
        "job-exists",
        "同一种作业还有一条没做完（" + existing.id + "，现在在 " + existing.step +
        " 这一步）；先把它做完或中止，再开新的",
      )
    None => ()
  }
  let selection = match @runtime.resolve_dsh_selection() {
    Some(sel) => sel
    None => {
      fail(
        "bad-params",
        "这台机器上找不到一份可用的 dsh，没法记录回退锚；先装一份 dsh 再来开作业",
      )
      abort("unreachable: fail 一定抛错")
    }
  }
  let now = now_iso()
  let id = kind + "-" + epoch_seconds()
  if @json.exists(@store.job_path(id)) {
    fail("job-exists", "作业文件已经存在：" + id + "（同一秒内重复开工）；等一秒再点一次")
  }
  let pin_before = capture_pin_before()
  let pin_text = pin_file_text()
  let anchor : @store.JobAnchor = { dir: selection.pkg.dir, version: selection.pkg.version }
  let job = @store.new_job(
    id,
    kind,
    job_title_upgrade,
    now,
    anchor,
    target_version,
    profile,
    pin_before,
  )
  @store.mark_step(
    job,
    "lock",
    "passed",
    "开工时生效的 dsh 是 " + selection.pkg.version + "，已记为回退点",
    [
      ("version", selection.pkg.version),
      ("dir", selection.pkg.dir),
      ("pinState", selection.pin_state),
      ("profile", profile),
      ("profileDir", profile_dir),
      ("home", home),
      ("homeSource", home_source),
      ("pinBeforeExisted", if pin_before.existed { "true" } else { "false" }),
      ("pinBeforeDir", pin_before.dir),
      ("pinBeforeVersion", pin_before.version),
      ("pinBeforeContent", pin_text),
      ("pinnedAt", now),
    ],
    now,
  )
  @store.advance_to(job, "install", now)
  match @store.save_job(job) {
    Ok(_) => ()
    Err(e) => {
      fail("io-error", "作业没能写进 " + @store.job_path(id) + "：" + e)
      abort("unreachable: fail 一定抛错")
    }
  }
  let pin_state_text = if pin_before.existed {
    if pin_before.version == "" {
      "开工前的 dsh-pin.json 读不出来，已经原样留在作业里"
    } else {
      "开工前指定的是 dsh " + pin_before.version + "（回滚就退回它）"
    }
  } else {
    "开工前没有指定过版本（回滚就是把指定删掉）"
  }
  let note = "回退锚：dsh " + selection.pkg.version + "。试跑用 profile " + profile +
    "。" + pin_state_text + "。这一步只记在作业里，没有动 dsh-pin.json。" +
    (if target_version == "" {
      "没有给目标版本 —— 安装那一步会拦住，不会替你挑版本。"
    } else if target_version == selection.pkg.version {
      "目标版本与现在的版本相同：装完会覆盖同一份安装。"
    } else {
      "目标版本：" + target_version + "。"
    })
  {
    job,
    fields: [
      ("anchorVersion", @json.JStr(selection.pkg.version)),
      ("anchorDir", @json.JStr(selection.pkg.dir)),
      ("targetVersion", @json.JStr(target_version)),
      ("profile", @json.JStr(profile)),
      ("pinState", @json.JStr(selection.pin_state)),
      (
        "pinBefore",
        @json.JObj([
          ("existed", @json.JBool(pin_before.existed)),
          ("dir", @json.JStr(pin_before.dir)),
          ("version", @json.JStr(pin_before.version)),
          ("content", @json.JStr(pin_text)),
        ]),
      ),
      ("jobPath", @json.JStr(@store.job_path(id))),
    ],
    note,
  }
}

// ── 2. job-install ───────────────────────────────────────────

///|
/// 安装新版本。confirm=false 只预演（回确切命令、会不会动到在跑的那份），
/// confirm=true 才真的执行 pnpm add -g。
///
/// 「会不会动到正在跑的那份」的口径：在跑实例各自跑在自己的包目录上（argv 里写死），
/// pnpm 装的是全局根里的另一份 —— **除非目标版本与某只在跑实例的版本相同**，
/// 那时 pnpm 会把同一份包的目录重装一遍，正在跑的那只读的文件就换了。
/// 这一条按事实说，不替用户判断安全不安全。
pub async fn job_install(id : String, confirm : Bool) -> JobOutcome raise ActionError {
  let job = require_job(id)
  if job.step != "install" {
    fail(
      "conflict",
      "这条作业现在不在「安装新版本」这一步（当前：" + job.step + "）",
    )
  }
  let version = match job.target {
    Some(t) => @json.trim_both(t.version)
    None => ""
  }
  if version == "" {
    fail("bad-params", "这条作业没有目标版本；到「维护」页重新开一条并填上要装的版本")
  }
  let command : Array[String] = ["pnpm", "add", "-g", "@deepseek-ai/dsh@" + version]
  let pnpm = @json.find_in_path("pnpm")
  let snapshots = running_snapshots()
  let touched : Array[RunningSnapshot] = []
  for item in snapshots {
    if item.version == version {
      touched.push(item)
    }
  }
  let touch_text = if touched.length() == 0 {
    "在跑的实例（" + snapshots.length().to_string() + " 只）各自跑在自己那份包目录上，这一装不动它们"
  } else {
    "有 " + touched.length().to_string() + " 只在跑的实例用的就是 " + version +
    "：pnpm 会把同一份包目录重装一遍，它们读的文件会换"
  }
  let running_field = running_json(snapshots)
  if !confirm {
    let note = "预演：将要执行 " + command.join(" ") + "（在 " + @json.home_dir() + " 下跑）。" +
      touch_text + "。这一步会真的装东西，装完不会自动切过去。"
    return {
      job,
      fields: [
        ("executed", @json.JBool(false)),
        ("command", @json.jstr_array(command)),
        ("pnpmPath", @json.str_or_null(pnpm)),
        ("pnpmFound", @json.JBool(pnpm is Some(_))),
        ("targetVersion", @json.JStr(version)),
        ("running", running_field),
        ("touchesRunning", @json.JBool(touched.length() > 0)),
      ],
      note,
    }
  }
  let pnpm_path = match pnpm {
    Some(p) => p
    None => {
      fail(
        "spawn-failed",
        "PATH 上找不到 pnpm，没法执行安装；装好 pnpm 再来，或者手动跑：" + command.join(" "),
      )
      abort("unreachable: fail 一定抛错")
    }
  }
  let argv : Array[String] = [pnpm_path, "add", "-g", "@deepseek-ai/dsh@" + version]
  let started = now_iso()
  let outcome = run_capture(argv, Map([]), @json.home_dir(), install_timeout_ms)
  let now = now_iso()
  match outcome {
    Err(reason) => {
      job.commands.push({ at: started, argv, result: "没跑完：" + reason })
      @store.mark_step(
        job,
        "install",
        "failed",
        "安装命令没跑完（原因在证据里）",
        [("exitCode", ""), ("argv", argv.join(" ")), ("error", reason)],
        now,
      )
      match @store.save_job(job) {
        Ok(_) => ()
        Err(e) => fail("io-error", e)
      }
      {
        job,
        fields: [
          ("executed", @json.JBool(true)),
          ("command", @json.jstr_array(argv)),
          ("exitCode", @json.JNull),
          ("targetVersion", @json.JStr(version)),
          ("running", running_field),
        ],
        note: "安装命令没跑完：" + reason,
      }
    }
    Ok(triple) => {
      let (code, stdout, stderr) = triple
      let tail = job_tail_lines(stdout + "\n" + stderr, 12)
      job.commands.push({
        at: started,
        argv,
        result: "exit=" + code.to_string() + (if tail == "" { "" } else { "；" + tail }),
      })
      let target_dir = find_version_dir(version)
      match target_dir {
        Some(dir) => job.target = Some({ version, dir })
        None => ()
      }
      let dir_text = match target_dir {
        Some(dir) => "新版包目录：" + dir
        None => "装完之后没在这台机器上扫到 " + version + " 这一份（试跑那一步会再找一次）"
      }
      if code == 0 {
        @store.mark_step(
          job,
          "install",
          "passed",
          "安装命令跑完了（退出码 0）",
          [
            ("exitCode", code.to_string()),
            ("argv", argv.join(" ")),
            ("targetVersion", version),
            ("targetDir", match target_dir {
              Some(dir) => dir
              None => ""
            }),
            ("outputTail", tail),
          ],
          now,
        )
        @store.advance_to(job, "trial", now)
      } else {
        @store.mark_step(
          job,
          "install",
          "failed",
          "安装命令失败（退出码 " + code.to_string() + "）",
          [
            ("exitCode", code.to_string()),
            ("argv", argv.join(" ")),
            ("targetVersion", version),
            ("outputTail", tail),
          ],
          now,
        )
      }
      match @store.save_job(job) {
        Ok(_) => ()
        Err(e) => {
          fail("io-error", "安装跑完了，但作业没能写进磁盘：" + e)
          abort("unreachable: fail 一定抛错")
        }
      }
      {
        job,
        fields: [
          ("executed", @json.JBool(true)),
          ("command", @json.jstr_array(argv)),
          ("exitCode", @json.jint(code)),
          ("targetVersion", @json.JStr(version)),
          ("targetDir", @json.str_or_null(target_dir)),
          ("outputTail", @json.JStr(tail)),
          ("running", running_field),
        ],
        note: (if code == 0 {
          "安装命令退出码 0。"
        } else {
          "安装命令退出码 " + code.to_string() + "。"
        }) + dir_text + (if tail == "" { "" } else { "输出尾部：" + tail }),
      }
    }
  }
}

// ── 3. job-trial ─────────────────────────────────────────────

///|
/// 把新版起成一只**真用的实例**：作业 target.dir 那份 dsh + 一份**一次性 home** +
/// 作业里选的 profile + 空闲端口。等到监听 + 签名通过，把 pid / port / url / home 记进 trial，
/// step -> verdict。**这一步不判定好坏** —— 好不好用由用户说了算（verdict 步）。
///
/// 一次性 home（design/deep-home-isolation.md 第 6 节）：在 homes root 下建
/// trial-<作业 id 末 6 位>，复制选中 profile 的配置、软链 node_modules 与 skills、
/// 凭证只写路径。用户平时那份 ~/.dsh 与已隔离的其它 home 一个字节都不动；
/// 收尾时（verdict 的 good / bad、trial-stop、abort）整份删掉。
///
/// 起实例走 start_instance 那条路（同样的端口挑选、同样的 bind 归因、同样的运行登记），
/// 只是把「用哪一份包目录」与「用哪一份 home」当参数传进去：不拿 dsh-pin.json 当临时覆盖，
/// 否则用户下次起实例会莫名其妙用上试跑的那一版。
///
/// 起好之后**不自动收掉它**：用户可能要试一阵。收掉它只有 job-trial-stop / job-abort
/// （以及 verdict 的 good / bad）这几条路，它们同时删掉这份一次性 home。
pub async fn job_trial(id : String) -> JobOutcome raise ActionError {
  let job = require_job(id)
  if job.step != "trial" {
    fail(
      "conflict",
      "这条作业现在不在「把新版本跑起来」这一步（当前：" + job.step + "）",
    )
  }
  // 上一只试跑实例还活着：不许起第二只（§4）。判据是这一刻的进程表，不是作业里的记录。
  match job.trial {
    Some(t) =>
      if process_alive(t.pid) {
        fail(
          "conflict",
          "试跑实例还在跑（PID " + t.pid.to_string() + "，端口 " + t.port.to_string() +
          "）；先在页面上「停掉试跑实例」，或者直接用那只",
        )
      }
    None => ()
  }
  let now = now_iso()
  let version = match job.target {
    Some(t) => @json.trim_both(t.version)
    None => ""
  }
  if version == "" {
    return trial_failed(
      job,
      "作业里没有目标版本，没法把新版跑起来",
      [("reason", "target.version 是空的")],
      now,
    )
  }
  let target_dir = match job.target {
    Some(t) if @json.trim_both(t.dir) != "" && @json.is_dir(t.dir) => @json.trim_both(t.dir)
    _ =>
      match find_version_dir(version) {
        Some(dir) => {
          job.target = Some({ version, dir })
          dir
        }
        None =>
          return trial_failed(
            job,
            "这台机器上找不到 " + version + " 这一份 dsh（安装那一步可能没真的装上）",
            [("targetVersion", version), ("reason", "没扫到这一版")],
            now,
          )
      }
  }
  // 目录里那一份到底是不是作业里写的那一版：目录被换过的时候，试跑通过也说明不了什么
  match package_version_of(target_dir) {
    Some(actual) =>
      if actual != version {
        return trial_failed(
          job,
          "目标包目录里的版本是 " + actual + "，不是作业里的 " + version,
          [("expectedVersion", version), ("actualVersion", actual), ("targetDir", target_dir)],
          now,
        )
      }
    None =>
      return trial_failed(
        job,
        "目标包目录里读不到版本，没法确认试的是哪一版",
        [("expectedVersion", version), ("targetDir", target_dir)],
        now,
      )
  }
  let script = @json.join_all([target_dir, "lib", "bin.js"])
  if !@json.exists(script) {
    return trial_failed(
      job,
      "新版目录里没有入口文件，没法把新版跑起来",
      [("targetDir", target_dir), ("reason", "入口不存在")],
      now,
    )
  }
  let profile = @json.trim_both(job.profile)
  if profile == "" {
    fail("bad-params", "这条作业没记试跑用的 profile（开工时就该选好）；到「维护」页重开一条")
  }
  validate_profile_name(profile)
  let (source_home, source_home_source) = @runtime.resolve_dsh_home()
  let source_profile_dir = @json.join_all([source_home, "profiles", profile])
  if !@json.is_dir(source_profile_dir) {
    return trial_failed(
      job,
      "这份 DSH_HOME 里没有 profile「" + profile + "」，起不了实例",
      [
        ("profile", profile),
        ("sourceHome", source_home),
        ("sourceHomeSource", source_home_source),
        ("sourceProfileDir", source_profile_dir),
      ],
      now,
    )
  }
  let settings = @store.load_settings().values
  let port = match pick_free_port(settings.instance_base_port) {
    Some(p) => p
    None => {
      fail(
        "conflict",
        "从 " + settings.instance_base_port.to_string() + " 起找不到空闲端口给试跑实例",
      )
      abort("unreachable: fail 一定抛错")
    }
  }
  // 一次性 home：建在 homes root 下（trial-<作业 id 末 6 位>），铺法照隔离 home 那一套。
  // 试跑跑在它里面，用户平时那份 home 与它的状态都不动；收尾时整份删掉。
  let trial_home = match @profiles.create_trial_home(job.id, profile) {
    Ok(home) => home
    Err((code, message)) =>
      return trial_failed(
        job,
        "没能给试跑铺一份一次性 home（原因在证据里）",
        [
          ("profile", profile),
          ("homeKind", @profiles.home_kind_trial),
          ("sourceHome", source_home),
          ("sourceProfileDir", source_profile_dir),
          ("error", message),
          ("code", code),
        ],
        now,
      )
  }
  let started = try {
    Ok(start_instance_with(profile, Some(trial_home.path), Some(port), Some(target_dir), true))
  } catch {
    ActionError(code~, message~) => Err((code, message))
  }
  match started {
    Err((code, message)) => {
      // 实例没起来：这份 home 也没有留着的理由，删掉并写进证据（删不掉也照实写）
      let teardown = match @profiles.remove_trial_home(trial_home.path) {
        Ok(note) => note
        Err((_c, why)) => "一次性 home 没删成：" + why
      }
      @store.mark_step(
        job,
        "trial",
        "failed",
        "新版没能起成实例（原因在证据里）",
        [
          ("profile", profile),
          ("homeKind", @profiles.home_kind_trial),
          ("home", trial_home.path),
          ("profileCopy", trial_home.profile_dir),
          ("homeTeardown", teardown),
          ("targetDir", target_dir),
          ("port", port.to_string()),
          ("error", message),
        ],
        now,
      )
      match @store.save_job(job) {
        Ok(_) => ()
        Err(e) => fail("io-error", e)
      }
      fail(code, message)
      abort("unreachable: fail 一定抛错")
    }
    Ok(outcome) => {
      let boot_ms = outcome.boot_ms
      job.trial = Some({
        pid: outcome.pid,
        port: outcome.port,
        url: outcome.url,
        profile,
        home: trial_home.path,
        home_kind: @profiles.home_kind_trial,
        profile_copy: trial_home.profile_dir,
        started_at: now_iso(),
        stopped_at: "",
      })
      // 证据：这次试跑用的是哪一份临时 home、从哪份 profile 复制过来的、里面是什么
      let evidence : Array[(String, String)] = [
        ("pid", outcome.pid.to_string()),
        ("port", outcome.port.to_string()),
        ("url", outcome.url),
        ("profile", profile),
        ("home", trial_home.path),
        ("homeKind", @profiles.home_kind_trial),
        ("profileCopy", trial_home.profile_dir),
        ("sourceHome", source_home),
        ("sourceHomeSource", source_home_source),
        ("sourceProfileDir", source_profile_dir),
        ("configFilesCopied", trial_home.files_copied.to_string()),
        ("nodeModulesTarget", trial_home.node_modules_target),
        ("skillsLinked", if trial_home.skills_linked { "true" } else { "false" }),
        ("credentialsPath", trial_home.credentials_path),
        ("credentialsKey", trial_home.credentials_key),
        ("targetDir", target_dir),
        ("targetVersion", version),
        ("bootMs", boot_ms.to_string()),
        ("logPath", outcome.log_path),
        ("command", outcome.command),
      ]
      if trial_home.replaced != "" {
        evidence.push(("homeReplaced", trial_home.replaced))
      }
      @store.mark_step(
        job,
        "trial",
        "passed",
        "新版本在一次性 home 里起来了（端口 " + outcome.port.to_string() + "，PID " +
        outcome.pid.to_string() + "），等你试",
        evidence,
        now,
      )
      // verdict 步：结论还没出，记 running —— 到这里写 passed 就是把「没验到」写成「通过」
      @store.mark_step(
        job,
        "verdict",
        "running",
        "等你试：好用 / 不好用 / 先放着",
        [("trialPid", outcome.pid.to_string()), ("trialPort", outcome.port.to_string())],
        now,
      )
      @store.advance_to(job, "verdict", now)
      match @store.save_job(job) {
        Ok(_) => ()
        Err(e) => {
          fail("io-error", "实例起来了，但作业没能写进磁盘：" + e)
          abort("unreachable: fail 一定抛错")
        }
      }
      {
        job,
        fields: [
          ("started", @json.JBool(true)),
          ("pid", @json.jint(outcome.pid)),
          ("port", @json.jint(outcome.port)),
          ("url", @json.JStr(outcome.url)),
          ("profile", @json.JStr(profile)),
          ("home", @json.JStr(trial_home.path)),
          ("homeKind", @json.JStr(@profiles.home_kind_trial)),
          ("profileCopy", @json.JStr(trial_home.profile_dir)),
          ("targetVersion", @json.JStr(version)),
          ("bootMs", @json.jint(boot_ms)),
          ("trialAlive", @json.JBool(true)),
        ],
        note: "新版本在一次性 home 里起来了：http://127.0.0.1:" + outcome.port.to_string() +
          "/。试跑用的是 profile " + profile + " 的一份配置拷贝，你平时那份 home 没有动。" +
          "这只实例不会被作业自动收掉；收尾（好用 / 不好用 / 停掉试跑 / 中止）时会停掉它，" +
          "并删掉 " + trial_home.path + " 这份 home。",
      }
    }
  }
}

// ── 4. job-verdict ───────────────────────────────────────────

///|
/// 用户来试。三条分支（§4）：
///   good  → 停掉试跑实例，step=commit。**先不写 dsh-pin.json** —— 切版本是 job-commit 那一下。
///   bad   → 停掉试跑实例，把 dsh-pin.json 恢复成开工前的样子，step=rollback。
///   later → 什么都不动，只记下结论，step 留在 verdict。
///
/// good / bad 都会把前后两份 pin 内容摆进证据：回滚这一步说「恢复成开工前」，
/// 只有把前后摆出来才验得了。
pub async fn job_verdict(id : String, verdict_in : String) -> JobOutcome raise ActionError {
  let job = require_job(id)
  let value = @json.trim_both(verdict_in)
  if !verdict_values.contains(value) {
    fail("bad-params", "verdict 只能是 good / bad / later，收到「" + value + "」")
  }
  if job.step != "verdict" {
    fail("conflict", "这条作业现在不在「你来试」这一步（当前：" + job.step + "）")
  }
  let now = now_iso()
  let pin_before_content = pin_file_text()
  let alive = match job.trial {
    Some(t) => process_alive(t.pid)
    None => false
  }
  let record = match value {
    "good" => "你说好用"
    "bad" => "你说不好用"
    _ => "先放着"
  }
  job.verdict = Some({ value, at: now, note: record })
  if value == "later" {
    @store.mark_step(
      job,
      "verdict",
      "running",
      "先放着：什么都不动，你想好了再说",
      [
        ("verdict", "later"),
        ("trialPid", match job.trial {
          Some(t) => t.pid.to_string()
          None => ""
        }),
        ("trialAlive", if alive { "true" } else { "false" }),
      ],
      now,
    )
    match @store.save_job(job) {
      Ok(_) => ()
      Err(e) => fail("io-error", e)
    }
    return {
      job,
      fields: [
        ("verdict", @json.JStr("later")),
        ("trialAlive", @json.JBool(alive)),
      ],
      note: "结论记下了：先放着。试跑实例没动，dsh-pin.json 也没动；" +
        "想好了再来点「好用」或「不好用」。",
    }
  }
  let stop_note = stop_trial(job)
  if value == "good" {
    @store.mark_step(
      job,
      "verdict",
      "passed",
      "你说好用；" + stop_note,
      [
        ("verdict", "good"),
        ("stop", stop_note),
        ("pinBefore", pin_before_content),
        ("pinAfter", pin_file_text()),
      ],
      now,
    )
    @store.advance_to(job, "commit", now)
    match @store.save_job(job) {
      Ok(_) => ()
      Err(e) => fail("io-error", "结论记下了，但作业没能写进磁盘：" + e)
    }
    return {
      job,
      fields: [
        ("verdict", @json.JStr("good")),
        ("trialAlive", @json.JBool(false)),
        ("stop", @json.JStr(stop_note)),
        ("pinUnchanged", @json.JBool(pin_before_content == pin_file_text())),
      ],
      note: "记下了：好用。" + stop_note + "。dsh-pin.json 还没有动 —— " +
        "切到新版本是下一步那一下。",
    }
  }
  // bad：先把试跑实例收掉，再按开工前的快照恢复 pin，最后看盘上恢复成了什么
  let restored = restore_pin_before(match job.pin_before {
    Some(p) => p
    None => { existed: false, dir: "", version: "", pinned_at: "" }
  })
  let pin_after_content = pin_file_text()
  match restored {
    Err(why) => {
      @store.mark_step(job, "verdict", "passed", "你说不好用；" + stop_note, [
        ("verdict", "bad"),
        ("stop", stop_note),
        ("pinBefore", pin_before_content),
        ("pinAfter", pin_after_content),
        ("restoreError", why),
      ], now)
      @store.mark_step(
        job,
        "rollback",
        "failed",
        "回滚没做成（原因在证据里）；作业停在「你来试」，可以再点一次「不好用，回滚」",
        [("reason", why), ("pinBefore", pin_before_content), ("pinAfter", pin_after_content)],
        now,
      )
      match @store.save_job(job) {
        Ok(_) => ()
        Err(e) => fail("io-error", e)
      }
      fail("io-error", "回滚没做成：" + why)
      abort("unreachable: fail 一定抛错")
    }
    Ok(what) => {
      @store.mark_step(job, "verdict", "passed", "你说不好用；" + stop_note, [
        ("verdict", "bad"),
        ("stop", stop_note),
        ("pinBefore", pin_before_content),
        ("pinAfter", pin_after_content),
      ], now)
      @store.mark_step(
        job,
        "rollback",
        "passed",
        "起实例用的版本已恢复成开工前那一份",
        [
          ("restore", what),
          ("pinBefore", pin_before_content),
          ("pinAfter", pin_after_content),
          ("pinPath", @store.state_paths().dsh_pin),
        ],
        now,
      )
      // 回滚之后没有「清理旧版本」可做：旧版本正是在用的那一份，新装的那份留着没删。
      // 这一步如实记成 skipped，不让它默认通过，也不让「清理」变成一个危险的默认动作。
      @store.mark_step(
        job,
        "cleanup",
        "skipped",
        "回滚之后没有要清理的东西：旧版本还在用，新装的那份留着没删",
        [("reason", "verdict=bad")],
        now,
      )
      @store.advance_to(job, "rollback", now)
      match @store.save_job(job) {
        Ok(_) => ()
        Err(e) => {
          fail("io-error", "回滚做完了，但作业没能写进磁盘：" + e)
          abort("unreachable: fail 一定抛错")
        }
      }
      {
        job,
        fields: [
          ("verdict", @json.JStr("bad")),
          ("trialAlive", @json.JBool(false)),
          ("stop", @json.JStr(stop_note)),
          ("anchorVersion", @json.JStr(match job.rollback_anchor {
            Some(a) => a.version
            None => ""
          })),
          ("restored", @json.JBool(true)),
          ("pinBefore", @json.JStr(pin_before_content)),
          ("pinAfter", @json.JStr(pin_after_content)),
        ],
        note: "回滚了：" + stop_note + "。" + what + "。",
      }
    }
  }
}

// ── 5. job-trial-stop ────────────────────────────────────────

///|
/// 用户主动收掉试跑实例：trial / verdict 步都可能要点它（试完了、要腾端口、试跑卡住了）。
/// 不推进状态机 —— 收到哪一步就是哪一步。
pub async fn job_trial_stop(id : String) -> JobOutcome raise ActionError {
  let job = require_job(id)
  if job.trial is None {
    fail("not-found", "这条作业还没有试跑实例")
  }
  if @store.job_finished(job) {
    fail("conflict", "这条作业已经结束了（" + job.step + "），没有可停的试跑实例")
  }
  let now = now_iso()
  let note = stop_trial(job)
  @store.append_evidence(job, job.step, [("trialStop", note)], now)
  match @store.save_job(job) {
    Ok(_) => ()
    Err(e) => fail("io-error", "实例收掉了，但作业没能写进磁盘：" + e)
  }
  {
    job,
    fields: [
      ("stopped", @json.JBool(true)),
      ("stop", @json.JStr(note)),
      ("trialAlive", @json.JBool(false)),
    ],
    note,
  }
}


// ── 6. job-commit ────────────────────────────────────────────

///|
/// 切到新版本：**verdict=good 且已经停在 commit 那一步**才允许。
/// 改 dsh-pin.json（复用 pin_dsh 的校验与写法），已经装好的东西一个字节都不动。
///
/// 为什么切版本单独一步、不在 verdict=good 那一下顺手做掉：用户说「好用」是结论，
/// 「现在切」是另一个动作。中间隔着两个按钮，才能把回滚点留到用户自己确认的那一刻。
pub async fn job_commit(id : String) -> JobOutcome raise ActionError {
  let job = require_job(id)
  let verdict_value = match job.verdict {
    Some(v) => v.value
    None => ""
  }
  if verdict_value != "good" || job.step != "commit" {
    fail(
      "conflict",
      "还没到「切到新版本」这一步（当前：" + job.step + "，结论：" +
      (if verdict_value == "" { "还没给" } else { verdict_value }) +
      "）；要先「好用，切到新版」把结论记下来",
    )
  }
  let target = match job.target {
    Some(t) => t
    None => {
      fail("conflict", "作业里没有目标版本，不知道切到哪一份")
      abort("unreachable: fail 一定抛错")
    }
  }
  let now = now_iso()
  if target.dir == "" || !@json.is_dir(target.dir) {
    @store.mark_step(
      job,
      "commit",
      "failed",
      "目标包目录不在了，没法切过去（路径在证据里）",
      [("targetVersion", target.version), ("targetDir", target.dir)],
      now,
    )
    match @store.save_job(job) {
      Ok(_) => ()
      Err(e) => fail("io-error", e)
    }
    return {
      job,
      fields: [("version", @json.JStr(target.version))],
      note: "目标包目录不在了（" + target.dir + "），没有动 dsh-pin.json",
    }
  }
  let pin_before_content = pin_file_text()
  let pinned = pin_dsh(target.dir)
  let pin_after_content = pin_file_text()
  let fields : Array[(String, @json.JsonVal)] = [
    ("version", @json.JStr(pinned.version)),
    ("dir", @json.JStr(pinned.dir)),
    ("pinPath", @json.JStr(pinned.pin_path)),
    ("pinBefore", @json.JStr(pin_before_content)),
    ("pinAfter", @json.JStr(pin_after_content)),
  ]
  @store.mark_step(
    job,
    "commit",
    "passed",
    "起实例用的版本已切到 " + pinned.version,
    [
      ("version", pinned.version),
      ("dir", pinned.dir),
      ("pinPath", pinned.pin_path),
      ("pinBefore", pin_before_content),
      ("pinAfter", pin_after_content),
    ],
    now,
  )
  @store.advance_to(job, "cleanup", now)
  match @store.save_job(job) {
    Ok(_) => ()
    Err(e) => {
      fail("io-error", "已经改了指派，但作业没能写进磁盘：" + e)
      abort("unreachable: fail 一定抛错")
    }
  }
  {
    job,
    fields,
    note: "已经切到 " + pinned.version + "；起实例会用这一版。旧版本留着当回滚锚，确认稳定后再清理",
  }
}

// ── 7. 清理旧版本 ────────────────────────────────────────────

///|
/// 回滚锚里那份旧包目录（没有或形状不对给 None，原因写进调用方的说明里）。
fn anchor_dir_of(job : @store.Job) -> String? {
  match job.rollback_anchor {
    Some(a) =>
      if a.dir.has_prefix("/") && a.dir.has_suffix(package_marker) {
        Some(a.dir)
      } else {
        None
      }
    None => None
  }
}

///|
/// 清理预演：列出「清理后会删掉什么」—— 旧版包目录、它占多大、正在跑的实例里有没有它。
/// 这一步不删任何东西。
pub async fn job_cleanup_preview(id : String) -> JobOutcome raise ActionError {
  let job = require_job(id)
  let anchor = match job.rollback_anchor {
    Some(a) => a
    None => {
      fail("not-found", "这条作业里没有回滚锚（旧版本包目录），没有可清理的东西")
      abort("unreachable: fail 一定抛错")
    }
  }
  let dir = match anchor_dir_of(job) {
    Some(d) => d
    None => {
      fail("conflict", "回滚锚里记的不是一份 dsh 包目录：" + anchor.dir)
      abort("unreachable: fail 一定抛错")
    }
  }
  let exists = @json.is_dir(dir)
  let (files, bytes, size_source) = if exists {
    match @fsx.measure_tree(dir) {
      Ok((count, size)) => (Some(count), Some(size), "递归数出来的")
      Err(e) => (None, None, "读不到体积：" + e)
    }
  } else {
    (Some(0), Some(0L), "这个目录现在不在了")
  }
  let users = running_users_of(dir)
  let target_dir = match job.target {
    Some(t) => t.dir
    None => ""
  }
  let same_as_target = target_dir != "" && job_real_dir(target_dir) == job_real_dir(dir)
  let safe = exists && users.length() == 0 && !same_as_target
  let reason = if !exists {
    "旧版本包目录已经不在了，清理时没有可删的"
  } else if same_as_target {
    "回滚锚与目标版本指的是同一份包目录，不许删"
  } else if users.length() > 0 {
    "还有 " + users.length().to_string() + " 只实例在跑这份 dsh，先停掉再清理"
  } else {
    "没有实例在跑这一份，可以清理"
  }
  let size_text = match bytes {
    Some(value) => value.to_string() + " 字节"
    None => "体积读不到"
  }
  {
    job,
    fields: [
      ("dir", @json.JStr(dir)),
      ("version", @json.JStr(anchor.version)),
      ("exists", @json.JBool(exists)),
      ("files", @json.int_or_null(files)),
      ("bytes", @json.int64_or_null(bytes)),
      ("sizeSource", @json.JStr(size_source)),
      ("running", running_json(users)),
      ("sameAsTarget", @json.JBool(same_as_target)),
      ("safe", @json.JBool(safe)),
    ],
    note: "清理会删掉旧版本的包目录 " + dir + "（" + size_text + "，" + reason + "）。" +
      "清理删的是旧版本的包目录，删掉不能再装回来 —— 确认之后再点执行。",
  }
}

///|
/// 清理旧版本：硬删回滚锚那一份包目录，而且只删这一份。
///
/// 必须带 params.confirm = "DELETE"（§4）；没带一律 bad-params。
/// 拒绝执行的情形：还有实例在跑这一份、锚与目标版本是同一份、目录形状不是 dsh 包目录。
/// 目录本来就不在了算目标状态已成立（passed，并在 note 里说清没有可删的）。
pub async fn job_cleanup(id : String, confirm : String?) -> JobOutcome raise ActionError {
  let given = match confirm {
    Some(v) => @json.trim_both(v)
    None => ""
  }
  if given != "DELETE" {
    fail(
      "bad-params",
      "清理旧版本要再带一次确认：params.confirm 必须是 \"DELETE\"（这一下之后包目录就没了）",
    )
  }
  let job = require_job(id)
  if job.step != "cleanup" {
    fail("conflict", "这条作业现在不在「清理旧版本」这一步（当前：" + job.step + "）")
  }
  let anchor = match job.rollback_anchor {
    Some(a) => a
    None => {
      fail("conflict", "这条作业里没有回滚锚，不知道该删哪一份")
      abort("unreachable: fail 一定抛错")
    }
  }
  let dir = match anchor_dir_of(job) {
    Some(d) => d
    None => {
      fail("conflict", "回滚锚里记的不是一份 dsh 包目录：" + anchor.dir)
      abort("unreachable: fail 一定抛错")
    }
  }
  let now = now_iso()
  let users = running_users_of(dir)
  if users.length() > 0 {
    fail(
      "conflict",
      "旧版本还有 " + users.length().to_string() + " 只实例在跑（PID " +
      users[0].pid.to_string() + "）；先停掉再清理",
    )
  }
  let target_dir = match job.target {
    Some(t) => t.dir
    None => ""
  }
  if target_dir != "" && job_real_dir(target_dir) == job_real_dir(dir) {
    fail("conflict", "回滚锚与目标版本指的是同一份包目录；删了它等于删掉刚切过去的新版")
  }
  if !@json.is_dir(dir) {
    @store.mark_step(
      job,
      "cleanup",
      "passed",
      "旧版本包目录已经不在了，这一步没有可删的",
      [("dir", dir), ("version", anchor.version), ("deleted", "false")],
      now,
    )
    @store.advance_to(job, "done", now)
    match @store.save_job(job) {
      Ok(_) => ()
      Err(e) => fail("io-error", e)
    }
    return {
      job,
      fields: [
        ("dir", @json.JStr(dir)),
        ("deleted", @json.JBool(false)),
        ("files", @json.JNull),
        ("bytes", @json.JNull),
      ],
      note: "旧版本包目录 " + dir + " 已经不在了，没有可删的；作业收尾。",
    }
  }
  let (files, bytes, size_source) = match @fsx.measure_tree(dir) {
    Ok((count, size)) => (Some(count), Some(size), "递归数出来的")
    Err(e) => (None, None, "删之前读不到体积：" + e)
  }
  let size_text = match bytes {
    Some(value) => value.to_string() + " 字节"
    None => "体积读不到"
  }
  match @fsx.remove_tree(dir) {
    Ok(_) => {
      @store.mark_step(
        job,
        "cleanup",
        "passed",
        "旧版本包目录已删掉（" + size_text + "）",
        [
          ("dir", dir),
          ("version", anchor.version),
          ("deleted", "true"),
          ("files", match files {
            Some(n) => n.to_string()
            None => ""
          }),
          ("bytes", match bytes {
            Some(n) => n.to_string()
            None => ""
          }),
          ("sizeSource", size_source),
        ],
        now,
      )
      @store.advance_to(job, "done", now)
      match @store.save_job(job) {
        Ok(_) => ()
        Err(e) => {
          fail("io-error", "目录已经删了，但作业没能写进磁盘：" + e)
          abort("unreachable: fail 一定抛错")
        }
      }
      {
        job,
        fields: [
          ("dir", @json.JStr(dir)),
          ("deleted", @json.JBool(true)),
          ("files", @json.int_or_null(files)),
          ("bytes", @json.int64_or_null(bytes)),
          ("sizeSource", @json.JStr(size_source)),
        ],
        note: "旧版本包目录已删掉：" + dir + "（" + size_text + "）。只删了这一份包目录，别处没动。",
      }
    }
    Err(e) => {
      @store.mark_step(
        job,
        "cleanup",
        "failed",
        "旧版本包目录没删掉（原因在证据里）",
        [("dir", dir), ("version", anchor.version), ("error", e)],
        now,
      )
      match @store.save_job(job) {
        Ok(_) => ()
        Err(e2) => {
          fail("io-error", "删除失败，作业记录也没写进去：" + e2)
          abort("unreachable: fail 一定抛错")
        }
      }
      fail("io-error", "旧版本包目录没删掉：" + e)
      abort("unreachable: fail 一定抛错")
    }
  }
}

// ── 中止 ─────────────────────────────────────────────────────

///|
/// 中止作业：**顺手收掉试跑实例（如果在跑）**，保留记录与已经做完的步骤。
/// 当前那一步的状态不动（它本来也没验完），只在它的 note 上写清「在这一步被中止」——
/// 把没做的事标成 passed 是这一批里最不能犯的错。
///
/// 为什么中止要收实例：作业被放弃之后，那只试跑实例就没人认领了 ——
/// 它还会一直占着端口，页面上也不再有任何一行指着它。
pub async fn job_abort(id : String) -> JobOutcome raise ActionError {
  let job = require_job(id)
  if @store.job_finished(job) {
    fail("conflict", "这条作业已经结束了（" + job.step + "），不能再中止")
  }
  let now = now_iso()
  let stop_note = stop_trial(job)
  let current = job.step
  match @store.step_of(job, current) {
    Some(step) => step.note = "作业在这一步被中止；这一步没有验完"
    None => ()
  }
  @store.append_evidence(job, current, [("trialStop", stop_note)], now)
  job.step = "aborted"
  job.updated_at = now
  match @store.save_job(job) {
    Ok(_) => ()
    Err(e) => {
      fail("io-error", "作业没能写进磁盘：" + e)
      abort("unreachable: fail 一定抛错")
    }
  }
  {
    job,
    fields: [
      ("abortedAt", @json.JStr(now)),
      ("stop", @json.JStr(stop_note)),
      ("trialAlive", @json.JBool(false)),
    ],
    note: "作业已中止；" +
      (if job.trial is Some(_) { stop_note + "。" } else { "" }) +
      "已经做完的步骤与记录都留着，没做的仍然是未开始。回滚锚没有动，dsh-pin.json 也没有动。",
  }
}
