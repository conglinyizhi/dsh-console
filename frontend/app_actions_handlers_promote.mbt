// 整体替换与新建实例类 Msg 的回执落地（含命令行型说明框）。

///|
/// PromoteOpen 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_promote_open(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    PromoteOpen(id) => 
      match find_row(model.rows, id) {
        None => (model, @cmd.none)
        Some(row) =>
          match row.profile_name {
            None => (notice_err(model, row.name + " 的目录名读不到，没法替换配置"), @cmd.none)
            Some(_) =>
              (
                {
                  ..model,
                  drawer_id: "",
                  promote_row: id,
                  // 关掉侧栏之后焦点回这张卡（抽屉已经收了，那颗按钮不在页面上了）
                  promote_return: card_id(id),
                  promote_source: "",
                  promote_preview: None,
                  promote_preview_error: "",
                  promote_loading: false,
                  promote_confirm: false,
                },
                focus_after_render(promote_close_id()),
              )
          }
      }
    // 选一只源：就地发 promote-preview（只读），回执之前先摆「正在读差异…」
    _ => (model, @cmd.none)
  }
}

///|
/// PromoteSourcePicked 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_promote_source_picked(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    PromoteSourcePicked(name) => 
      match find_row(model.rows, model.promote_row) {
        None => (model, @cmd.none)
        Some(row) =>
          match row.profile_name {
            None => (notice_err(model, row.name + " 的目录名读不到，没法替换配置"), @cmd.none)
            Some(target) =>
              (
                {
                  ..model,
                  promote_source: name,
                  promote_preview: None,
                  promote_preview_error: "",
                  promote_loading: true,
                  promote_confirm: false,
                },
                promote_preview_cmd(name, target, emit),
              )
          }
      }
    // 预览回执：成功就把四段差异摆出来，失败把原因留在侧栏里原位（不发全局提示）
    _ => (model, @cmd.none)
  }
}

///|
/// PromotePreviewDone 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_promote_preview_done(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    PromotePreviewDone(res) => {
      let next = match res {
        Err(err) =>
          {
            ..model,
            promote_loading: false,
            promote_preview: None,
            promote_preview_error: "这一步没发出去（" + describe(err) + "）",
          }
        Ok(text) =>
          match parse_promote_preview(text) {
            Ok(preview) =>
              {
                ..model,
                promote_loading: false,
                promote_preview: Some(preview),
                promote_preview_error: "",
              }
            Err(reason) =>
              {
                ..model,
                promote_loading: false,
                promote_preview: None,
                promote_preview_error: reason,
              }
          }
      }
      // 焦点跟着这一屏走：能应用就落在「确认替换」上，不能就落在关闭键上
      let focus = match next.promote_preview {
        Some(preview) =>
          if preview.blockers.length() == 0 && model.promote_row != "" {
            "dsh-promote-apply"
          } else {
            promote_close_id()
          }
        None => promote_close_id()
      }
      (next, focus_after_render(focus))
    }
    // 「确认替换」：只开框，不发请求（破坏性动作要先看一眼标题与正文）
    _ => (model, @cmd.none)
  }
}

///|
/// PromoteConfirmOpen 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_promote_confirm_open(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    PromoteConfirmOpen => 
      match model.promote_preview {
        Some(preview) =>
          if preview.blockers.length() > 0 {
            (model, @cmd.none)
          } else {
            ({ ..model, promote_confirm: true }, focus_after_render(promote_confirm_ok_id()))
          }
        None => (model, @cmd.none)
      }
    _ => (model, @cmd.none)
  }
}

///|
/// PromoteConfirmCancel 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_promote_confirm_cancel(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    PromoteConfirmCancel => (
      { ..model, promote_confirm: false },
      focus_after_render("dsh-promote-apply"),
    )
    // 真的替换：body 顶层带 confirm: PROMOTE；回执走 HttpDone（成功后重读读数）
    _ => (model, @cmd.none)
  }
}

///|
/// PromoteConfirm 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_promote_confirm(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    PromoteConfirm => 
      match find_row(model.rows, model.promote_row) {
        None => (model, @cmd.none)
        Some(row) =>
          match row.profile_name {
            None => (notice_err(model, row.name + " 的目录名读不到，没法替换配置"), @cmd.none)
            Some(target) =>
              if model.promote_source == "" {
                (notice_err(model, "还没选源，替换没发出去"), @cmd.none)
              } else {
                let pairs : Array[(String, String)] = [
                  ("from", json_text_literal(model.promote_source)),
                  ("to", json_text_literal(target)),
                ]
                let (next, cmd) = send_action(
                  { ..model, promote_confirm: false },
                  model.promote_row,
                  "promote-profile",
                  target,
                  "替换配置",
                  params_of(pairs),
                  emit,
                  confirm="PROMOTE",
                )
                (next, cmd)
              }
          }
      }
    // 回去重新选源：清掉预览，卡片那一屏重新摆出来
    _ => (model, @cmd.none)
  }
}

