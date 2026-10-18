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
/// 手动启动那两条命令用哪只 profile 的名字：优先读数里的 currentProfile（DSH_PROFILE），
/// 其次是 profiles 读数列出来的第一只，最后才退回读数里的 dshProfile。
/// 三处都没有就给空串，界面写占位 <名字> —— 不写死一个 "web" 出来。
fn manual_start_profile(model : Model) -> String {
  match model.profiles {
    Some(facts) => {
      match facts.current_profile {
        Some(name) =>
          if name == "" {
            ""
          } else {
            name
          }
        None =>
          if facts.profiles.length() > 0 {
            facts.profiles[0].name
          } else {
            model_profile_fallback(model)
          }
      }
    }
    None => model_profile_fallback(model)
  }
}

///|
/// 兜底：runtime 读数里的 dshProfile。两处都没有就是空串。
fn model_profile_fallback(model : Model) -> String {
  match model.runtime {
    Some(facts) =>
      match facts.dsh_profile {
        Some(name) => name
        None => ""
      }
    None => ""
  }
}

///|
/// 稳定环境那条的 home：runtime 读数里的 dshHome（控制台自己的 home），
/// 读不到再看 profiles 读数里的 dshHome。都没有给空串（界面写占位）。
fn manual_start_home(model : Model) -> String {
  match model.runtime {
    Some(facts) =>
      if facts.dsh_home == "" {
        manual_start_home_from_profiles(model)
      } else {
        facts.dsh_home
      }
    None => manual_start_home_from_profiles(model)
  }
}

///|
fn manual_start_home_from_profiles(model : Model) -> String {
  match model.profiles {
    Some(facts) => facts.dsh_home
    None => ""
  }
}

///|
/// 锁版本那条的包目录：生效那一份候选（active）的 dir，没有 active 就取第一份。
/// 空串 = 读数里没有候选（界面写占位 <包目录>）。
fn manual_start_package(model : Model) -> String {
  let facts = match model.runtime {
    None => return ""
    Some(facts) => facts
  }
  if facts.dsh_candidates.length() == 0 {
    return ""
  }
  for cand in facts.dsh_candidates {
    if cand.active {
      return cand.dir
    }
  }
  facts.dsh_candidates[0].dir
}

///|
/// 关于页「手动启动」里的一条命令：标签 + 命令本身 + 一句说明。
fn manual_start_row(label : String, command : String, note : String, key : String) -> @html.Html {
  @html.div(
    class="dsh-manual-row",
    attrs=mark("manual-start-row", ["about", "manual-start", key]),
    [
      @html.span(
        class="dsh-manual-label",
        attrs=mark("manual-start-label", ["about", "manual-start", key, "label"]),
        label,
      ),
      @html.code(
        class="dsh-manual-cmd",
        attrs=mark("manual-start-cmd", ["about", "manual-start", key, "cmd"]),
        command,
      ),
      @html.span(
        class="dsh-manual-note",
        attrs=mark("manual-start-note", ["about", "manual-start", key, "note"]),
        note,
      ),
    ],
  )
}

///|
/// 关于页「手动启动」那一块（规格第 8 节）。
///
/// 用途只有一个：控制台不可用时，使用者照着敲就能起来。所以名字、home、包目录
/// 全部照当前读数填 —— 不写死 web、不写死 ~/.dsh、也不写死某个版本的目录。
/// 读数还没回来时写占位（<名字> / <DSH_HOME> / <包目录>）并说清是占位，不假装已经填好了。
fn manual_start_panel(model : Model) -> @html.Html {
  let profile = manual_start_profile(model)
  let name = if profile == "" { "<名字>" } else { profile }
  let home = manual_start_home(model)
  let home_text = if home == "" { "<DSH_HOME>" } else { home }
  let pkg = manual_start_package(model)
  let stable = "DSH_HOME=" + home_text + " dsh --profile " + name
  let locked = if pkg == "" {
    "node <包目录>/lib/bin.js --profile " + name
  } else {
    "node " + pkg + "/lib/bin.js --profile " + name
  }
  let stable_note = if home == "" {
    "读数里还没有 DSH_HOME，这一条先用占位；它起的是控制台自己那个稳定环境"
  } else {
    "稳定环境这条用 " + home_text + " 起 " + name + "，dsh 取 PATH 上那一个"
  }
  let locked_note = if pkg == "" {
    "读数里还没有生效的包目录，这一条先用占位；它锁的是这一份 dsh，不吃 PATH"
  } else {
    "锁版本这条直接用 " + pkg + " 这一份 dsh，环境里换了版本也不影响它"
  }
  @html.div(
    class="dsh-panel",
    attrs=mark("manual-start-panel", ["about", "manual-start"]),
    [
      @html.h2(class="dsh-panel-title", "手动启动"),
      @html.p(
        class="dsh-para",
        "控制台起不来的时候，在终端里照着下面两条敲，起的是同一套东西。",
      ),
      @html.div(class="dsh-manual", [
        manual_start_row("稳定环境", stable, stable_note, "stable"),
        manual_start_row("锁版本", locked, locked_note, "pinned"),
      ]),
      @html.p(
        class="dsh-foot",
        "隔离到独立 home 的 profile 也这样起：把 DSH_HOME 换成那份隔离 home 的路径即可" +
        "（总览抽屉里「配置 home」那一格写着路径）。",
      ),
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
      manual_start_panel(model),
    ],
  )
}
