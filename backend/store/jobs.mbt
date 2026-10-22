// 维护作业的落盘与读回（design/ops-maintenance-jobs.md §3）。
//
// 一条作业一份文件：$XDG_STATE_HOME/dsh-console/jobs/<jobId>.json，原子写
// （@fsx.write_text_atomic）。控制台重启之后作业还在、状态从文件恢复 —— 不靠内存。
//
// 五档状态是硬口径：running / passed / failed / skipped / not-run。
// 「没验到」永远不能用 passed 表示：这里不提供「默认通过」，读到不认识的 state 原样留着，
// 由界面显示成「没验到」——把不认识的读成通过，比读不出来还糟。
//
// 读的口径与 dshpin.mbt 一致但更严：
//   · 目录不在 / 没有文件 —— 空列表，不是错误；
//   · 单个文件读不动 / 不是 JSON / 缺 id 这类必填字段 —— **不进作业列表**，
//     而是作为一条 unreadable 记录交给界面（§3 第 2 条：那条作业显示「记录读不出来」+ 原因，不吞）。

///|
/// 作业文件的目录。
pub async fn jobs_dir() -> String noraise {
  state_paths().jobs
}

///|
/// 一条作业里的一步。
///
/// evidence 是给「这一步凭什么算通过」留证据的：键值都是字符串，
/// 命令输出、退出码、端口、包目录都往这里放，正文只写结论（§6）。
pub(all) struct JobStep {
  key : String
  mut state : String
  /// 这一步落定的时刻（UTC ISO8601）；not-run 时是空串
  mut at : String
  /// 一句人话结论（成功为什么成功、失败为什么失败）
  mut note : String
  mut evidence : Array[(String, String)]
}

///|
/// 回滚锚：开工那一刻生效的那份 dsh。**只记在作业里，不写 dsh-pin.json** ——
/// 它说的是「退回哪里」，不是「现在用哪一版」。
pub(all) struct JobAnchor {
  dir : String
  version : String
}

///|
/// 这一步要装成什么、装完落在哪个目录。
/// dir 在安装/试跑之后才填得上：开工那一刻还没装，编不出来。
pub(all) struct JobTarget {
  version : String
  mut dir : String
}

///|
/// 跑过的一条命令（安装 / 试跑）。argv 原样留着，result 是退出码与输出尾部。
pub(all) struct JobCommand {
  at : String
  argv : Array[String]
  result : String
}

///|
/// 开工那一刻 `dsh-pin.json` 的样子。回滚（verdict=bad）要按它逐字恢复：
/// 「原来没指定」与「原来指定的是那一份」是两件事，恢复时不能都办成「删掉」。
pub(all) struct JobPinBefore {
  /// 开工时那份文件在不在
  existed : Bool
  /// 文件在时里面的 dir（读不出来是空串）
  dir : String
  /// 文件在时里面的 version（读不出来是空串）
  version : String
  /// 文件在时里面的 pinnedAt，原样留着 —— 恢复时一并写回，恢复出来的内容与开工前逐字相同
  pinned_at : String
}

///|
/// 试跑实例：把新版起成一只能真用的实例给使用者试，**不判定好坏**。
///
/// pid / port / url 是「起成了」那一刻的事实；stopped_at 是「我们收过它」的时刻。
/// 它现在到底还活不活着，由读数那一侧看进程说了算（见 console_api 的 trialAlive）——
/// 这里记的任何一格都不该冒充「还活着」或「已经没了」。
pub(all) struct JobTrial {
  pid : Int32
  port : Int32
  url : String
  profile : String
  /// 试跑用的 home（design/deep-home-isolation.md 第 6 节：一次性 home）。
  /// 空串 = 这条记录是第三版之前留下的（那时试跑用的是真实 home，没有这一格）。
  home : String
  /// home 的归属：trial = 这次作业的一次性 home；空串 = 旧记录
  home_kind : String
  /// 复制到一次性 home 里的那份 profile 目录（<home>/profiles/<名字>）。空串 = 旧记录
  profile_copy : String
  started_at : String
  /// 被收掉的时刻（空串 = 还没收过）。只说明动作发生过，不说明进程状态
  mut stopped_at : String
}

