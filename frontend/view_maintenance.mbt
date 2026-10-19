// 维护页（作业台，design/ops-maintenance-jobs.md §2 / §5 第二版）。
//
// 一条作业 = 七个按顺序做的步骤（锁定当前版本 / 安装新版本 / 把新版本跑起来 / 你来试 /
// 切到新版本 / 回滚 / 清理旧版本）。卡片上说清四件事：标题、状态、第几步、开始于；
// 展开之后是步骤表（每步的状态词 + 一句结论），再下面是这一步能点的按钮。
//
// 规格第二版的核心是「验收由使用者自己试」：程序只负责把新版起成一只真用的实例、
// 记下使用者给的结论、按结论切过去或回滚。页面因此有两种「这一步在说什么」：
//   · trial 步   还没起来 → 一颗「把新版本跑起来」；起来了 → 地址与「停掉试跑实例」
//   · verdict 步 地址 + 「试跑实例还在跑（端口 X）」+ 三颗结论按钮
//
// 三档空白分得清（与回收站、日志页同一套纪律）：
//   · console 读数还没回来      → 加载态
//   · 读数回来了、jobs 是空数组 → 空态「还没有作业。」
//   · 读数里没有 jobs 字段      → 第三种：这一版后端还没有作业读数（**不是**「没有作业」）
//
// 正文只给结论：确切命令、包目录、体积、输出尾部都在悬停或证据里（§6）；
// 颜色不作唯一信号：每一步都是「三色灯 + 文字状态词」，两者一起读。

///|
/// 一共有几步（步骤表按 7 步摆；卡片上写「第 n 步 / 共 7 步」）。
let job_step_total : Int = 7

///|
/// 步骤 key → 正文里的名字（§5 第二版的七个名字，一个字都不改）。
fn job_step_label(key : String) -> String {
  match key {
    "lock" => "锁定当前版本"
    "install" => "安装新版本"
    "trial" => "把新版本跑起来"
    "verdict" => "你来试"
    "commit" => "切到新版本"
    "rollback" => "回滚"
    "cleanup" => "清理旧版本"
    _ => key
  }
}

///|
/// 状态词（§5）。不认识的取值写「没验到」——**不能**读成「通过」。
fn job_state_word(state : String) -> String {
  match state {
    "running" => "进行中"
    "passed" => "通过"
    "failed" => "不通过"
    "skipped" => "跳过"
    "not-run" => "未开始"
    _ => "没验到"
  }
}

///|
/// 状态灯的三档色 + 一档「未开始 / 跳过」的灰。灯只是辅助，状态词永远在旁边。
fn job_state_dot(state : String) -> String {
  match state {
    "passed" => "dsh-job-dot ok"
    "failed" => "dsh-job-dot danger"
    "running" => "dsh-job-dot warn"
    _ => "dsh-job-dot idle"
  }
}

///|
/// 作业是不是结束了（done / aborted / rollback）。结束的作业不再摆步骤按钮。
///
/// rollback 也算结束：回滚之后这条作业没有更多能做的事 —— 旧版本正是在用的那一份，
/// 「清理旧版本」那一支被记成「跳过」（新装的那份留着没删）。
fn job_fact_finished(job : JobFact) -> Bool {
  job.step == "done" || job.step == "aborted" || job.step == "rollback"
}

///|
/// 作业整体状态词。**done 才是通过**；没跑完就是进行中，中止与回滚如实说。
fn job_status_word(job : JobFact) -> String {
  if job.step == "done" {
    "通过"
  } else if job.step == "aborted" {
    "已中止"
  } else if job.step == "rollback" {
    "已回滚"
  } else {
    "进行中"
  }
}

///|
/// 第几步（1 起）。done 是 7/7；aborted 停在被打断的那一步；认不出的 step 给 1。
fn job_step_index(job : JobFact) -> Int {
  match job.step {
    "lock" => 1
    "install" => 2
    "trial" => 3
    "verdict" => 4
    "commit" => 5
    "rollback" => 6
    "cleanup" => 7
    "done" => 7
    "aborted" => {
      // 中止时 step 已经变成 aborted 了：从步骤表里找最后一条有结论的那一步。
      // 不用「带下标的 for」：那套语法在不同 MoonBit 版本里写法不一，数一遍更稳。
      let mut at = 1
      let mut index = 0
      for step in job.steps {
        index = index + 1
        if step.state != "not-run" {
          at = index
        }
      }
      at
    }
    _ => 1
  }
}

///|
/// 作业的一句话结果：最后一条有结论的步骤的 note（没有就是空串，不编一句）。
fn job_fact_result(job : JobFact) -> String {
  job_result_line(job.steps)
}

///|
/// 作业卡上的时间：ISO → 本地短格式，读不出来写「—」。
fn job_time_text(iso : String) -> String {
  if iso == "" {
    return "—"
  }
  let short = js_short_time(iso)
  if short == "" {
    "—"
  } else {
    short
  }
}

///|
/// 某一步在读数里的样子（找不到给 None —— 旧作业文件里没有新加的步骤就是这一支）。
fn job_step_fact(job : JobFact, key : String) -> JobStepFact? {
  for step in job.steps {
    if step.key == key {
      return Some(step)
    }
  }
  None
}

///|
/// 某一步现在是什么状态（找不到给空串，界面按「没验到」显示）。
fn job_step_state_of(job : JobFact, key : String) -> String {
  match job_step_fact(job, key) {
    Some(step) => step.state
    None => ""
  }
}

///|
/// 步骤行：灯 + 名字 + 状态词 + 结论；时刻与证据收进悬停。
fn job_step_row(job : JobFact, step : JobStepFact) -> @html.Html {
  let hint_parts : Array[String] = []
  if step.at != "" {
    hint_parts.push("落定于 " + step.at)
  }
  if step.evidence != "" {
    hint_parts.push("证据：" + step.evidence)
  }
  let hint = join_with(hint_parts, " | ")
  let row_attrs = if hint == "" {
    mark("job-step", ["maintenance", "job", job.id, "step", step.key])
  } else {
    mark("job-step", ["maintenance", "job", job.id, "step", step.key]).title(hint)
  }
  @html.div(
    class="dsh-job-step",
    attrs=row_attrs.data_set("state", step.state),
    [
      @html.span(class=job_state_dot(step.state), @html.nothing),
      @html.span(
        class="dsh-job-step-name",
        attrs=mark("job-step-name", ["maintenance", "job", job.id, "step", step.key, "name"]),
        job_step_label(step.key),
      ),
      @html.span(
        class="dsh-job-step-state",
        attrs=mark("job-step-state", ["maintenance", "job", job.id, "step", step.key, "state"]),
        job_state_word(step.state),
      ),
      @html.span(
        class="dsh-job-step-note",
        attrs=mark("job-step-note", ["maintenance", "job", job.id, "step", step.key, "note"]),
        step.note,
      ),
    ],
  )
}

///|
/// 一颗作业按钮。disabled 为真时只是灰掉，仍然留在 DOM 里（焦点与读屏都还找得到它）。
fn job_button(
  label : String,
  name : String,
  parts : Array[String],
  disabled : Bool,
  hint : String,
  msg : Msg,
  emit : @cmd.Emit[Msg],
  primary : Bool,
) -> @html.Html {
  let cls = if primary { "dsh-btn primary" } else { "dsh-btn" }
  let attrs = if hint == "" {
    mark(name, parts)
  } else {
    mark(name, parts).title(hint)
  }
  @html.button(
    class=cls,
    type_="button",
    disabled~,
    attrs~,
    on_click=emit(msg),
    [@html.span(label)],
  )
}

// ── 试跑那一块（§5 第二版）──────────────────────────────────

///|
/// 试跑实例的地址。trial.url 是后端记下来的那一条；万一它不在，用端口拼一条
/// （端口就是「这只实例听在哪」的那个事实，不编别的来源）。
fn job_trial_url(job : JobFact) -> String {
  if job.trial_url != "" {
    job.trial_url
  } else if job.trial_port > 0 {
    "http://127.0.0.1:" + job.trial_port.to_string() + "/"
  } else {
    ""
  }
}

///|
/// 试跑那一块：「新版本起来了：<地址>。你去用一用」，下面跟那句
/// 「试跑跑在一次性的 home 里，你平时那份配置与状态都不动，作业收尾时它会被删掉。」（§9.4）
///
/// 地址本身就是能打开的入口（新标签页），不另加一颗按钮 —— 加一颗「打开」会多出一句
/// §5 里没有的文案，而这一块的重点是「你去用」，不是「点这里」。
/// 那一份临时 home 的路径进悬停：正文只讲「你平时那份不动」，具体落在哪儿给要查的人看。
fn job_trial_block(job : JobFact) -> @html.Html {
  let url = job_trial_url(job)
  if url == "" {
    return @html.nothing
  }
  let home = job.trial_home
  let sub_attrs = if home == "" {
    mark("job-trial-sub", ["maintenance", "job", job.id, "trial", "sub"])
  } else {
    mark("job-trial-sub", ["maintenance", "job", job.id, "trial", "sub"]).title(
      "一次性 home：" + home +
      (if job.trial_profile_copy == "" { "" } else { "；配置拷贝：" + job.trial_profile_copy }),
    )
  }
  @html.div(
    class="dsh-job-trial",
    attrs=mark("job-trial", ["maintenance", "job", job.id, "trial"]),
    [
      @html.p(
        class="dsh-job-trial-line",
        attrs=mark("job-trial-line", ["maintenance", "job", job.id, "trial", "line"]),
        [
          @html.text("新版本起来了："),
          @html.a(
            href=url,
            target=@html.Target::Blank,
            rel="noopener",
            class="dsh-job-trial-link",
            attrs=mark("job-trial-link", ["maintenance", "job", job.id, "trial", "link"])
              .title("在新标签页打开这只试跑实例"),
            [@html.text(url)],
          ),
          @html.text("。你去用一用"),
        ],
      ),
      @html.p(
        class="dsh-job-trial-sub",
        attrs=sub_attrs,
        "试跑跑在一次性的 home 里，你平时那份配置与状态都不动，作业收尾时它会被删掉。",
      ),
    ],
  )
}

