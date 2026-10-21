///|
/// 「开始一条新作业」那一块。目标版本必须是使用者选/填的：留空就拦住，不猜一个版本。
fn job_start_panel(
  model : Model,
  has_unfinished : Bool,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
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
      @html.h2(class="dsh-panel-title", "升级 dsh 之前进行实验"),
      // 这里原来还有一句「先留下旧版本，新版本你自己试过再切」—— 与作业卡副标题一字不差。
      // §14.5 的文案扫描要求同一句话不出现两处，这一句的正式位置是作业卡副标题（§5）。
      @html.div(class="dsh-job-start-row", [
        @html.div(
          class="dsh-job-current-field",
          attrs=mark("job-version-field", [
            "maintenance", "start", "version-field",
          ]),
          job_version_current(model, busy || has_unfinished, emit),
        ),
        @html.div(
          class="dsh-job-current-field",
          attrs=mark("job-profile-field", [
            "maintenance", "start", "profile-field",
          ]),
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
              @html.span(class="dsh-empty-icon", [
                icon("shield-outline", size=26),
              ]),
              @html.p(class="dsh-empty-line", "作业读数读取失败。"),
              @html.p(class="dsh-empty-sub", model.console_error),
            ],
          ),
        )
      } else {
        body.push(
          loading_block(
            "jobs-loading", "正在读取作业…", "读数还在路上；「还没有作业」要等读数回来才敢说。",
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
              @html.span(class="dsh-empty-icon", [
                icon("shield-outline", size=26),
              ]),
              @html.p(class="dsh-empty-line", "读不到作业记录。"),
              @html.p(
                class="dsh-empty-sub",
                attrs=mark("jobs-missing-note", [
                  "maintenance", "missing-field", "note",
                ]).title(
                  "这一版控制台还没有作业读数。这与「还没有作业」不是一回事。重启控制台之后再看一次。",
                ),
                "读不到作业读数（不是「没有作业」），重启控制台再看。",
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
                attrs=mark("jobs-empty-note", ["maintenance", "empty", "note"]).title(
                  "一条作业是按顺序做完的事，中间停止也不会丢进度。",
                ),
                "按顺序做完，中途停止不丢进度。",
              ),
              // 行动号召（design/design-fixes.md 第 3 条）：一颗真能点的按钮。
              // 它把焦点送到上面「当前版本」那一格（选目标版本的那一格）：
              // 走第一条作业的第一步就是选一版，按钮直接把位置指出来，
              // 不留一句「请在下面开始」让人自己找。
              @html.button(
                class="dsh-empty-cta",
                type_="button",
                attrs=mark("jobs-empty-start", ["maintenance", "empty", "start"]).title(
                  "滚到上面的表单，焦点落在「当前版本」那一格（选目标版本）",
                ),
                on_click=emit(JobStartFocus),
                [icon("tune", size=13), @html.span("开始一条作业")],
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