///|
/// 使用者给的结论（verdict 步）。
pub(all) struct JobVerdict {
  /// good / bad / later
  value : String
  at : String
  note : String
}

///|
/// 一份作业。
pub(all) struct Job {
  id : String
  kind : String
  title : String
  created_at : String
  mut updated_at : String
  /// lock / install / trial / verdict / commit / rollback / cleanup / done / aborted
  mut step : String
  mut steps : Array[JobStep]
  mut rollback_anchor : JobAnchor?
  mut target : JobTarget?
  /// 试跑用哪一只 profile：job-start 时选定（之后每一步都按它走，不在中途重挑）
  profile : String
  /// 开工前 dsh-pin.json 的样子（回滚按它恢复）
  pin_before : JobPinBefore?
  /// 试跑实例
  mut trial : JobTrial?
  /// 使用者给的结论
  mut verdict : JobVerdict?
  mut commands : Array[JobCommand]
}

///|
/// 读不出来的那一条作业文件：id 取自文件名，原因照实给。
pub(all) struct BadJob {
  id : String
  reason : String
}

///|
/// 五档状态，唯一的合法取值表。
pub let job_states : Array[String] = [
  "running", "passed", "failed", "skipped", "not-run",
]

///|
/// 状态词是不是五档里的一档。
pub fn job_state_known(state : String) -> Bool {
  job_states.contains(state)
}

///|
/// 作业 id 的形状：小写字母 / 数字 / 连字符，不以连字符开头，最长 80。
///
/// 这个值会拼进文件路径（jobs/<id>.json），所以它必须是一个**单段名字**：
/// 斜杠、点、双点一律不收 —— 目录穿越在这一层被挡掉，后面不再假设它干净。
pub fn job_id_valid(id : String) -> Bool {
  if id == "" || id.length() > 80 || id.has_prefix("-") {
    return false
  }
  for ch in id {
    let code = ch.to_int()
    let ok = (code >= 48 && code <= 57) ||
      (code >= 97 && code <= 122) ||
      ch == '-'
    if !ok {
      return false
    }
  }
  true
}

///|
/// 一份作业文件的路径。调用前 id 必须已经过 job_id_valid。
/// 状态目录的解析本身是 async（XDG_STATE_HOME 要从环境读），这里跟着同一条口径。
pub async fn job_path(id : String) -> String noraise {
  @json.join_all([state_paths().jobs, id + ".json"])
}

///|
/// 新建一份作业（步骤表全摆出来，除了 lock 之外都是 not-run）。
pub fn new_job(
  id : String,
  kind : String,
  title : String,
  now : String,
  anchor : JobAnchor,
  target_version : String,
  profile : String,
  pin_before : JobPinBefore,
) -> Job {
  let steps : Array[JobStep] = []
  // 七个步骤全摆出来：trial / verdict / rollback 是这一版新增的三个
  // （trial 只负责把新版跑起来，verdict 才是使用者的结论，rollback 是回滚那一下）。
  for
    key in [
      "lock", "install", "trial", "verdict", "commit", "rollback", "cleanup",
    ] {
    steps.push({ key, state: "not-run", at: "", note: "", evidence: [], })
  }
  let before : JobPinBefore? = Some(pin_before)
  {
    id,
    kind,
    title,
    created_at: now,
    updated_at: now,
    step: "lock",
    steps,
    rollback_anchor: Some(anchor),
    target: Some({ version: target_version, dir: "", }),
    profile,
    pin_before: before,
    trial: None,
    verdict: None,
    commands: [],
  }
}

///|
/// 取某一步（找不到给 None）。
pub fn step_of(job : Job, key : String) -> JobStep? {
  for step in job.steps {
    if step.key == key {
      return Some(step)
    }
  }
  None
}

///|
/// 某一步当前的状态字符串（找不到给空串 —— 界面据此显示「没验到」）。
pub fn job_step_state(job : Job, key : String) -> String {
  match step_of(job, key) {
    Some(step) => step.state
    None => ""
  }
}

