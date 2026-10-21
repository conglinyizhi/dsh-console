// 启动变量（design/design-fixes.md §61.3 / §62.3）的界面。
//
// 两处摆的是同一张表，只是作用域不同：
//   - 设置页**「进程」组**里的「全局启动变量」：scope = global，写进 env.json 的 global 段
//     （§62.1 撤掉了它单独那一组：它说的是「怎么起这一只进程」，与那组的两条设置项是同一件事）；
//   - 抽屉里「<profile> 的启动变量」对话框：scope = profile，
//     写进 profiles["<home>|<profile>"]，只影响这一只（同名不同 home 不会混）。
//
// 三条纪律写在这里：
//   1. 值默认打码为 ••••••，点「显示」才在本地露出来。显示状态只在内存里，刷新就收回 ——
//      环境变量里常放密钥，默认看得见就等于默认泄露。
//   2. 改动即保存：改值（回车 / 失焦）、删行、添行、改生效方式都立刻发 save-env
//      （整份替换这个作用域），成功之后重读设置那份读数，以读数为准；界面不自己记账。
//   3. 回执与提示条里不出现值：只说键名与生效方式（§61.4 第 4 条）。后端审计同样只记键名。
//
// 生效方式（§62.2 的 options，存在 env.json 顶层）：inherit 继不继承控制台进程的环境变量，
// merge 撞上同名键时覆盖还是追加。这两项是**全局**的，只摆在设置页那一张表下面；
// profile 那张表永远覆盖 global（没有第三种语义），所以对话框顶部只读显示当前方式。
//
// 键名那一侧有一张保留名单（DSH_HOME / PATH / HOME / PWD / TMPDIR / DSH_PROFILE）：
// 命中的行置灰、注明「控制台自己管，不能改」，删除与显示键都不摆 —— 后端也会拒，
// 界面这一层只负责别让人白点一次。

///|
/// 启动环境的一处作用域。
///
/// scope 是请求体里那个词（global / profile），scope_id 是界面状态的键
/// （"global" 或 "<home>|<profile>"）：两者分开，是因为前者是契约，后者只用来记
/// 「哪些值现在露着、哪一格在编辑」—— 后者带上 home，同名不同 home 的两只不会串。
struct EnvTarget {
  scope : String
  home : String
  profile : String
  scope_id : String
} derive(Eq)

pub extend EnvTarget with Eq::{ not_equal, equal }

///|
fn env_target_global() -> EnvTarget {
  { scope: "global", home: "", profile: "", scope_id: "global" }
}

///|
/// 这只 profile 自己的 home：profile 那一段的键要用它（后端 profile_env_key 同一口径）。
///
/// 优先「配置 home」（round 里那只 profile 的 home），其次补包用的那个 home，
/// 最后才退回行上那一格。都认不出返回空串 —— 那时这一份存不了，界面如实说，
/// 不拿控制台自己的 home 顶上（那会把变量记到别的 home 名下）。
fn env_home_of(row : Row) -> String {
  if home_is_path(row.home_path) {
    row.home_path
  } else if home_is_path(row.repair_home) {
    row.repair_home
  } else {
    own_home_of(row)
  }
}

///|
fn env_target_of_row(row : Row) -> EnvTarget? {
  let name = match row.profile_name {
    Some(name) => name
    None => ""
  }
  if name == "" {
    return None
  }
  let home = env_home_of(row)
  if home == "" {
    return None
  }
  Some({ scope: "profile", home, profile: name, scope_id: home + "|" + name })
}

///|
/// 对话框开着的那一只是哪一只（关着 / 行不在读数里 = None）。
fn env_target_open(model : Model) -> EnvTarget? {
  if model.env_open == "" {
    return None
  }
  match find_row(model.rows, model.env_open) {
    Some(row) => env_target_of_row(row)
    None => None
  }
}

