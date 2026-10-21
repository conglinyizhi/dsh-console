// 抽屉里的「用另一只配置替换这一只」：入口、目标与预览（差异 / 阻断项 / 备注）、选择侧栏。
//
// 2026-10-20 从 view_drawer.mbt 拆出来：这一族是抽屉里最长的一条预览链路，单独成文件。
// 只搬位置，函数体一个字没改。


///|
/// 抽屉「操作」组里那一颗：打开右侧栏去选源，把这一只的配置换成另一只的（§74）。
///
/// 文案只留「换上另一只的配置」：说清动作，不说机制；被换掉哪三份文件、会不会先拍快照，
/// 都在悬停里 —— 点这颗按钮的人先要知道「会发生什么」，细枝末节等打开侧栏再说。
fn promote_launcher(row : Row, emit : @cmd.Emit[Msg]) -> @html.Html {
  let usable = row.profile_name is Some(_) && !row.busy
  @html.button(
    id=promote_open_id(row.id),
    class="dsh-btn",
    type_="button",
    disabled=!usable,
    attrs=mark("drawer-promote-open", ["overview", "drawer", row.id, "action", "promote-open"])
      .data_set("action", "promote-open")
      .title(
        "把这一只的配置（package.json、cordis.patch.yml、pnpm-workspace.yaml）换成另一只的，" +
        "它没有的本地包一起搬过来；替换之前先给这一只拍一张快照，能还原",
      ),
    on_click=emit(PromoteOpen(row.id)),
    [icon("swap-horizontal"), @html.span("换上另一只的配置")],
  )
}
///|
/// 侧栏顶部那一行：被替换的是谁、它属于哪一份 home。路径收进悬停（正文只留一句）。
fn promote_target_block(model : Model) -> @html.Html {
  let (name, home_kind, home_path) = match find_row(model.rows, model.promote_row) {
    Some(row) =>
      (
        match row.profile_name {
          Some(profile) => profile
          None => row.name
        },
        row.home_kind,
        row.home_path,
      )
    None => ("", "", "")
  }
  let home_text = if home_kind == "" { "配置 home 读不到" } else { home_kind_text(home_kind) }
  let attrs = mark("promote-target", ["overview", "promote-sidebar", "target"])
  let attrs = if home_path == "" { attrs } else { attrs.title(home_path) }
  @html.div(class="dsh-drawer-section", [
    @html.h3(
      class="dsh-drawer-section-title",
      attrs=mark("promote-target-title", ["overview", "promote-sidebar", "target", "title"]),
      "目标",
    ),
    @html.p(class="dsh-promote-target", attrs~, name + "（" + home_text + "）"),
  ])
}

///|
/// 四段里的一段：标题 + 若干行。空段写「两边一样」（规格 §17.4 那一句）。
fn promote_section(
  key : String,
  title : String,
  lines : Array[@html.Html],
) -> @html.Html {
  let body = if lines.length() == 0 {
    [@html.p(class="dsh-promote-same", "两边一样")]
  } else {
    lines
  }
  @html.div(
    class="dsh-promote-section",
    attrs=mark("promote-section", ["overview", "promote-sidebar", "section", key]),
    [
      @html.h4(
        class="dsh-promote-title",
        attrs=mark("promote-section-title", ["overview", "promote-sidebar", "section", key, "title"]),
        title,
      ),
      @html.div(class="dsh-promote-lines", body),
    ],
  )
}

///|
/// 一行普通读数（名字 + 一句说明）。
fn promote_line(key : String, name : String, text : String) -> @html.Html {
  @html.div(
    class="dsh-promote-line",
    attrs=mark("promote-line", ["overview", "promote-sidebar", "line", key]),
    [
      @html.span(class="dsh-promote-name", name),
      @html.span(class="dsh-promote-tag", text),
    ],
  )
}