///|
/// 把某一步标成某个状态，并记下时刻 / 结论 / 证据。state 必须是五档之一 ——
/// 写进去一个表外的词，读回来就是「没验到」，那等于把结论丢了。
pub fn mark_step(
  job : Job,
  key : String,
  state : String,
  note : String,
  evidence : Array[(String, String)],
  now : String,
) -> Unit {
  for step in job.steps {
    if step.key == key {
      step.state = if job_state_known(state) { state } else { "failed" }
      step.at = now
      step.note = note
      step.evidence = evidence
    }
  }
  job.updated_at = now
}

///|
/// 往某一步的证据里追加几条（不改这一步的结论与 note）。
///
/// 给「已经落定的步骤上又发生了一件事」用：例如在 verdict 步停掉试跑实例，
/// 那一步的结论早写好了，但「谁在什么时候把实例收掉了」也该留证。
pub fn append_evidence(
  job : Job,
  key : String,
  pairs : Array[(String, String)],
  now : String,
) -> Unit {
  for step in job.steps {
    if step.key == key {
      for pair in pairs {
        step.evidence.push(pair)
      }
      // 不动 step.at：那是「这一步的结论是哪一刻落定的」。后追加一条证据不该把落定时刻往后挪，
      // 挪了就会读成「这一步刚刚才验完」。
    }
  }
  job.updated_at = now
}

///|
/// 把作业推进到下一步（step 字段与步骤表分开维护：step 是「现在该做哪一步」）。
pub fn advance_to(job : Job, key : String, now : String) -> Unit {
  job.step = key
  job.updated_at = now
}

///|
/// 作业是不是已经结束（done / aborted / rollback）。
///
/// rollback 也算结束：回滚之后这条作业没有更多能做的事了 —— 旧版本正是在用的那一份，
/// 「清理旧版本」在这一支上是被跳过的一步（新装的那份留着没删，要删是别处的事）。
/// 结束的作业不再挡住同 kind 的新作业。
pub fn job_finished(job : Job) -> Bool {
  job.step == "done" || job.step == "aborted" || job.step == "rollback"
}

///|
/// 一条步骤的 JSON（字段名就是文件里的键）。
fn step_json(step : JobStep) -> @json.JsonVal {
  let evidence : Array[(String, @json.JsonVal)] = []
  for pair in step.evidence {
    evidence.push((pair.0, @json.JStr(pair.1)))
  }
  @json.JObj([
    ("key", @json.JStr(step.key)),
    ("state", @json.JStr(step.state)),
    ("at", @json.JStr(step.at)),
    ("note", @json.JStr(step.note)),
    ("evidence", @json.JObj(evidence)),
  ])
}

///|
/// 一份作业的 JSON（形状见 §3）。
pub fn job_json(job : Job) -> @json.JsonVal {
  let steps : Array[@json.JsonVal] = []
  for step in job.steps {
    steps.push(step_json(step))
  }
  let anchor = match job.rollback_anchor {
    None => @json.JNull
    Some(a) =>
      @json.JObj([
        ("dir", @json.JStr(a.dir)),
        ("version", @json.JStr(a.version)),
      ])
  }
  let target = match job.target {
    None => @json.JNull
    Some(t) =>
      @json.JObj([
        ("version", @json.JStr(t.version)),
        ("dir", @json.JStr(t.dir)),
      ])
  }
  let commands : Array[@json.JsonVal] = []
  for c in job.commands {
    commands.push(
      @json.JObj([
        ("at", @json.JStr(c.at)),
        ("argv", @json.jstr_array(c.argv)),
        ("result", @json.JStr(c.result)),
      ]),
    )
  }
  let pin_before = match job.pin_before {
    None => @json.JNull
    Some(p) =>
      @json.JObj([
        ("existed", @json.JBool(p.existed)),
        ("dir", @json.JStr(p.dir)),
        ("version", @json.JStr(p.version)),
        ("pinnedAt", @json.JStr(p.pinned_at)),
      ])
  }
  let trial = match job.trial {
    None => @json.JNull
    Some(t) =>
      @json.JObj([
        ("pid", @json.jint(t.pid)),
        ("port", @json.jint(t.port)),
        ("url", @json.JStr(t.url)),
        ("profile", @json.JStr(t.profile)),
        ("home", @json.JStr(t.home)),
        ("homeKind", @json.JStr(t.home_kind)),
        ("profileCopy", @json.JStr(t.profile_copy)),
        ("startedAt", @json.JStr(t.started_at)),
        ("stoppedAt", @json.JStr(t.stopped_at)),
      ])
  }
  let verdict = match job.verdict {
    None => @json.JNull
    Some(v) =>
      @json.JObj([
        ("value", @json.JStr(v.value)),
        ("at", @json.JStr(v.at)),
        ("note", @json.JStr(v.note)),
      ])
  }
  @json.JObj([
    ("id", @json.JStr(job.id)),
    ("kind", @json.JStr(job.kind)),
    ("title", @json.JStr(job.title)),
    ("createdAt", @json.JStr(job.created_at)),
    ("updatedAt", @json.JStr(job.updated_at)),
    ("step", @json.JStr(job.step)),
    ("steps", @json.JArr(steps)),
    ("rollbackAnchor", anchor),
    ("target", target),
    ("profile", @json.JStr(job.profile)),
    ("pinBefore", pin_before),
    ("trial", trial),
    ("verdict", verdict),
    ("commands", @json.JArr(commands)),
  ])
}

