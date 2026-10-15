// 设置页：左索引 + 右条目。
//
// 左：五个分组（实例与端口 / 进程 / 日志 / 界面 / 危险动作），选中态在 model 里。
// 右：当前分组的九个键里的那几个，每项 = 名称 + 说明 + 控件 + 「当前值 / 来源」。
//
// 三条纪律写在这里：
//   1. 改动即保存（PUT /api/local/settings），成功失败都要有反馈；
//      失败把后端给的错误码与消息原样显示，不吞。
//   2. 后端没提供这个接口时，整页只剩一句「后端还没提供 /api/local/settings」
//      与具体状态行 —— 不拿契约缺省冒充当前值，也不给一排点不动的控件充数。
//   3. 控件里的文本（草稿）与已保存的值分开存：保存失败要把草稿退回去。

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
      setting_fallback_text(def) + (if unit == "" { "" } else { " · 单位" + unit }),
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
            [@html.text(n.to_string() + " 行（当前值，不在候选里）")],
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
/// 一个条目：左半边名称 + 说明 + 「当前值 / 来源」，右半边控件。
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
  // 元信息：来源是「默认」时，当前值与缺省本来就是同一个数，说一遍就够；
  // 只有被文件改过才需要「当前 X · 缺省 Y」两栏对照。
  let default_short = setting_default_short(model, def)
  let meta : Array[@html.Html] = if source_text == "默认" {
    [@html.span(class="dsh-setting-default", "默认 " + default_short)]
  } else {
    [
      @html.span(class="dsh-setting-current", "当前 " + value_text),
      @html.span(class="dsh-setting-sep", "·"),
      @html.span(class="dsh-setting-source", "来源 " + source_text),
      @html.span(class="dsh-setting-sep", "·"),
      @html.span(class="dsh-setting-default", "缺省 " + default_short),
    ]
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
        @html.div(
          class="dsh-setting-meta",
          attrs=mark("setting-meta", ["settings", "row", def.key, "meta"]),
          meta,
        ),
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
/// 「缺省」一栏取的是后端给的 defaults（不是本地的契约表）：
/// 两边不一致时该看见的是后端的口径。
fn setting_default_short(model : Model, def : SettingDef) -> String {
  match model.settings {
    Some(facts) =>
      match lookup_setting(facts.defaults, def.key) {
        Some(value) => setting_value_text(value)
        None => "没读到"
      }
    None => "—"
  }
}

///|
/// 左侧索引：五个分组。当前选中的那个带 .active 与 aria-current。
fn settings_index(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let items : Array[@html.Html] = []
  for group in settings_groups {
    let active = group.id == model.settings_group
    items.push(
      @html.button(
        class=if active { "dsh-settings-tab active" } else { "dsh-settings-tab" },
        type_="button",
        attrs=mark("settings-tab", ["settings", "tab", group.id])
          .data_set("group", group.id)
          .aria_current(if active { "true" } else { "false" }),
        on_click=emit(SettingsGroupPicked(group.id)),
        [
          @html.span(class="dsh-settings-tab-icon", [icon(group.icon, size=15)]),
          @html.span(class="dsh-settings-tab-label", group.label),
          @html.span(
            class="dsh-settings-tab-count",
            settings_table
            .filter(fn(def) { def.group == group.id })
            .length()
            .to_string(),
          ),
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
    "GET /api/local/settings → HTTP " +
    model.settings_status.to_string() +
    " " +
    model.settings_status_text
  } else {
    "GET /api/local/settings 的请求没发出去"
  }
  let status_line = if missing {
    "这台控制台还没提供设置这一页要的读数。"
  } else {
    "读设置这一步没能完成。"
  }
  let hint = if missing {
    "读不到时不摆任何条目：把猜出来的缺省值当成当前值填上去，比空着更容易误导。"
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
/// 保存反馈：成功与失败各一条，失败里带后端给的原因。没有反馈时不占位。
fn settings_feedback(model : Model) -> @html.Html {
  if model.settings_feedback.length() == 0 {
    return @html.nothing
  }
  let tone = if model.settings_feedback_ok { " ok" } else { " err" }
  @html.p(
    class="dsh-settings-feedback" + tone,
    attrs=mark("settings-feedback", ["settings", "feedback"])
      .data_set("ok", if model.settings_feedback_ok { "true" } else { "false" }),
    model.settings_feedback,
  )
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
  @html.section(
    class="dsh-settings-page",
    attrs=mark("settings-page", ["settings", "page"]),
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
      settings_feedback(model),
      body,
    ],
  )
}
