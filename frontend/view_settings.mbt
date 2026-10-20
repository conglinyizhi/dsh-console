// 设置页：左索引 + 右条目。
//
// 左：五个分组（实例与端口 / 进程 / 日志 / 界面 / 危险动作），选中态在 model 里。
// 右：当前分组的十个键里的那几个，每项 = 名称 + 说明 + 控件。
// 被改过的那一项（值 ≠ 缺省值）在说明下面多一颗「恢复默认」，值是缺省时那颗不出现。
//
// 三条纪律写在这里：
//   1. 改动即保存（PUT /api/local/settings），成功失败都要有反馈；
//      失败把后端给的错误码与消息原样显示，不吞。
//   2. 后端没提供这个接口时，整页只剩一句「后端还没提供 /api/local/settings」
//      与具体状态行 —— 不拿契约缺省冒充当前值，也不给一排点不动的控件充数。
//   3. 控件里的文本（草稿）与已保存的值分开存：保存失败要把草稿退回去。
//
// 窄屏（< 820px）是两级（design/design-fixes.md §18）：
//   第一级 分区列表（竖排，每行：图标 / 名字 / 条数 / 右箭头），地址 /settings；
//   第二级 返回键 + 该分组的条目，地址 /settings/<分组>。
// 一级二级由地址决定（model.settings_group 是空串还是具体 id），刷新与直达因此落回原处；
// 宽屏两列同屏摆着，这一格只写在 data-level 上，样式表里那一段才用它。

///|
/// 分区列表里某一行的 DOM id：窄屏第二级返回时焦点要还给刚进来的那一行。
fn settings_row_dom_id(group_id : String) -> String {
  "dsh-settings-row-" + group_id
}

///|
/// 窄屏第二级那个返回键的 DOM id：进去之后焦点落在它身上。
fn settings_back_dom_id() -> String {
  "dsh-settings-back"
}

///|
/// 设置页现在是不是窄屏那一档（< 820px）。
///
/// 断点与样式表里那条 media query 是同一个数（styles/app.scss 的
/// .dsh-settings-page 那一节），两处必须一起改。
/// 问它只为一件事：进第二级之后要不要把焦点挪到返回键上 ——
/// 宽屏两列同屏，点索引只是换右边的内容，焦点留在点过的那一行才顺手。
fn narrow_settings_page() -> Bool {
  js_viewport_width() < 820
}

///|
/// 控件里正在编辑的文本。没有草稿就用已保存的值渲染。
fn setting_draft_of(model : Model, key : String) -> String? {
  for draft in model.settings_draft {
    if draft.key == key {
      return Some(draft.text)
    }
  }
  None
}

///|
/// 控件里该显示的文本：草稿优先，其次已保存的值。
fn setting_control_text(model : Model, def : SettingDef) -> String {
  match setting_draft_of(model, def.key) {
    Some(text) => text
    None =>
      match model.settings {
        Some(facts) =>
          match setting_current(facts, def) {
            Some(value) => setting_value_text(value)
            None => ""
          }
        None => ""
      }
  }
}

///|
fn setting_input_attrs(model : Model, def : SettingDef, unit : String) -> @html.Attrs {
  mark("setting-input", ["settings", "row", def.key, "input"])
    .aria_label(def.label)
    .title(
      setting_fallback_text(def) + (if unit == "" { "" } else { " | 单位" + unit }),
    )
    .disabled(model.settings_saving == def.key)
}

///|
/// 数字输入：on_input 记草稿、on_change（回车 / 失焦）提交。
fn setting_number_control(
  model : Model,
  def : SettingDef,
  min : Int,
  max : Int,
  unit : String,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  @html.input(
    input_type=Number,
    id="dsh-setting-" + def.key,
    class="dsh-setting-input",
    value=setting_control_text(model, def),
    min~,
    max~,
    attrs=setting_input_attrs(model, def, unit),
    on_input=emit.map(fn(text) { SettingDraft(def.key, text) }),
    on_change=emit.map(fn(text) { SettingCommit(def.key, text) }),
  )
}

