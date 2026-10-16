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
fn running_empty(summary : String, detail : String) -> @html.Html {
  let lines : Array[@html.Html] = [
    @html.span(class="dsh-empty-icon", [icon("server", size=26)]),
    @html.p(class="dsh-empty-line", "当前没有检测到正在运行的 dsh 实例。"),
    @html.p(class="dsh-empty-sub", summary),
  ]
  if detail != "" {
    lines.push(@html.p(class="dsh-empty-sub", attrs=@html.Attrs::build().title(detail), detail))
  }
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
      @html.span(class="dsh-loading-icon", [icon("refresh", size=22)]),
      @html.p(class="dsh-loading-line", title),
      @html.p(class="dsh-loading-sub", detail),
    ],
  )
}

///|
/// 卡片栅格里的加载态：**与真条目同形**的占位块 + 一行说明。
///
/// 为什么要另起一副形状：卡片瘦成条目之后（图标位 + 名字 / 端口 / 备注），原来那块
/// 「整幅居中 + 一行字」已经不是卡片的样子了 —— 读数回来、卡片一进来，
/// 主区宽度、列数、第一张卡的起点全都要跳一次。这里改成在**同一个栅格**里摆占位块：
/// 外层 .dsh-loading 在栅格下是 display: contents（不生成盒子），里面的块直接成为
/// 栅格项，与真卡片共用同一套列轨、间距与断点，所以「正在读」到「读到了」布局不跳。
///
/// 与空态的界线照旧（空态是虚线框 + 居中图标）：这里说的是「还没读到」，
/// 不是「扫完了确实没有」。
///
/// 占位块是**静态**灰块：没有 shimmer、没有脉冲 —— 全页的动效只有启动态那颗状态点，
/// 多一个就会被 design/probe-animation.mjs 的「点击前无可见动效」抓到。
/// 它们也不是交互元素：没有 tabindex、没有 role、没有点击处理器，点了没反应；
/// 整块对读屏隐藏（aria-hidden），带语义的只有末尾那一行说明（role=status + aria-live）。
///
/// 说明摆在占位块**下面**（不是上面）：这样第一块与将来的第一张卡落在同一个位置，
/// 上下也不跳。说明只此一处，占位块里一个字都不写。
fn card_loading(name : String, title : String, detail : String) -> @html.Html {
  // 摆 6 块：栅格上限就是 6 列，宽屏那一档正好铺满一排；窄屏就是 6 行。
  // 这个数不是读数 —— 真有几张卡要等读数回来才知道，这里不假装知道。
  let count = 6
  let children : Array[@html.Html] = []
  for i = 0; i < count; i = i + 1 {
    children.push(
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
  children.push(
    @html.div(
      class="dsh-loading-note",
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
