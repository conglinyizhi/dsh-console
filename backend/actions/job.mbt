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
/// pnpm 安装的超时上限（10 分钟）。网络慢的时候 pnpm 会慢慢来，但不会无限等：
/// 一个卡住的安装不该把整条动作请求挂死。
let install_timeout_ms : Int32 = 600000

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
  let fields : Array[(String, @json.JsonVal)] = [
    ("job", @store.job_list_json(o.job)),
  ]
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
  (@async.now() / 1000L).to_int().to_string()
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
        Some(why) =>
          fail("io-error", "作业记录读不出来（" + id + "）：" + why)
        None => fail("not-found", "没有这条作业：" + id)
      }
      abort("unreachable: fail 一定抛错")
    }
  }
}

// ── 在跑实例的读数（清理预演与 profile 推导都要用） ─────────────

///|
/// 跑一条命令，三个流分开收：stdout / stderr 都要（--dump-config 的解析错误走 stderr）。
/// 有超时上限：卡住的命令不能把动作请求挂死。
async fn run_capture(
  argv : Array[String],
  extra_env : Map[String, String],
  cwd : String,
  timeout_ms : Int32,
) -> Result[(Int32, String, String), String] noraise {
  if argv.length() == 0 {
    return Err("命令是空的")
  }
  let prog = argv[0]
  let args = argv[1:].to_owned()
  let attempt : async () -> (Int32, String, String) = async fn() {
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
  let result = @async.with_timeout_opt(timeout_ms, attempt) catch {
    err => {
      // 起进程（或读它的输出）失败：原文交给审计，提示只说结论
      let e = spawn_error(err)
      note_raw(e.raw)
      return Err(e.summary)
    }
  }
  match result {
    Some(triple) => Ok(triple)
    None =>
      Err(
        "命令超过 " +
        (timeout_ms / 1000).to_string() +
        " 秒还没结束，已放弃等待",
      )
  }
}

///|
/// 取文本末尾若干非空行（失败信息只带证据，不把整份日志丢出去）。
fn job_tail_lines(text : String, lines : Int32) -> String {
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
    fail(
      "bad-params",
      "这一版只认识一种作业：" +
      job_kind_upgrade +
      "，收到 " +
      kind,
    )
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
    fail(
      "bad-params", "要选一只试跑用的 profile：试跑要从这份 home 里的那只 profile 复制一份配置",
    )
  }
  validate_profile_name(profile)
  let (home, home_source) = @runtime.resolve_dsh_home()
  let profile_dir = @json.join_all([home, "profiles", profile])
  // 第二道（§11.2）：界面已经把不可用的置灰了，后端仍要自己拒一次 ——
  // 目录读不到、配置读不到、或 bundles 里没有网页型入口的 profile，试跑注定起不来，
  // 一律 bad-params（这几种都是请求本身不该发出来，不是「哪一步跑失败了」）。
  match @profiles.trial_profile_blocker(home, profile) {
    Some(reason) => fail("bad-params", reason)
    None => ()
  }
  let (jobs, _bad, _notes) = @store.load_jobs()
  match @store.unfinished_of_kind(jobs, kind) {
    Some(existing) =>
      fail(
        "job-exists",
        "同一种作业还有一条没做完（" +
        existing.id +
        "，现在在 " +
        existing.step +
        " 这一步）；先把它做完或中止，再开新的",
      )
    None => ()
  }
  let selection = match @runtime.resolve_dsh_selection() {
    Some(sel) => sel
    None => {
      fail(
        "bad-params", "这台机器上找不到一份可用的 dsh，没法记录回退锚；先装一份 dsh 再来开作业",
      )
      abort("unreachable: fail 一定抛错")
    }
  }
  let now = now_iso()
  let id = kind + "-" + epoch_seconds()
  if @json.exists(@store.job_path(id)) {
    fail(
      "job-exists",
      "作业文件已经存在：" +
      id +
      "（同一秒内重复开工）；等一秒再点一次",
    )
  }
  let pin_before = capture_pin_before()
  let pin_text = pin_file_text()
  let anchor : @store.JobAnchor = {
    dir: selection.pkg.dir,
    version: selection.pkg.version,
  }
  let job = @store.new_job(
    id, kind, job_title_upgrade, now, anchor, target_version, profile, pin_before,
  )
  @store.mark_step(
    job,
    "lock",
    "passed",
    "开工时生效的 dsh 是 " +
    selection.pkg.version +
    "，已记为回退点",
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
      {
        note_raw(e)
        fail("io-error", "作业没能写进磁盘")
      }
      abort("unreachable: fail 一定抛错")
    }
  }
  let pin_state_text = if pin_before.existed {
    if pin_before.version == "" {
      "开工前的 dsh-pin.json 读不出来，已经原样留在作业里"
    } else {
      "开工前指定的是 dsh " +
      pin_before.version +
      "（回滚就退回它）"
    }
  } else {
    "开工前没有指定过版本（回滚就是把指定删掉）"
  }
  let note = "回退锚：dsh " +
    selection.pkg.version +
    "。试跑用 profile " +
    profile +
    "。" +
    pin_state_text +
    "。这一步只记在作业里，没有动 dsh-pin.json。" +
    (if target_version == "" {
      "没有给目标版本：安装那一步会拦住，不会替你挑版本。"
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
/// 用户主动收掉试跑实例：trial / verdict 步都可能要点它（试完了、要腾端口、试跑卡住了）。
/// 不推进状态机 —— 收到哪一步就是哪一步。
pub async fn job_trial_stop(id : String) -> JobOutcome raise ActionError {
  let job = require_job(id)
  if job.trial is None {
    fail("not-found", "这条作业还没有试跑实例")
  }
  if @store.job_finished(job) {
    fail(
      "conflict",
      "这条作业已经结束了（" +
      job.step +
      "），没有可停的试跑实例",
    )
  }
  let now = now_iso()
  let note = stop_trial(job)
  @store.append_evidence(job, job.step, [("trialStop", note)], now)
  match @store.save_job(job) {
    Ok(_) => ()
    Err(e) =>
      fail("io-error", "实例收掉了，但作业没能写进磁盘：" + e)
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
/// 中止作业：**顺手收掉试跑实例（如果在跑）**，保留记录与已经做完的步骤。
/// 当前那一步的状态不动（它本来也没验完），只在它的 note 上写清「在这一步被中止」——
/// 把没做的事标成 passed 是这一批里最不能犯的错。
///
/// 为什么中止要收实例：作业被放弃之后，那只试跑实例就没人认领了 ——
/// 它还会一直占着端口，页面上也不再有任何一行指着它。
pub async fn job_abort(id : String) -> JobOutcome raise ActionError {
  let job = require_job(id)
  if @store.job_finished(job) {
    fail(
      "conflict",
      "这条作业已经结束了（" + job.step + "），不能再中止",
    )
  }
  let now = now_iso()
  let stop_note = stop_trial(job)
  let current = job.step
  match @store.step_of(job, current) {
    Some(step) =>
      step.note = "作业在这一步被中止；这一步没有验完"
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
