// 作业的每一步：装包（job_install）、试跑（job_trial）、判定（job_verdict），
// 以及版本锁那几条（capture_pin_before / pin_file_text / restore_pin_before）与试跑 home 的清理。
//
// 2026-10-20 从 job.mbt 拆出来：那个文件 1670 行，主干（开始 / 中止 / 结局）与三步的细节混在
// 一起；拆开之后改某一步只看这一份。只搬位置，函数体一个字没改。

///|
/// 试跑实例现在跑的是不是这条作业起的那一只（进程表读得到 argv 时对上号）。
///
/// 返回 None = 没发现对不上（进程表里没这个 pid，或者对得上）；
/// Some(原因) = 对不上。为什么要认这一道：pid 会被系统回收再利用，
/// 真要收的是一只不属于这条作业的进程，那是这个控制台最不该做的事 ——
/// 宁可留下一只收不掉的实例并如实说清，也不拿 pid 数字直接下手。
async fn trial_owner_mismatch(job : @store.Job, pid : Int32) -> String? noraise {
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
        "PID " +
        pid.to_string() +
        " 现在跑的不是这条作业的试跑实例（进程表里它的 profile 与包目录都对不上），没有动它",
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
        let attempt = Ok(stop_pid(t.pid, settings.process_stop_grace_ms)) catch {
          // 停不成的原因只进正文；错误码在这里没有用处
          ActionError(message~, ..) => Err(message)
        }
        match attempt {
          Err(message) => "试跑实例没停成：" + message
          Ok(stopped) => {
            let _ = @store.remove_by_pid(t.pid)
            t.stopped_at = now_iso()
            "试跑实例已收掉（PID " +
            stopped.pid.to_string() +
            "，" +
            stopped.signal +
            "）"
          }
        }
      }
    }
  }
  // 实例还活着就不动它脚下的 home：删一份正被用着的 home 比留着它糟得多
  if process_alive(t.pid) {
    return stop_note +
      "；一次性 home 先留着：这只实例还在跑（PID " +
      t.pid.to_string() +
      "）"
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
    Some(pin) =>
      {
        existed: true,
        dir: pin.dir,
        version: pin.version,
        pinned_at: pin.pinned_at,
      }
    None => { existed, dir: "", version: "", pinned_at: "", }
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
  match @json.read_text_file_fs(paths.dsh_pin) {
    Ok(t) => @json.trim_both(t)
    Err(_) => "（读不出来）"
  }
}

///|
/// 把 dsh-pin.json 恢复成开工前的样子。只做这一件事，不碰任何包目录。
async fn restore_pin_before(
  before : @store.JobPinBefore,
) -> Result[String, String] noraise {
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
      pinned_at: if before.pinned_at == "" {
        now_iso()
      } else {
        before.pinned_at
      },
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
    Err(e) =>
      fail("io-error", "试跑没做成，作业也没能写进磁盘：" + e)
  }
  { job, fields: [("started", @json.JBool(false))], note, }
}

// ── 1. job-start ─────────────────────────────────────────────

