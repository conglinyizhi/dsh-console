// 维护动作与 profile 写动作的回执落地：删除 / 回收站 / 版本锁定（pin）、维护作业（job-*）、\n// 备注保存、新建实例、用另一只配置起实例。\n//\n// 2026-10-20 从 app_actions.mbt 拆出来：这一族都以「动作发出去了，回执怎么落地」为主，\n// 与实例那一条链分开读更清楚。只搬位置，函数体一个字没改。\n

///|
/// 删除的参数：只有 profile 这一项。
///
/// 二次确认串**不在这里** —— 它在 body 顶层，由 delete_confirm_of 给出、走
/// action_body_with_confirm。以前那个串被塞进 params，而后端读的是顶层，
/// 结果是硬删永远以 bad-params 告终（实测复现过 ✗）。
fn delete_pairs(model : Model, row_id : String) -> Array[(String, String)] {
  match find_row(model.rows, row_id) {
    None => []
    Some(row) => profile_pairs(row)
  }
}

///|
/// 删除要不要带二次确认串，带的话是什么 —— **按确认框打开那一刻记下来的模式**（§13.2）。
///
/// 契约第一节：safety.deleteToTrash=false 时删除是硬删，**body 顶层**必须带 "confirm":"DELETE"。
/// 认的是 model.confirm_hard（点开确认框时定下的那一格），不是此刻的设置页读数：
/// 框开着的这几秒里设置被改了，请求该照当时那个决定发，而不是悄悄换一种删法。
///
/// 这个串走 action_body_with_confirm（放顶层），不再塞进 params：
/// 后端是从顶层读的（handle_action 里的 json_field(json, "confirm")），
/// 塞进 params 的结果是硬删永远以 bad-params 告终 —— 这条实测复现过 ✗
fn delete_confirm_of(model : Model) -> String {
  if model.confirm_hard {
    "DELETE"
  } else {
    ""
  }
}

///|
/// 点下删除按钮那一刻是哪种模式：按住 Shift（读文档级打的那个标记），**或**回收站关着。
///
/// 由 DOM 监听器同步调用（见 view_overview 的 delete_click）：Shift 状态不进 model、
/// 不走状态回环 —— CSS 那边也是按同一个标记直接换色换字（§13.2）。
fn delete_mode_now(model : Model) -> Bool {
  if js_shift_held() {
    true
  } else {
    // 回收站没开时删除就是彻底删除，不管按没按 Shift；读不到设置也按可能要硬删处理
    delete_to_trash_of(model) != Some(true)
  }
}

///|
/// 回收站条目对应的 profile 名。
///
/// 恢复 / 彻底删除的提示条里用得到：目录名（zz-trash-a-1792071553106）是磁盘上的东西，
/// 提示条该说人话（zz-trash-a）。读数里没有这一条时退回目录名 —— 不编一个名字出来。
fn trash_profile_of(model : Model, dir : String) -> String {
  match model.console {
    None => dir
    Some(facts) => {
      let mut found = dir
      for entry in facts.trash {
        if entry.dir == dir {
          found = entry.profile
        }
      }
      found
    }
  }
}

///|
/// 关于页「用这一版」：把这一份 dsh 指定成起实例用的那一版（POST pin-dsh）。
///
/// 这条动作不挂在任何一行实例上：row_id 给空串，回执按动作名分派（见 update 里的 HttpDone），
/// 不走总览页那条提示条 —— 那一页说的是实例，这里说的是安装。
fn pin_dsh_version(
  model : Model,
  dir : String,
  version : String,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  if dir == "" {
    return (
      notice_err(model, "这一份 dsh 的目录没读到，没法指定（读数里那一格是空的）"),
      @cmd.none,
    )
  }
  let params = params_of([("dir", json_text_literal(dir))])
  (
    notice_clear({ ..model, dsh_pin_busy: dir }),
    action_cmd("", "pin-dsh", version, "用这一版", action_body("pin-dsh", params), emit),
  )
}

///|
/// 关于页「回到自动」：撤掉指定（POST unpin-dsh，没有参数）。
fn unpin_dsh_version(model : Model, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  (
    notice_clear({ ..model, dsh_pin_busy: "auto" }),
    action_cmd("", "unpin-dsh", "", "回到自动", action_body("unpin-dsh", "{}"), emit),
  )
}