///|
/// 试跑实例现在在不在跑（读数里那一格是后端现查进程算出来的）。
/// 还在跑就写端口；已经收掉就如实说收掉了 —— 不拿「试跑实例还在跑」去套一只已经没了的进程。
fn job_trial_status(job : JobFact) -> @html.Html {
  if job.trial_pid <= 0 {
    return @html.nothing
  }
  let text = if job.trial_alive {
    "试跑实例还在跑（端口 " + job.trial_port.to_string() + "）"
  } else {
    "试跑实例已经收掉了（端口 " + job.trial_port.to_string() + "）"
  }
  @html.p(
    class=if job.trial_alive { "dsh-job-trial-state alive" } else { "dsh-job-trial-state" },
    attrs=mark("job-trial-state", ["maintenance", "job", job.id, "trial", "state"])
      .data_set("alive", if job.trial_alive { "true" } else { "false" })
      .title(if job.trial_alive {
        "起好之后不会被作业自动收掉：要收它点「停掉试跑实例」，或者中止作业"
      } else {
        "现在没有试跑实例在跑"
      }),
    text,
  )
}

///|
/// 切过去 / 回滚之后那两句（§5 第二版原话）。
///
/// 这两句按**作业记录**渲染，不按「刚才那次回执」渲染：刷新页面、隔天回来都得读到
/// 同一句话。回执条只负责说「这一步做了什么」，事实在这里。
fn job_receipt(job : JobFact) -> @html.Html {
  let commit_passed = job_step_state_of(job, "commit") == "passed"
  let rollback_passed = job_step_state_of(job, "rollback") == "passed"
  let text = if rollback_passed {
    "回滚了：起实例还是用 " + job.anchor_version + "；新装的那份留着没删，要删单独清理"
  } else if commit_passed {
    "已经切到 " + job.target_version + "；起实例会用这一版。旧版本留着当回滚锚，确认稳定后再清理"
  } else {
    ""
  }
  if text == "" {
    return @html.nothing
  }
  @html.p(
    class=if rollback_passed { "dsh-job-receipt rollback" } else { "dsh-job-receipt" },
    attrs=mark("job-receipt", ["maintenance", "job", job.id, "receipt"]),
    text,
  )
}

// ── 新作业表单 ──────────────────────────────────────────────

///|
/// 本机全部 profile 的读数（读不到就是空表）。
fn job_profile_facts(model : Model) -> Array[ProfileFact] {
  let facts : Array[ProfileFact] = []
  match model.profiles {
    Some(got) =>
      for profile in got.profiles {
        if profile.name != "" {
          facts.push(profile)
        }
      }
    None => ()
  }
  facts
}

///|
/// 可选的 profile 名（判断「这一页有没有 profile 读数」用）。
fn job_profile_names(model : Model) -> Array[String] {
  let names : Array[String] = []
  for profile in job_profile_facts(model) {
    names.push(profile.name)
  }
  names
}

///|
/// 一只 profile 能不能拿来试跑：(可用, 原因)（§9.3）。
///
/// 只看两条事实，两条都由后端给（前端不自己翻 package.json）：
///   1. 配置读不到（package.json 不在 / 读不动）→ 不可用
///   2. dsh.profile.bundles 里没有 @deepseek-ai/dsh-web-app → 不可用（命令行型，没有网页入口）
/// 缺包**不算不可用**：那一条单独注明「缺 N 个包，可能起不来」，别混进这里。
///
/// 字段不在（这一版后端没给）时按可用处理：宁可让试跑自己去撞失败，
/// 也不拿一个说不清的读数把一份其实能用的配置灰掉。
fn job_profile_usable(profile : ProfileFact) -> (Bool, String) {
  match profile.package_json_ok {
    Some(false) => (false, "读不到这只配置")
    _ =>
      match profile.web_app {
        Some(false) => (false, "这只配置起的是命令行型，没有网页入口")
        _ => (true, "")
      }
  }
}

///|
/// 没亲手选过时的默认 profile：在跑的那一只 → web → 第一份（§9.3 的口径）。
/// 为什么先挑「在跑的」：使用者试新版，试的通常就是他平时开着的那个 profile。
/// 不可用的跳过 —— 挑一只起不了网页实例的，等于把「开始」变成一次注定失败的出击。
fn job_profile_default(model : Model) -> String {
  let facts = job_profile_facts(model)
  let usable : Array[String] = []
  for profile in facts {
    let (ok, _why) = job_profile_usable(profile)
    if ok {
      usable.push(profile.name)
    }
  }
  if usable.length() == 0 {
    return ""
  }
  match model.instances {
    Some(got) =>
      for item in got.instances {
        match item.profile {
          Some(name) =>
            if usable.contains(name) {
              return name
            }
          None => ()
        }
      }
    None => ()
  }
  if usable.contains("web") {
    return "web"
  }
  usable[0]
}

///|
/// 这一次「开始」到底会用哪一只 profile：亲手选过、那一份还在且可用就用它，否则按默认推。
fn job_profile_choice(model : Model) -> String {
  for profile in job_profile_facts(model) {
    if profile.name == model.job_profile {
      let (ok, _why) = job_profile_usable(profile)
      if ok {
        return profile.name
      }
    }
  }
  job_profile_default(model)
}

///|
/// 配置侧栏里的一张卡要的几格（§12.4）：名字、备注、状态灯与状态词、缺包数、
/// home 归属、可用性与原因、在不在跑。
///
/// 数据来自**总览那一套行**（见 job_profile_picks）：这里只把行摊成卡片要的几格，
/// 不重新判谁在跑、也不重新排一次序。
///
/// 为什么状态灯与状态词要从行里来、不从 profile 读数重算：运行中那一只的灯是实例
/// 读数给的（绿 = 签名探测通过），拿 profiles 读数重算只会把它说成「没有在跑」。
priv struct ProfilePick {
  name : String
  note : String
  note_source : String
  light : Light
  light_reason : String
  light_basis : String
  missing : Int
  missing_names : String
  home_kind : String
  home_path : String
  running : Bool
  usable : Bool
  why : String
}

///|
/// 按名字找一只 profile 的读数（找不到给 None）。
fn job_profile_fact_of(model : Model, name : String) -> ProfileFact? {
  for fact in job_profile_facts(model) {
    if fact.name == name {
      return Some(fact)
    }
  }
  None
}

///|
/// 把「总览那一行」与「它的 profile 读数」摊成一张卡。
///
/// 行给的是：在不在跑、状态灯与它那句话、备注、home 归属（试跑那一档只有实例读数说得出）。
/// 读数给的是：可用性判据（packageJson / webApp）、缺几个包。
/// 两边各缺一半时按有的那半说：行不在（读数里有、行里没有）就走 profile_light 判灯，
/// 读数不在（行在、读数没配上）就不判可用性 —— 宁可让试跑自己去撞失败，也不凭一个
/// 说不清的读数把一份其实能用的配置灰掉（与 job_profile_usable 同一口径）。
fn job_profile_pick(row : Row?, fact : ProfileFact?) -> ProfilePick {
  let (usable, why) = match fact {
    Some(item) => job_profile_usable(item)
    None => (true, "")
  }
  let (name, light, light_reason, light_basis, running) = match row {
    Some(item) => {
      let name = match item.profile_name {
        Some(n) => n
        None => item.name
      }
      (name, item.light, item.light_reason, item.light_basis, item.status is Running)
    }
    None =>
      match fact {
        Some(item) => {
          let (light, reason, basis) = profile_light(item)
          (item.name, light, reason, basis, false)
        }
        None => ("", LightUnknown, "", "", false)
      }
  }
  let (missing, missing_names) = match fact {
    Some(item) => (item.bundles.missing.length(), join_with(item.bundles.missing, "、"))
    None => (0, "")
  }
  let (note, note_source) = match row {
    Some(item) =>
      if item.user_note != "" || fact is None {
        (item.user_note, item.user_note_source)
      } else {
        match fact {
          Some(f) => (f.note, f.note_source)
          None => (item.user_note, item.user_note_source)
        }
      }
    None =>
      match fact {
        Some(item) => (item.note, item.note_source)
        None => ("", "")
      }
  }
  let (home_kind, home_path) = match row {
    Some(item) => (item.home_kind, item.home_path)
    None =>
      match fact {
        Some(item) => (item.home_kind, item.home_path)
        None => ("", "")
      }
  }
  {
    name,
    note,
    note_source,
    light,
    light_reason,
    light_basis,
    missing,
    missing_names,
    home_kind,
    home_path,
    running,
    usable,
    why,
  }
}

///|
/// 配置侧栏要摆的两组卡（§12.4）：先运行中、再停放。
///
/// 顺序**照总览那一份行**：display_groups 已经按 order.json 排过（组内），这里原样取，
/// 不另排一遍 —— 侧栏里看到的次序与总览上摆的次序必须是同一个。
///
/// 行里没有、读数里有的那几只（读数配不上行：home 对不上这类）补在停放组末尾：
/// 一只 profile 不该因为读数没配上就在侧栏里人间蒸发。
fn job_profile_picks(model : Model) -> (Array[ProfilePick], Array[ProfilePick]) {
  let (running_rows, stopped_rows) = display_groups(model)
  let running : Array[ProfilePick] = []
  let stopped : Array[ProfilePick] = []
  let seen : Array[String] = []
  // 只收**读数里有这一只**的行：试跑按 profile 名从 DSH_HOME 的 profiles/ 里找，
  // 别的 home 里同名的那一只在这里选不了（选完表单也会退回默认那一只）。
  // 那种行（实例在别的 home 里跑着）照样出现在总览上，但这里不摆一个点了没用的卡。
  for row in running_rows {
    match row.profile_name {
      Some(name) => match job_profile_fact_of(model, name) {
        Some(fact) =>
          if !seen.contains(name) {
            running.push(job_profile_pick(Some(row), Some(fact)))
            seen.push(name)
          }
        None => ()
      }
      None => ()
    }
  }
  for row in stopped_rows {
    match row.profile_name {
      Some(name) => match job_profile_fact_of(model, name) {
        Some(fact) =>
          if !seen.contains(name) {
            stopped.push(job_profile_pick(Some(row), Some(fact)))
            seen.push(name)
          }
        None => ()
      }
      None => ()
    }
  }
  for fact in job_profile_facts(model) {
    if !seen.contains(fact.name) {
      stopped.push(job_profile_pick(None, Some(fact)))
      seen.push(fact.name)
    }
  }
  (running, stopped)
}

