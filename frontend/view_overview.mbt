// 实例总览页。
//
// 两条分组（当前运行 / 已停止）+ 归档区 + 右栏信息面板，卡片的版式照 Vue 版逐项对齐：
// 两行卡头（标题行 + 副标题行）、状态点独立 13px 槽位、字段区固定两列、按钮组右缘贴卡片内容盒。
//
// md2 的用法是**收窄的**：card（外壳）/ icon（字形）/ btn（仅卡上那四个动作按钮，
// 那一组的形状在 dsh-skin.scss 里已经量过）。其余按钮走我们自己移植过来的类 ——
// md2 的 .v-btn 形状是 30px 无内边距差，皮肤层按 (0,2,1) 压过我们的 (0,1,0)，
// 归档行 28px、对话框 padding 0 14px、新建实例 32px 这些值会被它改掉，属于几何回归。

///|
priv enum MenuEntry {
  MItem(ActionKey, String, String, Bool)
  MSep
}

///|
fn action_name(key : ActionKey) -> String {
  match key {
    OpenUi => "open-ui"
    Toggle => "toggle"
    Restart => "restart"
    Tab => "tab"
    CopyUrl => "copy-url"
    Fork => "fork"
    Rename => "rename"
    Archive => "archive"
    Unarchive => "unarchive"
    Delete => "delete"
    Logs => "logs"
    Dir => "dir"
    Config => "config"
  }
}

///|
/// 运行中：重命名 / 派生 / 归档靠上，运维三项沉底；删除只给可删实例。
fn running_menu(deletable : Bool) -> Array[MenuEntry] {
  let items : Array[MenuEntry] = [
    MItem(Tab, "mdi-open-in-new", "在新标签页打开", false),
    MItem(CopyUrl, "mdi-link-variant", "复制访问地址", false),
    MSep,
    MItem(Rename, "mdi-rename-outline", "重命名", false),
    MItem(Fork, "mdi-source-fork", "派生开发副本", false),
    MItem(Archive, "mdi-archive-outline", "归档", false),
  ]
  if deletable {
    items.push(MItem(Delete, "mdi-delete-outline", "删除", true))
  }
  items.push(MSep)
  items.push(MItem(Logs, "mdi-text-box-outline", "查看日志", false))
  items.push(MItem(Dir, "mdi-folder-open-outline", "打开工作目录", false))
  items.push(MItem(Config, "mdi-tune", "编辑配置", false))
  items
}

///|
/// 已停止：下拉入口在「启动」右半的 caret 上；可删实例也能直接把删除放进菜单。
fn stopped_menu(deletable : Bool) -> Array[MenuEntry] {
  let items : Array[MenuEntry] = [
    MItem(Logs, "mdi-text-box-outline", "查看日志", false),
    MItem(Dir, "mdi-folder-open-outline", "打开工作目录", false),
    MItem(Config, "mdi-tune", "编辑配置", false),
    MSep,
    MItem(Rename, "mdi-rename-outline", "重命名", false),
    MItem(Archive, "mdi-archive-outline", "归档", false),
  ]
  if deletable {
    items.push(MItem(Delete, "mdi-delete-outline", "删除", true))
  }
  items
}

///|
/// 下拉菜单。锚点挂在按钮组容器上（.dsh-actions 是 position: relative），
/// 所以右缘与按钮组右缘、进而与卡片内容盒右缘对齐；top = 按钮组底 + 6px。
fn row_menu(row : Row, emit : @cmd.Emit[Msg]) -> @html.Html {
  let running = row.status is Running
  let entries = if running { running_menu(row.deletable) } else { stopped_menu(row.deletable) }
  let items : Array[@html.Html] = []
  for entry in entries {
    match entry {
      MSep =>
        items.push(
          @html.div(
            class="dsh-menu-sep",
            attrs=@html.Attrs::build().role("separator"),
            @html.nothing,
          ),
        )
      MItem(key, icon_name, label, danger) =>
        items.push(
          @html.button(
            class=if danger { "dsh-menu-item danger" } else { "dsh-menu-item" },
            type_="button",
            disabled=row.busy,
            attrs=@html.Attrs::build()
              .role("menuitem")
              .data_set("action", action_name(key)),
            on_click=emit(RowAction(row.id, key)),
            [icon(icon_name, Small), @html.span(label)],
          ),
        )
    }
  }
  @html.div(
    id=menu_id(row.id),
    class="dsh-menu",
    attrs=@html.Attrs::build().role("menu").data_set("name", "row-menu"),
    on_keydown=emit.map(fn(key : @html.Keyboard) {
      if key.key() == "Escape" {
        MenuCloseBack(row.id)
      } else {
        Noop
      }
    }),
    items,
  )
}

