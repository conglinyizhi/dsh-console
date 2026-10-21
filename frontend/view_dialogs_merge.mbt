// 分发插件对话框（design/backlog.md N 第五版）：一个对话框内分两步 —— 选插件 / 选目标。
// 一行一只：左边图标位、中间名字（粗）+ 来源与版本、下面 description，右边开关（small）。

///|
/// 第一步行：一只插件。
fn merge_plugin_row(model : Model, name : String, version : String, kind : String, description : String, emit : @cmd.Emit[Msg]) -> @html.Html {
  let picked = model.merge_plugin_picked.contains(name)
  let kind_label = match kind {
    "local-link" => "软链"
    "local-dir" => "目录"
    "registry" => "registry"
    _ => "没装上"
  }
  let meta = kind_label + (if version == "" { "" } else { " · " + version })
  @html.div(
    class=if picked { "dsh-merge-row on" } else { "dsh-merge-row" },
    attrs=mark("merge-plugin", ["dialog", "merge", "plugin", name])
      .id("dsh-merge-plugin-" + name)
      .data_set("picked", if picked { "true" } else { "false" })
      .role("button")
      .on_click(fn(_event) { emit(MergePluginToggle(name)) }),
    [
      @html.span(class="dsh-merge-ico", [icon("puzzle-outline", size=16)]),
      @html.div(class="dsh-merge-main", [
        @html.div(class="dsh-merge-name", name),
        @html.div(class="dsh-merge-meta", meta),
        if description == "" {
          @html.nothing
        } else {
          @html.div(class="dsh-merge-desc", description)
        },
      ]),
      // 开关只是这一段的状态显示（整行才是可点的那个）；id 带行名，不重复
      @html.span(
        class=if picked { "dsh-switch small on" } else { "dsh-switch small" },
        attrs=mark("merge-plugin-switch", ["dialog", "merge", "plugin-switch", name])
          .id("dsh-merge-plugin-switch-" + name)
          .aria_hidden("true"),
        @html.nothing,
      ),
    ],
  )
}

///|
/// 第二步行：一只目标。
fn merge_target_row(model : Model, row : Row, emit : @cmd.Emit[Msg]) -> @html.Html {
  let name = match row.profile_name {
    Some(n) => n
    None => row.name
  }
  let picked = model.merge_targets.contains(name)
  let port_part = match row.port_value {
    Some(p) => " · 端口 " + p.to_string()
    None => ""
  }
  let meta = row.kind + port_part
  @html.div(
    class=if picked { "dsh-merge-row on" } else { "dsh-merge-row" },
    attrs=mark("merge-target", ["dialog", "merge", "target", name])
      .id("dsh-merge-target-" + name)
      .data_set("picked", if picked { "true" } else { "false" })
      .role("button")
      .on_click(fn(_event) { emit(MergeTargetToggle(name)) }),
    [
      @html.span(class="dsh-merge-ico", [icon("cube-outline", size=16)]),
      @html.div(class="dsh-merge-main", [
        @html.div(class="dsh-merge-name", row.name),
        @html.div(class="dsh-merge-meta", meta),
      ]),
      @html.span(
        class=if picked { "dsh-switch small on" } else { "dsh-switch small" },
        attrs=mark("merge-target-switch", ["dialog", "merge", "target-switch", name])
          .id("dsh-merge-target-switch-" + name)
          .aria_hidden("true"),
        @html.nothing,
      ),
    ],
  )
}

