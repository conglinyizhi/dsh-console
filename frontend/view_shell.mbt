// 应用外壳：左侧导航四项 + 内容区。
//
// 导航既是状态切页也写地址（见 route.mbt）：刷新与前进/后退按地址复原页面。
// 页脚「本机运行，仅限回环访问」在导航栏底部。
// 顶部那条 .dsh-route-notice 只在地址认不出来、被回落时出现 —— 回落必须说清为什么，
// 不然「点进来发现不是自己要的那一页」就成了没法解释的怪事。
//
// 「设置」从顶栏搬到侧栏（这一轮）：顶栏当时只有那一个按钮，按钮一走顶栏就成了
// 一条 44px 的空带子，所以整条顶栏一起去掉，内容区直接顶到窗口上沿。
//
// 外壳自建，不套现成的抽屉/顶栏组件：以前试过 md2 的 navigation_drawer / app_bar，
// 那两个把 position: fixed、z-index、side 偏移写成了**内联样式**，而这套外壳是文档流里的
// flex 两列（.dsh-shell）—— 内联样式没法从样式表压过，除非上 !important。
// 形状全部来自 styles/app.scss，与 Vue 版逐条对齐。

///|
fn nav_item(page : Page, current : Page, label : String, icon_name : String, emit : @cmd.Emit[Msg]) -> @html.Html {
  let active = page == current
  @html.button(
    class=if active { "dsh-nav-item active" } else { "dsh-nav-item" },
    type_="button",
    attrs=mark("nav-" + nav_key(page), ["shell", "nav", nav_key(page)])
      .aria_current(if active { "page" } else { "false" }),
    on_click=emit(Navigate(page)),
    [
      @html.span(class="dsh-nav-icon", [icon(icon_name, size=16)]),
      @html.span(class="dsh-nav-label", label),
    ],
  )
}

///|
fn nav_key(page : Page) -> String {
  match page {
    Overview => "overview"
    Logs => "logs"
    Settings => "settings"
    About => "about"
  }
}

///|
fn side_nav(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  @html.aside(class="dsh-side", attrs=mark("side-nav", ["shell", "side-nav"]), [
    @html.div(class="dsh-brand", [
      @html.span(class="dsh-brand-icon", [icon("hub-outline", size=17)]),
      @html.span(class="dsh-brand-title", "DSH 控制台"),
    ]),
    @html.nav(class="dsh-nav", [
      nav_item(Overview, model.page, "实例总览", "view-grid-outline", emit),
      nav_item(Logs, model.page, "日志", "text-box-outline", emit),
      nav_item(Settings, model.page, "设置", "cog-outline", emit),
      nav_item(About, model.page, "关于", "shield-outline", emit),
    ]),
    @html.p(class="dsh-side-foot", [
      @html.i(class="dsh-side-dot", @html.nothing),
      @html.span("本机运行，仅限回环访问"),
    ]),
  ])
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
fn page_view(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let body = match model.page {
    Overview => overview_view(model, emit)
    Logs => logs_view(model, emit)
    Settings => settings_view(model, emit)
    About => about_view(model)
  }
  @html.div(class="dsh-shell", [
    side_nav(model, emit),
    @html.div(class="dsh-workbench", [
      route_notice_bar(model),
      @html.main_(class="dsh-main", [body]),
    ]),
  ])
}
