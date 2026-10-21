// 关于页。
//
// 版本表每项都是真实读数；读不到就写「读取失败」与原因，不写空。
// 这一批多一行「安装方式」：值是 pnpm / npm / yarn 全局安装或「未知」，
// 判据是后端按包目录路径认出来的（读数里的 dshInstallKind / dshInstallKindSource）。
// 没有「node 版本」这一行 —— 后端换掉之后那个字段已经不存在了。
//
// 这一页还管一件事：**用哪一版 dsh 起实例**（版本切换 / 回退）。
// 那是「这台机器装了什么、控制台打算用哪一份」的事实，属于这一页；
// 总览页那一组卡说的是实例，不是安装。

///|
/// 安装方式那一行的值：pnpm / npm / yarn 全局安装；认不出写「未知」。
///
/// **不写死 pnpm**：判据全在后端（runtime 的 install_kind_of，只看包目录路径），
/// 前端这里只负责把那个枚举翻成人话。空串 = 这一版读数里没有这一项，
/// 与「认出来是未知」分开说（见 install_kind_hint）。
fn install_kind_text(kind : String) -> String {
  match kind {
    "pnpm" => "pnpm 全局安装"
    "npm" => "npm 全局安装"
    "yarn" => "yarn 全局安装"
    _ => "未知"
  }
}

///|
/// 安装方式那一行的悬停依据。三档分开说：
///   后端给了依据   原样写（认不出时那句话里就带着整条包目录路径，能自己看）
///   字段整个不在   这一版读数里没有「安装方式」这一项（**不是**「未知」）
///   有值没依据     读数里没给判断依据
fn install_kind_hint(facts : RuntimeFacts) -> String {
  if facts.dsh_install_kind_source != "" {
    facts.dsh_install_kind_source
  } else if facts.dsh_install_kind == "" {
    "这一版读数里没有「安装方式」这一项"
  } else {
    "读数里没有判断依据"
  }
}

///|
fn version_rows(model : Model, emit : @cmd.Emit[Msg]) -> Array[@html.Html] {
  match model.runtime {
    // 读数还没回来与读取失败是两件事：前者说「正在读」，后者把原因摆出来
    None =>
      if model.read_runtime {
        [kv_row("读取状态", "读取失败", model.runtime_error)]
      } else {
        [kv_row("读取状态", "正在读取…", "本机读数还没返回")]
      }
    Some(facts) =>
      [
        // 版本号与「切换版本」**同一行**（§66）：按钮靠右，且不再多占一行 ——
        // 单独一行会让这张表多出一条空标签的行，看着像漏填了值。
        // 行标签「dsh 版本」不再写（降密度）：面板标题已经叫「版本」，同一个容器里说了两遍。
        // 底下那几行候选版本本来就没有标签，这一行去掉之后与它们同一种排法。
        @html.div(
          class="dsh-row",
          attrs=mark("about-version-row", ["about", "version", "row"]),
          [
            @html.span(
              class="dsh-value",
              attrs=mark("kv-value", ["about", "version-row", "dsh 版本", "value"])
                .title(facts.dsh_package_name),
              facts.dsh_version,
            ),
            @html.button(
              class="dsh-link-btn dsh-row-action",
              type_="button",
              attrs=mark("about-switch-version", ["about", "version", "switch"])
                .title("去设置页的「dsh 版本」一组，列本机装着的几份，选一份给以后起的实例用"),
              on_click=@cmd.batch([emit(Navigate(Settings)), emit(SettingsGroupPicked("version"))]),
              [@html.text("切换版本")],
            ),
          ],
        ),
        // 安装方式与平台不再各占一行（§68）：并进面板脚下那句小字（见 about_view），
        // 装法的判断依据仍在那句小字的悬停里。这一格只留「哪一版」这件主角。
      ]
  }
}