///|
/// 取字符串字段（不是字符串给 None）。
fn field_text(json : Json, key : String) -> String? {
  match field_of(json, key) {
    Some(v) => as_string(v)
    None => None
  }
}

///|
/// 解析一个 evidence 对象：只收字符串值，别的值记成空串但保留键 ——
/// 键在说明「这里本该有证据」，丢掉键会让那一步看起来什么都没查。
fn parse_evidence(json : Json) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  for pair in object_entries(json) {
    out.push(
      (
        pair.0,
        match as_string(pair.1) {
          Some(s) => s
          None => ""
        },
      ),
    )
  }
  out
}

///|
/// 解析一条步骤。key / state 缺一个就整份作业读不出来 —— 没有 key 的步骤没法对到界面上，
/// 没有 state 的步骤没法说它算不算过。
fn parse_step(json : Json) -> Result[JobStep, String] {
  let key = match field_text(json, "key") {
    Some(v) if @json.trim_both(v) != "" => @json.trim_both(v)
    _ => return Err("步骤缺 key")
  }
  let state = match field_text(json, "state") {
    Some(v) if @json.trim_both(v) != "" => @json.trim_both(v)
    _ => return Err("步骤 " + key + " 缺 state")
  }
  let at = match field_text(json, "at") {
    Some(v) => v
    None => ""
  }
  let note = match field_text(json, "note") {
    Some(v) => v
    None => ""
  }
  let evidence = match field_of(json, "evidence") {
    Some(v) => parse_evidence(v)
    None => []
  }
  Ok({ key, state, at, note, evidence, })
}