///|
/// PromoteBack 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_promote_back(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    PromoteBack => (
      {
        ..model,
        promote_preview: None,
        promote_preview_error: "",
        promote_loading: false,
        promote_source: "",
      },
      focus_after_render(promote_close_id()),
    )
    _ => (model, @cmd.none)
  }
}

///|
/// PromoteClose 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_promote_close(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    PromoteClose => 
      if model.promote_row == "" {
        (model, @cmd.none)
      } else {
        (
          {
            ..model,
            promote_row: "",
            promote_return: "",
            promote_source: "",
            promote_preview: None,
            promote_preview_error: "",
            promote_loading: false,
            promote_confirm: false,
          },
          focus_after_render(model.promote_return),
        )
      }
    // 点整张卡：开抽屉，焦点进抽屉里的关闭键。
    // 卡是 role=button + tabindex=0，键盘也能开（Enter / 空格，见 view_overview 的 card_attrs）。
    _ => (model, @cmd.none)
  }
}

///|
/// CliHelpOpen 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_cli_help_open(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    CliHelpOpen(id) => ({ ..model, cli_help_id: id }, focus_after_render("dsh-cli-help-ok"))
    _ => (model, @cmd.none)
  }
}

///|
/// CliHelpClose 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_cli_help_close(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    CliHelpClose => ({ ..model, cli_help_id: "" }, @cmd.none)
    _ => (model, @cmd.none)
  }
}

///|
/// NewInstanceOpen 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_new_instance_open(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    NewInstanceOpen => {
      let first = new_instance_first_usable(model)
      let default_base = new_instance_no_usable_source(model)
      (
        {
          ..model,
          new_open: true,
          new_source: "",
          new_base: default_base,
          new_name_draft: if default_base { new_instance_base_name(model) } else { "" },
          new_name_dirty: false,
          new_error: "",
          new_busy: false,
        },
        if default_base {
          // 勾上了：名字格已经预填 base-NN，焦点与光标送进去，接着打字就是改名
          focus_select_after_render(new_instance_name_id())
        } else if first == "" {
          // 读数还没到、或一只可用的都没有：焦点落在复选框上 ——
          // 它是这一刻框里唯一能点的东西（「创建」还锁着，「取消」谁都知道在哪儿）。
          focus_after_render(new_instance_base_id())
        } else {
          focus_after_render(new_instance_card_id(first))
        },
      )
    }
    // 取消 / Esc / 点遮罩：框关掉，草稿与错误一起清掉，焦点回页头那颗按钮。
    // 创建中不许关：请求已经出去了，关掉框会让人以为没创建（回执照样会把它关掉）。
    _ => (model, @cmd.none)
  }
}

///|
/// NewInstanceClose 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_new_instance_close(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    NewInstanceClose => 
      if model.new_busy {
        (model, @cmd.none)
      } else {
        (
          {
            ..model,
            new_open: false,
            new_source: "",
            new_base: false,
            new_name_draft: "",
            new_name_dirty: false,
            new_error: "",
          },
          focus_after_render(new_instance_btn_id()),
        )
      }
    // 选中一只源：名字默认填 <源>-dev。已经亲手改过名字的（不等于上一个默认值）就不覆盖，
    // 换源不该把人家刚打的字抹掉。
    _ => (model, @cmd.none)
  }
}

///|
/// NewInstanceStatePicked 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_new_instance_state_picked(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    NewInstanceStatePicked(name) => {
      let draft = model.new_name_draft.trim().to_owned()
      let keep = draft != "" &&
        !(model.new_source != "" && draft == model.new_source + "-dev")
      let next = {
        ..model,
        new_source: name,
        // 选了具体的源就走派生：从基础模板那一档退出来
        new_base: false,
        new_name_draft: if keep { model.new_name_draft } else { name + "-dev" },
        new_error: "",
      }
      // 焦点与光标送进名字那一格，默认那段选上：接着打字就是改名
      (next, focus_select_after_render(new_instance_name_id()))
    }
    // 名字框的输入事件：脏标记置位（§21）。勾上复选框时靠它判断「用户已经输入过任何字符」——
    // 预填不走这条消息，所以预填不会把标记点亮。
    _ => (model, @cmd.none)
  }
}

///|
/// NewInstanceNameInput 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_new_instance_name_input(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    NewInstanceNameInput(text) => (
      { ..model, new_name_draft: text, new_name_dirty: true, new_error: "" },
      @cmd.none,
    )
    // 创建：走既有 fork-profile（新副本默认隔离）。名字按输入框的原话发，
    // 空名字不带 newName —— 后端自己会按 <源>-dev 起一个。
    _ => (model, @cmd.none)
  }
}