///|
/// settings 响应体 → 启动环境那一段。
///
/// 旧后端没有 env 段：parse_env_facts 给空表，界面照此说「还没有」。
/// 这里再 parse 一次外壳（与 parse_settings 读的是同一份文本）：env 段本来就不在
/// parse_settings 的返回里（那一套是「一个键一个值」的契约，§61.5 说明了为什么分开）。
fn env_facts_of_response(body : String) -> EnvFacts {
  match open_envelope(body) {
    Ok(data) => parse_env_facts(data)
    Err(_) =>
      {
        path: "",
        global: [],
        profiles: [],
        reserved: [],
        options_known: false,
        inherit_env: true,
        merge: "override",
      }
  }
}

///|
/// 模型里那四格拼回一份读数（profile 那张表的查找走 settings.mbt 的 env_profile_pairs：
/// 键是 "<home>|<profile>"，与后端同一口径）。
fn env_facts_of_model(model : Model) -> EnvFacts {
  {
    path: model.env_path,
    global: model.env_global,
    profiles: model.env_profiles,
    reserved: model.env_reserved,
    options_known: model.env_options_known,
    inherit_env: model.env_inherit,
    merge: model.env_merge,
  }
}

///|
/// 这个作用域现在的那张表。
fn env_entries_of(model : Model, target : EnvTarget) -> Array[(String, String)] {
  if target.scope == "global" {
    model.env_global
  } else {
    env_profile_pairs(env_facts_of_model(model), target.home, target.profile)
  }
}

///|
/// 按作用域 id 取那一份表（profile 那一档的 id 就是 env_profiles 的键）。
fn env_entries_of_scope(model : Model, scope_id : String) -> Array[(String, String)] {
  if scope_id == "global" {
    model.env_global
  } else {
    for pair in model.env_profiles {
      if pair.0 == scope_id {
        return pair.1
      }
    }
    []
  }
}

///|
fn env_entry_of_scope(model : Model, scope_id : String, key : String) -> String? {
  for pair in env_entries_of_scope(model, scope_id) {
    if pair.0 == key {
      return Some(pair.1)
    }
  }
  None
}

///|
/// 草稿只在「与读数里的值不同」时留着：保存成功、读数跟上来之后它自然消失，
/// 同一时刻正在敲的另一格（文本仍然不同）不受影响。
fn env_prune_drafts(model : Model) -> Array[EnvDraft] {
  model.env_draft.filter(fn(draft) {
    match env_entry_of_scope(model, draft.scope, draft.key) {
      Some(value) => value != draft.text
      None => true
    }
  })
}

///|
fn env_is_reserved(model : Model, key : String) -> Bool {
  model.env_reserved.contains(key)
}

///|
/// 「这一格现在露着」的判据：作用域 + 键名。两条同名键（全局一条、某只 profile 一条）
/// 各露各的 —— 在全局点开显示，不该把某只 profile 的同名值也露出来。
fn env_shown_id(target : EnvTarget, key : String) -> String {
  target.scope_id + "|" + key
}

///|
fn env_revealed(model : Model, target : EnvTarget, key : String) -> Bool {
  model.env_shown.contains(env_shown_id(target, key))
}

///|
fn env_draft_of(model : Model, target : EnvTarget, key : String) -> String? {
  for draft in model.env_draft {
    if draft.scope == target.scope_id && draft.key == key {
      return Some(draft.text)
    }
  }
  None
}

///|
/// 控件里该显示的文本：草稿优先（正在敲的那一份），否则读数里的值。
fn env_control_text(model : Model, target : EnvTarget, key : String, value : String) -> String {
  match env_draft_of(model, target, key) {
    Some(text) => text
    None => value
  }
}

///|
fn env_draft_put(
  drafts : Array[EnvDraft],
  scope_id : String,
  key : String,
  text : String,
) -> Array[EnvDraft] {
  let out = drafts.filter(fn(draft) { draft.scope != scope_id || draft.key != key })
  out.push({ scope: scope_id, key, text })
  out
}