///|
/// 解析一份作业文件。必填：id / kind / title / createdAt / step / steps。
fn parse_job(json : Json) -> Result[Job, String] {
  let id = match field_text(json, "id") {
    Some(v) if job_id_valid(@json.trim_both(v)) => @json.trim_both(v)
    Some(v) => return Err("id 认不出来：" + v)
    None => return Err("缺 id")
  }
  let kind = match field_text(json, "kind") {
    Some(v) if @json.trim_both(v) != "" => @json.trim_both(v)
    _ => return Err("缺 kind")
  }
  let title = match field_text(json, "title") {
    Some(v) => v
    None => ""
  }
  let created_at = match field_text(json, "createdAt") {
    Some(v) if @json.trim_both(v) != "" => @json.trim_both(v)
    _ => return Err("缺 createdAt")
  }
  let updated_at = match field_text(json, "updatedAt") {
    Some(v) => v
    None => created_at
  }
  let step = match field_text(json, "step") {
    Some(v) if @json.trim_both(v) != "" => @json.trim_both(v)
    _ => return Err("缺 step")
  }
  let raw_steps = match field_of(json, "steps") {
    Some(Array(items)) => items
    Some(_) => return Err("steps 不是数组")
    None => return Err("缺 steps")
  }
  let steps : Array[JobStep] = []
  for item in raw_steps {
    match parse_step(item) {
      Ok(parsed) => steps.push(parsed)
      Err(reason) => return Err(reason)
    }
  }
  if steps.length() == 0 {
    return Err("steps 是空的")
  }
  let anchor = match field_of(json, "rollbackAnchor") {
    Some(anchor_json) =>
      match
        (field_text(anchor_json, "dir"), field_text(anchor_json, "version")) {
        (Some(dir), Some(version)) =>
          if dir != "" && version != "" {
            let parsed : JobAnchor = { dir, version, }
            Some(parsed)
          } else {
            None
          }
        _ => None
      }
    None => None
  }
  let target = match field_of(json, "target") {
    Some(t) =>
      match field_text(t, "version") {
        Some(version) => {
          let parsed : JobTarget = {
            version,
            dir: match field_text(t, "dir") {
              Some(dir) => dir
              None => ""
            },
          }
          Some(parsed)
        }
        None => None
      }
    None => None
  }
  let commands : Array[JobCommand] = []
  let raw_commands = match field_of(json, "commands") {
    Some(Array(items)) => items
    _ => []
  }
  for item in raw_commands {
    let argv : Array[String] = []
    let raw_argv = match field_of(item, "argv") {
      Some(Array(items)) => items
      _ => []
    }
    for arg in raw_argv {
      match as_string(arg) {
        Some(s) => argv.push(s)
        None => ()
      }
    }
    commands.push({
      at: match field_text(item, "at") {
        Some(s) => s
        None => ""
      },
      argv,
      result: match field_text(item, "result") {
        Some(s) => s
        None => ""
      },
    })
  }
  let profile = match field_text(json, "profile") {
    Some(v) => @json.trim_both(v)
    None => ""
  }
  let pin_before = match field_of(json, "pinBefore") {
    Some(p) => {
      let existed = match field_of(p, "existed") {
        Some(True) => true
        _ => false
      }
      let dir = match field_text(p, "dir") {
        Some(v) => @json.trim_both(v)
        None => ""
      }
      let version = match field_text(p, "version") {
        Some(v) => @json.trim_both(v)
        None => ""
      }
      let pinned_at = match field_text(p, "pinnedAt") {
        Some(v) => @json.trim_both(v)
        None => ""
      }
      let parsed : JobPinBefore = { existed, dir, version, pinned_at, }
      Some(parsed)
    }
    None => None
  }
  let trial = match field_of(json, "trial") {
    Some(t) => {
      let pid = match field_of(t, "pid") {
        Some(Number(n, ..)) => n.to_int()
        _ => 0
      }
      if pid <= 0 {
        None
      } else {
        let port = match field_of(t, "port") {
          Some(Number(n, ..)) => n.to_int()
          _ => 0
        }
        let parsed : JobTrial = {
          pid,
          port,
          url: match field_text(t, "url") {
            Some(v) => v
            None => ""
          },
          profile: match field_text(t, "profile") {
            Some(v) => v
            None => ""
          },
          // 三格都是第三版新增的：旧作业文件里没有它们，读成空串就是「那时用的不是一次性 home」
          home: match field_text(t, "home") {
            Some(v) => v
            None => ""
          },
          home_kind: match field_text(t, "homeKind") {
            Some(v) => v
            None => ""
          },
          profile_copy: match field_text(t, "profileCopy") {
            Some(v) => v
            None => ""
          },
          started_at: match field_text(t, "startedAt") {
            Some(v) => v
            None => ""
          },
          stopped_at: match field_text(t, "stoppedAt") {
            Some(v) => v
            None => ""
          },
        }
        Some(parsed)
      }
    }
    None => None
  }
  let verdict = match field_of(json, "verdict") {
    Some(v) =>
      match field_text(v, "value") {
        Some(value) =>
          if @json.trim_both(value) == "" {
            None
          } else {
            let parsed : JobVerdict = {
              value: @json.trim_both(value),
              at: match field_text(v, "at") {
                Some(s) => s
                None => ""
              },
              note: match field_text(v, "note") {
                Some(s) => s
                None => ""
              },
            }
            Some(parsed)
          }
        None => None
      }
    None => None
  }
  Ok({
    id,
    kind,
    title,
    created_at,
    updated_at,
    step,
    steps,
    rollback_anchor: anchor,
    target,
    profile,
    pin_before,
    trial,
    verdict,
    commands,
  })
}

