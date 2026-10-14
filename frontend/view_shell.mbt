// 应用外壳：左侧导航三项 + 顶栏 + 内容区。
//
// 导航是状态切页（没有 URL 路由，刷新回到总览）。页脚「本机运行，仅限回环访问」在导航栏底部。
//
// 外壳没有走 md2 的 navigation_drawer / app_bar：那两个组件把 position: fixed、z-index、
// side 偏移写成了**内联样式**（v_navigation_drawer.mbt / v_app_bar.mbt），而这套外壳是
// 文档流里的 flex 两列（.dsh-shell）。内联样式没法从样式表压过，除非上 !important ——
// 那正是换栈决策里明确不做的。所以外壳自建，形状来自移植过来的那一层 CSS。

///|
fn nav_item(page : Page, current : Page, label : String, icon_name : String, emit : @cmd.Emit[Msg]) -> @html.Html {
  let active = page == current
  @html.button(
    class=if active { "dsh-nav-item active" } else { "dsh-nav-item" },
    type_="button",
    attrs=@html.Attrs::build()
      .data_set("name", "nav-" + nav_key(page))
      .aria_current(if active { "page" } else { "false" }),
    on_click=emit(Navigate(page)),
    [
      @html.span(class="dsh-nav-icon", [icon(icon_name, Default)]),
      @html.span(class="dsh-nav-label", label),
    ],
  )
}

///|
fn nav_key(page : Page) -> String {
  match page {
    Overview => "overview"
    Logs => "logs"
    About => "about"
  }
}

///|
fn side_nav(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  @html.aside(class="dsh-side", attrs=@html.Attrs::build().data_set("name", "side-nav"), [
    @html.div(class="dsh-brand", [
      @html.span(class="dsh-brand-icon", [icon("mdi-hub-outline", Small)]),
      @html.span(class="dsh-brand-title", "DSH 控制台"),
    ]),
    @html.nav(class="dsh-nav", [
      nav_item(Overview, model.page, "实例总览", "mdi-view-grid-outline", emit),
      nav_item(Logs, model.page, "日志", "mdi-text-box-outline", emit),
      nav_item(About, model.page, "关于", "mdi-shield-outline", emit),
    ]),
    @html.p(class="dsh-side-foot", [
      @html.i(class="dsh-side-dot", @html.nothing),
      @html.span("本机运行，仅限回环访问"),
    ]),
  ])
}

///|
/// 顶栏：标题 + 设置按钮（当前无行为）。
fn top_bar() -> @html.Html {
  @html.header(class="dsh-topbar", attrs=@html.Attrs::build().data_set("name", "top-bar"), [
    @html.span(class="dsh-topbar-spacer", @html.nothing),
    @html.button(
      class="dsh-settings",
      type_="button",
      attrs=@html.Attrs::build().data_set("name", "settings"),
      [icon("mdi-cog-outline", XSmall), @html.span("设置")],
    ),
  ])
}

///|
fn page_view(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let body = match model.page {
    Overview => overview_view(model, emit)
    Logs => logs_view(model, emit)
    About => about_view(model)
  }
  @html.div(class="dsh-shell", [
    side_nav(model, emit),
    @html.div(class="dsh-workbench", [
      top_bar(),
      @html.main_(class="dsh-main", [body]),
    ]),
  ])
}
