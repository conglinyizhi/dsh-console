// 应用外壳：左侧导航六项（实例总览 / 维护 / 日志 / 设置 / 回收站 / 关于）+ 内容区。
//
// 导航既是状态切页也写地址（见 route.mbt）：刷新与前进/后退按地址复原页面。
// 页脚那颗「服务端在线」灯在导航栏底部（design/design-fixes.md §31.1），
// 由 app.mbt 里每 5 秒一次的探测喂，不是写死的文案。
// 顶部那条 .dsh-route-notice 只在地址认不出来、被回落时出现 —— 回落必须说清为什么，
// 不然「点进来发现不是自己要的那一页」就成了没法解释的怪事。
//
// 侧栏有两副形状（design/sidebar-collapse.md）：
//   ≥1024  文档流里的第一列。190px 展开，或 56px 的图标栏（顶栏那颗按钮切换，
//          形态存进设置 ui.sidebarCollapsed，刷新之后照旧）。
//   <1024  不占位：主区满宽，顶栏换成一条窄栏（汉堡 + 当前页名）。点汉堡时侧栏
//          从左边滑出来盖在页面上（宽 min(280px, 78vw)），底下加一层遮罩。
//          收起来的三种走法：Esc / 点遮罩 / 点任意导航项。
//
// 外壳自建，不套现成的抽屉/顶栏组件：以前试过 md2 的 navigation_drawer / app_bar，
// 那两个把 position: fixed、z-index、side 偏移写成了**内联样式**，而这套外壳是文档流里的
// flex 两列（.dsh-shell）—— 内联样式没法从样式表压过，除非上 !important。
// 形状全部来自 styles/app.scss，与 Vue 版逐条对齐。

///|
/// 导航项的 DOM id：窄屏覆盖层打开时焦点要落在第一项上（app.mbt 按它找节点）。
fn nav_dom_id(page : Page) -> String {
  "dsh-nav-" + nav_key(page)
}

///|
/// 窄屏顶栏那颗汉堡的 id：覆盖层收起之后焦点回它。
fn side_burger_id() -> String {
  "dsh-side-burger"
}

///|
/// 宽屏顶栏那颗折叠按钮的 id。
fn side_toggle_id() -> String {
  "dsh-side-toggle"
}

///|
/// 导航项的文字（侧栏的一行、顶栏的当前页名，宽屏窄屏两处都用这一份）。
fn page_label(page : Page) -> String {
  match page {
    Overview => "实例总览"
    Maintenance => "维护"
    Logs => "日志"
    Settings => "设置"
    Trash => "回收站"
    About => "关于"
  }
}

///|
fn nav_item(
  page : Page,
  current : Page,
  icon_name : String,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let active = page == current
  let label = page_label(page)
  @html.button(
    id=nav_dom_id(page),
    class=if active { "dsh-nav-item active" } else { "dsh-nav-item" },
    type_="button",
    attrs=mark("nav-" + nav_key(page), ["shell", "nav", nav_key(page)])
      .aria_current(if active { "page" } else { "false" })
      // 收起成图标栏时文字那一格不显示，名字靠这条 aria-label 与下面那颗提示
      .aria_label(label),
    on_click=emit(Navigate(page)),
    [
      @html.span(class="dsh-nav-icon", [icon(icon_name, size=16)]),
      @html.span(class="dsh-nav-label", label),
      // 悬停提示：只在宽屏的图标栏形态下显示（见 app.scss），展开态与窄屏都不产出视觉
      @html.span(class="dsh-nav-tip", label),
    ],
  )
}

///|
fn nav_key(page : Page) -> String {
  match page {
    Overview => "overview"
    Maintenance => "maintenance"
    Logs => "logs"
    Settings => "settings"
    Trash => "trash"
    About => "about"
  }
}