///|
/// NewInstanceConfirm 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_new_instance_confirm(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    NewInstanceConfirm => {
      let source = model.new_source
      let base = model.new_base
      let draft = model.new_name_draft.trim().to_owned()
      if (!base && source == "") || draft == "" || model.new_busy {
        (
          {
            ..model,
            new_error: if !base && source == "" {
              "先选一只源配置，或者勾上「从基础实例开始」"
            } else {
              "名字不能为空"
            },
          },
          @cmd.none,
        )
      } else {
        (
          { ..model, new_busy: true, new_error: "" },
          if base {
            // 源是基础模板：不派生，直接用 dsh 自带的基础模板新建一份
            base_profile_cmd(draft, emit)
          } else {
            new_instance_cmd(source, draft, emit)
          },
        )
      }
    }
    // 勾上「从基础实例开始」（§21）：源换成基础模板、选中的源卡让位（卡片自己由视图锁上）、
    // 名字**只在它现在是空的、而且用户一个字都没输入过**时预填 base-<两位序号>；
    // 焦点进名字格。勾掉：卡片恢复可选，名字框一个字都不动 —— 两条都不看文本框的内容去还原 / 清空。
    _ => (model, @cmd.none)
  }
}

///|
/// NewInstanceBaseToggled 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_new_instance_base_toggled(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    NewInstanceBaseToggled(on) => 
      if model.new_busy {
        (model, @cmd.none)
      } else if on {
        let prefill = !model.new_name_dirty && model.new_name_draft == ""
        let draft = if prefill {
          new_instance_base_name(model)
        } else {
          model.new_name_draft
        }
        (
          {
            ..model,
            new_source: "",
            new_base: true,
            new_name_draft: draft,
            new_error: "",
          },
          // 刚预填的那一段整段选上（接着打字就是改名）；用户自己的字只落焦点，不动选区
          if prefill {
            focus_select_after_render(new_instance_name_id())
          } else {
            focus_after_render(new_instance_name_id())
          },
        )
      } else {
        ({ ..model, new_base: false, new_error: "" }, @cmd.none)
      }
    _ => (model, @cmd.none)
  }
}

///|
/// NewInstanceDone 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_new_instance_done(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    NewInstanceDone(res) => {
      let (next, cmd) = new_instance_settled(model, res, emit)
      // 失败时把焦点拉回名字那一格：要改的就是那里
      if next.new_error != "" {
        (next, @cmd.batch([cmd, focus_select_after_render(new_instance_name_id())]))
      } else {
        (next, cmd)
      }
    }
    _ => (model, @cmd.none)
  }
}

///|
/// NewInstanceBaseDone 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_new_instance_base_done(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    NewInstanceBaseDone(res) => {
      let (next, cmd) = base_profile_settled(model, res, emit)
      // 失败同样不关框、焦点回名字格（同名 conflict 就是在那儿改）
      if next.new_error != "" {
        (next, @cmd.batch([cmd, focus_select_after_render(new_instance_name_id())]))
      } else {
        (next, cmd)
      }
    }

    // 删除也是真实动作：POST delete-profile。删掉的行由重读 profiles 之后消失，
    // 不在这里先手动抹掉 —— 后端失败时列表不该少一行。
    _ => (model, @cmd.none)
  }
}

///|
/// TrashRestore 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_trash_restore(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    TrashRestore(dir) => {
      let params = params_of([("dir", json_text_literal(dir))])
      send_action(
        model,
        trash_row_id(dir),
        "restore-from-trash",
        trash_profile_of(model, dir),
        "恢复",
        params,
        emit,
      )
    }
    // 真删之前先开确认框（走既有那套 dialog()），焦点落在确认键上
    _ => (model, @cmd.none)
  }
}

///|
/// TrashPurgeOpen 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_trash_purge_open(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    TrashPurgeOpen(dir, return_id) => (
      { ..model, trash_purge_dir: dir, trash_purge_return: return_id },
      focus_after_render("dsh-purge-ok"),
    )
    // 彻底删除：confirm 走顶层（缺了后端给 bad-params），与硬删同一风险等级
    _ => (model, @cmd.none)
  }
}

///|
/// TrashPurgeConfirm 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_trash_purge_confirm(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    TrashPurgeConfirm => {
      let dir = model.trash_purge_dir
      let return_id = model.trash_purge_return
      if dir == "" {
        (model, @cmd.none)
      } else {
        let params = params_of([("dir", json_text_literal(dir))])
        let (next, cmd) = send_action(
          { ..model, trash_purge_dir: "" },
          trash_row_id(dir),
          "purge-trash-item",
          trash_profile_of(model, dir),
          "彻底删除",
          params,
          emit,
          confirm="PURGE",
        )
        (next, @cmd.batch([cmd, focus_after_render(return_id)]))
      }
    }
    _ => (model, @cmd.none)
  }
}

///|
/// TrashPurgeCancel 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_trash_purge_cancel(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    TrashPurgeCancel => (
      { ..model, trash_purge_dir: "" },
      focus_after_render(model.trash_purge_return),
    )
    // ── 维护页（作业台） ──
    // 打开版本侧栏（§12.1）：清空搜索框、焦点进搜索框，并再读一次缓存。
    // 那一条接口现在只读后端进程内的缓存（秒回），所以「每次打开都读」不再是一笔等待。
    // 过滤与排序**不重置**：它们是使用者上一次挑的读法，关掉再开回来还该是那一套。
    _ => (model, @cmd.none)
  }
}

