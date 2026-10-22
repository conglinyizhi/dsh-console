// 启动变量（design/design-fixes.md §61.3 / §62.3）的写入口与那几条回执。
//
// 每条写动作都走同一套路：取出这个作用域的那一份表 → 改一行 → **整份**发 save-env
// （契约就是整份替换）→ 成功之后重读设置那份读数（env 段与 options 跟着回来）。
// 界面不本地记账：失败时页面停在读数里的样子，不会出现「看着改了、其实没存下」。
//
// 生效方式（§62.2 的 options）是**全局**的一项：随 global 那张表一起发，profile 那张不动它。
// 两项选项的控件在开关/单选被点的那一刻先翻界面（不然那一下看着像没点上），
// 失败了由 EnvSaved 重读设置，读数一回来就退回文件里的那份。
//
// 值可能含密钥，所以这里有一条硬规矩：回执与提示条只说键名与生效方式（§61.4 第 4 条），
// 任何一句拼接都不许带上值 —— 后端审计同样只记键名与两个 options。

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
  // 生效方式只在「写全局那张表」时带上：它是全局的一项（§62.2），profile 那张不动它。
  // 读不到 options 段就不带 —— 旧后端的参数 allow-list 里没有 options，带了整枪会被拒。
  let options = if target.scope == "global" && model.env_options_known {
    "{\"inherit\":" +
    (if model.env_inherit { "true" } else { "false" }) +
    ",\"merge\":" +
    json_text_literal(model.env_merge) +
    "}"
  } else {
    ""
  }
  (
    model,
    env_save_cmd(
      target.scope,
      env_put_body(target.scope, target.home, target.profile, kept, options~),
      emit,
    ),
  )
}

///|
/// 改生效方式之后那一枪：把全局那张表连同新的 options 一起写回去。
///
/// 为什么连表一起发：save-env 的契约是「整份替换这个作用域」，只发 options 没有那条路。
/// 表里那些值原样带回去（保留键在这一步被剔掉，见 env_save）—— 一个字节都不改。
fn env_save_options(model : Model, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  let target = env_target_global()
  env_save(model, target, env_entries_of(model, target), emit)
}

///|
/// 「继承系统环境变量」开关与「同名变量：覆盖 / 追加」两枚单选（§62.3）。
///
/// 先翻界面再发请求：这是一次点击，等回执再翻的话那一下看着像没点上，
/// 而回执是一条本地 GET，几十毫秒就回来了。失败时 EnvSaved 重读设置把它退回去。
fn handle_env_options(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    EnvInheritToggled(next) =>
      if !model.env_options_known {
        (model, @cmd.none)
      } else {
        env_save_options({ ..model, env_inherit: next, }, emit)
      }
    EnvMergePicked(merge) =>
      if !model.env_options_known || (merge != "override" && merge != "append") {
        (model, @cmd.none)
      } else {
        env_save_options({ ..model, env_merge: merge, }, emit)
      }
    _ => (model, @cmd.none)
  }
}

///|
/// EnvDraft：值输入框里的原文（还改没保存）。
fn handle_env_draft(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    EnvDraft(scope, key, text) =>
      match env_target_for_scope(model, scope) {
        Some(target) =>
          (
            {
              ..model,
              env_draft: env_draft_put(
                model.env_draft,
                target.scope_id,
                key,
                text,
              ),
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
fn handle_env_commit(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
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
          let unchanged = match
            env_entry_of_scope(model, target.scope_id, key) {
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
            env_draft: env_draft_put(
              model.env_draft,
              target.scope_id,
              key,
              text,
            ),
          }
          env_save(next, target, env_entries_with(stored, key, text), emit)
        }
      }
    _ => (model, @cmd.none)
  }
}

///|
/// EnvDelete：删掉一行（整行从文件里消失）。
fn handle_env_delete(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    EnvDelete(scope, key) =>
      match env_target_for_scope(model, scope) {
        None => (model, @cmd.none)
        Some(target) =>
          if env_is_reserved(model, key) {
            (
              notice_err(model, key + " 由控制台自己管，删不了"),
              @cmd.none,
            )
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
fn handle_env_add(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
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
            env_entries_with(
              env_entries_of(model, target),
              key,
              model.env_add_value,
            ),
            emit,
          )
        }
      }
    _ => (model, @cmd.none)
  }
}

///|
/// 「添加一行」那两格输入。它们不属于任何一行，单独两格存。
fn handle_env_add_input(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    EnvAddKeyInput(text) => ({ ..model, env_add_key: text, }, @cmd.none)
    EnvAddValueInput(text) => ({ ..model, env_add_value: text, }, @cmd.none)
    _ => (model, @cmd.none)
  }
}

///|
/// EnvReveal：显示 / 隐藏一个值。只改本地状态，一个字节都不写文件。
fn handle_env_reveal(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    EnvReveal(scope, key) =>
      match env_target_for_scope(model, scope) {
        None => (model, @cmd.none)
        Some(target) => {
          // 三态：现在露着 → 记「明确隐藏」（"!" 前缀）；现在蒙着 → 记「明确显示」
          let id = env_shown_id(target, key)
          let hidden_id = "!" + id
          let entries = env_entries_of(model, target)
          let mut value = ""
          for pair in entries {
            if pair.0 == key {
              value = pair.1
            }
          }
          let now_shown = env_revealed(model, target, key, value)
          let shown : Array[String] = []
          for item in model.env_shown {
            if item != id && item != hidden_id {
              shown.push(item)
            }
          }
          shown.push(if now_shown { hidden_id } else { id })
          ({ ..model, env_shown: shown, }, @cmd.none)
        }
      }
    _ => (model, @cmd.none)
  }
}