///|
/// 侧栏本体。两个类名说的是两件事，互不覆盖：
///   collapsed  宽屏的图标栏形态（窄屏的样式块把它整段盖过去）
///   open       窄屏的覆盖层正在滑出
///   （没有类名就是宽屏的展开态 / 窄屏的收起态）
fn side_nav(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let cls = if model.sidebar_overlay {
    if model.sidebar_collapsed {
      "dsh-side collapsed open"
    } else {
      "dsh-side open"
    }
  } else if model.sidebar_collapsed {
    "dsh-side collapsed"
  } else {
    "dsh-side"
  }
  @html.aside(
    id="dsh-side-nav",
    class=cls,
    attrs=mark("side-nav", ["shell", "side-nav"])
      .aria_label("主导航")
      .data_set(
        "collapsed",
        if model.sidebar_collapsed {
          "true"
        } else {
          "false"
        },
      )
      .data_set("open", if model.sidebar_overlay { "true" } else { "false" }),
    [
      @html.div(class="dsh-brand", [
        @html.span(class="dsh-brand-icon", [icon("hub-outline", size=17)]),
        @html.span(class="dsh-brand-title", "DSH 控制台"),
      ]),
      @html.nav(class="dsh-nav", [
        nav_item(Overview, model.page, "view-grid-outline", emit),
        // 维护紧跟在实例总览下面（规格 §2 定的位置）：它是第二条「对整台机器做事」的入口
        nav_item(Maintenance, model.page, "tune", emit),
        nav_item(Logs, model.page, "text-box-outline", emit),
        nav_item(Settings, model.page, "cog-outline", emit),
        // 回收站挨着「关于」放：它是一条能真删东西的入口，摆在一排设置项后面不抢视线，
        // 也不跟「实例总览」那种常用项混在一起
        nav_item(Trash, model.page, "delete-outline", emit),
        nav_item(About, model.page, "shield-outline", emit),
      ]),
      // 页脚那颗灯（design/design-fixes.md §31.1）：**服务端在线状态**，不是「仅限回环」那句。
      // 颜色 + 状态词两通道：三档各有自己的说法，悬停里给细节（响应毫秒 / 连续失败与原因）。
      // role=status + aria-live=polite：这一格会自己变，读屏跟着播一句。
      @html.p(
        class="dsh-side-foot",
        attrs=mark("side-foot", ["shell", "side-foot"])
          .data_set("state", health_key(model.health_state))
          .title(health_hint(model))
          .role("status")
          .aria_live("polite"),
        [
          @html.i(
            class="dsh-side-dot " + health_key(model.health_state),
            attrs=mark("side-foot-dot", ["shell", "side-foot", "dot"]).aria_hidden(
              "true",
            ),
            @html.nothing,
          ),
          @html.span(
            class="dsh-side-foot-text",
            attrs=mark("side-foot-text", ["shell", "side-foot", "text"]),
            health_label(model.health_state),
          ),
          // 版本号（只读）：server 与 client 的构建 sha 各一段，悬停给构建时刻。
          // 服务端没连上时只剩 client 那一段。
          @html.span(
            class="dsh-side-ver",
            attrs=mark("side-version", ["shell", "side-foot", "version"]).title(
              "client " + build_at + "（本页构建）",
            ),
            [
              @html.span(
                attrs=mark("side-version-client", [
                  "shell", "side-foot", "client",
                ]),
                // 优先显示资源内容哈希（构建时按 app.js 内容算的，改了就变）；
                // 读不到才回落到 git sha —— 开发时没有 ?v= 参数就是这一档。
                "client " +
                (match js_asset_version() {
                  "" => build_sha
                  v => v
                }),
              ),
            ],
          ),
          match model.console {
            Some(facts) =>
              if facts.build_sha == "" {
                @html.nothing
              } else {
                @html.span(
                  class="dsh-side-ver",
                  attrs=mark("side-version-server", [
                    "shell", "side-foot", "server",
                  ]).title(
                    "server " + facts.build_at + "（控制台后端构建）",
                  ),
                  "server " + facts.build_sha,
                )
              }
            None => @html.nothing
          },
        ],
      ),
    ],
  )
}

///|
/// 宽屏顶栏（≥1024 才显示）：折叠按钮在前，紧挨着当前页名，右边留空。
///
/// 上一轮把顶栏整条去掉，是因为它当时只为「设置」那一个按钮存在；这一轮侧栏要能收起，
/// 那开关得有地方放，于是顶栏回来一条窄的并带上当前页名 —— 只有一颗按钮的空带子
/// 正是上一轮删掉的东西，不再造一遍。
fn shell_topbar(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let collapsed = model.sidebar_collapsed
  @html.header(class="dsh-topbar", attrs=mark("topbar", ["shell", "topbar"]), [
    @html.button(
      id=side_toggle_id(),
      class="dsh-icon-btn",
      type_="button",
      attrs=mark("side-toggle", ["shell", "topbar", "side-toggle"])
        .aria_label(if collapsed { "展开侧栏" } else { "收起侧栏" })
        .aria_expanded(if collapsed { "false" } else { "true" })
        .aria_controls("dsh-side-nav")
        .title(
          if collapsed {
            "展开侧栏（190px，带文字）"
          } else {
            "收起成 56px 的图标栏，悬停看名字"
          },
        ),
      on_click=emit(SidebarToggle),
      [
        icon(
          if collapsed {
            "chevron-double-right"
          } else {
            "chevron-double-left"
          },
          size=16,
        ),
      ],
    ),
    @html.span(
      class="dsh-topbar-title",
      attrs=mark("topbar-title", ["shell", "topbar", "title"]),
      page_label(model.page),
    ),
    // 顶栏右侧：通知（§36）。按钮 + 未读角标，点在右侧开历史侧栏。
    notice_bell(model, emit, "topbar"),
  ])
}