///|
/// 开关：没有中间态，点一下就是一次 PUT。role=switch + aria-checked 是它的语义面。
fn setting_switch_control(
  model : Model,
  def : SettingDef,
  current : SettingValue?,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let on = match current {
    Some(VBool(value)) => value
    _ => false
  }
  let known = match current {
    Some(VBool(_)) => true
    _ => false
  }
  @html.button(
    class=if on { "dsh-switch on" } else { "dsh-switch" },
    type_="button",
    disabled=!known || model.settings_saving == def.key,
    attrs=mark("setting-switch", ["settings", "row", def.key, "switch"])
      .role("switch")
      .aria_checked(if on { "true" } else { "false" })
      .aria_label(def.label)
      .title(setting_fallback_text(def)),
    on_click=emit(SettingToggle(def.key, !on)),
    [
      @html.span(class="dsh-switch-knob", @html.nothing),
      @html.span(class="dsh-switch-text", if on { "开" } else { "关" }),
    ],
  )
}

///|
/// 枚举：原生 select，与日志页的来源下拉同一副皮。
fn setting_select_control(
  model : Model,
  def : SettingDef,
  current : SettingValue?,
  options : Array[Int],
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let current_int = match current {
    Some(VInt(n)) => Some(n)
    _ => None
  }
  let items : Array[@html.Html] = []
  let listed = match current_int {
    Some(n) => options.contains(n)
    None => false
  }
  if !listed {
    match current_int {
      Some(n) =>
        items.push(
          @html.option(
            value=n.to_string(),
            selected=true,
            [@html.text(n.to_string() + " 行（这个值不在候选项里）")],
          ),
        )
      None =>
        items.push(
          @html.option(
            value="",
            selected=true,
            disabled=true,
            [@html.text("没读到")],
          ),
        )
    }
  }
  for n in options {
    items.push(
      @html.option(
        value=n.to_string(),
        selected=current_int == Some(n),
        [@html.text(n.to_string() + " 行")],
      ),
    )
  }
  @html.select(
    id="dsh-setting-" + def.key,
    class="dsh-select",
    disabled=current_int is None || model.settings_saving == def.key,
    attrs=mark("setting-select", ["settings", "row", def.key, "select"])
      .aria_label(def.label)
      .title(setting_fallback_text(def)),
    on_change=emit.map(fn(text) { SettingCommit(def.key, text) }),
    items,
  )
}

///|
/// 一个条目：左半边名称 + 说明（改过的话多一颗「恢复默认」），右半边控件。
///
/// 这里曾经还挂着一行元信息（「当前 5000 | 来源 文件 | 缺省 5000」）。它整行删掉了：
/// 当前值在右边的控件里本来就看得见，而「来源」「缺省」是给改这个工具的人看的东西，
/// 用它的人不需要知道。需要退回去的时候，那颗「恢复默认」只在**真被改过**时才出现
/// （见 setting_reset_button）—— 没改过的项上，它一个节点都不产出。
fn setting_row(model : Model, def : SettingDef, emit : @cmd.Emit[Msg]) -> @html.Html {
  let facts = model.settings
  let current = match facts {
    Some(got) => setting_current(got, def)
    None => None
  }
  let value_text = match current {
    Some(value) => setting_value_text(value)
    None => "没读到"
  }
  let source_text = match facts {
    Some(got) => setting_source(got, def)
    None => "没读到"
  }
  let control = match def.kind {
    CNum(min, max, unit) => setting_number_control(model, def, min, max, unit, emit)
    CBool => setting_switch_control(model, def, current, emit)
    CList(options) => setting_select_control(model, def, current, options, emit)
  }
  let saving = model.settings_saving == def.key
  // 值还是缺省 → 一颗「恢复默认」都不摆（不是摆成禁用态：那个位置上本来就不该有东西）
  let changed = match facts {
    Some(got) => !setting_is_default(got, def)
    None => false
  }
  @html.div(
    class="dsh-setting",
    attrs=mark("setting-row", ["settings", "row", def.key])
      .data_set("setting", def.key)
      .data_set("value", value_text)
      .data_set("source", source_text)
      // 键名是给排查用的，摆在标题旁边太嘈杂 —— 收进悬停
      .title(def.label + "：设置文件里的键名是 " + def.key),
    [
      @html.div(class="dsh-setting-main", [
        // 可见的只有人话名称，键名在行悬停里
        @html.div(class="dsh-setting-title", [
          @html.span(
            class="dsh-setting-name",
            attrs=mark("setting-name", ["settings", "row", def.key, "name"]),
            def.label,
          ),
        ]),
        @html.p(
          class="dsh-setting-desc",
          attrs=mark("setting-desc", ["settings", "row", def.key, "desc"]),
          def.desc,
        ),
        if changed {
          setting_reset_button(model, def, emit)
        } else {
          @html.nothing
        },
      ]),
      @html.div(class="dsh-setting-control", [
        control,
        if saving {
          @html.span(
            class="dsh-setting-saving",
            attrs=mark("setting-saving", ["settings", "row", def.key, "saving"]),
            "保存中…",
          )
        } else {
          @html.nothing
        },
      ]),
    ],
  )
}

