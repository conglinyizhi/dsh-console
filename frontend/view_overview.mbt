// 实例总览页（第七轮：卡片变条目 + 右侧覆盖式详情抽屉）。
//
// 卡片上**只剩三样**：图标 + 右上角那颗实心状态圆、profile 名（在跑的带端口）、备注。
// 六格读数、按钮组、行尾的 ⋯ 菜单全部撤走 —— 点整张卡是打开详情的唯一入口。
// 读数与控制按钮一个都没丢，它们搬进了右侧的覆盖式抽屉（见 detail_drawer）。
//
// 为什么这么做（使用者的原话）：卡片要给每只实例「详细的展示空间」，首页只留一点
// 一眼要认得出的东西；一屏里能扫过多少只 profile，比一张卡里塞多少格子更要紧。
//
// 状态灯的判据与文案在 state.mbt（instance_light / profile_light），这里只负责画。

///|
/// 动作名：抽屉里每颗按钮的 data-action，与契约里的 action 名一一对应。
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
/// 状态名（写进卡片的 data-status）：探针按它选卡，样式也按它分档。
fn status_name(status : RowStatus) -> String {
  match status {
    Running => "running"
    Stopped => "stopped"
    Starting => "starting"
  }
}

// ── 卡片 ───────────────────────────────────────────────────

///|
/// 图标右上角那颗实心圆。
///
/// 类名里保留 dsh-dot：几何不变量里那一条「同一列的状态点对齐」量的就是它 ——
/// 灯从副标题行搬到图标角上，只要每张卡的偏移一致，那条不变量照样成立。
/// 档位写在 data-state 上（running / fault / starting / stopped / unknown），
/// 样式与探针都按档位认，不按颜色值认 —— 颜色不是唯一信息，这一条从 DOM 就开始落实。
fn status_light(row : Row) -> @html.Html {
  @html.span(
    class="dsh-dot " + light_class(row.light),
    attrs=mark("status-light", ["overview", "card", row.id, "light"])
      .data_set("state", light_key(row.light))
      .role("img")
      // 悬停直接给那句「为什么」—— light_reason 自己是完整的（开头就带档位），
      // 前面再挂一次档位标签就成了「绿 · 运行中：绿 · 运行中：…」（实测踩过）
      .aria_label(light_label(row.light))
      .title(row.light_reason),
    @html.nothing,
  )
}

///|
/// 「由本控制台启动」那个标记（runtime.json 的登记）。
///
/// 它从卡片的标题行搬进了抽屉：卡片只剩三样，这一枚是第四样。
/// 搬走不等于删掉 —— 它是「这只实例是我起的」的唯一凭据，摆在抽屉标题下面。
fn console_mark(row : Row) -> @html.Html {
  if !row.console_started {
    return @html.nothing
  }
  @html.span(
    class="dsh-console-mark",
    attrs=mark("console-mark", ["overview", "drawer", row.id, "console-mark"])
      .data_set("mark", "console-started")
      .role("img")
      .aria_label("由本控制台启动")
      .title(
        "由本控制台启动：这一条在 $XDG_STATE_HOME/dsh-console/runtime.json 的登记里。登记只记控制台自己起的，外部实例不写进去",
      ),
    [icon("play", size=11), @html.text("由本控制台启动")],
  )
}

///|
/// 整张卡的可点属性：点它是打开抽屉的唯一入口，键盘也能开（Enter / 空格）。
///
/// 卡片是 article + role=button，不是 <button>：卡片里将来可能还要放文本节点，
/// 而 button 里嵌块级内容是无效的；role + tabindex 给的是同一套键盘与读屏语义。
fn card_attrs(row : Row, emit : @cmd.Emit[Msg]) -> @html.Attrs {
  mark("instance-card", ["overview", "card", row.id])
    .data_set("instance", row.name)
    .data_set("status", status_name(row.status))
    .data_set("light", light_key(row.light))
    .role("button")
    .tabindex(0)
    .aria_haspopup("dialog")
    .aria_label(row.name + " —— 点开看读数与控制（" + light_label(row.light) + "）")
    .on_click(fn(_event) { emit(DrawerOpen(row.id)) })
    .on_keydown(fn(event) {
      if event.key() == "Enter" || event.key() == " " {
        emit(DrawerOpen(row.id))
      } else {
        @cmd.none
      }
    })
}