///|
/// 覆盖项里同 id 的两条：并排摆，源那一条标「会盖掉目标这条」。
fn promote_patch_pair(change : PromotePatchChange) -> @html.Html {
  @html.div(
    class="dsh-promote-pair",
    attrs=mark("promote-patch-pair", ["overview", "promote-sidebar", "patch", change.id]),
    [
      @html.div(class="dsh-promote-side source", [
        @html.div(class="dsh-promote-side-head", [
          @html.span(class="dsh-promote-name", change.id),
          @html.span(class="dsh-promote-tag danger", "会盖掉目标这条"),
        ]),
        @html.div(class="dsh-promote-code", change.source_text),
      ]),
      @html.div(class="dsh-promote-side target", [
        @html.div(class="dsh-promote-side-head", [
          @html.span(class="dsh-promote-name", "目标里这一条"),
        ]),
        @html.div(class="dsh-promote-code", change.target_text),
      ]),
    ],
  )
}

///|
/// 覆盖项里新增 / 移除的那一条：id + 原文。
fn promote_patch_entry(key : String, entry : PromotePatchEntry, tag : String) -> @html.Html {
  @html.div(
    class="dsh-promote-entry",
    attrs=mark("promote-patch-entry", ["overview", "promote-sidebar", "patch", key]),
    [
      @html.div(class="dsh-promote-side-head", [
        @html.span(
          class="dsh-promote-name",
          if entry.id == "" { "（这一条没有 id）" } else { entry.id },
        ),
        @html.span(class="dsh-promote-tag", tag),
      ]),
      @html.div(class="dsh-promote-code", entry.text),
    ],
  )
}

///|
/// 四段差异预览（§17.1 的四段 + blockers + 底部按钮）。
fn promote_preview_body(
  preview : PromotePreview,
  model : Model,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  // 插件清单：会多出来的 / 会丢的 / 顺序变了
  let bundle_lines : Array[@html.Html] = []
  for name in preview.bundles_added {
    bundle_lines.push(
      promote_line("bundle-added-" + name, name, "目标里没有，替换后会多出来"),
    )
  }
  for name in preview.bundles_removed {
    bundle_lines.push(
      promote_line("bundle-removed-" + name, name, "目标多出来的，会被移除"),
    )
  }
  if preview.bundles_reordered {
    let before = if preview.bundles_from.length() == 0 {
      "空"
    } else {
      preview.bundles_from.join("、")
    }
    let after = if preview.bundles_to.length() == 0 { "空" } else { preview.bundles_to.join("、") }
    bundle_lines.push(
      @html.p(
        class="dsh-promote-note",
        "顺序会变：今天是 " + before + "，替换后是 " + after,
      ),
    )
  }
  // 覆盖项：同 id 的并排摆
  let patch_lines : Array[@html.Html] = []
  for entry in preview.patches_added {
    patch_lines.push(promote_patch_entry("added-" + entry.id, entry, "目标里没有这一条"))
  }
  for change in preview.patches_changed {
    patch_lines.push(promote_patch_pair(change))
  }
  for entry in preview.patches_removed {
    patch_lines.push(promote_patch_entry("removed-" + entry.id, entry, "目标多出来的，会被移除"))
  }
  if preview.patches_anonymous > 0 {
    patch_lines.push(
      @html.p(
        class="dsh-promote-note",
        "有 " + preview.patches_anonymous.to_string() + " 条没有 id 的条目，只能按整段原文比",
      ),
    )
  }
  // 本地包：会搬过去的 / 同名不同版本的
  let package_lines : Array[@html.Html] = []
  for name in preview.packages_added {
    package_lines.push(promote_line("package-added-" + name, name, "会搬过去"))
  }
  for item in preview.packages_mismatch {
    package_lines.push(
      promote_line(
        "package-version-" + item.name,
        item.name,
        "同名不同版本：源 " + item.source_version + "，目标 " + item.target_version +
        "（不搬也不覆盖）",
      ),
    )
  }
  // 文件：会被写过去的那几份
  let file_lines : Array[@html.Html] = []
  for name in preview.files_written {
    let is_new = preview.files.contains(name)
    file_lines.push(
      promote_line(
        "file-" + name,
        name,
        if is_new { "目标里没有，会新建" } else { "会盖掉目标里那一份" },
      ),
    )
  }
  if preview.files_written.length() == 0 {
    file_lines.push(
      @html.p(class="dsh-promote-note", "源 profile 里这三份文件都没有，这一趟没有可写的"),
    )
  }
  for name in preview.files_target_only {
    file_lines.push(
      promote_line("file-target-only-" + name, name, "目标里有、源里没有，替换之后仍然留着"),
    )
  }
  let can_apply = preview.blockers.length() == 0
  let why = preview.blockers.join("；")
  let note_lines : Array[@html.Html] = []
  for note in preview.notes {
    note_lines.push(@html.p(class="dsh-promote-note", note))
  }
  let blockers_view = if preview.blockers.length() == 0 {
    @html.nothing
  } else {
    @html.div(
      class="dsh-promote-blockers",
      attrs=mark("promote-blockers", ["overview", "promote-sidebar", "blockers"]),
      [
        @html.p(class="dsh-promote-blockers-title", "这一趟不能应用"),
        @html.fragment(blockers_view_lines(preview.blockers)),
      ],
    )
  }
  let busy = match find_row(model.rows, model.promote_row) {
    Some(row) => row.busy
    None => false
  }
  @html.div(class="dsh-promote-preview", [
    blockers_view,
    promote_section("bundles", "插件清单", bundle_lines),
    promote_section("patches", "覆盖项", patch_lines),
    promote_section("packages", "本地包", package_lines),
    promote_section("files", "文件", file_lines),
    if note_lines.length() == 0 {
      @html.nothing
    } else {
      @html.div(class="dsh-promote-section", [
        @html.h4(
          class="dsh-promote-title",
          attrs=mark("promote-notes-title", ["overview", "promote-sidebar", "notes", "title"]),
          "读数备注",
        ),
        @html.div(class="dsh-promote-lines", note_lines),
      ])
    },
    @html.div(class="dsh-promote-foot", [
      @html.button(
        id="dsh-promote-apply",
        class="dsh-btn primary",
        type_="button",
        disabled=!can_apply || busy,
        attrs=mark("promote-apply", ["overview", "promote-sidebar", "apply"])
          .data_set("state", if can_apply { "ready" } else { "blocked" })
          .title(if can_apply { "确认之后会先给目标拍一张快照，再把配置写过去" } else { why }),
        on_click=emit(PromoteConfirmOpen),
        [@html.span(if busy { "正在替换…" } else { "确认替换" })],
      ),
      @html.button(
        class="dsh-btn",
        type_="button",
        disabled=busy,
        attrs=mark("promote-back", ["overview", "promote-sidebar", "back"]),
        on_click=emit(PromoteBack),
        [@html.span("换一只源")],
      ),
    ]),
  ])
}