///|
/// 这一项是不是**还没被改过**（当前值与缺省值相等）。
///
/// 三档分开办：两个值都读到且相等 → true（项上不摆「恢复默认」）；读到且不等 → false（摆）；
/// 有一个读不到 → true（**不摆**）。最后一档是刻意的：既不知道它是不是被改过，
/// 也不知道该写回哪个数 —— 摆一颗点下去会写错数的入口，比不摆糟得多。
fn setting_is_default(facts : SettingsFacts, def : SettingDef) -> Bool {
  match (setting_current(facts, def), lookup_setting(facts.defaults, def.key)) {
    (Some(current), Some(default)) => current == default
    _ => true
  }
}

///|
/// 「恢复默认」那一颗 —— 只在**这一项的值不等于缺省值**时才调用（值是缺省时一个节点都不产出）。
///
/// 缺省值取的是后端给的 defaults，不是本地契约表：两边不一致时，该写回去的是后端的口径。
/// 缺省值多少收进悬停，正文不占 —— 那是「想退回去」的时候才需要读的一句话。
fn setting_reset_button(model : Model, def : SettingDef, emit : @cmd.Emit[Msg]) -> @html.Html {
  @html.button(
    class="dsh-setting-reset",
    type_="button",
    disabled=model.settings_saving == def.key,
    attrs=mark("setting-reset", ["settings", "row", def.key, "reset"])
      .title("把这一项写回" + setting_fallback_text(def))
      .aria_label("把" + def.label + "恢复为出厂缺省值"),
    on_click=emit(SettingReset(def.key)),
    [icon("refresh", size=12), @html.span("恢复默认")],
  )
}

///|
/// 分区索引：五个分组。当前选中的那个带 .active 与 aria-current。
///
/// 宽屏是一列索引（点它就是换右边那一栏），窄屏是第一级的分区列表（点它是进第二级）。
/// 同一份节点，差别全在样式表里：右箭头只在窄屏显示。
fn settings_index(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let current = setting_group_of(model.settings_group)
  let items : Array[@html.Html] = []
  for group in settings_groups {
    let active = group.id == current.id
    items.push(
      @html.button(
        class=if active { "dsh-settings-tab active" } else { "dsh-settings-tab" },
        type_="button",
        id=settings_row_dom_id(group.id),
        attrs=mark("settings-tab", ["settings", "tab", group.id])
          .data_set("group", group.id)
          .aria_current(if active { "true" } else { "false" }),
        on_click=emit(SettingsGroupPicked(group.id)),
        [
          @html.span(class="dsh-settings-tab-icon", [icon(group.icon, size=15)]),
          @html.span(class="dsh-settings-tab-label", group.label),
          @html.span(
            class="dsh-settings-tab-count",
            settings_group_count(group.id).to_string(),
          ),
          // 「这一行后面还有内容」的提示：窄屏靠它说清「点进去」是下一步
          @html.span(class="dsh-settings-tab-arrow", [icon("chevron-right", size=16)]),
        ],
      ),
    )
  }
  @html.aside(
    class="dsh-settings-index",
    attrs=mark("settings-index", ["settings", "index"]),
    items,
  )
}

///|
/// 右侧条目面板。
fn settings_panel(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let group = setting_group_of(model.settings_group)
  let defs = settings_table.filter(fn(def) { def.group == group.id })
  @html.div(class="dsh-settings-body", [
    settings_index(model, emit),
    @html.div(
      class="dsh-settings-panel",
      attrs=mark("settings-panel", ["settings", "panel"]),
      [
        @html.h2(class="dsh-settings-panel-title", group.label),
        @html.p(class="dsh-settings-panel-note", group.note),
        @html.div(class="dsh-settings-rows", defs.map(fn(def) { setting_row(model, def, emit) })),
      ],
    ),
  ])
}

