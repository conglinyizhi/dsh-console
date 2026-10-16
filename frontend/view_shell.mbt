// 应用外壳：左侧导航五项（实例总览 / 日志 / 设置 / 回收站 / 关于）+ 内容区。
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
    Trash => "trash"
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
      // 回收站挨着「关于」放：它是一条能真删东西的入口，摆在一排设置项后面不抢视线，
      // 也不跟「实例总览」那种常用项混在一起
      nav_item(Trash, model.page, "回收站", "delete-outline", emit),
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
/// 成功提示的 toast：出现约 4 秒、自己淡出（到期计时挂在哪见 app.mbt 的 flash_timer）。
///
/// 位置在 shell 这一层，所以五个页面是同一个位置（右下角，见 app.scss 的 .dsh-toast）；
/// 每条提示都得各自摆一次的话，「各页一致」这件事迟早会分叉。
///
/// **只管成功**：失败照旧留在它自己那一页不动（view_overview 的 action_notice /
/// view_settings 的 settings_feedback）—— 正常可以沉默，异常不能沉默。
/// 鼠标停在上面的时候那一拍不算数（FlashHover）：不许它正好在眼皮底下消失。
///
/// 方案 B 的兜底入口也挂在这儿：启动时自动开的那个标页可能被浏览器拦掉、也可能被用户
/// 自己关掉，那时就在这条提示里摆一颗「打开 Web UI」—— 用户再点一下是新手势，
/// 一定不被弹窗拦截器吃掉。按钮只在**这条提示对应的地址还在**时出现
/// （notice_url_notice 与当前文字一致）：提示被别的动作改写之后它自动失效。
fn flash_toast(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let (text, hint) = flash_text(model)
  if text == "" {
    return @html.nothing
  }
  let text_attrs = if hint == "" {
    mark("flash-toast-text", ["shell", "flash-toast", "text"])
  } else {
    mark("flash-toast-text", ["shell", "flash-toast", "text"]).title(hint)
  }
  let children : Array[@html.Html] = [
    @html.span(class="dsh-toast-text", attrs=text_attrs, text),
  ]
  let has_button = match model.notice_url {
    Some(_) => model.notice_url_notice == text
    None => false
  }
  if has_button {
    children.push(
      @html.button(
        class="dsh-btn",
        type_="button",
        attrs=mark("notice-open-web-ui", ["shell", "flash-toast", "open-web-ui"])
          .title("再点一下就在新标签页打开带令牌的地址 —— 手动点击是新手势，弹窗拦截器拦不住"),
        on_click=emit(NoticeOpenUi),
        [icon("open-in-new"), @html.span("打开 Web UI")],
      ),
    )
  }
  @html.div(
    class=if model.flash_fading { "dsh-toast fading" } else { "dsh-toast" },
    attrs=mark("flash-toast", ["shell", "flash-toast"])
      .data_set("ok", "true")
      .data_set("fading", if model.flash_fading { "true" } else { "false" })
      .role("status")
      .on_mouseenter(fn(_e) { emit(FlashHover(true)) })
      .on_mouseleave(fn(_e) { emit(FlashHover(false)) }),
    children,
  )
}

///|
/// 当前页面上正摆着的成功提示 →（正文, 悬停补充）。没有就给空串。
///
/// 一个函数收口，是因为有两处要问同一件事：toast 摆什么、以及 app.mbt 里那条
/// 「这条提示是新出现的吗」的判断（新出现才重新挂计时）。
fn flash_text(model : Model) -> (String, String) {
  // 设置页的成功回执走自己那条 settings_feedback；其余页面的动作回执都在 act_notice 上
  // （总览与回收站都有动作，两条路都得接上 —— 少接一条，那一页的成功就成了「什么都没发生」）
  if model.page is Settings {
    if model.settings_feedback_ok {
      (model.settings_feedback, "")
    } else {
      ("", "")
    }
  } else if model.page is Overview || model.page is Trash {
    if model.act_notice_ok {
      let hint = if model.act_notice_hint != "" &&
        model.act_notice_hint_for == model.act_notice {
        model.act_notice_hint
      } else {
        ""
      }
      (model.act_notice, hint)
    } else {
      ("", "")
    }
  } else {
    ("", "")
  }
}

///|
fn page_view(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let body = match model.page {
    Overview => overview_view(model, emit)
    Logs => logs_view(model, emit)
    Settings => settings_view(model, emit)
    Trash => trash_view(model, emit)
    About => about_view(model)
  }
  // 拖动的「移动 / 松开 / 取消」三件事挂在外壳这一层，不挂在条目或分组上。
  // 理由两条：
  //   ① 拖到列表之外再松手时，挂在分组上就收不到那一次抬起，拖动状态会一直挂着
  //      （那一拍再划过列表，落位线还会跟着走）。外壳包着整页，哪儿松开都冒泡上来。
  //   ② 指针移到条目之间的空隙、或者移出列表时，落点判定拿到「底下没有条目」，
  //      落位线随之收掉 —— 在空白处松手就是作废，与画面上看到的一致。
  // 只在**正在按下 / 拖动**时才挂（drag_id 非空）：一直挂着的话，每一次鼠标划过
  // 页面都会送一条消息进来重渲染一遍 —— 而那一拍什么都没发生。
  let mut shell_attrs = @html.Attrs::build()
  if model.drag_id != "" {
    shell_attrs = shell_attrs
      .on_pointermove(fn(event) {
        emit(DragMove(event.get_client_x(), event.get_client_y(), event.get_buttons()))
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
  @html.div(
    class="dsh-shell",
    attrs=shell_attrs,
    [
      side_nav(model, emit),
      @html.div(class="dsh-workbench", [
        route_notice_bar(model),
        @html.main_(class="dsh-main", [body]),
      ]),
      // toast 挂在 shell 这一层、不在任何一页里面：位置因此与页面无关（五个页面同一个角落）
      flash_toast(model, emit),
    ],
  )
}
