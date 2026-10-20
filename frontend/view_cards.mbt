// 实例卡与它身上的记号：卡片的 DOM 与类名、状态灯、端口、名字、命令行型 / 独立 home 两枚标记、
// 第二行那三段（备注 / 上次启动 / 从哪儿派生）以及归档区里那一行。
//
// 2026-10-20 从 view_overview.mbt 拆出来：那个文件 3369 行，卡片与抽屉、对话框挤在一起，
// 改一张卡的样式得在三个方向的文件里翻。只搬位置，函数体一个字没改。


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
  // 卡上不再写状态词（§44）：分组标题「当前运行的实例 / 已停止的实例」已经把这件事说了，
  // 写在每张卡上是同一句话重复 N 遍，还挤名字。红灯/绿灯本身仍带 aria-label 与悬停，
  // 卡上名字的悬停也仍写「（状态词）」，文字通道没断。
  match row.port_value {
    Some(port) => head.push(card_port(row, port))
    None => ()
  }
  // 标记（金标「独立 home」/ 蓝标「命令行型」/ 以后别的颜色）**吸在右上角**：
  // 一律摆在第一行的最右端，按一行并排、新的往后加。名字占满余下宽度（.dsh-name flex:1），
  // 所以标记组永远贴着卡片右边，与端口同一行时排在端口右侧（§46）。
  let badges : Array[@html.Html] = []
  match row.home_kind {
    "isolated" => badges.push(card_home_badge(row))
    _ => ()
  }
  if row.cli_only {
    badges.push(card_cli_badge(row))
  }
  if badges.length() > 0 {
    head.push(
      @html.span(
        class="dsh-case-badges",
        attrs=mark("card-badges", ["overview", "card", row.id, "badges"]),
        badges,
      ),
    )
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
    // 状态词不再上卡（§44），但状态本身要留一个机器可读的出口：
    // 验收与探针按这个属性认，读屏按灯上的 aria-label 认。
    attrs=card_attrs(row, model, emit).data_set("state", light_key(row.light)),
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