///|
/// 「用这一版 / 回到自动」的回执：把结果写进关于页那一格，并重读 runtime 读数。
///
/// **重读就是这条动作的正文**：能不能指定、指定之后生效的是哪一版，都由
/// /api/local/runtime 说了算（dshVersion / dshPinState / dshCandidates）。
/// 本地不猜结果 —— 猜一个「已切换」出去，重读完界面又变回去，比不换更糟。
fn dsh_pin_settled(
  model : Model,
  action : String,
  ok : Bool,
  note : String,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let text = if ok {
    note
  } else if action == "pin-dsh" {
    "没能指定这个版本：" + note
  } else {
    "没能回到自动：" + note
  }
  (
    notice_put({ ..model, dsh_pin_busy: "" }, ok, text, ""),
    if ok { load_runtime(emit) } else { @cmd.none },
  )
}


// ── 维护页（作业台） ─────────────────────────────────────────
//
// 这一页的动作全部走 POST /api/local/action，回执带着整份作业（outcome.job）。
// 页面只在**回执之后**改文案，不本地猜「成功了」：作业到底到哪一步，由后端写下的
// 那份记录说了算（下一次 console 读数回来也是同一份事实）。

///|
/// 动作名 → 给使用者看的名字（失败提示的句首用它，不把内部动作名摆到正文里）。
fn job_action_label(action : String) -> String {
  match action {
    "job-start" => "开始作业"
    "job-install" => "安装新版本"
    "job-trial" => "把新版本跑起来"
    "job-verdict" => "记下结论"
    "job-trial-stop" => "停掉试跑实例"
    "job-commit" => "切到新版本"
    "job-cleanup-preview" => "清理预演"
    "job-cleanup" => "清理旧版本"
    "job-abort" => "中止作业"
    _ => "这一步"
  }
}

///|
/// 回执里的 outcome 对象（成功才是 Some）。
fn job_outcome_of(res : Result[String, Error]) -> Map[String, Json]? {
  match res {
    Err(_) => None
    Ok(text) => {
      let got = parse_http_result(text)
      if got.status < 200 || got.status >= 300 {
        return None
      }
      match open_envelope(got.body) {
        Ok(data) =>
          match data.get("outcome") {
            Some(Json::Object(outcome)) => Some(outcome)
            _ => None
          }
        Err(_) => None
      }
    }
  }
}

///|
/// 回执里那条作业的 id（没有给空串）。
fn job_id_of(outcome : Map[String, Json]?) -> String {
  match outcome {
    Some(o) =>
      match o.get("job") {
        Some(Json::Object(job)) => str_field(job, "id")
        _ => ""
      }
    None => ""
  }
}

///|
/// 成功的正文。**只写结论**（命令、路径、输出尾部都收进悬停）：
/// 这一页的正文要能一眼看懂「现在到哪一步了」，不是给人读日志的。
fn job_success_text(action : String, outcome : Map[String, Json]?) -> String {
  let o = match outcome {
    Some(o) => o
    None => Map([])
  }
  match action {
    "job-start" => "作业已创建，第 1 步（锁定当前版本）已经做完。"
    "job-install" =>
      if !bool_field(o, "executed") {
        "预演完成：还没有装任何东西。"
      } else {
        match int_field(o, "exitCode") {
          Some(0) => "安装命令跑完了（退出码 0）。下一步把新版本跑起来。"
          Some(code) => "安装命令退出码 " + code.to_string() + "，这一步记为不通过。"
          None => "安装命令没跑完，这一步记为不通过。"
        }
      }
    "job-trial" =>
      if bool_field(o, "started") {
        let url = str_field(o, "url")
        "新版本在一次性 home 里起来了：" + (if url == "" { "见下面的地址" } else { url }) +
        "。你去用一用，收尾时这只实例会停掉、这份 home 会删掉。"
      } else {
        "新版本没跑起来，这一步记为不通过。原因在悬停里。"
      }
    "job-verdict" =>
      match str_field(o, "verdict") {
        "good" => "记下了：好用。下一步是切到新版本。"
        "bad" =>
          "回滚了：起实例还是用 " + str_field(o, "anchorVersion") +
          "；新装的那份留着没删，要删单独清理"
        "later" => "记下了：先放着。试跑实例、一次性 home 与版本指定都没动。"
        _ => "结论记下了。"
      }
    "job-trial-stop" => "试跑实例已经收掉了，一次性 home 也删了；作业还停在这一步。"
    "job-commit" =>
      "已经切到 " + str_field(o, "version") +
      "；起实例会用这一版。旧版本留着当回滚锚，确认稳定后再清理"
    "job-cleanup-preview" => "预演完成：这一步会删掉旧版本的包目录，还没有删。"
    "job-cleanup" =>
      if bool_field(o, "deleted") {
        "旧版本的包目录已删掉。"
      } else {
        "旧版本的包目录本来就不在了，这一步没有可删的。"
      }
    "job-abort" => "作业已中止，试跑实例与一次性 home 都收掉了；已经做完的步骤都留着。"
    _ => "这一步完成了。"
  }
}

