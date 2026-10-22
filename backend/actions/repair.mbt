// 补包：repair-packages（design/design-fixes.md §39）。
//
// 一只 profile 缺 bundles 时，界面给一颗「安装缺的包（N）」。这一支在 profile 目录里跑一次
// 包管理器（有 pnpm-lock 用 pnpm、有 package-lock 用 npm、都没有按 pnpm），把输出落进
// <状态目录>/logs/repair-<名>-<毫秒>.log，跑完重新读一遍 bundles 算剩余缺包。
//
// 只动 node_modules 的意图：命令就是 `install`，不碰 package.json / cordis.patch.yml，
// 也不改 lock 文件之外的东西 —— 真被 install 顺手更新了 lock，那是包管理器自己的行为，
// 不在这一处加干预（干预它就得替用户决定要不要锁版本）。

///|
/// 一次补包的硬上限（§39.2）：120 秒。到点收掉进程（SIGTERM，等 2 秒再 SIGKILL）。
let repair_timeout_ms : Int32 = 120000

///|
/// 正在跑的补包（键是 home + 换行 + profile）。同一只 profile 同时只允许一个：
/// 两条 install 撞在同一个 node_modules 上会互相撕，报 busy 比赌它没事强。
let repairing : Ref[Array[String]] = { val: [], }

///|
fn repair_key(home : String, profile : String) -> String {
  home + "\n" + profile
}

///|
fn repair_release(key : String) -> Unit {
  let kept : Array[String] = []
  for item in repairing.val {
    if item != key {
      kept.push(item)
    }
  }
  repairing.val = kept
}

///|
/// 补包动作的入口：校验 → 上锁 → 跑 → 复算 → 回执。
///
/// 失败一律走 fail（busy / not-found / install-failed / install-incomplete），
/// 并在抛错之前把 outcome 登记到 failure_outcome —— 那笔失败的审计因此也带 logPath。
pub async fn repair_packages(
  profile_in : String,
  home_in : String?,
) -> @json.JsonVal raise ActionError {
  let profile = @json.trim_both(profile_in)
  validate_profile_name(profile)
  let home = match home_in {
    Some(raw) =>
      match @store.normalize_home(@json.trim_both(raw)) {
        Some(h) => h
        None => {
          fail(
            "bad-params",
            "home 要是一个绝对的目录路径（不含 . 与 .. 段）：" +
            raw,
          )
          abort("unreachable: fail 一定抛错")
        }
      }
    None => {
      let (h, _) = @profiles.default_home_of(profile)
      h
    }
  }
  let dir = @json.join_all([home, "profiles", profile])
  if !@json.is_dir(dir) {
    fail("not-found", "profile 目录不存在：" + dir)
  }
  let pkg = @json.join_path(dir, "package.json")
  if !@json.exists(pkg) {
    fail(
      "not-found",
      "这只 profile 没有 package.json（" +
      pkg +
      "）：没有包清单，不知道该装什么",
    )
  }
  let key = repair_key(home, profile)
  if repairing.val.contains(key) {
    fail(
      "busy",
      "这只 profile 上一次补包还没结束（同一只同时只跑一个）：等它收尾，或者看 " +
      "状态目录 logs/ 下那份 repair 日志",
    )
  }
  repairing.val.push(key)
  // 从这里开始，任何一条出口都要把锁摘掉 —— 包括抛错那条（ActionError 只有两个格，
  // 用 catch 摘锁再原样抛回去）。
  let data = run_repair(profile, home, dir) catch {
    ActionError(code~, message~) => {
      repair_release(key)
      fail(code, message)
      abort("unreachable: fail 一定抛错")
    }
  }
  repair_release(key)
  data
}