///|
/// 安装新版本。confirm=false 只预演（回确切命令、会不会动到在跑的那份），
/// confirm=true 才真的执行 pnpm add -g。
///
/// 「会不会动到正在跑的那份」的口径：在跑实例各自跑在自己的包目录上（argv 里写死），
/// pnpm 装的是全局根里的另一份 —— **除非目标版本与某只在跑实例的版本相同**，
/// 那时 pnpm 会把同一份包的目录重装一遍，正在跑的那只读的文件就换了。
/// 这一条按事实说，不替用户判断安全不安全。
pub async fn job_install(
  id : String,
  confirm : Bool,
) -> JobOutcome raise ActionError {
  let job = require_job(id)
  if job.step != "install" {
    fail(
      "conflict",
      "这条作业现在不在「安装新版本」这一步（当前：" +
      job.step +
      "）",
    )
  }
  let version = match job.target {
    Some(t) => @json.trim_both(t.version)
    None => ""
  }
  if version == "" {
    fail(
      "bad-params", "这条作业没有目标版本；到「维护」页重新开一条并填上要装的版本",
    )
  }
  let command : Array[String] = [
    "pnpm",
    "add",
    "-g",
    "@deepseek-ai/dsh@" + version,
  ]
  let pnpm = @json.find_in_path("pnpm")
  let snapshots = running_snapshots()
  let touched : Array[RunningSnapshot] = []
  for item in snapshots {
    if item.version == version {
      touched.push(item)
    }
  }
  let touch_text = if touched.length() == 0 {
    "在跑的实例（" +
    snapshots.length().to_string() +
    " 只）各自跑在自己那份包目录上，这一装不动它们"
  } else {
    "有 " +
    touched.length().to_string() +
    " 只在跑的实例用的就是 " +
    version +
    "：pnpm 会把同一份包目录重装一遍，它们读的文件会换"
  }
  let running_field = running_json(snapshots)
  if !confirm {
    let note = "预演：将要执行 " +
      command.join(" ") +
      "（在 " +
      @json.home_dir() +
      " 下跑）。" +
      touch_text +
      "。这一步会真的装东西，装完不会自动切过去。"
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
        "PATH 上找不到 pnpm，没法执行安装；装好 pnpm 再来，或者手动跑：" +
        command.join(" "),
      )
      abort("unreachable: fail 一定抛错")
    }
  }
  let argv : Array[String] = [
    pnpm_path,
    "add",
    "-g",
    "@deepseek-ai/dsh@" + version,
  ]
  let started = now_iso()
  let outcome = run_capture(argv, Map([]), @json.home_dir(), install_timeout_ms)
  let now = now_iso()
  match outcome {
    Err(reason) => {
      job.commands.push({ at: started, argv, result: "没跑完：" + reason, })
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
        result: "exit=" +
        code.to_string() +
        (if tail == "" { "" } else { "；" + tail }),
      })
      let target_dir = find_version_dir(version)
      match target_dir {
        Some(dir) => job.target = Some({ version, dir, })
        None => ()
      }
      let dir_text = match target_dir {
        Some(dir) => "新版包目录：" + dir
        None =>
          "装完之后没在这台机器上扫到 " +
          version +
          " 这一份（试跑那一步会再找一次）"
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
            (
              "targetDir",
              match target_dir {
                Some(dir) => dir
                None => ""
              },
            ),
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
          fail(
            "io-error",
            "安装跑完了，但作业没能写进磁盘：" + e,
          )
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
        }) +
        dir_text +
        (if tail == "" { "" } else { "输出尾部：" + tail }),
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
      "这条作业现在不在「把新版本跑起来」这一步（当前：" +
      job.step +
      "）",
    )
  }
  // 上一只试跑实例还活着：不许起第二只（§4）。判据是这一刻的进程表，不是作业里的记录。
  match job.trial {
    Some(t) =>
      if process_alive(t.pid) {
        fail(
          "conflict",
          "试跑实例还在跑（PID " +
          t.pid.to_string() +
          "，端口 " +
          t.port.to_string() +
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
    Some(t) if @json.trim_both(t.dir) != "" && @json.is_dir(t.dir) =>
      @json.trim_both(t.dir)
    _ =>
      match find_version_dir(version) {
        Some(dir) => {
          job.target = Some({ version, dir, })
          dir
        }
        None =>
          return trial_failed(
            job,
            "这台机器上找不到 " +
            version +
            " 这一份 dsh（安装那一步可能没真的装上）",
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
          "目标包目录里的版本是 " +
          actual +
          "，不是作业里的 " +
          version,
          [
            ("expectedVersion", version),
            ("actualVersion", actual),
            ("targetDir", target_dir),
          ],
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
    fail(
      "bad-params", "这条作业没记试跑用的 profile（开工时就该选好）；到「维护」页重开一条",
    )
  }
  validate_profile_name(profile)
  let (source_home, source_home_source) = @runtime.resolve_dsh_home()
  // 第二道（§11.2）：配置读不到、或不是网页型 profile，一律 bad-params 拒掉 ——
  // 这不是「这一步跑失败了」，是请求本身不该发出来（作业留在 trial 步，修好再点）。
  match @profiles.trial_profile_blocker(source_home, profile) {
    Some(reason) => fail("bad-params", reason)
    None => ()
  }
  let source_profile_dir = @json.join_all([source_home, "profiles", profile])
  let settings = @store.load_settings().values
  let port = match pick_free_port(settings.instance_base_port) {
    Some(p) => p
    None => {
      fail(
        "conflict",
        "从 " +
        settings.instance_base_port.to_string() +
        " 起找不到空闲端口给试跑实例",
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
  let started = Ok(
    start_instance_with(
      profile,
      Some(trial_home.path),
      Some(port),
      Some(target_dir),
      true,
    ),
  ) catch {
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
        (
          "skillsLinked",
          if trial_home.skills_linked {
            "true"
          } else {
            "false"
          },
        ),
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
        "新版本在一次性 home 里起来了（端口 " +
        outcome.port.to_string() +
        "，PID " +
        outcome.pid.to_string() +
        "），等你试",
        evidence,
        now,
      )
      // verdict 步：结论还没出，记 running —— 到这里写 passed 就是把「没验到」写成「通过」
      @store.mark_step(
        job,
        "verdict",
        "running",
        "等你试：好用 / 不好用 / 先放着",
        [
          ("trialPid", outcome.pid.to_string()),
          ("trialPort", outcome.port.to_string()),
        ],
        now,
      )
      @store.advance_to(job, "verdict", now)
      match @store.save_job(job) {
        Ok(_) => ()
        Err(e) => {
          fail(
            "io-error",
            "实例起来了，但作业没能写进磁盘：" + e,
          )
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
        note: "新版本在一次性 home 里起来了：http://127.0.0.1:" +
        outcome.port.to_string() +
        "/。试跑用的是 profile " +
        profile +
        " 的一份配置拷贝，你平时那份 home 没有动。" +
        "这只实例不会被作业自动收掉；收尾（好用 / 不好用 / 停掉试跑 / 中止）时会停掉它，" +
        "并删掉 " +
        trial_home.path +
        " 这份 home。",
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
pub async fn job_verdict(
  id : String,
  verdict_in : String,
) -> JobOutcome raise ActionError {
  let job = require_job(id)
  let value = @json.trim_both(verdict_in)
  if !verdict_values.contains(value) {
    fail(
      "bad-params",
      "verdict 只能是 good / bad / later，收到「" + value + "」",
    )
  }
  if job.step != "verdict" {
    fail(
      "conflict",
      "这条作业现在不在「你来试」这一步（当前：" +
      job.step +
      "）",
    )
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
  job.verdict = Some({ value, at: now, note: record, })
  if value == "later" {
    @store.mark_step(
      job,
      "verdict",
      "running",
      "先放着：什么都不动，你想好了再说",
      [
        ("verdict", "later"),
        (
          "trialPid",
          match job.trial {
            Some(t) => t.pid.to_string()
            None => ""
          },
        ),
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
      Err(e) =>
        fail("io-error", "结论记下了，但作业没能写进磁盘：" + e)
    }
    return {
      job,
      fields: [
        ("verdict", @json.JStr("good")),
        ("trialAlive", @json.JBool(false)),
        ("stop", @json.JStr(stop_note)),
        ("pinUnchanged", @json.JBool(pin_before_content == pin_file_text())),
      ],
      note: "记下了：好用。" +
      stop_note +
      "。dsh-pin.json 还没有动；" +
      "切到新版本是下一步那一下。",
    }
  }
  // bad：先把试跑实例收掉，再按开工前的快照恢复 pin，最后看盘上恢复成了什么
  let restored = restore_pin_before(
    match job.pin_before {
      Some(p) => p
      None => { existed: false, dir: "", version: "", pinned_at: "", }
    },
  )
  let pin_after_content = pin_file_text()
  match restored {
    Err(why) => {
      @store.mark_step(
        job,
        "verdict",
        "passed",
        "你说不好用；" + stop_note,
        [
          ("verdict", "bad"),
          ("stop", stop_note),
          ("pinBefore", pin_before_content),
          ("pinAfter", pin_after_content),
          ("restoreError", why),
        ],
        now,
      )
      @store.mark_step(
        job,
        "rollback",
        "failed",
        "回滚没做成（原因在证据里）；作业停在「你来试」，可以再点一次「不好用，回滚」",
        [
          ("reason", why),
          ("pinBefore", pin_before_content),
          ("pinAfter", pin_after_content),
        ],
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
      @store.mark_step(
        job,
        "verdict",
        "passed",
        "你说不好用；" + stop_note,
        [
          ("verdict", "bad"),
          ("stop", stop_note),
          ("pinBefore", pin_before_content),
          ("pinAfter", pin_after_content),
        ],
        now,
      )
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
          fail(
            "io-error",
            "回滚做完了，但作业没能写进磁盘：" + e,
          )
          abort("unreachable: fail 一定抛错")
        }
      }
      {
        job,
        fields: [
          ("verdict", @json.JStr("bad")),
          ("trialAlive", @json.JBool(false)),
          ("stop", @json.JStr(stop_note)),
          (
            "anchorVersion",
            @json.JStr(
              match job.rollback_anchor {
                Some(a) => a.version
                None => ""
              },
            ),
          ),
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
