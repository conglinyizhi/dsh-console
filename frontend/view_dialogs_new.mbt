// 对话框：改名 / 删除 / 备注 / 补包确认 / 取消隔离 / 快照还原 / 整体替换 / 新建实例 /
// 命令行型说明 —— 所有会盖住页面、需要用户再看一眼再决定的框。
//
// 2026-10-20 从 view_overview.mbt 拆出来：对话框的文案与按钮是一组独立的契约，
// 与页面、卡片、抽屉都不共用状态。只搬位置，函数体一个字没改。

///|
/// 第一张可点的源卡是哪一只：开框时焦点落在它身上。
///
/// 与「选择配置」侧栏同一个口径（job_profile_first_usable）：顺序就是显示顺序
/// （运行中那一组在前），「第一张」在界面上是看得见的那一条。
fn new_instance_first_usable(model : Model) -> String {
  let (running, stopped) = job_profile_picks(model)
  for pick in running {
    if pick.usable {
      return pick.name
    }
  }
  for pick in stopped {
    if pick.usable {
      return pick.name
    }
  }
  ""
}

///|
/// 这一刻「一只可用的源都没有」成不成立（design/design-fixes.md §21.4）。
///
/// **要求读数已经落地**（built）：读数还在路上时框里写的是「还没读到」，那时说
/// 「一只可用的都没有」是把「还不知道」说成了「没有」。读数落地、而第一张可点的源卡
/// 不存在（一只 profile 都没有，或全不可用）时才算成立 —— 这时复选框默认勾上，
/// 因为它是唯一能走的路。
fn new_instance_no_usable_source(model : Model) -> Bool {
  model.built && new_instance_first_usable(model) == ""
}

///|
/// 勾上复选框之后名字那一格预填什么：`base-<两位序号>`，读数里已有的就顺延
/// （design/design-fixes.md 第 20 / 21 节）。
///
/// 「已存在」拿手上这份 profiles 读数判（列表里看得见的那几只），序号从 01 起挨个试。
/// 读数里没有、磁盘上却有的名字交给后端兜底：那时它回 conflict，原因写在框里，
/// 改个名字就能再点一次 —— 比前端凭空猜一个号更诚实。
fn new_instance_base_name(model : Model) -> String {
  let taken : Array[String] = []
  for fact in job_profile_facts(model) {
    taken.push(fact.name)
  }
  let mut index = 1
  while index <= 999 {
    let digits = if index < 10 { "0" + index.to_string() } else { index.to_string() }
    let candidate = "base-" + digits
    if !taken.contains(candidate) {
      return candidate
    }
    index = index + 1
  }
  "base-" + index.to_string()
}

///|
/// 框里的一张源卡：与「选择配置」「整体替换选源」是**同一份画法**
/// （view_parts.mbt 的 profile_card）。这一处只决定点下去发什么、路径前缀、
/// 挂不挂「已选」那枚标记。选中那一张挂一枚「已选」—— 文字标记，不只靠高亮色。
///
/// 勾上「从基础实例开始」时整组不可选，但那一档不写在卡上（§22）：容器 inert + 遮罩，
/// 卡片照旧只写读数带来的 data-usable —— 同一张卡在维护页与这里长得一模一样。
fn new_instance_source_card(
  model : Model,
  pick : ProfilePick,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let selected = pick.name == model.new_source
  let ok = pick.usable
  let aria = if ok { "用 " + pick.name + " 当源配置" } else { pick.name + " 不可用：" + pick.why }
  profile_card(
    pick,
    new_instance_card_id(pick.name),
    "new-instance",
    ["overview", "new-instance"],
    if selected { "已选" } else { "" },
    aria,
    aria,
    fn(name) { NewInstanceStatePicked(name) },
    emit,
    chosen=selected,
  )
}