///|
fn restart_button(row : Row, model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let restarting = model.restarting == row.id
  @md2.btn(
    children=[icon("mdi-refresh", XSmall), @html.text(" " + (if restarting { "重启中…" } else { "重启" }))],
    variant=Outlined,
    disabled=restarting || row.busy,
    class="dsh-btn",
    on_click=emit(RowAction(row.id, Restart)),
  )
}

///|
/// 行内按钮组。启动等待态（status=starting）：整行按钮禁用，含两段式的两半 ——
/// caret 也 disabled，所以菜单根本开不出来。
fn instance_actions(row : Row, model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let running = row.status is Running
  let tone = match row.tone {
    Accent => " accent"
    Violet => " violet"
  }
  let parts : Array[@html.Html] = []
  if running {
    parts.push(
      @md2.btn(
        children=[icon("mdi-open-in-new", XSmall), @html.text(" 打开 Web UI")],
        // 不给 color="primary"：md2 的背景助记类 .bg-primary 是 !important，
        // 会把实例卡「主色随色调走」（运行中蓝 / profile 紫）这条盖死。
        // 填充色由 .dsh-btn.primary 读 --btn-bg 给，与 Vue 版一致。
        variant=Flat,
        class="dsh-btn primary" + tone,
        on_click=emit(RowAction(row.id, OpenUi)),
      ),
    )
    parts.push(
      @md2.btn(
        children=[@html.i(class="dsh-dot-danger", @html.nothing), @html.text(" 停止")],
        variant=Outlined,
        disabled=row.busy,
        class="dsh-btn",
        on_click=emit(RowAction(row.id, Toggle)),
      ),
    )
    parts.push(restart_button(row, model, emit))
    parts.push(
      @md2.btn(
        children=[icon("mdi-dots-horizontal", Small)],
        variant=Outlined,
        icon=true,
        disabled=row.busy,
        class="dsh-btn icon-only",
        attrs=@html.Attrs::build()
          .id(trigger_id(row.id))
          .aria_haspopup("menu")
          .aria_expanded(if model.menu_open == row.id { "true" } else { "false" })
          .aria_label("更多操作（" + row.name + "）"),
        on_click=emit(MenuToggle(row.id)),
      ),
    )
  } else {
    // 两段式：左半启动、右半只开菜单；分隔线是右半的 border-left，圆角各只留外侧两角
    parts.push(
      @html.div(class="dsh-split" + tone, [
        @md2.btn(
          children=[
            icon("mdi-play", XSmall),
            @html.text(" " + (if row.status is Starting { "启动中…" } else { "启动" })),
          ],
          variant=Flat,
          disabled=row.busy,
          class="dsh-btn primary dsh-split-main",
          on_click=emit(RowAction(row.id, Toggle)),
        ),
        @md2.btn(
          children=[@md2.icon(icon_name="mdi-chevron-right", size=XSmall, class="dsh-caret")],
          variant=Flat,
          disabled=row.busy,
          class="dsh-btn primary split-caret",
          attrs=@html.Attrs::build()
            .id(trigger_id(row.id))
            .aria_haspopup("menu")
            .aria_expanded(if model.menu_open == row.id { "true" } else { "false" })
            .aria_label("启动菜单（" + row.name + "）"),
          on_click=emit(MenuToggle(row.id)),
        ),
      ]),
    )
    parts.push(restart_button(row, model, emit))
  }
  // 菜单挂在按钮组容器**里面**：.dsh-actions 是它的定位祖先（position: relative），
  // 这样 top = 按钮组底 + 6px、right: 0 才对得上卡片内容盒右缘。
  if model.menu_open == row.id {
    parts.push(row_menu(row, emit))
  }
  let children : Array[@html.Html] = [@html.div(class="dsh-actions", parts)]
  if model.menu_open == row.id {
    // 点菜单外关闭：铺满视口的一层，z-index 20 < 菜单 30，菜单自己不受影响
    children.push(
      @html.div(
        class="dsh-menu-overlay",
        attrs=@html.Attrs::build().data_set("name", "menu-overlay"),
        on_click=emit(MenuClose),
        @html.nothing,
      ),
    )
  }
  @html.fragment(children)
}

