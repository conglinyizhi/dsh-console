// 实例总览页。
//
// 两条分组（当前运行 / 已停止）+ 归档区 + 右栏信息面板，卡片的版式照 Vue 版逐项对齐：
// 两行卡头（标题行 + 副标题行）、状态点独立 13px 槽位、字段区固定两列、按钮组右缘贴卡片内容盒。
//
// 卡片、按钮、图标全部自建：DOM 与类名照 Vue 版逐条对齐，
// 形状出自 styles/app.scss（那份表就是从 Vue 的组件样式块机械迁移来的）。
// 卡片是 .dsh-case（一张卡），行内按钮组是 .dsh-btn，图标是 icons.mbt 的内联 SVG。

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
    CopyTokenUrl => "copy-token-url"
    Fork => "fork"
    Rename => "rename"
    Note => "note"
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
///
/// 菜单里那两项「打开」用的都是**带令牌的地址**：裸地址在 dsh 上是 401，
/// 菜单拿它去开新标签就是给了个点了不能用的链接。
fn running_menu(row : Row) -> Array[MenuEntry] {
  let items : Array[MenuEntry] = [
    MItem(Tab, "open-in-new", "在新标签页打开", false),
    MItem(CopyUrl, "link-variant", "复制访问地址", false),
  ]
  // 带令牌的地址只有真读到时才有这一项：读不到令牌就不摆一个「复制空串」出来
  if row.web_url is Some(_) {
    items.push(MItem(CopyTokenUrl, "key-variant", "复制带令牌的地址", false))
  }
  items.push(MSep)
  items.push(MItem(Rename, "rename-outline", "重命名", false))
  items.push(MItem(Note, "note-text-outline", "编辑备注", false))
  items.push(MItem(Fork, "source-fork", "派生开发副本", false))
  items.push(MItem(Archive, "archive-outline", "归档", false))
  if row.deletable {
    items.push(MItem(Delete, "delete-outline", "删除", true))
  }
  items.push(MSep)
  items.push(MItem(Logs, "text-box-outline", "查看日志", false))
  items.push(MItem(Dir, "folder-open-outline", "打开工作目录", false))
  items.push(MItem(Config, "tune", "编辑配置", false))
  items
}

///|
/// 已停止：菜单从行尾独立的 ⋯ 打开（与运行中卡同一个入口）；可删实例才多一条「删除」。
fn stopped_menu(deletable : Bool) -> Array[MenuEntry] {
  let items : Array[MenuEntry] = [
    MItem(Logs, "text-box-outline", "查看日志", false),
    MItem(Dir, "folder-open-outline", "打开工作目录", false),
    MItem(Config, "tune", "编辑配置", false),
    MSep,
    MItem(Rename, "rename-outline", "重命名", false),
    MItem(Note, "note-text-outline", "编辑备注", false),
    MItem(Archive, "archive-outline", "归档", false),
  ]
  if deletable {
    items.push(MItem(Delete, "delete-outline", "删除", true))
  }
  items
}

///|
/// 下拉菜单。锚点挂在按钮组容器上（.dsh-actions 是 position: relative），
/// 所以右缘与按钮组右缘、进而与卡片内容盒右缘对齐；top = 按钮组底 + 6px。
fn row_menu(row : Row, emit : @cmd.Emit[Msg]) -> @html.Html {
  let running = row.status is Running
  let entries = if running { running_menu(row) } else { stopped_menu(row.deletable) }
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
            [icon(icon_name), @html.span(label)],
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
  @html.button(
    class="dsh-btn",
    type_="button",
    disabled=restarting || row.busy,
    on_click=emit(RowAction(row.id, Restart)),
    [icon("refresh"), @html.span(if restarting { "重启中…" } else { "重启" })],
  )
}