///|
/// 框里的一组源卡：分组头（与「选择配置」同一个说法）+ 卡片。
fn new_instance_group(
  key : String,
  title : String,
  picks : Array[ProfilePick],
  model : Model,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let cards : Array[@html.Html] = []
  for pick in picks {
    cards.push(new_instance_source_card(model, pick, emit))
  }
  @html.div(
    class="dsh-profile-sidebar-group",
    attrs=mark("new-instance-group", ["overview", "new-instance", "group", key])
      .data_set("group", key),
    [
      @html.h3(
        class="dsh-profile-sidebar-group-title",
        attrs=mark("new-instance-group-title", ["overview", "new-instance", "group", key, "title"]),
        title + " (" + picks.length().to_string() + ")",
      ),
      @html.div(
        class="dsh-profile-sidebar-list",
        attrs=mark("new-instance-list", ["overview", "new-instance", "list", key]),
        cards,
      ),
    ],
  )
}

///|
/// 源卡区上面那一句说明（§21）：一只可用的都没有时写出路，data-kind 标明是哪一档。
///
/// 为什么要有这一句：几行「不可用：…」自己躺着时，读者得自己推出「那我还能怎么办」；
/// 这一句把出路说出来。刻度只有一档了 —— 勾上之后的「这一刻不可选」跟着遮罩走
/// （new_instance_veil），不在这里。
fn new_instance_note(kind : String, text : String) -> @html.Html {
  @html.p(
    class="dsh-new-note",
    attrs=mark("new-instance-note", ["dialog", "new-instance", "note"]).data_set("kind", kind),
    text,
  )
}

///|
/// 整组源卡上盖的那一层（§22）：勾上「从基础实例开始」时，不可选这件事由**容器**说 ——
/// 容器挂 inert（键盘与指针都进不去），这一层挡在眼睛前面把话说出来。
///
/// 为什么不是「每张卡置灰 + 每张卡写一句 aria」：卡上的话说的是「这只配置怎么样」，
/// 而这一刻要说的是「这一组这一刻不参与选源」，是对整组说的。挂在卡上就得在每张卡上
/// 重复一遍同一件事，还把维护页那一套读数说明挤掉（同一份画法）。
fn new_instance_veil() -> @html.Html {
  @html.div(
    class="dsh-new-pick-veil",
    attrs=mark("new-instance-veil", ["dialog", "new-instance", "veil"]),
    [
      @html.p(
        class="dsh-new-pick-veil-text",
        attrs=mark("new-instance-veil-text", ["dialog", "new-instance", "veil", "text"]),
        "已勾上「从基础实例开始」，这些源配置这一刻不可选",
      ),
    ],
  )
}