///|
/// 真正干活的那一段：跑命令、写日志、复算缺包、拼 outcome。
async fn run_repair(
  profile : String,
  home : String,
  dir : String,
) -> @json.JsonVal raise ActionError {
  let shared = @json.join_all([home, "profiles", "node_modules"])
  let missing_before = @profiles.missing_bundles_in(dir, shared)
  let command = @profiles.repair_command_of(dir)
  let argv = @profiles.repair_argv_of(dir)
  // §F：跑之前先拦两种跑不成的 —— 包管理器不在机器上、或这只 profile 是 Yarn PnP。
  // 拦在这里是为了不等那 120 秒超时：这两种情况等下去也不会有转机。
  match @profiles.repair_refusal(dir) {
    Some(pair) => {
      // 新码在 respond.mbt 的 fail() 白名单之外会被收敛成 io-error，这里用 bad-params：
      // 语义是「这次请求在这个环境下办不成」，不是服务端读写失败。
      let _ = pair.0
      fail("bad-params", pair.1)
      abort("unreachable: fail 一定抛错")
    }
    None => ()
  }
  let state = @store.state_paths()
  let logs_dir = @json.join_path(state.dir, "logs")
  match @fsx.to_result_unit(@fsx.ensure_dir_fs(logs_dir)) {
    Ok(_) => ()
    Err(reason) => {
      fail("io-error", reason)
      abort("unreachable: fail 一定抛错")
    }
  }
  let started_ms = @async.now()
  let log_path = @json.join_path(
    logs_dir,
    "repair-" + profile + "-" + started_ms.to_string() + ".log",
  )
  let header = "# repair-packages\n" +
    "# at: " +
    @json.iso_from_epoch_ms(started_ms) +
    "\n" +
    "# profile: " +
    profile +
    "\n" +
    "# dir: " +
    dir +
    "\n" +
    "# command: " +
    command +
    "\n" +
    "# timeout: " +
    (repair_timeout_ms / 1000).to_string() +
    "s\n" +
    "# missingBefore: " +
    missing_before.length().to_string() +
    "\n" +
    "\n"
  match @fsx.to_result_unit(@fsx.write_text_atomic_fs(log_path, header)) {
    Ok(_) => ()
    Err(reason) => {
      {
        note_raw(reason)
        fail("io-error", "建不了补包日志")
      }
      abort("unreachable: fail 一定抛错")
    }
  }
  // 子进程的 stdout/stderr 直接追加进这份日志（append），父进程这一侧只负责等。
  let out = @process.redirect_to_file(
    log_path,
    append=true,
    create_mode=OpenOrCreate,
    permission=0o600,
  ) catch {
    err => {
      fail(
        "io-error",
        "打不开补包日志：" + log_path + "（" + err.to_string() + "）",
      )
      abort("unreachable: fail 一定抛错")
    }
  }
  let input = @process.redirect_from_file("/dev/null") catch {
    err => {
      fail("io-error", "打不开 /dev/null：" + err.to_string())
      abort("unreachable: fail 一定抛错")
    }
  }
  // cwd 必须是 profile 目录：不传的话 pnpm 会在控制台自己的工作目录里
  // 「Already up to date」并退出 0 —— 装的是别处，缺的包一个没补（实测踩过）。
  // inherit_env=true：包管理器要 PATH / HOME / 代理 / registry 这些环境才跑得对
  //（给子进程一份空环境时，pnpm 连自己的 store 都找不着）。
  let pid = @process.spawn_orphan(
    argv[0],
    argv[1:],
    stdin=input,
    stdout=out,
    stderr=out,
    cwd=dir,
    inherit_env=true,
  ) catch {
    err => {
      fail(
        "install-failed",
        "起不了 " +
        argv[0] +
        "（" +
        err.to_string() +
        "）；日志 " +
        log_path,
      )
      abort("unreachable: fail 一定抛错")
    }
  }
  out.close()
  let began = @async.now()
  let mut timed_out = false
  while process_alive(pid) {
    if (@async.now() - began).to_int() >= repair_timeout_ms {
      timed_out = true
      break
    }
    @async.sleep(100)
  }
  if timed_out {
    // 与停实例同一套：先 SIGTERM，等 2 秒还不走再 SIGKILL（不硬等到 120 秒之后又一秒）。
    let _ = @fsx.send_signal(pid, @fsx.sigterm)
    let grace = @async.now()
    while process_alive(pid) && (@async.now() - grace).to_int() < 2000 {
      @async.sleep(50)
    }
    if process_alive(pid) {
      let _ = @fsx.send_signal(pid, @fsx.sigkill)
    }
  }
  let mut exit_code = -1
  if !process_alive(pid) {
    exit_code = @process.wait_pid(pid) catch { _ => -1 }
  } else {
    // 还活着（SIGKILL 之后极短的窗口）：挂一只协程收尸，不留僵尸。
    spawn_reaper(async fn() {
      try {
        let _ = @process.wait_pid(pid)
      } catch {
        _ => ()
      }
      ()
    })
  }
  let duration = (@async.now() - began).to_int()
  let missing_after = @profiles.missing_bundles_in(dir, shared)
  // §E：日志里有没有「registry 说没这个包」的证据 —— 有的话，重试多少次都没用，下一步是改 package.json。
  let not_in_registry = log_mentions_missing(log_path)
  let outcome = @json.JObj([
    ("profile", @json.JStr(profile)),
    ("home", @json.JStr(home)),
    ("dir", @json.JStr(dir)),
    ("command", @json.JStr(command)),
    ("exitCode", @json.jint(exit_code)),
    ("durationMs", @json.jint(duration)),
    ("timedOut", @json.JBool(timed_out)),
    ("logPath", @json.JStr(log_path)),
    ("missingBefore", @json.jint(missing_before.length())),
    ("missingAfter", @json.jint(missing_after.length())),
    ("remaining", @json.JArr(missing_after.map(fn(m) { @json.JStr(m) }))),
  ])
  if timed_out {
    set_failure_outcome(outcome)
    fail(
      "install-failed",
      "补包超过 " +
      (repair_timeout_ms / 1000).to_string() +
      " 秒，已经收掉；日志 " +
      log_path,
    )
    abort("unreachable: fail 一定抛错")
  } else if not_in_registry {
    // §E 第一档：registry 里根本没有（404 / ERR_PNPM_FETCH_404）。退出码通常非 0，但也可能
    // 「其它包装上了、这一个没装上」而退出 0 —— 两条出口都先看这个证据。
    set_failure_outcome(outcome)
    fail(
      "install-incomplete",
      "这几个在 registry 里找不到，得改 package.json：" +
      join_names(missing_after) +
      "（重试不会变好）；日志 " +
      log_path,
    )
    abort("unreachable: fail 一定抛错")
  } else if exit_code != 0 {
    set_failure_outcome(outcome)
    fail(
      "install-failed",
      "安装失败（退出码 " +
      exit_code.to_string() +
      "）：" +
      log_tail_line(log_path) +
      "；完整输出在 " +
      log_path,
    )
    abort("unreachable: fail 一定抛错")
  } else if missing_after.length() > 0 {
    set_failure_outcome(outcome)
    fail(
      "install-incomplete",
      "装了，但还缺 " +
      missing_after.length().to_string() +
      " 个（" +
      join_names(missing_after) +
      "），可以重试；日志 " +
      log_path,
    )
    abort("unreachable: fail 一定抛错")
  } else {
    @json.JObj([
      ("action", @json.JStr("repair-packages")),
      ("outcome", outcome),
      (
        "note",
        @json.JStr(
          profile +
          " 的包已装齐（" +
          command +
          "，" +
          (duration / 1000).to_string() +
          " 秒）",
        ),
      ),
    ])
  }
}

