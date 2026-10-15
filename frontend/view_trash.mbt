// 回收站页（第六轮契约第二节）。
//
// 为什么要有这一页：删除进回收站那条回执当时写着「可以捞回来」，而界面上没有任何入口 ——
// 那是一个没有把手的承诺。这一页就是那个把手：谁在回收站里、什么时候删的、多大，
// 以及两个动作（恢复 / 彻底删除）。
//
// 三档空白分得清（与日志页同一套纪律）：
//   · 读数还没回来          → 加载态（.dsh-loading，实线框 + 面板底色）
//   · 读数回来了、确实是空的 → 空态「回收站是空的」（.dsh-empty，虚线框）
//   · 读数里根本没有 trash   → 第三种：这一版后端还没这个字段（**不是**空的）
// 三者写成同一副样子就是把「还没读到 / 读不到」说成了「没有」✗

///|
/// 一条回收站的行 id：写动作用它认「这一枪打中了哪一条」。
/// 加前缀是有意的 —— 它与 profile 行 id 不会撞，重读读数时也不会被拼列表那一步动到。
fn trash_row_id(dir : String) -> String {
  "trash:" + dir
}

///|
/// 「彻底删除」那颗按钮的 id：确认框关掉之后焦点要还给它。
fn trash_purge_trigger_id(dir : String) -> String {
  "dsh-trash-purge-" + dom_key(dir)
}

///|
/// 体积（字节）→ 人读的串。接口给的是数字，这里只换单位。
fn trash_size_text(bytes : Double?) -> String {
  match bytes {
    None => "读不到"
    Some(value) =>
      if value < 1024.0 {
        value.to_int().to_string() + " B"
      } else if value < 1024.0 * 1024.0 {
        format_decimal(value / 1024.0, 1) + " KB"
      } else {
        format_decimal(value / 1024.0 / 1024.0, 2) + " MB"
      }
  }
}

///|
/// 文件数那一格的值：数不出来写「读不到」，不写 0。
fn trash_count_text(count : Int?) -> String {
  match count {
    Some(n) => n.to_string() + " 个文件"
    None => "文件数读不到"
  }
}

///|
/// 删除时刻那一格：本地短格式（10-15 18:50）；读不到写「—」并把原因放进悬停。
fn trash_time_text(item : ConsoleTrash) -> String {
  match item.deleted_at_ms {
    None => "—"
    Some(ms) =>
      match js_short_time_ms(ms) {
        "" => "—"
        short => short
      }
  }
}

///|
fn trash_time_hint(item : ConsoleTrash) -> String {
  match item.deleted_at_ms {
    Some(ms) => {
      let iso = js_iso_time_ms(ms)
      "删除时刻（按浏览器本地时间显示" +
      (if iso == "" { "" } else { "，" + iso }) +
      "）。来源：" + item.deleted_at_source
    }
    None => "读不到删除时刻：" + item.deleted_at_source
  }
}

///|
/// 一行：profile 名 + 删除时间 + 文件数 + 体积 + 两个动作。
fn trash_row(item : ConsoleTrash, emit : @cmd.Emit[Msg]) -> @html.Html {
  let trigger = trash_purge_trigger_id(item.dir)
  @html.article(
    class="dsh-trash-row",
    attrs=mark("trash-row", ["trash", "list", item.dir]),
    [
      @html.span(
        class="dsh-trash-name",
        attrs=mark("trash-name", ["trash", "list", item.dir, "name"])
          .title("回收站里的目录名：" + item.dir + "（恢复与彻底删除都以它为目标）"),
        item.profile,
      ),
      @html.span(class="dsh-trash-stamp", [
        @html.span(class="dsh-trash-stamp-label", "删除于"),
        @html.span(
          class="dsh-trash-stamp-value",
          attrs=mark("trash-stamp", ["trash", "list", item.dir, "stamp"]).title(
            trash_time_hint(item),
          ),
          trash_time_text(item),
        ),
      ]),
      @html.span(
        class="dsh-trash-size",
        attrs=mark("trash-size", ["trash", "list", item.dir, "size"]).title(item.size_source),
        trash_count_text(item.file_count) + " | " + trash_size_text(item.bytes),
      ),
      @html.span(class="dsh-trash-spacer", @html.nothing),
      @html.button(
        class="dsh-trash-btn",
        type_="button",
        attrs=mark("trash-restore", ["trash", "list", item.dir, "restore"]),
        on_click=emit(TrashRestore(item.dir)),
        [icon("archive-arrow-up-outline"), @html.span("恢复")],
      ),
      @html.button(
        id=trigger,
        class="dsh-trash-btn danger",
        type_="button",
        attrs=mark("trash-purge", ["trash", "list", item.dir, "purge"]),
        on_click=emit(TrashPurgeOpen(item.dir, trigger)),
        [icon("delete-outline"), @html.span("彻底删除")],
      ),
    ],
  )
}