///|
fn status_name(status : RowStatus) -> String {
  match status {
    Running => "running"
    Stopped => "stopped"
    Starting => "starting"
  }
}

///|
/// 副标题行：类型标签 + 状态点 + 状态文案 + 末轨（四段固定轨道，状态点不随标签宽度漂移）。
fn sub_line(row : Row) -> @html.Html {
  let sub_class = match row.status {
    Running => "dsh-sub"
    Stopped => "dsh-sub off"
    Starting => "dsh-sub starting"
  }
  let state_label = match row.status {
    Starting => "正在启动…"
    Running => "运行中"
    Stopped => "已停止"
  }
  let tail : Array[@html.Html] = []
  match row.status {
    Starting => tail.push(@html.span(class="dsh-hint", "等待核心就绪"))
    Running =>
      tail.push(
        @html.span(
          class="dsh-uptime",
          attrs=@html.Attrs::build().title(row.uptime_hint),
          match row.uptime {
            Some(minutes) => "已运行 " + duration_text(minutes)
            None => "运行时长未知"
          },
        ),
      )
    Stopped =>
      tail.push(
        @html.span(
          class="dsh-uptime",
          attrs=@html.Attrs::build().title(row.idle_note),
          if row.idle_note.length() > 0 { row.idle_note } else { "未运行" },
        ),
      )
  }
  let note = if row.status is Starting { row.port_note } else { row.note }
  if note.length() > 0 {
    tail.push(@html.span(class="dsh-port-note", attrs=@html.Attrs::build().title(note), note))
  }
  @html.div(
    class=sub_class,
    attrs=@html.Attrs::build()
      .data_set("status", status_name(row.status))
      .data_set("name", "sub-line"),
    [
      @html.span(
        class="dsh-kind",
        attrs=@html.Attrs::build().title(row.kind_hint),
        row.kind,
      ),
      @html.span(class="dsh-dot-slot", [@html.i(class="dsh-dot", @html.nothing)]),
      @html.span(class="dsh-state", state_label),
      @html.span(class="dsh-tail", tail),
    ],
  )
}

///|
/// 一张实例卡：两行卡头 + 字段区。
fn instance_card(row : Row, model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let tile_class = match row.tone {
    Accent => "dsh-tile accent"
    Violet => "dsh-tile violet"
  }
  let tile_icon = match row.tone {
    Accent => "mdi-open-in-new"
    Violet => "mdi-puzzle-outline"
  }
  @md2.card(
    variant=Outlined,
    class="dsh-case",
    attrs=@html.Attrs::build()
      .data_set("name", "instance-card")
      .data_set("instance", row.name),
    children=[
      @html.div(class="dsh-case-head", [
        @html.span(class=tile_class, [icon(tile_icon, Large)]),
        @html.div(class="dsh-ident", [
          @html.div(class="dsh-title-line", [@html.span(class="dsh-name", row.name)]),
          sub_line(row),
        ]),
        instance_actions(row, model, emit),
      ]),
      @html.ul(class="dsh-fields", [
        field("mdi-label-outline", "DSH 版本 / 来源", row.version, ""),
        field("mdi-layers-outline", "Profile", row.profile, ""),
        field("mdi-link-variant", "访问地址", row.url, ""),
        field("mdi-home-outline", "DSH_HOME", row.home, ""),
        field("mdi-puzzle-outline", "插件数量", row.plugin_count, row.plugin_detail),
      ]),
    ],
  )
}

///|
fn archived_row(row : Row, emit : @cmd.Emit[Msg]) -> @html.Html {
  let parts : Array[@html.Html] = [
    @html.span(class="dsh-archive-name", row.name),
    @html.span(class="dsh-archive-kind", row.kind),
    @html.span(class="dsh-archive-stamp", [
      @html.span(class="dsh-archive-stamp-label", "归档时间"),
      @html.span(
        class="dsh-archive-stamp-value",
        match row.archived_at {
          Some(stamp) => stamp
          None => "—"
        },
      ),
    ]),
    @html.span(class="dsh-archive-spacer", @html.nothing),
    @html.button(
      class="dsh-archive-btn",
      type_="button",
      on_click=emit(RowAction(row.id, Unarchive)),
      [icon("mdi-archive-arrow-up-outline", Small), @html.span("取消归档")],
    ),
  ]
  if row.deletable {
    parts.push(
      @html.button(
        id=archive_trigger_id(row.id),
        class="dsh-archive-btn danger",
        type_="button",
        on_click=emit(DeleteOpen(row.id, archive_trigger_id(row.id))),
        [icon("mdi-delete-outline", Small), @html.span("删除")],
      ),
    )
  }
  @html.article(
    class="dsh-archive-row",
    attrs=@html.Attrs::build().data_set("name", "archived-row"),
    parts,
  )
}