///|
/// 窄屏顶栏（<1024 才显示）：汉堡 + 当前页名，右侧留空。
fn shell_narrowbar(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  @html.header(
    class="dsh-narrowbar",
    attrs=mark("narrowbar", ["shell", "narrowbar"]),
    [
      @html.button(
        id=side_burger_id(),
        class="dsh-icon-btn",
        type_="button",
        attrs=mark("side-burger", ["shell", "narrowbar", "burger"])
          .aria_label("打开导航")
          .aria_expanded(if model.sidebar_overlay { "true" } else { "false" })
          .aria_controls("dsh-side-nav")
          .title("打开导航"),
        on_click=emit(SidebarOverlayOpen),
        [icon("menu", size=18)],
      ),
      @html.span(
        class="dsh-narrowbar-title",
        attrs=mark("narrowbar-title", ["shell", "narrowbar", "title"]),
        page_label(model.page),
      ),
      // 窄屏顶栏也摆一颗：那一档没有侧栏可挂，通知是全局的，落在顶栏右侧最顺。
      notice_bell(model, emit, "narrowbar"),
    ],
  )
}

///|
/// 窄屏侧栏的遮罩。**节点一直在 DOM 里**，只有窄屏且覆盖层开着时才显示
/// （见 app.scss 的 display 规则）：这样宽屏不会因为它多一层浮层，
/// 从窄屏拉宽到宽屏时也不会留下一个盖住整页的东西。
fn side_scrim(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  @html.div(
    class=if model.sidebar_overlay {
      "dsh-side-scrim open"
    } else {
      "dsh-side-scrim"
    },
    attrs=mark("side-scrim", ["shell", "side-scrim"]),
    on_click=emit(SidebarOverlayClose),
    @html.nothing,
  )
}

///|
/// 地址回落说明：认不出来的地址落在这一页时，把「为什么」摆在最上面。
/// 没有要说的就一个节点都不占（DOM 里不留空壳）。
fn route_notice_bar(model : Model) -> @html.Html {
  if model.route_notice.length() == 0 {
    return @html.nothing
  }
  @html.p(
    class="dsh-route-notice",
    attrs=mark("route-notice", ["shell", "route-notice"]).role("status"),
    [
      @html.span(class="dsh-route-notice-tag", "地址回落"),
      @html.span(model.route_notice),
    ],
  )
}

///|
/// 顶栏那颗「通知」（design/design-fixes.md §36）：铃铛 + 未读条数角标。
///
/// 角标只是「上次打开侧栏之后又来了几条」：打开就算看过了，不另设已读操作。
/// 颜色之外还有 aria-label 与悬停里的条数 —— 不靠颜色单独表达。
fn notice_bell(
  model : Model,
  emit : @cmd.Emit[Msg],
  slot : String,
) -> @html.Html {
  let unread = model.notice_unread
  let count = if unread > notice_history_max {
    notice_history_max
  } else {
    unread
  }
  // 铃铛上不再挂未读数量（§97）：数字压在图标上既挤又容易和面板标题混读；
  // 未读信息只留在 aria-label 与悬停里，给读屏与鼠标用户，不占视觉。
  let kids : Array[@html.Html] = [icon("bell-outline", size=16)]
  @html.button(
    id=notice_bell_id(),
    class=if model.notice_panel {
      "dsh-icon-btn dsh-bell active"
    } else {
      "dsh-icon-btn dsh-bell"
    },
    type_="button",
    attrs=mark("notice-bell", ["shell", slot, "notice", "bell"])
      .aria_label(
        if count > 0 {
          "通知：还有 " + count.to_string() + " 条未读"
        } else {
          "通知"
        },
      )
      .aria_haspopup("dialog")
      .aria_expanded(if model.notice_panel { "true" } else { "false" })
      .aria_controls("dsh-notice-panel")
      .data_set("unread", count.to_string())
      .title(
        if count > 0 {
          count.to_string() + " 条未读通知"
        } else {
          "通知历史：这次打开页面以来的动作结果"
        },
      ),
    on_click=emit(NoticePanelOpen),
    kids,
  )
}

