// 页面之间共用的小件：徽标、分组头、空态、字段行、对话框。
//
// 图标本身在 icons.mbt（内联 SVG）。
//
// DOM 上刻意挂 data-name + data-uid：类名会随样式层换、位置会随列表顺序换，
// 这两个不会 —— 截图脚本、DOM 实测脚本、渲染基线、以及使用者的元素拾取工具都按它定位。
//   data-name = 角色（instance-card / source-badge，同类共用，允许重复）
//   data-uid  = 这一个（8 位 base36，全页唯一、跨刷新稳定，算法在 uid.mbt）
//
// 语义路径统一在这里的口径：页面 → 分组 → 角色 → 这一项自己的键。
// **最后一段永远是这一项自己的键**（row.id / 设置键名 / 来源值），不是序号。

///|
/// 数据源徽标：只在读数出岔子时才有 —— 读到了（None）这里一个节点都不产出。
///
/// 为什么读到了反而不标：页面上读到的一切都是真读数，为「一切正常」挂个徽标
/// 只是旧前端迁移期的历史产物（使用者 2026-10-15 决定清掉）。
/// 而「这一次读取失败了，你看到的是兜底数据」**必须留着** —— 删了它，失败就伪装成正常。
///
/// parts 由调用方给全：同一个 data-name 的徽标在页面上有好几个
/// （运行中分组 / 已停止分组 / 归档区 / 各页页眉），只靠 name 分不开它们。
fn source_badge(tag : SourceTag?, parts : Array[String]) -> @html.Html {
  let tag = match tag {
    None => return @html.nothing
    Some(tag) => tag
  }
  let icon_name = match tag.kind {
    Fallback => "shield-outline"
    Pending => "refresh"
  }
  let tone = match tag.kind {
    Fallback => " fallback"
    Pending => " pending"
  }
  @html.span(
    class="dsh-badge" + tone,
    attrs=mark("source-badge", parts).title(tag.detail),
    [icon(icon_name, size=12), @html.span(class="dsh-badge-label", tag.label)],
  )
}

///|
/// 分组头：标题 + 计数（读数正常时右边是空的，见 source_badge）。
///
/// 计数是字符串而不是数字：读数还没回来时那里得写「…」而不是「0」——
/// 「(0)」配一块加载态，正是把「还没读到」读成「没有」的那种写法。
///
/// group 是这一组自己的键（running / stopped），语义路径靠它把两个分组的
/// 同名徽标与同名标题分开。
fn section_head(group : String, title : String, count : String, tag : SourceTag?) -> @html.Html {
  @html.div(class="dsh-section-head", [
    @html.h2(
      class="dsh-section-title",
      attrs=mark("section-title", ["overview", "section", group, "title"]),
      title + " (" + count + ")",
    ),
    source_badge(tag, ["overview", "section", group, "source-badge"]),
  ])
}

///|
/// 运行中分组的空态：监听端口扫完、一个 DSH 签名都没命中时才出现，不留假实例占位。
///
/// detail 是**读数出岔子时**那一句（读失败的原因）；读到了就是空串 ——
/// 那时它本来也只是把 summary 又说了一遍，多一行反而让人以为漏看了什么。
/// 空态里的行动号召（design/design-fixes.md 第 3 条）：一颗真能点的按钮，
/// 不是一句「请先…」。样式是线框档（.dsh-empty-cta），一页只有一颗实心主操作。
///
/// 为什么是「重新读一遍」而不是「新建实例」：这一格摆的是「扫完了，确实一个都没在跑」——
/// 这时候要的多半是先确认读数是不是新鲜（另一台窗口里的实例刚停、刚起来），
/// 重读一次就能分辨。新建一份 profile 与「一个实例都没在跑」不是同一件事，
/// 那件事由页头那颗「＋新建实例」负责（design/design-fixes.md §19.1 起它会开框）。
/// 这一颗是现成动作：点一下两份读数都重发，骨架屏立刻立起来，读完再落回列表或空态。
fn running_empty(summary : String, detail : String, emit : @cmd.Emit[Msg]) -> @html.Html {
  let lines : Array[@html.Html] = [
    @html.span(class="dsh-empty-icon", [icon("server", size=26)]),
    @html.p(class="dsh-empty-line", "当前没有检测到正在运行的 dsh 实例。"),
    @html.p(class="dsh-empty-sub", summary),
  ]
  if detail != "" {
    lines.push(@html.p(class="dsh-empty-sub", attrs=@html.Attrs::build().title(detail), detail))
  }
  lines.push(
    @html.button(
      class="dsh-empty-cta",
      type_="button",
      attrs=mark("running-empty-refresh", ["overview", "section", "running", "empty", "refresh"])
        .title("重新读一遍实例与 profile 的读数，读完还空就还是这一张"),
      on_click=emit(RefreshReadings),
      [icon("refresh", size=13), @html.span("刷新读数")],
    ),
  )
  @html.section(
    class="dsh-empty",
    attrs=mark("running-empty", ["overview", "section", "running", "empty"]),
    lines,
  )
}