///|
fn merge_dialog(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let source = match find_row(model.rows, model.merge_source) {
    Some(row) => row.name
    None => model.merge_source
  }
  let picked_plugins = model.merge_plugin_picked.length() > 0
  let step = model.merge_step
  let step1 : Array[@html.Html] = []
  if model.merge_loading {
    step1.push(@html.p(class="dsh-merge-empty", "正在读这一只的插件…"))
  } else if model.merge_plugins.length() == 0 {
    step1.push(
      @html.p(
        class="dsh-merge-empty",
        attrs=mark("merge-empty", ["dialog", "merge", "empty"]),
        "这一只里没有可分发或可声明的插件。",
      ),
    )
  } else {
    let local_rows : Array[@html.Html] = []
    let other_rows : Array[@html.Html] = []
    for plugin in model.merge_plugins {
      let (name, version, kind, description) = plugin
      let line = merge_plugin_row(model, name, version, kind, description, emit)
      if kind == "local-dir" || kind == "local-link" {
        local_rows.push(line)
      } else {
        other_rows.push(line)
      }
    }
    if local_rows.length() > 0 {
      step1.push(
        @html.p(
          class="dsh-merge-group",
          attrs=mark("merge-group-local", ["dialog", "merge", "group", "local"]),
          "本地插件（可分发实体）",
        ),
      )
      for r in local_rows {
        step1.push(r)
      }
    }
    if other_rows.length() > 0 {
      step1.push(
        @html.p(
          class="dsh-merge-group",
          attrs=mark("merge-group-other", ["dialog", "merge", "group", "other"]),
          "已安装的其它插件（只补声明）",
        ),
      )
      for r in other_rows {
        step1.push(r)
      }
    }
  }
  let step2 : Array[@html.Html] = []
  if !picked_plugins {
    step2.push(@html.p(class="dsh-merge-empty", "先回到上一步选插件。"))
  } else {
    let source_name = match find_row(model.rows, model.merge_source) {
      Some(r) => merge_row_name(r)
      None => ""
    }
    for row in model.rows {
      match row.profile_name {
        Some(n) =>
          if n != "" && n != source_name {
            step2.push(merge_target_row(model, row, emit))
          }
        None => ()
      }
    }
  }
  let why = if !picked_plugins {
    "先在第一步选至少一只插件"
  } else if model.merge_targets.length() == 0 {
    "再勾至少一只目标"
  } else if model.merge_busy {
    "正在分发…"
  } else {
    ""
  }
  let foot : Array[@html.Html] = []
  if step == 1 {
    foot.push(
      @html.button(
        class="dsh-dialog-btn",
        type_="button",
        disabled=!picked_plugins,
        attrs=mark("merge-step-next", ["dialog", "merge", "step", "next"]),
        on_click=emit(MergeStepNext),
        [@html.text("下一步")],
      ),
    )
  } else {
    foot.push(
      @html.button(
        class="dsh-dialog-btn",
        type_="button",
        attrs=mark("merge-step-prev", ["dialog", "merge", "step", "prev"]),
        on_click=emit(MergeStepPrev),
        [@html.text("上一步")],
      ),
    )
  }
  foot.push(
    @html.button(
      class="dsh-dialog-btn",
      type_="button",
      attrs=mark("merge-dialog-cancel", ["dialog", "merge", "cancel"]),
      on_click=emit(MergeCancel),
      [@html.text("取消")],
    ),
  )
  let card = @html.div(class="dsh-dialog-card dsh-merge-card", [
    @html.h2(
      class="dsh-dialog-title",
      attrs=mark("merge-dialog-title", ["dialog", "merge", "title"]),
      if step == 1 { "把 " + source + " 的插件分发出去" } else { "分发到哪几只" },
    ),
    @html.p(
      class="dsh-dialog-message",
      attrs=mark("merge-dialog-message", ["dialog", "merge", "message"]),
      if step == 1 {
        "第 1 / 2 步：选插件。勾上的会被分发；registry 只补声明，实体要目标自己补包。"
      } else {
        "第 2 / 2 步：选目标。每只先拍快照，再复制实体插件、补 bundles；cordis.patch.yml 不动。"
      },
    ),
    @html.div(
      class="dsh-merge-list",
      attrs=mark("merge-step", ["dialog", "merge", "step"]).data_set("step", step.to_string()),
      if step == 1 {
        step1
      } else {
        step2
      },
    ),
    if step == 2 && picked_plugins {
      @html.div(
        class="dsh-merge-slide",
        attrs=mark("merge-confirm", ["dialog", "merge", "confirm"])
          .id("dsh-merge-slide")
          .tabindex(0)
          .data_set("slide", model.merge_slide.to_string())
          .aria_label("向右滑动分发")
          .title("拖到最右端（或按 End / 方向键到最右）才分发；松手没到位会弹回")
          .on_pointerdown(fn(_event) {
            // 按下只置「正在拖」：位移交给 pointermove（它只在拖动期间生效）。
            emit(MergeSlideStart)
          })
          .on_pointermove(fn(event) {
            emit(MergeSlide(js_slide_percent("dsh-merge-slide", event.get_client_x())))
          })
          .on_pointerup(fn(_event) { emit(MergeSlideRelease) })
          .on_keydown(fn(event) {
            let key = event.key()
            if key == " " {
              emit(MergeSlideKey("Space"))
            } else {
              emit(MergeSlideKey(key))
            }
          }),
        [
          @html.span(class="dsh-merge-slide-hint", "向右滑动分发"),
          @html.div(
            class="dsh-merge-slide-knob",
            style=["left: " + model.merge_slide.to_string() + "%"],
            attrs=mark("merge-knob", ["dialog", "merge", "knob"]),
            [icon("send", size=14)],
          ),
        ],
      )
    } else {
      @html.nothing
    },
    @html.p(
      class="dsh-merge-why",
      attrs=mark("merge-dialog-preview", ["dialog", "merge", "preview"]).data_set("why", why),
      if why == "" {
        "选了 " + model.merge_plugin_picked.length().to_string() + " 只插件，分发到 " +
        model.merge_targets.length().to_string() + " 只；拖到底才分发"
      } else {
        why
      },
    ),
    @html.div(class="dsh-dialog-foot", foot),
  ])
  dialog(
    "merge-dialog",
    "分发插件",
    emit(MergeCancel),
    emit.map(fn(key : @html.Keyboard) {
      if key.key() == "Escape" {
        MergeCancel
      } else {
        Noop
      }
    }),
    card,
  )
}