///|
/// 一张卡上的「配置 home」小字。读数里没给 home 那一项时写「读不到」，
/// 不按控制台自己的 DSH_HOME 猜一个归属出来（与抽屉那一格同一口径）。
fn job_pick_home_text(pick : ProfilePick) -> String {
  if pick.home_kind == "" {
    "配置 home：读不到"
  } else {
    "配置 home：" + home_kind_text(pick.home_kind)
  }
}

///|
/// 第一张可点的 profile 卡是哪一只（打开侧栏时焦点落在它身上，§10.3）。
/// 顺序就是侧栏里的显示顺序（运行中那一组在前）：「第一张」在界面上是看得见的那一条。
fn job_profile_first_usable(model : Model) -> String {
  let (running, stopped) = job_profile_picks(model)
  for pick in running {
    if pick.usable {
      return pick.name
    }
  }
  for pick in stopped {
    if pick.usable {
      return pick.name
    }
  }
  ""
}

///|
/// 表单里「试跑用配置」那一格（§10.3）：一行「当前配置」+ 一颗「选择配置」按钮。
///
/// 候选不再是常驻下拉：点按钮开右侧侧栏，里面按总览的卡片样式摆本机全部 profile。
/// 这一格只负责说「现在用的是谁」——没选过（也没有可用的）就写「未选择」。
fn job_profile_current(
  model : Model,
  disabled : Bool,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let choice = job_profile_choice(model)
  let value = if choice == "" { "未选择" } else { choice }
  @html.div(class="dsh-job-current", [
    @html.span(
      class="dsh-job-current-label",
      attrs=mark("job-profile-current-label", ["maintenance", "start", "profile-current-label"]),
      "当前配置",
    ),
    @html.span(
      class="dsh-job-current-value",
      attrs=mark("job-profile-current", ["maintenance", "start", "profile-current"])
        .data_set("state", if choice == "" { "empty" } else { "picked" }),
      value,
    ),
    @html.button(
      id=profile_choose_id(),
      class="dsh-btn dsh-job-choose",
      type_="button",
      disabled~,
      attrs=mark("job-profile-choose", ["maintenance", "start", "profile-choose"])
        .aria_label("选择试跑用配置"),
      on_click=emit(ProfileSidebarOpen),
      [@html.span("选择配置")],
    ),
  ])
}

///|
/// 一条 data-name 路径：前缀 + 这一格的尾巴。
/// 两张卡（选择配置 / 替换用源）共用一份画法，差别之一就是前缀，所以路径得拼。
fn mark_path(marks : Array[String], tail : Array[String]) -> Array[String] {
  let out : Array[String] = []
  for m in marks {
    out.push(m)
  }
  for t in tail {
    out.push(t)
  }
  out
}

///|
/// 一张 profile 卡（**复用总览卡片那一套样式**：.dsh-case，含图标位与三行）。
///
/// 两处共用这一份画法：「选择配置」（维护页的试跑用配置）与
/// 「用另一只配置替换这一只」（总览抽屉里的整体替换）。差别只在四件事：
/// 点下去发哪条消息、data-name 前缀、挂不挂「当前配置」那枚标记、aria 那句话。
///
/// 卡上五样（§12.4）：名字、备注（没有就写「没有备注」）、状态灯 + 状态词、缺包数、
/// home 归属；不可用的卡另写一行原因，并整张置灰、不可点、从 Tab 序列里摘掉。
/// 运行中的卡带「在跑」—— 标记都是文字，不只靠颜色。
///
/// 缺包**不算不可用**（§9.3）：卡照旧能点，「缺 N 个包」只是如实摆着的读数。
fn profile_pick_card(
  pick : ProfilePick,
  card_id : String,
  mark_prefix : String,
  marks : Array[String],
  selected_text : String,
  aria_ok : String,
  aria_bad : String,
  picked : (String) -> Msg,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let ok = pick.usable
  let why = pick.why
  let head : Array[@html.Html] = [
    @html.span(
      class="dsh-name",
      attrs=mark(mark_prefix + "-card-name", mark_path(marks, [pick.name, "name"])),
      pick.name,
    ),
  ]
  if pick.running {
    head.push(
      @html.span(
        class="dsh-profile-card-mark running",
        attrs=mark(mark_prefix + "-card-running", mark_path(marks, [pick.name, "running"])),
        "在跑",
      ),
    )
  }
  if selected_text != "" {
    head.push(
      @html.span(
        class="dsh-profile-card-mark selected",
        attrs=mark(mark_prefix + "-card-mark", mark_path(marks, [pick.name, "mark"])),
        selected_text,
      ),
    )
  }
  // 备注那一行：有就写备注（人写的，带左侧细线，与总览同一副样子）；
  // 没有就写「没有备注」。空着与「没有」在这里是两件事，而这一行是卡上的固定一格。
  let note_line = if pick.note != "" {
    @html.span(
      class="dsh-card-note",
      attrs=mark(mark_prefix + "-card-note", mark_path(marks, [pick.name, "note"])).title(
        if pick.note_source == "" { pick.note } else { pick.note + "\n（" + pick.note_source + "）" },
      ),
      [@html.span(class="dsh-card-note-text", pick.note)],
    )
  } else {
    @html.span(
      class="dsh-profile-card-sub dsh-profile-card-nonote",
      attrs=mark(mark_prefix + "-card-nonote", mark_path(marks, [pick.name, "nonote"])),
      "没有备注",
    )
  }
  // 读数那一行：状态灯 + 状态词 + 缺包数 + home 归属。灯与词永远并排，颜色不作唯一信号。
  let light_attrs = mark(mark_prefix + "-card-light", mark_path(marks, [pick.name, "light"]))
    .data_set("state", light_key(pick.light))
    .role("img")
    .aria_label(light_label(pick.light))
  let light_attrs = if pick.light_basis == "" {
    light_attrs.title(pick.light_reason)
  } else {
    light_attrs.title(pick.light_reason + "\n" + pick.light_basis)
  }
  let missing_text = "缺 " + pick.missing.to_string() + " 个包"
  let missing_attrs = mark(mark_prefix + "-card-missing", mark_path(marks, [pick.name, "missing"]))
  let missing_attrs = if pick.missing_names == "" {
    missing_attrs
  } else {
    missing_attrs.title("缺的包：" + pick.missing_names)
  }
  let home_attrs = mark(mark_prefix + "-card-home", mark_path(marks, [pick.name, "home"]))
  let home_attrs = if pick.home_path == "" {
    home_attrs
  } else {
    home_attrs.title(pick.home_path)
  }
  let meta : Array[@html.Html] = [
    @html.span(class="dsh-dot " + light_class(pick.light), attrs=light_attrs, @html.nothing),
    @html.span(
      class="dsh-profile-card-state",
      attrs=mark(mark_prefix + "-card-state", mark_path(marks, [pick.name, "state"]))
        .data_set("state", light_key(pick.light)),
      light_label(pick.light),
    ),
    @html.span(class="dsh-profile-card-missing", attrs=missing_attrs, missing_text),
    @html.span(
      class="dsh-profile-card-home",
      attrs=home_attrs,
      job_pick_home_text(pick),
    ),
  ]
  let lines : Array[@html.Html] = [
    @html.div(class="dsh-case-head", head),
    note_line,
    @html.div(class="dsh-profile-card-meta", meta),
  ]
  if !ok {
    lines.push(
      @html.span(
        class="dsh-profile-card-sub unusable",
        attrs=mark(mark_prefix + "-card-why", mark_path(marks, [pick.name, "why"])),
        why,
      ),
    )
  }
  let click = if ok {
    emit(picked(pick.name))
  } else {
    @cmd.none
  }
  @html.article(
    id=card_id,
    class=if ok { "dsh-case dsh-profile-card" } else { "dsh-case dsh-profile-card disabled" },
    attrs=mark(mark_prefix + "-card", mark_path(marks, [pick.name]))
      .data_set("usable", if ok { "true" } else { "false" })
      .data_set("group", if pick.running { "running" } else { "stopped" })
      .role("button")
      .tabindex(if ok { 0 } else { -1 })
      .aria_disabled(if ok { "false" } else { "true" })
      .aria_label(if ok { aria_ok } else { aria_bad })
      .on_click(fn(_event) { click })
      .on_keydown(fn(event) {
        if ok && (event.key() == "Enter" || event.key() == " ") {
          emit(picked(pick.name))
        } else {
          @cmd.none
        }
      }),
    [
      @html.span(class="dsh-tile-slot", [
        @html.span(
          class=if pick.running { "dsh-tile accent" } else { "dsh-tile violet" },
          [icon("cube-outline", size=20)],
        ),
      ]),
      @html.div(class="dsh-case-body", lines),
    ],
  )
}

///|
/// 「选择配置」那一栏里的一张卡：点下去回填试跑用配置。
fn job_profile_card(model : Model, pick : ProfilePick, emit : @cmd.Emit[Msg]) -> @html.Html {
  let choice = job_profile_choice(model)
  let selected = pick.name == choice
  let ok = pick.usable
  let aria = if ok { "试跑用 " + pick.name } else { pick.name + " 不可用：" + pick.why }
  profile_pick_card(
    pick,
    job_profile_card_id(pick.name),
    "job-profile",
    ["maintenance", "profile-sidebar"],
    if selected { "当前配置" } else { "" },
    aria,
    aria,
    fn(name) { JobProfilePicked(name) },
    emit,
  )
}

