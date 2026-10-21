// 分发插件对话框（design/backlog.md N）：选目标（多选，排除自己）→ 看清单 → 输入 MERGE 才可分发。

///|
/// 目标候选：现在读数里的 profile 行，排除源自己。
fn merge_target_rows(model : Model) -> Array[Row] {
  let source = match find_row(model.rows, model.merge_source) {
    Some(row) => row.name
    None => ""
  }
  let out : Array[Row] = []
  for row in model.rows {
    if row.name == source {
      continue
    }
    // 只对「有成对的 profile 名」的行分发：实例行没有 package.json 可补
    match row.profile_name {
      Some(name) =>
        if name != "" {
          out.push(row)
        }
      None => ()
    }
  }
  out
}

///|
fn merge_dialog(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let source = match find_row(model.rows, model.merge_source) {
    Some(row) => row.name
    None => model.merge_source
  }
  // 两步：先选插件（≥1 只）才展开选目标；确认串仍是 MERGE
  let picked_plugins = model.merge_plugin_picked.length() > 0
  let ready = model.merge_confirm == "MERGE" && model.merge_targets.length() > 0 &&
    picked_plugins
  // 第一步：插件（名字 + 版本 + 软链/目录），默认全不选
  let plugin_rows : Array[@html.Html] = []
  if model.merge_loading {
    plugin_rows.push(@html.p(class="dsh-merge-empty", "正在读这一只的插件…"))
  } else if model.merge_plugins.length() == 0 {
    plugin_rows.push(
      @html.p(
        class="dsh-merge-empty",
        attrs=mark("merge-empty", ["dialog", "merge", "empty"]),
        "这一只里没有本地插件（node_modules/@local 与 file:/link: 依赖都是空的）。",
      ),
    )
  } else {
    for plugin in model.merge_plugins {
      let (name, version, kind) = plugin
      let kind_label = match kind {
        "local-link" => "软链"
        "local-dir" => "目录"
        "registry" => "registry（只补声明）"
        _ => "没装上（只补声明）"
      }
      let picked = model.merge_plugin_picked.contains(name)
      plugin_rows.push(
        @html.button(
          class=if picked { "dsh-merge-target on" } else { "dsh-merge-target" },
          type_="button",
          attrs=mark("merge-plugin", ["dialog", "merge", "plugin", name])
            .data_set("picked", if picked { "true" } else { "false" }),
          on_click=emit(MergePluginToggle(name)),
          [
            @html.span(class="dsh-merge-check", if picked { "✓" } else { "" }),
            @html.span(name),
            @html.span(class="dsh-merge-meta", kind_label +
              (if version == "" { "" } else { " · " + version })),
          ],
        ),
      )
    }
  }
  let rows : Array[@html.Html] = []
  for row in merge_target_rows(model) {
    let name = match row.profile_name {
      Some(n) => n
      None => row.name
    }
    let picked = model.merge_targets.contains(name)
    rows.push(
      @html.button(
        class=if picked { "dsh-merge-target on" } else { "dsh-merge-target" },
        type_="button",
        attrs=mark("merge-target", ["dialog", "merge", "target", name])
          .data_set("picked", if picked { "true" } else { "false" }),
        on_click=emit(MergeTargetToggle(name)),
        [
          @html.span(class="dsh-merge-check", if picked { "✓" } else { "" }),
          @html.span(name),
        ],
      ),
    )
  }
  let card = @html.div(class="dsh-dialog-card dsh-merge-card", [
    @html.h2(
      class="dsh-dialog-title",
      attrs=mark("merge-dialog-title", ["dialog", "merge", "title"]),
      "把 " + source + " 的插件分发出去",
    ),
    @html.p(
      class="dsh-dialog-message",
      attrs=mark("merge-dialog-message", ["dialog", "merge", "message"]),
      "每一只目标都会先拍一张快照，再复制 node_modules/@local 下的插件、补 dsh.profile.bundles；" +
      "目标里已有同名插件会被覆盖。cordis.patch.yml 这一版不动。",
    ),
    @html.p(class="dsh-merge-step", "1. 选插件"),
    @html.div(class="dsh-merge-targets", attrs=mark("merge-plugins", ["dialog", "merge", "plugins"]), plugin_rows),
    @html.p(class="dsh-merge-step", "2. 选目标" +
      (if picked_plugins { "" } else { "（先选插件）" })),
    @html.div(
      class="dsh-merge-targets",
      attrs=mark("merge-targets", ["dialog", "merge", "targets"]),
      if picked_plugins { rows } else { [
        @html.p(class="dsh-merge-empty", "选了插件再选目标。"),
      ] },
    ),
    @html.p(
      class="dsh-dialog-message",
      attrs=mark("merge-dialog-preview", ["dialog", "merge", "preview"]),
      "选了 " + model.merge_plugin_picked.length().to_string() + " 只插件，分发到 " +
      model.merge_targets.length().to_string() + " 只；" +
      (if model.merge_targets.length() == 0 { "先勾目标" } else { "输入 MERGE 才能点分发" }),
    ),
    @html.input(
      input_type=Text,
      id="dsh-merge-dialog-input",
      class="dsh-dialog-input",
      value=model.merge_confirm,
      placeholder="输入 MERGE",
      attrs=mark("merge-confirm-input", ["dialog", "merge", "confirm"]),
      on_input=emit.map(fn(text) { MergeConfirmInput(text) }),
    ),
    @html.div(class="dsh-dialog-foot", [
      @html.button(
        id="dsh-merge-dialog-ok",
        class="dsh-dialog-btn primary",
        type_="button",
        disabled=!ready || model.merge_busy,
        attrs=mark("merge-dialog-ok", ["dialog", "merge", "ok"]),
        on_click=emit(MergeSubmit),
        [@html.text(if model.merge_busy { "分发中…" } else { "分发" })],
      ),
      @html.button(
        class="dsh-dialog-btn",
        type_="button",
        attrs=mark("merge-dialog-cancel", ["dialog", "merge", "cancel"]),
        on_click=emit(MergeCancel),
        [@html.text("取消")],
      ),
    ]),
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