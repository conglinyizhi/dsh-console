// 改名 / 删除 / 备注 / 隔离 home / 快照 / 回收站类 Msg 的回执落地。

///|
/// DeleteOpen 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_delete_open(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    DeleteOpen(id, return_id, hard) => (
      { ..model, confirm_id: id, confirm_return: return_id, confirm_hard: hard },
      focus_after_render("dsh-confirm-ok"),
    )
    // 移回共用 home 的确认：确认之后真发 deisolate-profile（confirm 走 body 顶层），
    // 关框与焦点回触发元素与删除确认框同一套。
    _ => (model, @cmd.none)
  }
}

///|
/// HomeDeisolateOpen 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_home_deisolate_open(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    HomeDeisolateOpen(id, return_id) => (
      {
        ..model,
        drawer_id: "",
        home_confirm_id: id,
        home_confirm_return: return_id,
      },
      focus_after_render("dsh-home-confirm-ok"),
    )
    _ => (model, @cmd.none)
  }
}

///|
/// HomeDeisolateConfirm 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_home_deisolate_confirm(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    HomeDeisolateConfirm => 
      match find_row(model.rows, model.home_confirm_id) {
        None => (
          { ..model, home_confirm_id: "" },
          focus_after_render(model.home_confirm_return),
        )
        Some(row) => {
          let params = params_of(profile_name_pairs(row))
          let return_id = model.home_confirm_return
          let confirm_id = model.home_confirm_id
          let (next, cmd) = send_action(
            {
              ..model,
              home_confirm_id: "",
              home_confirm_return: "",
              home_move_id: confirm_id,
            },
            confirm_id,
            "deisolate-profile",
            row.name,
            "移至共用 home",
            params,
            emit,
            confirm="DELETE",
          )
          (next, @cmd.batch([cmd, focus_after_render(return_id)]))
        }
      }
    _ => (model, @cmd.none)
  }
}

///|
/// HomeDeisolateCancel 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_home_deisolate_cancel(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    HomeDeisolateCancel => (
      { ..model, home_confirm_id: "" },
      focus_after_render(model.home_confirm_return),
    )
    // ── 配置历史（design/ops-maintenance-jobs.md §16.4）────────────
    // 创建快照是一条真实写动作：回执走全局提示，成功后重读读数 ——
    // 列表不在这里本地插一条，刷新的是读数，界面自己会变。
    _ => (model, @cmd.none)
  }
}

///|
/// SnapshotCreate 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_snapshot_create(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    SnapshotCreate(id) => 
      match find_row(model.rows, id) {
        None => (model, @cmd.none)
        Some(row) =>
          send_action(
            model,
            id,
            "snapshot-profile",
            row.name,
            "创建快照",
            params_of(profile_name_pairs(row)),
            emit,
          )
      }
    // 打开还原确认框：先把抽屉收掉（对话框在抽屉之上，背后那张留着没有意义），
    // 焦点回触发它的那张卡 —— 与删除 / 取消隔离同一套。
    _ => (model, @cmd.none)
  }
}

///|
/// SnapshotRestoreOpen 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_snapshot_restore_open(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    SnapshotRestoreOpen(id, snap, return_id) => (
      {
        ..model,
        drawer_id: "",
        snapshot_confirm_id: id,
        snapshot_confirm_snap: snap,
        snapshot_confirm_return: return_id,
      },
      focus_after_render("dsh-snapshot-confirm-ok"),
    )
    // 确认还原：params 带 profile 与 snapshot，二次确认串 RESTORE 走 body 顶层。
    _ => (model, @cmd.none)
  }
}

///|
/// SnapshotRestoreConfirm 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_snapshot_restore_confirm(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    SnapshotRestoreConfirm => 
      match find_row(model.rows, model.snapshot_confirm_id) {
        None => (
          {
            ..model,
            snapshot_confirm_id: "",
            snapshot_confirm_snap: "",
            snapshot_confirm_return: "",
          },
          focus_after_render(model.snapshot_confirm_return),
        )
        Some(row) => {
          let pairs = profile_name_pairs(row)
          pairs.push(("snapshot", json_text_literal(model.snapshot_confirm_snap)))
          let return_id = model.snapshot_confirm_return
          let confirm_id = model.snapshot_confirm_id
          let (next, cmd) = send_action(
            {
              ..model,
              snapshot_confirm_id: "",
              snapshot_confirm_snap: "",
              snapshot_confirm_return: "",
            },
            confirm_id,
            "restore-snapshot",
            row.name,
            "还原快照",
            params_of(pairs),
            emit,
            confirm="RESTORE",
          )
          (next, @cmd.batch([cmd, focus_after_render(return_id)]))
        }
      }
    _ => (model, @cmd.none)
  }
}

///|
/// SnapshotRestoreCancel 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_snapshot_restore_cancel(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    SnapshotRestoreCancel => (
      { ..model, snapshot_confirm_id: "", snapshot_confirm_snap: "" },
      focus_after_render(model.snapshot_confirm_return),
    )
    // ── 整体替换（design/ops-maintenance-jobs.md §17.3）────────────
    // 打开侧栏：先收抽屉（两个都是右侧浮层，叠着摆会互相挡），焦点进侧栏的关闭键。
    _ => (model, @cmd.none)
  }
}

///|
/// RenameInput 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_rename_input(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    RenameInput(text) => ({ ..model, rename_draft: text }, @cmd.none)
    // 改名不再是改一个显示字符串：它 POST rename-profile，改的是磁盘上的目录名。
    // 对话框照旧先关（语义没变），结果由提示条给出。
    _ => (model, @cmd.none)
  }
}