///|
/// 一张实例卡：图标 + 右上角状态灯、profile 名、备注（有才显示）。
fn instance_card(row : Row, _model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
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
      @html.span(class="dsh-tile-slot", [
        @html.span(class=tile_class, [icon(tile_icon, size=20)]),
        status_light(row),
      ]),
      @html.span(
        class="dsh-name",
        attrs=mark("card-name", ["overview", "card", row.id, "name"]).title(
          row.name + "（" + light_label(row.light) + "）",
        ),
        row.name,
      ),
    ]),
  ]
  // 备注只在这一行真有内容时才多一个节点：没有备注的卡片 DOM 逐节点一致
  if row.user_note.length() > 0 {
    children.push(card_note(row))
  }
  @html.article(
    id=card_id(row.id),
    class="dsh-case",
    attrs=card_attrs(row, emit),
    children,
  )
}

///|
/// 卡片底部的备注行：**人写的**一句话，与机器读数分开摆。
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

// ── 详情抽屉 ───────────────────────────────────────────────

///|
/// 「访问地址」那一行的悬停：这一栏只说这一行自己（在不在监听、监听在哪），
/// **不提令牌** —— 带令牌的地址走「打开 Web UI」与「复制带令牌的地址」。
fn url_hint(row : Row) -> String {
  match row.status {
    Stopped => "这只 profile 现在没有在跑，所以没有可访问的地址"
    Starting => "实例正在起来，端口还没开始监听"
    Running => "这只实例正在 " + row.url + " 上监听（要进去用「打开 Web UI」）"
  }
}

///|
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
/// 字段区第六格「最近改动」的正文：有值就是本地短时刻（10-15 18:50），
/// 没值就写 row.mtime_missing —— 停止卡是「读不到」，运行卡解析不出 profile 时是「—」。
///
/// 标签是「最近改动」，**不是「创建时间」**：口径与理由见 state.mbt
/// 「卡片第六格『最近改动』」那段注释（ctime 会被 chmod / 改名推新，birth time 不通用）。
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
/// 抽屉里的一颗控制按钮。图标 + 文字，与卡片上原来那排按钮同一副皮（.dsh-btn）。
///
/// data-action 写的是契约里的动作名，data-name 是 drawer-<动作名>：
/// 探针与使用者的拾取工具按它定位，不看位置。
fn drawer_button(
  row : Row,
  key : ActionKey,
  icon_name : String,
  label : String,
  danger : Bool,
  disabled : Bool,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let name = action_name(key)
  @html.button(
    class=if danger { "dsh-btn danger" } else { "dsh-btn" },
    type_="button",
    disabled=disabled,
    attrs=mark(
      "drawer-" + name,
      ["overview", "drawer", row.id, "action", name],
    ).data_set("action", name),
    on_click=emit(RowAction(row.id, key)),
    [icon(icon_name), @html.span(label)],
  )
}