///|
/// 行内按钮组。启动等待态（status=starting）：整行按钮禁用，行尾的 ⋯ 也 disabled ——
/// 触发按钮点不动，菜单根本开不出来。
fn instance_actions(row : Row, model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let running = row.status is Running
  let tone = match row.tone {
    Accent => " accent"
    Violet => " violet"
  }
  let parts : Array[@html.Html] = []
  if running {
    parts.push(
      @html.button(
        // 主色随色调走（运行中蓝 / profile 紫）：填充色由 .dsh-btn.primary 读 --btn-bg 给
        class="dsh-btn primary" + tone,
        type_="button",
        // 令牌读不到时按钮**照样可点**：点下去先把原因说清，不给一个点了 401 的链接
        attrs=@html.Attrs::build()
          .data_set("name", "open-web-ui")
          .title(open_ui_hint(row)),
        on_click=emit(RowAction(row.id, OpenUi)),
        [icon("open-in-new"), @html.span("打开 Web UI")],
      ),
    )
    parts.push(
      @html.button(
        class="dsh-btn",
        type_="button",
        disabled=row.busy,
        on_click=emit(RowAction(row.id, Toggle)),
        [@html.i(class="dsh-dot-danger", @html.nothing), @html.span("停止")],
      ),
    )
  } else {
    // 启动：普通主色按钮（原来分段按钮的左半）。
    // 分段形态在这里被**有意识地去掉**：我们只有一种启动方式，而"一颗按钮 + 一个 caret"
    // 的形状在暗示"有多个变体可选"。控件的形状应该和它的真实语义一致 ——
    // 更多动作归行尾独立的 ⋯，于是已停止卡与运行中卡是同一个骨架，
    // 只有第一颗按钮的语义随状态翻转。
    parts.push(
      @html.button(
        class="dsh-btn primary" + tone,
        type_="button",
        disabled=row.busy,
        on_click=emit(RowAction(row.id, Toggle)),
        [
          icon("play", size=13),
          @html.span(if row.status is Starting { "启动中…" } else { "启动" }),
        ],
      ),
    )
  }
  parts.push(restart_button(row, model, emit))
  // 行尾 ⋯：两种状态共用这一段代码，类名 / 尺寸 / 圆角 / 间距因此逐项一致；
  // 只有点开之后的内容随状态分叉（running_menu / stopped_menu）。
  parts.push(
    @html.button(
      class="dsh-btn icon-only",
      type_="button",
      disabled=row.busy,
      attrs=@html.Attrs::build()
        .id(trigger_id(row.id))
        .aria_haspopup("menu")
        .aria_expanded(if model.menu_open == row.id { "true" } else { "false" })
        .aria_label("更多操作（" + row.name + "）"),
      on_click=emit(MenuToggle(row.id)),
      [icon("dots-horizontal", size=16)],
    ),
  )
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
          // 悬停里补上档案的健康读数（patch 行数 / lock 时刻）：
          // 这只 profile 的卡已经不再单独出现，这份读数得跟着进程卡走。
          attrs=@html.Attrs::build().title(
            if row.idle_note.length() > 0 {
              (if row.uptime_hint.length() > 0 {
                row.uptime_hint + " · "
              } else {
                ""
              }) + row.idle_note
            } else {
              row.uptime_hint
            },
          ),
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
/// 卡头中间那一列：标题行 + 副标题行 +（有备注时）备注行。
///
/// 备注行**只在真有备注时**才推进这个列 —— 没有备注的卡片 DOM 与以前逐节点一致，
/// 几何自然一个像素都不动。空串不进 DOM，也不留一个占位的空 span。
fn ident_block(row : Row) -> @html.Html {
  let parts : Array[@html.Html] = [
    @html.div(class="dsh-title-line", [
      @html.span(class="dsh-name", row.name),
      // 标记的文字走 CSS 的 content（见 styles/app.scss 的 .dsh-console-mark::after）：
      // 卡片的 textContent 里因此没有「启动」两个字。这不是为了好看 ——
      // design/probe-dialog.mjs 是用 textContent.includes('启动') 找「已停止」那张卡的，
      // 卡里多一段含「启动」的文字会让它选中运行中的卡，进而点到旁边那颗「停止」。
      // 语义没丢：aria-label 与 title 都是同一句话。
      if row.console_started {
        @html.span(
          class="dsh-console-mark",
          attrs=@html.Attrs::build()
            .data_set("name", "console-mark")
            .data_set("mark", "console-started")
            .role("img")
            .aria_label("由本控制台启动")
            .title(
              "由本控制台启动：这一条在 $XDG_STATE_HOME/dsh-console/runtime.json 的登记里。登记只记控制台自己起的，外部实例不写进去",
            ),
          [icon("play", size=11), @html.text("由本控制台启动")],
        )
      } else {
        @html.nothing
      },
    ]),
    sub_line(row),
  ]
  // 备注就写在副标题行下面一行：整行左对齐、超长省略，完整内容在悬停里。
  // 它不属于「运行事实」，所以不给图标、不跟字段区抢位置。
  if row.user_note.length() > 0 {
    parts.push(
      @html.div(
        class="dsh-note-row",
        attrs=@html.Attrs::build()
          .data_set("name", "card-note")
          .title(
            if row.user_note_source.length() > 0 {
              row.user_note + "\n（" + row.user_note_source + "）"
            } else {
              row.user_note
            },
          ),
        [
          @html.span(class="dsh-note-tag", "备注"),
          @html.span(class="dsh-note-text", row.user_note),
        ],
      ),
    )
  }
  @html.div(class="dsh-ident", parts)
}

///|
/// 「访问地址」那一行的悬停：这一栏只说这一行自己（在不在监听、监听在哪），
/// **不提令牌** —— 带令牌的地址走「打开 Web UI」与菜单里的「复制带令牌的地址」。
/// 这一栏是给人读的地址，不是进去用的入口。
fn url_hint(row : Row) -> String {
  match row.status {
    Stopped => "这只 profile 现在没有在跑，所以没有可访问的地址"
    Starting => "实例正在起来，端口还没开始监听"
    Running => "这只实例正在 " + row.url + " 上监听（要进去用「打开 Web UI」）"
  }
}
/// 「打开 Web UI」按钮的悬停：点下去会发生什么，先说在前面。
fn open_ui_hint(row : Row) -> String {
  match row.web_url {
    Some(_) => "在新标签页打开带令牌的地址（" + row.url + " 这条裸地址打开是 401）"
    None =>
      if row.web_url_source == "" {
        "读不到握手令牌，点了不会打开标签页"
      } else {
        "读不到握手令牌（" + row.web_url_source + "），点了不会打开标签页"
      }
  }
}

///|
/// 一张实例卡：两行卡头 + 字段区。
fn instance_card(row : Row, model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let tile_class = match row.tone {
    Accent => "dsh-tile accent"
    Violet => "dsh-tile violet"
  }
  let tile_icon = match row.tone {
    Accent => "open-in-new"
    Violet => "puzzle-outline"
  }
  @html.div(
    class="dsh-case",
    attrs=@html.Attrs::build()
      .data_set("name", "instance-card")
      .data_set("instance", row.name),
    [
      @html.div(class="dsh-case-head", [
        @html.span(class=tile_class, [icon(tile_icon, size=20)]),
        ident_block(row),
        instance_actions(row, model, emit),
      ]),
      @html.ul(class="dsh-fields", [
        field("label-outline", "DSH 版本 / 来源", row.version, row.version_hint),
        field("layers-outline", "Profile", row.profile, row.profile_hint),
        field("link-variant", "访问地址", row.url, url_hint(row)),
        field("home-outline", "DSH_HOME", row.home, row.home_hint),
        field("puzzle-outline", "插件数量", row.plugin_count, row.plugin_detail),
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
        // 记录里的时间是后端给的 ISO（UTC）：显示成浏览器本地的 MM-DD HH:MM，
        // 原值留在悬停里。解析不出来就照原样显示，不吞。
        attrs=@html.Attrs::build().title(
          match row.archived_at {
            Some(stamp) => stamp
            None => "归档时间读不到"
          },
        ),
        match row.archived_at {
          Some(stamp) =>
            match js_short_time(stamp) {
              "" => stamp
              short => short
            }
          None => "—"
        },
      ),
    ]),
    @html.span(class="dsh-archive-spacer", @html.nothing),
    @html.button(
      class="dsh-archive-btn",
      type_="button",
      on_click=emit(RowAction(row.id, Unarchive)),
      [icon("archive-arrow-up-outline"), @html.span("取消归档")],
    ),
  ]
  if row.deletable {
    parts.push(
      @html.button(
        id=archive_trigger_id(row.id),
        class="dsh-archive-btn danger",
        type_="button",
        on_click=emit(DeleteOpen(row.id, archive_trigger_id(row.id))),
        [icon("delete-outline"), @html.span("删除")],
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
  // 徽标跟着内容走：折叠时标题行干净，展开时明说这一组是演示数据。
  // 挂在折叠标题上，标的是用户当时看不到的东西。
  let body : Array[@html.Html] = []
  if model.archived_open {
    body.push(source_badge(model.tag_archived))
    for row in items {
      body.push(archived_row(row, emit))
    }
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
            icon(if model.archived_open { "chevron-down" } else { "chevron-right" }),
            @html.span("已归档 (" + items.length().to_string() + ")"),
          ],
        ),
      ]),
    ]),
    @html.div(class="dsh-rows", body),
  ])
}