///|
/// 归档区：可折叠 + 取消归档。这一组固定是演示数据（磁盘上没有「归档记录」这种概念）。
fn archived_section(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let items = model.rows.filter(fn(row) { row.archived_at is Some(_) })
  if items.length() == 0 {
    return @html.nothing
  }
  let body : Array[@html.Html] = if model.archived_open {
    items.map(fn(row) { archived_row(row, emit) })
  } else {
    []
  }
  @html.fragment([
    @html.div(class="dsh-section-head", [
      @html.h2(class="dsh-section-title", [
        @html.button(
          class="dsh-collapse",
          type_="button",
          attrs=@html.Attrs::build().data_set("name", "archived-toggle"),
          on_click=emit(ToggleArchived),
          [
            @md2.icon(
              icon_name=if model.archived_open { "mdi-chevron-down" } else { "mdi-chevron-right" },
              size=XSmall,
            ),
            @html.span("已归档 (" + items.length().to_string() + ")"),
          ],
        ),
      ]),
      source_badge(model.tag_archived),
    ]),
    @html.div(class="dsh-rows", body),
  ])
}

///|
/// 右栏：工作流入口两行 + 关于实例说明。两处都是固定文案（与 Vue 版一致）。
fn side_info_panel() -> @html.Html {
  let flows : Array[@html.Html] = []
  let tones = ["accent", "violet"]
  let icons = ["mdi-source-fork", "mdi-open-in-new"]
  let index : Ref[Int] = Ref(0)
  for flow in workflows {
    let (title, detail) = flow
    let i = index.val
    index.val = i + 1
    flows.push(
      @html.button(
        class="dsh-flow",
        type_="button",
        [
          @html.span(class="dsh-flow-icon " + tones[i % 2], [icon(icons[i % 2], Default)]),
          @html.span(class="dsh-flow-body", [
            @html.span(class="dsh-flow-title", title),
            @html.span(class="dsh-flow-detail", detail),
          ]),
          @html.span(class="dsh-flow-arrow", [icon("mdi-chevron-right", Small)]),
        ],
      ),
    )
  }
  let notes : Array[@html.Html] = safety_checks.map(fn(item) {
    @html.li(class="dsh-note", [@html.span(class="dsh-note-text", item)])
  })
  @html.aside(class="dsh-side-info", attrs=@html.Attrs::build().data_set("name", "side-info"), [
    @md2.card(variant=Outlined, class="dsh-info-card", children=[
      @html.h2(class="dsh-info-title", "工作流入口"),
      @html.div(class="dsh-flows", flows),
    ]),
    @md2.card(variant=Outlined, class="dsh-info-card", children=[
      @html.h2(class="dsh-info-title", "关于实例"),
      @html.ul(class="dsh-notes", notes),
    ]),
  ])
}

///|
/// 删除确认框：打开时焦点落在确认键，Esc 关闭，关闭后焦点回到触发元素。
fn confirm_dialog(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let name = match find_row(model.rows, model.confirm_id) {
    Some(row) => row.name
    None => model.confirm_id
  }
  let card = @html.div(class="dsh-dialog-card", [
    @html.h2(class="dsh-dialog-title", "删除实例 " + name + "？"),
    @html.p(class="dsh-dialog-message", "删除后该实例将从列表移除，本页不连接真实进程。"),
    @html.div(class="dsh-dialog-foot", [
      @html.button(
        id="dsh-confirm-ok",
        class="dsh-dialog-btn primary",
        type_="button",
        on_click=emit(DeleteConfirm),
        [@html.text("删除")],
      ),
      @html.button(
        class="dsh-dialog-btn",
        type_="button",
        on_click=emit(DeleteCancel),
        [@html.text("取消")],
      ),
    ]),
  ])
  dialog(
    "confirm-dialog",
    "删除实例 " + name + "？",
    emit(DeleteCancel),
    emit.map(fn(key : @html.Keyboard) {
      if key.key() == "Escape" {
        DeleteCancel
      } else {
        Noop
      }
    }),
    card,
  )
}