///|
/// 通知历史里的一行（§36 / §45）：时刻、成功或失败（文字，不只是颜色）、
/// **完整正文**（不再两行封顶，失败原文本来就该看全），以及两颗动作：
/// 「复制」把正文与悬停细节一起写进剪贴板，「查看日志」只在这一条有审计行时出现。
fn notice_row(
  item : NoticeRecord,
  index : Int32,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let mut attrs = mark("notice-row", [
    "shell",
    "notice",
    "panel",
    "row",
    index.to_string(),
  ])
  if item.hint != "" {
    attrs = attrs.title(item.hint)
  }
  let copy_text = if item.hint == "" {
    item.text
  } else {
    item.text + "\n" + item.hint
  }
  let actions : Array[@html.Html] = [
    @html.button(
      class="dsh-notice-row-btn",
      type_="button",
      attrs=mark("notice-row-copy", [
        "shell",
        "notice",
        "panel",
        "row",
        index.to_string(),
        "copy",
      ]).title("复制这一条的正文与细节"),
      on_click=copy_cmd("通知", copy_text, emit),
      [@html.text("复制")],
    ),
  ]
  if item.audit {
    actions.push(
      @html.button(
        class="dsh-notice-row-btn",
        type_="button",
        attrs=mark("notice-row-logs", [
          "shell",
          "notice",
          "panel",
          "row",
          index.to_string(),
          "logs",
        ]).title("在控制台审计里看这一条的完整记录"),
        on_click=emit(NoticeOpenLogs),
        [@html.text("查看日志")],
      ),
    )
  }
  @html.div(
    class=if item.ok { "dsh-notice-row ok" } else { "dsh-notice-row err" },
    attrs~,
    [
      @html.div(class="dsh-notice-row-head", [
        @html.span(class="dsh-notice-row-time", item.at),
        @html.span(
          class="dsh-notice-row-mark",
          if item.ok {
            "成功"
          } else {
            "失败"
          },
        ),
      ]),
      @html.span(class="dsh-notice-row-text", item.text),
      @html.div(class="dsh-notice-row-actions", actions),
    ],
  )
}

///|
/// 通知历史侧栏（§36）：右侧覆盖式，遮罩与面板是兄弟（与抽屉同一套）。
///
/// 层级 57/56：盖在抽屉与侧栏（51/50）和提示条（55）之上，在确认框（60/61）之下 ——
/// 通知是「刚刚发生了什么」的回看，不该被提示条自己挡住。
fn notice_panel(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  if !model.notice_panel {
    return @html.nothing
  }
  let rows : Array[@html.Html] = []
  let mut i = 0
  for item in model.notice_history {
    rows.push(notice_row(item, i, emit))
    i = i + 1
  }
  let body : Array[@html.Html] = if rows.length() == 0 {
    [
      @html.p(
        class="dsh-notice-empty",
        attrs=mark("notice-empty", ["shell", "notice", "panel", "empty"]),
        "还没有通知。动作的结果会在这里留一条。",
      ),
    ]
  } else {
    [
      @html.div(
        class="dsh-notice-list",
        attrs=mark("notice-list", ["shell", "notice", "panel", "list"]),
        rows,
      ),
    ]
  }
  @html.fragment([
    @html.div(
      class="dsh-notice-panel-scrim",
      attrs=mark("notice-panel-scrim", ["shell", "notice", "panel", "scrim"]),
      on_click=emit(NoticePanelClose),
      @html.nothing,
    ),
    @html.aside(
      id="dsh-notice-panel",
      class="dsh-notice-panel",
      attrs=mark("notice-panel", ["shell", "notice", "panel"])
        .role("dialog")
        .aria_modal("true")
        .aria_label("通知")
        .on_keydown(fn(event) {
          if event.key() == "Escape" {
            emit(NoticePanelClose)
          } else {
            @cmd.none
          }
        }),
      [
        @html.div(class="dsh-notice-panel-head", [
          @html.h2(
            class="dsh-notice-panel-title",
            attrs=mark("notice-panel-title", [
              "shell", "notice", "panel", "title",
            ]),
            "通知",
          ),
          @html.button(
            id=notice_panel_close_id(),
            class="dsh-btn icon-only",
            type_="button",
            attrs=mark("notice-panel-close", [
              "shell", "notice", "panel", "close",
            ]).aria_label("关闭通知"),
            on_click=emit(NoticePanelClose),
            [icon("close", size=16)],
          ),
        ]),
        @html.div(class="dsh-notice-panel-body", body),
      ],
    ),
  ])
}