///|
/// 整体替换那一栏里的一张源卡：点下去选它当源（点完在同一侧栏里出差异预览）。
/// 与「选择配置」是**同一份画法**（profile_pick_card），只是换一套 data-name 与消息。
fn promote_source_card(pick : ProfilePick, emit : @cmd.Emit[Msg]) -> @html.Html {
  let ok = pick.usable
  let aria = if ok { "用 " + pick.name + " 的配置替换" } else { pick.name + " 不可用：" + pick.why }
  profile_pick_card(
    pick,
    promote_card_id(pick.name),
    "promote",
    ["overview", "promote-sidebar"],
    "",
    aria,
    aria,
    fn(name) { PromoteSourcePicked(name) },
    emit,
  )
}

///|
/// 侧栏里的一组卡：分组头（与总览同一个说法）+ 卡片。
///
/// 分组头用的是总览那两个标题（「当前运行的实例」/「已停止的实例」）：这一组摆的就是
/// 那两组的行，换个说法会让人以为侧栏里是另一批东西。
fn job_profile_group(
  key : String,
  title : String,
  picks : Array[ProfilePick],
  model : Model,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let cards : Array[@html.Html] = []
  for pick in picks {
    cards.push(job_profile_card(model, pick, emit))
  }
  @html.div(
    class="dsh-profile-sidebar-group",
    attrs=mark("job-profile-group", ["maintenance", "profile-sidebar", "group", key])
      .data_set("group", key),
    [
      @html.h3(
        class="dsh-profile-sidebar-group-title",
        attrs=mark("job-profile-group-title", ["maintenance", "profile-sidebar", "group", key, "title"]),
        title + " (" + picks.length().to_string() + ")",
      ),
      @html.div(
        class="dsh-profile-sidebar-list",
        attrs=mark("job-profile-list", ["maintenance", "profile-sidebar", "list", key]),
        cards,
      ),
    ],
  )
}

///|
/// 试跑用配置的右侧侧栏（§10.3 / §12.4）：与实例详情抽屉同一套外壳（遮罩 + 右侧面板 + Esc）。
///
/// 里面是**总览那一套行**：先运行中分组、再停放分组，组内按 order.json；
/// 每张卡写名字、备注、状态灯与状态词、缺包数、home 归属，不可用的置灰并写明原因。
/// 正在跑的那一只也可以选 —— 试跑用一次性 home，不占用它（§9.4）。
fn job_profile_sidebar(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let facts = job_profile_facts(model)
  let body : Array[@html.Html] = []
  if facts.length() == 0 {
    body.push(
      @html.p(
        class="dsh-empty-sub",
        attrs=mark("job-profile-sidebar-empty", ["maintenance", "profile-sidebar", "empty"]),
        "还没读到 profile 读数，等读数回来再挑。",
      ),
    )
  } else {
    let (running, stopped) = job_profile_picks(model)
    if running.length() > 0 {
      body.push(job_profile_group("running", "当前运行的实例", running, model, emit))
    }
    if stopped.length() > 0 {
      body.push(job_profile_group("stopped", "已停止的实例", stopped, model, emit))
    }
  }
  @html.fragment([
    @html.div(
      class="dsh-drawer-scrim",
      attrs=mark("job-profile-sidebar-scrim", ["maintenance", "profile-sidebar", "scrim"])
        .data_set("state", "open"),
      on_click=emit(ProfileSidebarClose),
      @html.nothing,
    ),
    @html.aside(
      id="dsh-job-profile-sidebar",
      class="dsh-drawer",
      attrs=mark("job-profile-sidebar", ["maintenance", "profile-sidebar"])
        .role("dialog")
        .aria_modal("true")
        .aria_label("选择配置")
        .data_set("state", "open")
        .on_keydown(fn(event) {
          if event.key() == "Escape" {
            emit(ProfileSidebarClose)
          } else {
            @cmd.none
          }
        }),
      [
        @html.div(class="dsh-drawer-head", [
          @html.span(
            class="dsh-drawer-name",
            attrs=mark("job-profile-sidebar-title", ["maintenance", "profile-sidebar", "title"]),
            "选择配置",
          ),
          @html.button(
            id=profile_sidebar_close_id(),
            class="dsh-btn icon-only",
            type_="button",
            attrs=mark("job-profile-sidebar-close", ["maintenance", "profile-sidebar", "close"])
              .aria_label("关闭选择配置"),
            on_click=emit(ProfileSidebarClose),
            [icon("close", size=16)],
          ),
        ]),
        @html.div(class="dsh-drawer-body", body),
      ],
    ),
  ])
}

///|
/// 来源 id → 正文里那个名字。认不出的 id 原样写（不编一个名字）。
fn release_source_name(id : String) -> String {
  match id {
    "github" => "GitHub"
    "npm" => "npm"
    "mirror" => "国内镜像"
    _ => id
  }
}

///|
/// 来源小字那一行的悬停：三个源各自的结果与耗时，一个都不省。
///
/// 为什么把「过了多久」也写出来：三个源里哪个慢（甚至慢到超时）是使用者判断
/// 「要不要还等它」的唯一依据；只写「成功了」等于把这一条藏起来。
fn release_sources_hint(sources : Array[ReleaseSource]) -> String {
  let parts : Array[String] = []
  for source in sources {
    let name = release_source_name(source.id)
    if source.ok {
      parts.push(
        name + "：" + source.count.to_string() + " 个版本，" +
        source.ms.to_string() + "ms",
      )
    } else {
      let why = if source.error == "" { "没答上来，原因没给" } else { source.error }
      parts.push(name + "：" + why + "（" + source.ms.to_string() + "ms）")
    }
  }
  parts.join("；")
}

///|
/// 一条版本的悬停：每枚标记凭什么打上。
///
/// 正文的标记那一格只放得下两枚（§12.2），而「registry 的 latest / next 指向哪一版」
/// 这两条读数不进正文 —— 它们与其它依据一起进悬停，不然后端算出来的东西在界面上
/// 一个落点都没有。
fn release_option_hint(item : ReleaseVersion) -> String {
  let parts : Array[String] = []
  if item.installed {
    parts.push("这台机器上装着这一版")
  }
  if item.latest {
    parts.push("registry 的 latest 指向这一版")
  }
  if item.next {
    parts.push("registry 的 next 指向这一版")
  }
  if item.prerelease {
    parts.push("这一版带预发布后缀（预发布）")
  } else {
    parts.push("这一版是正式发布（版本号不带预发布后缀）")
  }
  parts.join("；")
}

///|
/// 一次过滤给出几条候选。理由：npm 那个 registry 的 versions 键可能有几百条，
/// 全摊开的话这一块比整张作业卡都高；剩下的条数如实写在最后一行，使用者接着写就能收窄。
let job_version_list_cap : Int = 20

///|
/// 表单里「目标版本」那一格（§10.2 / §12.1）：一行「当前版本」+ 一颗「选择版本」按钮。
/// 没选时写「未选择」；候选不再常驻，点按钮开**右侧栏**（与「选择配置」同一套外壳）。
fn job_version_current(
  model : Model,
  disabled : Bool,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let picked = model.job_version.trim().to_owned()
  let value = if picked == "" { "未选择" } else { picked }
  @html.div(class="dsh-job-current", [
    @html.span(
      class="dsh-job-current-label",
      attrs=mark("job-version-current-label", ["maintenance", "start", "version-current-label"]),
      "当前版本",
    ),
    @html.span(
      class="dsh-job-current-value",
      attrs=mark("job-version-current", ["maintenance", "start", "version-current"])
        .data_set("state", if picked == "" { "empty" } else { "picked" }),
      value,
    ),
    @html.button(
      id=version_choose_id(),
      class="dsh-btn dsh-job-choose",
      type_="button",
      disabled~,
      attrs=mark("job-version-choose", ["maintenance", "start", "version-choose"])
        .aria_label("选择目标版本"),
      on_click=emit(VersionSidebarOpen),
      [@html.span("选择版本")],
    ),
  ])
}

///|
/// 拉取时刻那一格：ISO 转浏览器本地的 MM-DD HH:MM，解析不出来就照原样显示（不吞）。
fn release_stamp_text(iso : String) -> String {
  if iso == "" {
    ""
  } else {
    let short = js_short_time(iso)
    if short == "" { iso } else { short }
  }
}

// ── 版本侧栏（§12.1 到 §12.3）────────────────────────────────
//
// 目标版本从居中弹层改成右侧栏，与「选择配置」同一套外壳（遮罩 + 右侧面板 + Esc，
// 焦点先进搜索框）。里面是一张表：版本 / 标记 / 发布时间。
// 标记四档按规格上色，文字同时在场；一版多标记时最多显示两个，其余进悬停。
// 过滤（chip，多选）与排序（三档）都在前端做，与顶部搜索三者叠加。

///|
/// 版本表上的一枚标记：key 进 data-kind 与样式（颜色），文字同时进正文 ——
/// 颜色从来不是唯一信号（§12.2）。
priv struct VersionMark {
  key : String
  text : String
}

///|
/// 现在生效的那份 dsh 是哪个版本（§12.2 的「当前在用」认它）。
///
/// 先看 runtime 读数里打了 active 的那份候选（「起实例会用这一份」，后端判的）；
/// 候选里一个 active 都没有才退回 dshVersion —— 那是同一条链的结论。
/// **不按「版本号最高」自己挑一份**：猜错就会把别的版本说成在用的那一版。
fn active_dsh_version(model : Model) -> String {
  match model.runtime {
    Some(facts) => {
      for cand in facts.dsh_candidates {
        if cand.active && cand.version != "" {
          return cand.version
        }
      }
      facts.dsh_version
    }
    None => ""
  }
}

///|
/// 一版的标记，按 §12.2 那张表的顺序排：当前在用 / 已安装 / 正式发布 / 预发布。
///
/// 正式发布与预发布互斥（判据是版本号带不带预发布后缀，后端给的 prerelease 就是它），
/// 所以每一版至少有一枚；在用的那一版通常同时是已安装的。
fn version_marks(item : ReleaseVersion, active_version : String) -> Array[VersionMark] {
  let out : Array[VersionMark] = []
  if active_version != "" && item.version == active_version {
    out.push({ key: "current", text: "当前在用" })
  }
  if item.installed {
    out.push({ key: "installed", text: "已安装" })
  }
  if item.prerelease {
    out.push({ key: "prerelease", text: "预发布" })
  } else {
    out.push({ key: "stable", text: "正式发布" })
  }
  out
}