///|
fn stopped_empty() -> @html.Html {
  @html.section(
    class="dsh-empty",
    attrs=mark("stopped-empty", ["overview", "section", "stopped", "empty"]),
    [
      @html.span(class="dsh-empty-icon", [icon("cube-outline", size=26)]),
      @html.p(class="dsh-empty-line", "还没有已停止的实例。"),
    ],
  )
}

///|
/// 读数还没回来时占位的那一块：**整幅一块**，给不在卡片栅格里的那两处用
/// （日志页、回收站页）—— 那两处的内容本来就不是卡片，条目形状的占位块在那里没有对应物。
/// 实例总览的两个分组走 card_loading（与真条目同形），见下。
///
/// **它与空态是两副样子，这是重点**：空态（running_empty / stopped_empty）说的是
/// 「扫完了，确实没有」；这一块说的是「还没读到」。两者长得一样的话，
/// 刷新之后那段加载时间就会被读成「本机一个实例都没有」。
///
/// 形状刻意跟空态拉开：空态是虚线框 + 居中图标，这里是实线框 + 面板底色。
/// 也没有动效 —— 页面上的动效是启动态状态点专用的（见 styles/app.scss）。
///
/// name 既是 data-name 也是语义路径的最后一段：各处加载态的 name 本来就各不相同
/// （log-loading / trash-loading / running-loading / stopped-loading），
/// 不必再让调用方多传一遍路径。
fn loading_block(name : String, title : String, detail : String) -> @html.Html {
  @html.section(
    class="dsh-loading",
    attrs=mark(name, ["loading", name]).data_set("state", "loading"),
    [
      // 可见的一行字换成三根灰条（§73）：句子对读屏是必要的，对眼睛是噪音。
      @html.div(class="dsh-loading-lines", [
        @html.span(class="dsh-loading-bar bar-1", [@html.nothing]),
        @html.span(class="dsh-loading-bar bar-2", [@html.nothing]),
        @html.span(class="dsh-loading-bar bar-3", [@html.nothing]),
      ]),
      @html.p(class="dsh-sr-only", title),
      @html.p(class="dsh-sr-only", detail),
    ],
  )
}