///|
/// POST 一条作业动作，回执走 JobDone）。
fn job_cmd(action : String, params : String, emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.attempt(
    fn(res : Result[String, Error]) { emit(JobDone(action, res)) },
    async fn() {
      let text : String = js_http_call(
        "POST",
        "/api/local/action",
        action_body(action, params),
        write_headers(),
      ).wait().cast()
      text
    },
  )
}

///|
/// 开始一条作业。目标版本必须是使用者填的 —— 留空就在这里拦住，
/// 不拿「本机装着的最新一份」顶上（§4：版本由前端选，别在后端猜；这里连前端也不猜）。
fn job_start_command(model : Model, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  let version = model.job_version.trim().to_owned()
  if version == "" {
    return (notice_err(model, "先填上要装的目标版本，再点开始。"), @cmd.none)
  }
  // profile 必填（后端也拦）：试跑要从这只 profile 复制一份配置到一次性 home（§9.4）。
  // 名称取自「在跑的 → web → 第一份」里第一只**可用**的，与页面下拉里显示的是同一个函数。
  let profile = job_profile_choice(model)
  if profile == "" {
    let text = if job_profile_names(model).length() == 0 {
      "先选一只试跑用的 profile：这一页没读到任何 profile 读数。"
    } else {
      "没有可用的试跑 profile：这一只配置要么读不到，要么起不了网页实例。"
    }
    return (notice_err(model, text), @cmd.none)
  }
  let params = params_of([
    ("kind", json_text_literal("upgrade-dsh")),
    ("version", json_text_literal(version)),
    ("profile", json_text_literal(profile)),
  ])
  (notice_clear({ ..model, job_busy: "new" }), job_cmd("job-start", params, emit))
}

///|
/// 某条作业的一步。安装与清理的「确认执行」必须在**这一次会话里先预演过**：
/// 没预演就点执行，这里当场拦住，不把请求发出去 —— 会后端一次 conflict 也能挡住，
/// 但那要等一个来回，而且用户会以为「点了没反应」。
fn job_step_command(
  model : Model,
  id : String,
  step : String,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  if id == "" {
    return (model, @cmd.none)
  }
  let refuse = fn(text : String) { (notice_err(model, text), @cmd.none) }
  let params_with = fn(confirm_key : String, confirm_value : String) {
    params_of([("id", json_text_literal(id)), (confirm_key, confirm_value)])
  }
  match step {
    "install-preview" => (
      notice_clear({ ..model, job_busy: id }),
      job_cmd("job-install", params_with("confirm", "false"), emit),
    )
    "install-confirm" =>
      if model.job_previewed != id || model.job_previewed_step != "install" {
        refuse("先点「预演这一步」，看过确切命令再确认执行。")
      } else {
        (notice_clear({ ..model, job_busy: id }), job_cmd("job-install", params_with("confirm", "true"), emit))
      }
    "trial" => (
      notice_clear({ ..model, job_busy: id }),
      job_cmd("job-trial", params_of([("id", json_text_literal(id))]), emit),
    )
    "verdict-good" => (
      notice_clear({ ..model, job_busy: id }),
      job_cmd(
        "job-verdict",
        params_of([("id", json_text_literal(id)), ("verdict", json_text_literal("good"))]),
        emit,
      ),
    )
    "verdict-bad" => (
      notice_clear({ ..model, job_busy: id }),
      job_cmd(
        "job-verdict",
        params_of([("id", json_text_literal(id)), ("verdict", json_text_literal("bad"))]),
        emit,
      ),
    )
    "verdict-later" => (
      notice_clear({ ..model, job_busy: id }),
      job_cmd(
        "job-verdict",
        params_of([("id", json_text_literal(id)), ("verdict", json_text_literal("later"))]),
        emit,
      ),
    )
    "trial-stop" => (
      notice_clear({ ..model, job_busy: id }),
      job_cmd("job-trial-stop", params_of([("id", json_text_literal(id))]), emit),
    )
    "commit" => (
      notice_clear({ ..model, job_busy: id }),
      job_cmd("job-commit", params_of([("id", json_text_literal(id))]), emit),
    )
    "cleanup-preview" => (
      notice_clear({ ..model, job_busy: id }),
      job_cmd("job-cleanup-preview", params_of([("id", json_text_literal(id))]), emit),
    )
    "cleanup" =>
      if model.job_previewed != id || model.job_previewed_step != "cleanup" {
        refuse("先点「清理旧版本」，看过会删掉什么再确认执行。")
      } else {
        (notice_clear({ ..model, job_busy: id }), job_cmd("job-cleanup", params_with("confirm", "DELETE"), emit))
      }
    "abort" => (
      notice_clear({ ..model, job_busy: id }),
      job_cmd("job-abort", params_of([("id", json_text_literal(id))]), emit),
    )
    _ => refuse("认不出这一步，没有发出请求。")
  }
}

