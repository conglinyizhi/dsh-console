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
/// 读数还没回来时占位的那一块。
///
/// **它与空态是两副样子，这是重点**：空态（running_empty / stopped_empty）说的是
/// 「扫完了，确实没有」；这一块说的是「还没读到」。两者长得一样的话，
/// 刷新之后那段加载时间就会被读成「本机一个实例都没有」。
///
/// 形状刻意跟空态拉开：空态是虚线框 + 居中图标，这里是实线框 + 面板底色。
/// 也没有动效 —— 页面上的动效是启动态状态点专用的（见 styles/app.scss）。
///
/// name 既是 data-name 也是语义路径的最后一段：三处加载态（运行中 / 已停止 / 日志）
/// 的 name 本来就各不相同，不必再让调用方多传一遍路径。
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
/// 卡上的一个字段行：左图标 + 标签 + 右值（值右对齐，超长省略，完整内容在悬停里）。
///
/// key 是这一格自己的键（dsh-version / profile / url / home / plugin-count / mtime），
/// card 是它所在那张卡的 row.id —— 两张卡上同一格因此是不同的两个 uid。
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
    attrs=mark("card-field", ["overview", "card", card, "field", key])
      .data_set("field", key),
    [
      @html.span(class="dsh-field-icon", [icon(icon_name)]),
      @html.span(
        class="dsh-field-label",
        attrs=mark("field-label", ["overview", "card", card, "field", key, "label"]),
        label,
      ),
      @html.span(
        class="dsh-field-value",
        attrs=mark("field-value", ["overview", "card", card, "field", key, "value"]).title(hint),
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