///|
/// 卡片栅格里的加载态：**与真条目同形**的占位块 + 一行说明。
///
/// 为什么要另起一副形状：卡片瘦成条目之后（图标位 + 名字 / 端口 / 备注），原来那块
/// 「整幅居中 + 一行字」已经不是卡片的样子了 —— 读数回来、卡片一进来，
/// 主区宽度、列数、第一张卡的起点全都要跳一次。这里改成在**同一个栅格**里摆占位块：
/// 外层 .dsh-loading 在栅格下是 display: contents（不生成盒子），里面那条
/// .dsh-skeleton-row 横跨整幅、成为一条栅格项，占位块在它里面用与真卡片**同一套列轨**
/// 摆开，所以「正在读」到「读到了」列轨与宽度不跳。
///
/// **一行封顶**（第十一轮）：这一条盒子只有一行高，第 2 行往后裁掉 —— 6 块占位块在
/// 4 列时铺成两行、2 列时三行，骨架屏会把下面的分组一路顶下去，读数回来再弹回来。
/// 现在任何列数下每个分组最多占一行（一行的高度就是真条目那一行）。
///
/// 与空态的界线照旧（空态是虚线框 + 居中图标）：这里说的是「还没读到」，
/// 不是「扫完了确实没有」。
///
/// 占位块是**静态**灰块：没有 shimmer、没有脉冲 —— 全页的动效只有启动态那颗状态点，
/// 多一个就会被 design/probe-animation.mjs 的「点击前无可见动效」抓到。
/// 它们也不是交互元素：没有 tabindex、没有 role、没有点击处理器，点了没反应；
/// 整块对读屏隐藏（aria-hidden），带语义的只有末尾那一条状态说明（role=status + aria-live）。
///
/// **那一条说明是视觉隐藏的（sr-only）**（第十二轮）：正文里不再出现「正在读取…」那几句 ——
/// 骨架屏本身就代表加载态，再摆四句话是重复。但它一个字都不能删：占位方块对读屏
/// 等于空白，读屏的人要的正是这一条。屏幕上一个像素都不占（见 app.scss 的 .dsh-sr-only）。
///
/// 说明摆在占位块**下面**（不是上面）：这样第一块与将来的第一张卡落在同一个位置，
/// 上下也不跳。说明只此一处，占位块里一个字都不写。
fn card_loading(name : String, title : String, detail : String) -> @html.Html {
  // 摆 6 块：栅格上限就是 6 列，宽屏那一档正好铺满一排。
  // 这个数不是读数 —— 真有几张卡要等读数回来才知道，这里不假装知道。
  let count = 6
  let tiles : Array[@html.Html] = []
  for i = 0; i < count; i = i + 1 {
    tiles.push(
      @html.div(
        class="dsh-skeleton",
        attrs=@html.Attrs::build().aria_hidden("true"),
        [
          // 形状与真条目一一对应（第十轮：左图标竖跨两行 + 右两行），
          // 几何见 app.scss 的 .dsh-skeleton 一节 —— 改一处就得改另一处。
          @html.span(class="dsh-skeleton-tile", @html.nothing),
          @html.div(class="dsh-skeleton-body", [
            @html.span(class="dsh-skeleton-name", @html.nothing),
            @html.span(class="dsh-skeleton-sub", @html.nothing),
          ]),
        ],
      ),
    )
  }
  // 占位块装进一层「最多一行」的盒子：**它就是一条栅格项**（横跨整幅），
  // 里面用与真卡片**同一套列轨**摆那 6 块 —— 一排铺满视口这一档的列数就对了，
  // 多出来的几行被这一层裁掉（见 app.scss 的 .dsh-skeleton-row）。
  // 这样不必在 JS 里量列数，骨架屏也不会把下面的分组顶下去。
  let children : Array[@html.Html] = [
    @html.div(class="dsh-skeleton-row", tiles),
  ]
  // 这一条只给读屏：role=status + aria-live 保留，位置由 .dsh-sr-only 挪出可视区
  // （绝对定位 + 1px + clip）。四句话从可见位拿掉，骨架屏单独代表加载态。
  children.push(
    @html.div(
      class="dsh-loading-note dsh-sr-only",
      attrs=@html.Attrs::build().role("status").aria_live("polite"),
      [
        @html.p(class="dsh-loading-line", title),
        @html.p(class="dsh-loading-sub", detail),
      ],
    ),
  )
  @html.section(
    class="dsh-loading",
    attrs=mark(name, ["loading", name]).data_set("state", "loading"),
    children,
  )
}

///|
/// 抽屉里的一条问题提示：**高度封顶**，不许把抽屉撑高到影响操作（第十二轮）。
///
/// 两副形状，判据是**我们预先知不知道它长什么样**（不是内容长短）：
///   * 已知且可枚举（缺 N 个包这类）：正文压成**一行**（超出省略号），完整清单进悬停；
///   * 自由文本（后端报回来的错误串）：正文**最多两行**（超出省略号），原文进悬停。
/// 形状在 app.scss 的 .dsh-problem 里定死：正文按数据长短自己折行的话，
/// 一行、两行、五行全看数据，抽屉高度就跟着数据跑 ✗
///
/// hint 为空串就不挂悬停 —— 与正文逐字相同的一句不留。
fn problem_hint(
  name : String,
  path : Array[String],
  text : String,
  hint : String,
  free : Bool,
) -> @html.Html {
  let mut attrs = mark(name, path)
  if hint != "" {
    attrs = attrs.title(hint)
  }
  // 正文包一层：**裁剪的那一层不能带竖向内边距**。
  // overflow 是裁在 padding box 上的，所以带 7px 下内边距的卡片会把第 3 行的字头
  // 露在那 7px 里（实测过：第 3 行顶到卡片下边框上方，露出来 7px 字头）✗
  // 现在卡片管边框与内边距、里面那层管「裁几行」，裁剪区正好是两行的内容盒。
  @html.p(
    class=if free {
      "dsh-drawer-health dsh-problem is-free"
    } else {
      "dsh-drawer-health dsh-problem"
    },
    attrs=attrs,
    [@html.span(class="dsh-problem-text", text)],
  )
}