///|
/// 重命名框：预填当前名并全选；空名 / 纯空格禁用确定；Enter 确认、Esc 取消；
/// 关闭后焦点回到触发元素。
fn rename_dialog(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let name = match find_row(model.rows, model.rename_id) {
    Some(row) => row.name
    None => model.rename_id
  }
  let can_confirm = model.rename_draft.trim().length() > 0
  let card = @html.div(class="dsh-dialog-card", [
    @html.h2(class="dsh-dialog-title", "重命名实例 " + name),
    @html.input(
      input_type=Text,
      id="dsh-rename-input",
      class="dsh-dialog-input",
      value=model.rename_draft,
      autofocus=true,
      attrs=@html.Attrs::build().aria_label("实例名称").spellcheck(false),
      on_input=emit.map(fn(text) { RenameInput(text) }),
    ),
    @html.div(class="dsh-dialog-foot", [
      @html.button(
        class="dsh-dialog-btn primary",
        type_="button",
        disabled=!can_confirm,
        on_click=emit(RenameConfirm),
        [@html.text("确定")],
      ),
      @html.button(
        class="dsh-dialog-btn",
        type_="button",
        on_click=emit(RenameCancel),
        [@html.text("取消")],
      ),
    ]),
  ])
  dialog(
    "rename-dialog",
    "重命名实例 " + name,
    emit(RenameCancel),
    emit.map(fn(key : @html.Keyboard) {
      if key.key() == "Escape" {
        RenameCancel
      } else if key.key() == "Enter" {
        RenameConfirm
      } else {
        Noop
      }
    }),
    card,
  )
}

///|
/// 实例总览页。
fn overview_view(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let running = model.rows.filter(fn(row) {
    row.archived_at is None && row.status is Running
  })
  // 启动等待中的行留在原分组，所以「已停止」组把 starting 一起算进来
  let stopped = model.rows.filter(fn(row) {
    row.archived_at is None && !(row.status is Running)
  })
  let running_list : Array[@html.Html] = running.map(fn(row) {
    instance_card(row, model, emit)
  })
  if running.length() == 0 {
    running_list.push(running_empty(running_summary(model), model.tag_instances.detail))
  }
  let stopped_list : Array[@html.Html] = stopped.map(fn(row) {
    instance_card(row, model, emit)
  })
  if stopped.length() == 0 {
    stopped_list.push(stopped_empty())
  }
  let dialogs : Array[@html.Html] = []
  if model.confirm_id.length() > 0 {
    dialogs.push(confirm_dialog(model, emit))
  }
  if model.rename_id.length() > 0 {
    dialogs.push(rename_dialog(model, emit))
  }
  let body : Array[@html.Html] = [
      @html.section(class="dsh-overview-page", [
        @html.header(class="dsh-overview-head", [
          @html.div(class="dsh-head-text", [
            @html.h1(class="dsh-page-title", "实例总览"),
            source_badge(model.tag_runtime),
            @html.span(class="dsh-head-note", "动作仍是演示"),
          ]),
          @html.button(
            class="dsh-new-btn",
            type_="button",
            attrs=@html.Attrs::build().data_set("name", "new-instance"),
            [@html.span(class="dsh-plus", "＋"), @html.span("新建实例")],
          ),
        ]),
        section_head("当前运行的实例", running.length(), model.tag_instances),
        @html.div(class="dsh-rows", running_list),
        section_head("已停止的实例", stopped.length(), model.tag_profiles),
        @html.div(class="dsh-rows", stopped_list),
        archived_section(model, emit),
      ]),
    side_info_panel(),
  ]
  for node in dialogs {
    body.push(node)
  }
  @html.div(
    class="dsh-overview",
    attrs=@html.Attrs::build().data_set("name", "overview-page"),
    body,
  )
}

///|
/// 空态口径：扫了多少个 loopback 监听端口、命中几个 DSH 签名。
fn running_summary(model : Model) -> String {
  match model.instances {
    None => "监听端口扫描还没返回结果"
    Some(facts) =>
      "扫了本机 " + facts.candidate_count.to_string() + " 个 loopback 监听端口，其中 " +
      facts.probe_hits.to_string() + " 个命中 DSH 签名"
  }
}
