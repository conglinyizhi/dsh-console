// 抽屉：五个组与组内的按钮行、补包那一行（还缺 N 个包 + 安装）、配置 home 那一格、
// 配置快照与「用另一只配置替换」的入口，以及抽屉自己的壳（detail_drawer）。
//
// 2026-10-20 从 view_overview.mbt 拆出来：抽屉是这套界面里最长的一条读路径，
// 单独成文件之后「打开抽屉看到什么」只在这一处找。只搬位置，函数体一个字没改。


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