///|
/// 一行的悬停全文：这一版带的所有标记（正文只放得下两枚）+ 每枚凭什么打上 +
/// 完整发布时间（正文那一格是本地短时刻）。
fn version_row_hint(item : ReleaseVersion, marks : Array[VersionMark]) -> String {
  let parts : Array[String] = []
  if marks.length() > 0 {
    let words : Array[String] = []
    for mark in marks {
      words.push(mark.text)
    }
    parts.push("标记：" + words.join(" · "))
  }
  parts.push(release_option_hint(item))
  if item.published_at != "" {
    parts.push("发布时间：" + item.published_at)
  }
  parts.join("\n")
}

///|
/// 发布时间那一格：空串 = 不知道（§12.2 是写「不知道」，不拿拉取时间顶替）。
fn release_published_text(item : ReleaseVersion) -> String {
  if item.published_at == "" {
    "不知道"
  } else {
    let short = js_short_time(item.published_at)
    if short == "" { item.published_at } else { short }
  }
}

///|
/// 版本号切成 (core 数字段, 预发布段)："0.2.1-rc.2" → ([0, 2, 1], "rc.2")。
/// 与后端 releases.mbt 的 split_version 同一口径（两端排序必须说同一件事）。
fn version_segments(version : String) -> (Array[Int], String) {
  let core : Array[Int] = []
  let pre = StringBuilder()
  let mut in_pre = false
  let mut n = 0
  for c in version {
    if in_pre {
      pre.write_char(c)
    } else if c == '-' {
      core.push(n)
      n = 0
      in_pre = true
    } else if c == '.' {
      core.push(n)
      n = 0
    } else if c >= '0' && c <= '9' {
      n = n * 10 + (c.to_int() - 48)
    } else {
      // 版本号里不会出现的字符：当这一段结束，不编数字（排序照旧稳定）
      core.push(n)
      n = 0
    }
  }
  if !in_pre {
    core.push(n)
  }
  (core, pre.to_string())
}

///|
/// 一串按 '.' 切的段。版本号这种小串，逐字符扫一遍就够，不引别的库。
fn segments_of(text : String) -> Array[String] {
  let out : Array[String] = []
  let mut buf = StringBuilder()
  for c in text {
    if c == '.' {
      out.push(buf.to_string())
      buf = StringBuilder()
    } else {
      buf.write_char(c)
    }
  }
  out.push(buf.to_string())
  out
}

///|
fn is_digits_text(text : String) -> Bool {
  if text == "" {
    return false
  }
  for c in text {
    if c < '0' || c > '9' {
      return false
    }
  }
  true
}

///|
fn dec_text(text : String) -> Int {
  let mut n = 0
  for c in text {
    n = n * 10 + (c.to_int() - 48)
  }
  n
}

///|
/// 预发布段逐段比：两边都是数字就按数字，否则按字面；前缀相同、段数多的那份更大。
fn compare_pre_text(a : String, b : String) -> Int {
  let xs = segments_of(a)
  let ys = segments_of(b)
  let n = if xs.length() < ys.length() { xs.length() } else { ys.length() }
  for i = 0; i < n; i = i + 1 {
    let x = xs[i]
    let y = ys[i]
    if x == y {
      continue
    }
    if is_digits_text(x) && is_digits_text(y) {
      let xi = dec_text(x)
      let yi = dec_text(y)
      if xi != yi {
        return if xi < yi { -1 } else { 1 }
      }
      continue
    }
    let c = x.lexical_compare(y)
    if c != 0 {
      return if c < 0 { -1 } else { 1 }
    }
  }
  if xs.length() == ys.length() {
    0
  } else if xs.length() < ys.length() {
    -1
  } else {
    1
  }
}

///|
/// 两个版本号谁大（-1 / 0 / 1）：core 逐段比（缺的段当 0），core 相同则正式版更大，
/// 两个都预发布时比预发布段。与后端 compare_version 同一口径。
fn compare_version_text(a : String, b : String) -> Int {
  let (ac, ap) = version_segments(a)
  let (bc, bp) = version_segments(b)
  let n = if ac.length() < bc.length() { bc.length() } else { ac.length() }
  for i = 0; i < n; i = i + 1 {
    let x = if i < ac.length() { ac[i] } else { 0 }
    let y = if i < bc.length() { bc[i] } else { 0 }
    if x != y {
      return if x < y { -1 } else { 1 }
    }
  }
  if ap == "" && bp == "" {
    return 0
  }
  if ap == "" {
    return 1
  }
  if bp == "" {
    return -1
  }
  compare_pre_text(ap, bp)
}

///|
/// 「按发布时间」这一档的比较：新的在前，**没有发布时间的沉底**
/// （不知道就是不知道，不排到最前面冒充最新）。
///
/// 发布时间按 ISO 串字面比：两个源给的都是 UTC（Z 结尾），字面次序就是时间次序。
fn compare_published_desc(a : ReleaseVersion, b : ReleaseVersion) -> Int {
  if a.published_at == "" && b.published_at == "" {
    0
  } else if a.published_at == "" {
    1
  } else if b.published_at == "" {
    -1
  } else {
    let c = a.published_at.lexical_compare(b.published_at)
    if c > 0 { -1 } else if c < 0 { 1 } else { 0 }
  }
}

///|
/// 按当前那一档排序（§12.3）。三档都拿版本的次序当兜底，结果是全序 ——
/// 不因为排序算法稳不稳定而换个样子。只动这一份副本，不改读数。
fn version_sorted(items : Array[ReleaseVersion], sort : String) -> Array[ReleaseVersion] {
  let out = items.copy()
  out.sort_by(fn(a, b) {
    let by_version = compare_version_text(a.version, b.version)
    if sort == "old" {
      by_version
    } else if sort == "published" {
      let by_time = compare_published_desc(a, b)
      if by_time != 0 { by_time } else { -by_version }
    } else {
      -by_version
    }
  })
  out
}

///|
/// 这一版过不过当前的 chip（§12.3）：空数组 = 「全部」。
///
/// 多个 chip 之间是「或」：勾「已安装」与「预发布」要的是两类的并集 ——
/// 交集在真实使用里几乎总是空的（装着的预发布很少），那不是一个帮得上忙的过滤。
fn version_passes_filters(item : ReleaseVersion, filters : Array[String]) -> Bool {
  if filters.length() == 0 {
    return true
  }
  for key in filters {
    if key == "installed" && item.installed {
      return true
    }
    if key == "stable" && !item.prerelease {
      return true
    }
    if key == "prerelease" && item.prerelease {
      return true
    }
  }
  false
}

///|
/// 一枚过滤 chip。选中的那一枚除了颜色，还有 aria-pressed=true 与 data-on ——
/// 颜色不是唯一信号。
fn version_chip(
  label : String,
  key : String,
  active : Bool,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  @html.button(
    class=if active { "dsh-version-chip on" } else { "dsh-version-chip" },
    type_="button",
    attrs=mark("job-version-filter", ["maintenance", "version-sidebar", "filter", key])
      .data_set("filter", key)
      .data_set("on", if active { "true" } else { "false" })
      .aria_pressed(if active { "true" } else { "false" }),
    on_click=emit(VersionFilterToggle(key)),
    [@html.span(label)],
  )
}

///|
/// 版本表的一行：版本 / 标记 / 发布时间。
///
/// 整行可点（鼠标 / Enter / 空格，与侧栏里的卡同一套），选中的那一行多一档底色与
/// 左侧竖线 —— 但「选中」这件事同时写在 aria 里，不只靠那一道线。
fn version_row(
  item : ReleaseVersion,
  active_version : String,
  selected : Bool,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let marks = version_marks(item, active_version)
  // 最多显示两枚（§12.2），其余进悬停
  let shown = if marks.length() > 2 {
    marks[:2].to_owned()
  } else {
    marks
  }
  let mark_cells : Array[@html.Html] = []
  for badge in shown {
    mark_cells.push(
      @html.span(
        class="dsh-version-mark",
        attrs=mark(
          "job-version-mark",
          ["maintenance", "version-sidebar", item.version, "mark", badge.key],
        ).data_set("kind", badge.key),
        badge.text,
      ),
    )
  }
  let words : Array[String] = []
  for badge in marks {
    words.push(badge.text)
  }
  let label = if words.length() == 0 {
    "选这一版 " + item.version
  } else {
    "选这一版 " + item.version + "（" + words.join("、") + "）"
  }
  @html.tr(
    class=if selected { "dsh-version-row selected" } else { "dsh-version-row" },
    attrs=mark("job-version-option", ["maintenance", "version-sidebar", "option", item.version])
      .data_set("version", item.version)
      .data_set("selected", if selected { "true" } else { "false" })
      .data_set("installed", if item.installed { "true" } else { "false" })
      .data_set("prerelease", if item.prerelease { "true" } else { "false" })
      .role("button")
      .tabindex(0)
      .aria_label(label)
      .title(version_row_hint(item, marks))
      .on_click(fn(_event) { emit(JobVersionPicked(item.version)) })
      .on_keydown(fn(event) {
        if event.key() == "Enter" || event.key() == " " {
          emit(JobVersionPicked(item.version))
        } else {
          @cmd.none
        }
      }),
    [
      @html.td(
        class="dsh-version-cell",
        attrs=mark(
          "job-version-cell",
          ["maintenance", "version-sidebar", item.version, "version"],
        ),
        item.version,
      ),
      @html.td(
        class="dsh-version-marks",
        attrs=mark(
          "job-version-marks-cell",
          ["maintenance", "version-sidebar", item.version, "marks"],
        ),
        mark_cells,
      ),
      @html.td(
        class="dsh-version-published",
        attrs=mark(
          "job-version-published",
          ["maintenance", "version-sidebar", item.version, "published"],
        ),
        release_published_text(item),
      ),
    ],
  )
}

