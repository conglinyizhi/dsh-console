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
  let ready = model.merge_confirm == "MERGE" && model.merge_targets.length() > 0
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
    @html.div(class="dsh-merge-targets", rows),
    @html.p(
      class="dsh-dialog-message",
      attrs=mark("merge-dialog-preview", ["dialog", "merge", "preview"]),
      "要分发到 " + model.merge_targets.length().to_string() + " 只；" +
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