///|
/// 抽屉里那颗「启动」：与原来卡上那颗同一个 start_click。
///
/// **占位标页必须在 DOM 监听器里同步开**（见 start_click 的注释）：等启动响应回来再
/// window.open，用户手势那一栈早没了，弹窗拦截器一定拦。
fn drawer_start_button(row : Row, emit : @cmd.Emit[Msg]) -> @html.Html {
  let tone = match row.tone {
    Accent => " accent"
    Violet => " violet"
  }
  @html.button(
    class="dsh-btn primary" + tone,
    type_="button",
    disabled=row.busy,
    attrs=start_click(row, emit),
    [
      icon("play", size=13),
      @html.span(if row.status is Starting { "启动中…" } else { "启动" }),
    ],
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
  mark("drawer-start", ["overview", "drawer", row.id, "action", "start"])
    .data_set("action", "start")
    .on_click(fn(_event) {
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
/// 抽屉里那一组控制按钮 —— **今天行菜单里有的一个不少**。
///
/// 顺序照原来的菜单骨架：先主操作（打开 / 起停 / 重启），再「把东西拿走」那一簇
/// （开新标签、两条复制、复制开发指令），然后是会改本机状态的（重命名 / 备注 / 派生 /
/// 归档 / 删除），最后是运维三项（查看日志 / 打开工作目录 / 编辑配置）。
fn drawer_controls(row : Row, model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let running = row.status is Running
  let busy = row.busy
  // 主色底随色调走：运行卡蓝、profile 卡紫（与卡片图标底板同一套）
  let tone = match row.tone {
    Accent => " accent"
    Violet => " violet"
  }
  let main : Array[@html.Html] = []
  if running {
    main.push(
      @html.button(
        class="dsh-btn primary" + tone,
        type_="button",
        // 令牌读不到时按钮**照样可点**：点下去先把原因说清，不给一个点了 401 的链接
        attrs=mark("drawer-open-web-ui", ["overview", "drawer", row.id, "action", "open-ui"])
          .data_set("action", "open-ui")
          .title(open_ui_hint(row)),
        on_click=emit(RowAction(row.id, OpenUi)),
        [icon("open-in-new"), @html.span("打开 Web UI")],
      ),
    )
    main.push(
      @html.button(
        class="dsh-btn",
        type_="button",
        disabled=busy,
        attrs=mark("drawer-stop", ["overview", "drawer", row.id, "action", "stop"])
          .data_set("action", "stop"),
        on_click=emit(RowAction(row.id, Toggle)),
        [@html.i(class="dsh-dot-danger", @html.nothing), @html.span("停止")],
      ),
    )
  } else {
    main.push(drawer_start_button(row, emit))
  }
  main.push(
    @html.button(
      class="dsh-btn",
      type_="button",
      disabled=model.restarting == row.id || busy,
      attrs=mark("drawer-restart", ["overview", "drawer", row.id, "action", "restart"])
        .data_set("action", "restart"),
      on_click=emit(RowAction(row.id, Restart)),
      [
        icon("refresh"),
        @html.span(if model.restarting == row.id { "重启中…" } else { "重启" }),
      ],
    ),
  )
  let take : Array[@html.Html] = []
  if running {
    take.push(
      drawer_button(row, Tab, "open-in-new", "在新标签页打开", false, false, emit),
    )
  }
  take.push(drawer_button(row, CopyUrl, "link-variant", "复制访问地址", false, false, emit))
  // 带令牌的地址只有真读到时才有这一项：读不到令牌就不摆一个「复制空串」出来
  if row.web_url is Some(_) {
    take.push(
      drawer_button(row, CopyTokenUrl, "key-variant", "复制带令牌的地址", false, false, emit),
    )
  }
  // 「复制开发指令」认得出 profile 目录名才摆（见 copy_dev_entry 的原口径）
  match row.profile_name {
    Some(name) =>
      if name != "" {
        take.push(drawer_button(row, CopyDev, "content-copy", "复制开发指令", false, false, emit))
      }
    None => ()
  }
  let mutate : Array[@html.Html] = [
    drawer_button(row, Rename, "rename-outline", "重命名", false, busy, emit),
    drawer_button(row, Note, "note-text-outline", "备注", false, busy, emit),
  ]
  if running {
    mutate.push(drawer_button(row, Fork, "source-fork", "派生开发副本", false, busy, emit))
  } else {
    mutate.push(drawer_button(row, Archive, "archive-outline", "归档", false, busy, emit))
  }
  if row.archived_at is Some(_) {
    mutate.push(drawer_button(row, Unarchive, "archive-arrow-up-outline", "取消归档", false, busy, emit))
  }
  if row.deletable {
    mutate.push(drawer_button(row, Delete, "delete-outline", "删除", true, busy, emit))
  }
  // 运维三项：查看日志 / 打开工作目录 / 编辑配置（第三轮接上的那三项）
  let ops : Array[@html.Html] = [
    drawer_button(row, Logs, "text-box-outline", "查看日志", false, busy, emit),
    drawer_button(row, Dir, "folder-open-outline", "打开工作目录", false, busy, emit),
    drawer_button(row, Config, "tune", "编辑配置", false, busy, emit),
  ]
  let groups : Array[(String, Array[@html.Html])] = [
    ("主操作", main),
    ("拿走", take),
    ("改动这只 profile", mutate),
    ("运维", ops),
  ]
  let blocks : Array[@html.Html] = []
  for group in groups {
    let (title, items) = group
    blocks.push(
      @html.div(class="dsh-drawer-group", [
        @html.span(class="dsh-drawer-group-title", title),
        @html.div(class="dsh-drawer-btns", items),
      ]),
    )
  }
  @html.div(class="dsh-drawer-section", [
    @html.h3(class="dsh-drawer-section-title", "控制"),
    @html.fragment(blocks),
  ])
}

///|
/// 抽屉最上面那一块：**为什么是这个颜色**。
///
/// 契约里的硬要求（颜色不能是唯一信息）就落在这里：档位标签 + 一句判据，
/// 再把后端给的 state / stateReason 原样摆出来。黄的两种成因因此分得开：
/// b 是「端口在听但签名探测不通过」，c 是「profile 缺包 / 没有 cordis.patch.yml」，
/// 两句话长得不一样，不会都被读成一句「有点问题」。
fn drawer_state_block(row : Row) -> @html.Html {
  let lines : Array[@html.Html] = [
    @html.div(class="dsh-drawer-light-line", [
      @html.span(
        class="dsh-dot " + light_class(row.light),
        attrs=mark("drawer-light", ["overview", "drawer", row.id, "state", "light"])
          .data_set("state", light_key(row.light))
          .role("img")
          .aria_label(light_label(row.light)),
        @html.nothing,
      ),
      @html.span(
        class="dsh-drawer-light-label",
        attrs=mark("drawer-light-label", ["overview", "drawer", row.id, "state", "label"])
          .data_set("state", light_key(row.light)),
        light_label(row.light),
      ),
    ]),
    @html.p(
      class="dsh-drawer-why",
      attrs=mark("drawer-why", ["overview", "drawer", row.id, "state", "why"]),
      row.light_reason,
    ),
  ]
  // 后端给的原值原样摆出来：判据是后端下的，前端只是把它说清楚
  lines.push(
    @html.p(
      class="dsh-drawer-raw",
      attrs=mark("drawer-state-raw", ["overview", "drawer", row.id, "state", "raw"]),
      "后端 state：" + row.state_raw,
    ),
  )
  lines.push(
    @html.p(
      class="dsh-drawer-raw",
      attrs=mark("drawer-state-reason", ["overview", "drawer", row.id, "state", "reason"]),
      "后端 stateReason：" + row.state_reason,
    ),
  )
  @html.div(class="dsh-drawer-section", [
    @html.h3(class="dsh-drawer-section-title", "状态"),
    @html.fragment(lines),
  ])
}

///|
/// 详情抽屉：右侧、覆盖式。
///
/// - 点卡片滑出；点外部 / Esc / 关闭键收起（三条路都发 DrawerClose）
/// - 焦点：打开时落进抽屉里的关闭键（update 里的 DrawerOpen 发 focus cmd），
///   关闭时回触发它的那张卡（卡有稳定 id，见 card_id）
/// - 遮罩与面板是**兄弟**：rabbita 的 div.on_click 收不到事件对象、判断不了 target，
///   父子结构下点面板会冒泡到遮罩上。兄弟结构下「点外部关闭」天然成立，
///   与既有对话框同一套做法（见 view_parts 的 dialog）。
/// - 窄屏占满宽度、宽屏固定宽度，内容自己滚（见 app.scss 的 .dsh-drawer）
fn detail_drawer(row : Row, model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let fields = @html.ul(class="dsh-fields", [
    field("label-outline", "dsh-version", row.id, "DSH 版本 / 来源", row.version, row.version_hint),
    field("layers-outline", "profile", row.id, "Profile", row.profile, row.profile_hint),
    field("link-variant", "url", row.id, "访问地址", row.url, url_hint(row)),
    field("home-outline", "home", row.id, "DSH_HOME", row.home, row.home_hint),
    field("puzzle-outline", "plugin-count", row.id, "插件数量", row.plugin_count, row.plugin_detail),
    field("clock-outline", "mtime", row.id, "最近改动", mtime_value(row), row.mtime_hint),
  ])
  let body : Array[@html.Html] = [
    drawer_state_block(row),
    @html.div(class="dsh-drawer-section", [
      @html.h3(class="dsh-drawer-section-title", "读数"),
      fields,
    ]),
    @html.div(class="dsh-drawer-section", [
      @html.h3(class="dsh-drawer-section-title", "profile 健康"),
      @html.p(
        class="dsh-drawer-health",
        attrs=mark("drawer-health", ["overview", "drawer", row.id, "health"]),
        row.health_text,
      ),
      @html.p(
        class="dsh-drawer-raw",
        attrs=mark("drawer-health-source", ["overview", "drawer", row.id, "health", "source"]),
        "来源：" + row.health_source,
      ),
    ]),
  ]
  if row.user_note.length() > 0 {
    body.push(
      @html.div(class="dsh-drawer-section", [
        @html.h3(class="dsh-drawer-section-title", "备注"),
        card_note(row),
      ]),
    )
  }
  body.push(drawer_controls(row, model, emit))
  let head : Array[@html.Html] = [
    @html.div(class="dsh-drawer-head", [
      @html.span(
        class="dsh-drawer-name",
        attrs=mark("drawer-name", ["overview", "drawer", row.id, "name"]),
        row.name,
      ),
      console_mark(row),
      @html.button(
        id=drawer_close_id(),
        class="dsh-btn icon-only",
        type_="button",
        attrs=mark("drawer-close", ["overview", "drawer", row.id, "close"])
          .aria_label("关闭详情"),
        on_click=emit(DrawerClose),
        [icon("close", size=16)],
      ),
    ]),
  ]
  @html.fragment([
    @html.div(
      class="dsh-drawer-scrim",
      attrs=mark("drawer-scrim", ["overview", "drawer", row.id, "scrim"]),
      on_click=emit(DrawerClose),
      @html.nothing,
    ),
    @html.aside(
      id=drawer_panel_id(),
      class="dsh-drawer",
      attrs=mark("detail-drawer", ["overview", "drawer", row.id])
        .role("dialog")
        .aria_modal("true")
        .aria_label("详情 " + row.name)
        .data_set("light", light_key(row.light))
        .on_keydown(fn(event) {
          if event.key() == "Escape" {
            emit(DrawerClose)
          } else {
            @cmd.none
          }
        }),
      [@html.fragment(head), @html.div(class="dsh-drawer-body", body)],
    ),
  ])
}

// ── 归档区 ─────────────────────────────────────────────────

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
/// 归档区：可折叠 + 取消归档。这一组的内容由本轮真点过「归档」的 profile 组成
/// （归档记录的读接口见 GET /api/local/console 的 archive）。
fn archived_section(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let items = model.rows.filter(fn(row) { row.archived_at is Some(_) })
  if items.length() == 0 {
    return @html.nothing
  }
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

// ── 提示条与对话框 ─────────────────────────────────────────

///|
/// 动作结果提示条 —— **只管失败**。成功那一半走 toast（见 view_shell 的 flash_toast）：
/// 它出现几秒、自己淡出；失败留在这儿不动，直到使用者自己处理掉下一条动作。
/// 同一条规矩的两个面：正常可以沉默，异常不能沉默 —— 所以只有成功会被自动收走
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
  let mode = match delete_to_trash_of(model) {
    Some(true) => "删除后移入回收站，可以捞回来。"
    Some(false) => "删除后无法恢复。"
    None => "暂时读不到删除方式。"
  }
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

// ── 页面 ───────────────────────────────────────────────────

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
  let body : Array[@html.Html] = [
    @html.section(class="dsh-overview-page", [
      @html.header(class="dsh-overview-head", [
        @html.div(class="dsh-head-text", [
          @html.h1(class="dsh-page-title", "实例总览"),
          source_badge(model.tag_runtime, ["overview", "head", "source-badge"]),
          @html.span(class="dsh-head-note", "点卡片看读数与控制；卡片上的圆是状态灯"),
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
      @html.div(class="dsh-rows dsh-card-grid", running_list),
      section_head(
        "stopped",
        "已停止的实例",
        if pending { "…" } else { stopped.length().to_string() },
        model.tag_profiles,
      ),
      @html.div(class="dsh-rows dsh-card-grid", stopped_list),
      archived_section(model, emit),
    ]),
  ]
  for node in dialogs {
    body.push(node)
  }
  // 详情抽屉：同一时刻只开一个，开着的那一行必须在（列表重建后行没了就自动不开，
  // 见 app.mbt 的 rebuild —— 抽屉指向一个不存在的行会留下一个关不掉的空面板）。
  match find_row(model.rows, model.drawer_id) {
    Some(row) => body.push(detail_drawer(row, model, emit))
    None => ()
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