///|
/// 全局提示（design/ops-maintenance-jobs.md §14）：**动作结果的唯一出口**。
///
/// 只在 shell 这一层渲染一次，六个页面共用同一份状态 —— 在总览点出来的提示，
/// 切到设置页、关于页仍然看得见。成功是底部 toast（3.5 秒后自己淡出），
/// 失败是常驻提示条（留到下一条动作替换它，绝不自动消失）。
///
/// 层级：盖在抽屉与版本 / 配置侧栏之上（那两条是 50 / 51），在确认框之下（60 / 61）。
/// 位置在内容区底部居中（左侧导航 190px，所以圆心是 50% + 95px）。
///
/// 鼠标停在上面的时候那一拍不算数（FlashHover）：不许它正好在眼皮底下消失。
///
/// 方案 B 的兜底入口也挂在这儿：启动时自动开的那个标页可能被浏览器拦掉、也可能被用户
/// 自己关掉，那时就在这条提示里摆一颗「打开 Web UI」—— 用户再点一下是新手势，
/// 一定不被弹窗拦截器吃掉。按钮只在**这条提示对应的地址还在**时出现
/// （notice_url_notice 与当前正文一致）：提示被别的动作改写之后它自动失效。
fn global_notice(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  match model.notice {
    None => @html.nothing
    Some(n) =>
      if n.text == "" {
        @html.nothing
      } else {
        let text_attrs = if n.hint == "" {
          mark("global-notice-text", ["shell", "notice", "text"])
        } else {
          mark("global-notice-text", ["shell", "notice", "text"]).title(n.hint)
        }
        let children : Array[@html.Html] = [
          @html.span(class="dsh-notice-text", attrs=text_attrs, n.text),
        ]
        let has_url = match model.notice_url {
          Some(_) => model.notice_url_notice == n.text
          None => false
        }
        // 动作失败那一类：右边挂一颗低调的「查看日志」（§32.1）。
        // 完整原文在这一次动作写的审计行里（audit.jsonl 的 message），这里只负责把人送过去。
        if !n.ok && n.audit {
          children.push(
            @html.button(
              class="dsh-btn",
              type_="button",
              attrs=mark("notice-open-logs", ["shell", "notice", "open-logs"]).title(
                "在审计日志里看这次失败的完整原因",
              ),
              on_click=emit(NoticeOpenLogs),
              [icon("text-box-outline"), @html.span("查看日志")],
            ),
          )
        }
        let has_button = n.ok && has_url
        if has_button {
          children.push(
            @html.button(
              class="dsh-btn",
              type_="button",
              attrs=mark("notice-open-web-ui", [
                "shell", "notice", "open-web-ui",
              ]).title(
                "再点一下就在新标签页打开带令牌的地址。手动点击是新手势，弹窗拦截器拦不住",
              ),
              on_click=emit(NoticeOpenUi),
              [icon("open-in-new"), @html.span("打开 Web UI")],
            ),
          )
        }
        // 成功用 toast 那副脸色，失败用提示条那副脸色；两者的外壳位置与层级是同一个，
        // 所以「成功自己走、失败常驻」只是计时上的差别，不靠第二套渲染点。
        let cls = if n.ok {
          if model.flash_fading {
            "dsh-toast fading"
          } else {
            "dsh-toast"
          }
        } else {
          "dsh-notice err dsh-global-notice"
        }
        @html.div(
          class=cls,
          attrs=mark("global-notice", ["shell", "notice"])
            .data_set("ok", if n.ok { "true" } else { "false" })
            .data_set(
              "fading",
              if model.flash_fading {
                "true"
              } else {
                "false"
              },
            )
            .role("status")
            .on_mouseenter(fn(_e) { emit(FlashHover(true)) })
            .on_mouseleave(fn(_e) { emit(FlashHover(false)) }),
          children,
        )
      }
  }
}

