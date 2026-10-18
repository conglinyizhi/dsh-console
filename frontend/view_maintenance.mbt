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
/// 缺几个包（bundles.missing 的条数）。缺包仍然可用，只在旁边注明。
fn job_profile_missing(profile : ProfileFact) -> Int {
  profile.bundles.missing.length()
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
/// 一只可用 profile 的「配置 home」小字。读数里没给 home 那一项时写「读不到」，
/// 不按控制台自己的 DSH_HOME 猜一个归属出来（与抽屉那一格同一口径）。
fn job_profile_home_text(profile : ProfileFact) -> String {
  if profile.home_kind == "" {
    "配置 home：读不到"
  } else {
    "配置 home：" + home_kind_text(profile.home_kind)
  }
}

///|
/// 第一张可点的 profile 卡是哪一只（打开侧栏时焦点落在它身上，§10.3）。
/// 顺序照读数里的顺序（不按默认推导重排）：「第一张」在界面上是看得见的那一条。
fn job_profile_first_usable(model : Model) -> String {
  for profile in job_profile_facts(model) {
    let (ok, _why) = job_profile_usable(profile)
    if ok {
      return profile.name
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
/// 侧栏里的一颗 profile 卡：**复用总览卡片那一套样式**（.dsh-case，含图标位与两行）。
///
///   · 可用：整张卡可点（鼠标 / Enter / 空格），第二行写缺包数与配置 home 归属；
///   · 不可用：置灰、不可点、从 Tab 序列里摘掉，第二行就写为什么不可用。
/// 缺包不算不可用（§9.3）：旁边注明「缺 N 个包，可能起不来」，卡照旧能点。
fn job_profile_card(
  model : Model,
  profile : ProfileFact,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let (ok, why) = job_profile_usable(profile)
  let missing = job_profile_missing(profile)
  let choice = job_profile_choice(model)
  let selected = profile.name == choice
  let second : Array[String] = []
  if !ok {
    second.push(why)
  } else {
    if missing > 0 {
      second.push("缺 " + missing.to_string() + " 个包，可能起不来")
    }
    second.push(job_profile_home_text(profile))
  }
  let head : Array[@html.Html] = [
    @html.span(
      class="dsh-name",
      attrs=mark("job-profile-card-name", ["maintenance", "profile-sidebar", profile.name, "name"]),
      profile.name,
    ),
  ]
  if selected {
    head.push(
      @html.span(
        class="dsh-profile-card-mark",
        attrs=mark("job-profile-card-mark", ["maintenance", "profile-sidebar", profile.name, "mark"]),
        "当前配置",
      ),
    )
  }
  let lines : Array[@html.Html] = [
    @html.div(class="dsh-case-head", head),
    @html.span(
      class=if ok { "dsh-profile-card-sub" } else { "dsh-profile-card-sub unusable" },
      attrs=mark("job-profile-card-sub", ["maintenance", "profile-sidebar", profile.name, "sub"])
        .title(second.join(" · ")),
      second.join(" · "),
    ),
  ]
  let click = if ok {
    emit(JobProfilePicked(profile.name))
  } else {
    @cmd.none
  }
  @html.article(
    id=job_profile_card_id(profile.name),
    class=if ok { "dsh-case dsh-profile-card" } else { "dsh-case dsh-profile-card disabled" },
    attrs=mark("job-profile-card", ["maintenance", "profile-sidebar", profile.name])
      .data_set("usable", if ok { "true" } else { "false" })
      .role("button")
      .tabindex(if ok { 0 } else { -1 })
      .aria_disabled(if ok { "false" } else { "true" })
      .aria_label(
        if ok {
          "试跑用 " + profile.name
        } else {
          profile.name + " 不可用：" + why
        },
      )
      .on_click(fn(_event) { click })
      .on_keydown(fn(event) {
        if ok && (event.key() == "Enter" || event.key() == " ") {
          emit(JobProfilePicked(profile.name))
        } else {
          @cmd.none
        }
      }),
    [
      @html.span(class="dsh-tile-slot", [
        @html.span(class="dsh-tile violet", [icon("cube-outline", size=20)]),
      ]),
      @html.div(class="dsh-case-body", lines),
    ],
  )
}

///|
/// 试跑用配置的右侧侧栏（§10.3）：与实例详情抽屉同一套外壳（遮罩 + 右侧面板 + Esc）。
///
/// 里面是**总览的卡片样式**摆本机全部 profile：可用可点、不可用置灰并写明原因。
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
    let cards : Array[@html.Html] = []
    for profile in facts {
      cards.push(job_profile_card(model, profile, emit))
    }
    body.push(
      @html.div(
        class="dsh-profile-sidebar-list",
        attrs=mark("job-profile-list", ["maintenance", "profile-sidebar", "list"]),
        cards,
      ),
    )
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
/// 下拉里一条版本的文字：版本号 + 标记（已装 / 最新 / 预发布）。
fn release_option_text(item : ReleaseVersion) -> String {
  let marks : Array[String] = []
  if item.installed {
    marks.push("已装")
  }
  if item.latest {
    marks.push("最新")
  }
  if item.prerelease {
    marks.push("预发布")
  }
  if marks.length() == 0 {
    item.version
  } else {
    item.version + " · " + marks.join(" · ")
  }
}

///|
/// 下拉里一条版本的悬停：每个标记凭什么打上。
///
/// 为什么要它：正文那条只放 已装 / 最新 / 预发布 三个词（规格 §2 就这三条），
/// 而「registry 的 next 指向哪一版」这一条读数不摆进正文 —— 它进悬停，
/// 不然后端算出来的 next 在界面上一个落点都没有。
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
    parts.push("这一版带预发布标记")
  }
  if parts.length() == 0 {
    "这一版没有任何标记（没装、不是 latest / next、也不是预发布）"
  } else {
    parts.join("；")
  }
}

///|
/// 一次过滤给出几条候选。理由：npm 那个 registry 的 versions 键可能有几百条，
/// 全摊开的话这一块比整张作业卡都高；剩下的条数如实写在最后一行，使用者接着写就能收窄。
let job_version_list_cap : Int = 20

///|
/// 表单里「目标版本」那一格（§10.2）：一行「当前版本」+ 一颗「选择版本」按钮。
/// 没选时写「未选择」；候选不再常驻，点按钮开居中弹层。
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
      on_click=emit(VersionDialogOpen),
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

///|
/// 版本弹层（§10.2）：居中对话框，复用 view_parts 的 dialog 外壳。
///
/// 从上到下：搜索框（打开即聚焦）→ 过滤出来的候选（最多 20 条）→ 自定义版本那一行 →
/// 底部小字（来源、拉取时间、「正在重新拉取」或失败原因）与关闭键。
///
/// 状态说三档，与后端缓存那三格对齐：
///   loading  → 还没有候选时写「正在拉版本列表」；有旧候选就照旧列出来（底部说正在重新拉取）
///   ready    → 候选 + 来源 + 拉取时间
///   failed   → 写明上次没拉到的原因，搜索框照旧能写（写了就是自定义版本）
fn job_version_dialog(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
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
  // 过滤：输入即匹配（包含判，大小写不敏感），最多列 20 条，余下的条数如实写在最后一行
  let matched : Array[ReleaseVersion] = []
  for item in versions {
    if query == "" || job_version_matches(item.version, query) {
      matched.push(item)
    }
  }
  let shown = if matched.length() > job_version_list_cap {
    matched[:job_version_list_cap].to_owned()
  } else {
    matched
  }
  let mut exact = false
  for item in versions {
    if item.version == query {
      exact = true
    }
  }
  let body : Array[@html.Html] = []
  if shown.length() > 0 {
    let items : Array[@html.Html] = []
    for item in shown {
      let selected = item.version == model.job_version
      let cls = if selected { "dsh-job-version-item selected" } else { "dsh-job-version-item" }
      items.push(
        @html.button(
          class=cls,
          type_="button",
          attrs=mark("job-version-option", ["maintenance", "start", "version-option", item.version])
            .role("option")
            .aria_selected(if selected { "true" } else { "false" })
            .title(release_option_hint(item)),
          on_click=emit(JobVersionPicked(item.version)),
          [@html.span(release_option_text(item))],
        ),
      )
    }
    body.push(
      @html.div(
        class="dsh-job-version-list dsh-version-dialog-list",
        attrs=mark("job-version-list", ["maintenance", "start", "version-list"])
          .role("listbox")
          .aria_label("可选版本"),
        items,
      ),
    )
    if matched.length() > shown.length() {
      body.push(
        @html.span(
          class="dsh-job-version-more",
          attrs=mark("job-version-more", ["maintenance", "start", "version-more"]),
          "还有 " + (matched.length() - shown.length()).to_string() + " 条匹配，继续输入缩小范围",
        ),
      )
    }
  } else if query == "" {
    // 没有候选、也没输入：要么还在拉，要么拉到了却没有答案 —— 两件事分开说
    if loading {
      body.push(
        @html.span(
          class="dsh-version-dialog-note",
          attrs=mark("job-version-loading", ["maintenance", "start", "version-loading"]),
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
          attrs=mark("job-version-none", ["maintenance", "start", "version-none"]).title(hint),
          text,
        ),
      )
    }
  }
  // 自定义版本：输入串不在列表里（没有一模一样的版本号）就给这一行，点了按它开工。
  // 不做存在性校验（控制台不猜远端有什么），装不上由安装那一步如实报失败。
  if query != "" && !exact {
    body.push(
      @html.div(class="dsh-version-custom-row", [
        @html.span(
          class="dsh-job-version-custom",
          attrs=mark("job-version-custom", ["maintenance", "start", "version-custom"]),
          "列表里没有 " + query + "，",
        ),
        @html.button(
          id="dsh-job-version-use-custom",
          class="dsh-dialog-btn",
          type_="button",
          attrs=mark("job-version-use-custom", ["maintenance", "start", "version-use-custom"]),
          on_click=emit(JobVersionPicked(query)),
          [@html.span("用这个版本")],
        ),
      ]),
    )
  }
  // 底部小字：来源 + 拉取时间 + 「正在重新拉取」/失败原因。悬停里是三个源各自的结果与耗时。
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
  let status_text = if loading {
    if stamp == "" { "正在拉版本列表" } else { "正在重新拉取" }
  } else if fetch_error != "" {
    "上次没拉到：" + fetch_error
  } else {
    ""
  }
  let foot : Array[@html.Html] = [
    @html.span(
      class="dsh-version-dialog-meta",
      attrs=mark("job-version-meta", ["maintenance", "start", "version-meta"]).title(
        match facts {
          Some(got) => release_sources_hint(got.sources)
          None => "读数里没有三个源的结果"
        },
      ),
      meta,
    ),
  ]
  if status_text != "" {
    foot.push(
      @html.span(
        class="dsh-version-dialog-status",
        attrs=mark("job-version-status", ["maintenance", "start", "version-status"]),
        status_text,
      ),
    )
  }
  let card = @html.div(class="dsh-dialog-card dsh-version-dialog", [
    @html.h2(
      class="dsh-dialog-title",
      attrs=mark("dialog-title", ["dialog", "version-dialog", "title"]),
      "选择版本",
    ),
    @html.input(
      input_type=Text,
      id=version_search_id(),
      class="dsh-dialog-input dsh-version-search",
      value=model.version_query,
      placeholder="输入版本号过滤，或直接写自定义版本",
      autofocus=true,
      attrs=mark("job-version-search", ["maintenance", "start", "version-search"])
        .aria_label("搜索版本")
        .spellcheck(false),
      on_input=emit.map(fn(text) { VersionQueryInput(text) }),
    ),
    @html.div(
      class="dsh-version-dialog-body",
      attrs=mark("job-version-dialog-body", ["maintenance", "start", "version-dialog-body"]),
      body,
    ),
    @html.div(
      class="dsh-version-dialog-foot",
      attrs=mark("job-version-foot", ["maintenance", "start", "version-foot"]),
      foot,
    ),
    @html.div(class="dsh-dialog-foot", [
      @html.button(
        id="dsh-job-version-close",
        class="dsh-dialog-btn",
        type_="button",
        attrs=mark("job-version-close", ["maintenance", "start", "version-close"]),
        on_click=emit(VersionDialogClose),
        [@html.text("取消")],
      ),
    ]),
  ])
  dialog(
    "version-dialog",
    "选择版本",
    emit(VersionDialogClose),
    emit.map(fn(key : @html.Keyboard) {
      if key.key() == "Escape" {
        VersionDialogClose
      } else {
        Noop
      }
    }),
    card,
  )
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
  // 目标版本留空就禁用「开始」：弹出的版本弹层里选的那一版，不替他挑一个装上
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
      @html.p(class="dsh-para", "先留下旧版本，新版本你自己试过再切"),
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
  // 提示条：成功失败都留在这一页（这一页没有别的地方能说），细节进悬停。
  let notice : Array[@html.Html] = []
  if model.job_notice != "" {
    let hint = if model.job_notice_hint != "" &&
      model.job_notice_hint_for == model.job_notice {
      model.job_notice_hint
    } else {
      ""
    }
    let text_attrs = if hint == "" {
      mark("job-notice-text", ["maintenance", "notice", "text"])
    } else {
      mark("job-notice-text", ["maintenance", "notice", "text"]).title(hint)
    }
    notice.push(
      @html.div(
        class=if model.job_notice_ok { "dsh-notice" } else { "dsh-notice err" },
        attrs=mark("job-notice", ["maintenance", "notice"])
          .data_set("ok", if model.job_notice_ok { "true" } else { "false" }),
        [@html.span(class="dsh-notice-text", attrs=text_attrs, model.job_notice)],
      ),
    )
  }
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
  // 版本弹层与配置侧栏盖在整页上（固定定位），位置摆在表单后面只是为了渲染顺序稳定
  if model.version_dialog {
    children.push(job_version_dialog(model, emit))
  }
  if model.profile_sidebar {
    children.push(job_profile_sidebar(model, emit))
  }
  for node in notice {
    children.push(node)
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
