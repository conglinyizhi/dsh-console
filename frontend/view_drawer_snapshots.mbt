// 抽屉：五个组与组内的按钮行、补包那一行（还缺 N 个包 + 安装）、配置 home 那一格、
// 配置快照与「用另一只配置替换」的入口，以及抽屉自己的壳（detail_drawer）。
//
// 2026-10-20 从 view_overview.mbt 拆出来：抽屉是这套界面里最长的一条读路径，
// 单独成文件之后「打开抽屉看到什么」只在这一处找。只搬位置，函数体一个字没改。

///|
/// 快照那一行的时间：本地短格式（10-19 15:04）。读不出来写「—」，不编一个时刻。
fn snapshot_time_text(snap : SnapshotFact) -> String {
  match js_short_time(snap.at) {
    "" => "—"
    short => short
  }
}

///|
/// 和 profile 当前内容比，这一份改了哪些文件、各差多少行。
/// 全同就写「和当前一致」——这句话本身就是「要不要还原」的答案。
fn snapshot_diff_text(snap : SnapshotFact) -> String {
  if snap.diff.length() == 0 {
    return "和当前一致"
  }
  let parts : Array[String] = []
  for d in snap.diff {
    let one = match d.state {
      "changed" =>
        d.name + " +" + d.added.to_string() + " −" + d.removed.to_string()
      "only-snapshot" => d.name + "（只在快照里）"
      "only-current" => d.name + "（只在当前里）"
      _ => d.name
    }
    parts.push(one)
  }
  parts.join("；")
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
  "拍下来的时刻：" +
  when +
  "；原因：" +
  snapshot_reason_text(snap) +
  "；快照 id：" +
  snap.id +
  "；这一份里存了 " +
  snapshot_size_text(snap) +
  "。还原会用它的三个文件覆盖现在的内容"
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
  _model : Model,
  emit : @cmd.Emit[Msg],
  lead~ : Array[@html.Html] = [],
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
      attrs=mark("drawer-snapshot-create-line", [
        "overview",
        "drawer",
        row.id,
        "snapshot",
        "create",
      ]),
      lead_items +
      [
        @html.button(
          class="dsh-btn",
          type_="button",
          disabled=!creatable,
          attrs=mark("drawer-snapshot-create", [
              "overview",
              "drawer",
              row.id,
              "action",
              "snapshot-create",
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
    // 「还没有快照」不再单占一行（§69）：空态是常态，这一行每天挂着只是噪声。
    // 只有老后端缺这一项时才留一行 —— 那是「读不到」，与「还没拍过」不是一回事。
    if row.snapshots_source ==
      "这一版读数里没有「配置快照」这一项" {
      items.push(
        @html.p(
          class="dsh-snapshot-empty",
          attrs=mark("drawer-snapshot-empty", [
            "overview",
            "drawer",
            row.id,
            "snapshot",
            "empty",
          ]).title(row.snapshots_source),
          "这一版读数里没有配置快照，暂时拍不了也还原不了。",
        ),
      )
    }
  } else {
    for snap in row.snapshots {
      items.push(
        @html.div(
          class="dsh-snapshot-row",
          attrs=mark("drawer-snapshot-row", [
              "overview",
              "drawer",
              row.id,
              "snapshot",
              snap.id,
            ])
            .data_set("snapshot", snap.id)
            .title(snapshot_row_hint(snap)),
          [
            @html.span(
              class="dsh-snapshot-time",
              attrs=mark("drawer-snapshot-time", [
                "overview",
                "drawer",
                row.id,
                "snapshot",
                snap.id,
                "time",
              ]),
              snapshot_time_text(snap),
            ),
            @html.span(
              class="dsh-snapshot-reason",
              attrs=mark("drawer-snapshot-reason", [
                "overview",
                "drawer",
                row.id,
                "snapshot",
                snap.id,
                "reason",
              ]),
              snapshot_reason_text(snap),
            ),
            @html.span(
              class="dsh-snapshot-diff",
              attrs=mark("drawer-snapshot-diff", [
                "overview",
                "drawer",
                row.id,
                "snapshot",
                snap.id,
                "diff",
              ]).title("和 profile 现在那三个文件比，差多少行"),
              snapshot_diff_text(snap),
            ),
            @html.span(
              class="dsh-snapshot-size",
              attrs=mark("drawer-snapshot-size", [
                "overview",
                "drawer",
                row.id,
                "snapshot",
                snap.id,
                "size",
              ]),
              snapshot_size_text(snap),
            ),
            @html.button(
              class="dsh-snapshot-restore",
              type_="button",
              disabled=busy,
              attrs=mark("drawer-snapshot-restore", [
                  "overview",
                  "drawer",
                  row.id,
                  "snapshot",
                  snap.id,
                  "restore",
                ])
                .data_set("snapshot", snap.id)
                .title(
                  "把这份快照里的三个文件写回去；还原之前会先给当前状态拍一张",
                ),
              on_click=emit(
                SnapshotRestoreOpen(row.id, snap.id, card_id(row.id)),
              ),
              [@html.text("还原")],
            ),
            @html.button(
              class="dsh-snapshot-delete",
              type_="button",
              disabled=busy,
              attrs=mark("drawer-snapshot-delete", [
                  "overview",
                  "drawer",
                  row.id,
                  "snapshot",
                  snap.id,
                  "delete",
                ])
                .data_set("snapshot", snap.id)
                .title("删掉这一份快照，删了就找不回来"),
              on_click=emit(SnapshotDelete(row.id, snap.id)),
              [@html.text("删除")],
            ),
          ],
        ),
      )
    }
  }
  @html.div(
    class="dsh-drawer-history",
    attrs=mark("drawer-snapshot-history", [
        "overview",
        "drawer",
        row.id,
        "snapshot",
        "history",
      ])
      .data_set("count", row.snapshots.length().to_string())
      .title(
        "配置快照：" +
        (if row.snapshots_source == "" {
          "读数里没给来源"
        } else {
          row.snapshots_source
        }),
      ),
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
