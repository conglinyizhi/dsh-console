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
fn version_rows(model : Model) -> Array[@html.Html] {
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
        kv_row("dsh 版本", facts.dsh_version, facts.dsh_package_name),
        // 这一版的 dsh 是怎么装上去的：值只有四种（pnpm / npm / yarn 全局安装、未知），
        // 凭什么这么判挂在悬停里。它说的是「装法」，不是「版本」，放在版本号下面一行。
        kv_row(
          "安装方式",
          install_kind_text(facts.dsh_install_kind),
          install_kind_hint(facts),
        ),
        kv_row(
          "控制台版本",
          match facts.console_version {
            Some(version) => version
            None => "未知"
          },
          facts.console_package_name,
        ),
        kv_row("平台", facts.platform, ""),
      ]
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
  // 改完指定之后的反馈：成功失败都留在这儿，直到下一次点 ——
  // 这一页没有总览页那条提示条，不留一行的话「点了没反应」与「成功了」看着一样。
  if model.dsh_pin_notice != "" {
    body.push(
      @html.div(
        class=if model.dsh_pin_notice_ok { "dsh-notice" } else { "dsh-notice err" },
        attrs=mark("dsh-pin-notice", ["about", "dsh-version", "notice"])
          .data_set("ok", if model.dsh_pin_notice_ok { "true" } else { "false" }),
        [@html.span(class="dsh-notice-text", model.dsh_pin_notice)],
      ),
    )
  }
  body.push(
    @html.p(
      class="dsh-foot",
      "改这一版只影响以后起的实例：已经在跑的那些要重启才会换",
    ),
  )
  @html.div(
    class="dsh-panel",
    attrs=mark("dsh-version-panel", ["about", "dsh-version-panel"]),
    [
      @html.h2(class="dsh-panel-title", "这台的 dsh 版本"),
      @html.fragment(body),
    ],
  )
}

///|
fn about_view(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  @html.section(
    class="dsh-page",
    attrs=mark("about-page", ["about", "page"]),
    [
      @html.header(class="dsh-page-head", [@html.h1(class="dsh-page-title", "关于")]),
      @html.div(
        class="dsh-panel",
        attrs=mark("about-panel", ["about", "about-panel"]),
        [
          @html.p(
            class="dsh-para",
            "面向个人本机使用的 DSH 控制台，用来查看这台机器上的 DeepSeek Harness 实例。",
          ),
          @html.p(
            class="dsh-para",
            "读数只读本机 ~/.dsh；动作（启动 / 停止 / 重启 / 派生 / 归档 / 重命名 / 编辑备注 / 删除）会真的作用到本机实例与 profile，不是预览。",
          ),
        ],
      ),
      @html.div(
        class="dsh-panel",
        attrs=mark("version-panel", ["about", "version-panel"]),
        [
          @html.h2(class="dsh-panel-title", "版本"),
          @html.div(class="dsh-kv", version_rows(model)),
          @html.p(
            class="dsh-foot",
            "读于 " + model.runtime_time + " | 读自本机",
          ),
        ],
      ),
      dsh_version_panel(model, emit),
    ],
  )
}