///|
/// 版本面板脚下那一句：装法 · 平台 · 读于（§68）。原来是三行键值，现在一行小字。
fn facts_line(model : Model) -> String {
  match model.runtime {
    None => "读于 " + model.runtime_time
    Some(facts) => {
      let parts : Array[String] = []
      let kind = install_kind_text(facts.dsh_install_kind)
      if kind != "" {
        parts.push(kind)
      }
      if facts.platform != "" {
        parts.push(facts.platform)
      }
      let console_version = console_version_text(model)
      if console_version != "" {
        parts.push("控制台 " + console_version)
      }
      parts.push("读于 " + model.runtime_time)
      join_with(parts, " · ")
    }
  }
}

///|
/// 上面那句小字的悬停：装法的判断依据、控制台包名都在这里。
fn facts_note(model : Model) -> String {
  match model.runtime {
    None => ""
    Some(facts) => install_kind_hint(facts) + "；控制台包 " + facts.console_package_name
  }
}

///|
/// 控制台自己的版本号（读数里没有就是空串，界面上不写「未知」占一行）。
fn console_version_text(model : Model) -> String {
  match model.runtime {
    Some(facts) =>
      match facts.console_version {
        Some(version) => version
        None => ""
      }
    None => ""
  }
}

///|
/// 一个候选 dsh 的一行：版本号在左，标记与按钮在右。
///
/// 包目录**不进正文**（一屏里放不下几条长路径），挂在整行的悬停里；
/// 从哪找到的那句话也一样。
fn dsh_candidate_row(
  model : Model,
  facts : RuntimeFacts,
  cand : DshCandidate,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let pinned = facts.dsh_pin_state == "pinned"
  let marks : Array[@html.Html] = []
  if cand.active {
    marks.push(@html.span(class="dsh-dsh-mark is-active", "在用"))
  }
  if cand.running {
    marks.push(@html.span(class="dsh-dsh-mark", "在跑"))
  }
  // 已经是「按指定用的那一份」时，再点「用这一版」没有意义 —— 那一位置灰；
  // 那一行同时给「回到自动」，否则指定之后就没有退回的路了。
  let use_button = @html.button(
    class="dsh-btn",
    type_="button",
    disabled=model.dsh_pin_busy != "" || (cand.active && pinned),
    attrs=mark("dsh-use-version", ["about", "dsh-version", "use", cand.version]),
    on_click=emit(DshVersionPin(cand.dir, cand.version)),
    [@html.span("用这一版")],
  )
  let buttons : Array[@html.Html] = [use_button]
  if cand.active && pinned {
    buttons.push(
      @html.button(
        class="dsh-btn",
        type_="button",
        disabled=model.dsh_pin_busy != "",
        attrs=mark("dsh-use-auto", ["about", "dsh-version", "auto"]),
        on_click=emit(DshVersionUnpin),
        [@html.span("回到自动")],
      ),
    )
  }
  let hint = "包目录：" + cand.dir +
    (if cand.source == "" { "" } else { " | 从哪找到的：" + cand.source })
  @html.div(
    class="dsh-row dsh-version-item",
    attrs=mark("dsh-version-row", ["about", "dsh-version", cand.version]).title(hint),
    [
      @html.span(class="dsh-value", cand.version),
      @html.span(class="dsh-dsh-marks", marks),
      @html.span(class="dsh-dsh-actions", buttons),
    ],
  )
}

///|
/// 「现在生效的是哪一版」那一句。
///
/// 三种状态都照实说：没指定过 / 按你指定的 / 你指定过但那版不在了（后端给的原话照抄）。
/// 状态字段整个不在时（这一版后端还没有这一项）也说清是「没有这一项」，不写成「没指定」。
fn dsh_pin_line(facts : RuntimeFacts) -> @html.Html {
  let text = if facts.dsh_pin_state == "pinned" {
    "起实例用的是你指定的 " + facts.dsh_version + "（启动 / 重启都用它）"
  } else if facts.dsh_pin_state == "pin-missing" {
    if facts.dsh_pin_note == "" {
      "你指定过的那一版现在找不到了，起实例已回到自动挑的那一份"
    } else {
      facts.dsh_pin_note
    }
  } else if facts.dsh_pin_state == "auto" {
    "没指定过版本，起实例按自动挑的那一份：" + facts.dsh_version
  } else {
    "这一版读数里没有「指定了哪一版」这一项，起实例按自动挑的那一份"
  }
  @html.p(
    class="dsh-para dsh-dsh-pin-line",
    attrs=mark("dsh-pin-line", ["about", "dsh-version", "pin-line"]),
    text,
  )
}

