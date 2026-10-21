// 维护页的配置选择：profile 读数取值、可用性判据、卡片、分组与「选择配置」侧栏。
//
// 2026-10-20 从 view_maintenance.mbt 拆出来：这一族是「选哪一份配置开工」的读侧，
// 与作业状态机、版本表都不共用状态。只搬位置，函数体一个字没改。

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
        Some(false) =>
          (false, "这只配置起的是命令行型，没有网页入口")
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
          Some(name) => if usable.contains(name) { return name }
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
fn job_profile_pick(
  row : Row?,
  fact : ProfileFact?,
  ignore_missing : Bool,
) -> ProfilePick {
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
      (
        name,
        item.light,
        item.light_reason,
        item.light_basis,
        item.status is Running,
      )
    }
    None =>
      match fact {
        Some(item) => {
          let (light, reason, basis) = profile_light(item, ignore_missing)
          (item.name, light, reason, basis, false)
        }
        None => ("", LightUnknown, "", "", false)
      }
  }
  let (missing, missing_names) = match fact {
    Some(item) =>
      (item.bundles.missing.length(), join_with(item.bundles.missing, "、"))
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
  // 与总览同一把尺子（§40.3）：缺包排不排进灯，全看这一个设置项
  let ignore_missing = ignore_missing_bundles(model)
  let running : Array[ProfilePick] = []
  let stopped : Array[ProfilePick] = []
  let seen : Array[String] = []
  // 只收**读数里有这一只**的行：试跑按 profile 名从 DSH_HOME 的 profiles/ 里找，
  // 别的 home 里同名的那一只在这里选不了（选完表单也会退回默认那一只）。
  // 那种行（实例在别的 home 里跑着）照样出现在总览上，但这里不摆一个点了没用的卡。
  for row in running_rows {
    match row.profile_name {
      Some(name) =>
        match job_profile_fact_of(model, name) {
          Some(fact) =>
            if !seen.contains(name) {
              running.push(
                job_profile_pick(Some(row), Some(fact), ignore_missing),
              )
              seen.push(name)
            }
          None => ()
        }
      None => ()
    }
  }
  for row in stopped_rows {
    match row.profile_name {
      Some(name) =>
        match job_profile_fact_of(model, name) {
          Some(fact) =>
            if !seen.contains(name) {
              stopped.push(
                job_profile_pick(Some(row), Some(fact), ignore_missing),
              )
              seen.push(name)
            }
          None => ()
        }
      None => ()
    }
  }
  for fact in job_profile_facts(model) {
    if !seen.contains(fact.name) {
      stopped.push(job_profile_pick(None, Some(fact), ignore_missing))
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
      attrs=mark("job-profile-current-label", [
        "maintenance", "start", "profile-current-label",
      ]),
      "当前配置",
    ),
    @html.span(
      class="dsh-job-current-value",
      attrs=mark("job-profile-current", [
        "maintenance", "start", "profile-current",
      ]).data_set("state", if choice == "" { "empty" } else { "picked" }),
      value,
    ),
    @html.button(
      id=profile_choose_id(),
      class="dsh-btn dsh-job-choose",
      type_="button",
      disabled~,
      attrs=mark("job-profile-choose", [
        "maintenance", "start", "profile-choose",
      ]).aria_label("选择试跑用配置"),
      on_click=emit(ProfileSidebarOpen),
      [@html.span("选择配置")],
    ),
  ])
}

///|
/// 「选择配置」那一栏里的一张卡：点下去回填试跑用配置。
///
/// 画法在 view_parts.mbt 的 profile_card（§25）：这一处只决定点下去发什么、路径前缀、
/// 挂不挂「当前配置」那枚标记、aria 那句话。
fn job_profile_card(
  model : Model,
  pick : ProfilePick,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let choice = job_profile_choice(model)
  let selected = pick.name == choice
  let ok = pick.usable
  let aria = if ok {
    "试跑用 " + pick.name
  } else {
    pick.name + " 不可用：" + pick.why
  }
  profile_card(
    pick,
    job_profile_card_id(pick.name),
    "job-profile",
    ["maintenance", "profile-sidebar"],
    if selected {
      "当前配置"
    } else {
      ""
    },
    aria,
    aria,
    fn(name) { JobProfilePicked(name) },
    emit,
  )
}

///|
/// 整体替换那一栏里的一张源卡：点下去选它当源（点完在同一侧栏里出差异预览）。
/// 与「选择配置」是**同一份画法**（view_parts.mbt 的 profile_card），只是换一套 data-name 与消息。
fn promote_source_card(pick : ProfilePick, emit : @cmd.Emit[Msg]) -> @html.Html {
  let ok = pick.usable
  let aria = if ok {
    "用 " + pick.name + " 的配置替换"
  } else {
    pick.name + " 不可用：" + pick.why
  }
  profile_card(
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
    attrs=mark("job-profile-group", [
      "maintenance", "profile-sidebar", "group", key,
    ]).data_set("group", key),
    [
      @html.h3(
        class="dsh-profile-sidebar-group-title",
        attrs=mark("job-profile-group-title", [
          "maintenance", "profile-sidebar", "group", key, "title",
        ]),
        title + " (" + picks.length().to_string() + ")",
      ),
      @html.div(
        class="dsh-profile-sidebar-list",
        attrs=mark("job-profile-list", [
          "maintenance", "profile-sidebar", "list", key,
        ]),
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
        attrs=mark("job-profile-sidebar-empty", [
          "maintenance", "profile-sidebar", "empty",
        ]),
        "还没读到 profile 读数，等读数回来再挑。",
      ),
    )
  } else {
    let (running, stopped) = job_profile_picks(model)
    if running.length() > 0 {
      body.push(
        job_profile_group(
          "running", "当前运行的实例", running, model, emit,
        ),
      )
    }
    if stopped.length() > 0 {
      body.push(
        job_profile_group("stopped", "已停止的实例", stopped, model, emit),
      )
    }
  }
  @html.fragment([
    @html.div(
      class="dsh-drawer-scrim",
      attrs=mark("job-profile-sidebar-scrim", [
        "maintenance", "profile-sidebar", "scrim",
      ]).data_set("state", "open"),
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
            attrs=mark("job-profile-sidebar-title", [
              "maintenance", "profile-sidebar", "title",
            ]),
            "选择配置",
          ),
          @html.button(
            id=profile_sidebar_close_id(),
            class="dsh-btn icon-only",
            type_="button",
            attrs=mark("job-profile-sidebar-close", [
              "maintenance", "profile-sidebar", "close",
            ]).aria_label("关闭选择配置"),
            on_click=emit(ProfileSidebarClose),
            [icon("close", size=16)],
          ),
        ]),
        @html.div(class="dsh-drawer-body", body),
      ],
    ),
  ])
}