///|
/// 一个字段行：左图标 + 标签 + 右值（值右对齐，超长省略，完整内容在悬停里）。
///
/// 第七轮起它只出现在**详情抽屉**里（卡片只剩：图标 + 状态灯、名字、右上角端口、备注），
/// 所以语义路径是 overview → drawer → 这一行 → field。
/// key 是这一格自己的键（dsh-version / profile / url / home / plugin-count / mtime），
/// card 是它所属那一行的 row.id —— 两份读数里同一格因此是不同的两个 uid。
fn field(
  icon_name : String,
  key : String,
  card : String,
  label : String,
  value : String,
  hint : String,
) -> @html.Html {
  @html.li(
    class="dsh-field",
    attrs=mark("drawer-field", ["overview", "drawer", card, "field", key])
      .data_set("field", key),
    [
      @html.span(class="dsh-field-icon", [icon(icon_name)]),
      @html.span(
        class="dsh-field-label",
        attrs=mark("field-label", ["overview", "drawer", card, "field", key, "label"]),
        label,
      ),
      @html.span(
        class="dsh-field-value",
        attrs=mark("field-value", ["overview", "drawer", card, "field", key, "value"]).title(hint),
        value,
      ),
    ],
  )
}

///|
/// 版本表的一行：每项都是真实读数；读不到就写「读取失败」与原因，不写空。
///
/// 行的键是 label（dsh 版本 / 控制台版本 / 平台 / 读取状态）—— 这几条是固定项，
/// label 就是它们自己的键，不用序号。
fn kv_row(label : String, value : String, hint : String) -> @html.Html {
  @html.div(
    class="dsh-row",
    attrs=mark("kv-row", ["about", "version-row", label]),
    [
      @html.span(
        class="dsh-label",
        attrs=mark("kv-label", ["about", "version-row", label, "label"]),
        label,
      ),
      @html.span(
        class="dsh-value",
        attrs=mark("kv-value", ["about", "version-row", label, "value"]).title(hint),
        value,
      ),
    ],
  )
}

// ── 配置卡片（design/design-fixes.md §25） ───────────────────