///|
/// RenameConfirm 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_rename_confirm(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    RenameConfirm => {
      let draft = model.rename_draft.trim().to_owned()
      let id = model.rename_id
      let return_id = model.rename_return
      if draft.length() == 0 {
        (model, @cmd.none)
      } else {
        let old = row_name(model, id)
        let params = match find_row(model.rows, id) {
          None => ""
          Some(row) =>
            match row.profile_name {
              None => ""
              Some(name) =>
                params_of([
                  ("profile", json_text_literal(name)),
                  ("newName", json_text_literal(draft)),
                ])
            }
        }
        let cleared = { ..model, rename_id: "", rename_draft: "" }
        let (next, cmd) = send_action(
          cleared,
          id,
          "rename-profile",
          old,
          "重命名",
          params,
          emit,
        )
        (next, @cmd.batch([cmd, focus_after_render(return_id)]))
      }
    }
    _ => (model, @cmd.none)
  }
}

///|
/// RenameCancel 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_rename_cancel(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    RenameCancel => (
      { ..model, rename_id: "", rename_draft: "" },
      focus_after_render(model.rename_return),
    )
    // 编辑备注：与重命名同一套（预填、Esc 取消、关闭后焦点回触发元素）。
    // 焦点落在备注框、光标推到文末 —— 这里是接着改，不是整段覆盖。
    // 与重命名 / 删除同一条口径（§30.1）：抽屉留着，关框之后焦点回抽屉里那颗「备注」。
    _ => (model, @cmd.none)
  }
}

///|
/// NoteOpen 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_note_open(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    NoteOpen(id) => (
      {
        ..model,
        note_open: id,
        note_draft: row_note(model, id),
        note_return: drawer_note_id(),
        note_error: "",
      },
      focus_end_after_render("dsh-note-input"),
    )
    _ => (model, @cmd.none)
  }
}

///|
/// NoteInput 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_note_input(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    NoteInput(text) => ({ ..model, note_draft: text, note_error: "" }, @cmd.none)
    // 保存失败**不关框**：后端给的原因（bad-params / io-error / not-authorized…）写在框里，
    // 用户改一改就能再存一次。关掉的话那句原因就成了一闪而过的提示条。
    _ => (model, @cmd.none)
  }
}

///|
/// NoteConfirm 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_note_confirm(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    NoteConfirm => 
      match find_row(model.rows, model.note_open) {
        // 框开着却找不到那一行（列表刚被重建掉）：把框收掉，不留一个悬空的编辑框
        None => (
          { ..model, note_open: "", note_draft: "", note_error: "", note_return: "" },
          @cmd.none,
        )
        Some(row) => {
          let pairs = note_pairs(row, model.note_draft)
          if pairs.length() == 0 {
            (
              {
                ..model,
                note_error: "这一行的读数里没有 profile 目录名，保存不了。没有目标就什么都没做",
              },
              @cmd.none,
            )
          } else {
            // 这一行不置忙：备注保存时卡片本身还能用，忙碌态只锁保存键
            (
              notice_clear({ ..model, note_saving: row.id, note_error: "" }),
              action_cmd(
                row.id,
                "set-profile-note",
                row.name,
                "保存备注",
                action_body("set-profile-note", params_of(pairs)),
                emit,
              ),
            )
          }
        }
      }
    _ => (model, @cmd.none)
  }
}

///|
/// NoteCancel 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_note_cancel(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    NoteCancel => {
      // 保存中不许关：请求已经出去了，关掉框会让人以为没存上（回执到了会把框关掉）
      if model.note_saving != "" {
        (model, @cmd.none)
      } else {
        let return_id = model.note_return
        (
          { ..model, note_open: "", note_draft: "", note_error: "", note_return: "" },
          focus_after_render(return_id),
        )
      }
    }
    // ── 新建实例框（design/design-fixes.md §19.1）─────────────
    // 开框：清掉上一次的错与草稿。没有可用源时「从基础实例开始」默认勾上（§21.4）：
    // 这时它是唯一能走的路，名字预填 base-NN、焦点直接进名字格。
    // 有可用源就照旧把焦点落在第一张可点的源卡上；读数还没落地时卡都点不了，落在复选框上。
    _ => (model, @cmd.none)
  }
}

///|
/// DeleteConfirm 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_delete_confirm(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    DeleteConfirm => {
      let target = model.confirm_id
      let return_id = model.confirm_return
      // 动词照记下来的模式说：彻底删除与进回收站是两件事，回执里说错就是骗人
      let verb = if model.confirm_hard { "彻底删除" } else { "删除" }
      let (next, cmd) = send_action(
        { ..model, confirm_id: "" },
        target,
        "delete-profile",
        row_name(model, target),
        verb,
        params_of(delete_pairs(model, target)),
        emit,
        confirm=delete_confirm_of(model),
      )
      (next, @cmd.batch([cmd, focus_after_render(return_id)]))
    }
    _ => (model, @cmd.none)
  }
}

///|
/// DeleteCancel 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_delete_cancel(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    DeleteCancel => (
      { ..model, confirm_id: "" },
      focus_after_render(model.confirm_return),
    )
    // ── 回收站 ─────────────────────────────────────────────
    // 恢复：把回收站里那一份移回 profile 目录。成功 / 失败都重读读数并出提示条，
    // 失败尤其要显示后端给的原因（已经有同名 profile 时是 conflict）。
    _ => (model, @cmd.none)
  }
}