///|
/// 日志里有没有「registry 里没有这个包」的证据（§E）：pnpm 的 ERR_PNPM_FETCH_404 / 404 Not Found。
async fn log_mentions_missing(path : String) -> Bool noraise {
  let text = match @json.read_text_file(path) {
    Ok(t) => t
    Err(_) => return false
  }
  let upper = text.to_upper()
  upper.contains("ERR_PNPM_FETCH_404") ||
  upper.contains("404 NOT FOUND") ||
  upper.contains("E404") ||
  upper.contains("NOT FOUND - 404")
}

///|
/// 把包名拼成「A、B、C」（不引第三方 join 助手）。
fn join_names(names : Array[String]) -> String {
  let out = StringBuilder()
  for i, name in names {
    if i > 0 {
      out.write_string("、")
    }
    out.write_string(name)
  }
  out.to_string()
}

///|
/// 日志最后一条非空行（失败信息只带证据，不把整份日志丢进提示条）。
/// 读不到就空串 —— 日志本身可能因为磁盘满没写出来，那不该盖住「安装失败」这件事。
async fn log_tail_line(path : String) -> String noraise {
  let text = match @json.read_text_file(path) {
    Ok(t) => t
    Err(_) => return ""
  }
  let kept : Array[String] = []
  for line in text.split("\n") {
    let trimmed = @json.trim_both(@json.owned(line))
    if trimmed != "" && !trimmed.has_prefix("#") {
      kept.push(trimmed)
    }
  }
  if kept.length() == 0 {
    return ""
  }
  "最后一行：" + @json.utf8_prefix(kept[kept.length() - 1], 200)
}