///|
/// 彻底删除的确认框：走既有那套 dialog()（居中 / 层级 / 点遮罩关闭 / Esc 关闭都是同一套）。
///
/// 这里必须问一次：这一下之后目录就从磁盘上没了，恢复的路径同时也没了。
/// 框里说清「删的是哪一份、多大、无法恢复」，不摆请求参数与错误码那些实现细节。
fn trash_purge_dialog(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let item : ConsoleTrash? = match model.console {
    None => None
    Some(facts) => {
      let mut found : ConsoleTrash? = None
      for entry in facts.trash {
        if entry.dir == model.trash_purge_dir {
          found = Some(entry)
        }
      }
      found
    }
  }
  let name = match item {
    Some(entry) => entry.profile
    None => model.trash_purge_dir
  }
  let detail = match item {
    Some(entry) =>
      "这一份是 " + trash_count_text(entry.file_count) + " | " + trash_size_text(entry.bytes) +
      "，删掉之后磁盘上就没有了，恢复的路径也同时消失 —— 无法恢复。"
    None => "这一份已经不在回收站读数里了，删掉之后无法恢复。"
  }
  let card = @html.div(class="dsh-dialog-card", [
    @html.h2(
      class="dsh-dialog-title",
      attrs=mark("dialog-title", ["dialog", "purge-dialog", "title"]),
      "彻底删除 " + name + "？",
    ),
    @html.p(
      class="dsh-dialog-message",
      attrs=mark("dialog-message", ["dialog", "purge-dialog", "message"]).title(
        "回收站目录名：" + model.trash_purge_dir,
      ),
      detail,
    ),
    @html.div(class="dsh-dialog-foot", [
      @html.button(
        id="dsh-purge-ok",
        class="dsh-dialog-btn primary",
        type_="button",
        attrs=mark("dialog-ok", ["dialog", "purge-dialog", "ok"]),
        on_click=emit(TrashPurgeConfirm),
        [@html.text("彻底删除")],
      ),
      @html.button(
        class="dsh-dialog-btn",
        type_="button",
        attrs=mark("dialog-cancel", ["dialog", "purge-dialog", "cancel"]),
        on_click=emit(TrashPurgeCancel),
        [@html.text("取消")],
      ),
    ]),
  ])
  dialog(
    "purge-dialog",
    "彻底删除 " + name + "？",
    emit(TrashPurgeCancel),
    emit.map(fn(key : @html.Keyboard) {
      if key.key() == "Escape" {
        TrashPurgeCancel
      } else {
        Noop
      }
    }),
    card,
  )
}

///|
/// 回收站页。
fn trash_view(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let pending = !model.read_console
  let body : Array[@html.Html] = []
  match model.console {
    None =>
      if pending {
        body.push(
          loading_block(
            "trash-loading",
            "正在读取回收站…",
            "控制台自身状态的读数还在路上。这里先摆加载态 —— 「回收站是空的」要等读数回来才敢说。",
          ),
        )
      } else {
        body.push(
          @html.section(
            class="dsh-empty",
            attrs=mark("trash-unreadable", ["trash", "unreadable"]),
            [
              @html.span(class="dsh-empty-icon", [icon("shield-outline", size=26)]),
              @html.p(class="dsh-empty-line", "回收站读数读取失败。"),
              @html.p(class="dsh-empty-sub", model.console_error),
            ],
          ),
        )
      }
    Some(facts) =>
      if !facts.trash_present {
        // 读不到 ≠ 没有：后端这一版没给 trash 字段，就不说「回收站是空的」
        body.push(
          @html.section(
            class="dsh-empty",
            attrs=mark("trash-missing-field", ["trash", "missing-field"]),
            [
              @html.span(class="dsh-empty-icon", [icon("shield-outline", size=26)]),
              @html.p(class="dsh-empty-line", "这一版后端还没有回收站读数。"),
              @html.p(
                class="dsh-empty-sub",
                "GET /api/local/console 的响应里没有 trash 字段，读不到回收站里有什么 —— " +
                "这与「回收站是空的」不是一回事。重启控制台后端（用带这个字段的那一版）即可。",
              ),
            ],
          ),
        )
      } else if facts.trash.length() == 0 {
        body.push(
          @html.section(
            class="dsh-empty",
            attrs=mark("trash-empty", ["trash", "empty"]),
            [
              @html.span(class="dsh-empty-icon", [icon("delete-outline", size=26)]),
              @html.p(class="dsh-empty-line", "回收站是空的"),
              @html.p(
                class="dsh-empty-sub",
                "删除进回收站的 profile 会在这里等着，直到把它恢复或彻底删掉。",
              ),
            ],
          ),
        )
      } else {
        let rows = facts.trash.map(fn(item) { trash_row(item, emit) })
        body.push(@html.div(class="dsh-trash-rows", rows))
      }
  }
  // 页头 + 提示条 + 三档空白里的一档，排在同一列里
  let children : Array[@html.Html] = [
    @html.header(class="dsh-overview-head", [
      @html.div(class="dsh-head-text", [
        @html.h1(class="dsh-page-title", "回收站"),
        source_badge(model.tag_archived, ["trash", "head", "source-badge"]),
        @html.span(class="dsh-head-note", "删掉的 profile 在这里，能恢复也能彻底删掉"),
      ]),
    ]),
    action_notice(model, emit),
  ]
  for block in body {
    children.push(block)
  }
  let nodes : Array[@html.Html] = [
    @html.section(
      class="dsh-trash",
      attrs=mark("trash-page", ["trash", "page"]),
      children,
    ),
  ]
  if model.trash_purge_dir.length() > 0 {
    nodes.push(trash_purge_dialog(model, emit))
  }
  @html.fragment(nodes)
}