///|
/// 版本侧栏（§12.1）：与「选择配置」同一套外壳（遮罩 + 右侧面板 + Esc），
/// 打开时焦点进搜索框，关掉之后焦点回「选择版本」那颗按钮。
///
/// 从上到下：搜索框 → 过滤 chip → 排序 → 版本表（最多 20 条）→ 自定义版本那一行 →
/// 底部小字（来源、拉取时间、「正在重新拉取」或失败原因）与「重新拉取」。
///
/// 状态说三档，与后端缓存那三格对齐：
///   loading  → 还没有候选时写「正在拉版本列表」；有旧候选就照旧列出来（底部说正在重新拉取）
///   ready    → 候选 + 来源 + 拉取时间
///   failed   → 写明上次没拉到的原因，搜索框照旧能写（写了就是自定义版本）
fn job_version_sidebar(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let facts = model.releases
  let versions = match facts {
    Some(got) => got.versions
    None => []
  }
  let state = match facts {
    Some(got) => got.state
    None => if model.releases_loading { "loading" } else { "" }
  }
  let loading = state == "loading" || model.releases_loading
  let query = model.version_query.trim().to_owned()
  let active_version = active_dsh_version(model)
  // 搜索 + 过滤叠加（两者都是「这一版要不要进表」），再按当前那一档排序，最后封顶 20 条
  let matched : Array[ReleaseVersion] = []
  for item in versions {
    if (query == "" || job_version_matches(item.version, query)) &&
      version_passes_filters(item, model.version_filters) {
      matched.push(item)
    }
  }
  let sorted = version_sorted(matched, model.version_sort)
  let shown = if sorted.length() > job_version_list_cap {
    sorted[:job_version_list_cap].to_owned()
  } else {
    sorted
  }
  let mut exact = false
  for item in versions {
    if item.version == query {
      exact = true
    }
  }
  let body : Array[@html.Html] = [
    @html.input(
      input_type=Text,
      id=version_search_id(),
      class="dsh-dialog-input dsh-version-search",
      value=model.version_query,
      placeholder="输入版本号过滤，或直接写自定义版本",
      autofocus=true,
      attrs=mark("job-version-search", ["maintenance", "version-sidebar", "search"])
        .aria_label("搜索版本")
        .spellcheck(false),
      on_input=emit.map(fn(text) { VersionQueryInput(text) }),
    ),
  ]
  // 过滤 chip：全部 / 已安装 / 正式发布 / 预发布。多选，全部 = 一个都不选。
  body.push(
    @html.div(
      class="dsh-version-filters",
      attrs=mark("job-version-filters", ["maintenance", "version-sidebar", "filters"])
        .role("group")
        .aria_label("过滤"),
      [
        version_chip("全部", "all", model.version_filters.length() == 0, emit),
        version_chip("已安装", "installed", model.version_filters.contains("installed"), emit),
        version_chip("正式发布", "stable", model.version_filters.contains("stable"), emit),
        version_chip("预发布", "prerelease", model.version_filters.contains("prerelease"), emit),
      ],
    ),
  )
  // 排序三档。用下拉而不是一排 chip：它选的是**同一样东西的读法**，不是三个并列的条件。
  let sort_options : Array[@html.Html] = []
  let sort_choices : Array[(String, String)] = [
    ("new", "版本从新到旧"),
    ("old", "从旧到新"),
    ("published", "按发布时间"),
  ]
  for choice in sort_choices {
    let (key, label) = choice
    sort_options.push(
      @html.option(
        value=key,
        selected=model.version_sort == key,
        attrs=mark("job-version-sort-option", ["maintenance", "version-sidebar", "sort", key]),
        [@html.text(label)],
      ),
    )
  }
  body.push(
    @html.div(class="dsh-version-sort", [
      @html.select(
        id="dsh-job-version-sort",
        class="dsh-select",
        attrs=mark("job-version-sort", ["maintenance", "version-sidebar", "sort"])
          .aria_label("排序"),
        on_change=emit.map(fn(value) { VersionSortPicked(value) }),
        sort_options,
      ),
    ]),
  )
  if shown.length() > 0 {
    let rows : Array[@html.Html] = []
    for item in shown {
      let selected = item.version == model.job_version
      rows.push(version_row(item, active_version, selected, emit))
    }
    let head_cells : Array[@html.Html] = [
      @html.th(
        scope=@html.Scope::Col,
        attrs=mark("job-version-th", ["maintenance", "version-sidebar", "th", "version"]),
        [@html.text("版本")],
      ),
      @html.th(
        scope=@html.Scope::Col,
        attrs=mark("job-version-th", ["maintenance", "version-sidebar", "th", "marks"]),
        [@html.text("标记")],
      ),
      @html.th(
        scope=@html.Scope::Col,
        attrs=mark("job-version-th", ["maintenance", "version-sidebar", "th", "published"]),
        [@html.text("发布时间")],
      ),
    ]
    body.push(
      @html.div(
        class="dsh-version-table-wrap",
        [
          @html.table(
            class="dsh-version-table",
            attrs=mark("job-version-table", ["maintenance", "version-sidebar", "table"]),
            [
              @html.thead([@html.tr(head_cells)]),
              @html.tbody(rows),
            ],
          ),
        ],
      ),
    )
    if sorted.length() > shown.length() {
      body.push(
        @html.span(
          class="dsh-job-version-more",
          attrs=mark("job-version-more", ["maintenance", "version-sidebar", "more"]),
          "还有 " + (sorted.length() - shown.length()).to_string() + " 条匹配，继续输入缩小范围",
        ),
      )
    }
  } else if versions.length() > 0 || query != "" {
    // 有候选却一条都不剩：要么被过滤掉了，要么搜索没命中。两件事一句话说都不够准确，
    // 所以只写「没有符合条件的版本」—— 它同时是搜索与过滤的结果，不替使用者判定是哪一个。
    body.push(
      @html.span(
        class="dsh-job-version-none",
        attrs=mark("job-version-empty", ["maintenance", "version-sidebar", "empty"]),
        "没有符合条件的版本",
      ),
    )
  } else {
    // 没有候选、也没输入：要么还在拉，要么拉到了却没有答案 —— 两件事分开说
    if loading {
      body.push(
        @html.span(
          class="dsh-version-dialog-note",
          attrs=mark("job-version-loading", ["maintenance", "version-sidebar", "loading"]),
          "正在拉版本列表",
        ),
      )
    } else {
      let (text, hint) = match facts {
        Some(got) =>
          (
            "一个源都没答上来，直接写版本号再点「用这个版本」",
            release_sources_hint(got.sources),
          )
        None =>
          (
            "没读到版本来源，直接写版本号再点「用这个版本」",
            if model.releases_error == "" {
              "这一版读数里没有版本来源"
            } else {
              model.releases_error
            },
          )
      }
      body.push(
        @html.span(
          class="dsh-job-version-none",
          attrs=mark("job-version-none", ["maintenance", "version-sidebar", "none"]).title(hint),
          text,
        ),
      )
    }
  }
  // 自定义版本：输入串不在列表里（没有一模一样的版本号）就给这一行，点了按它开工。
  // 过滤把结果清空时这一行照样在：它说的是「你写的那串可以直接用」，与列表里剩几条无关。
  // 不做存在性校验（控制台不猜远端有什么），装不上由安装那一步如实报失败。
  if query != "" && !exact {
    body.push(
      @html.div(class="dsh-version-custom-row", [
        @html.span(
          class="dsh-job-version-custom",
          attrs=mark("job-version-custom", ["maintenance", "version-sidebar", "custom"]),
          "列表里没有 " + query + "，",
        ),
        @html.button(
          id="dsh-job-version-use-custom",
          class="dsh-dialog-btn",
          type_="button",
          attrs=mark("job-version-use-custom", ["maintenance", "version-sidebar", "use-custom"]),
          on_click=emit(JobVersionPicked(query)),
          [@html.span("用这个版本")],
        ),
      ]),
    )
  }
  // 底部小字：**只剩来源与拉取时间**（§14.3）。「重新拉取没成」走全局提示 ——
  // 它是动作结果；「正在重新拉取」由那颗按钮自己说（按下去之后按钮就是这个字）。
  // 悬停里是三个源各自的结果与耗时。
  let chosen = match facts {
    Some(got) => got.chosen
    None => ""
  }
  let fetched_at = match facts {
    Some(got) => got.fetched_at
    None => ""
  }
  let fetch_error = match facts {
    Some(got) => got.fetch_error
    None => ""
  }
  let source_name = if chosen == "" { "没有答上来的来源" } else { release_source_name(chosen) }
  let mut meta = "来源：" + source_name
  let stamp = release_stamp_text(fetched_at)
  if stamp != "" {
    meta = meta + " · 拉取于 " + stamp
  }
  // 「上次没拉到」是**读取失败**，不是动作结果：按 §14.4 留在原位（这一栏里），
  // 不进全局提示，也不从界面上消失。
  if fetch_error != "" && !loading {
    body.push(
      @html.span(
        class="dsh-version-dialog-status",
        attrs=mark("job-version-status", ["maintenance", "version-sidebar", "status"]),
        "上次没拉到：" + fetch_error,
      ),
    )
  }
  let foot : Array[@html.Html] = [
    @html.span(
      class="dsh-version-dialog-meta",
      attrs=mark("job-version-meta", ["maintenance", "version-sidebar", "meta"]).title(
        match facts {
          Some(got) => release_sources_hint(got.sources)
          None => "读数里没有三个源的结果"
        },
      ),
      meta,
    ),
  ]
  // 手动重拉（§11.3）：只负责排一趟后台刷新，结果照旧靠轮询接上。
  // 在路上时按钮按成「正在重新拉取」并禁用，避免同一拍连点把补问预算耗掉。
  foot.push(
    @html.div(class="dsh-version-foot-btn", [
      @html.button(
        id="dsh-job-version-refresh",
        class="dsh-dialog-btn",
        type_="button",
        disabled=loading,
        attrs=mark("job-version-refresh", ["maintenance", "version-sidebar", "refresh"]),
        on_click=emit(ReleasesRefresh),
        [@html.text(if loading { "正在重新拉取" } else { "重新拉取" })],
      ),
    ]),
  )
  body.push(
    @html.div(
      class="dsh-version-dialog-foot",
      attrs=mark("job-version-foot", ["maintenance", "version-sidebar", "foot"]),
      foot,
    ),
  )
  @html.fragment([
    @html.div(
      class="dsh-drawer-scrim",
      attrs=mark("job-version-sidebar-scrim", ["maintenance", "version-sidebar", "scrim"])
        .data_set("state", "open"),
      on_click=emit(VersionSidebarClose),
      @html.nothing,
    ),
    @html.aside(
      id="dsh-job-version-sidebar",
      class="dsh-drawer",
      attrs=mark("job-version-sidebar", ["maintenance", "version-sidebar"])
        .role("dialog")
        .aria_modal("true")
        .aria_label("选择版本")
        .data_set("state", "open")
        .on_keydown(fn(event) {
          if event.key() == "Escape" {
            emit(VersionSidebarClose)
          } else {
            @cmd.none
          }
        }),
      [
        @html.div(class="dsh-drawer-head", [
          @html.span(
            class="dsh-drawer-name",
            attrs=mark("job-version-sidebar-title", ["maintenance", "version-sidebar", "title"]),
            "选择版本",
          ),
          @html.button(
            id=version_sidebar_close_id(),
            class="dsh-btn icon-only",
            type_="button",
            attrs=mark("job-version-sidebar-close", ["maintenance", "version-sidebar", "close"])
              .aria_label("关闭选择版本"),
            on_click=emit(VersionSidebarClose),
            [icon("close", size=16)],
          ),
        ]),
        @html.div(class="dsh-drawer-body", body),
      ],
    ),
  ])
}