///|
/// 右栏：工作流入口两行 + 关于实例说明。两处都是固定文案（与 Vue 版一致）。
fn side_info_panel() -> @html.Html {
  let flows : Array[@html.Html] = []
  let tones = ["accent", "violet"]
  let icons = ["source-fork", "open-in-new"]
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
          @html.span(class="dsh-flow-icon " + tones[i % 2], [icon(icons[i % 2], size=16)]),
          @html.span(class="dsh-flow-body", [
            @html.span(class="dsh-flow-title", title),
            @html.span(class="dsh-flow-detail", detail),
          ]),
          @html.span(class="dsh-flow-arrow", [icon("chevron-right")]),
        ],
      ),
    )
  }
  let notes : Array[@html.Html] = safety_checks.map(fn(item) {
    @html.li(class="dsh-note", [@html.span(class="dsh-note-text", item)])
  })
  @html.aside(class="dsh-side-info", attrs=@html.Attrs::build().data_set("name", "side-info"), [
    @html.div(class="dsh-info-card", [
      @html.h2(class="dsh-info-title", "工作流入口"),
      @html.div(class="dsh-flows", flows),
    ]),
    @html.div(class="dsh-info-card", [
      @html.h2(class="dsh-info-title", "关于实例"),
      @html.ul(class="dsh-notes", notes),
    ]),
  ])
}