///|
/// blockers 的每一行。
fn blockers_view_lines(blockers : Array[String]) -> Array[@html.Html] {
  let out : Array[@html.Html] = []
  for text in blockers {
    out.push(
      @html.p(
        class="dsh-promote-blocker",
        attrs=mark("promote-blocker", ["overview", "promote-sidebar", "blocker"]),
        text,
      ),
    )
  }
  out
}

///|
/// 选源那一屏：与「选择配置」同一套分组与卡片，排除目标自己。
fn promote_pick_body(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let target = match find_row(model.rows, model.promote_row) {
    Some(row) =>
      match row.profile_name {
        Some(name) => name
        None => ""
      }
    None => ""
  }
  let facts = job_profile_facts(model)
  let body : Array[@html.Html] = []
  if facts.length() == 0 {
    body.push(
      @html.p(
        class="dsh-empty-sub",
        attrs=mark("promote-empty", ["overview", "promote-sidebar", "empty"]),
        "还没读到 profile 读数，等读数回来再挑。",
      ),
    )
  } else {
    let (running, stopped) = job_profile_picks(model)
    let running_cards : Array[@html.Html] = []
    for pick in running {
      if pick.name != target {
        running_cards.push(promote_source_card(pick, emit))
      }
    }
    let stopped_cards : Array[@html.Html] = []
    for pick in stopped {
      if pick.name != target {
        stopped_cards.push(promote_source_card(pick, emit))
      }
    }
    if running_cards.length() > 0 {
      body.push(promote_pick_group("running", "当前运行的实例", running_cards))
    }
    if stopped_cards.length() > 0 {
      body.push(promote_pick_group("stopped", "已停止的实例", stopped_cards))
    }
    if running_cards.length() == 0 && stopped_cards.length() == 0 {
      body.push(
        @html.p(
          class="dsh-empty-sub",
          attrs=mark("promote-empty", ["overview", "promote-sidebar", "empty"]),
          "本机没有第二只 profile 可以当源。",
        ),
      )
    }
  }
  if model.promote_loading {
    body.push(
      @html.p(
        class="dsh-promote-note",
        attrs=mark("promote-loading", ["overview", "promote-sidebar", "loading"]),
        "正在读差异…",
      ),
    )
  }
  if model.promote_preview_error != "" {
    body.push(
      @html.p(
        class="dsh-promote-error",
        attrs=mark("promote-error", ["overview", "promote-sidebar", "error"]),
        "差异读不出来：" + model.promote_preview_error,
      ),
    )
  }
  @html.div(class="dsh-promote-pick", [
    @html.h3(
      class="dsh-drawer-section-title",
      attrs=mark("promote-pick-title", ["overview", "promote-sidebar", "pick", "title"]),
      "选一只源配置",
    ),
    @html.fragment(body),
  ])
}

