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
let job_step_total : Int32 = 7

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
fn job_step_index(job : JobFact) -> Int32 {
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
    mark("job-step", ["maintenance", "job", job.id, "step", step.key]).title(
      hint,
    )
  }
  @html.div(
    class="dsh-job-step",
    attrs=row_attrs.data_set("state", step.state),
    [
      @html.span(class=job_state_dot(step.state), @html.nothing),
      @html.span(
        class="dsh-job-step-name",
        attrs=mark("job-step-name", [
          "maintenance",
          "job",
          job.id,
          "step",
          step.key,
          "name",
        ]),
        job_step_label(step.key),
      ),
      @html.span(
        class="dsh-job-step-state",
        attrs=mark("job-step-state", [
          "maintenance",
          "job",
          job.id,
          "step",
          step.key,
          "state",
        ]),
        job_state_word(step.state),
      ),
      @html.span(
        class="dsh-job-step-note",
        attrs=mark("job-step-note", [
          "maintenance",
          "job",
          job.id,
          "step",
          step.key,
          "note",
        ]),
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
      "一次性 home：" +
      home +
      (if job.trial_profile_copy == "" {
        ""
      } else {
        "；配置拷贝：" + job.trial_profile_copy
      }),
    )
  }
  @html.div(
    class="dsh-job-trial",
    attrs=mark("job-trial", ["maintenance", "job", job.id, "trial"]),
    [
      @html.p(
        class="dsh-job-trial-line",
        attrs=mark("job-trial-line", [
          "maintenance",
          "job",
          job.id,
          "trial",
          "line",
        ]),
        [
          @html.text("新版本起来了："),
          @html.a(
            href=url,
            target=@html.Target::Blank,
            rel="noopener",
            class="dsh-job-trial-link",
            attrs=mark("job-trial-link", [
              "maintenance",
              "job",
              job.id,
              "trial",
              "link",
            ]).title("在新标签页打开这只试跑实例"),
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
    class=if job.trial_alive {
      "dsh-job-trial-state alive"
    } else {
      "dsh-job-trial-state"
    },
    attrs=mark("job-trial-state", [
        "maintenance",
        "job",
        job.id,
        "trial",
        "state",
      ])
      .data_set("alive", if job.trial_alive { "true" } else { "false" })
      .title(
        if job.trial_alive {
          "起好之后不会被作业自动收掉：要收它点「停掉试跑实例」，或者中止作业"
        } else {
          "现在没有试跑实例在跑"
        },
      ),
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
    "回滚了：起实例还是用 " +
    job.anchor_version +
    "；新装的那份留着没删，要删单独清理"
  } else if commit_passed {
    "已经切到 " +
    job.target_version +
    "；起实例会用这一版。旧版本留着当回滚锚，确认稳定后再清理"
  } else {
    ""
  }
  if text == "" {
    return @html.nothing
  }
  @html.p(
    class=if rollback_passed {
      "dsh-job-receipt rollback"
    } else {
      "dsh-job-receipt"
    },
    attrs=mark("job-receipt", ["maintenance", "job", job.id, "receipt"]),
    text,
  )
}

// ── 新作业表单 ──────────────────────────────────────────────

///|
/// 这一步的按钮组。没结束的作业才有按钮；结束的只留结论。
///
/// 十个按钮（§5 第二版 + 「停掉试跑实例」）就分布在这几支里：
///   开始 / 预演这一步 / 确认执行 / 把新版本跑起来 / 停掉试跑实例 /
///   好用，切到新版 / 不好用，回滚 / 先放着 / 清理旧版本 / 中止作业
fn job_actions(
  model : Model,
  job : JobFact,
  emit : @cmd.Emit[Msg],
) -> Array[@html.Html] {
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
    "trial" =>
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
    "commit" =>
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
    "cleanup" =>
      "清理删的是旧版本的包目录，删掉不能再装回来"
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
  let anchor_hint = card_title +
    " | 试跑 profile：" +
    (if job.profile == "" { "（没记）" } else { job.profile }) +
    (if job.trial_home == "" {
      ""
    } else {
      " | 试跑一次性 home：" + job.trial_home
    }) +
    (if job.anchor_version == "" {
      ""
    } else {
      " | 回退点：" +
      job.anchor_version +
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
    (if job.target_version == "" {
      ""
    } else {
      " | 目标版本：" + job.target_version
    })
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
            attrs=mark("job-subtitle", [
              "maintenance",
              "job",
              job.id,
              "subtitle",
            ]),
            "先留下旧版本，新版本你自己试过再切",
          ),
        ]),
        @html.span(
          class="dsh-job-status",
          attrs=mark("job-status", ["maintenance", "job", job.id, "status"]),
          [
            @html.span(
              class=job_state_dot(
                if job.step == "done" {
                  "passed"
                } else if job.step == "aborted" {
                  "skipped"
                } else if job.step == "rollback" {
                  "warn"
                } else {
                  "running"
                },
              ),
              @html.nothing,
            ),
            @html.span(job_status_word(job)),
          ],
        ),
      ]),
      @html.div(
        class="dsh-job-meta",
        attrs=mark("job-meta", ["maintenance", "job", job.id, "meta"]),
        "第 " +
        job_step_index(job).to_string() +
        " 步 / 共 " +
        job_step_total.to_string() +
        " 步 · 开始于 " +
        job_time_text(job.created_at),
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
        attrs=mark("job-toggle", ["maintenance", "job", job.id, "toggle"]).aria_expanded(
          if expanded {
            "true"
          } else {
            "false"
          },
        ),
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
        attrs=mark("job-trial-wrap", [
          "maintenance",
          "job",
          job.id,
          "trial-wrap",
        ]),
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
    "这条记录读不出来：" +
    job.reason +
    " | 文件在 " +
    dir +
    "/" +
    job.id +
    ".json"
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