///|
/// 作业动作的回执。
///
/// 出口分两处、各说一半（§14.3）：
///   - 全局提示：一条结论（成功 toast / 失败常驻），切到哪一页都看得见
///   - 作业卡：这次动作的**细节**（确切命令 / 包目录 / 输出尾部），跟着那条作业留在页面上
/// 两处的话不重叠，所以同一句话不会在页面上出现两遍（§14.4）。
/// 成功之后重读 console —— 作业的真实状态在那份读数里，不在本地猜。
fn job_settled(
  model : Model,
  action : String,
  res : Result[String, Error],
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let (ok, note) = interpret_http(res)
  let outcome = job_outcome_of(res)
  if !ok {
    return (
      // 失败不往作业卡里写细节：原因在常驻提示条上（一句话，§32.1），历史在后端写的步骤表里。
      notice_failed_action(
        { ..model, job_busy: "", job_detail: "", job_detail_for: "" },
        job_action_label(action) + "没成功：" + note,
      ),
      // 失败也可能改过作业记录（例如清理没删掉时那一步被记成 failed）：
      // 重读一次 console，让步骤表与后端那份记录对上，而不是停在动作前的样子。
      load_console(emit),
    )
  }
  let body = job_success_text(action, outcome)
  let job_id = job_id_of(outcome)
  let preview_install = action == "job-install" && !bool_field(match outcome {
    Some(o) => o
    None => Map([])
  }, "executed")
  let preview_cleanup = action == "job-cleanup-preview"
  let mut next = notice_ok(
    { ..model, job_busy: "", job_detail: note, job_detail_for: job_id },
    body,
    "",
  )
  if action == "job-start" {
    next = { ..next, job_version: "" }
    next = {
      ..next,
      job_collapsed: next.job_collapsed.filter(fn(collapsed) { collapsed != job_id }),
    }
  }
  if preview_install {
    next = { ..next, job_previewed: job_id, job_previewed_step: "install" }
  } else if preview_cleanup {
    next = { ..next, job_previewed: job_id, job_previewed_step: "cleanup" }
  } else if model.job_previewed == job_id && job_id != "" {
    // 预演过的那一步已经执行（或作业被别的动作推进了）：这一份预演作废。
    // 留着它会让下一次「确认执行」拿一份旧的预演去放行。
    next = { ..next, job_previewed: "", job_previewed_step: "" }
  }
  // 试跑起了一只实例、收掉它、切了版本 —— 这三类动作会把「本机有哪些实例 / 哪一版生效」
  // 一起改掉，所以连 profiles 与 instances 读数一起重读（否则总览页还停在动作前）。
  if action == "job-trial" || action == "job-trial-stop" || action == "job-verdict" {
    refresh_readings(next, emit)
  } else if action == "job-commit" {
    let (after, cmd) = refresh_readings(next, emit)
    (after, @cmd.batch([cmd, load_runtime(emit)]))
  } else {
    (next, load_console(emit))
  }
}

///|
/// 备注保存的回执。两条路分开：
///   成功 —— 关框（位置与触发元素都留着），重读 profiles，卡上那一行由读数给出；
///           提示条里那句 note 是后端写的「这次到底做了什么」。
///   失败 —— **框不关**，后端给的原因写进框内，用户改一改就能再存一次。
fn note_settled(
  model : Model,
  res : Result[String, Error],
  name : String,
  note : String,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let return_id = model.note_return
  let base = { ..model, note_saving: "" }
  let (ok, _) = interpret_http(res)
  if ok {
    let (text, hint) = note_receipt(name, note, res)
    let closed = notice_ok(
      { ..base, note_open: "", note_draft: "", note_error: "" },
      text,
      hint,
    )
    let (next, cmd) = refresh_readings(closed, emit)
    (next, @cmd.batch([cmd, focus_after_render(return_id)]))
  } else {
    ({ ..base, note_error: note }, @cmd.none)
  }
}