///|
/// 候选是否匹配输入框里的那串：按包含判（写 "0.2.2" 能列出 0.2.2 与 0.2.2-rc.1）。
/// 大小写不敏感 —— 版本号里偶尔带字母（rc / beta），不该逼使用者记住大小写。
fn job_version_matches(version : String, query : String) -> Bool {
  version.to_lower().contains(query.to_lower())
}

///|
/// 「开始一条新作业」那一块。目标版本必须是使用者选/填的：留空就拦住，不猜一个版本。
fn job_start_panel(model : Model, has_unfinished : Bool, emit : @cmd.Emit[Msg]) -> @html.Html {
  let busy = model.job_busy != ""
  // 目标版本留空就禁用「开始」：版本侧栏里选的那一版，不替他挑一个装上
  let version_empty = model.job_version.trim() == ""
  // 一只可用的 profile 都没有时也拦住：前端知道这一条（侧栏里都标着为什么），
  // 让按钮先灰着比发出去再被后端拒一次好懂
  let profile_empty = job_profile_choice(model) == ""
  let disabled = busy || has_unfinished || version_empty || profile_empty
  let hint = if has_unfinished {
    "已经有一条没做完的作业，先做完或中止它"
  } else if version_empty {
    "先选或填一个目标版本；这一步只记回退点，不装东西"
  } else if profile_empty {
    if job_profile_names(model).length() == 0 {
      "还没读到 profile 读数，试跑得先挑一只能起网页实例的配置"
    } else {
      "没有可用的 profile：这一只配置要么读不到，要么起不了网页实例"
    }
  } else {
    "记下回退点与开工前的版本指定，然后停在「安装新版本」"
  }
  @html.div(
    class="dsh-panel dsh-job-start",
    attrs=mark("job-start-panel", ["maintenance", "start-panel"]),
    [
      @html.h2(class="dsh-panel-title", "升级 dsh"),
      // 这里原来还有一句「先留下旧版本，新版本你自己试过再切」—— 与作业卡副标题一字不差。
      // §14.5 的文案扫描要求同一句话不出现两处，这一句的正式位置是作业卡副标题（§5）。
      @html.div(class="dsh-job-start-row", [
        @html.div(
          class="dsh-job-current-field",
          attrs=mark("job-version-field", ["maintenance", "start", "version-field"]),
          job_version_current(model, busy || has_unfinished, emit),
        ),
        @html.div(
          class="dsh-job-current-field",
          attrs=mark("job-profile-field", ["maintenance", "start", "profile-field"]),
          job_profile_current(model, busy || has_unfinished, emit),
        ),
        @html.button(
          class="dsh-btn primary dsh-job-start-btn",
          type_="button",
          disabled~,
          attrs=mark("job-start", ["maintenance", "start", "start"]).title(hint),
          on_click=emit(JobStart),
          [@html.span("开始")],
        ),
      ]),
    ],
  )
}

// ── 按钮组 ─────────────────────────────────────────────────

///|
/// 这一步的按钮组。没结束的作业才有按钮；结束的只留结论。
///
/// 十个按钮（§5 第二版 + 「停掉试跑实例」）就分布在这几支里：
///   开始 / 预演这一步 / 确认执行 / 把新版本跑起来 / 停掉试跑实例 /
///   好用，切到新版 / 不好用，回滚 / 先放着 / 清理旧版本 / 中止作业
fn job_actions(model : Model, job : JobFact, emit : @cmd.Emit[Msg]) -> Array[@html.Html] {
  let busy = model.job_busy != ""
  let out : Array[@html.Html] = []
  if job_fact_finished(job) {
    return out
  }
  let preview_ok = model.job_previewed == job.id
  // 试跑实例在跑：这一页任何一步都不该再起第二只
  let trial_alive = job.trial_alive
  match job.step {
    "install" => {
      out.push(
        job_button(
          "预演这一步",
          "job-install-preview",
          ["maintenance", "job", job.id, "action", "install-preview"],
          busy,
          "先看确切命令与它会不会动到在跑的实例；这一步不执行任何命令",
          JobAction(job.id, "install-preview"),
          emit,
          false,
        ),
      )
      out.push(
        job_button(
          "确认执行",
          "job-install-confirm",
          ["maintenance", "job", job.id, "action", "install-confirm"],
          busy || !preview_ok || model.job_previewed_step != "install",
          if preview_ok && model.job_previewed_step == "install" {
            "按预演过的那条命令装新版本；装完不会自动切过去"
          } else {
            "先点「预演这一步」，看过确切命令再确认执行"
          },
          JobAction(job.id, "install-confirm"),
          emit,
          true,
        ),
      )
    }
    "trial" => {
      out.push(
        job_button(
          "把新版本跑起来",
          "job-trial",
          ["maintenance", "job", job.id, "action", "trial"],
          busy || trial_alive,
          if trial_alive {
            "试跑实例已经在跑了；起第二只之前先把它停掉"
          } else {
            "用作业里那份新版 + 一份一次性 home 起一只实例，等它答出 dsh web 签名"
          },
          JobAction(job.id, "trial"),
          emit,
          true,
        ),
      )
    }
    "verdict" => {
      out.push(
        job_button(
          "好用，切到新版",
          "job-verdict-good",
          ["maintenance", "job", job.id, "action", "verdict-good"],
          busy,
          "先停掉试跑实例，然后进入「切到新版本」这一步（版本指定还没动）",
          JobAction(job.id, "verdict-good"),
          emit,
          true,
        ),
      )
      out.push(
        job_button(
          "不好用，回滚",
          "job-verdict-bad",
          ["maintenance", "job", job.id, "action", "verdict-bad"],
          busy,
          "停掉试跑实例，把版本指定恢复成开工前的样子；新装的那份留着没删",
          JobAction(job.id, "verdict-bad"),
          emit,
          false,
        ),
      )
      out.push(
        job_button(
          "先放着",
          "job-verdict-later",
          ["maintenance", "job", job.id, "action", "verdict-later"],
          busy,
          "只记下「还想再试试」：试跑实例与版本指定都不动，作业停在这一步",
          JobAction(job.id, "verdict-later"),
          emit,
          false,
        ),
      )
    }
    "commit" => {
      out.push(
        job_button(
          "切到新版本",
          "job-commit",
          ["maintenance", "job", job.id, "action", "commit"],
          busy,
          "只改控制台的指定记录，不动系统上装好的东西；旧版本留着当回滚锚",
          JobAction(job.id, "commit"),
          emit,
          true,
        ),
      )
    }
    "cleanup" => {
      out.push(
        job_button(
          "清理旧版本",
          "job-cleanup-preview",
          ["maintenance", "job", job.id, "action", "cleanup-preview"],
          busy,
          "先列出会删掉什么（旧版包目录、体积、有没有实例在跑）；这一步不删任何东西",
          JobAction(job.id, "cleanup-preview"),
          emit,
          false,
        ),
      )
      out.push(
        job_button(
          "确认执行",
          "job-cleanup",
          ["maintenance", "job", job.id, "action", "cleanup"],
          busy || !preview_ok || model.job_previewed_step != "cleanup",
          if preview_ok && model.job_previewed_step == "cleanup" {
            "硬删旧版本的包目录；删掉不能再装回来"
          } else {
            "先点「清理旧版本」，看过会删掉什么再确认执行"
          },
          JobAction(job.id, "cleanup"),
          emit,
          true,
        ),
      )
    }
    _ => ()
  }
  // 试跑实例还在跑：trial / verdict 步都能收它（这也是用户「试完了」之后的第一反应）
  if trial_alive && (job.step == "trial" || job.step == "verdict") {
    out.push(
      job_button(
        "停掉试跑实例",
        "job-trial-stop",
        ["maintenance", "job", job.id, "action", "trial-stop"],
        busy,
        "SIGTERM → 宽限 → SIGKILL 收掉那只实例，再删掉这次试跑用的一次性 home；作业还停在这一步",
        JobAction(job.id, "trial-stop"),
        emit,
        false,
      ),
    )
  }
  out.push(
    job_button(
      "中止作业",
      "job-abort",
      ["maintenance", "job", job.id, "action", "abort"],
      busy,
      "停掉试跑实例（如果在跑）并删掉一次性 home，保留记录与已经做完的步骤；没做的仍然是未开始",
      JobAction(job.id, "abort"),
      emit,
      false,
    ),
  )
  out
}

///|
/// 边界提示（§5 的两句，原话）。只在对应那一步的按钮下面出现。
fn job_boundary_hint(job : JobFact) -> @html.Html {
  let text = match job.step {
    "install" => "这一步会真的装东西，装完不会自动切过去"
    "cleanup" => "清理删的是旧版本的包目录，删掉不能再装回来"
    _ => ""
  }
  if text == "" {
    return @html.nothing
  }
  @html.p(
    class="dsh-job-boundary",
    attrs=mark("job-boundary", ["maintenance", "job", job.id, "boundary"]),
    text,
  )
}