///|
/// 一张配置卡要的几格：名字、备注、状态灯与状态词、缺包数、home 归属、
/// 可用性与原因、在不在跑。
///
/// 数据来自总览那一套行与 profile 读数（见 view_maintenance.mbt 的 job_profile_pick），
/// 这里只是卡片自己的入参形状。三个调用点传的是同一份结构，所以卡片只有一份画法。
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
/// 开关组件（design/design-fixes.md §51.1）：MD2 的轨道 + 圆点，没有开/关文字。
///
/// 语义全在 button 上：`role=switch` + `aria-checked` + `aria-label`，键盘 Tab 能到、
/// 空格与回车都能切（button 的原生行为）。视觉只有两件事：圆点停在哪一端、轨道什么颜色。
///
/// `key` 是这一颗的语义路径尾巴（进 data-uid）：同页多颗开关时**必须不一样** ——
/// uid 是路径的哈希，路径一样的两颗会拿到同一个 uid，diff 时分不开谁是谁。
/// 不给时退回 `label`（读屏名字，通常也够唯一）。
fn switch_control(
  on : Bool,
  disabled : Bool,
  label : String,
  title : String,
  on_click : @cmd.Cmd,
  small? : Bool = false,
  key? : String = "",
  elem_id? : String = "",
) -> @html.Html {
  let path = if key == "" { label } else { key }
  let mut cls = "dsh-switch"
  if on {
    cls = cls + " on"
  }
  if small {
    cls = cls + " small"
  }
  @html.button(
    id=elem_id,
    class=cls,
    type_="button",
    disabled=disabled,
    attrs=mark("switch", ["switch", path])
      .role("switch")
      .aria_checked(if on { "true" } else { "false" })
      .aria_label(label)
      .data_set("state", if on { "on" } else { "off" })
      .title(title),
    on_click=on_click,
    [
      // 轨道里只有圆点：开/关文字已经撤掉，状态由位置与颜色表达（§51.1）
      @html.span(
        class="dsh-switch-track",
        [@html.span(class="dsh-switch-thumb", @html.nothing)],
      ),
    ],
  )
}
///|
/// 一条 data-name 路径：前缀 + 这一格的尾巴。
/// 三张卡（新建实例框 / 选择配置 / 替换用源）共用一份画法，差别之一就是前缀，所以路径得拼。
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
/// 一张配置卡：**三行、72px、一律单行省略**（§25 的形态，§26.2 收的高度）。
///
/// 第 1 行 名字 + 状态词（紧跟名字）+ 标记（当前配置 / 已选）；
/// **不再单独挂「在跑」**：状态词就在名字后面，「运行中」与「在跑」是同一件事，
/// 两枚并排只会把名字挤成省略号。
/// 第 2 行 备注，没有就写「没有备注」；
/// 第 3 行 缺包数 + 配置 home 档；不可用的卡第 3 行换成原因（单行省略，全文进悬停）。
///
/// **不再显示**缺包清单与 home 路径：两样都只进悬停（缺包挂在「缺 N 个包」上、路径挂在
/// 「配置 home：…」上，灯的判据挂在灯上、原因的全文挂在原因那一行上）。配置卡本来就没有
/// 「上次启动」这一格，三行里也不新开一格。状态灯挂在图标右上角（图标容器
/// position: relative），不相对整张卡定位 —— 这样卡片能安心 overflow: hidden，
/// 灯也不会因为卡片的裁剪切出一道斜口。
///
/// 三个调用点（新建实例框源卡、维护页选择配置、整体替换选源；见 job_profile_card /
/// promote_source_card / new_instance_source_card）只在五件事上不同：点下去发哪条消息、
/// data-name 前缀、挂不挂「当前配置 / 已选」那枚标记、aria 那句话、是不是当前高亮。
/// 这五件以外，卡片长得一模一样 —— 改一处就是改三处。
fn profile_card(
  pick : ProfilePick,
  card_id : String,
  mark_prefix : String,
  marks : Array[String],
  selected_text : String,
  aria_ok : String,
  aria_bad : String,
  picked : (String) -> Msg,
  emit : @cmd.Emit[Msg],
  chosen? : Bool = false,
) -> @html.Html {
  let usable = pick.usable
  let why = pick.why
  // 状态灯：挂在图标右上角。悬停给两样 —— 先是那句人话，再是技术依据。
  let light_attrs = mark(mark_prefix + "-card-light", mark_path(marks, [pick.name, "light"]))
    .data_set("state", light_key(pick.light))
    .role("img")
    .aria_label(light_label(pick.light))
  let light_attrs = if pick.light_basis == "" {
    light_attrs.title(pick.light_reason)
  } else {
    light_attrs.title(pick.light_reason + "\n" + pick.light_basis)
  }
  // 第 1 行：名字 + 状态词 + 标记。三样都 nowrap，名字先让位（省略号）。
  let head : Array[@html.Html] = [
    @html.span(
      class="dsh-name",
      attrs=mark(mark_prefix + "-card-name", mark_path(marks, [pick.name, "name"])).title(pick.name),
      pick.name,
    ),
    @html.span(
      class="dsh-dot-state " + light_key(pick.light),
      attrs=mark(mark_prefix + "-card-state", mark_path(marks, [pick.name, "state"]))
        .data_set("state", light_key(pick.light))
        .title(pick.light_reason),
      light_label(pick.light),
    ),
  ]
  if selected_text != "" {
    head.push(
      @html.span(
        class="dsh-profile-card-mark selected",
        attrs=mark(mark_prefix + "-card-mark", mark_path(marks, [pick.name, "mark"])),
        selected_text,
      ),
    )
  }
  // 第 2 行：有备注就写备注（人写的，带左侧细线；完整内容与来源在悬停里）；
  // 没有就写「没有备注」。空着与「没有」是两件事，这一行是卡上的固定一格。
  let note_line = if pick.note != "" {
    @html.span(
      class="dsh-card-note",
      attrs=mark(mark_prefix + "-card-note", mark_path(marks, [pick.name, "note"])).title(
        if pick.note_source == "" {
          pick.note
        } else {
          pick.note + "\n（" + pick.note_source + "）"
        },
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
  // 第 3 行：可用时是「缺 N 个包」+「配置 home：<档>」两个短标记（各挂各的悬停）；
  // 不可用时换成原因一行。缺包清单与 home 路径只进悬停，正文一个字都不占。
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
  let meta = if usable {
    @html.div(class="dsh-profile-card-meta", [
      @html.span(class="dsh-profile-card-missing", attrs=missing_attrs, missing_text),
      @html.span(class="dsh-profile-card-home", attrs=home_attrs, job_pick_home_text(pick)),
    ])
  } else {
    // 完整句进悬停：三行钉死之后这一行会被省略号截，被截掉的半句得能读回来。
    @html.span(
      class="dsh-profile-card-sub unusable",
      attrs=mark(mark_prefix + "-card-why", mark_path(marks, [pick.name, "why"])).title(why),
      why,
    )
  }
  let lines : Array[@html.Html] = [@html.div(class="dsh-case-head", head), note_line, meta]
  let click = if usable {
    emit(picked(pick.name))
  } else {
    @cmd.none
  }
  // 选中那一条整张卡再亮一层（底色 + 左侧一道主色竖条）：卡上那枚「已选 / 当前配置」
  // 是文字通道，这里补的是色块通道 —— 不是只靠颜色，也不是只靠一个字。
  let base_class = if usable {
    "dsh-case dsh-profile-card"
  } else {
    "dsh-case dsh-profile-card disabled"
  }
  let card_class = if chosen && usable { base_class + " chosen" } else { base_class }
  @html.article(
    id=card_id,
    class=card_class,
    attrs=mark(mark_prefix + "-card", mark_path(marks, [pick.name]))
      .data_set("usable", if usable { "true" } else { "false" })
      .data_set("group", if pick.running { "running" } else { "stopped" })
      .data_set("chosen", if chosen { "true" } else { "false" })
      .role("button")
      .tabindex(if usable { 0 } else { -1 })
      .aria_disabled(if usable { "false" } else { "true" })
      .aria_label(if usable { aria_ok } else { aria_bad })
      .on_click(fn(_event) { click })
      .on_keydown(fn(event) {
        if usable && (event.key() == "Enter" || event.key() == " ") {
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
        // §26.1：已停止不显示灯。这一档不产出节点（见 state.mbt 的 light_shown），
        // 状态词「已停止」照旧在第一行 —— 颜色不是唯一信号，不画灯也不会少信息。
        if light_shown(pick.light) {
          @html.span(class="dsh-dot " + light_class(pick.light), attrs=light_attrs, @html.nothing)
        } else {
          @html.nothing
        },
      ]),
      @html.div(class="dsh-case-body", lines),
    ],
  )
}

// ── 对话框 ─────────────────────────────────────────────────

///|
/// 遮罩 + 居中层 + 卡片。
///
/// 与 Vue 版的 DOM 有一个刻意的差别：遮罩与卡片在这里是**兄弟**（遮罩 z-index 60、
/// 居中层 61），不是父子。父子结构下点卡片会冒泡到遮罩上，而「只在点遮罩本身时关闭」
/// 需要拿到事件对象判断 target（Vue 用的是 @click.self），rabbita 的 div.on_click 只收
/// Cmd、收不到事件。兄弟结构下「点遮罩关闭」天然成立，卡片自己一个像素都不受影响。
///
/// name 是对话框自己的键（confirm-dialog / rename-dialog / note-dialog），
/// 遮罩与居中层各取一条路径 —— 同一时刻只有一个框，但路径本身写的是「哪一个框」。
fn dialog(
  name : String,
  label : String,
  on_scrim : @cmd.Cmd,
  on_keydown : @cmd.Emit[@html.Keyboard],
  card : @html.Html,
) -> @html.Html {
  @html.fragment([
    @html.div(
      class="dsh-scrim",
      attrs=mark(name + "-scrim", ["dialog", name, "scrim"]),
      on_click=on_scrim,
      @html.nothing,
    ),
    @html.div(
      class="dsh-dialog-wrap",
      attrs=mark(name, ["dialog", name])
        .aria_label(label)
        .role("dialog")
        .aria_modal("true"),
      on_keydown~,
      [card],
    ),
  ])
}