///|
/// 「＋新建实例」这一枪的回执（design/design-fixes.md §19.1）。
///
/// 成：回执写新名字与它隔离到哪儿，框关掉，重读读数；新卡要等读数落地才有，
/// 所以焦点不在这里发 —— 把名字记进 new_focus，由 rebuild 在列表拼好之后送过去。
/// 败：**框不关**，后端原话写在框里。用户改个名字就能再点一次创建；
/// 关掉的话那句原因就成了一闪而过的提示条。
///
/// 两条路都不在本地插一条卡：新卡是重读 profiles 之后由读数给出的，本地先插一条
/// 会让「看着有、其实没派生」和「派生成功」长得一样。
fn new_instance_settled(
  model : Model,
  res : Result[String, Error],
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let (ok, note) = interpret_http(res)
  if !ok {
    return ({ ..model, new_busy: false, new_error: note }, @cmd.none)
  }
  let outcome = match outcome_of(res) {
    Some(fields) => fields
    None =>
      return (
        { ..model, new_busy: false, new_error: "回执里没有 outcome，这一版认不出派生结果" },
        @cmd.none,
      )
  }
  // 新名字以**回执**为准：重名时后端会自动加序号，前端猜不出它加到几
  let created = str_field(outcome, "newName")
  let source = str_field(outcome, "profile")
  let home = obj_field(outcome, "home")
  let home_path = str_field(home, "path")
  let home_error = str_field(home, "error")
  let name = if created == "" { model.new_name_draft.trim().to_owned() } else { created }
  // 隔离建成与没建成是两件事：没建成时不能说「已隔离到」，那是假报
  let text = if home_path != "" {
    "已创建 " + name + "（已隔离到 " + home_path + "）"
  } else if home_error != "" {
    "已创建 " + name + "（隔离 home 没建成：" + home_error + "，它现在与别的 profile 共用 DSH_HOME）"
  } else {
    "已创建 " + name
  }
  let hint = backend_hint(note) + (if source == "" { "" } else { "\n源配置：" + source })
  let closed = notice_ok(
    {
      ..model,
      new_open: false,
      new_source: "",
      new_base: false,
      new_name_draft: "",
      new_name_dirty: false,
      new_error: "",
      new_busy: false,
      new_focus: name,
    },
    text,
    hint,
  )
  refresh_readings(closed, emit)
}

///|
/// 「从基础实例开始」这一枪的回执（design/design-fixes.md 第 20 节）。
///
/// 成：回执照规格写「已从基础模板新建 <名字>（已隔离到 <路径>）」，隔离没建成时那一支
/// 照实说「共用 DSH_HOME」；框关掉，重读读数，新卡出现之后焦点再送过去（与派生同一套）。
/// 败：**框不关**，后端原话写在框里 —— 那句原因要能对着改名字（同名 conflict 尤其常见）。
fn base_profile_settled(
  model : Model,
  res : Result[String, Error],
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let (ok, note) = interpret_http(res)
  if !ok {
    return ({ ..model, new_busy: false, new_error: note }, @cmd.none)
  }
  let outcome = match outcome_of(res) {
    Some(fields) => fields
    None =>
      return (
        { ..model, new_busy: false, new_error: "回执里没有 outcome，这一版认不出新建结果" },
        @cmd.none,
      )
  }
  let created = str_field(outcome, "name")
  let home = obj_field(outcome, "home")
  let home_path = str_field(home, "path")
  let home_error = str_field(home, "error")
  let name = if created == "" { model.new_name_draft.trim().to_owned() } else { created }
  // 隔离建成与没建成是两件事：没建成时不能说「已隔离到」，那是假报（与派生那一支同一口径）
  let text = if home_path != "" {
    "已从基础模板新建 " + name + "（已隔离到 " + home_path + "）"
  } else if home_error != "" {
    "已从基础模板新建 " + name + "（隔离 home 没建成：" + home_error +
    "，它与别的 profile 共用 DSH_HOME）"
  } else {
    "已从基础模板新建 " + name
  }
  let closed = notice_ok(
    {
      ..model,
      new_open: false,
      new_source: "",
      new_base: false,
      new_name_draft: "",
      new_name_dirty: false,
      new_error: "",
      new_busy: false,
      new_focus: name,
    },
    text,
    backend_hint(note),
  )
  refresh_readings(closed, emit)
}