///|
/// 「这台的 dsh 版本」那一块：列出这台机器上装着的每一份 dsh。
///
/// 读取中 / 读取失败与上面那张版本表同一套措辞 —— 两处说的都是同一份读数。
fn dsh_version_panel(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let body : Array[@html.Html] = []
  match model.runtime {
    None =>
      if model.read_runtime {
        body.push(kv_row("读取状态", "读取失败", model.runtime_error))
      } else {
        body.push(kv_row("读取状态", "正在读取…", "本机读数还没返回"))
      }
    Some(facts) => {
      if facts.dsh_candidates.length() == 0 {
        body.push(
          @html.p(
            class="dsh-para",
            "这一版读数里没有列出本机装着的 dsh，所以这里没有可选的版本",
          ),
        )
      } else {
        let rows : Array[@html.Html] = []
        for cand in facts.dsh_candidates {
          rows.push(dsh_candidate_row(model, facts, cand, emit))
        }
        body.push(@html.div(class="dsh-kv", rows))
      }
      body.push(dsh_pin_line(facts))
    }
  }
  // 改完指定之后的反馈走外壳那一条全局提示（§14.3）：切到别的页也看得见，
  // 本页不再留第二份（§14.4）。
  body.push(
    @html.p(
      class="dsh-foot",
      "改这一版只影响以后起的实例：已经在跑的那些要重启才会换",
    ),
  )
  @html.div(
    class="dsh-version-body",
    attrs=mark("dsh-version-panel", ["settings", "dsh-version-panel"]),
    body,
  )
}

///|
///|
/// 「手动启动」那两条命令不再渲染进页面（§71）：静态说明在 design/manual-start.md，
/// 人也好 agent 也好直接读那个文件；页面上只留一句指向它的说明。
fn about_manual_note() -> @html.Html {
  @html.p(
    class="dsh-foot",
    attrs=mark("about-manual-note", ["about", "manual-start", "note"]).title(
      "为什么要看文件：控制台起不来时这条页面本身也可能打不开，静态文件在仓库里随手可读"
    ),
    "手动启动命令见 design/manual-start.md（静态说明，不在这页渲染）",
  )
}

///|
fn about_view(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  @html.section(
    class="dsh-page",
    attrs=mark("about-page", ["about", "page"]),
    [
      // 页头带那句简介（降密度）：一句话不值得单独占一块面板 ——
      // 一块只有一行字的面板等于给这句话加了一圈边，读的人还得先判断「这块是不是可点的」。
      // 那句话本身留着：它说的是「动作会真的作用到本机」，是安全提示，不删。
      @html.header(class="dsh-page-head", [
        @html.h1(class="dsh-page-title", "关于"),
        @html.p(
          class="dsh-para",
          attrs=mark("about-intro", ["about", "page", "intro"]),
          "本机 DSH 控制台。读数是只读的，动作会真的作用到本机实例与 profile。",
        ),
      ]),
      @html.div(
        class="dsh-panel",
        attrs=mark("version-panel", ["about", "version-panel"]),
        [
          @html.h2(class="dsh-panel-title", "版本"),
          @html.div(class="dsh-kv", version_rows(model, emit)),
          @html.p(
            class="dsh-foot",
            attrs=mark("about-facts-foot", ["about", "version-panel", "foot"]).title(
              facts_note(model),
            ),
            facts_line(model),
          ),
        ],
      ),

      about_manual_note(),
    ],
  )
}