// ── 卡片 ───────────────────────────────────────────────────

///|
/// 作业卡：标题 / 状态 / 第几步 / 开始于 / 一句话结果 / 步骤表 / 试跑那一块 / 按钮。
fn job_card(model : Model, job : JobFact, emit : @cmd.Emit[Msg]) -> @html.Html {
  let expanded = !model.job_collapsed.contains(job.id)
  let steps : Array[@html.Html] = []
  if expanded {
    for step in job.steps {
      steps.push(job_step_row(job, step))
    }
  }
  let result = job_fact_result(job)
  let head_attrs = mark("job-card", ["maintenance", "job", job.id])
  let card_title = "作业 id：" + job.id
  let anchor_hint = card_title + " | 试跑 profile：" +
    (if job.profile == "" { "（没记）" } else { job.profile }) +
    (if job.trial_home == "" {
      ""
    } else {
      " | 试跑一次性 home：" + job.trial_home
    }) +
    (if job.anchor_version == "" {
      ""
    } else {
      " | 回退点：" + job.anchor_version +
      (if job.pin_before_existed {
        if job.pin_before_version == "" {
          "（开工前那份版本指定读不出来）"
        } else {
          "（开工前指定的是 " + job.pin_before_version + "）"
        }
      } else {
        "（开工前没有版本指定）"
      })
    }) +
    (if job.target_version == "" { "" } else { " | 目标版本：" + job.target_version })
  // trial 步：还在跑就摆地址；已经收掉就只摆状态那一句 ——
  // 收尾时那份一次性 home 已经删了，还摆「新版本起来了」就是一句过期的话
  let show_trial = job.step == "trial" || job.step == "verdict"
  let trial_nodes : Array[@html.Html] = []
  if show_trial && job.trial_pid > 0 {
    if job.trial_alive {
      trial_nodes.push(job_trial_block(job))
    }
    trial_nodes.push(job_trial_status(job))
  }
  // 最近一次动作的细节（§14.3「回执照旧写进作业卡」）：确切命令 / 包目录 / 输出尾部。
  // 结论在全局提示里，这里只说细节 —— 同一句话不会在页面上出现两遍。
  let detail = if model.job_detail_for == job.id && model.job_detail != "" {
    @html.div(
      class="dsh-job-detail",
      attrs=mark("job-detail", ["maintenance", "job", job.id, "detail"]),
      [
        @html.span(class="dsh-job-detail-tag", "最近一次操作"),
        @html.span(class="dsh-job-detail-text", model.job_detail),
      ],
    )
  } else {
    @html.nothing
  }
  @html.article(
    class="dsh-job-card",
    attrs=head_attrs.title(anchor_hint).data_set("step", job.step),
    [
      @html.div(class="dsh-job-head", [
        @html.div(class="dsh-job-head-text", [
          @html.h2(
            class="dsh-job-title",
            attrs=mark("job-title", ["maintenance", "job", job.id, "title"]),
            job.title,
          ),
          @html.p(
            class="dsh-job-subtitle",
            attrs=mark("job-subtitle", ["maintenance", "job", job.id, "subtitle"]),
            "先留下旧版本，新版本你自己试过再切",
          ),
        ]),
        @html.span(
          class="dsh-job-status",
          attrs=mark("job-status", ["maintenance", "job", job.id, "status"]),
          [
            @html.span(
              class=job_state_dot(if job.step == "done" {
                "passed"
              } else if job.step == "aborted" {
                "skipped"
              } else if job.step == "rollback" {
                "warn"
              } else {
                "running"
              }),
              @html.nothing,
            ),
            @html.span(job_status_word(job)),
          ],
        ),
      ]),
      @html.div(
        class="dsh-job-meta",
        attrs=mark("job-meta", ["maintenance", "job", job.id, "meta"]),
        "第 " + job_step_index(job).to_string() + " 步 / 共 " +
        job_step_total.to_string() + " 步 · 开始于 " + job_time_text(job.created_at),
      ),
      if result == "" {
        @html.nothing
      } else {
        @html.p(
          class="dsh-job-result",
          attrs=mark("job-result", ["maintenance", "job", job.id, "result"]),
          result,
        )
      },
      job_receipt(job),
      detail,
      @html.button(
        class="dsh-collapse dsh-job-toggle",
        type_="button",
        attrs=mark("job-toggle", ["maintenance", "job", job.id, "toggle"])
          .aria_expanded(if expanded { "true" } else { "false" }),
        on_click=emit(JobToggle(job.id)),
        [
          icon(if expanded { "chevron-down" } else { "chevron-right" }),
          @html.span("步骤"),
        ],
      ),
      if expanded {
        @html.div(
          class="dsh-job-steps",
          attrs=mark("job-steps", ["maintenance", "job", job.id, "steps"]),
          steps,
        )
      } else {
        @html.nothing
      },
      @html.div(
        class="dsh-job-trial-wrap",
        attrs=mark("job-trial-wrap", ["maintenance", "job", job.id, "trial-wrap"]),
        trial_nodes,
      ),
      job_boundary_hint(job),
      @html.div(
        class="dsh-job-actions",
        attrs=mark("job-actions", ["maintenance", "job", job.id, "actions"]),
        job_actions(model, job, emit),
      ),
    ],
  )
}

///|
/// 读不出来的那一条记录：id + 原因 + 落盘目录。
/// 不摆步骤表 —— 它本来就没有可读的步骤；编一张空表出来只会让人以为「一步都没做」。
fn unreadable_job_card(model : Model, job : JobFact) -> @html.Html {
  let dir = match model.console {
    Some(facts) => facts.jobs_dir
    None => ""
  }
  let hint = if dir == "" {
    "这条记录读不出来：" + job.reason
  } else {
    "这条记录读不出来：" + job.reason + " | 文件在 " + dir + "/" + job.id + ".json"
  }
  @html.article(
    class="dsh-job-card dsh-job-bad",
    attrs=mark("job-card", ["maintenance", "job", job.id]).title(hint),
    [
      @html.div(class="dsh-job-head", [
        @html.div(class="dsh-job-head-text", [
          @html.h2(class="dsh-job-title", "记录读不出来"),
          @html.p(
            class="dsh-job-subtitle",
            "这条作业的文件读不出来，所以它的步骤与状态都无从说起。文件没有被改动。",
          ),
        ]),
      ]),
      @html.p(class="dsh-job-result", "原因：" + job.reason),
    ],
  )
}

///|
/// 维护页。
fn maintenance_view(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let body : Array[@html.Html] = []
  let mut has_unfinished = false
  match model.console {
    None =>
      if model.read_console {
        body.push(
          @html.section(
            class="dsh-empty",
            attrs=mark("jobs-unreadable", ["maintenance", "unreadable"]),
            [
              @html.span(class="dsh-empty-icon", [icon("shield-outline", size=26)]),
              @html.p(class="dsh-empty-line", "作业读数读取失败。"),
              @html.p(class="dsh-empty-sub", model.console_error),
            ],
          ),
        )
      } else {
        body.push(
          loading_block(
            "jobs-loading",
            "正在读取作业…",
            "控制台自身状态的读数还在路上。这里先摆加载态。「还没有作业」要等读数回来才敢说。",
          ),
        )
      }
    Some(facts) =>
      if !facts.jobs_present {
        body.push(
          @html.section(
            class="dsh-empty",
            attrs=mark("jobs-missing-field", ["maintenance", "missing-field"]),
            [
              @html.span(class="dsh-empty-icon", [icon("shield-outline", size=26)]),
              @html.p(class="dsh-empty-line", "读不到作业记录。"),
              @html.p(
                class="dsh-empty-sub",
                "这一版控制台还没有作业读数。这与「还没有作业」不是一回事。" +
                "重启控制台之后再看一次。",
              ),
            ],
          ),
        )
      } else if facts.jobs.length() == 0 {
        body.push(
          @html.section(
            class="dsh-empty",
            attrs=mark("jobs-empty", ["maintenance", "empty"]),
            [
              @html.span(class="dsh-empty-icon", [icon("tune", size=26)]),
              @html.p(class="dsh-empty-line", "还没有作业。"),
              @html.p(
                class="dsh-empty-sub",
                "一条作业是按顺序做完的事，中间停止也不会丢进度。",
              ),
            ],
          ),
        )
      } else {
        let cards : Array[@html.Html] = []
        for job in facts.jobs {
          if job.unreadable {
            cards.push(unreadable_job_card(model, job))
          } else {
            if !job_fact_finished(job) {
              has_unfinished = true
            }
            cards.push(job_card(model, job, emit))
          }
        }
        body.push(@html.div(class="dsh-job-cards", cards))
      }
  }
  // 动作结果不在这里：从 §14 起走外壳那一条全局提示（结论），
  // 细节写进对应的作业卡（job_detail）。两处各说一半，同一句话不会出现两遍。
  let children : Array[@html.Html] = [
    @html.header(class="dsh-page-head", [
      @html.h1(
        class="dsh-page-title",
        attrs=mark("maintenance-title", ["maintenance", "title"]),
        "维护",
      ),
    ]),
    job_start_panel(model, has_unfinished, emit),
  ]
  // 两个右侧栏都盖在整页上（固定定位），位置摆在表单后面只是为了渲染顺序稳定
  if model.version_sidebar {
    children.push(job_version_sidebar(model, emit))
  }
  if model.profile_sidebar {
    children.push(job_profile_sidebar(model, emit))
  }
  for block in body {
    children.push(block)
  }
  // 维护页用满内容区宽度（§9.1）：不套 .dsh-page 的窄栏，作业卡与步骤表跟着铺开。
  // 关于页、设置页仍是 .dsh-page 的窄栏 —— 那一页是散文与表单，一行太长反而难读。
  @html.section(
    class="dsh-maintenance",
    attrs=mark("maintenance-page", ["maintenance", "page"]),
    children,
  )
}
