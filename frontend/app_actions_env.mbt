// 启动环境（design/design-fixes.md §61.3）的写入口与那几条回执。
//
// 每条写动作都走同一套路：取出这个作用域的那一份表 → 改一行 → **整份**发 save-env
// （契约就是整份替换）→ 成功之后重读设置那份读数（env 段跟着回来）。
// 界面不本地记账：失败时页面停在读数里的样子，不会出现「看着改了、其实没存下」。
//
// 值可能含密钥，所以这里有一条硬规矩：回执与提示条只说键名与条数（§61.4 第 4 条），
// 任何一句拼接都不许带上值 —— 后端审计同样只记键名。

///|
/// 消息里那个 scope 词（global / profile）→ 这一处作用域的身份。
/// profile 那一档的身份来自**开着的对话框**（model.env_open）：界面只摆得出一只，
/// 消息里不再带一遍 home / profile，两处一旦不一致就会写到另一只名下。
fn env_target_for_scope(model : Model, scope : String) -> EnvTarget? {
  if scope == "global" {
    Some(env_target_global())
  } else {
    env_target_open(model)
  }
}

///|
/// 把这个作用域整份写回去。
///
/// 保留键（DSH_HOME / PATH …）在这一步剔掉：后端 env_key_allowed 会为一枚保留键整枪拒掉
/// （§61.2），而界面上那一行是灰的、删不掉 —— 手改过 env.json 留下了这样的残条时，
/// 带着它发就成了「这张表再也存不了任何改动」的死循环。它本来也不会被注进子进程
/// （后端 env_for_spawn 同一张名单跳过），剔掉是对的；下一次保存顺带把它从文件里清走。
fn env_save(
  model : Model,
  target : EnvTarget,
  entries : Array[(String, String)],
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let kept = entries.filter(fn(pair) { !env_is_reserved(model, pair.0) })
  (
    model,
    env_save_cmd(
      target.scope,
      env_put_body(target.scope, target.home, target.profile, kept),
      emit,
    ),
  )
}

///|
/// EnvDraft：值输入框里的原文（还改没保存）。
fn handle_env_draft(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    EnvDraft(scope, key, text) =>
      match env_target_for_scope(model, scope) {
        Some(target) => (
          {
            ..model,
            env_draft: env_draft_put(model.env_draft, target.scope_id, key, text),
          },
          @cmd.none,
        )
        None => (model, @cmd.none)
      }
    _ => (model, @cmd.none)
  }
}

///|
/// EnvCommit：改值即保存。与读数里的值一样就不发请求（点一下回车不该写一次文件）。
///
/// 草稿先留着：保存回来之前控件上是刚填的那个值，读数跟上来之后由 env_prune_drafts 收掉。
fn handle_env_commit(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    EnvCommit(scope, key, text) =>
      match env_target_for_scope(model, scope) {
        None => (model, @cmd.none)
        Some(target) => {
          let problem = env_key_problem(model, key)
          if problem != "" {
            return (notice_err(model, problem), @cmd.none)
          }
          let stored = env_entries_of(model, target)
          let unchanged = match env_entry_of_scope(model, target.scope_id, key) {
            Some(value) => value == text
            None => false
          }
          if unchanged {
            // 值没变：把草稿收掉就行，别为了「按了一次回车」写一次文件
            return (
              {
                ..model,
                env_draft: model.env_draft.filter(fn(draft) {
                  draft.scope != target.scope_id || draft.key != key
                }),
              },
              @cmd.none,
            )
          }
          let next = {
            ..model,
            env_draft: env_draft_put(model.env_draft, target.scope_id, key, text),
          }
          env_save(next, target, env_entries_with(stored, key, text), emit)
        }
      }
    _ => (model, @cmd.none)
  }
}

