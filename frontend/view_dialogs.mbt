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
  let message = "替换前会先给 " +
    target +
    " 拍一张快照，出问题能还原。"
  let card = @html.div(class="dsh-dialog-card", [
    @html.h2(
      class="dsh-dialog-title",
      attrs=mark("promote-dialog-title", [
        "dialog", "promote-confirm-dialog", "title",
      ]),
      title,
    ),
    @html.p(
      class="dsh-dialog-message",
      attrs=mark("promote-dialog-message", [
        "dialog", "promote-confirm-dialog", "message",
      ]),
      message,
    ),
    @html.div(class="dsh-dialog-foot", [
      @html.button(
        id=promote_confirm_ok_id(),
        class="dsh-dialog-btn primary",
        type_="button",
        attrs=mark("promote-dialog-ok", [
          "dialog", "promote-confirm-dialog", "ok",
        ]),
        on_click=emit(PromoteConfirm),
        [@html.text("确认替换")],
      ),
      @html.button(
        class="dsh-dialog-btn",
        type_="button",
        attrs=mark("promote-dialog-cancel", [
          "dialog", "promote-confirm-dialog", "cancel",
        ]),
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
/// 删除确认框：打开时焦点落在确认键，Esc 关闭，关闭后焦点回到触发元素。
fn confirm_dialog(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let name = match find_row(model.rows, model.confirm_id) {
    Some(row) => row.name
    None => model.confirm_id
  }
  // 三处文案都照**点开那一刻记下来的模式**（§13.2）：确认框开着的时候设置被改了，
  // 这个框说的仍然是对那一次点击的判断。
  let hard = model.confirm_hard
  let title = (if hard { "彻底删除 " } else { "删除实例 " }) +
    name +
    "？"
  let mode = if hard {
    "删除后无法恢复。"
  } else {
    "删除后移入回收站，可以捞回来。"
  }
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
      attrs=mark("dialog-title", ["dialog", "confirm-dialog", "title"]).data_set(
        "mode",
        if hard {
          "hard"
        } else {
          "soft"
        },
      ),
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
        class=if hard {
          "dsh-dialog-btn danger"
        } else {
          "dsh-dialog-btn primary"
        },
        type_="button",
        attrs=mark("dialog-ok", ["dialog", "confirm-dialog", "ok"]).data_set(
          "mode",
          if hard {
            "hard"
          } else {
            "soft"
          },
        ),
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
/// 派生副本前的确认框（design/design-fixes.md §60.2）：副本里的相对软链接仍指向原处，
/// 「在副本里改插件 = 改原处那一份」这件事得先让人知道，再决定要不要派生。
fn fork_confirm_dialog(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let (name, count) = match find_row(model.rows, model.fork_confirm_id) {
    Some(row) => (row.name, row.external_links)
    None => (model.fork_confirm_id, 0)
  }
  let message = "这份副本里还有 " +
    count.to_string() +
    " 个软链接指向原 profile 之外（例如 .pi/agent 下的本地插件）。" +
    "在副本里改这些插件，等于改原处那一份，仍然会影响主机上的其他 profile。" +
    "要真正隔开，先把它们拷成实体文件再改。"
  let card = @html.div(class="dsh-dialog-card", [
    @html.h2(
      class="dsh-dialog-title",
      attrs=mark("fork-dialog-title", ["dialog", "fork-confirm-dialog", "title"]),
      "派生 " + name + " 的开发副本",
    ),
    @html.p(
      class="dsh-dialog-message",
      attrs=mark("fork-dialog-message", [
        "dialog", "fork-confirm-dialog", "message",
      ]).title("这一只有 " + count.to_string() + " 个外部软链接"),
      message,
    ),
    @html.div(class="dsh-dialog-foot", [
      @html.button(
        id="dsh-fork-dialog-ok",
        class="dsh-dialog-btn primary",
        type_="button",
        attrs=mark("fork-dialog-ok", ["dialog", "fork-confirm-dialog", "ok"]),
        on_click=emit(ForkConfirm),
        [@html.text("仍然派生")],
      ),
      @html.button(
        class="dsh-dialog-btn",
        type_="button",
        attrs=mark("fork-dialog-cancel", [
          "dialog", "fork-confirm-dialog", "cancel",
        ]),
        on_click=emit(ForkCancel),
        [@html.text("取消")],
      ),
    ]),
  ])
  dialog(
    "fork-confirm-dialog",
    "派生 " + name + " 的开发副本",
    emit(ForkCancel),
    emit.map(fn(key : @html.Keyboard) {
      if key.key() == "Escape" {
        ForkCancel
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
  let (name, dir, command, count) = match
    find_row(model.rows, model.repair_confirm_id) {
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
  let message = "将在 " +
    where_text +
    " 里执行 " +
    cmd_text +
    "，只补 node_modules。" +
    "装完会重新读一次这只 profile。"
  let card = @html.div(class="dsh-dialog-card", [
    @html.h2(
      class="dsh-dialog-title",
      attrs=mark("repair-dialog-title", [
        "dialog", "repair-confirm-dialog", "title",
      ]),
      "给 " + name + " 安装缺的包",
    ),
    @html.p(
      class="dsh-dialog-message",
      attrs=mark("repair-dialog-message", [
        "dialog", "repair-confirm-dialog", "message",
      ]).title(message + "\n缺 " + count.to_string() + " 个包"),
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
        attrs=mark("repair-dialog-cancel", [
          "dialog", "repair-confirm-dialog", "cancel",
        ]),
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
  let message = "移至共用 home 会把这份额外 home 里剩下的会话与插件状态移到回收站，可以捞回来。"
  let card = @html.div(class="dsh-dialog-card", [
    @html.h2(
      class="dsh-dialog-title",
      attrs=mark("home-dialog-title", ["dialog", "home-confirm-dialog", "title"]),
      "移至共用 home？",
    ),
    @html.p(
      class="dsh-dialog-message",
      attrs=mark("home-dialog-message", [
        "dialog", "home-confirm-dialog", "message",
      ]).title(where_text),
      message,
    ),
    @html.div(class="dsh-dialog-foot", [
      @html.button(
        id="dsh-home-confirm-ok",
        class="dsh-dialog-btn primary",
        type_="button",
        attrs=mark("home-dialog-ok", ["dialog", "home-confirm-dialog", "ok"]),
        on_click=emit(HomeDeisolateConfirm),
        [@html.text("移至共用 home")],
      ),
      @html.button(
        class="dsh-dialog-btn",
        type_="button",
        attrs=mark("home-dialog-cancel", [
          "dialog", "home-confirm-dialog", "cancel",
        ]),
        on_click=emit(HomeDeisolateCancel),
        [@html.text("取消")],
      ),
    ]),
  ])
  dialog(
    "home-confirm-dialog",
    "移至共用 home " + name + "？",
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
  let empty : SnapshotFact = {
    id: model.snapshot_confirm_snap,
    at: "",
    reason: "",
    files: 0,
    bytes: 0.0,
  }
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
    "会先用当前状态拍一张，再把 " +
    stamp +
    " 的三个文件写回去"
  }
  let card = @html.div(class="dsh-dialog-card", [
    @html.h2(
      class="dsh-dialog-title",
      attrs=mark("snapshot-dialog-title", [
        "dialog", "snapshot-confirm-dialog", "title",
      ]),
      title,
    ),
    @html.p(
      class="dsh-dialog-message",
      attrs=mark("snapshot-dialog-message", [
        "dialog", "snapshot-confirm-dialog", "message",
      ]),
      message,
    ),
    @html.p(
      class="dsh-dialog-note",
      attrs=mark("snapshot-dialog-what", [
        "dialog", "snapshot-confirm-dialog", "what",
      ]),
      name +
      " 的这一份：" +
      (if snap.reason == "" { "没有写原因" } else { snap.reason }) +
      "，" +
      (if snap.files == 0 {
        "文件数读不到"
      } else {
        snapshot_size_text(snap)
      }),
    ),
    @html.div(class="dsh-dialog-foot", [
      @html.button(
        id="dsh-snapshot-confirm-ok",
        class="dsh-dialog-btn primary",
        type_="button",
        attrs=mark("snapshot-dialog-ok", [
          "dialog", "snapshot-confirm-dialog", "ok",
        ]),
        on_click=emit(SnapshotRestoreConfirm),
        [@html.text("还原")],
      ),
      @html.button(
        class="dsh-dialog-btn",
        type_="button",
        attrs=mark("snapshot-dialog-cancel", [
          "dialog", "snapshot-confirm-dialog", "cancel",
        ]),
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
      attrs=mark("cli-help-message", ["dialog", "cli-help", "message"]).title(
        home,
      ),
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
        "磁盘上的目录名：" +
        dir_name +
        "（读数里没有它的 home，拼不出完整路径）"
      } else {
        "磁盘上的目录：" +
        row.home_path +
        "/profiles/" +
        dir_name +
        "（改名就是改这一段的最后一级）"
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
        attrs=mark("rename-dir", ["dialog", "rename-dialog", "dir"]).title(
          dir_hint,
        ),
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
      [icon("note-text-outline", size=14), @html.text("编辑备注 " + name)],
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
/// 派生拷贝的进度框（§72）。拷完由轮询把 active 置假、框自动收掉；
/// 成功与失败仍由派生那条请求的回执去说，这里只说「拷到哪儿了」。
fn fork_progress_dialog(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let name = if model.fork_progress_name == "" {
    "副本"
  } else {
    model.fork_progress_name
  }
  let total = model.fork_progress_total
  let files = model.fork_progress_files
  let pct = if total <= 0 { 0 } else { files * 100 / total }
  let bucket = pct / 10 * 10
  let card = @html.div(class="dsh-dialog-card dsh-fork-progress", [
    @html.h2(
      class="dsh-dialog-title",
      attrs=mark("fork-progress-title", ["dialog", "fork-progress", "title"]),
      "正在派生 " + name,
    ),
    @html.p(
      class="dsh-dialog-message",
      attrs=mark("fork-progress-count", ["dialog", "fork-progress", "count"]),
      if total <= 0 {
        "正在数要拷多少文件…"
      } else {
        "正在拷贝文件 " + files.to_string() + " / " + total.to_string()
      },
    ),
    @html.div(
      class="dsh-fork-progress-track",
      attrs=mark("fork-progress-track", ["dialog", "fork-progress", "track"])
        .role("progressbar")
        .aria_valuenow(pct.to_string()),
      [
        @html.div(
          class="dsh-fork-progress-fill step-" + bucket.to_string(),
          attrs=mark("fork-progress-fill", ["dialog", "fork-progress", "fill"]).data_set(
            "pct",
            pct.to_string(),
          ),
          @html.nothing,
        ),
      ],
    ),
    @html.p(
      class="dsh-dialog-message dsh-fork-progress-note",
      "带 node_modules 一起拷；拷完会自动隔离到它自己的 home",
    ),
    @html.div(class="dsh-dialog-foot", [
      @html.span(class="dsh-dialog-foot-note", "拷完这里会自己关掉"),
    ]),
  ])
  dialog(
    "fork-progress-dialog",
    "正在派生 " + name,
    @cmd.none,
    emit.map(fn(key : @html.Keyboard) {
      if key.key() == "Escape" {
        Noop
      } else {
        Noop
      }
    }),
    card,
  )
}