///|

///|
fn page_view(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  // 原来这里包了一层 try 当渲染兜底，编译器的 unused_try 把它判掉了：
  // MoonBit 的异常是类型化的，这些渲染函数没有 raise 签名就不会抛，catch 抓不到东西。
  // 与其留一层假的保险，不如把这层删掉、把「异常无处可逃」这件事写进 README（§110）。
  let body = match model.page {
    Overview => overview_view(model, emit)
    Maintenance => maintenance_view(model, emit)
    Logs => logs_view(model, emit)
    Settings => settings_view(model, emit)
    Trash => trash_view(model, emit)
    About => about_view(model, emit)
  }
  // 拖动的「移动 / 松开 / 取消」三件事挂在外壳这一层，不挂在条目或分组上。
  // 理由两条：
  //   ① 拖到列表之外再松手时，挂在分组上就收不到那一次抬起，拖动状态会一直挂着
  //      （那一拍再划过列表，落位线还会跟着走）。外壳包着整页，哪儿松开都冒泡上来。
  //   ② 指针移到条目之间的空隙、或者移出列表时，落点判定拿到「底下没有条目」，
  //      落位线随之收掉 —— 在空白处松手就是作废，与画面上看到的一致。
  // 只在**正在按下 / 拖动**时才挂（drag_id 非空）：一直挂着的话，每一次鼠标划过
  // 页面都会送一条消息进来重渲染一遍 —— 而那一拍什么都没发生。
  // 提示的位置与右侧覆盖层无关：它固定贴在视口底部居中，抽屉 / 侧栏开关时不动。
  // 让位那套（覆盖层开着就往左挪）实测下来是「提示会跟着抽屉滑」—— 那是病不是特性。
  let mut shell_attrs = @html.Attrs::build()
  if model.drag_id != "" {
    shell_attrs = shell_attrs
      .on_pointermove(fn(event) {
        emit(
          DragMove(
            event.get_client_x(),
            event.get_client_y(),
            event.get_buttons(),
          ),
        )
      })
      .on_pointerup(fn(_event) { emit(DragUp) })
      .on_pointercancel(fn(_event) { emit(DragCancel) })
  }
  // 拖动中滚了页面就作废：落点判定用的那份格子坐标是**视口坐标**，页面一滚就全对不上，
  // 再算下去会得到一个「看着对、落错格」的落点 —— 那比不作废还糟。
  // 挂在外壳上（不在分组上）：滚的是窗口，事件落在外壳这一层才收得到。
  // 只在拖动态存在时挂，与上面三条同一个理由：不拖的时候划过页面不该重渲染。
  if model.drag_active {
    shell_attrs = shell_attrs.on_scroll(fn(_event) { emit(DragCancel) })
  }
  // 窄屏覆盖层开着时 Esc 收掉它。挂在 shell 上而不是 document 上：
  // 打开时焦点已经进了第一个导航项，按键从那里冒泡上来，这一层收得到。
  if model.sidebar_overlay {
    shell_attrs = shell_attrs.on_keydown(fn(event) {
      if event.key() == "Escape" {
        emit(SidebarOverlayClose)
      } else {
        @cmd.none
      }
    })
  }
  @html.div(class="dsh-shell", attrs=shell_attrs, [
    // 遮罩节点一直在（宽屏不显示）：见 side_scrim
    side_scrim(model, emit),
    side_nav(model, emit),
    @html.div(class="dsh-workbench", [
      shell_topbar(model, emit),
      shell_narrowbar(model, emit),
      route_notice_bar(model),
      @html.main_(class="dsh-main", [body]),
    ]),
    // 全局提示挂在 shell 这一层、不在任何一页里面：位置与页面无关，
    // 切页也不会把它带走（§14.2）。六个页面共用这一个节点。
    global_notice(model, emit),
    // 通知历史侧栏（§36）：也挂在 shell 这一层 —— 打开时切页不该把它带走。
    notice_panel(model, emit),
    // 全局启动变量专窗（§94）：它从设置页打开，而设置页不渲染总览的 dialogs 列表，
    // 挂在 shell 才会出现（挂在 overview 里时探针永远 open:false）。
    if model.env_global_open {
      env_global_dialog(model, emit)
    } else {
      @html.nothing
    },
  ])
}