///|
/// 写一份作业（原子写）。写不进去把原因原样交回去：界面上一句「已保存」而盘上没有，
/// 刷新之后作业就退回上一步 —— 那一句谎比报错难查。
pub async fn save_job(job : Job) -> Result[Unit, String] noraise {
  let path = job_path(job.id)
  @fsx.to_result_unit(@fsx.write_text_atomic_fs(path, @json.encode(job_json(job)) + "\n"))
}

///|
/// 读一份作业。三种情形：
///   · 文件不在 / id 不合法 —— (None, None)：没有这份作业（不是错误）
///   · 读不动 / 不是 JSON / 缺必填 —— (None, Some(原因))：调用方照实报出来
///   · 读到了 —— (Some(job), None)
pub async fn load_job(id : String) -> (Job?, String?) noraise {
  if !job_id_valid(id) {
    return (None, None)
  }
  let (json, reason) = read_state_json(job_path(id))
  if reason is Some(r) {
    return (None, Some(r))
  }
  let json = match json {
    Some(j) => j
    None => return (None, None)
  }
  match parse_job(json) {
    Ok(job) => (Some(job), None)
    Err(why) => (None, Some(why))
  }
}

///|
/// 某 kind 有没有还没结束的作业（job-start 的 job-exists 判据）。
pub fn unfinished_of_kind(jobs : Array[Job], kind : String) -> Job? {
  for job in jobs {
    if job.kind == kind && !job_finished(job) {
      return Some(job)
    }
  }
  None
}

///|
/// 读整个作业目录：合法作业按 createdAt 倒序（最近的在前），读不出来的文件单列。
///
/// 为什么坏文件也要回到界面上：一条读不出来的记录如果只是从列表里消失，
/// 用户会以为那条作业不存在，然后重新开一条 —— 磁盘上那份坏记录永远没人处理。
pub async fn load_jobs() -> (Array[Job], Array[BadJob], Array[String]) noraise {
  let dir = jobs_dir()
  let names = match @json.list_dir_result(dir) {
    Ok(list) => list
    Err(e) =>
      if @json.exists(dir) {
        return ([], [], ["列不出作业目录 " + dir + "：" + e])
      } else {
        return ([], [], [])
      }
  }
  let jobs : Array[Job] = []
  let bad : Array[BadJob] = []
  for name in names {
    if !@json.ends_with(name, ".json") {
      continue
    }
    let id = @json.slice(name, 0, name.length() - 5)
    let (job, reason) = load_job(id)
    match job {
      Some(loaded) => jobs.push(loaded)
      None =>
        match reason {
          Some(why) => bad.push({ id, reason: why, })
          None => ()
        }
    }
  }
  // 最近的在前。createdAt 是 ISO8601（同一时区、定长），按字符串比就是按时间比。
  jobs.sort_by(fn(a, b) {
    -@json.compare_code_units(a.created_at, b.created_at)
  })
  bad.sort_by(fn(a, b) { @json.compare_code_units(a.id, b.id) })
  (jobs, bad, [])
}

///|
/// 读不出来的那条记录在列表里的形状：不编一个作业出来，只给 id 与原因。
pub fn bad_job_json(bad : BadJob) -> @json.JsonVal {
  @json.JObj([
    ("id", @json.JStr(bad.id)),
    ("unreadable", @json.JBool(true)),
    ("reason", @json.JStr(bad.reason)),
  ])
}

///|
/// 合法记录多一个 unreadable=false：界面只认这一条形状，字段缺了会读成坏记录。
pub fn job_list_json(job : Job) -> @json.JsonVal {
  job_list_json_extra(job, [])
}

///|
/// 与 job_list_json 同一份形状，另加几个「读数那一刻才算得出来」的字段。
///
/// 现在只有 trialAlive：试跑实例还活不活着要看进程，不是作业文件里的事实。
/// 界面据此说「试跑实例还在跑」，判据必须来自这一刻的进程表，不能靠 stoppedAt 反推。
pub fn job_list_json_extra(
  job : Job,
  extra : Array[(String, @json.JsonVal)],
) -> @json.JsonVal {
  match job_json(job) {
    @json.JObj(fields) => {
      fields.push(("unreadable", @json.JBool(false)))
      for pair in extra {
        fields.push(pair)
      }
      @json.JObj(fields)
    }
    other => other
  }
}
