// 实例总览页（第七轮：卡片变条目 + 右侧覆盖式详情抽屉）。
//
// 卡片上**只剩三样**，各占一处：左上 profile 名、右上端口（只在运行中那一条）、
// 下方一行备注（有才进 DOM）。图标在左边，那颗实心状态圆挂在**图标**右上角 ——
// 它与条目右上角的端口是两处位置，别混。
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
    IsolateHome => "isolate-home"
    DeisolateHome => "deisolate-home"
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
  // §26.1：已停止不显示灯。这一档**一个节点都不产出** —— 不是画一颗透明的圆，
  // 那仍然占着位置、读屏也还会念它；状态词「已停止」照旧在第一行（颜色不是唯一信号）。
  if !light_shown(row.light) {
    return @html.nothing
  }
  @html.span(
    class="dsh-dot " + light_class(row.light),
    attrs=mark("status-light", ["overview", "card", row.id, "light"])
      .data_set("state", light_key(row.light))
      .role("img")
      // 悬停给两样：先是那句人话，再是技术依据（哪一条握手应答命中）。
      // 档位标签不再重挂一遍：那会变成「运行中：运行中：…」（实测踩过）。
      .aria_label(light_label(row.light))
      .title(if row.light_basis == "" {
        row.light_reason
      } else {
        row.light_reason + "\n" + row.light_basis
      }),
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
fn card_attrs(row : Row, model : Model, emit : @cmd.Emit[Msg]) -> @html.Attrs {
  let attrs = mark("instance-card", ["overview", "card", row.id])
    .data_set("instance", row.name)
    // 行 id 也写进 DOM：指针拖动的落点判定要按它认行（见 dom.mbt 的 js_drop_target）。
    // 与卡片自己的 DOM id 分开：那个是给焦点用的短串（dsh-card-…），这个要与 row.id 一字不差。
    .data_set("row", row.id)
    .data_set("status", status_name(row.status))
    .data_set("light", light_key(row.light))
    // 「这一行有没有地址可复制」（design/ops-maintenance-jobs.md §13.1）。
    // 抽屉里那颗按钮的置灰、以及复制动作自己那一道，都从同一格走。
    .data_set("copy-url", if row.url_copyable { "true" } else { "false" })
    .role("button")
    // 正被拖的那一条：从 Tab 序列里摘掉。它在原地只剩一个空位（画成了占位块），
    // 焦点落在一个看不见的节点上，键盘用户就找不着自己在哪儿了。
    .tabindex(if model.drag_active && model.drag_id == row.id { -1 } else { 0 })
    .aria_haspopup("dialog")
    .aria_label(row.name + "，点开看读数与控制（" + light_label(row.light) + "）")
    .on_click(fn(_event) { emit(DrawerOpen(row.id)) })
    // 指针按下只是**记住起点**：位移过阈值才算拖动（判在 update_inner 的 DragDown）。
    // 这里**不 preventDefault**：掐掉默认行为会把随后的 click 一起掐掉，
    // 而点整张卡是打开抽屉的唯一入口 —— 拖动与点击必须共存。
    .on_pointerdown(fn(event) {
      emit(DragDown(row.id, event.get_client_x(), event.get_client_y()))
    })
    .on_keydown(fn(event) {
      let key = event.key()
      if key == "Enter" || key == " " {
        emit(DrawerOpen(row.id))
      } else {
        @cmd.none
      }
    })
    // 换位挂在**抬起**这一拍，不挂按下：
    //   ① 按一次键浏览器会送好几个键盘事件（按下 / 自动重复 / 抬起），
    //      挂在按下上会换两次位 —— 一次按键换两格，不是使用者要的；
    //   ② 抬起还顺手给了「按错了就按住不放、再移开」这个反悔的余地。
    // 键位仍旧是 Ctrl+方向键：裸方向键要留给页面滚动与焦点移动，抢过来键盘用户在列表里走不动路。
    .on_keyup(fn(event) {
      let key = event.key()
      if (key == "ArrowUp" || key == "ArrowDown") && event.ctrl_key() {
        emit(ReorderKey(row.id, if key == "ArrowUp" { -1 } else { 1 }))
      } else {
        @cmd.none
      }
    })
  attrs
}

///|
/// 条目左上角那个名字：**只要 profile 名**，端口另起一个节点摆到右上角。
///
/// 运行中那一条的 row.name 是「profile 名 : 端口」拼成的一串（state.mbt 拼的，
/// 抽屉标题、卡片 aria-label、data-instance 都用它）——卡片这里只取前半截，
/// 把端口让给右上角那一格。已停止的行走不到这一步：它本来就没有端口。
fn card_name_text(row : Row) -> String {
  match row.port_value {
    Some(port) => {
      let suffix = " :" + port.to_string()
      let n = row.name.length()
      let m = suffix.length()
      // 只在这个尾巴真在时裁：读数里名字与端口对不上时原样显示，不硬裁出一个半截名字
      if n > m && row.name[n - m:] == suffix[:] {
        row.name[0:n - m].to_owned()
      } else {
        row.name
      }
    }
    None => row.name
  }
}

///|
/// 条目**第一行右侧**那一格：这只实例正在监听的端口号，前面带一个「端口：」标签。
///
/// 与状态灯不是一处位置：灯在图标右上角（.dsh-dot，挂在 .dsh-tile-slot 里），
/// 这一格在第一行的右端（中间的名字把它顶过去）。
///
/// **判据是「这一行知不知道端口」，不是「灯是不是绿的」**：故障那一档里
/// 「端口在听、签名不通」正是最该一眼看到「它占着哪个端口」的时候，
/// 拿颜色当开关会恰好把它藏起来。没有端口就不产出这个节点 ——
/// 与第二行同一口径：没有就是没有，不摆一个空位。标签挂在这个节点**里面**：
/// 没有端口时连标签一起不产出，不会剩一个「端口：」孤零零挂在右端。
///
/// 标签是 label（.dsh-card-port-label，比数字淡一档，颜色见 app.scss），
/// 数字才是内容。两者同在一个等宽字行里，中间不加空白 —— 这一格的 DOM 文本
/// 读出来就是「端口：3080」，探针取到的也是这一串。
fn card_port(row : Row, port : Int) -> @html.Html {
  @html.span(
    class="dsh-card-port",
    attrs=mark("card-port", ["overview", "card", row.id, "port"]),
    [
      @html.span(class="dsh-card-port-label", "端口："),
      @html.text(port.to_string()),
    ],
  )
}

///|
/// 一张实例条目：**图标在左、竖跨两行**；右边两行 ——
/// 第一行是 profile 名 + 端口号（知道端口才有），第二行是备注，没有备注就写「上次启动」。
///
/// 两行的行高加起来正好等于图标那一块的高度（22 + 2 + 16 = 40），所以
/// **有没有第二行，条目的高度都是 70px**（14 + 1 + 40 + 1 + 14），
/// 与第七轮「没有备注的条目」逐像素一致 —— 响应式列数就是从这个高度推出来的。
/// 只有一行的时候整块靠 justify-content: center 居中，名字的基线也跟着落在原处。
fn instance_card(row : Row, model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let tile_class = match row.tone {
    Accent => "dsh-tile accent"
    Violet => "dsh-tile violet"
  }
  // 一只 profile 就是一份配置：不管在跑还是停着，图标都是那份文档。
  // 状态由灯与状态词说（颜色 + 文字两通道），不再让图标兼职表达运行状态 ——
  // 之前「跑着的」用 open-in-new、「停着的」用拼图块，两者都不像一份配置。
  let tile_icon = "file-document-outline"
  // 第一行：名字占满余下的宽度，把端口顶到右端
  let head : Array[@html.Html] = [
    @html.span(
      class="dsh-name",
      attrs=mark("card-name", ["overview", "card", row.id, "name"]).title(
        row.name + "（" + light_label(row.light) + "）",
      ),
      card_name_text(row),
    ),
  ]
  // 状态词：颜色之外的第二条通道（design/design-fixes.md 第 1 条），但**故障那一档不上卡**。
  // 「上次启动失败」五个字会挤掉名字（headless 被截成「hea…」），而它要说的其实是
  // 「点开看」——红灯 + 卡上悬停 + 抽屉里那句说都还在，文字通道没断（§43）。
  if row.light is LightFault {
    ()
  } else {
    head.push(
      @html.span(
        class="dsh-dot-state " + light_key(row.light),
        attrs=mark("card-state", ["overview", "card", row.id, "state"])
          .data_set("state", light_key(row.light))
          .title(light_label(row.light) + "：" + row.light_reason),
        light_label(row.light),
      ),
    )
  }
  // 小金标紧跟在名字后面（隔离那一档才有节点）：它是金边之外的第二信号
  match row.home_kind {
    "isolated" => head.push(card_home_badge(row))
    _ => ()
  }
  // 蓝标：命令行型（bundles 里没有 dsh-web-app）。这种 profile 没有网页入口，
  // 起不成常驻实例 —— 在卡上先说出来，省得用户点「启动」再看报错（§41）。
  if row.cli_only {
    head.push(card_cli_badge(row))
  }
  match row.port_value {
    Some(port) => head.push(card_port(row, port))
    None => ()
  }
  let lines : Array[@html.Html] = [@html.div(class="dsh-case-head", head)]
  // 第二行只在这一行真有内容时才多一个节点：两条都没有时 DOM 逐节点与从前一致
  match card_second_line(row) {
    Some(node) => lines.push(node)
    None => ()
  }
  @html.article(
    id=card_id(row.id),
    class=card_class(row, model),
    attrs=card_attrs(row, model, emit),
    [
      @html.span(class="dsh-tile-slot", [
        @html.span(class=tile_class, [icon(tile_icon, size=20)]),
        status_light(row),
      ]),
      @html.div(class="dsh-case-body", lines),
    ],
  )
}


///|
/// 一组里的一条：卡片节点 + 它的行 id。
///
/// 为什么要把 id 与节点摆在一起：拖动预览要按 id 找到「哪一条该插到哪儿」，
/// 而 @html.Html 是不透明的 —— 想从节点里反查行 id 只能去翻 DOM，
/// 那是把渲染期该知道的事推给浏览器。并排存着，查找就是一次数组遍历。
priv struct DragItem {
  id : String
  node : @html.Html
}

///|
/// 被拖的那一条现在排在第几格（0 起）：**按模型里的数**，不按 DOM 顺序。
///
/// 摆格子那一步（dom.mbt 的 js_grid_cells）拿的就是这个数，它也是落点；
/// 这里只是把它变成「第几位」好播报。
fn drag_position(model : Model) -> Int {
  if model.drag_at_index >= 0 {
    model.drag_at_index + 1
  } else {
    model.drag_from + 1
  }
}


///|
/// 占位块：**它就是这块将来真正会占的那一格**。
///
/// 形状与真条目同款（宽高、圆角、内边距、图标位全部照 .dsh-case 走，见 app.scss 一节），
/// 内容用的是被拖的那一条自己 —— 一眼看出「是它要落到这儿」，不是另找一块灰。
/// 它照抄形状而不是照抄外观：虚线边 + 半透明底，一眼分得出「这是将要有的」；
/// 状态灯摘掉（灯说的是**现在**在不在跑，一块预览摆一颗灯是拿将来冒充现在）。
///
/// 静态信息，不是装饰：prefers-reduced-motion 下让位那一段过渡会撤掉，这一块留着。
fn drop_slot(row : Row, slot_index : Int) -> @html.Html {
  // slot_index 只写进 DOM 供验收探针对号（真正摆格子的是 js_grid_cells）
  @html.div(
    class="dsh-case dsh-drop-slot ghost-tile",
    // 两个 data 属性：
    //   slot-index 说它落在第几格（样式按它给 order —— **不用行内 style**：
    //     那一层按位置比对孩子，行内样式会被对齐到别的节点上，实测差一格）；
    //   slot-row 说「这一格将来是谁的」（验收探针按它把占位块与真条目对号，它不是行 id）。
    attrs=mark("drop-slot", ["overview", "drop-slot", row.id])
      .data_set("slot-index", slot_index.to_string())
      .data_set("slot-row", row.id)
      .aria_hidden("true"),
    [
      // 图标位：形状要占着，但里面什么都不画（真图标是这一条的标识，预览不该冒充它）
      @html.span(class="dsh-tile-slot", [@html.span(class="dsh-tile", @html.nothing)]),
      @html.div(class="dsh-case-body", [
        @html.div(class="dsh-case-head", [
          @html.span(class="dsh-name", card_name_text(row)),
        ]),
      ]),
    ],
  )
}

///|
/// 栅格末尾那块**不可见落点区**：只在拖动期间存在，绝对定位、不参与布局
/// （卡片位置一个像素都不动），让最后一格有一块自己的命中区域。
///
/// 位置与高度不在样式里写死：渲染之后由 dom.mbt 的 js_grid_cells 从可见的最后一行
/// 下沿量到栅格底（拖动期间栅格底会比最后一行低出一截）。判定上对应
/// 「指针在栅格下方 = 最后一格」那一条（见 js_drop_target）。
/// 它没有内容、没有底色，也不吃指针事件：是地标，不是可交互的东西。
fn drop_tail(group : String) -> @html.Html {
  @html.div(
    class="dsh-drop-tail",
    attrs=mark("drop-tail", ["overview", "drop-tail", group]).aria_hidden("true"),
    [@html.nothing],
  )
}

///|
/// 跟着指针走的虚影：手上那一条的**半透明副本**。
///
/// 位置由 dom.mbt 的 js_drag_ghost_move 每动一下就改一次（只改这一个节点的 transform，
/// 不回状态、不重渲染）；这里只负责把它画出来、给它定尺寸。
/// 对指针关掉（pointer-events: none）：它压在指针下面，不关的话每逢指针落到它身上，
/// 事件就换了目标，底下列表再也收不到移动。它也**不是** [data-row] 节点 ——
/// 落点判定要认的是真条目，多一个同名的会认错。
fn drag_ghost_view(row : Row, model : Model) -> @html.Html {
  @html.div(
    class="dsh-drag-ghost",
    style=[
      "width: " + model.drag_ghost_w.to_string() + "px",
      "height: " + model.drag_ghost_h.to_string() + "px",
    ],
    attrs=mark("drag-ghost", ["overview", "drag-ghost", row.id]).aria_hidden("true"),
    [
      @html.article(class="dsh-case ghost-card", [
        @html.span(class="dsh-tile-slot", [
          @html.span(
            class=if row.tone is Accent { "dsh-tile accent" } else { "dsh-tile violet" },
            @html.nothing,
          ),
          status_light(row),
        ]),
        @html.div(class="dsh-case-body", [
          @html.div(class="dsh-case-head", [
            @html.span(class="dsh-name", card_name_text(row)),
            match row.port_value {
              Some(port) => card_port(row, port)
              None => @html.nothing
            },
          ]),
          match card_second_line(row) {
            Some(node) => node
            None => @html.nothing
          },
        ]),
      ]),
    ],
  )
}

///|
/// 拖动 / 换位时给读屏播报的一句：**已移到第 N 位**。
///
/// 播报的是「将要落到第几位」而不是「现在在第几位」—— 拖动过程中使用者要判断的，
/// 正是「松手会落在哪儿」；说当前位次等于把问题重复一遍。
/// 换位落定之后模型里就没有拖动态了，这一段随之消失，读屏不再念（它是一句提醒，不是状态）。
fn drag_live_region(model : Model) -> @html.Html {
  if !model.drag_active || model.drag_at_index < 0 {
    return @html.nothing
  }
  let name = row_name(model, model.drag_id)
  let text = if name == "" {
    "已移到第 " + drag_position(model).to_string() + " 位"
  } else {
    name + " 已移到第 " + drag_position(model).to_string() + " 位"
  }
  @html.span(
    class="dsh-drag-live",
    attrs=mark("drag-live", ["overview", "drag-live"])
      .role("status")
      .aria_live("polite")
      .aria_atomic("true"),
    text,
  )
}
///|
/// 一组条目的容器（「当前运行的实例」/「已停止的实例」各一个）。
///
/// 这一层给的是**分组语义**：落点判定要知道指针底下那一条属于哪一组
/// （跨组不许放，两组不合并），以及拖动过程中整组的文字不许被选中。
///
/// 占位块也在这里插，**追加在末尾**。摆到第几格不靠这里的位置，也不靠节点上的属性 ——
/// 虚拟 DOM 那一层按**位置**比对孩子序列（中间插一个节点会让它把后面的节点错位对齐、
/// 属性也对到别的节点上），所以位置与属性都不可信。真正摆格子的是渲染之后那一步：
/// dom.mbt 的 js_grid_cells 直接给每一条写 grid-column / grid-row（同一个 k，
/// 也就是落点那一个数）。
///
/// 于是 n 个格子上是：占位块在第 k 格、被拖的那一条在最后一格（画成虚影看不见，
/// `visibility: hidden` 仍然占着那一格）、其余各条按原次序填满剩下的格子 ——
/// 与「真把它抽走、再插进第 k 格」的终局**逐格相同**：预览就是结果。
///
/// 指针的按下 / 移动 / 松开**不挂在这里**，挂在外壳（见 view_shell 的 page_view）：
/// 拖到列表之外再松手时，组这一层收不到抬起，拖动状态会一直挂着。
/// 外壳包着整页，指针在页面里哪儿都是一路冒泡上去的。
fn row_group(
  group : String,
  items : Array[DragItem],
  model : Model,
  _emit : @cmd.Emit[Msg],
) -> @html.Html {
  // 落点写在 DOM 上（data-drop-index）：它是「预览就是结果」这条验收的判据之一，
  // 探针照它比对「松手前占位块在第几格」与「松手后被拖那一条排在第几格」。
  // 也是这一条链路的自证：算法算出来的那个数，与画面上摆的那一格是同一个。
  let attrs = mark("row-group", ["overview", "rows", group])
    .data_set("group", group)
    .data_set("drop-index", model.drag_at_index.to_string())
  let kids : Array[@html.Html] = items.map(fn(item) { item.node })
  // 占位块里放的是被拖那一条自己的名字：一眼看出「是它要落到这儿」
  let dragged_row = match find_row(model.rows, model.drag_id) {
    Some(row) => row
    None => return @html.div(class="dsh-rows dsh-card-grid", attrs=attrs, kids)
  }
  let previewing = model.drag_active && model.drag_group == group && model.drag_at_index >= 0
  if previewing {
    // **占位块挂在末尾**，不插进中间：虚拟 DOM 那一层是按位置比对孩子序列的，
    // 中间插一个会让它把后面那些节点错位对齐 —— 实测「插在第 0 位的占位块」
    // 拿到了第 0 位那个节点的行内样式，占位块本身被挤到末尾（预览因此差一格）。
    // 挂末尾 = 只是多了一个孩子，前面一个节点都不动；摆到第几格由它自己的
    // data-slot-index 说（样式里按这个属性给 order，见 app.scss 那一段）。
    kids.push(drop_slot(dragged_row, model.drag_at_index))
    // 末尾那块不可见落点区也只在拖动期间挂：绝对定位，不参与布局。
    kids.push(drop_tail(group))
  }
  if model.drag_active {
    @html.div(class="dsh-rows dsh-card-grid dsh-drag-active", attrs=attrs, kids)
  } else {
    @html.div(class="dsh-rows dsh-card-grid", attrs=attrs, kids)
  }
}

///|
/// 条目的类名：常态是 `dsh-case`，正在被拖的那一条多一档 `drag-image`。
///
/// drag-image = 原件（手上那一条的替身：半透明地跟着指针走）**还在它原来的格子上**，
/// 只是看不见了 —— 位置留着，DOM 顺序就与拖动前一致，落点算法才有一份稳的坐标可用
/// （见 dom.mbt 的 js_drop_freeze）。原来那两档（dragging / drop-before / drop-after）
/// 随插入线一起去掉了：落点现在由占位块自己说，不再画在这条卡上。
fn card_class(row : Row, model : Model) -> String {
  // 被隔离的 profile 多一档：金色描边（样式在 app.scss 的「独立 home」那一段，
  // 它排在状态色相关规则之后、且选择器更重，状态怎么变都盖不掉它）。
  // 描边不是唯一信号：卡上还有一个「独立 home」小金标（见 card_home_badge）。
  let isolated = if row.home_kind == "isolated" { " dsh-case-home-isolated" } else { "" }
  if model.drag_active && model.drag_id == row.id {
    "dsh-case drag-image" + isolated
  } else {
    "dsh-case" + isolated
  }
}

///|
/// 卡上的「独立 home」小金标：金色描边之外的那一个信号（颜色不许当唯一信息）。
///
/// 只在 isolated 那一档产出节点（共用的卡 DOM 与从前逐节点一致）；悬停里说清这份 home
/// 在哪儿、为什么这一只被单独放在一个 home 里。
fn card_cli_badge(row : Row) -> @html.Html {
  @html.span(
    class="dsh-cli-badge",
    attrs=mark("card-cli-badge", ["overview", "card", row.id, "cli"])
      .data_set("cli-only", "true")
      .role("img")
      .aria_label("命令行型")
      .title(
        "命令行型：这只 profile 的 bundles 里没有 @deepseek-ai/dsh-web-app，" +
        "没有网页入口，起不成常驻实例。要用它就按它自己的用法在终端里跑一次" +
        "（dsh --profile <名字> …，具体参数看 --help）",
      ),
    [@html.text("命令行型")],
  )
}

///|
fn card_home_badge(row : Row) -> @html.Html {
  if row.home_kind != "isolated" {
    return @html.nothing
  }
  let where_text = if row.home_path == "" { "这只 profile 的独立 home" } else { row.home_path }
  @html.span(
    class="dsh-home-badge",
    attrs=mark("card-home-badge", ["overview", "card", row.id, "home"])
      .data_set("home-kind", row.home_kind)
      .role("img")
      .aria_label("独立 home")
      .title(
        "独立 home：这只 profile 的目录在 " + where_text +
        " 里，它起的实例用自己的 sessions / storages / logs，炸也炸不到别的 profile。" +
        "状态灯的颜色照旧只看运行状态，与这一道金边无关",
      ),
    [@html.text("独立 home")],
  )
}

///|
/// 条目第二行画什么：**有备注写备注**；没有备注才轮到「上次启动」；
/// 两个都没有就**不产出这一行**（空着，不写任何占位）。
///
/// 顺序不能反：备注是人写的，人写的东西优先 —— 机器读数不该把人写的话挤掉。
fn card_second_line(row : Row) -> @html.Html? {
  if row.user_note.length() > 0 {
    return Some(card_note(row))
  }
  let short = js_short_time(row.last_started)
  // 解析不出时刻（读数里是个不成形状的串）就当没有：写一行「上次启动 —」看着像有读数，
  // 其实没有 —— 那比空着更容易被误读。
  if short == "" {
    return None
  }
  Some(card_stamp(row, short))
}

///|
/// 条目第二行的**机器**那一档：上次启动时刻。
///
/// 与备注行同一处位置，但**不带左侧那道细线** —— 那道线是「这是人写的」的记号，
/// 时间是机器的读数，挂上去就是把两种东西说成一种。颜色也更淡一档（$text-dim）。
fn card_stamp(row : Row, short : String) -> @html.Html {
  @html.div(
    class="dsh-card-stamp",
    attrs=mark("card-started", ["overview", "card", row.id, "started"]).title(
      "上次启动：" + short +
      (if row.last_started_source == "" {
        ""
      } else {
        "\n（" + row.last_started_source + "）"
      }),
    ),
    [@html.span(class="dsh-card-stamp-text", "上次启动 " + short)],
  )
}

///|
/// 卡片底部的备注行：**人写的**一句话，与机器读数分开摆。
///
/// 左侧一道细竖线 + 比读数淡一档的颜色（见 app.scss 的 .dsh-card-note）——
/// 目标是一眼看出这是人写的，不是又一条读数。超长省略，完整内容在悬停里。
///
/// **不带「备注」二字**：这一行整个就是备注，标签只是把同一句话说两遍；
/// 抽屉里那一处上面有分组标题「备注」顶着，更不需要这一标。竖线留着 ——
/// 那是「这是人写的」的记号。
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
    [@html.span(class="dsh-card-note-text", row.user_note)],
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
/// 「宿主版本」那一格的值（§30.3）：**只放版本号**。
/// 读数里的值带着一个括注（（入口包）/（本机已安装）/（本地源码）…），那是来源的说法，
/// 摆进正文只会把这一格撑满、还要省略号；它和包目录一起进悬停（见 row.version_hint）。
fn version_value(row : Row) -> String {
  // 按「（」切一刀，取前一段：读数里的值都是「版本号（来源说法）」这个形状，
  // 没有括注时切开就只有一段，原样返回。
  let mut head = row.version
  for part in row.version.split("（") {
    head = part.to_owned()
    break
  }
  if head == "" {
    row.version
  } else {
    head
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
  elem_id? : String = "",
) -> @html.Html {
  drawer_button_hint(row, key, icon_name, label, danger, disabled, "", emit, elem_id~)
}

///|
/// 同上，另外挂一句悬停（「为什么这颗是灰的 / 悬停说清那件事」用）。
fn drawer_button_hint(
  row : Row,
  key : ActionKey,
  icon_name : String,
  label : String,
  danger : Bool,
  disabled : Bool,
  hint : String,
  emit : @cmd.Emit[Msg],
  elem_id? : String = "",
) -> @html.Html {
  let name = action_name(key)
  let mut attrs = mark(
    "drawer-" + name,
    ["overview", "drawer", row.id, "action", name],
  ).data_set("action", name)
  if hint != "" {
    attrs = attrs.title(hint)
  }
  // 有的按钮要能被 focus 点名（§30.1：关掉对话框之后焦点回这几颗）；
  // 没给 elem_id 的按钮一个字节都不多
  if elem_id != "" {
    attrs = attrs.id(elem_id)
  }
  @html.button(
    class=if danger { "dsh-btn danger" } else { "dsh-btn" },
    type_="button",
    disabled=disabled,
    attrs~,
    on_click=emit(RowAction(row.id, key)),
    [icon(icon_name), @html.span(label)],
  )
}

///|
/// 抽屉里那颗「删除」：Shift 语义（design/ops-maintenance-jobs.md §13.2）。
///
/// 三件事凑在一起，缺一条就不成立：
///   1. 两个标签都进 DOM（「删除」/「彻底删除」），CSS 按 [data-mode] 与 body[data-shift] 换字；
///   2. data-mode 由**后端读数**定：回收站关着（deleteToTrash=false）时始终 hard，
///      不管按没按 Shift；读不到设置也按 hard（那时删除就是要彻底删）；
///   3. 点下去那一刻把模式读出来一起发（DeleteOpen 的第三格）—— 确认框与请求都照它走。
///
/// 悬停两句：回收站开着时说「按住 Shift 是彻底删除」，关着时说「回收站没开，删除就是彻底删除」。
fn drawer_delete_button(row : Row, model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let hard_default = delete_to_trash_of(model) != Some(true)
  let hint = if hard_default {
    "回收站没开，删除就是彻底删除（删完无法恢复）"
  } else {
    "按住 Shift 是彻底删除，不进回收站"
  }
  @html.button(
    class="dsh-btn danger dsh-delete",
    type_="button",
    disabled=row.busy,
    // 模式在**这一拍**读（Attrs.on_click 挂的是 DOM 监听器，同步调用）：
    // Shift 是文档级标记，不进 model，也没法在渲染期读到一个「此刻」的值。
    attrs=mark("drawer-delete", ["overview", "drawer", row.id, "action", "delete"])
      .data_set("action", "delete")
      .data_set("mode", if hard_default { "hard" } else { "soft" })
      .title(hint)
      .id(drawer_delete_id())
      // 关框之后焦点回这一颗（§30.1）：抽屉不再因为开确认框而收起
      .on_click(fn(_event) {
        emit(DeleteOpen(row.id, drawer_delete_id(), delete_mode_now(model)))
      }),
    [
      icon("delete-outline"),
      // 两段标签都在 DOM 里，显示哪一段由 CSS 按标记决定（不走状态回环）
      @html.span(class="dsh-delete-soft", "删除"),
      @html.span(class="dsh-delete-hard", "彻底删除"),
    ],
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
  // 命令行型（§41）：没有网页入口，点了必然失败。按钮置灰但**仍可点** ——
  // 点它弹一句说明（禁用按钮收不到点击，也就没法解释为什么不让点）。
  if row.cli_only {
    return @html.button(
      class="dsh-btn is-inert" + tone,
      type_="button",
      attrs=mark("drawer-start-cli", ["overview", "drawer", row.id, "action", "start-cli"])
        .aria_disabled("true")
        .title("命令行型 profile，起不成常驻实例；点一下看怎么用"),
      on_click=emit(CliHelpOpen(row.id)),
      [icon("play", size=13), @html.span("启动")],
    )
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
/// 「打开 Web UI」拆成两段（design/design-fixes.md §29.3）：
///   主段：照旧开带令牌的地址（RowAction OpenUi；没有令牌时给那句提示）；
///   右段 chevron：约 28px、与主段同高共用边框，点开一份只有「强制启动」的菜单。
///
/// 菜单项就是原来的「硬开裸地址」：这一枪要在 DOM 监听器里**同步**打
/// （window.open 只有在手势的同一个栈里才不被拦，见 start_click 那段），
/// 打完顺手收菜单 —— 两件事同一拍发出去，回执照旧走 HardOpenDone。
///
/// 焦点：展开落进菜单项（键盘 Enter 就是「强制启动」），收起回 chevron；
/// 菜单项一撤，焦点落在被卸载的节点上会掉到 body。
fn drawer_open_ui_split(row : Row, model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let tone = match row.tone {
    Accent => " accent"
    Violet => " violet"
  }
  let open = model.split_menu_open
  let main_attrs = mark("drawer-open-web-ui", [
    "overview", "drawer", row.id, "action", "open-ui",
  ])
    .data_set("action", "open-ui")
    .title(
      open_ui_hint(row) +
      "；按住 Alt，或点右边的菜单：不管有没有 key，直接开裸地址（可能用不了）",
    )
  let toggle_attrs = mark("drawer-open-ui-menu", [
    "overview", "drawer", row.id, "action", "open-ui-menu",
  ])
    .data_set("action", "open-ui-menu")
    .data_set("state", if open { "open" } else { "closed" })
    .aria_haspopup("menu")
    .aria_expanded(if open { "true" } else { "false" })
    .aria_label("打开 Web UI 的其它方式")
    .title("打开 Web UI 的其它方式")
  let children : Array[@html.Html] = [
    @html.button(
      class="dsh-btn primary dsh-open-ui dsh-split-main" + tone,
      type_="button",
      attrs=main_attrs,
      on_click=emit(RowAction(row.id, OpenUi)),
      [icon("open-in-new"), @html.span("打开 Web UI")],
    ),
    @html.button(
      id=split_menu_btn_id(row.id),
      class="dsh-split-toggle",
      type_="button",
      attrs=toggle_attrs,
      on_click=emit(SplitMenuToggle),
      [icon("chevron-down", size=14)],
    ),
  ]
  if open {
    children.push(
      @html.div(
        class="dsh-split-menu",
        attrs=mark("drawer-open-ui-menu-list", ["overview", "drawer", row.id, "menu"])
          .role("menu")
          .aria_label("打开 Web UI 的其它方式"),
        [
          @html.button(
            id=split_menu_item_id(row.id),
            class="dsh-menu-item",
            type_="button",
            attrs=mark("drawer-open-ui-force", [
              "overview", "drawer", row.id, "action", "open-ui-force",
            ])
              .data_set("action", "open-ui-force")
              .role("menuitem")
              .title("不管有没有 key，直接在新标签页打开裸地址；服务端没握手，可能用不了")
              .on_click(fn(_event) {
                // 两件事同一拍：开裸地址（同步，手势栈里）、收菜单（焦点回 chevron）
                @cmd.batch([
                  emit(HardOpenDone(row.id, row.url, js_open_url(row.url))),
                  emit(SplitMenuClose),
                ])
              }),
            [icon("open-in-new", size=14), @html.span("强制启动")],
          ),
        ],
      ),
    )
    // 点外部关闭：一层透明的整屏垫片，与抽屉遮罩同一套做法（rabbita 的 on_click
    // 收不到 target，判不了「点在菜单外面」）。它在菜单下面一层，点菜单不会误触。
    children.push(
      @html.div(
        class="dsh-split-scrim",
        attrs=mark("drawer-open-ui-scrim", ["overview", "drawer", row.id, "menu", "scrim"]),
        on_click=emit(SplitMenuClose),
        @html.nothing,
      ),
    )
  }
  @html.div(
    class="dsh-split" + tone,
    attrs=mark("drawer-open-ui-split", [
      "overview", "drawer", row.id, "action", "open-ui-split",
    ]).data_set("open", if open { "true" } else { "false" }),
    children,
  )
}

// ── 配置历史（design/ops-maintenance-jobs.md §16.4）──────────────

///|
/// 快照那一行的时间：本地短格式（10-19 15:04）。读不出来写「—」，不编一个时刻。
fn snapshot_time_text(snap : SnapshotFact) -> String {
  match js_short_time(snap.at) {
    "" => "—"
    short => short
  }
}

///|
/// 快照那一行的「N 个文件 · X KB」。体积换算与回收站条目同一套（trash_size_text）。
fn snapshot_size_text(snap : SnapshotFact) -> String {
  snap.files.to_string() + " 个文件 · " + trash_size_text(Some(snap.bytes))
}

///|
/// 快照原因那一格：空串（只有 meta.json 读不出来时才会）写「没有写原因」，
/// 不拿「手动快照」冒充一个当时没记下来的原因。
fn snapshot_reason_text(snap : SnapshotFact) -> String {
  if snap.reason == "" {
    "没有写原因"
  } else {
    snap.reason
  }
}

///|
/// 快照那一行的悬停：完整原因与拍下来的时刻都在这里（正文里过长的原因会被省略号收掉）。
fn snapshot_row_hint(snap : SnapshotFact) -> String {
  let when = if snap.at == "" { "读不到时刻" } else { snap.at }
  "拍下来的时刻：" + when + "；原因：" + snapshot_reason_text(snap) + "；快照 id：" + snap.id +
  "；这一份里存了 " + snapshot_size_text(snap) + "。还原会用它的三个文件覆盖现在的内容"
}

///|
/// 在列表里找一份快照。找不到给 None（行被重读之后对不上了就什么都不做）。
fn find_snapshot(snaps : Array[SnapshotFact], id : String) -> SnapshotFact? {
  for snap in snaps {
    if snap.id == id {
      return Some(snap)
    }
  }
  None
}

///|
/// 抽屉「配置历史」那一组：创建快照按钮 + 快照列表 + 空态。
///
/// 空态只在**真读到空**时出现。读数里根本没有 snapshots 这一项时（旧后端）
/// 换成一句「这一版读数里没有配置快照」，与「还没拍过」分开说 ——
/// 把「读不到」写成「没有」，正是这套界面一直要避开的那件事。
fn snapshot_history(
  row : Row,
  model : Model,
  emit : @cmd.Emit[Msg],
  lead? : Array[@html.Html] = [],
) -> @html.Html {
  let busy = row.busy
  let creatable = row.profile_name is Some(_) && !busy
  // lead：「配置 home」那颗按钮与「创建快照」并排 —— 这两件事都属于「给这一份配置做点什么」，
  // 各自单独占一行会让「配置」这一组变成一串长度不一的短行（§38）。
  let lead_items : Array[@html.Html] = []
  for item in lead {
    lead_items.push(item)
  }
  let items : Array[@html.Html] = [
    @html.div(
      class="dsh-snapshot-create-line",
      attrs=mark("drawer-snapshot-create-line", ["overview", "drawer", row.id, "snapshot", "create"]),
      lead_items + [
        @html.button(
          class="dsh-btn",
          type_="button",
          disabled=!creatable,
          attrs=mark("drawer-snapshot-create", [
            "overview", "drawer", row.id, "action", "snapshot-create",
          ])
            .data_set("action", "snapshot-create")
            .title(
              "把 package.json、cordis.patch.yml、pnpm-workspace.yaml 拍成一张快照（有才存），" +
              "保留最近 20 份；这只 profile 有实例在跑时不让动配置",
            ),
          on_click=emit(SnapshotCreate(row.id)),
          [icon("camera-outline"), @html.span("创建快照")],
        ),
      ],
    ),
  ]
  if row.snapshots.length() == 0 {
    // 空态只留三个字：这一组里已经有一颗「创建快照」按钮，长句子只是把一组按钮隔断。
    // 完整说明进悬停（「动配置之前先拍一张，出了问题能还原」也在那儿）。
    let old_backend = row.snapshots_source == "这一版读数里没有「配置快照」这一项"
    let text = if old_backend { "这一版读数里没有配置快照，暂时拍不了也还原不了。" } else { "还没有快照" }
    items.push(
      @html.p(
        class="dsh-snapshot-empty",
        attrs=mark("drawer-snapshot-empty", ["overview", "drawer", row.id, "snapshot", "empty"])
          .title(
            if old_backend {
              row.snapshots_source
            } else {
              "还没有快照。动配置之前可以先拍一张，出了问题能还原。" + row.snapshots_source
            },
          ),
        text,
      ),
    )
  } else {
    for snap in row.snapshots {
      items.push(
        @html.div(
          class="dsh-snapshot-row",
          attrs=mark("drawer-snapshot-row", ["overview", "drawer", row.id, "snapshot", snap.id])
            .data_set("snapshot", snap.id)
            .title(snapshot_row_hint(snap)),
          [
            @html.span(
              class="dsh-snapshot-time",
              attrs=mark("drawer-snapshot-time", [
                "overview", "drawer", row.id, "snapshot", snap.id, "time",
              ]),
              snapshot_time_text(snap),
            ),
            @html.span(
              class="dsh-snapshot-reason",
              attrs=mark("drawer-snapshot-reason", [
                "overview", "drawer", row.id, "snapshot", snap.id, "reason",
              ]),
              snapshot_reason_text(snap),
            ),
            @html.span(
              class="dsh-snapshot-size",
              attrs=mark("drawer-snapshot-size", [
                "overview", "drawer", row.id, "snapshot", snap.id, "size",
              ]),
              snapshot_size_text(snap),
            ),
            @html.button(
              class="dsh-snapshot-restore",
              type_="button",
              disabled=busy,
              attrs=mark("drawer-snapshot-restore", [
                "overview", "drawer", row.id, "snapshot", snap.id, "restore",
              ])
                .data_set("snapshot", snap.id)
                .title("把这份快照里的三个文件写回去；还原之前会先给当前状态拍一张"),
              on_click=emit(SnapshotRestoreOpen(row.id, snap.id, card_id(row.id))),
              [@html.text("还原")],
            ),
          ],
        ),
      )
    }
  }
  @html.div(
    class="dsh-drawer-history",
    attrs=mark("drawer-snapshot-history", ["overview", "drawer", row.id, "snapshot", "history"])
      .data_set("count", row.snapshots.length().to_string())
      .title("配置快照：" + (if row.snapshots_source == "" { "读数里没给来源" } else { row.snapshots_source })),
    items,
  )
}

// ── 整体替换：用另一只配置替换这一只（design/ops-maintenance-jobs.md §17.3）──
//
// 三步走，同一个右侧栏里切换内容：
//   1. 选源（复用「选择配置」那套卡片，排除目标自己）
//   2. 选中之后就地出四段差异预览（插件清单 / 覆盖项 / 本地包 / 文件）
//   3. 底部按钮开确认框，确认之后应用，回执回来重读读数
// blockers 非空时按钮禁用并写明原因（那几条原话由后端给，前端不改写）。

///|
/// 抽屉「配置历史」组下面那一颗：打开右侧栏去选源。
fn promote_launcher(row : Row, emit : @cmd.Emit[Msg]) -> @html.Html {
  let usable = row.profile_name is Some(_) && !row.busy
  @html.div(
    class="dsh-promote-launcher",
    attrs=mark("drawer-promote-open-line", ["overview", "drawer", row.id, "promote", "open"]),
    [
      @html.button(
        id=promote_open_id(row.id),
        class="dsh-btn",
        type_="button",
        disabled=!usable,
        attrs=mark("drawer-promote-open", ["overview", "drawer", row.id, "action", "promote-open"])
          .data_set("action", "promote-open")
          .title(
            "把这一只的三份配置（package.json、cordis.patch.yml、pnpm-workspace.yaml）换成另一只的，" +
            "再把它没有的本地包搬过来；替换之前会先给这一只拍一张快照",
          ),
        on_click=emit(PromoteOpen(row.id)),
        [icon("swap-horizontal"), @html.span("用另一只配置替换这一只")],
      ),
    ],
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

///|
/// 替换确认框：文案照 design/ops-maintenance-jobs.md §17.4。
fn promote_confirm_dialog(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let (source, target) = match model.promote_preview {
    Some(preview) => (preview.source.name, preview.target.name)
    None => {
      let target = match find_row(model.rows, model.promote_row) {
        Some(row) =>
          match row.profile_name {
            Some(name) => name
            None => row.name
          }
        None => ""
      }
      (model.promote_source, target)
    }
  }
  let title = "用 " + source + " 的配置替换 " + target + "？"
  let message = "替换前会先给 " + target + " 拍一张快照，出问题能还原。"
  let card = @html.div(class="dsh-dialog-card", [
    @html.h2(
      class="dsh-dialog-title",
      attrs=mark("promote-dialog-title", ["dialog", "promote-confirm-dialog", "title"]),
      title,
    ),
    @html.p(
      class="dsh-dialog-message",
      attrs=mark("promote-dialog-message", ["dialog", "promote-confirm-dialog", "message"]),
      message,
    ),
    @html.div(class="dsh-dialog-foot", [
      @html.button(
        id=promote_confirm_ok_id(),
        class="dsh-dialog-btn primary",
        type_="button",
        attrs=mark("promote-dialog-ok", ["dialog", "promote-confirm-dialog", "ok"]),
        on_click=emit(PromoteConfirm),
        [@html.text("确认替换")],
      ),
      @html.button(
        class="dsh-dialog-btn",
        type_="button",
        attrs=mark("promote-dialog-cancel", ["dialog", "promote-confirm-dialog", "cancel"]),
        on_click=emit(PromoteConfirmCancel),
        [@html.text("取消")],
      ),
    ]),
  ])
  dialog(
    "promote-confirm-dialog",
    title,
    emit(PromoteConfirmCancel),
    emit.map(fn(key : @html.Keyboard) {
      if key.key() == "Escape" {
        PromoteConfirmCancel
      } else {
        Noop
      }
    }),
    card,
  )
}

///|
/// 「配置 home」那一格的三档文字（design/deep-home-isolation.md 第 5 节、
/// design/ops-maintenance-jobs.md §11.1）。
fn home_kind_text(kind : String) -> String {
  match kind {
    "trial" => "试跑"
    "isolated" => "独立"
    "shared" => "共用"
    _ => "读不到"
  }
}

///|
/// 抽屉「配置 home」那一格的值：独立（<路径>）/ 共用（<路径>）/ 读不到。
///
/// 路径同时挂在悬停里（完整不省略）：这一格的值太长时会被样式省略，
/// 而「到底是哪一个 home」是使用者最可能要抄下来的一件事。
fn home_field_value(row : Row) -> String {
  if row.home_kind == "" {
    "读不到"
  } else if row.home_path == "" {
    home_kind_text(row.home_kind)
  } else {
    home_kind_text(row.home_kind) + "（" + row.home_path + "）"
  }
}

///|
/// 「配置 home」那一格的悬停（§30.4 / §33.2）：先说清这一格是怎么认定的，再给路径与依据。
/// 三档：按实例的 home 认定 / 照 profile 读数（独立、共用、试跑）/ 认不出。
fn home_field_hint(row : Row) -> String {
  if row.home_kind == "" {
    if row.home_kind_source != "" {
      // 连实例的 home 都认不出：说清「两个来源都没有」，不拿默认值顶上
      "这只实例的 home 与 profile 都认不出来（" + row.home_kind_source + "）"
    } else {
      "这一版读数里没有「配置 home」这一项：独立还是共用，这一格不猜"
    }
  } else if row.home_from_instance {
    // §33.1：profile 不在控制台的 DSH_HOME 里，按它跑着的那份 home 算
    "按实例的 home 认定的：这只 profile 不在控制台的 DSH_HOME 里，所以按它跑着的那份 home 算" +
    "\n路径：" + row.home_path +
    (if row.home_kind_source == "" { "" } else { "\n依据：" + row.home_kind_source })
  } else {
    let kind_line = match row.home_kind {
      "isolated" => "独立：起实例用的是这份 home，与共用 DSH_HOME 分开"
      "shared" => "共用：与控制台自己的 DSH_HOME 是同一份"
      "trial" => "试跑：维护作业开的一次性 home，作业收尾时删掉"
      _ => "这一版读数里没有「配置 home」这一项：独立还是共用，这一格不猜"
    }
    let tail = if row.home_kind_source == "" {
      "（读数里没给判断依据）"
    } else {
      "｜依据：" + row.home_kind_source
    }
    kind_line + "\n路径：" + row.home_path + tail
  }
}

///|
/// 「运行 home」那一行（§30.4）：**只在在跑的实例自己的 home 与「配置 home」不同**时出现。
///
/// 两个 home 平时是同一份，并排摆两行只会让人以为它们不一样 —— 所以相同时一个节点都不产出。
/// 不同则必须说：那只实例实际读写的 home 与这一份 profile 的归属分开了。
fn run_home_field(row : Row) -> @html.Html? {
  if !(row.status is Running) || !home_is_path(row.home) {
    return None
  }
  // 配置 home 有值、且与实例 home 不同，才值得单独列一行（§33.1：
  // 按实例 home 认定的那一档两者是同一份，再摆一行就是自己打自己）
  if row.home_path == "" || same_home(row.home, row.home_path) {
    return None
  }
  let hint = if row.home_hint == "" {
    "这只实例进程自己用的 DSH_HOME，与「配置 home」那一份不同"
  } else {
    row.home_hint + "\n与上面「配置 home」不是同一份，所以单独列这一行"
  }
  Some(field("play", "run-home", row.id, "运行 home", row.home, hint))
}

///|
/// 抽屉「配置」组里与 home 有关的那几行（§30.4）：先是「配置 home」这一格，
/// 只有在跑的实例自己的 home 与它不同时，才多一行「运行 home」。
fn home_field_items(row : Row) -> Array[@html.Html] {
  let items : Array[@html.Html] = [
    field(
      "home-outline",
      "config-home",
      row.id,
      "配置 home",
      home_field_value(row),
      home_field_hint(row),
    ),
  ]
  match run_home_field(row) {
    Some(item) => items.push(item)
    None => ()
  }
  items
}

///|
/// 抽屉里那一组控制按钮 —— **今天行菜单里有的一个不少**。
///
/// 顺序照原来的菜单骨架：先主操作（打开 / 起停 / 重启），再「打开与复制」那一簇
/// （开新标签、两条复制、复制开发指令），然后是会改本机状态的（重命名 / 备注 / 派生 /
/// 归档 / 删除），最后是运维三项（查看日志 / 打开工作目录 / 编辑配置）。
fn drawer_controls(row : Row, model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let running = row.status is Running
  let busy = row.busy
  let main : Array[@html.Html] = []
  if running {
    // 「打开 Web UI」是一颗拆分按钮（§29.3）：主段 + 右侧 chevron 菜单。
    // 硬开裸地址从「一颗独立按钮 / 一个设置开关」收进了那份菜单（§29.2 删掉高级操作）。
    main.push(drawer_open_ui_split(row, model, emit))
    main.push(
      @html.button(
        class="dsh-btn",
        type_="button",
        disabled=busy,
        attrs=mark("drawer-stop", ["overview", "drawer", row.id, "action", "stop"])
          .data_set("action", "stop"),
        on_click=emit(RowAction(row.id, Toggle)),
        // 红色方块：停止键的通行形状。圆形在别处是状态灯，混用会读成「这里有个红点」
        [@html.span(class="dsh-stop-mark", [icon("stop", size=12)]), @html.span("停止")],
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
  // 「在新标签页打开」与「打开 Web UI」是同一件事（后者本来就在新标签页里开），
  // 摆两颗只是让这一组多一行按钮，所以删掉。ActionKey::Tab 与其处理分支保留，
  // 免得动到别处引用（现在没有别的入口发它）。
  // 「复制访问地址」：只有**真在跑、地址不是占位串**的行才是可点的（§13.1）。
  // 停用行的 url 是「已停用，无法访问」，点下去就是把一句占位话写进剪贴板。
  // 置灰 + 悬停说清；复制动作自己也拦一道（见 app.mbt 的 copy_url_action）。
  take.push(
    drawer_button_hint(
      row,
      CopyUrl,
      "link-variant",
      "复制访问地址",
      false,
      !row.url_copyable,
      if row.url_copyable {
        "复制这一行读数里的访问地址（" + row.url + "）"
      } else {
        "这只没在跑，没有可复制的访问地址"
      },
      emit,
    ),
  )
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
    drawer_button(
      row,
      Rename,
      "rename-outline",
      "重命名",
      false,
      busy,
      emit,
      elem_id=drawer_rename_id(),
    ),
    drawer_button(
      row,
      Note,
      "note-text-outline",
      "备注",
      false,
      busy,
      emit,
      elem_id=drawer_note_id(),
    ),
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
    mutate.push(drawer_delete_button(row, model, emit))
  }
  // 配置 home：共用 → 移到独立 home；独立 → 移回共用 home（先开确认框）。
  // 读数里没有这一项（home_kind 空串）时给一句「读不到」，不发一个不知道会把目录挪到哪儿的动作。
  // 正在移的那一行：按钮换成「正在移动…」并禁用（真实的目录移动，按下去没反应最容易被再点一次）。
  let moving = model.home_move_id == row.id
  let home_items : Array[@html.Html] = []
  if row.home_kind == "isolated" {
    home_items.push(
      @html.button(
        class="dsh-btn danger",
        type_="button",
        disabled=busy || moving,
        attrs=mark("drawer-deisolate-home", ["overview", "drawer", row.id, "action", "deisolate-home"])
          .data_set("action", "deisolate-home")
          .data_set("state", if moving { "moving" } else { "idle" })
          .title(
            "把这份 profile 的目录移回共用 home（" + row.home_path +
            "/profiles），这份额外 home 里剩下的会话与插件状态移到回收站，可以捞回来",
          ),
        on_click=emit(RowAction(row.id, DeisolateHome)),
        [
          icon("home-outline"),
          @html.span(if moving { "正在移动…" } else { "移回共用 home" }),
        ],
      ),
    )
  } else if row.home_kind == "trial" {
    // 试跑的一次性 home 归维护作业管：收尾（好用 / 不好用 / 停掉试跑 / 中止）时整份删掉。
    // 这里不给隔离 / 取消隔离 —— 那两条动作会把这份临时目录当成一只 profile 的固定家。
    home_items.push(
      @html.span(
        class="dsh-foot",
        attrs=mark("drawer-home-trial", ["overview", "drawer", row.id, "action", "home-trial"]),
        "试跑的一次性 home：作业收尾时删掉，这里不提供隔离与取消隔离",
      ),
    )
  } else if row.home_kind == "shared" {
    // 这只 profile 不在控制台的 DSH_HOME 里（按实例的 home 认出来的那一档，§33.1）：
    // 它的目录不归控制台管，移进 / 移回都动不了它 —— 按钮摆着但禁用，悬停说清为什么（§33.3）。
    let movable = !row.home_from_instance
    let hint = if movable {
      "把这份 profile 的目录移到控制台的 homes 根下（目录名就是 profile 名，缺省 ~/.dsh-homes），" +
      "以后用这只 profile 起的实例都在里面跑；共用 home 里那一份跟着搬走，不再留副本"
    } else {
      "这只 profile 不在控制台的 DSH_HOME 里，动不了它的 home"
    }
    home_items.push(
      @html.button(
        class="dsh-btn",
        type_="button",
        disabled=busy || moving || !movable,
        attrs=mark("drawer-isolate-home", ["overview", "drawer", row.id, "action", "isolate-home"])
          .data_set("action", "isolate-home")
          .data_set("state", if moving { "moving" } else { "idle" })
          .data_set("movable", if movable { "true" } else { "false" })
          .title(hint),
        on_click=emit(RowAction(row.id, IsolateHome)),
        [
          icon("folder-move-outline"),
          @html.span(if moving { "正在移动…" } else { "移到独立 home" }),
        ],
      ),
    )
  } else {
    // 真的认不出（连实例的 home 都没有）：不给动作，只说清这一版为什么没有这一项
    let why = if row.home_kind_source != "" {
      "这只实例的 home 与 profile 都认不出来，移进 / 移回都不发"
    } else {
      "这一版读数里没有「配置 home」，移进 / 移回都不发"
    }
    home_items.push(
      @html.span(
        class="dsh-foot",
        attrs=mark("drawer-home-missing", ["overview", "drawer", row.id, "action", "home-missing"]),
        why,
      ),
    )
  }
  // 运维三项：查看日志 / 打开工作目录 / 编辑配置（第三轮接上的那三项）
  let ops : Array[@html.Html] = [
    drawer_button(row, Logs, "text-box-outline", "查看日志", false, busy, emit),
    drawer_button(row, Dir, "folder-open-outline", "打开工作目录", false, busy, emit),
    drawer_button(row, Config, "tune", "编辑配置", false, busy, emit),
  ]
  // ── 五组里的后三组（§29.1）：操作 / 这只 profile / 配置 ──
  //
  // 组内只有行，不再有二级小标题：一组一个标题，标题下面是它能折的按钮行。
  // 组间间距是组内的两倍（样式在 app.scss 的 .dsh-drawer-body / .dsh-drawer-section）。
  let op_rows : Array[@html.Html] = [
    // 第一行：主操作（启动 / 停止 / 重启 / 打开 Web UI 拆分按钮）
    @html.div(class="dsh-drawer-btns", main),
    // 第二行：拿出去用（开新标签、两条复制、复制开发指令）
    @html.div(class="dsh-drawer-btns", take),
  ]
  let profile_rows : Array[@html.Html] = []
  if row.user_note.length() > 0 {
    profile_rows.push(card_note(row))
  }
  profile_rows.push(@html.div(class="dsh-drawer-btns", mutate))
  let config_rows : Array[@html.Html] = [
    // 配置 home 那一格读数留在这里：它是「以后起的实例落在哪儿」，与上面「实例自己在用的
    // DSH_HOME」不是同一件事，所以这一格跟着「配置」这一组走，不挤在读数里。
    @html.ul(class="dsh-fields is-single", home_field_items(row)),
    // 配置历史（§16.4）：动配置之前先拍一张、之后能还原。
    // home 那颗按钮并进同一行（lead），免得「配置」变成一串短行。
    snapshot_history(row, model, emit, lead=home_items),
    // 缺包仍可修（§40.2）：低调地摆在配置组里 —— 状态组不再摆那一行大提示
    repair_action(row, model, emit),
    promote_launcher(row, emit),
    // 查看与编辑（第三轮接上的那三项）
    @html.div(class="dsh-drawer-btns", ops),
  ]
  @html.fragment([
    drawer_section("操作", "action", op_rows),
    drawer_section("这只 profile", "profile", profile_rows),
    drawer_section("配置", "config", config_rows),
  ])
}

///|
/// 抽屉最上面那一块：**为什么是这个颜色**。
///
/// 契约里的硬要求（颜色不能是唯一信息）就落在这里：档位标签 + 一句人话。
/// 黄的两个成因因此分得开：一句说「端口在听，但不应答 dsh 的握手」，另一句说
/// 「这只 profile 缺 3 个包」—— 两句长得不一样，不会被一起读成「有点问题」。
///
/// **判据怎么来的收进悬停**（哪一条握手应答命中、探测回来的是什么、profile 那一侧
/// 怎么样）：正文一个字都不占。正文是给用这个工具的人看的，技术依据是给要核对
/// 这个结论的人看的 —— 两个读者不是同一个人。
fn drawer_state_block(row : Row, model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let mut why_attrs = mark("drawer-why", ["overview", "drawer", row.id, "state", "why"])
  let mut dot_attrs = mark("drawer-light", ["overview", "drawer", row.id, "state", "light"])
    .data_set("state", light_key(row.light))
    .role("img")
    .aria_label(light_label(row.light))
  if row.light_basis != "" {
    why_attrs = why_attrs.title(row.light_basis)
    dot_attrs = dot_attrs.title(row.light_basis)
  }
  // §26.1：已停止那一档不画灯 —— 抽屉里也不画（这一行的标签与那句为什么照旧在）
  let light_line : Array[@html.Html] = if light_shown(row.light) {
    [
      @html.span(class="dsh-dot " + light_class(row.light), attrs=dot_attrs, @html.nothing),
    ]
  } else {
    []
  }
  light_line.push(
    @html.span(
      class="dsh-drawer-light-label",
      attrs=mark("drawer-light-label", ["overview", "drawer", row.id, "state", "label"])
        .data_set("state", light_key(row.light)),
      light_label(row.light),
    ),
  )
  // 第二行：profile 健康（§29.1 并进「状态」）。只说人话：缺几个包、补丁文件在不在；
  // 「这句话是从哪读出来的」不在这里 —— 那是这一版怎么实现的，正文一个字不占。
  // **高度封顶**（第十二轮）：包名清单进悬停，自由文本那一类最多两行。
  drawer_section("状态", "state", [
    @html.div(class="dsh-drawer-light-line", light_line),
    @html.p(class="dsh-drawer-why", attrs=why_attrs, row.light_reason),
    problem_hint(
      "drawer-health",
      ["overview", "drawer", row.id, "health"],
      row.health_text,
      row.health_hint,
      row.health_free,
    ),
    // 缺包那一行与那颗按钮已经不在这里了（§40.2）：搬进「配置」组，降成一句低调的小字
    // + 一颗「安装」（见 repair_action）。状态组只留「还有没有别的毛病」。
  ])
}

///|
/// 「还缺 N 个包」+「安装」那一行（design/design-fixes.md §40.2 / §40.4）。
///
/// 缺包默认不报警（设置项 profile.ignoreMissingBundles），所以这一行从「状态」组
/// 搬到「配置」组，并降成一句低调的小字 + 一颗次要按钮：它不再是要人看一眼的警告，
/// 而是「想弄干净的时候」才去点的一个入口。缺包仍然可以装 —— 只是不喊。
///
/// 悬停写清在哪个目录跑哪条命令、日志落在哪儿（与 §39 同一句话）。
fn repair_action(row : Row, model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  if row.missing_count <= 0 || row.repair_command == "" || row.repair_home == "" {
    return @html.nothing
  }
  let repairing = model.repair_id == row.id
  // 目录名要用磁盘上的目录名（profile_name），不是卡片上那串「web :3080」——
  // 后者带端口，拼出来的路径不存在（§39 验收时撞到的那条）。
  let dir_name = match row.profile_name {
    Some(profile) => profile
    None => row.name
  }
  let dir = row.repair_home + "/profiles/" + dir_name
  let log_hint = "输出写进状态目录的 logs/repair-" + dir_name + "-<毫秒>.log"
  let label = if repairing { "正在安装…" } else { "安装" }
  let note = if repairing {
    "正在安装…"
  } else {
    "还缺 " + row.missing_count.to_string() + " 个包"
  }
  @html.div(class="dsh-drawer-btns dsh-missing-row", [
    @html.span(
      class="dsh-foot",
      attrs=mark("drawer-missing-note", ["overview", "drawer", row.id, "missing"]),
      note,
    ),
    @html.button(
      id=drawer_repair_id(),
      class="dsh-btn",
      type_="button",
      disabled=row.busy || repairing,
      attrs=mark("drawer-repair", ["overview", "drawer", row.id, "action", "repair"])
        .data_set("action", "repair-packages")
        .data_set("state", if repairing { "running" } else { "idle" })
        .title(
          "在 " + dir + " 里跑 " + row.repair_command +
          "；只动 node_modules，不改 package.json 与 cordis.patch.yml。" + log_hint,
        ),
      on_click=emit(RepairOpen(id=row.id, return_id=drawer_repair_id())),
      [icon("cube-outline", size=13), @html.span(label)],
    ),
  ])
}

///|
/// 抽屉里的一个组（§29.1）：小字标题 + 组内若干行。
///
/// 五个组用同一套画法，data-name 的尾巴是组自己的键（state / readings / action /
/// profile / config）—— 量「组间是组内的两倍」时按它取盒子，不看位置。
/// 组内只有行，没有二级小标题：标题一多，那五组又会被读成九组。
fn drawer_section(title : String, key : String, items : Array[@html.Html]) -> @html.Html {
  @html.div(
    class="dsh-drawer-section",
    attrs=mark("drawer-section", ["overview", "drawer", "section", key])
      .data_set("section", key),
    [@html.h3(class="dsh-drawer-section-title", title), @html.fragment(items)],
  )
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
///
/// closing = 这一只正在**收**（滑出那一段，节点还留着一小会儿，见 app.mbt 的 DrawerClose）：
/// 内容一字不差，只有 data-state 换成 closing —— 动画挂在那个属性上，判断也挂在它上面。
fn detail_drawer(
  row : Row,
  model : Model,
  emit : @cmd.Emit[Msg],
  closing : Bool,
) -> @html.Html {
  // 开 / 收两种状态。样式里 .dsh-drawer 与 .dsh-drawer-scrim 各挂一套 keyframes，
  // 收的那一只对指针关掉（半透明的面板不该再吃点击）
  let state = if closing { "closing" } else { "open" }
  // 读数只留**别处没说过的**那几格（§30.3）：
  //   宿主版本 / 访问地址 / 插件数量 / 最近改动。
  //   Profile 删掉：抽屉标题就是这个名字；DSH_HOME 删掉：「配置」那一组已经说了这只 profile
  //   的 home，两个 home 并排只会让人以为它们不一样。
  //   宿主版本只放版本号，来源与包目录（versionSource 里的那条 package.json 路径）进悬停。
  let field_items : Array[@html.Html] = [
    field(
      "label-outline",
      "dsh-version",
      row.id,
      "宿主版本",
      version_value(row),
      row.version_hint,
    ),
    field("link-variant", "url", row.id, "访问地址", row.url, url_hint(row)),
  ]
  // 同一个进程的其余监听端口（以前这里有一格「还听着 9230」）不再显示：
  // 那是 Unix 的「监听端口」说法，这个控制台要跨平台，没必要让用户读这一格。
  // 读数里仍然带着 alsoPorts，需要排查的人去 /api/local/instances 看得到。
  // 「配置 home」那一格不在这里：它跟着「配置」这一组走（§29.1）。
  field_items.push(
    field("puzzle-outline", "plugin-count", row.id, "插件数量", row.plugin_count, row.plugin_detail),
  )
  field_items.push(
    field("clock-outline", "mtime", row.id, "最近改动", mtime_value(row), row.mtime_hint),
  )
  let fields = @html.ul(class="dsh-fields", field_items)
  // 五组（§29.1）：状态（含 profile 健康）/ 读数 / 操作 / 这只 profile / 配置。
  // 后三组在 drawer_controls 里拼（它们要 model 与 emit）。
  let body : Array[@html.Html] = [
    drawer_state_block(row, model, emit),
    drawer_section("读数", "readings", [fields]),
    drawer_controls(row, model, emit),
  ]
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
      attrs=mark("drawer-scrim", ["overview", "drawer", row.id, "scrim"])
        .data_set("state", state),
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
        .data_set("state", state)
        .on_keydown(fn(event) {
          // Esc 先收菜单（§29.3：收起并把焦点还回 chevron），菜单没开才关抽屉。
          // 这里判 model 而不是在菜单上拦事件：键从菜单项冒泡上来，同一个处理器
          // 分得清「这一下该收谁」，也不必给两个节点各挂一套。
          if event.key() == "Escape" {
            if model.split_menu_open {
              emit(SplitMenuClose)
            } else {
              emit(DrawerClose)
            }
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
fn archived_row(row : Row, model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
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
        // 归档区这颗没有 Shift 语义（§13.2 说的是抽屉里那颗）：模式只按「回收站开没开」定
        on_click=emit(
          DeleteOpen(
            row.id,
            archive_trigger_id(row.id),
            delete_to_trash_of(model) != Some(true),
          ),
        ),
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
      body.push(archived_row(row, model, emit))
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

// ── 对话框 ─────────────────────────────────────────────────

///|
/// 删除确认框：打开时焦点落在确认键，Esc 关闭，关闭后焦点回到触发元素。
fn confirm_dialog(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let name = match find_row(model.rows, model.confirm_id) {
    Some(row) => row.name
    None => model.confirm_id
  }
  // 三处文案都照**点开那一刻记下来的模式**（§13.2）：确认框开着的时候设置被改了，
  // 这个框说的仍然是对那一次点击的判断。
  let hard = model.confirm_hard
  let title = (if hard { "彻底删除 " } else { "删除实例 " }) + name + "？"
  let mode = if hard { "删除后无法恢复。" } else { "删除后移入回收站，可以捞回来。" }
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
      attrs=mark("dialog-title", ["dialog", "confirm-dialog", "title"])
        .data_set("mode", if hard { "hard" } else { "soft" }),
      title,
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
        // 彻底删除时确认键用红色（.danger）：与「删除后无法恢复」那句一致，
        // 也让两个模式在按键上就分得开 —— 颜色之外还有文案与标题两处文字。
        class=if hard { "dsh-dialog-btn danger" } else { "dsh-dialog-btn primary" },
        type_="button",
        attrs=mark("dialog-ok", ["dialog", "confirm-dialog", "ok"])
          .data_set("mode", if hard { "hard" } else { "soft" }),
        on_click=emit(DeleteConfirm),
        [@html.text(if hard { "彻底删除" } else { "删除" })],
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
    title,
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
/// 补包确认框（design/design-fixes.md §39.1）：写 node_modules 是真动作，先问一句。
///
/// 文案把「在哪个目录、跑哪条命令、动的是什么」讲全：这三件事决定了这一下会不会把
/// 别的东西改坏 —— 答案是只补 node_modules，不改 package.json 与 cordis.patch.yml。
fn repair_confirm_dialog(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let (name, dir, command, count) = match find_row(model.rows, model.repair_confirm_id) {
    Some(row) =>
      (
        // 对话框里说名字，说的是磁盘上那一只（profile_name），不是卡片上带端口的显示名
        match row.profile_name {
          Some(profile) => profile
          None => row.name
        },
        if row.repair_home == "" {
          ""
        } else {
          let dir_name = match row.profile_name {
            Some(profile) => profile
            None => row.name
          }
          row.repair_home + "/profiles/" + dir_name
        },
        row.repair_command,
        row.missing_count,
      )
    None => (model.repair_confirm_id, "", "", 0)
  }
  let where_text = if dir == "" { "这只 profile 的目录" } else { dir }
  let cmd_text = if command == "" { "包管理器 install" } else { command }
  let message = "将在 " + where_text + " 里执行 " + cmd_text + "，只补 node_modules。" +
    "装完会重新读一次这只 profile。"
  let card = @html.div(class="dsh-dialog-card", [
    @html.h2(
      class="dsh-dialog-title",
      attrs=mark("repair-dialog-title", ["dialog", "repair-confirm-dialog", "title"]),
      "给 " + name + " 安装缺的包",
    ),
    @html.p(
      class="dsh-dialog-message",
      attrs=mark("repair-dialog-message", ["dialog", "repair-confirm-dialog", "message"])
        .title(message + "\n缺 " + count.to_string() + " 个包"),
      message,
    ),
    @html.div(class="dsh-dialog-foot", [
      @html.button(
        id=repair_dialog_ok_id(),
        class="dsh-dialog-btn primary",
        type_="button",
        attrs=mark("repair-dialog-ok", ["dialog", "repair-confirm-dialog", "ok"]),
        on_click=emit(RepairConfirm),
        [@html.text("安装")],
      ),
      @html.button(
        class="dsh-dialog-btn",
        type_="button",
        attrs=mark("repair-dialog-cancel", ["dialog", "repair-confirm-dialog", "cancel"]),
        on_click=emit(RepairCancel),
        [@html.text("取消")],
      ),
    ]),
  ])
  dialog(
    "repair-confirm-dialog",
    "给 " + name + " 安装缺的包",
    emit(RepairCancel),
    emit.map(fn(key : @html.Keyboard) {
      if key.key() == "Escape" {
        RepairCancel
      } else {
        Noop
      }
    }),
    card,
  )
}
///|
/// 取消隔离的确认框：文案照 design/deep-home-isolation.md 第 5 节。
///
/// 与删除确认框分开一格状态（home_confirm_id）：两个框说的是两件事，
/// 共用一格会让「关掉一个，另一个也关了」。确定键是危险动作，焦点先落在上面。
fn home_confirm_dialog(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let (name, path) = match find_row(model.rows, model.home_confirm_id) {
    Some(row) => (row.name, row.home_path)
    None => (model.home_confirm_id, "")
  }
  // 文案照 design/deep-home-isolation.md §9.4 第 3 条 / §9.5：
  // 移回本身不动内容，进回收站的是「剩下那份 home 里的会话与插件状态」，而且能捞回来。
  let where_text = if path == "" { "这份额外 home" } else { path }
  let message = "移回共用 home 会把这份额外 home 里剩下的会话与插件状态移到回收站，可以捞回来。"
  let card = @html.div(class="dsh-dialog-card", [
    @html.h2(
      class="dsh-dialog-title",
      attrs=mark("home-dialog-title", ["dialog", "home-confirm-dialog", "title"]),
      "移回共用 home？",
    ),
    @html.p(
      class="dsh-dialog-message",
      attrs=mark("home-dialog-message", ["dialog", "home-confirm-dialog", "message"])
        .title(where_text),
      message,
    ),
    @html.div(class="dsh-dialog-foot", [
      @html.button(
        id="dsh-home-confirm-ok",
        class="dsh-dialog-btn primary",
        type_="button",
        attrs=mark("home-dialog-ok", ["dialog", "home-confirm-dialog", "ok"]),
        on_click=emit(HomeDeisolateConfirm),
        [@html.text("移回共用 home")],
      ),
      @html.button(
        class="dsh-dialog-btn",
        type_="button",
        attrs=mark("home-dialog-cancel", ["dialog", "home-confirm-dialog", "cancel"]),
        on_click=emit(HomeDeisolateCancel),
        [@html.text("取消")],
      ),
    ]),
  ])
  dialog(
    "home-confirm-dialog",
    "移回共用 home " + name + "？",
    emit(HomeDeisolateCancel),
    emit.map(fn(key : @html.Keyboard) {
      if key.key() == "Escape" {
        HomeDeisolateCancel
      } else {
        Noop
      }
    }),
    card,
  )
}

///|
/// 配置历史的还原确认框：文案照 design/ops-maintenance-jobs.md §16.4。
///
/// 「会先用当前状态拍一张」不是安慰话：后端 restore-snapshot 的第二步就是先拍
/// 一张 reason 为「还原前」的快照，那张拍不成就不动任何文件。
fn snapshot_confirm_dialog(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let empty : SnapshotFact = { id: model.snapshot_confirm_snap, at: "", reason: "", files: 0, bytes: 0.0 }
  let (name, snap) = match find_row(model.rows, model.snapshot_confirm_id) {
    Some(row) =>
      match find_snapshot(row.snapshots, model.snapshot_confirm_snap) {
        Some(found) => (row.name, found)
        None => (row.name, empty)
      }
    None => (model.snapshot_confirm_id, empty)
  }
  // 时间读不出来时用「这份快照」：标题与正文说同一件事，不塞一个编出来的时刻。
  // 正文里的 <时间> 只是时刻本身（不带「那一份」）—— 那句的原话是
  // 「会先用当前状态拍一张，再把 <时间> 的三个文件写回去」。
  let stamp = snapshot_time_text(snap)
  let title = if stamp == "—" {
    "还原到这份快照？"
  } else {
    "还原到 " + stamp + " 那一份？"
  }
  let message = if stamp == "—" {
    "会先用当前状态拍一张，再把这份快照的三个文件写回去"
  } else {
    "会先用当前状态拍一张，再把 " + stamp + " 的三个文件写回去"
  }
  let card = @html.div(class="dsh-dialog-card", [
    @html.h2(
      class="dsh-dialog-title",
      attrs=mark("snapshot-dialog-title", ["dialog", "snapshot-confirm-dialog", "title"]),
      title,
    ),
    @html.p(
      class="dsh-dialog-message",
      attrs=mark("snapshot-dialog-message", ["dialog", "snapshot-confirm-dialog", "message"]),
      message,
    ),
    @html.p(
      class="dsh-dialog-note",
      attrs=mark("snapshot-dialog-what", ["dialog", "snapshot-confirm-dialog", "what"]),
      name + " 的这一份：" + (if snap.reason == "" { "没有写原因" } else { snap.reason }) + "，" +
      (if snap.files == 0 { "文件数读不到" } else { snapshot_size_text(snap) }),
    ),
    @html.div(class="dsh-dialog-foot", [
      @html.button(
        id="dsh-snapshot-confirm-ok",
        class="dsh-dialog-btn primary",
        type_="button",
        attrs=mark("snapshot-dialog-ok", ["dialog", "snapshot-confirm-dialog", "ok"]),
        on_click=emit(SnapshotRestoreConfirm),
        [@html.text("还原")],
      ),
      @html.button(
        class="dsh-dialog-btn",
        type_="button",
        attrs=mark("snapshot-dialog-cancel", ["dialog", "snapshot-confirm-dialog", "cancel"]),
        on_click=emit(SnapshotRestoreCancel),
        [@html.text("取消")],
      ),
    ]),
  ])
  dialog(
    "snapshot-confirm-dialog",
    title,
    emit(SnapshotRestoreCancel),
    emit.map(fn(key : @html.Keyboard) {
      if key.key() == "Escape" {
        SnapshotRestoreCancel
      } else {
        Noop
      }
    }),
    card,
  )
}

///|
/// 命令行型 profile 的「启动」说明（design/design-fixes.md §42）：
/// 启动键置灰但仍可点 —— 禁用按钮收不到点击，就没法解释为什么不让点。
fn cli_help_dialog(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let (name, home) = match find_row(model.rows, model.cli_help_id) {
    Some(row) =>
      (
        match row.profile_name {
          Some(profile) => profile
          None => row.name
        },
        row.home,
      )
    None => (model.cli_help_id, "")
  }
  let command = "DSH_HOME=" + home + " dsh --profile " + name + " --help"
  let body = "这只 profile 的 bundles 里没有 @deepseek-ai/dsh-web-app，没有网页入口，" +
    "起不成常驻实例。它要按自己的用法在终端里跑一次，参数以 --help 为准。"
  let card = @html.div(class="dsh-dialog-card", [
    @html.h2(
      class="dsh-dialog-title",
      attrs=mark("cli-help-title", ["dialog", "cli-help", "title"]),
      name + " 是命令行型",
    ),
    @html.p(
      class="dsh-dialog-message",
      attrs=mark("cli-help-message", ["dialog", "cli-help", "message"]).title(home),
      body,
    ),
    @html.pre(
      class="dsh-dialog-code",
      attrs=mark("cli-help-code", ["dialog", "cli-help", "code"]),
      [@html.text(command)],
    ),
    @html.div(class="dsh-dialog-foot", [
      @html.button(
        id="dsh-cli-help-ok",
        class="dsh-dialog-btn primary",
        type_="button",
        attrs=mark("cli-help-ok", ["dialog", "cli-help", "ok"]),
        on_click=emit(CliHelpClose),
        [@html.text("知道了")],
      ),
    ]),
  ])
  dialog(
    "cli-help-dialog",
    "命令行型 profile",
    emit(CliHelpClose),
    emit.map(fn(key : @html.Keyboard) {
      if key.key() == "Escape" {
        CliHelpClose
      } else {
        Noop
      }
    }),
    card,
  )
}

///|
/// 改名框（§30.2）：说清改的是目录名，不是卡片上的字。
///
/// 这一框改的不是显示字符串：它改的是磁盘上的 profile 目录名。所以标题写全「给 X 改名」，
/// 正文一句说清改的是什么，输入框下面再把**当前目录名**摆出来（技术细节进悬停）——
/// 一个叫「重命名实例」的框，很容易被读成「只改卡片上的字」。
fn rename_dialog(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let (name, dir_name, dir_hint) = match find_row(model.rows, model.rename_id) {
    Some(row) => {
      let dir_name = match row.profile_name {
        Some(profile) => profile
        None => ""
      }
      let hint = if dir_name == "" {
        "这一行的读数里没有 profile 目录名"
      } else if row.home_path == "" {
        "磁盘上的目录名：" + dir_name + "（读数里没有它的 home，拼不出完整路径）"
      } else {
        "磁盘上的目录：" + row.home_path + "/profiles/" + dir_name + "（改名就是改这一段的最后一级）"
      }
      (card_name_text(row), dir_name, hint)
    }
    None => (model.rename_id, "", "这一行已经不在读数里了")
  }
  let title = "给 " + name + " 改名"
  let can_confirm = model.rename_draft.trim().length() > 0
  let dir_line : Array[@html.Html] = if dir_name == "" {
    []
  } else {
    [
      @html.p(
        class="dsh-dialog-sub",
        attrs=mark("rename-dir", ["dialog", "rename-dialog", "dir"]).title(dir_hint),
        "当前目录名：" + dir_name,
      ),
    ]
  }
  let card = @html.div(class="dsh-dialog-card", [
    @html.h2(
      class="dsh-dialog-title",
      attrs=mark("dialog-title", ["dialog", "rename-dialog", "title"]),
      title,
    ),
    @html.p(
      class="dsh-dialog-desc",
      attrs=mark("rename-desc", ["dialog", "rename-dialog", "desc"]),
      "改的是这只 profile 的目录名；界面上的名字跟着变，配置里的内容不动。",
    ),
    @html.input(
      input_type=Text,
      id="dsh-rename-input",
      class="dsh-dialog-input",
      value=model.rename_draft,
      autofocus=true,
      attrs=mark("rename-input", ["dialog", "rename-dialog", "input"])
        .aria_label("新的目录名")
        .spellcheck(false),
      on_input=emit.map(fn(text) { RenameInput(text) }),
    ),
    @html.fragment(dir_line),
    @html.div(class="dsh-dialog-foot", [
      @html.button(
        class="dsh-dialog-btn primary",
        type_="button",
        disabled=!can_confirm,
        attrs=mark("dialog-ok", ["dialog", "rename-dialog", "ok"]),
        on_click=emit(RenameConfirm),
        [@html.text("改名")],
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
    title,
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

// ── 新建实例框（design/design-fixes.md §19.1）───────────────

///|
/// 第一张可点的源卡是哪一只：开框时焦点落在它身上。
///
/// 与「选择配置」侧栏同一个口径（job_profile_first_usable）：顺序就是显示顺序
/// （运行中那一组在前），「第一张」在界面上是看得见的那一条。
fn new_instance_first_usable(model : Model) -> String {
  let (running, stopped) = job_profile_picks(model)
  for pick in running {
    if pick.usable {
      return pick.name
    }
  }
  for pick in stopped {
    if pick.usable {
      return pick.name
    }
  }
  ""
}

///|
/// 这一刻「一只可用的源都没有」成不成立（design/design-fixes.md §21.4）。
///
/// **要求读数已经落地**（built）：读数还在路上时框里写的是「还没读到」，那时说
/// 「一只可用的都没有」是把「还不知道」说成了「没有」。读数落地、而第一张可点的源卡
/// 不存在（一只 profile 都没有，或全不可用）时才算成立 —— 这时复选框默认勾上，
/// 因为它是唯一能走的路。
fn new_instance_no_usable_source(model : Model) -> Bool {
  model.built && new_instance_first_usable(model) == ""
}

///|
/// 勾上复选框之后名字那一格预填什么：`base-<两位序号>`，读数里已有的就顺延
/// （design/design-fixes.md 第 20 / 21 节）。
///
/// 「已存在」拿手上这份 profiles 读数判（列表里看得见的那几只），序号从 01 起挨个试。
/// 读数里没有、磁盘上却有的名字交给后端兜底：那时它回 conflict，原因写在框里，
/// 改个名字就能再点一次 —— 比前端凭空猜一个号更诚实。
fn new_instance_base_name(model : Model) -> String {
  let taken : Array[String] = []
  for fact in job_profile_facts(model) {
    taken.push(fact.name)
  }
  let mut index = 1
  while index <= 999 {
    let digits = if index < 10 { "0" + index.to_string() } else { index.to_string() }
    let candidate = "base-" + digits
    if !taken.contains(candidate) {
      return candidate
    }
    index = index + 1
  }
  "base-" + index.to_string()
}

///|
/// 框里的一张源卡：与「选择配置」「整体替换选源」是**同一份画法**
/// （view_parts.mbt 的 profile_card）。这一处只决定点下去发什么、路径前缀、
/// 挂不挂「已选」那枚标记。选中那一张挂一枚「已选」—— 文字标记，不只靠高亮色。
///
/// 勾上「从基础实例开始」时整组不可选，但那一档不写在卡上（§22）：容器 inert + 遮罩，
/// 卡片照旧只写读数带来的 data-usable —— 同一张卡在维护页与这里长得一模一样。
fn new_instance_source_card(
  model : Model,
  pick : ProfilePick,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let selected = pick.name == model.new_source
  let ok = pick.usable
  let aria = if ok { "用 " + pick.name + " 当源配置" } else { pick.name + " 不可用：" + pick.why }
  profile_card(
    pick,
    new_instance_card_id(pick.name),
    "new-instance",
    ["overview", "new-instance"],
    if selected { "已选" } else { "" },
    aria,
    aria,
    fn(name) { NewInstanceStatePicked(name) },
    emit,
    chosen=selected,
  )
}

///|
/// 框里的一组源卡：分组头（与「选择配置」同一个说法）+ 卡片。
fn new_instance_group(
  key : String,
  title : String,
  picks : Array[ProfilePick],
  model : Model,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let cards : Array[@html.Html] = []
  for pick in picks {
    cards.push(new_instance_source_card(model, pick, emit))
  }
  @html.div(
    class="dsh-profile-sidebar-group",
    attrs=mark("new-instance-group", ["overview", "new-instance", "group", key])
      .data_set("group", key),
    [
      @html.h3(
        class="dsh-profile-sidebar-group-title",
        attrs=mark("new-instance-group-title", ["overview", "new-instance", "group", key, "title"]),
        title + " (" + picks.length().to_string() + ")",
      ),
      @html.div(
        class="dsh-profile-sidebar-list",
        attrs=mark("new-instance-list", ["overview", "new-instance", "list", key]),
        cards,
      ),
    ],
  )
}

///|
/// 源卡区上面那一句说明（§21）：一只可用的都没有时写出路，data-kind 标明是哪一档。
///
/// 为什么要有这一句：几行「不可用：…」自己躺着时，读者得自己推出「那我还能怎么办」；
/// 这一句把出路说出来。刻度只有一档了 —— 勾上之后的「这一刻不可选」跟着遮罩走
/// （new_instance_veil），不在这里。
fn new_instance_note(kind : String, text : String) -> @html.Html {
  @html.p(
    class="dsh-new-note",
    attrs=mark("new-instance-note", ["dialog", "new-instance", "note"]).data_set("kind", kind),
    text,
  )
}

///|
/// 整组源卡上盖的那一层（§22）：勾上「从基础实例开始」时，不可选这件事由**容器**说 ——
/// 容器挂 inert（键盘与指针都进不去），这一层挡在眼睛前面把话说出来。
///
/// 为什么不是「每张卡置灰 + 每张卡写一句 aria」：卡上的话说的是「这只配置怎么样」，
/// 而这一刻要说的是「这一组这一刻不参与选源」，是对整组说的。挂在卡上就得在每张卡上
/// 重复一遍同一件事，还把维护页那一套读数说明挤掉（同一份画法）。
fn new_instance_veil() -> @html.Html {
  @html.div(
    class="dsh-new-pick-veil",
    attrs=mark("new-instance-veil", ["dialog", "new-instance", "veil"]),
    [
      @html.p(
        class="dsh-new-pick-veil-text",
        attrs=mark("new-instance-veil-text", ["dialog", "new-instance", "veil", "text"]),
        "已勾上「从基础实例开始」，这些源配置这一刻不可选",
      ),
    ],
  )
}

///|
/// 「＋新建实例」的居中对话框：两步在同一个框里 —— 选源配置、填名字。
///
/// 源卡是「选择配置」那一套（全部 profile，含隔离的）；名字默认 `<源>-dev`，可改。
/// 左下角是「从基础实例开始」复选框（§21）：勾上就把源卡整组锁上、名字预填 base-NN、
/// 焦点进名字格；勾掉卡片恢复可选、名字一个字不动。
/// 底部两颗键：创建走既有 fork-profile（新副本默认隔离），取消把焦点还给页头那颗按钮。
/// 创建失败**不关框**：后端原话写在框里，改个名字就能再点一次。
fn new_instance_dialog(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let (running, stopped) = job_profile_picks(model)
  // 「读数到了没有」与「有没有可用源」是两件事：前者说知道不知道，后者才说得出口
  // 「一只可用的都没有」。空态那一句按这两档分开写。
  let landed = model.built
  let no_usable = new_instance_no_usable_source(model)
  // 勾上复选框、框里又有源卡时，整组锁住（§22）：锁挂在容器上，不挂在卡上。
  // 一只卡都没有时不盖遮罩 —— 那时没有可锁的东西，底下一句空态才是该看的。
  let lock_sources = model.new_base && (running.length() > 0 || stopped.length() > 0)
  // 有卡而一只可用的都没有：出路写在卡上面，不让几行「不可用」自己猜。
  // 这一句摆在遮罩**外面**（下面 pick_area 之前）：勾上之后它照样读得到 —— 遮罩上那句说的是
  // 「这一刻不可选」，这一句说的是「本来就没有可用的」，两件事各说各的。
  let none_usable_note = if no_usable && (running.length() > 0 || stopped.length() > 0) {
    new_instance_note("none-usable", "现在一只可用的都没有，可以勾上「从基础实例开始」新建一份。")
  } else {
    @html.nothing
  }
  let picks : Array[@html.Html] = []
  if running.length() == 0 && stopped.length() == 0 {
    picks.push(
      @html.p(
        class="dsh-empty-sub",
        attrs=mark("new-instance-empty", ["overview", "new-instance", "empty"])
          .data_set("state", if landed { "none-usable" } else { "loading" }),
        if landed {
          "现在一只可用的都没有，可以勾上「从基础实例开始」新建一份。"
        } else {
          "还没读到 profile 读数，等读数回来再挑。"
        },
      ),
    )
  } else {
    if running.length() > 0 {
      picks.push(new_instance_group("running", "当前运行的实例", running, model, emit))
    }
    if stopped.length() > 0 {
      picks.push(new_instance_group("stopped", "已停止的实例", stopped, model, emit))
    }
  }
  // 源那一格：从基础模板开始时写「基础模板」，否则写选中的那一只（还没选就写「还没选」）
  let source_text = if model.new_base {
    "基础模板"
  } else if model.new_source == "" {
    "还没选"
  } else {
    model.new_source
  }
  let has_source = model.new_base || model.new_source != ""
  let can_create = has_source && model.new_name_draft.trim() != "" && !model.new_busy
  // 框头那句**固定**（§25.4）：它说的是这个框有两条路（复制现有配置 / 用基础模板新建），
  // 勾不勾复选框都不改这一句。复选框只影响卡片区锁不锁、名字格引导要不要显示。
  let message_line = "从现有的某个配置复制一个，或者是创建一个全新的"
  let error_block = if model.new_error.length() > 0 {
    @html.p(
      class="dsh-dialog-error",
      attrs=mark("new-instance-error", ["dialog", "new-instance", "error"]),
      model.new_error,
    )
  } else {
    @html.nothing
  }
  // 名字这一格：标签 + 输入框；标签下面是那句引导（§21.1）——
  // 那一刻源卡全锁着，能做的只有填名字，「填一个名字，它会用基础模板新建」就是下一步。
  // 这一句**常驻占位**（§24.3）：没勾时只是 visibility: hidden，行还在，勾上勾下对话框
  // 高度与下半截的位置一个像素都不动。读屏那边由 visibility 自己摘掉，不另挂 aria。
  let name_lines : Array[@html.Html] = [
    @html.label(
      class="dsh-new-name-label",
      for_=new_instance_name_id(),
      attrs=mark("new-instance-name-label", ["dialog", "new-instance", "name-label"]),
      [
        // 必填星号（§24.1）：颜色是 danger，读屏不报它（靠输入框上的 aria-required）。
        @html.span(
          class="dsh-req",
          attrs=@html.Attrs::build().aria_hidden("true"),
          "*",
        ),
        @html.text("新实例名字（源配置：" + source_text + "）"),
      ],
    ),
    @html.span(
      class="dsh-new-name-guide",
      attrs=mark("new-instance-name-guide", ["dialog", "new-instance", "name-guide"])
        .data_set("active", if model.new_base { "true" } else { "false" }),
      "填一个名字，它会用基础模板新建",
    ),
  ]
  name_lines.push(
    @html.input(
      input_type=Text,
      id=new_instance_name_id(),
      class="dsh-dialog-input",
      value=model.new_name_draft,
      attrs=mark("new-instance-name", ["dialog", "new-instance", "name"])
        .aria_label("新实例名字")
        // 必填（§24.1）：读屏靠这一条，悬停里写人话，星号只是眼睛那一路。
        .aria_required("true")
        .title("必填")
        .spellcheck(false)
        // Enter 只挂在名字这一格上，不挂整个框：源卡自己也吃 Enter（选中），
        // 挂在框上会让「回车选源」同一次按键里顺手把实例也建了。
        .on_keydown(fn(event) {
          if event.key() == "Enter" {
            emit(NewInstanceConfirm)
          } else {
            @cmd.none
          }
        }),
      on_input=emit.map(fn(text) { NewInstanceNameInput(text) }),
    ),
  )
  // 源卡区：外面这层只做两件事 —— 给遮罩当定位容器、勾上时挂 inert 与 aria-disabled。
  // 列表自己的高度上限与滚动位置留在 .dsh-new-pick 上（那一层一个像素都不动）。
  let pick_targets : Array[@html.Html] = [
    @html.div(
      class="dsh-new-pick",
      attrs=mark("new-instance-pick", ["dialog", "new-instance", "pick"]),
      picks,
    ),
  ]
  if lock_sources {
    pick_targets.push(new_instance_veil())
  }
  let pick_area = @html.div(
    class="dsh-new-pick-wrap",
    attrs=mark("new-instance-pick-wrap", ["dialog", "new-instance", "pick-wrap"])
      .inert(lock_sources)
      .aria_disabled(if lock_sources { "true" } else { "false" }),
    pick_targets,
  )
  let card = @html.div(class="dsh-dialog-card dsh-new-card", [
    @html.h2(
      class="dsh-dialog-title",
      attrs=mark("new-instance-title", ["dialog", "new-instance", "title"]),
      "新建实例",
    ),
    @html.p(
      class="dsh-dialog-message",
      attrs=mark("new-instance-message", ["dialog", "new-instance", "message"])
        .data_set("source", if model.new_base { "base" } else { "profile" }),
      message_line,
    ),
    none_usable_note,
    pick_area,
    @html.div(class="dsh-new-name", name_lines),
    error_block,
    // 左下角「从基础实例开始」复选框（§21，原来那颗文本按钮）：勾上 = 换一种模式，
    // 不是「挑一种源」—— 源卡整组锁上，名字预填、焦点进名字格。与右下角的「创建 / 取消」分开。
    // 一只可用的源都没有时它默认勾上（见 app.mbt 的 NewInstanceOpen）。
    @html.div(class="dsh-dialog-foot dsh-dialog-foot-split", [
      @html.label(
        class="dsh-new-base-check",
        for_=new_instance_base_id(),
        attrs=mark("new-instance-base-label", ["dialog", "new-instance", "base-label"])
          .data_set("checked", if model.new_base { "true" } else { "false" })
          // 悬停说明挂在 label 上（挂在 input 上时只有指着那个小方块才出得来）
          .title("用 dsh 自带的基础模板新建一份，不依赖现有配置。现有配置都不可用时用这个。"),
        [
          @html.input(
            input_type=Checkbox,
            id=new_instance_base_id(),
            class="dsh-new-base-box",
            checked=model.new_base,
            attrs=mark("new-instance-base", ["dialog", "new-instance", "base"])
              .data_set("checked", if model.new_base { "true" } else { "false" })
              .title("用 dsh 自带的基础模板新建一份，不依赖现有配置。现有配置都不可用时用这个。")
              .aria_label("从基础实例开始")
              .disabled(model.new_busy)
              // 勾的是「勾完之后的那一档」：模型是唯一真相，原生复选框的翻转随后由重渲染对齐
              .on_click(fn(_event) { emit(NewInstanceBaseToggled(!model.new_base)) }),
          ),
          @html.span("从基础实例开始"),
        ],
      ),
      @html.div(class="dsh-dialog-actions", [
        @html.button(
          id=new_instance_ok_id(),
          class="dsh-dialog-btn primary",
          type_="button",
          disabled=!can_create,
          attrs=mark("new-instance-ok", ["dialog", "new-instance", "ok"]),
          on_click=emit(NewInstanceConfirm),
          [@html.text(if model.new_busy { "正在创建…" } else { "创建" })],
        ),
        @html.button(
          id="dsh-new-instance-cancel",
          class="dsh-dialog-btn",
          type_="button",
          disabled=model.new_busy,
          attrs=mark("new-instance-cancel", ["dialog", "new-instance", "cancel"]),
          on_click=emit(NewInstanceClose),
          [@html.text("取消")],
        ),
      ]),
    ]),
  ])
  dialog(
    "new-instance-dialog",
    "新建实例",
    emit(NewInstanceClose),
    emit.map(fn(key : @html.Keyboard) {
      if key.key() == "Escape" {
        NewInstanceClose
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
  // 两组各自的顺序都在这里定：自动排序（运行中按实例、已停止按最近改动降序）
  // 之上再叠一层手动顺序表（见 state.mbt 的 display_groups）。
  // **在取的时候算，不在 rebuild 里算**：顺序表会随拖动变，而 rebuild 一趟只跑一次，
  // 放那儿的话拖完松手页面会停在旧顺序上。
  // 启动等待中的行留在原分组，所以「已停止」组把 starting 一起算进来。
  let (running, stopped) = display_groups(model)
  // 读数还没落地：这一格摆加载态（与真条目同形的占位块，见 card_loading），
  // 空态只在真读到空的时候出现
  let pending = readings_pending(model)
  // 一组里的每一条都带上自己的行 id（见 DragItem）：拖动预览要按 id 找锚点
  let running_list : Array[DragItem] = running.map(fn(row) {
    { id: row.id, node: instance_card(row, model, emit) }
  })
  if running.length() == 0 {
    if pending {
      running_list.push({
        id: "",
        node: card_loading(
          "running-loading",
          "正在读取实例读数…",
          "实例与 profile 的读数还在路上。这里先摆加载态。「确实一个都没有」要等读数回来才敢说。",
        ),
      })
    } else {
      // 读数失败时把原因带上（那一档标记里有）；读到了就没这一句
      let detail = match model.tag_instances {
        Some(tag) => tag.detail
        None => ""
      }
      running_list.push({
        id: "",
        node: running_empty(running_summary(model), detail, emit),
      })
    }
  }
  let stopped_list : Array[DragItem] = stopped.map(fn(row) {
    { id: row.id, node: instance_card(row, model, emit) }
  })
  if stopped.length() == 0 {
    if pending {
      stopped_list.push({
        id: "",
        node: card_loading(
          "stopped-loading",
          "正在读取 profile 读数…",
          "profile 的读数还在路上，这里先摆加载态。",
        ),
      })
    } else {
      stopped_list.push({ id: "", node: stopped_empty() })
    }
  }
  let dialogs : Array[@html.Html] = []
  if model.confirm_id.length() > 0 {
    dialogs.push(confirm_dialog(model, emit))
  }
  if model.home_confirm_id.length() > 0 {
    dialogs.push(home_confirm_dialog(model, emit))
  }
  if model.repair_confirm_id.length() > 0 {
    dialogs.push(repair_confirm_dialog(model, emit))
  }
  if model.snapshot_confirm_id.length() > 0 {
    dialogs.push(snapshot_confirm_dialog(model, emit))
  }
  if model.promote_confirm {
    dialogs.push(promote_confirm_dialog(model, emit))
  }
  if model.cli_help_id.length() > 0 {
    dialogs.push(cli_help_dialog(model, emit))
  }
  if model.rename_id.length() > 0 {
    dialogs.push(rename_dialog(model, emit))
  }
  if model.note_open.length() > 0 {
    dialogs.push(note_dialog(model, emit))
  }
  if model.new_open {
    dialogs.push(new_instance_dialog(model, emit))
  }
  let body : Array[@html.Html] = [
    @html.section(class="dsh-overview-page", [
      @html.header(class="dsh-overview-head", [
        @html.div(class="dsh-head-text", [
          @html.h1(class="dsh-page-title", "实例总览"),
          source_badge(model.tag_runtime, ["overview", "head", "source-badge"]),
          @html.span(class="dsh-head-note", "点卡片看读数与控制；灯旁边的词就是状态"),
        ]),
        // 页头的主操作：点开新建实例框（§19.1）。它不再是颗点了没反应的按钮。
        @html.button(
          id=new_instance_btn_id(),
          class="dsh-new-btn",
          type_="button",
          attrs=mark("new-instance", ["overview", "new-instance"]),
          on_click=emit(NewInstanceOpen),
          [@html.span(class="dsh-plus", "＋"), @html.span("新建实例")],
        ),
      ]),
      section_head(
        "running",
        "当前运行的实例",
        if pending { "…" } else { running.length().to_string() },
        model.tag_instances,
      ),
      row_group("running", running_list, model, emit),
      section_head(
        "stopped",
        "已停止的实例",
        if pending { "…" } else { stopped.length().to_string() },
        model.tag_profiles,
      ),
      row_group("stopped", stopped_list, model, emit),
      archived_section(model, emit),
    ]),
  ]
  // 对话框一律排在最后 push（见本函数末尾），不能插在抽屉前面：
  // 抽屉的入场动画挂在元素本身上，节点序号一变它就重新挂一次，动画会重放一遍。
  // 实测过：开着抽屉点「删除」，对话框一插到抽屉前头，抽屉就再滑进来一次。
  // 详情抽屉：同一时刻只开一个，开着的那一行必须在（列表重建后行没了就自动不开，
  // 见 app.mbt 的 rebuild —— 抽屉指向一个不存在的行会留下一个关不掉的空面板）。
  match find_row(model.rows, model.drawer_id) {
    Some(row) => body.push(detail_drawer(row, model, emit, false))
    None => ()
  }
  // 正在收的那一只：节点多留 drawer_anim_ms，让滑出看得见。它只是**一段动画的寿命** ——
  // 焦点早就回卡片了，指针也被它自己那套样式关掉了；走完由 DrawerClosed 撤节点。
  // 行没了（收的这 220ms 里列表重建过）就什么都不画，与开着的那一只同一口径。
  match find_row(model.rows, model.drawer_closing) {
    Some(row) => body.push(detail_drawer(row, model, emit, true))
    None => ()
  }
  // 整体替换的右侧栏（§17.3）：与抽屉同一套外壳，但同一时刻只开一个
  //（打开它时抽屉已经收了，见 app.mbt 的 PromoteOpen）。
  if model.promote_row != "" {
    body.push(promote_sidebar(model, emit))
  }
  // 虚影挂在最外层、不进任何一页的栅格：它是 position: fixed 的，不占文档流，
  // 也就不动任何一条的位置（落点算法量的是格子，多一个盒子就会量错）。
  match find_row(model.rows, model.drag_id) {
    Some(dragged) => {
      if model.drag_ghost {
        body.push(drag_ghost_view(dragged, model))
      }
    }
    None => ()
  }
  // 读屏播报：只在拖动态存在时才有一个节点（它是提醒，不是常驻状态）
  body.push(drag_live_region(model))
  // 对话框放在整张页面的最末：它们出现 / 消失只改自己这一段，不动前面抽屉的节点序号。
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
