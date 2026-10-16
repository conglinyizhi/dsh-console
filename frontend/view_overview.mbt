// 实例总览页。
//
// 两条分组（当前运行 / 已停止）+ 归档区，单栏铺满内容区；卡片的版式照 Vue 版逐项对齐：
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
    CopyDev => "copy-dev"
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
/// 「复制开发指令」那一项：认得出 profile 目录名才摆。
///
/// 复制出来的是给**另一个会话**的任务说明（文本见 app.mbt 的 dev_instruction_text）：
/// 让那边的 agent 针对这一只 profile 开发，不必切进这只 profile 自己的会话 ——
/// 那就是要的隔离。没有目标（演示数据、读数里读不到 profile 名）时一个节点都不摆：
/// 一个点下去只会说「没有可复制的目标」的菜单项，比没有更糟。
fn copy_dev_entry(row : Row) -> Array[MenuEntry] {
  match row.profile_name {
    Some(name) =>
      if name == "" {
        []
      } else {
        [MItem(CopyDev, "content-copy", "复制开发指令", false)]
      }
    None => []
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
  // 「复制开发指令」跟在这两条复制后面：菜单头上这一簇都是「把东西拿走」的动作，
  // 往下的分界线之后才是改名 / 派生 / 删除那些会改本机状态的动作。
  for entry in copy_dev_entry(row) {
    items.push(entry)
  }
  items.push(MSep)
  items.push(MItem(Rename, "rename-outline", "重命名", false))
  items.push(MItem(Note, "note-text-outline", "备注", false))
  items.push(MItem(Fork, "source-fork", "派生开发副本", false))
  // 运行中的条目**不给归档**：一只还在跑的实例从台面上撤下去，只会让人以为它停了。
  // 后端也挡了这一道（archive-profile 对在跑的 profile 回 conflict）—— 两层都在，
  // 少一层就会有人从别的地方打进来。
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
///
/// 「复制开发指令」摆在第一簇末尾（与运行中卡同一口径：都是「不动本机状态」的那一簇），
/// 分隔线之后才是改名 / 备注 / 归档 / 删除这些会真的改东西的动作。
fn stopped_menu(row : Row) -> Array[MenuEntry] {
  let items : Array[MenuEntry] = [
    MItem(Logs, "text-box-outline", "查看日志", false),
    MItem(Dir, "folder-open-outline", "打开工作目录", false),
    MItem(Config, "tune", "编辑配置", false),
  ]
  for entry in copy_dev_entry(row) {
    items.push(entry)
  }
  items.push(MSep)
  items.push(MItem(Rename, "rename-outline", "重命名", false))
  items.push(MItem(Note, "note-text-outline", "备注", false))
  items.push(MItem(Archive, "archive-outline", "归档", false))
  if row.deletable {
    items.push(MItem(Delete, "delete-outline", "删除", true))
  }
  items
}

///|
fn is_sep(entry : MenuEntry) -> Bool {
  match entry {
    MSep => true
    MItem(_, _, _, _) => false
  }
}

///|
/// 分隔线只用来分组：不该出现在菜单的头尾，也不该两条挨着。
///
/// 归档那一项从运行中的菜单里撤掉之后，「别留一条孤零零的线」这件事就有了真实的诱因。
/// 撤掉那一项本身不会留下孤线（它两边都有项），这一遍是**兜底**：以后谁再摘一项，
/// 头部 / 尾部 / 连着的那条线都不会漏出来。
fn trim_separators(entries : Array[MenuEntry]) -> Array[MenuEntry] {
  let out : Array[MenuEntry] = []
  for entry in entries {
    if is_sep(entry) {
      if out.length() > 0 && !is_sep(out[out.length() - 1]) {
        out.push(entry)
      }
    } else {
      out.push(entry)
    }
  }
  while out.length() > 0 && is_sep(out[out.length() - 1]) {
    ignore(out.pop())
  }
  out
}

///|
/// 下拉菜单。锚点挂在按钮组容器上（.dsh-actions 是 position: relative），
/// 所以右缘与按钮组右缘、进而与卡片内容盒右缘对齐；默认向下，top = 按钮组底 + 6px。
///
/// 行尾空间不够时改向上折（底边贴按钮组顶 − 6px）：这个判断只能在 DOM 落地后量，
/// 由 dom.mbt 的 js_menu_flip 在 after_render 里做一次，结论写在 data-flip 上，
/// 向上时的定位在 app.scss 的 .dsh-menu[data-flip="up"]。
fn row_menu(row : Row, emit : @cmd.Emit[Msg]) -> @html.Html {
  let running = row.status is Running
  let entries = trim_separators(
    if running { running_menu(row) } else { stopped_menu(row) },
  )
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
            attrs=mark("menu-item", ["overview", "card", row.id, "menu-item", action_name(key)])
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
    attrs=mark("row-menu", ["overview", "card", row.id, "row-menu"]).role("menu"),
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
    attrs=mark("restart", ["overview", "card", row.id, "restart"]),
    on_click=emit(RowAction(row.id, Restart)),
    [icon("refresh"), @html.span(if restarting { "重启中…" } else { "重启" })],
  )
}

///|
/// 启动按钮的点击属性。
///
/// **占位标页要在这里开**，不能在 update 里开：这个 lambda 由 DOM 监听器同步调用
/// （rabbita 的 insert_props 是 addEventListener(event => handler(event, scheduler))），
/// 而 update 走的是 queueMicrotask —— 等启动响应（约 2.5 秒）回来再 window.open，
/// 用户手势那一栈早没了，弹窗拦截器一定拦。
///
/// 回执随 StartClicked 一起进 model：开成没开成不许猜（被拦时 window.open 给 null）。
fn start_click(row : Row, emit : @cmd.Emit[Msg]) -> @html.Attrs {
  mark("start", ["overview", "card", row.id, "start"]).on_click(fn(_event) {
    let profile = match row.profile_name {
      Some(name) => name
      None => ""
    }
    let tab = if profile == "" {
      // 读数里连 profile 目录名都没有（演示数据）：这一枪本来就不会发请求，别开标页
      ""
    } else {
      js_tab_hold(profile)
    }
    emit(StartClicked(row.id, profile, tab))
  })
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
        attrs=mark("open-web-ui", ["overview", "card", row.id, "open-web-ui"])
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
        attrs=mark("stop", ["overview", "card", row.id, "stop"]),
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
        attrs=start_click(row, emit),
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
      attrs=mark("menu-trigger", ["overview", "card", row.id, "menu-trigger"])
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
        attrs=mark("menu-overlay", ["overview", "card", row.id, "menu-overlay"]),
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
          attrs=mark("sub-uptime", ["overview", "card", row.id, "sub-line", "uptime"])
            // 悬停里补上档案的健康读数（patch 行数 / lock 时刻）：
            // 这只 profile 的卡已经不再单独出现，这份读数得跟着进程卡走。
            .title(
              if row.idle_note.length() > 0 {
                (if row.uptime_hint.length() > 0 {
                  row.uptime_hint + " | "
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
          attrs=mark("sub-uptime", ["overview", "card", row.id, "sub-line", "uptime"])
            .title(row.idle_note),
          if row.idle_note.length() > 0 { row.idle_note } else { "未运行" },
        ),
      )
  }
  let note = if row.status is Starting { row.port_note } else { row.note }
  if note.length() > 0 {
    tail.push(
      @html.span(
        class="dsh-port-note",
        attrs=mark("port-note", ["overview", "card", row.id, "sub-line", "note"]).title(note),
        note,
      ),
    )
  }
  // 类型标签只在**真有话可说**时才产出节点：已停止的 profile 卡如果既不是默认、
  // 也没有别的类型，这一格就一个节点都不摆（空的 pill 比没有 pill 更糟 ✗）。
  // 这一轨的宽度照旧留着 —— 状态点要跨卡对齐（验收项「状态点跨卡对齐」量的是同列），
  // 撤掉整轨会让停止卡的点左移一整列，与运行中的卡错开。见 app.scss 的 .dsh-sub。
  let parts : Array[@html.Html] = []
  if row.kind.length() > 0 {
    parts.push(
      @html.span(
        class="dsh-kind",
        attrs=mark("sub-kind", ["overview", "card", row.id, "sub-line", "kind"]).title(row.kind_hint),
        row.kind,
      ),
    )
  }
  parts.push(
    @html.span(
      class="dsh-dot-slot",
      attrs=mark("status-dot", ["overview", "card", row.id, "sub-line", "dot"]),
      [@html.i(class="dsh-dot", @html.nothing)],
    ),
  )
  parts.push(
    @html.span(
      class="dsh-state",
      attrs=mark("sub-state", ["overview", "card", row.id, "sub-line", "state"]),
      state_label,
    ),
  )
  parts.push(@html.span(class="dsh-tail", tail))
  @html.div(
    class=sub_class,
    attrs=mark("sub-line", ["overview", "card", row.id, "sub-line"])
      .data_set("status", status_name(row.status)),
    parts,
  )
}

///|
/// 卡头中间那一列：标题行 + 副标题行。
///
/// 备注**不在这里**：它是人写的，跟「运行事实」那一列混在一起读起来像又一条读数。
/// 它摆在卡片底部、字段区下面（见 card_note）——「谁在跑、跑的什么版本」是机器读数，
/// 「这只 profile 是干什么用的」是人写的一句话，两件事在版面上分开。
fn ident_block(row : Row) -> @html.Html {
  let parts : Array[@html.Html] = [
    @html.div(class="dsh-title-line", [
      @html.span(
        class="dsh-name",
        attrs=mark("card-name", ["overview", "card", row.id, "name"]),
        row.name,
      ),
      // 标记的文字走 CSS 的 content（见 styles/app.scss 的 .dsh-console-mark::after）：
      // 卡片的 textContent 里因此没有「启动」两个字。这不是为了好看 ——
      // design/probe-dialog.mjs 是用 textContent.includes('启动') 找「已停止」那张卡的，
      // 卡里多一段含「启动」的文字会让它选中运行中的卡，进而点到旁边那颗「停止」。
      // 语义没丢：aria-label 与 title 都是同一句话。
      if row.console_started {
        @html.span(
          class="dsh-console-mark",
          attrs=mark("console-mark", ["overview", "card", row.id, "console-mark"])
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
/// 卡片字段区第六格「最近改动」的正文：有值就是本地短时刻（10-15 18:50），
/// 没值就写 row.mtime_missing —— 停止卡是「读不到」，运行卡解析不出 profile 时是「—」。
///
/// 标签是「最近改动」，**不是「创建时间」**✗：口径与理由见 state.mbt
/// 「卡片第六格『最近改动』」那段注释（ctime 会被 chmod / 改名推新，birth time 不通用）。
/// 用「最近改动」还有一层好处：刚派生出来的 profile 一定最新，它因此同时回答了
/// 「哪个是刚弄的」。
fn mtime_value(row : Row) -> String {
  match row.mtime_ms {
    Some(ms) =>
      match js_short_time_ms(ms) {
        // 数值解析不出成时刻（NaN / 越界）也算读不到，不写一个假的 0
        "" => row.mtime_missing
        short => short
      }
    None => row.mtime_missing
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
  let children : Array[@html.Html] = [
    @html.div(class="dsh-case-head", [
      @html.span(class=tile_class, [icon(tile_icon, size=20)]),
      ident_block(row),
      instance_actions(row, model, emit),
    ]),
    // 字段区是 2 列 × 3 行 = 6 格。第六格是「最近改动」——
    // 以前这里只填了 5 格，右下角空着（使用者点出来的那件事）。
    @html.ul(class="dsh-fields", [
      field("label-outline", "dsh-version", row.id, "DSH 版本 / 来源", row.version, row.version_hint),
      field("layers-outline", "profile", row.id, "Profile", row.profile, row.profile_hint),
      field("link-variant", "url", row.id, "访问地址", row.url, url_hint(row)),
      field("home-outline", "home", row.id, "DSH_HOME", row.home, row.home_hint),
      field("puzzle-outline", "plugin-count", row.id, "插件数量", row.plugin_count, row.plugin_detail),
      field("clock-outline", "mtime", row.id, "最近改动", mtime_value(row), row.mtime_hint),
    ]),
  ]
  // 备注摆在字段区**下面**：只在这一行真有备注时才多一个节点，
  // 没有备注的卡片与以前逐节点一致（几何也就一个像素都不动）。
  if row.user_note.length() > 0 {
    children.push(card_note(row))
  }
  @html.div(
    class="dsh-case",
    attrs=mark("instance-card", ["overview", "card", row.id])
      .data_set("instance", row.name),
    children,
  )
}

///|
/// 卡片底部的备注行：**人写的**一句话，跟上面的机器读数分开摆。
///
/// 「备注」标 + 左侧一道细竖线 + 比读数淡一档的颜色（见 app.scss 的 .dsh-card-note）——
/// 目标是一眼看出这是人写的，不是又一条读数。超长省略，完整内容在悬停里。
fn card_note(row : Row) -> @html.Html {
  @html.div(
    class="dsh-card-note",
    attrs=mark("card-note", ["overview", "card", row.id, "note"]).title(
      if row.user_note_source.length() > 0 {
        row.user_note + "\n（" + row.user_note_source + "）"
      } else {
        row.user_note
      },
    ),
    [
      @html.span(class="dsh-card-note-tag", "备注"),
      @html.span(class="dsh-card-note-text", row.user_note),
    ],
  )
}

///|
fn archived_row(row : Row, emit : @cmd.Emit[Msg]) -> @html.Html {
  let parts : Array[@html.Html] = [
    @html.span(
      class="dsh-archive-name",
      attrs=mark("archive-name", ["overview", "archive", row.id, "name"]),
      row.name,
    ),
    @html.span(
      class="dsh-archive-kind",
      attrs=mark("archive-kind", ["overview", "archive", row.id, "kind"]),
      row.kind,
    ),
    @html.span(class="dsh-archive-stamp", [
      @html.span(class="dsh-archive-stamp-label", "归档时间"),
      @html.span(
        class="dsh-archive-stamp-value",
        // 记录里的时间是后端给的 ISO（UTC）：显示成浏览器本地的 MM-DD HH:MM，
        // 原值留在悬停里。解析不出来就照原样显示，不吞。
        attrs=mark("archive-stamp", ["overview", "archive", row.id, "stamp"]).title(
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
      attrs=mark("unarchive", ["overview", "archive", row.id, "unarchive"]),
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
        attrs=mark("archive-delete", ["overview", "archive", row.id, "delete"]),
        on_click=emit(DeleteOpen(row.id, archive_trigger_id(row.id))),
        [icon("delete-outline"), @html.span("删除")],
      ),
    )
  }
  @html.article(
    class="dsh-archive-row",
    attrs=mark("archived-row", ["overview", "archive", row.id]),
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
    body.push(source_badge(model.tag_archived, ["overview", "section", "archived", "source-badge"]))
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
          attrs=mark("archived-toggle", ["overview", "archive", "toggle"]),
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
/// 动作结果提示条 —— **只管失败**。成功那一半走 toast（见 view_shell 的 flash_toast）：
/// 它出现几秒、自己淡出；失败留在这儿不动，直到使用者自己处理掉下一条动作。
/// 同一条规矩的两个面：正常可以沉默，异常不能沉默 —— 所以只有成功会被自动收走 ✗
///
/// 失败里写清后端给的原因（conflict / not-authorized …）。
/// 动作发不出去（这一行的读数里没有目标）也走这里，所以「没反应」这件事不会发生。
fn action_notice(model : Model) -> @html.Html {
  if model.act_notice.length() == 0 || model.act_notice_ok {
    return @html.nothing
  }
  let tone = " err"
  // 正文之外的细节（删除回执里的路径 / mode / hardDeleted）收在悬停里。
  // 只在「这段悬停确实属于当前这条提示」时挂上去：提示条被别的动作改写之后它自己失效。
  let hint = if model.act_notice_hint != "" && model.act_notice_hint_for == model.act_notice {
    model.act_notice_hint
  } else {
    ""
  }
  let text_attrs = if hint == "" {
    mark("action-notice-text", ["overview", "action-notice", "text"])
  } else {
    mark("action-notice-text", ["overview", "action-notice", "text"]).title(hint)
  }
  @html.div(
    class="dsh-notice" + tone,
    attrs=mark("action-notice", ["overview", "action-notice"]).data_set("ok", "false"),
    [
      @html.span(class="dsh-notice-text", attrs=text_attrs, model.act_notice),
    ],
  )
}

///|
/// 删除确认框：打开时焦点落在确认键，Esc 关闭，关闭后焦点回到触发元素。
fn confirm_dialog(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let name = match find_row(model.rows, model.confirm_id) {
    Some(row) => row.name
    None => model.confirm_id
  }
  // 删除方式只说一件事：**删了会怎样、能不能捞回来**。
  // 键名（safety.deleteToTrash）、请求参数（confirm=DELETE）、「设置页还没读过」这类
  // 缓存状态一律不进来 —— 那些是说给改这个工具的人听的，不是给用它的人听的。
  let mode = match delete_to_trash_of(model) {
    Some(true) => "删除后移入回收站，可以捞回来。"
    Some(false) => "删除后无法恢复。"
    None => "暂时读不到删除方式。"
  }
  // 删之前先看清这一只是干什么用的：有备注就把备注摆在确认框里，没有就不占位
  let note = match find_row(model.rows, model.confirm_id) {
    Some(row) => row.user_note
    None => ""
  }
  let note_block = if note.length() > 0 {
    @html.div(
      class="dsh-dialog-note",
      attrs=mark("confirm-note", ["dialog", "confirm-dialog", "note"]),
      [@html.span(class="dsh-dialog-note-tag", "备注"), @html.text(note)],
    )
  } else {
    @html.nothing
  }
  let card = @html.div(class="dsh-dialog-card", [
    @html.h2(
      class="dsh-dialog-title",
      attrs=mark("dialog-title", ["dialog", "confirm-dialog", "title"]),
      "删除实例 " + name + "？",
    ),
    note_block,
    @html.p(
      class="dsh-dialog-message",
      attrs=mark("dialog-message", ["dialog", "confirm-dialog", "message"]),
      mode,
    ),
    @html.div(class="dsh-dialog-foot", [
      @html.button(
        id="dsh-confirm-ok",
        class="dsh-dialog-btn primary",
        type_="button",
        attrs=mark("dialog-ok", ["dialog", "confirm-dialog", "ok"]),
        on_click=emit(DeleteConfirm),
        [@html.text("删除")],
      ),
      @html.button(
        class="dsh-dialog-btn",
        type_="button",
        attrs=mark("dialog-cancel", ["dialog", "confirm-dialog", "cancel"]),
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
    @html.h2(
      class="dsh-dialog-title",
      attrs=mark("dialog-title", ["dialog", "rename-dialog", "title"]),
      "重命名实例 " + name,
    ),
    @html.input(
      input_type=Text,
      id="dsh-rename-input",
      class="dsh-dialog-input",
      value=model.rename_draft,
      autofocus=true,
      attrs=mark("rename-input", ["dialog", "rename-dialog", "input"])
        .aria_label("实例名称")
        .spellcheck(false),
      on_input=emit.map(fn(text) { RenameInput(text) }),
    ),
    @html.div(class="dsh-dialog-foot", [
      @html.button(
        class="dsh-dialog-btn primary",
        type_="button",
        disabled=!can_confirm,
        attrs=mark("dialog-ok", ["dialog", "rename-dialog", "ok"]),
        on_click=emit(RenameConfirm),
        [@html.text("确定")],
      ),
      @html.button(
        class="dsh-dialog-btn",
        type_="button",
        attrs=mark("dialog-cancel", ["dialog", "rename-dialog", "cancel"]),
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
      attrs=mark("note-error", ["dialog", "note-dialog", "error"]),
      model.note_error,
    )
  } else {
    @html.nothing
  }
  let card = @html.div(class="dsh-dialog-card", [
    @html.h2(
      class="dsh-dialog-title",
      attrs=mark("dialog-title", ["dialog", "note-dialog", "title"]),
      [
        icon("note-text-outline", size=14),
        @html.text("编辑备注 " + name),
      ],
    ),
    @html.p(
      class="dsh-dialog-message",
      attrs=mark("dialog-message", ["dialog", "note-dialog", "message"]),
      "备注写的是这只 profile 干什么用的，存在它自己的目录里（改名、派生、搬走都跟着走）。留空保存就是删掉备注。",
    ),
    @html.textarea(
      id="dsh-note-input",
      class="dsh-dialog-input dsh-dialog-textarea",
      rows=3,
      maxlength=2000,
      value=model.note_draft,
      placeholder="这只 profile 是干什么用的…",
      autofocus=true,
      attrs=mark("note-input", ["dialog", "note-dialog", "input"])
        .aria_label("profile 备注")
        .spellcheck(false),
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
        attrs=mark("dialog-ok", ["dialog", "note-dialog", "ok"]),
        on_click=emit(NoteConfirm),
        [@html.text(if saving { "保存中…" } else { "保存" })],
      ),
      @html.button(
        id="dsh-note-cancel",
        class="dsh-dialog-btn",
        type_="button",
        disabled=saving,
        attrs=mark("dialog-cancel", ["dialog", "note-dialog", "cancel"]),
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
          "实例与 profile 的读数还在路上。这里先摆加载态 —— 「确实一个都没有」要等读数回来才敢说。",
        ),
      )
    } else {
      // 读数失败时把原因带上（那一档标记里有）；读到了就没这一句
      let detail = match model.tag_instances {
        Some(tag) => tag.detail
        None => ""
      }
      running_list.push(running_empty(running_summary(model), detail))
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
          "profile 的读数还在路上，这里先摆加载态。",
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
  // 单栏：这一页只有内容这一列。右边那栏（「工作流入口」两个按钮 + 「关于实例」三行说明）
  // 已按使用者的判断删掉 —— 那些字要么是点了没下文的摆设，要么在别处已经有了入口。
  let body : Array[@html.Html] = [
      @html.section(class="dsh-overview-page", [
        @html.header(class="dsh-overview-head", [
          @html.div(class="dsh-head-text", [
            @html.h1(class="dsh-page-title", "实例总览"),
            source_badge(model.tag_runtime, ["overview", "head", "source-badge"]),
            @html.span(class="dsh-head-note", "菜单里的动作会真的作用到本机实例与 profile"),
          ]),
          @html.button(
            class="dsh-new-btn",
            type_="button",
            attrs=mark("new-instance", ["overview", "new-instance"]),
            [@html.span(class="dsh-plus", "＋"), @html.span("新建实例")],
          ),
        ]),
        action_notice(model),
        section_head(
          "running",
          "当前运行的实例",
          if pending { "…" } else { running.length().to_string() },
          model.tag_instances,
        ),
        @html.div(class="dsh-rows", running_list),
        section_head(
          "stopped",
          "已停止的实例",
          if pending { "…" } else { stopped.length().to_string() },
          model.tag_profiles,
        ),
        @html.div(class="dsh-rows", stopped_list),
        archived_section(model, emit),
      ]),
  ]
  for node in dialogs {
    body.push(node)
  }
  @html.div(
    class="dsh-overview",
    attrs=mark("overview-page", ["overview", "page"]),
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