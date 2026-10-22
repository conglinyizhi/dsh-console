// 试跑用的一次性 home：名字规则、铺设、清理、残留清扫。
//
// 2026-10-20 从 homes.mbt 拆出来：那一族寿命只有「一次作业」，与长期存在的隔离 home
// 是两种东西。只搬位置，函数体一个字没改。

///|
/// 作业 id 能不能拿来拼一次性 home 的名字：只认小写字母 / 数字 / 连字符
/// （与作业文件 id 同一把尺子，见 store 的 job_id_valid），且不以连字符开头。
fn trial_job_id_ok(id : String) -> Bool {
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
/// 作业 id → 一次性 home 的目录名 trial-<末 6 位>（id 不足 6 位就是整段）。
pub fn trial_home_name(job_id : String) -> String? {
  let id = @json.trim_both(job_id)
  if !trial_job_id_ok(id) {
    return None
  }
  let n = id.length()
  let tail = if n <= 6 { id } else { @json.slice(id, n - 6, n) }
  Some(trial_home_prefix + tail)
}

///|
/// 一次性 home 的路径（不判断存在）。硬约束：正好是 <root>/trial-<单段>。
/// 拼出来不是这一条就给 None —— 路径不从这里以外的地方来。
pub fn trial_home_path(root : String, job_id : String) -> String? {
  match trial_home_name(job_id) {
    None => None
    Some(name) =>
      if !single_segment(name) || !name.has_prefix(trial_home_prefix) {
        None
      } else {
        Some(root + "/" + name)
      }
  }
}

///|
/// 一次建试跑 home 的结果。作业里的 trial 三格与证据都从这里取，不另猜。
pub(all) struct TrialHome {
  job_id : String
  path : String
  profile : String
  /// 复制过去的那份 profile 目录：<path>/profiles/<名字>
  profile_dir : String
  files_copied : Int32
  node_modules_target : String
  skills_linked : Bool
  credentials_path : String
  credentials_key : String
  created_at : String
  /// 建之前有没有一份旧的在（上次没收干净）：有就先删掉，这句话照实写「删掉了哪一份」
  replaced : String
}

///|
/// 建之前把上次留下的那一份删掉，并把这件事实写成一句话。
/// 返回 (说明, 错误)：删不掉时错误非空，调用方不能接着建新的。
async fn clear_stale_trial_home(home : String) -> (String, String) noraise {
  if !@json.exists(home) {
    return ("", "")
  }
  let size_text = match @fsx.measure_tree(home) {
    Ok((files, bytes)) =>
      "（" +
      files.to_string() +
      " 个文件，" +
      bytes.to_string() +
      " 字节）"
    Err(_) => "（体积读不到）"
  }
  match @fsx.remove_tree_fs(home) {
    Ok(_) => ("上次留下的 " + home + " 已经先删掉" + size_text, "")
    Err(e) =>
      (
        "",
        {
          @store.note_raw(e.raw)
          "删目录失败：上次留下的一次性 home 删不掉，不能在建新的之前留着一份旧的"
        },
      )
  }
}

///|
/// 建一份试跑用的一次性 home：<homes root>/trial-<作业 id 末 6 位>/
///
/// 建之前先看有没有旧的那一份（上次没收干净）：有就先删再建，删了哪一份照实写进
/// replaced（调用方把它写进证据）。
/// 任何一步失败都把刚建的那份删掉再报 —— 不留半成品给下一次「先删再建」去收拾。
pub async fn create_trial_home(
  job_id_in : String,
  name_in : String,
) -> Result[TrialHome, (String, String)] noraise {
  let name = @json.trim_both(name_in)
  if !single_segment(name) {
    return Err(
      (
        "bad-params",
        "profile 名要是单段（不含 / 与 ..，非空）：" + name,
      ),
    )
  }
  let job_id = @json.trim_both(job_id_in)
  let (root, root_source) = homes_root()
  let home = match trial_home_path(root, job_id) {
    Some(h) => h
    None =>
      return Err(
        (
          "bad-params",
          "试跑 home 的路径拼不出来（作业 id 认不出）：" +
          job_id +
          "；homes root 来自 " +
          root_source +
          "：" +
          root,
        ),
      )
  }
  let (dsh_home, _dsh_home_source) = @runtime.resolve_dsh_home()
  let src_dir = @json.join_all([dsh_home, "profiles", name])
  if !@json.is_dir(src_dir) {
    return Err(("not-found", "profile 目录不存在：" + src_dir))
  }
  let (replaced, stale_error) = clear_stale_trial_home(home)
  if stale_error != "" {
    return Err(("io-error", stale_error))
  }
  let layout = match layout_home(home, name, src_dir, dsh_home) {
    Err((code, message)) => {
      let _ = @fsx.remove_tree_fs(home)
      return Err(
        (
          code,
          message +
          "；刚建的 " +
          home +
          " 已经删掉，没有留下半成品",
        ),
      )
    }
    Ok(got) => got
  }
  let pdir = @json.join_all([home, "profiles", name])
  let created = @json.iso_from_epoch_ms(@async.now())
  let marker = @json.JObj([
    ("kind", @json.JStr(home_kind_trial)),
    ("jobId", @json.JStr(job_id)),
    ("profile", @json.JStr(name)),
    ("createdAt", @json.JStr(created)),
    ("dshHome", @json.JStr(dsh_home)),
    ("homesRoot", @json.JStr(root)),
    ("profileSource", @json.JStr(src_dir)),
    ("credentialsPath", @json.JStr(layout.credentials_path)),
    ("credentialsKey", @json.JStr(layout.credentials_key)),
    ("nodeModulesTarget", @json.JStr(layout.node_modules_target)),
  ])
  let marker_write = @fsx.write_text_atomic_fs(
    @json.join_path(home, isolation_marker),
    @json.encode(marker) + "\n",
  )
  match marker_write {
    Ok(_) => ()
    Err(e) => {
      let _ = @fsx.remove_tree_fs(home)
      return Err(
        (
          "io-error",
          {
            @store.note_raw(e.raw)
            "写文件失败；刚建的 " + home + " 已经删掉"
          },
        ),
      )
    }
  }
  match verify_isolated(pdir, layout.node_modules_target) {
    Some(problem) => {
      let _ = @fsx.remove_tree_fs(home)
      return Err(
        (
          "io-error",
          "一次性 home 的核对没过：" +
          problem +
          "；刚建的 " +
          home +
          " 已经删掉",
        ),
      )
    }
    None => ()
  }
  Ok({
    job_id,
    path: home,
    profile: name,
    profile_dir: pdir,
    files_copied: layout.files_copied,
    node_modules_target: layout.node_modules_target,
    skills_linked: layout.skills_linked,
    credentials_path: layout.credentials_path,
    credentials_key: layout.credentials_key,
    created_at: created,
    replaced,
  })
}

///|
/// 删一份试跑用的一次性 home。成功给一句人话（进证据 / 正文），失败给 (错误码, 原因)。
///
/// 路径核对：必须正好是 <homes root>/trial-<单段>，且不带 . / .. —— 这一道挡的是
/// 「拿一个别的路径来让控制台删」这件事，不是格式洁癖。
pub async fn remove_trial_home(
  home_in : String,
) -> Result[String, (String, String)] noraise {
  let (root, _root_source) = homes_root()
  let home = trim_tail_slash(@json.trim_both(home_in))
  if home == "" {
    return Err(("bad-params", "没有给出要删的试跑 home 路径"))
  }
  let prefix = root + "/"
  if !home.has_prefix(prefix) {
    return Err(
      (
        "bad-params",
        "试跑 home 不在 " + root + " 下，没有动它：" + home,
      ),
    )
  }
  let name = @json.slice_from(home, prefix.length())
  if !single_segment(name) || !name.has_prefix(trial_home_prefix) {
    return Err(
      (
        "bad-params",
        "只删 " +
        root +
        "/" +
        trial_home_prefix +
        "… 这一种目录，没有动它：" +
        home,
      ),
    )
  }
  if !@json.is_dir(home) {
    return Ok("一次性 home 本来就不在：" + home)
  }
  let size_text = match @fsx.measure_tree(home) {
    Ok((files, bytes)) =>
      "（" +
      files.to_string() +
      " 个文件，" +
      bytes.to_string() +
      " 字节）"
    Err(_) => "（体积读不到）"
  }
  match @fsx.remove_tree_fs(home) {
    Ok(_) => Ok("一次性 home 已经删掉：" + home + size_text)
    Err(e) => {
      @store.note_raw(e.raw)
      Err(("io-error", "删目录失败：一次性 home 没删掉"))
    }
  }
}