///|
/// 「＋新建实例」的居中对话框：两步在同一个框里 —— 选源配置、填名字。
///
/// 源卡是「选择配置」那一套（全部 profile，含隔离的）；名字默认 `<源>-dev`，可改。
/// 左下角是「从基础实例开始」复选框（§21）：勾上就把源卡整组锁上、名字预填 base-NN、
/// 焦点进名字格；勾掉卡片恢复可选、名字一个字不动。
/// 底部两颗键：创建走既有 fork-profile（新副本默认隔离），取消把焦点还给页头那颗按钮。
/// 创建失败**不关框**：后端原话写在框里，改个名字就能再点一次。
fn new_instance_dialog(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let (running, stopped) = job_profile_picks(model)
  // 「读数到了没有」与「有没有可用源」是两件事：前者说知道不知道，后者才说得出口
  // 「一只可用的都没有」。空态那一句按这两档分开写。
  let landed = model.built
  let no_usable = new_instance_no_usable_source(model)
  // 勾上复选框、框里又有源卡时，整组锁住（§22）：锁挂在容器上，不挂在卡上。
  // 一只卡都没有时不盖遮罩 —— 那时没有可锁的东西，底下一句空态才是该看的。
  let lock_sources = model.new_base && (running.length() > 0 || stopped.length() > 0)
  // 有卡而一只可用的都没有：出路写在卡上面，不让几行「不可用」自己猜。
  // 这一句摆在遮罩**外面**（下面 pick_area 之前）：勾上之后它照样读得到 —— 遮罩上那句说的是
  // 「这一刻不可选」，这一句说的是「本来就没有可用的」，两件事各说各的。
  let none_usable_note = if no_usable && (running.length() > 0 || stopped.length() > 0) {
    new_instance_note("none-usable", "现在一只可用的都没有，可以勾上「从基础实例开始」新建一份。")
  } else {
    @html.nothing
  }
  let picks : Array[@html.Html] = []
  if running.length() == 0 && stopped.length() == 0 {
    picks.push(
      @html.p(
        class="dsh-empty-sub",
        attrs=mark("new-instance-empty", ["overview", "new-instance", "empty"])
          .data_set("state", if landed { "none-usable" } else { "loading" }),
        if landed {
          "现在一只可用的都没有，可以勾上「从基础实例开始」新建一份。"
        } else {
          "还没读到 profile 读数，等读数回来再挑。"
        },
      ),
    )
  } else {
    if running.length() > 0 {
      picks.push(new_instance_group("running", "当前运行的实例", running, model, emit))
    }
    if stopped.length() > 0 {
      picks.push(new_instance_group("stopped", "已停止的实例", stopped, model, emit))
    }
  }
  // 源那一格：从基础模板开始时写「基础模板」，否则写选中的那一只（还没选就写「还没选」）
  let source_text = if model.new_base {
    "基础模板"
  } else if model.new_source == "" {
    "还没选"
  } else {
    model.new_source
  }
  let has_source = model.new_base || model.new_source != ""
  let can_create = has_source && model.new_name_draft.trim() != "" && !model.new_busy
  // 框头那句**固定**（§25.4）：它说的是这个框有两条路（复制现有配置 / 用基础模板新建），
  // 勾不勾复选框都不改这一句。复选框只影响卡片区锁不锁、名字格引导要不要显示。
  let message_line = "从现有的某个配置复制一个，或者是创建一个全新的"
  let error_block = if model.new_error.length() > 0 {
    @html.p(
      class="dsh-dialog-error",
      attrs=mark("new-instance-error", ["dialog", "new-instance", "error"]),
      model.new_error,
    )
  } else {
    @html.nothing
  }
  // 名字这一格：标签 + 输入框；标签下面是那句引导（§21.1）——
  // 那一刻源卡全锁着，能做的只有填名字，「填一个名字，它会用基础模板新建」就是下一步。
  // 这一句**常驻占位**（§24.3）：没勾时只是 visibility: hidden，行还在，勾上勾下对话框
  // 高度与下半截的位置一个像素都不动。读屏那边由 visibility 自己摘掉，不另挂 aria。
  let name_lines : Array[@html.Html] = [
    @html.label(
      class="dsh-new-name-label",
      for_=new_instance_name_id(),
      attrs=mark("new-instance-name-label", ["dialog", "new-instance", "name-label"]),
      [
        // 必填星号（§24.1）：颜色是 danger，读屏不报它（靠输入框上的 aria-required）。
        @html.span(
          class="dsh-req",
          attrs=@html.Attrs::build().aria_hidden("true"),
          "*",
        ),
        @html.text("新实例名字（源配置：" + source_text + "）"),
      ],
    ),
    @html.span(
      class="dsh-new-name-guide",
      attrs=mark("new-instance-name-guide", ["dialog", "new-instance", "name-guide"])
        .data_set("active", if model.new_base { "true" } else { "false" }),
      "填一个名字，它会用基础模板新建",
    ),
  ]
  name_lines.push(
    @html.input(
      input_type=Text,
      id=new_instance_name_id(),
      class="dsh-dialog-input",
      value=model.new_name_draft,
      attrs=mark("new-instance-name", ["dialog", "new-instance", "name"])
        .aria_label("新实例名字")
        // 必填（§24.1）：读屏靠这一条，悬停里写人话，星号只是眼睛那一路。
        .aria_required("true")
        .title("必填")
        .spellcheck(false)
        // Enter 只挂在名字这一格上，不挂整个框：源卡自己也吃 Enter（选中），
        // 挂在框上会让「回车选源」同一次按键里顺手把实例也建了。
        .on_keydown(fn(event) {
          if event.key() == "Enter" {
            emit(NewInstanceConfirm)
          } else {
            @cmd.none
          }
        }),
      on_input=emit.map(fn(text) { NewInstanceNameInput(text) }),
    ),
  )
  // 源卡区：外面这层只做两件事 —— 给遮罩当定位容器、勾上时挂 inert 与 aria-disabled。
  // 列表自己的高度上限与滚动位置留在 .dsh-new-pick 上（那一层一个像素都不动）。
  let pick_targets : Array[@html.Html] = [
    @html.div(
      class="dsh-new-pick",
      attrs=mark("new-instance-pick", ["dialog", "new-instance", "pick"]),
      picks,
    ),
  ]
  if lock_sources {
    pick_targets.push(new_instance_veil())
  }
  let pick_area = @html.div(
    class="dsh-new-pick-wrap",
    attrs=mark("new-instance-pick-wrap", ["dialog", "new-instance", "pick-wrap"])
      .inert(lock_sources)
      .aria_disabled(if lock_sources { "true" } else { "false" }),
    pick_targets,
  )
  let card = @html.div(class="dsh-dialog-card dsh-new-card", [
    @html.h2(
      class="dsh-dialog-title",
      attrs=mark("new-instance-title", ["dialog", "new-instance", "title"]),
      "新建实例",
    ),
    @html.p(
      class="dsh-dialog-message",
      attrs=mark("new-instance-message", ["dialog", "new-instance", "message"])
        .data_set("source", if model.new_base { "base" } else { "profile" }),
      message_line,
    ),
    none_usable_note,
    pick_area,
    @html.div(class="dsh-new-name", name_lines),
    error_block,
    // 左下角「从基础实例开始」复选框（§21，原来那颗文本按钮）：勾上 = 换一种模式，
    // 不是「挑一种源」—— 源卡整组锁上，名字预填、焦点进名字格。与右下角的「创建 / 取消」分开。
    // 一只可用的源都没有时它默认勾上（见 app.mbt 的 NewInstanceOpen）。
    @html.div(class="dsh-dialog-foot dsh-dialog-foot-split", [
      @html.label(
        class="dsh-new-base-check",
        for_=new_instance_base_id(),
        attrs=mark("new-instance-base-label", ["dialog", "new-instance", "base-label"])
          .data_set("checked", if model.new_base { "true" } else { "false" })
          // 悬停说明挂在 label 上（挂在 input 上时只有指着那个小方块才出得来）
          .title("用 dsh 自带的基础模板新建一份，不依赖现有配置。现有配置都不可用时用这个。"),
        [
          @html.input(
            input_type=Checkbox,
            id=new_instance_base_id(),
            class="dsh-new-base-box",
            checked=model.new_base,
            attrs=mark("new-instance-base", ["dialog", "new-instance", "base"])
              .data_set("checked", if model.new_base { "true" } else { "false" })
              .title("用 dsh 自带的基础模板新建一份，不依赖现有配置。现有配置都不可用时用这个。")
              .aria_label("从基础实例开始")
              .disabled(model.new_busy)
              // 勾的是「勾完之后的那一档」：模型是唯一真相，原生复选框的翻转随后由重渲染对齐
              .on_click(fn(_event) { emit(NewInstanceBaseToggled(!model.new_base)) }),
          ),
          @html.span("从基础实例开始"),
        ],
      ),
      @html.div(class="dsh-dialog-actions", [
        @html.button(
          id=new_instance_ok_id(),
          class="dsh-dialog-btn primary",
          type_="button",
          disabled=!can_create,
          attrs=mark("new-instance-ok", ["dialog", "new-instance", "ok"]),
          on_click=emit(NewInstanceConfirm),
          [@html.text(if model.new_busy { "正在创建…" } else { "创建" })],
        ),
        @html.button(
          id="dsh-new-instance-cancel",
          class="dsh-dialog-btn",
          type_="button",
          disabled=model.new_busy,
          attrs=mark("new-instance-cancel", ["dialog", "new-instance", "cancel"]),
          on_click=emit(NewInstanceClose),
          [@html.text("取消")],
        ),
      ]),
    ]),
  ])
  dialog(
    "new-instance-dialog",
    "新建实例",
    emit(NewInstanceClose),
    emit.map(fn(key : @html.Keyboard) {
      if key.key() == "Escape" {
        NewInstanceClose
      } else {
        Noop
      }
    }),
    card,
  )
}

// ── 页面 ───────────────────────────────────────────────────