///|
/// 动作结果提示条：成功与失败各一副脸色，失败里写清后端给的原因（conflict / not-authorized …）。
/// 动作发不出去（这一行的读数里没有目标）也走这里，所以「没反应」这件事不会发生。
fn action_notice(model : Model) -> @html.Html {
  if model.act_notice.length() == 0 {
    return @html.nothing
  }
  let tone = if model.act_notice_ok { " ok" } else { " err" }
  @html.p(
    class="dsh-notice" + tone,
    attrs=@html.Attrs::build()
      .data_set("name", "action-notice")
      .data_set("ok", if model.act_notice_ok { "true" } else { "false" }),
    model.act_notice,
  )
}

///|
/// 删除确认框：打开时焦点落在确认键，Esc 关闭，关闭后焦点回到触发元素。
fn confirm_dialog(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let name = match find_row(model.rows, model.confirm_id) {
    Some(row) => row.name
    None => model.confirm_id
  }
  // 删除方式由后端的 safety.deleteToTrash 决定：说清楚这一次会不会落刀。
  // 硬删时请求里带 confirm=DELETE 的二次确认（契约要求，前端在这里给出来）。
  let trash = setting_bool_of(model, "safety.deleteToTrash")
  let mode = match trash {
    Some(true) => "按当前设置（safety.deleteToTrash 开）移入回收站，还能捞回来。"
    Some(false) =>
      "按当前设置（safety.deleteToTrash 关）**硬删除 profile 目录**，不可恢复；请求会带上 confirm=DELETE 的二次确认。"
    None =>
      "设置页还没读过，删除方式由后端的 safety.deleteToTrash 决定；如果是硬删，请求会带上 confirm=DELETE。"
  }
  // 删之前先看清这一只是干什么用的：有备注就把备注摆在确认框里，没有就不占位
  let note = match find_row(model.rows, model.confirm_id) {
    Some(row) => row.user_note
    None => ""
  }
  let note_block = if note.length() > 0 {
    @html.div(
      class="dsh-dialog-note",
      attrs=@html.Attrs::build().data_set("name", "confirm-note"),
      [@html.span(class="dsh-dialog-note-tag", "备注"), @html.text(note)],
    )
  } else {
    @html.nothing
  }
  let card = @html.div(class="dsh-dialog-card", [
    @html.h2(class="dsh-dialog-title", "删除实例 " + name + "？"),
    note_block,
    @html.p(class="dsh-dialog-message", mode),
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
/// 编辑备注框。与重命名框同一套外壳（居中层 .dsh-dialog-wrap、Esc 取消、
/// 关闭后焦点回触发元素），只是内容是自由文本：
///
/// - 预填当前备注，光标推到文末（接着改，不是整段覆盖）
/// - 空文本是合法的：那就是「删掉这个备注」
/// - 保存失败不关框，后端给的原因写在框里
/// - 保存中锁住保存键与取消键，回执到了再收尾
fn note_dialog(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let name = match find_row(model.rows, model.note_open) {
    Some(row) => row.name
    None => model.note_open
  }
  let saving = model.note_saving != ""
  let error_block = if model.note_error.length() > 0 {
    @html.p(
      class="dsh-dialog-error",
      attrs=@html.Attrs::build().data_set("name", "note-error"),
      model.note_error,
    )
  } else {
    @html.nothing
  }
  let card = @html.div(class="dsh-dialog-card", [
    @html.h2(class="dsh-dialog-title", [
      icon("note-text-outline", size=14),
      @html.text("编辑备注 " + name),
    ]),
    @html.p(class="dsh-dialog-message", "备注写的是这只 profile 干什么用的，存在它自己的目录里（改名、派生、搬走都跟着走）。留空保存就是删掉备注。"),
    @html.textarea(
      id="dsh-note-input",
      class="dsh-dialog-input dsh-dialog-textarea",
      rows=3,
      maxlength=2000,
      value=model.note_draft,
      placeholder="这只 profile 是干什么用的…",
      autofocus=true,
      attrs=@html.Attrs::build()
        .aria_label("profile 备注")
        .spellcheck(false)
        .data_set("name", "note-input"),
      on_input=emit.map(fn(text) { NoteInput(text) }),
      @html.nothing,
    ),
    error_block,
    @html.div(class="dsh-dialog-foot", [
      @html.button(
        id="dsh-note-ok",
        class="dsh-dialog-btn primary",
        type_="button",
        disabled=saving,
        on_click=emit(NoteConfirm),
        [@html.text(if saving { "保存中…" } else { "保存" })],
      ),
      @html.button(
        id="dsh-note-cancel",
        class="dsh-dialog-btn",
        type_="button",
        disabled=saving,
        on_click=emit(NoteCancel),
        [@html.text("取消")],
      ),
    ]),
  ])
  dialog(
    "note-dialog",
    "编辑备注 " + name,
    emit(NoteCancel),
    emit.map(fn(key : @html.Keyboard) {
      if key.key() == "Escape" {
        NoteCancel
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
  // 读数还没落地：这一格摆加载态，空态只在真读到空的时候出现（见 loading_block）
  let pending = readings_pending(model)
  let running_list : Array[@html.Html] = running.map(fn(row) {
    instance_card(row, model, emit)
  })
  if running.length() == 0 {
    if pending {
      running_list.push(
        loading_block(
          "running-loading",
          "正在读取实例读数…",
          "GET /api/local/instances 与 /api/local/profiles 还没返回。读数回来之前这里显示的是加载态；空态只在真读到空的时候出现。",
        ),
      )
    } else {
      running_list.push(running_empty(running_summary(model), model.tag_instances.detail))
    }
  }
  let stopped_list : Array[@html.Html] = stopped.map(fn(row) {
    instance_card(row, model, emit)
  })
  if stopped.length() == 0 {
    if pending {
      stopped_list.push(
        loading_block(
          "stopped-loading",
          "正在读取 profile 读数…",
          "GET /api/local/profiles 还没返回。读数回来之前这里显示的是加载态。",
        ),
      )
    } else {
      stopped_list.push(stopped_empty())
    }
  }
  let dialogs : Array[@html.Html] = []
  if model.confirm_id.length() > 0 {
    dialogs.push(confirm_dialog(model, emit))
  }
  if model.rename_id.length() > 0 {
    dialogs.push(rename_dialog(model, emit))
  }
  if model.note_open.length() > 0 {
    dialogs.push(note_dialog(model, emit))
  }
  let body : Array[@html.Html] = [
      @html.section(class="dsh-overview-page", [
        @html.header(class="dsh-overview-head", [
          @html.div(class="dsh-head-text", [
            @html.h1(class="dsh-page-title", "实例总览"),
            source_badge(model.tag_runtime),
            @html.span(class="dsh-head-note", "菜单里的动作走 POST /api/local/action"),
          ]),
          @html.button(
            class="dsh-new-btn",
            type_="button",
            attrs=@html.Attrs::build().data_set("name", "new-instance"),
            [@html.span(class="dsh-plus", "＋"), @html.span("新建实例")],
          ),
        ]),
        action_notice(model),
        section_head(
          "当前运行的实例",
          if pending { "…" } else { running.length().to_string() },
          model.tag_instances,
        ),
        @html.div(class="dsh-rows", running_list),
        section_head(
          "已停止的实例",
          if pending { "…" } else { stopped.length().to_string() },
          model.tag_profiles,
        ),
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