///|
/// 一张表里放一个键：已经有就原位换值（保持行序），没有就追加到末尾。
fn env_entries_with(
  entries : Array[(String, String)],
  key : String,
  value : String,
) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  let mut found = false
  for pair in entries {
    if pair.0 == key {
      out.push((key, value))
      found = true
    } else {
      out.push(pair)
    }
  }
  if !found {
    out.push((key, value))
  }
  out
}

///|
fn env_entries_without(
  entries : Array[(String, String)],
  key : String,
) -> Array[(String, String)] {
  entries.filter(fn(pair) { pair.0 != key })
}

///|
/// 键名能不能写进启动环境（后端 env_key_allowed 的前端口径）。
///
/// 返回一句人话，空串 = 没问题。本地先把关，是为了不让人点了「添加」再吃一条
/// 后端回来的 bad-params —— 那道闸门仍然在，这里只是提前说清。
fn env_key_problem(model : Model, key : String) -> String {
  if key == "" {
    return "键名不能是空的"
  }
  if env_is_reserved(model, key) {
    return key + " 由控制台自己管，不能写进启动环境"
  }
  for ch in key {
    let code = ch.to_int()
    let ok = (code >= 48 && code <= 57) ||
      (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      ch == '_'
    if !ok {
      return "键名 " + key + " 只能用字母、数字和下划线"
    }
  }
  ""
}

// ── 表 ──────────────────────────────────────────────────────

///|
/// 值那一格：打码 / 明文输入框 / 保留键的说明。
///
/// 打码是**原文之外**的一层：隐藏时连输入框都不摆（摆一个 value=•••••• 的输入框，
/// 看着能改，改了就把掩码当成值存下去）。要看、要改都得先点「显示」。
fn env_value_cell(
  model : Model,
  target : EnvTarget,
  key : String,
  value : String,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  if !env_revealed(model, target, key) {
    return @html.span(
      class="dsh-env-mask",
      attrs=mark("env-mask", ["settings", "env", target.scope_id, key, "mask"])
        .aria_label(key + " 的值已打码"),
      "••••••",
    )
  }
  @html.input(
    input_type=Text,
    class="dsh-env-input",
    value=env_control_text(model, target, key, value),
    attrs=mark("env-input", ["settings", "env", target.scope_id, key, "input"])
      .aria_label(key + " 的值")
      .spellcheck(false),
    on_input=emit.map(fn(text) { EnvDraft(target.scope, key, text) }),
    on_change=emit.map(fn(text) { EnvCommit(target.scope, key, text) }),
  )
}

///|
/// 表里的一行：键 / 值 / 操作。保留键那一档置灰、不给动作，只注明「控制台自己管」。
fn env_row(
  model : Model,
  target : EnvTarget,
  key : String,
  value : String,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let locked = env_is_reserved(model, key)
  let revealed = env_revealed(model, target, key)
  let ops : Array[@html.Html] = if locked {
    [
      @html.span(
        class="dsh-env-locked",
        attrs=mark("env-locked", ["settings", "env", target.scope_id, key, "locked"]),
        "控制台自己管，不能改",
      ),
    ]
  } else {
    [
      @html.button(
        class="dsh-env-btn",
        type_="button",
        attrs=mark("env-reveal", ["settings", "env", target.scope_id, key, "reveal"])
          .data_set("shown", if revealed { "true" } else { "false" })
          .aria_pressed(if revealed { "true" } else { "false" })
          .aria_label(if revealed { "隐藏 " + key + " 的值" } else { "显示 " + key + " 的值" }),
        on_click=emit(EnvReveal(target.scope, key)),
        [@html.text(if revealed { "隐藏" } else { "显示" })],
      ),
      @html.button(
        class="dsh-env-btn is-danger",
        type_="button",
        attrs=mark("env-delete", ["settings", "env", target.scope_id, key, "delete"])
          .aria_label("删掉 " + key),
        on_click=emit(EnvDelete(target.scope, key)),
        [@html.text("删除")],
      ),
    ]
  }
  @html.div(
    class=if locked { "dsh-env-row is-locked" } else { "dsh-env-row" },
    attrs=mark("env-row", ["settings", "env", target.scope_id, key])
      .data_set("key", key)
      .data_set("locked", if locked { "true" } else { "false" }),
    [
      @html.span(
        class="dsh-env-key",
        attrs=mark("env-key", ["settings", "env", target.scope_id, key, "key"]).title(key),
        key,
      ),
      @html.div(class="dsh-env-value", [
        // 保留键那一档连值都不摆：那个值不归这张表管，摆出来只会被读成「它也在这张表里」
        if locked {
          @html.span(class="dsh-env-mask", "—")
        } else {
          env_value_cell(model, target, key, value, emit)
        },
      ]),
      @html.div(class="dsh-env-ops", ops),
    ],
  )
}

///|
/// 底部「添加一行」：两格输入 + 一颗「添加」。
fn env_add_row(model : Model, target : EnvTarget, emit : @cmd.Emit[Msg]) -> @html.Html {
  @html.div(
    class="dsh-env-add",
    attrs=mark("env-add", ["settings", "env", target.scope_id, "add"]),
    [
      @html.input(
        input_type=Text,
        class="dsh-env-add-key",
        value=model.env_add_key,
        placeholder="KEY",
        attrs=mark("env-add-key", ["settings", "env", target.scope_id, "add", "key"])
          .aria_label("新变量的键名")
          .spellcheck(false),
        on_input=emit.map(fn(text) { EnvAddKeyInput(text) }),
      ),
      @html.input(
        input_type=Text,
        class="dsh-env-add-value",
        value=model.env_add_value,
        placeholder="值",
        attrs=mark("env-add-value", ["settings", "env", target.scope_id, "add", "value"])
          .aria_label("新变量的值")
          .spellcheck(false),
        on_input=emit.map(fn(text) { EnvAddValueInput(text) }),
      ),
      @html.button(
        class="dsh-env-btn primary",
        type_="button",
        attrs=mark("env-add-commit", ["settings", "env", target.scope_id, "add", "commit"]),
        on_click=emit(EnvAdd(target.scope)),
        [@html.text("添加")],
      ),
    ],
  )
}

///|
/// 表脚：这一段落在哪儿，以及保留键是哪几个（保留键不占行，只在这里点名）。
fn env_foot(model : Model) -> @html.Html {
  let reserved = if model.env_reserved.length() == 0 {
    ""
  } else {
    "｜控制台自己管的键不能改：" + join_with(model.env_reserved, "、")
  }
  // 页脚只留一句短的（§63）：路径、权限、保留键名单全进悬停。
  // 这一段在设置页与对话框里各出现一次，长句子会把表格压得没地方站。
  @html.p(
    class="dsh-env-foot",
    attrs=mark("env-foot", ["settings", "env", "foot"]).title(
      (if model.env_path == "" {
        "落盘位置还没读到"
      } else {
        "落盘位置 " + model.env_path + "（权限 600）"
      }) + "；改一行就存一次，下一次启动实例生效" + reserved,
    ),
    "改一行就存一次",
  )
}

///|
/// 一张表（两个作用域共用）。editable = false：连 home 都认不出，这一份存不了，
/// 只摆已读到的内容与一句说明，不给一排点下去必然失败的控件。
fn env_table(
  model : Model,
  target : EnvTarget,
  empty_text : String,
  editable : Bool,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let entries = env_entries_of(model, target)
  let body : Array[@html.Html] = []
  if entries.length() == 0 {
    body.push(
      @html.p(
        class="dsh-env-empty",
        attrs=mark("env-empty", ["settings", "env", target.scope_id, "empty"]),
        empty_text,
      ),
    )
  } else {
    body.push(
      @html.div(
        class="dsh-env-head",
        attrs=mark("env-head", ["settings", "env", target.scope_id, "head"]),
        [
          @html.span(class="dsh-env-head-key", "键"),
          @html.span(class="dsh-env-head-value", "值"),
          @html.span(class="dsh-env-head-ops", "操作"),
        ],
      ),
    )
    for pair in entries {
      body.push(env_row(model, target, pair.0, pair.1, emit))
    }
  }
  if editable {
    body.push(env_add_row(model, target, emit))
  } else {
    body.push(
      @html.p(
        class="dsh-env-empty",
        attrs=mark("env-unavailable", ["settings", "env", target.scope_id, "unavailable"]),
        "读不到这只 profile 的目录名或 home，这一份存不了",
      ),
    )
  }
  body.push(env_foot(model))
  @html.div(
    class="dsh-env-table",
    attrs=mark("env-table", ["settings", "env", target.scope_id]).data_set(
      "scope",
      target.scope,
    ),
    body,
  )
}

// ── 生效方式（§62.2 的 options）────────────────────────────

///|
/// 「同名变量」那半句：同名覆盖 / 同名追加。
fn env_merge_text(model : Model) -> String {
  if model.env_merge == "append" {
    "同名追加"
  } else {
    "同名覆盖"
  }
}

///|
/// 生效方式那一整句，提示条与对话框顶部共用：「继承系统环境，同名覆盖」。
///
/// inherit 关掉之后 merge 不再参与合并，但它的值仍然存在文件里（下次打开继承就用得上），
/// 所以照样拼出来：这一句说的是「现在存的是什么」，不是替用户推断「现在有没有用」。
fn env_mode_text(model : Model) -> String {
  let inherit_text = if model.env_inherit { "继承系统环境" } else { "不继承系统环境" }
  inherit_text + "，" + env_merge_text(model)
}

///|
/// 对话框顶部那一行只读文字（§62.3）：「继承系统环境 · 同名覆盖 · 这一份覆盖全局」。
///
/// 旧后端没有 options 段时只说后一半：前半句这时是「不知道」，不是「继承」。
/// 后一半（profile 覆盖 global）是 §62.2 写死的语义，永远成立。
fn env_mode_line(model : Model) -> String {
  if model.env_options_known {
    (if model.env_inherit { "继承系统环境" } else { "不继承系统环境" }) + " · " +
    env_merge_text(model) +
    " · 这一份覆盖全局"
  } else {
    "这一份覆盖全局"
  }
}

///|
/// 一枚「同名变量」的单选（§62.3）。点了即保存，没有单独的确认键。
fn env_merge_radio(
  model : Model,
  value : String,
  label : String,
  hint : String,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  @html.label(
    class="dsh-env-radio",
    attrs=mark("env-merge-" + value, ["settings", "env", "options", "merge", value]).title(hint),
    [
      @html.input(
        input_type=Radio,
        name="dsh-env-merge",
        id="dsh-env-merge-" + value,
        class="dsh-env-radio-input",
        value=value,
        checked=model.env_merge == value,
        on_change=emit.map(fn(_text) { EnvMergePicked(value) }),
      ),
      @html.span(class="dsh-env-radio-text", label),
    ],
  )
}

///|
/// 生效方式那两项：「继承系统环境变量」开关 + 「同名变量：覆盖 / 追加」（§62.3）。
///
/// 只在读数里有 options 段时才摆：save-env 的参数 allow-list 在旧后端里没有 options，
/// 摆一排点下去必然被拒的控件，比不摆更糟（也更容易被读成「这台后端坏了」）。
fn env_options_block(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  if !model.env_options_known {
    return @html.nothing
  }
  let merge_hint = "只在继承系统环境时有区别：覆盖 = 系统里的同名键用这张表的值；" +
    "追加 = 系统值在前、表里的值接在后面，分隔符是冒号"
  @html.div(
    class="dsh-env-options",
    attrs=mark("env-options", ["settings", "env", "options"]),
    [
      @html.div(class="dsh-env-option", [
        @html.div(class="dsh-env-option-main", [
          @html.div(
            class="dsh-env-option-name",
            attrs=mark("env-inherit-name", ["settings", "env", "options", "inherit", "name"]),
            "继承系统环境变量",
          ),
          @html.p(
            class="dsh-env-option-desc",
            attrs=mark("env-inherit-desc", ["settings", "env", "options", "inherit", "desc"]),
            "起实例时带上控制台进程自己的环境变量；关掉之后子进程只有这张表与保留键",
          ),
        ]),
        @html.div(class="dsh-env-option-control", [
          switch_control(
            model.env_inherit,
            false,
            "继承系统环境变量",
            "起实例时带上控制台进程自己的环境变量；关掉之后子进程只有这张表与保留键",
            emit(EnvInheritToggled(!model.env_inherit)),
            key="env.inherit",
            elem_id="dsh-env-inherit",
          ),
        ]),
      ]),
      @html.div(class="dsh-env-option", [
        @html.div(class="dsh-env-option-main", [
          @html.div(
            class="dsh-env-option-name",
            attrs=mark("env-merge-name", ["settings", "env", "options", "merge", "name"]),
            "同名变量",
          ),
          @html.p(
            class="dsh-env-option-desc",
            attrs=mark("env-merge-desc", ["settings", "env", "options", "merge", "desc"]),
            "与继承来的同名键撞上时，覆盖或把系统值接在前面（冒号分隔）",
          ),
        ]),
        @html.div(class="dsh-env-option-control", [
          @html.div(
            class="dsh-env-radios",
            attrs=mark("env-merge-group", ["settings", "env", "options", "merge", "group"])
              .role("radiogroup")
              .aria_label("同名变量"),
            [
              env_merge_radio(model, "override", "覆盖", merge_hint, emit),
              env_merge_radio(model, "append", "追加", merge_hint, emit),
            ],
          ),
        ]),
      ]),
    ],
  )
}

// ── 设置页「进程」组里那一块 ────────────────────────────────

///|
/// 设置页「进程」组里的「全局启动变量」那一块（§62.1）：表格 + 生效方式。
///
/// 它接在那两条设置项后面，所以自己带一个小标题 —— 面板标题是「进程」，
/// 这一块得说清自己叫「全局启动变量」，不然那张表看上去像第三条设置项。
fn env_settings_body(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let target = env_target_global()
  @html.div(
    class="dsh-settings-section",
    attrs=mark("env-section", ["settings", "env", "section"]),
    [
      @html.h3(class="dsh-settings-section-title", "全局启动变量"),
      @html.p(
        class="dsh-settings-section-note",
        "起实例时挂进子进程的变量：这一份是全局的，某只 profile 可以再覆盖其中的键",
      ),
      env_table(model, target, "还没有启动变量，加一行就会在起实例时带上", true, emit),
      env_options_block(model, emit),
    ],
  )
}

///|
/// 抽屉「操作」组里那一颗：打开这只 profile 的启动变量对话框（§62.1）。
///
/// 名字用「启动变量」四个字：它在「操作」组里，上下文已经说明了这是「这一只的」，
/// 长名字（「这只 profile 的启动变量」）反而要占半行。作用域写在悬停里说清。
fn drawer_env_button(row : Row, emit : @cmd.Emit[Msg]) -> @html.Html {
  @html.button(
    class="dsh-btn",
    type_="button",
    disabled=row.busy,
    attrs=mark("drawer-env", ["overview", "drawer", row.id, "action", "env"])
      .data_set("action", "env")
      .title(
        "这只 profile 的启动变量：起它时挂进子进程的变量，同名键覆盖设置页那份全局的",
      ),
    on_click=emit(EnvProfileOpen(row.id)),
    [icon("key-variant"), @html.span("启动变量")],
  )
}

// ── 抽屉里的对话框 ──────────────────────────────────────────

///|
/// 对话框里「摆不出一张表」时那一句话（读取中 / 读失败 / 认不出这只）。
fn env_dialog_note(
  model : Model,
  key : String,
  text : String,
  hint : String,
) -> @html.Html {
  let attrs = mark(key, ["settings", "env", "dialog", key])
  @html.div(class="dsh-env-table", [
    @html.p(
      class="dsh-env-empty",
      attrs=if hint == "" { attrs } else { attrs.title(hint) },
      text,
    ),
    env_foot(model),
  ])
}

///|
/// 「<profile> 的启动变量」对话框（§61.3 / §62.1）：同一张表，scope = profile。
///
/// 顶部有一行只读的生效方式（§62.3）：那两项是全局的（在设置页「进程」组里改），
/// 摆在这里是为了让「这一份到底怎么和全局、系统环境拼」在动手之前就看得见；
/// 「这一份覆盖全局」是写死的语义，不提供第三种。
///
/// 空态写「没有单独设置，跟着全局走」—— 这一句是这个对话框最常出现的状态，
/// 也是它与全局那一份的关系说明（全局那张表不在这里重复摆，免得两处各说一半）。
fn env_profile_dialog(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let row = find_row(model.rows, model.env_open)
  // 标题说磁盘上的名字（web），不是卡片上带端口的那串（web :3080）——与改名框同一口径。
  let name = match row {
    Some(item) =>
      match item.profile_name {
        Some(profile) => profile
        None => item.name
      }
    None => "这只 profile"
  }
  let target = env_target_open(model)
  // 三种「现在摆不出一张真表」的状态分开说，别拿空态冒充：
  //   还没读到设置 → 正在读；读失败 → 说读失败；这只 profile 的目录名 / home 认不出 → 存不了。
  // 「没有单独设置」这一句只说**真读到过、确实没有**那一档（空态与「不知道」不是一回事）。
  let content = if !model.settings_loaded {
    env_dialog_note(model, "env-loading", "正在读启动变量", "")
  } else if model.settings_error != "" {
    env_dialog_note(
      model,
      "env-unread",
      "启动变量没读到，暂时改不了",
      model.settings_error,
    )
  } else {
    match target {
      Some(target) =>
        env_table(model, target, "没有单独设置，跟着全局走", true, emit)
      None =>
        env_dialog_note(
          model,
          "env-unavailable",
          "读不到这只 profile 的目录名或 home，这一份存不了",
          "",
        )
    }
  }
  // 顶部那一行只读的生效方式（§62.3）。悬停里说清「这两项在哪儿改、为什么这里只读」——
  // 不摆控件是刻意的：它是全局的一项，摆在两只 profile 的对话框里就会变成两个入口。
  // 一行生效方式 + 悬停说清「在哪儿改、谁盖谁」（§63）。原来还有一段三句的正文，
  // 讲的是同一件事，删掉：对话框的主语是这张表，不是那套合并规则。
  let mode_line = @html.p(
    class="dsh-env-mode",
    attrs=mark("env-mode", ["dialog", "env-dialog", "mode"]).title(
      "继承与同名变量的方式在设置页的「进程」组里改；这一只的变量永远覆盖全局那一份。" +
      "起这只 profile 时先铺全局那一段，再铺这一份，同键以这里为准，只影响这一只",
    ),
    env_mode_line(model),
  )
  let card = @html.div(class="dsh-dialog-card dsh-env-dialog", [
    @html.h2(
      class="dsh-dialog-title",
      attrs=mark("dialog-title", ["dialog", "env-dialog", "title"]),
      name + " 的启动变量",
    ),
    mode_line,
    content,
    @html.div(class="dsh-dialog-foot", [
      @html.button(
        class="dsh-dialog-btn primary",
        type_="button",
        attrs=mark("dialog-ok", ["dialog", "env-dialog", "ok"]),
        on_click=emit(EnvProfileClose),
        [@html.text("关闭")],
      ),
    ]),
  ])
  dialog(
    "env-dialog",
    name + " 的启动变量",
    emit(EnvProfileClose),
    emit.map(fn(key : @html.Keyboard) {
      if key.key() == "Escape" {
        EnvProfileClose
      } else {
        Noop
      }
    }),
    card,
  )
}
