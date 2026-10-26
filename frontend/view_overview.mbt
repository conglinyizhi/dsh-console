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
/// 被拖的那一条现在排在第几格（0 起）：**按模型里的数**，不按 DOM 顺序。
///
/// 摆格子那一步（dom.mbt 的 js_grid_cells）拿的就是这个数，它也是落点；
/// 这里只是把它变成「第几位」好播报。
fn drag_position(model : Model) -> Int32 {
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
fn drop_slot(row : Row, slot_index : Int32) -> @html.Html {
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
      @html.span(class="dsh-tile-slot", [
        @html.span(class="dsh-tile", @html.nothing),
      ]),
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
    attrs=mark("drop-tail", ["overview", "drop-tail", group]).aria_hidden(
      "true",
    ),
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
    attrs=mark("drag-ghost", ["overview", "drag-ghost", row.id]).aria_hidden(
      "true",
    ),
    [
      @html.article(class="dsh-case ghost-card", [
        @html.span(class="dsh-tile-slot", [
          @html.span(
            class=if row.tone is Accent {
              "dsh-tile accent"
            } else {
              "dsh-tile violet"
            },
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
  items : Array[@html.Html],
  model : Model,
  _emit : @cmd.Emit[Msg],
) -> @html.Html {
  // 落点写在 DOM 上（data-drop-index）：它是「预览就是结果」这条验收的判据之一，
  // 探针照它比对「松手前占位块在第几格」与「松手后被拖那一条排在第几格」。
  // 也是这一条链路的自证：算法算出来的那个数，与画面上摆的那一格是同一个。
  let attrs = mark("row-group", ["overview", "rows", group])
    .data_set("group", group)
    .data_set("drop-index", model.drag_at_index.to_string())
  let kids : Array[@html.Html] = items
  // 占位块里放的是被拖那一条自己的名字：一眼看出「是它要落到这儿」
  let dragged_row = match find_row(model.rows, model.drag_id) {
    Some(row) => row
    None => return @html.div(class="dsh-rows dsh-card-grid", attrs~, kids)
  }
  let previewing = model.drag_active &&
    model.drag_group == group &&
    model.drag_at_index >= 0
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
    @html.div(class="dsh-rows dsh-card-grid dsh-drag-active", attrs~, kids)
  } else {
    @html.div(class="dsh-rows dsh-card-grid", attrs~, kids)
  }
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
    body.push(
      source_badge(model.tag_archived, [
        "overview", "section", "archived", "source-badge",
      ]),
    )
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
            icon(
              if model.archived_open {
                "chevron-down"
              } else {
                "chevron-right"
              },
            ),
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
/// 实例总览页。
///|
/// 没装 DSH 时的引导卡：说清缺什么、给一个安装入口，并说明下面那份是演示数据。
///
/// 这一格替代原来的「演示数据 | 真实读取失败」徽标 —— 那个徽标只说「失败了」，
/// 不告诉人为什么、也不告诉人下一步做什么。
fn dsh_missing_notice() -> @html.Html {
  @html.div(class="dsh-empty dsh-missing", [
    @html.span(class="dsh-empty-icon", [icon("server", size=26)]),
    @html.p(class="dsh-empty-line", "还没读到本机的 DSH 配置。"),
    @html.p(
      class="dsh-empty-sub",
      "控制台管理的是本机 DSH 的 profile 与实例。如果还没装 DSH，先装一份；如果已经装了，确认 DSH_HOME 指向的是你平时用的那一份。",
    ),
    @html.a(
      href="https://github.com/deepseek-ai/deepseek-harness",
      target=@html.Target::Blank,
      rel="noopener",
      class="dsh-empty-cta",
      attrs=mark("missing-dsh-install", ["overview", "missing-dsh", "install"]),
      "去安装 DSH",
    ),
    @html.p(
      class="dsh-empty-sub",
      "下面显示的是演示数据，用来看一眼界面长什么样。",
    ),
  ])
}

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
  let running_list : Array[@html.Html] = running.map(fn(row) {
    instance_card(row, model, emit)
  })
  if running.length() == 0 {
    if pending {
      running_list.push(
        card_loading(
          "running-loading", "正在读取实例读数…", "实例与 profile 的读数还在路上。这里先摆加载态。「确实一个都没有」要等读数回来才敢说。",
        ),
      )
    } else {
      // 读数失败时把原因带上（那一档标记里有）；读到了就没这一句
      let detail = match model.tag_instances {
        Some(tag) => tag.detail
        None => ""
      }
      running_list.push(running_empty(running_summary(model), detail, emit))
    }
  }
  let stopped_list : Array[@html.Html] = stopped.map(fn(row) {
    instance_card(row, model, emit)
  })
  if stopped.length() == 0 {
    if pending {
      stopped_list.push(
        card_loading(
          "stopped-loading", "正在读取 profile 读数…", "profile 的读数还在路上，这里先摆加载态。",
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
  if model.home_confirm_id.length() > 0 {
    dialogs.push(home_confirm_dialog(model, emit))
  }
  if model.merge_source.length() > 0 {
    dialogs.push(merge_dialog(model, emit))
  }
  if model.fork_confirm_id.length() > 0 {
    dialogs.push(fork_confirm_dialog(model, emit))
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
  // 这只 profile 的启动环境（§61.3）：从抽屉「配置」组里点开，盖在抽屉上面
  if model.fork_progress_active {
    dialogs.push(fork_progress_dialog(model, emit))
  }
  if model.env_open.length() > 0 {
    dialogs.push(env_profile_dialog(model, emit))
  }
  let body : Array[@html.Html] = [
    @html.section(class="dsh-overview-page", [
      @html.header(class="dsh-overview-head", [
        @html.div(class="dsh-head-text", [
          @html.h1(class="dsh-page-title", "实例总览"),
          source_badge(model.tag_runtime, ["overview", "head", "source-badge"]),
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
      if model.dsh_missing {
        dsh_missing_notice()
      } else {
        @html.span(class="dsh-missing-none", "")
      },
      section_head(
        "running",
        "当前运行的实例",
        if pending {
          "…"
        } else {
          running.length().to_string()
        },
        model.tag_instances,
      ),
      row_group("running", running_list, model, emit),
      section_head(
        "stopped",
        "已停止的实例",
        if pending {
          "…"
        } else {
          stopped.length().to_string()
        },
        // 已经在顶部摆过「还没读到 DSH 配置」的引导卡时，这一格不再重复一枚失败徽标
        if model.dsh_missing { None } else { model.tag_profiles },
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
    Some(dragged) =>
      if model.drag_ghost {
        body.push(drag_ghost_view(dragged, model))
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
      "扫了本机 " +
      facts.candidate_count.to_string() +
      " 个 loopback 监听端口，其中 " +
      facts.probe_hits.to_string() +
      " 个命中 DSH 签名"
  }
}