fn promote_pick_group(
  key : String,
  title : String,
  cards : Array[@html.Html],
) -> @html.Html {
  @html.div(
    class="dsh-profile-sidebar-group",
    attrs=mark("promote-group", ["overview", "promote-sidebar", "group", key])
      .data_set("group", key),
    [
      @html.h3(
        class="dsh-profile-sidebar-group-title",
        attrs=mark("promote-group-title", ["overview", "promote-sidebar", "group", key, "title"]),
        title + " (" + cards.length().to_string() + ")",
      ),
      @html.div(
        class="dsh-profile-sidebar-list",
        attrs=mark("promote-list", ["overview", "promote-sidebar", "list", key]),
        cards,
      ),
    ],
  )
}

///|
/// 整体替换的右侧栏：与「选择配置」「选择版本」同一套外壳（遮罩 + 右侧面板 + Esc）。
fn promote_sidebar(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let body : Array[@html.Html] = [promote_target_block(model)]
  match model.promote_preview {
    Some(preview) => body.push(promote_preview_body(preview, model, emit))
    None => body.push(promote_pick_body(model, emit))
  }
  @html.fragment([
    @html.div(
      class="dsh-drawer-scrim",
      attrs=mark("promote-sidebar-scrim", ["overview", "promote-sidebar", "scrim"])
        .data_set("state", "open"),
      on_click=emit(PromoteClose),
      @html.nothing,
    ),
    @html.aside(
      id="dsh-promote-sidebar",
      class="dsh-drawer",
      attrs=mark("promote-sidebar", ["overview", "promote-sidebar"])
        .role("dialog")
        .aria_modal("true")
        .aria_label("用另一只配置替换这一只")
        .data_set("state", "open")
        .data_set("stage", if model.promote_preview is Some(_) { "preview" } else { "pick" })
        .on_keydown(fn(event) {
          if event.key() == "Escape" {
            emit(PromoteClose)
          } else {
            @cmd.none
          }
        }),
      [
        @html.div(class="dsh-drawer-head", [
          @html.span(
            class="dsh-drawer-name",
            attrs=mark("promote-sidebar-title", ["overview", "promote-sidebar", "title"]),
            "用另一只配置替换这一只",
          ),
          @html.button(
            id=promote_close_id(),
            class="dsh-btn icon-only",
            type_="button",
            attrs=mark("promote-sidebar-close", ["overview", "promote-sidebar", "close"])
              .aria_label("关闭用另一只配置替换这一只"),
            on_click=emit(PromoteClose),
            [icon("close", size=16)],
          ),
        ]),
        @html.div(class="dsh-drawer-body", body),
      ],
    ),
  ])
}
