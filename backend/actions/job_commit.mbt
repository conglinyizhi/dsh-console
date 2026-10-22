// 提交与收尾：job_commit（提交失败要回滚）、清理预演（job_cleanup_preview）、清理（job_cleanup）。
//
// 2026-10-20 从 job.mbt 拆出来：这三条都会动磁盘且都要写审计，是最该单独读的一族。
// 只搬位置，函数体一个字没改。

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
      "还没到「切到新版本」这一步（当前：" +
      job.step +
      "，结论：" +
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
      note: "目标包目录不在了（" +
      target.dir +
      "），没有动 dsh-pin.json",
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
      fail(
        "io-error",
        "已经改了指派，但作业没能写进磁盘：" + e,
      )
      abort("unreachable: fail 一定抛错")
    }
  }
  {
    job,
    fields,
    note: "已经切到 " +
    pinned.version +
    "；起实例会用这一版。旧版本留着当回滚锚，确认稳定后再清理",
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
      fail(
        "not-found", "这条作业里没有回滚锚（旧版本包目录），没有可清理的东西",
      )
      abort("unreachable: fail 一定抛错")
    }
  }
  let dir = match anchor_dir_of(job) {
    Some(d) => d
    None => {
      fail(
        "conflict",
        "回滚锚里记的不是一份 dsh 包目录：" + anchor.dir,
      )
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
  let same_as_target = target_dir != "" &&
    job_real_dir(target_dir) == job_real_dir(dir)
  let safe = exists && users.length() == 0 && !same_as_target
  let reason = if !exists {
    "旧版本包目录已经不在了，清理时没有可删的"
  } else if same_as_target {
    "回滚锚与目标版本指的是同一份包目录，不许删"
  } else if users.length() > 0 {
    "还有 " +
    users.length().to_string() +
    " 只实例在跑这份 dsh，先停掉再清理"
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
    note: "清理会删掉旧版本的包目录 " +
    dir +
    "（" +
    size_text +
    "，" +
    reason +
    "）。" +
    "清理删的是旧版本的包目录，删掉不能再装回来。确认之后再点执行。",
  }
}

///|
/// 清理旧版本：硬删回滚锚那一份包目录，而且只删这一份。
///
/// 必须带 params.confirm = "DELETE"（§4）；没带一律 bad-params。
/// 拒绝执行的情形：还有实例在跑这一份、锚与目标版本是同一份、目录形状不是 dsh 包目录。
/// 目录本来就不在了算目标状态已成立（passed，并在 note 里说清没有可删的）。
pub async fn job_cleanup(
  id : String,
  confirm : String?,
) -> JobOutcome raise ActionError {
  let given = match confirm {
    Some(v) => @json.trim_both(v)
    None => ""
  }
  if given != "DELETE" {
    fail(
      "bad-params", "清理旧版本要再带一次确认：params.confirm 必须是 \"DELETE\"（这一下之后包目录就没了）",
    )
  }
  let job = require_job(id)
  if job.step != "cleanup" {
    fail(
      "conflict",
      "这条作业现在不在「清理旧版本」这一步（当前：" +
      job.step +
      "）",
    )
  }
  let anchor = match job.rollback_anchor {
    Some(a) => a
    None => {
      fail(
        "conflict", "这条作业里没有回滚锚，不知道该删哪一份",
      )
      abort("unreachable: fail 一定抛错")
    }
  }
  let dir = match anchor_dir_of(job) {
    Some(d) => d
    None => {
      fail(
        "conflict",
        "回滚锚里记的不是一份 dsh 包目录：" + anchor.dir,
      )
      abort("unreachable: fail 一定抛错")
    }
  }
  let now = now_iso()
  let users = running_users_of(dir)
  if users.length() > 0 {
    fail(
      "conflict",
      "旧版本还有 " +
      users.length().to_string() +
      " 只实例在跑（PID " +
      users[0].pid.to_string() +
      "）；先停掉再清理",
    )
  }
  let target_dir = match job.target {
    Some(t) => t.dir
    None => ""
  }
  if target_dir != "" && job_real_dir(target_dir) == job_real_dir(dir) {
    fail(
      "conflict", "回滚锚与目标版本指的是同一份包目录；删了它等于删掉刚切过去的新版",
    )
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
      note: "旧版本包目录 " +
      dir +
      " 已经不在了，没有可删的；作业收尾。",
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
  match @fsx.remove_tree_fs(dir) {
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
          (
            "files",
            match files {
              Some(n) => n.to_string()
              None => ""
            },
          ),
          (
            "bytes",
            match bytes {
              Some(n) => n.to_string()
              None => ""
            },
          ),
          ("sizeSource", size_source),
        ],
        now,
      )
      @store.advance_to(job, "done", now)
      match @store.save_job(job) {
        Ok(_) => ()
        Err(e) => {
          fail(
            "io-error",
            "目录已经删了，但作业没能写进磁盘：" + e,
          )
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
        note: "旧版本包目录已删掉：" +
        dir +
        "（" +
        size_text +
        "）。只删了这一份包目录，别处没动。",
      }
    }
    Err(e) => {
      @store.mark_step(
        job,
        "cleanup",
        "failed",
        "旧版本包目录没删掉（原因在证据里）",
        [("dir", dir), ("version", anchor.version), ("error", e.raw)],
        now,
      )
      match @store.save_job(job) {
        Ok(_) => ()
        Err(e2) => {
          fail("io-error", "删除失败，作业记录也没写进去：" + e2)
          abort("unreachable: fail 一定抛错")
        }
      }
      note_raw(e.raw)
      fail("io-error", "删目录失败")
      abort("unreachable: fail 一定抛错")
    }
  }
}

// ── 中止 ─────────────────────────────────────────────────────
