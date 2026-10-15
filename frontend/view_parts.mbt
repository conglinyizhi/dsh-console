// 页面之间共用的小件：徽标、分组头、空态、字段行、对话框。
//
// 图标本身在 icons.mbt（内联 SVG）。
//
// DOM 上刻意挂 data-name：类名会随样式层换，data-name 不会 ——
// 截图脚本、DOM 实测脚本、渲染基线都按它定位。

///|
/// 数据源徽标：三态各自一个图标与色调，悬停写出这个标记的完整依据。
fn source_badge(tag : SourceTag) -> @html.Html {
  let icon_name = match tag.kind {
    Real => "check"
    Fallback => "shield-outline"
    Demo => "tune"
  }
  let tone = match tag.kind {
    Real => " real"
    Fallback => " fallback"
    Demo => ""
  }
  @html.span(
    class="dsh-badge" + tone,
    attrs=@html.Attrs::build().title(tag.detail).data_set("name", "source-badge"),
    [icon(icon_name, size=12), @html.span(class="dsh-badge-label", tag.label)],
  )
}

///|
/// 分组头：标题 + 计数 + 该组数据的数据源标记。
fn section_head(title : String, count : Int, tag : SourceTag) -> @html.Html {
  @html.div(class="dsh-section-head", [
    @html.h2(class="dsh-section-title", title + " (" + count.to_string() + ")"),
    source_badge(tag),
  ])
}

///|
/// 运行中分组的空态：监听端口扫完、一个 DSH 签名都没命中时才出现，不留假实例占位。
fn running_empty(summary : String, detail : String) -> @html.Html {
  @html.section(
    class="dsh-empty",
    attrs=@html.Attrs::build().data_set("name", "running-empty"),
    [
      @html.span(class="dsh-empty-icon", [icon("server", size=26)]),
      @html.p(class="dsh-empty-line", "当前没有检测到正在运行的 dsh 实例。"),
      @html.p(class="dsh-empty-sub", summary),
      @html.p(class="dsh-empty-sub", attrs=@html.Attrs::build().title(detail), detail),
    ],
  )
}

///|
fn stopped_empty() -> @html.Html {
  @html.section(
    class="dsh-empty",
    attrs=@html.Attrs::build().data_set("name", "stopped-empty"),
    [
      @html.span(class="dsh-empty-icon", [icon("cube-outline", size=26)]),
      @html.p(class="dsh-empty-line", "还没有已停止的实例。"),
    ],
  )
}

///|
/// 卡上的一个字段行：左图标 + 标签 + 右值（值右对齐，超长省略，完整内容在悬停里）。
fn field(
  icon_name : String,
  label : String,
  value : String,
  hint : String,
) -> @html.Html {
  @html.li(class="dsh-field", [
    @html.span(class="dsh-field-icon", [icon(icon_name)]),
    @html.span(class="dsh-field-label", label),
    @html.span(class="dsh-field-value", attrs=@html.Attrs::build().title(hint), value),
  ])
}

///|
/// 版本表的一行：每项都是真实读数；读不到就写「读取失败」与原因，不写空。
fn kv_row(label : String, value : String, hint : String) -> @html.Html {
  @html.div(
    class="dsh-row",
    attrs=@html.Attrs::build().data_set("name", "kv-row"),
    [
      @html.span(class="dsh-label", label),
      @html.span(class="dsh-value", attrs=@html.Attrs::build().title(hint), value),
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
      attrs=@html.Attrs::build().data_set("name", name + "-scrim"),
      on_click=on_scrim,
      @html.nothing,
    ),
    @html.div(
      class="dsh-dialog-wrap",
      attrs=@html.Attrs::build()
        .data_set("name", name)
        .aria_label(label)
        .role("dialog")
        .aria_modal("true"),
      on_keydown~,
      [card],
    ),
  ])
}