///|
/// 打开抽屉里「这只 profile 的启动变量」：两格「添加一行」清空 ——
/// 它们属于上一次摆着的那张表，带过来会让新对话框里凭空多半行输入。
fn handle_env_profile_open(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    // 解锁那一格跟着清（M）：只读是**每一次打开**的默认，不跟着上一只 profile 一起过去。
    EnvProfileOpen(id) =>
      (
        {
          ..model,
          env_open: id,
          env_add_key: "",
          env_add_value: "",
          env_edit_unlocked: false,
        },
        @cmd.none,
      )
    _ => (model, @cmd.none)
  }
}

///|
fn handle_env_profile_close(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    EnvProfileClose =>
      (
        {
          ..model,
          env_open: "",
          env_add_key: "",
          env_add_value: "",
          env_edit_unlocked: false,
        },
        @cmd.none,
      )
    _ => (model, @cmd.none)
  }
}

///|
/// 只读档上那颗「仍然修改」（M）：只翻本地一格，不写任何读数。
///
/// 解锁之后表格切回**这一只覆盖的那张表**（可编辑那一份），焦点送到「添加一行」的
/// 键名输入框 —— 解锁那一枪之后原来那颗按钮就没了，焦点不能掉到 body 上。
/// 那一格渲染出来的 id 带作用域（dsh-env-add-key-profile / -global），见 view_env 的 env_add_row。
fn handle_env_edit_unlock(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    EnvEditUnlock =>
      (
        { ..model, env_edit_unlocked: true, },
        focus_after_render("dsh-env-add-key-profile"),
      )
    _ => (model, @cmd.none)
  }
}

///|
/// 对话框里那一只是谁（提示条里要用它的名字）。
fn env_open_name(model : Model) -> String {
  match find_row(model.rows, model.env_open) {
    Some(row) => if row.name == "" { "这只 profile" } else { row.name }
    None => "这只 profile"
  }
}

///|
/// save-env 的回执。
///
/// 成功 → 一句短提示（§62.3）：全局那句必须带「下一次启动生效」与当前生效方式，
/// 因为它们说的是「改了之后什么时候、按哪种方式起」。然后**重读设置**：
/// 那才是这份表与 options 的真样子（后端把整个文件读回来，顺序、跨 profile 的改动都以它为准）。
///
/// 失败 → 常驻提示条，回执原文进悬停与审计；同一个作用域的草稿退回读数里的值。
/// 另外**重读一次设置**：生效方式那两项是先翻界面再发的，不重读就会停在「看着改了、
/// 其实没存下」的样子 —— 那正是这次重读要退回去的东西。
fn handle_env_saved(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    EnvSaved(scope, res) => {
      let (ok, note) = interpret_http(res)
      let hint = if model.env_path == "" {
        ""
      } else {
        "落在 " + model.env_path
      }
      if ok {
        // 全局那句带生效方式（§62.3）；读不到 options 段的后端只说「下一次启动生效」——
        // 拼一个它其实没读到的模式进去，就成了一句凭缺省猜的话
        let text = if scope == "global" {
          if model.env_options_known {
            "全局启动变量已保存（" +
            env_mode_text(model) +
            "），下一次启动生效"
          } else {
            "全局启动变量已保存，下一次启动生效"
          }
        } else {
          env_open_name(model) +
          " 的启动变量已保存，下一次启动生效"
        }
        (
          notice_ok(
            { ..model, env_add_key: "", env_add_value: "", },
            text,
            hint,
          ),
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
          notice_failed_action(
            { ..model, env_draft: drafts, },
            "启动变量没保存：" + note,
          ),
          settings_get_cmd(emit),
        )
      }
    }
    _ => (model, @cmd.none)
  }
}

///|
/// N8：全局启动变量专窗 + 长值展开 + 「填入本机代理建议」。
fn handle_env_dialog(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    EnvGlobalOpen =>
      (
        { ..model, env_global_open: true, env_expanded: [], },
        focus_after_render("dsh-env-global-close"),
      )
    EnvGlobalClose => ({ ..model, env_global_open: false, }, @cmd.none)
    EnvGotoProcess => {
      // handle_settings_group_picked 只改分组与路由，不切页：从总览打开框再点这条链接，
      // 于是只关了框、人还站在总览（§99 实测）。这里把页一起切到设置并推路由。
      let closed = {
        ..model,
        env_global_open: false,
        env_open: "",
        page: Settings,
        settings_group: "process",
      }
      (closed, push_route(route_url(Settings, "process", closed.log_source)))
    }
    EnvToggleExpand(key) => {
      let next : Array[String] = []
      let mut had = false
      for item in model.env_expanded {
        if item == key {
          had = true
        } else {
          next.push(item)
        }
      }
      if !had {
        next.push(key)
      }
      ({ ..model, env_expanded: next, }, @cmd.none)
    }
    _ => (model, @cmd.none)
  }
}