///|
/// 后端还没提供接口（404 / 501）与其它失败：都不显示条目，只显示这一块。
/// 差别只在措辞：前者说明「接口不在」，后者把后端给的原因摆出来。
fn settings_error_panel(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let missing = model.settings_endpoint_missing
  let title = if missing {
    "这一版还没有设置这一页"
  } else {
    "设置没能读到"
  }
  // 状态行是排查用的（端点、状态码），收进悬停：正文只说「读不到」这件事本身
  let detail = if model.settings_status > 0 {
    "读设置失败：HTTP " +
    model.settings_status.to_string() +
    " " +
    model.settings_status_text
  } else {
    "读设置这一枪没发出去"
  }
  let status_line = if missing {
    "这台控制台还没提供设置这一页要的读数。"
  } else {
    "读设置这一步没能完成。"
  }
  let hint = if missing {
    "读不到时不摆任何条目：拿猜出来的数填上去，比空着更容易误导。"
  } else {
    model.settings_error
  }
  @html.div(
    class="dsh-settings-error",
    attrs=mark("settings-error", ["settings", "error"]),
    [
      @html.h2(class="dsh-settings-error-title", title),
      @html.p(
        class="dsh-settings-error-status",
        attrs=@html.Attrs::build().title(detail),
        status_line,
      ),
      @html.p(class="dsh-settings-error-hint", hint),
      @html.div(class="dsh-settings-error-foot", [
        @html.button(
          class="dsh-settings-retry",
          type_="button",
          disabled=model.settings_loading,
          attrs=mark("settings-retry", ["settings", "retry"]),
          on_click=emit(SettingsRetry),
          [icon("refresh", size=13), @html.span("重新读取")],
        ),
      ]),
    ],
  )
}

///|
/// 窄屏第二级顶部那个返回键。
///
/// 宽屏整行不摆（样式表里 display: none）：两列那一档没有一级二级，
/// 索引一直在左边，多一颗「返回列表」的键反而是噪音。
/// 分区名不写在这颗键里 —— 它是紧跟着的面板标题那一行，不重复两遍。
fn settings_back_row(emit : @cmd.Emit[Msg]) -> @html.Html {
  @html.div(class="dsh-settings-back-row", [
    @html.button(
      class="dsh-settings-back",
      type_="button",
      id=settings_back_dom_id(),
      attrs=mark("settings-back", ["settings", "back"])
        .aria_label("返回设置分区列表"),
      on_click=emit(SettingsBack),
      [@html.span("‹ 设置")],
    ),
  ])
}

///|
/// 设置页。
fn settings_view(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let body = if model.settings_loading && !model.settings_loaded {
    @html.div(
      class="dsh-settings-hint",
      attrs=mark("settings-loading", ["settings", "loading"]),
      "正在读设置…",
    )
  } else if model.settings_error.length() > 0 {
    settings_error_panel(model, emit)
  } else {
    match model.settings {
      Some(_) => settings_panel(model, emit)
      None =>
        @html.div(
          class="dsh-settings-hint",
          attrs=mark("settings-loading", ["settings", "loading"]),
          "设置还没读。",
        )
    }
  }
  // 一级二级只由地址决定：settings_group 是空串 = 没有指定分组 = 第一级。
  // 宽屏两列同屏，这一个标记在那一档不起作用（样式表只在窄屏那一段读它）。
  let level = if model.settings_group == "" { "list" } else { "panel" }
  @html.section(
    class="dsh-settings-page",
    attrs=mark("settings-page", ["settings", "page"]).data_set("level", level),
    [
      @html.header(class="dsh-settings-head", [
        @html.h1(class="dsh-page-title", "设置"),
        source_badge(model.tag_settings, ["settings", "head", "source-badge"]),
      ]),
      // 落盘路径是排查用的细节，收进悬停：使用者只需要知道「改动即保存」
      @html.p(
        class="dsh-settings-note",
        attrs=mark("settings-note", ["settings", "note"]).title(
          "每个键单独保存一次；落盘位置 $XDG_STATE_HOME/dsh-console/settings.json",
        ),
        "改动即保存。",
      ),
      // 窄屏第二级的返回键（宽屏不显示）
      settings_back_row(emit),
      // 保存成功 / 失败从 §14 起走外壳那一条全局提示：本页不留第二份（§14.4）
      body,
    ],
  )
}