///|
/// EnvDelete：删掉一行（整行从文件里消失）。
fn handle_env_delete(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    EnvDelete(scope, key) =>
      match env_target_for_scope(model, scope) {
        None => (model, @cmd.none)
        Some(target) =>
          if env_is_reserved(model, key) {
            (notice_err(model, key + " 由控制台自己管，删不了"), @cmd.none)
          } else {
            env_save(
              model,
              target,
              env_entries_without(env_entries_of(model, target), key),
              emit,
            )
          }
      }
    _ => (model, @cmd.none)
  }
}

///|
/// EnvAdd：底部那两格输入 → 一行。已经在表里的键原位换值（不重复两行）。
fn handle_env_add(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    EnvAdd(scope) =>
      match env_target_for_scope(model, scope) {
        None => (model, @cmd.none)
        Some(target) => {
          let key = model.env_add_key.trim().to_owned()
          let problem = env_key_problem(model, key)
          if problem != "" {
            return (notice_err(model, problem), @cmd.none)
          }
          env_save(
            model,
            target,
            env_entries_with(env_entries_of(model, target), key, model.env_add_value),
            emit,
          )
        }
      }
    _ => (model, @cmd.none)
  }
}

///|
/// 「添加一行」那两格输入。它们不属于任何一行，单独两格存。
fn handle_env_add_input(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    EnvAddKeyInput(text) => ({ ..model, env_add_key: text }, @cmd.none)
    EnvAddValueInput(text) => ({ ..model, env_add_value: text }, @cmd.none)
    _ => (model, @cmd.none)
  }
}

///|
/// EnvReveal：显示 / 隐藏一个值。只改本地状态，一个字节都不写文件。
fn handle_env_reveal(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    EnvReveal(scope, key) =>
      match env_target_for_scope(model, scope) {
        None => (model, @cmd.none)
        Some(target) => {
          let id = env_shown_id(target, key)
          let revealed = model.env_shown.contains(id)
          let shown : Array[String] = []
          for item in model.env_shown {
            if item != id {
              shown.push(item)
            }
          }
          if !revealed {
            shown.push(id)
          }
          ({ ..model, env_shown: shown }, @cmd.none)
        }
      }
    _ => (model, @cmd.none)
  }
}

///|
/// 打开抽屉里「这只 profile 的启动环境」：两格「添加一行」清空 ——
/// 它们属于上一次摆着的那张表，带过来会让新对话框里凭空多半行输入。
fn handle_env_profile_open(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    EnvProfileOpen(id) => (
      { ..model, env_open: id, env_add_key: "", env_add_value: "" },
      @cmd.none,
    )
    _ => (model, @cmd.none)
  }
}

///|
fn handle_env_profile_close(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    EnvProfileClose => (
      { ..model, env_open: "", env_add_key: "", env_add_value: "" },
      @cmd.none,
    )
    _ => (model, @cmd.none)
  }
}

///|
/// save-env 的回执。
///
/// 成功 → 用后端那句 note 发一条短提示（只有键名与条数），并**重读设置**：
/// 那才是这份表的真样子（后端把整个文件读回来，顺序、跨 profile 的改动都以它为准）。
/// 失败 → 常驻提示条，回执原文进悬停与审计；同一个作用域的草稿退回读数里的值 ——
/// 停在「看着改了、其实没存下」比不做还糟。
fn handle_env_saved(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    EnvSaved(scope, res) => {
      let (ok, note) = interpret_http(res)
      if ok {
        (
          notice_ok({ ..model, env_add_key: "", env_add_value: "" }, note, ""),
          settings_get_cmd(emit),
        )
      } else {
        let target = env_target_for_scope(model, scope)
        let drafts = match target {
          Some(item) =>
            model.env_draft.filter(fn(draft) { draft.scope != item.scope_id })
          None => model.env_draft
        }
        (
          notice_failed_action({ ..model, env_draft: drafts }, "启动环境没保存：" + note),
          @cmd.none,
        )
      }
    }
    _ => (model, @cmd.none)
  }
}
