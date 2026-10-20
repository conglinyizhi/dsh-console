// 行模型：Row 结构与两张卡的构造函数（running_rows / profile_rows）、行 id 与候选 id、
// 分组与拖动顺序、归档标记、演示数据，以及读数加载那几条（行就是这些读数拼出来的）。
//
// 2026-10-20 从 state.mbt 拆出来：那个文件 3324 行，Model/Msg 与行模型混在一起；
// 拆开之后「一行长什么样、怎么拼出来」只在这一份里找。只搬位置，函数体一个字没改。

///|
/// 一张卡的 DOM id。关抽屉时焦点要回到触发它的那张卡，所以卡必须有个稳定的 id ——
/// 按 row.id 算（profile:web / port:3080），与语义路径同一口径，列表重排也不变。
fn card_id(id : String) -> String {
  "dsh-card-" + dom_key(id)
}

///|
/// 抽屉面板的 DOM id（同一时刻只开一个）。
fn drawer_panel_id() -> String {
  "dsh-drawer"
}

///|
/// 抽屉里那颗关闭键的 DOM id：打开时焦点落在它身上 ——
/// 焦点必须**真的进抽屉**（不然 Tab 还在背后的列表里走，Esc 也未必收得到）。
fn drawer_close_id() -> String {
  "dsh-drawer-close"
}

///|
/// 设置页一颗开关的 DOM id（§51）：保存成功之后把焦点送回它 ——
/// 保存会让这一行多出「恢复默认」那颗按钮，节点结构一变焦点就掉到 body，
/// 键盘用户按一次空格就「走丢」了（§51.4 要空格与回车都能切）。
fn setting_switch_id(key : String) -> String {
  "dsh-switch-" + key
}

///|
/// 抽屉里「安装缺的包（N）」那颗按钮的 DOM id（§39）：确认框关掉之后焦点回它。
fn drawer_repair_id() -> String {
  "dsh-drawer-repair"
}

///|
/// 补包确认框里「安装」那颗按钮的 DOM id：打开时焦点落在它上面。
fn repair_dialog_ok_id() -> String {
  "dsh-repair-dialog-ok"
}

///|
/// 顶栏那颗铃铛的 DOM id（§36）：通知侧栏关掉之后焦点回它身上。
fn notice_bell_id() -> String {
  "dsh-notice-bell"
}

///|
/// 通知侧栏里关闭键的 DOM id：打开时焦点落在它上面（与抽屉同一套）。
fn notice_panel_close_id() -> String {
  "dsh-notice-panel-close"
}

///|
/// 抽屉里「重命名 / 备注 / 删除」三颗按钮的 DOM id（§30.1）：抽屉不再因为开对话框而收起，
/// 关框之后焦点要回到按下它的那一颗按钮，而不是回卡片。
fn drawer_rename_id() -> String {
  "dsh-drawer-rename"
}

///|
fn drawer_note_id() -> String {
  "dsh-drawer-note"
}

///|
fn drawer_delete_id() -> String {
  "dsh-drawer-delete"
}

///|
/// 「打开 Web UI」右段 chevron 的 DOM id：菜单收起之后焦点回它身上。
fn split_menu_btn_id(row_id : String) -> String {
  "dsh-split-menu-btn-" + dom_key(row_id)
}

///|
/// 那份菜单里「强制启动」的 DOM id：展开时焦点落进它（键盘用户按 Enter 就能走这条路）。
fn split_menu_item_id(row_id : String) -> String {
  "dsh-split-menu-item-" + dom_key(row_id)
}

///|
/// 版本侧栏的搜索框：「选择版本」打开后焦点落在这儿（§12.1，与配置侧栏同一套焦点规则）。
fn version_search_id() -> String {
  "dsh-job-version-search"
}

///|
/// 版本侧栏的关闭键：搜索框落不到（不该发生）时的兜底落点，与配置侧栏同一套。
fn version_sidebar_close_id() -> String {
  "dsh-job-version-sidebar-close"
}

///|
/// 表单里「选择版本」那颗按钮的 id：侧栏关掉之后焦点回它身上。
fn version_choose_id() -> String {
  "dsh-job-version-choose"
}

///|
/// 表单里「选择配置」那颗按钮的 id：侧栏关掉之后焦点回它身上。
fn profile_choose_id() -> String {
  "dsh-job-profile-choose"
}

///|
/// 配置侧栏的关闭键 id：一只可用的 profile 都没有时，焦点落在这儿（总得有处可去）。
fn profile_sidebar_close_id() -> String {
  "dsh-job-profile-close"
}

///|
/// 配置侧栏里一颗卡的 DOM id：打开时焦点落在第一张可点的卡上。
/// 按 profile 名算（与语义路径同一口径），列表顺序变了也指得回同一只。
fn job_profile_card_id(name : String) -> String {
  "dsh-job-profile-card-" + dom_key(name)
}

///|
/// 整体替换侧栏的关闭键 id：一只可选的源都没有时，焦点落在这儿（总得有处可去）。
fn promote_close_id() -> String {
  "dsh-promote-close"
}

///|
/// 整体替换侧栏里一颗源卡的 DOM id（按 profile 名算，焦点打开时落在第一张）。
fn promote_card_id(name : String) -> String {
  "dsh-promote-card-" + dom_key(name)
}

///|
/// 抽屉里「用另一只配置替换这一只」那颗按钮的 id：关掉侧栏之后焦点回它身上。
fn promote_open_id(row_id : String) -> String {
  "dsh-promote-open-" + dom_key(row_id)
}

///|
/// 确认框里「确认替换」那颗键的 id（打开时焦点落在它上面）。
fn promote_confirm_ok_id() -> String {
  "dsh-promote-confirm-ok"
}

///|
fn archive_trigger_id(id : String) -> String {
  "dsh-archive-trigger-" + dom_key(id)
}

///|
/// 页头那颗「＋新建实例」的 id：对话框关掉之后焦点回它（与重命名 / 备注同一套）。
fn new_instance_btn_id() -> String {
  "dsh-new-instance-btn"
}

///|
/// 新建实例框里一颗源卡的 DOM id（按 profile 名算，打开时焦点落在第一张可点的卡上）。
fn new_instance_card_id(name : String) -> String {
  "dsh-new-instance-card-" + dom_key(name)
}

///|
/// 名字输入框的 id：选中源之后焦点与光标送进来，默认那段 <源>-dev 全选，直接打字就是换名。
fn new_instance_name_id() -> String {
  "dsh-new-instance-name"
}

///|
/// 「创建」那颗键的 id。
fn new_instance_ok_id() -> String {
  "dsh-new-instance-ok"
}

///|
/// 新建实例框左下角那枚「从基础实例开始」复选框的 id（label 的 for 指向它）。
/// 一只可用的 profile 都没有、读数又还没落地时，打开框的焦点落在这儿
/// （那一刻框里只有它还能点）。
fn new_instance_base_id() -> String {
  "dsh-new-instance-base"
}

///|
fn find_row(rows : Array[Row], id : String) -> Row? {
  for row in rows {
    if row.id == id {
      return Some(row)
    }
  }
  None
}

///|
fn map_row(rows : Array[Row], id : String, f : (Row) -> Row) -> Array[Row] {
  rows.map(fn(row) { if row.id == id { f(row) } else { row } })
}


// ── 真实读数 → 卡片 ─────────────────────────────────────────

///|
/// 一个行 id 在顺序表里排第几。-1 = 表里没有这一条。
fn order_rank(order : Array[String], id : String) -> Int {
  for i = 0; i < order.length(); i = i + 1 {
    if order[i] == id {
      return i
    }
  }
  -1
}

///|
/// 按顺序表把**一组**行排一遍。
///
/// 规则三条（两组各自排，绝不合并成一张表 —— 组是语义，不是排版）：
///   ① 表里没有的行（新出现的实例 / 新加的 profile）保持它们自己的自动顺序，
///      整体排在已排好的之后。这是一份**稳定的部分序**：没动过的那些不会因为
///      表里多了一条就乱跳。
///   ② 表里有的行按表里的次序排。
///   ③ 表为空 = 没拖过 = 原样返回（自动排序那条路一个字节都不动）。
fn apply_order(rows : Array[Row], order : Array[String]) -> Array[Row] {
  if order.length() == 0 || rows.length() < 2 {
    return rows
  }
  let ranked : Array[Row] = []
  let rest : Array[Row] = []
  for row in rows {
    if order_rank(order, row.id) >= 0 {
      ranked.push(row)
    } else {
      rest.push(row)
    }
  }
  // 表里的 id 互不重复（后端拒重复），所以每一行的名次都是唯一的：这是一份全序，
  // 排序算法稳不稳定都不影响结果。
  ranked.sort_by(fn(a, b) { order_rank(order, a.id) - order_rank(order, b.id) })
  let out : Array[Row] = []
  for row in ranked {
    out.push(row)
  }
  for row in rest {
    out.push(row)
  }
  out
}

///|
/// 按 id 去控制台的「上次启动」表里查一条。查不到给 ("", "")。
fn last_started_lookup(console : ConsoleFacts?, id : String) -> (String, String) {
  match console {
    None => ("", "")
    Some(facts) => {
      for item in facts.last_started {
        if item.id == id {
          return (item.at, item.source)
        }
      }
      ("", "")
    }
  }
}

///|
/// 卡片第二行第三顺位要用的那个时刻：先看这一行自己能不能给出**真实**的启动时刻，
/// 再看控制台的记录。都给不出就是 ("", "")，那一行空着。
///
/// 顺序不能反：正在跑的实例，进程起始时间是最准的那一个；控制台记录里那条
/// 可能是很久以前起的那一次（这一只后来被别人重启过）。反过来会把新时刻说成旧的。

///|
/// 按 profile 查「上次启动」要试的那几个行 id，按该试的先后排。
///
/// 新的形状（带 home）在前，老形状（只有名字）在后：后端那边的记录不一定都带 home
/// （audit.jsonl 里的 start-instance 流水就没有），那一条读数不该因为键换代就查不到。
fn profile_id_candidates(name : String, home : String) -> Array[String] {
  let out : Array[String] = []
  if home != "" {
    out.push(profile_row_id(name, home))
  }
  out.push("profile:" + name)
  out
}

///|
/// 同上，一行卡片的「上次启动」：正在跑的那一只按端口，其余按 profile。
fn row_last_started(
  instance_started : String?,
  port_id : String,
  profile_ids : Array[String],
  console : ConsoleFacts?,
) -> (String, String) {
  match instance_started {
    Some(at) =>
      if at != "" {
        return (at, "这只实例的启动时刻：后端从进程起始时间读出来的")
      }
    None => ()
  }
  let (at, source) = last_started_lookup(console, port_id)
  if at != "" {
    return (at, source)
  }
  for id in profile_ids {
    let (at2, source2) = last_started_lookup(console, id)
    if at2 != "" {
      return (at2, source2)
    }
  }
  ("", "")
}

///|
/// 总览页两组行的**当前显示顺序**（已按顺序表排过）。
///
/// 视图与拖动都从这里取：页面上看到的顺序只有这一个来源。
/// 排在 rebuild 里做不行 —— 顺序表在拖动之后会变，而 rebuild 一趟只跑一次，
/// 页面会停在旧顺序上（拖完看着没动）。这一处是纯读，随取随算。
fn display_groups(model : Model) -> (Array[Row], Array[Row]) {
  let running = model.rows.filter(fn(row) {
    row.archived_at is None && group_of(row) == "running"
  })
  let stopped = model.rows.filter(fn(row) {
    row.archived_at is None && group_of(row) == "stopped"
  })
  (apply_order(running, model.order), apply_order(stopped, model.order))
}

///|
/// 某一组**当前显示着**的行 id（顺序就是屏幕上的顺序）。
fn current_group_ids(model : Model, group : String) -> Array[String] {
  let (running, stopped) = display_groups(model)
  let rows = if group == "running" { running } else { stopped }
  let out : Array[String] = []
  for row in rows {
    out.push(row.id)
  }
  out
}

///|
/// 拖动的落点：从 js_drop_target 那段 JSON 里取出 (指针底下那一格的卡片 id, 组名, 格子序号)。
///
/// `index` 是**这一组按屏幕顺序数**的格子序号（0 起）：指针压在哪张卡上就占哪一格。
/// 取不到（指针横向出了这一组的栅格 / 进到另一组 / JSON 不合形状）给 ("", "", -1)，
/// 调用方据此既不画占位块也不落位。
fn drop_target_of(x : Double, y : Double) -> (String, String, Int) {
  let text = js_drop_target(x, y)
  if text == "" {
    return ("", "", -1)
  }
  let json = try @json.parse(text) catch {
    // 解析不出来就当没有落点：宁可这一次拖动不落位，也不拿一个猜的位置去插
    _ =>
      return ("", "", -1)
  }
  match json {
    Json::Object(fields) =>
      (
        str_field(fields, "row"),
        str_field(fields, "group"),
        // 没有 index（横向出栅格 / 跨组）就当没有落点
        match int_field(fields, "index") {
          Some(v) => v
          None => -1
        },
      )
    _ => ("", "", -1)
  }
}

///|
/// **落点的唯一算法**：js_drop_target 给的格子序号就是结果里的位次，这里只做边界收口。
///
/// 卡槽语义下「指针压在第 i 张卡上」= 被拖的那一条占第 i 格：它从原处抽走之后
/// 插进第 i 格，其余各条按原次序填满剩下的格子。预览与落位都取这一个数，
/// 所以「占位块画在第几格」与「松手落在第几格」不可能分叉。
///
/// 边界：小于 0 落到最前（0）；大于 n-1 落到最后（n-1）。
fn drop_cell(n : Int, index : Int) -> Int {
  if n <= 1 {
    return 0
  }
  if index < 0 {
    return 0
  }
  if index > n - 1 {
    return n - 1
  }
  index
}

///|
/// 把被拖的那一条插进 ids 的第 k 格，返回整组的新顺序。
///
/// k 由 drop_cell 收口，所以这里的 k 就是**格子序号**：结果数组的第 k 个元素
/// 就是被拖的那一条。占位块也摆在同一个 k 上 —— 预览与结果因此逐格一致。
fn insert_row_at(ids : Array[String], dragged : String, k : Int) -> Array[String] {
  let rest : Array[String] = []
  for id in ids {
    if id != dragged {
      rest.push(id)
    }
  }
  let out : Array[String] = []
  let mut placed = false
  for i = 0; i <= rest.length(); i = i + 1 {
    if i == k && !placed {
      out.push(dragged)
      placed = true
    }
    if i < rest.length() {
      out.push(rest[i])
    }
  }
  if !placed {
    out.push(dragged)
  }
  out
}

///|
/// 两份顺序表是不是逐格相同。拖动落在原位（指针在被拖的那张自己身上）时靠它
/// 认出「这一次没有挪动」，从而不发请求。
fn same_order(a : Array[String], b : Array[String]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
/// 被拖的那一条现在排在第几格（0 起）；不在组里给 -1。
fn index_of_row(ids : Array[String], id : String) -> Int {
  let mut at = -1
  for i = 0; i < ids.length(); i = i + 1 {
    if ids[i] == id {
      at = i
    }
  }
  at
}

///|
/// 占位块要摆在**谁的前面**：结果顺序里第 k 格那条，就是此刻屏幕上的第 k 格那一条。
///
/// 为什么是它：被拖的那一条在拖动期间还留在原地（画成虚影占着那一格），没有从序列里消失。
/// 所以「其余条各自占哪一格」与结果顺序里「它们各自占哪一格」是同一件事 ——
/// 结果顺序的第 k 格那条，此刻正站在第 k 格。占位块插在它前面，就正好落在第 k 格。
/// 同理插在最后一条前面 = 落在它那一格，也就是最后一格。
///
/// k 越界（理论上不会）给空串：视图拿到空串就不插占位块，宁可不画也不画错一格。
fn anchor_at(ids : Array[String], k : Int) -> String {
  if k < 0 || k >= ids.length() {
    return ""
  }
  ids[k]
}

///|
/// 被拖的那一条按下的那一刻有多大（宽, 高）—— 虚影照这个尺寸画，整个拖动过程不变。
///
/// 为什么要照抄而不是给虚影一个固定尺寸：虚影说的是「这一条被拿在手上」，
/// 尺寸与它自己不一样的话，看着像换了一条东西在拖。
/// 中途不再重量：列表正在让位，再量一次可能量到挪开后的格子，虚影会跟着跳。
fn lift_sizes_of(id : String) -> (Double, Double) {
  let text = js_card_box(card_id(id))
  if text == "" {
    return (0.0, 0.0)
  }
  let json = try @json.parse(text) catch {
    _ => return (0.0, 0.0)
  }
  match json {
    Json::Object(fields) =>
      (
        match num_field(fields, "w") {
          Some(v) => v
          None => 0.0
        },
        match num_field(fields, "h") {
          Some(v) => v
          None => 0.0
        },
      )
    _ => (0.0, 0.0)
  }
}

///|
/// 位移过没过阈值。**用平方比，不开方**：这一步每次指针移动都要算一遍，
/// 而开方在这里没有任何意义（阈值只是个手感数）。
fn drag_past_threshold(x0 : Double, y0 : Double, x1 : Double, y1 : Double) -> Bool {
  let dx = x1 - x0
  let dy = y1 - y0
  dx * dx + dy * dy > drag_threshold_px * drag_threshold_px
}

///|
/// 把被拖的那一条挪到第 k 格（占位块现在所在的那一格），返回这一组的新顺序。
///
/// k < 0 = 没有落点，作废。**k 与占位块用的是同一个数**（见 drag_drop_index），
/// 所以「看到的」与「落到的」是同一件事，不可能差一格。
fn moved_group_ids(model : Model, dragged : String, k : Int) -> Array[String]? {
  let group = group_of_row_id(model, dragged)
  if group == "" || k < 0 {
    return None
  }
  let ids = current_group_ids(model, group)
  if index_of_row(ids, dragged) < 0 {
    return None
  }
  Some(insert_row_at(ids, dragged, k))
}

///|
/// 这一条属于哪一组；行不在列表里给空串。
fn group_of_row_id(model : Model, id : String) -> String {
  match find_row(model.rows, id) {
    Some(row) =>
      if row.archived_at is None {
        group_of(row)
      } else {
        // 归档行不在两组里，拖动不该碰它
        ""
      }
    None => ""
  }
}

///|
/// 把「某一组的新顺序」拼成**整份**顺序表提交。
///
/// 为什么整份提交：后端的 set-row-order 收的就是整份 —— 增量式接口要后端先读一份
/// 当前顺序再算，两次并发拖动会互相覆盖。组内顺序换了的那一组用新的，
/// 另一组保持它现在显示的顺序（不因为动了一组就把另一组也重写一遍）。
fn compose_order(model : Model, group : String, moved : Array[String]) -> Array[String] {
  let out : Array[String] = []
  if group == "running" {
    for id in moved {
      out.push(id)
    }
    for id in current_group_ids(model, "stopped") {
      out.push(id)
    }
  } else {
    for id in current_group_ids(model, "running") {
      out.push(id)
    }
    for id in moved {
      out.push(id)
    }
  }
  out
}

///|
/// 提交一份新顺序：**先就地生效，再写回**；写回失败由 OrderDone 回滚。
///
/// 为什么要乐观更新：拖完松手那一刻列表必须已经在新位置上 —— 等一趟 HTTP
/// 再动，手上会有一段「拖了没反应」的空档。代价是失败时要自己擦干净，
/// 那一步在 OrderDone 里，且必须擦（见那里的注释）。
fn commit_order(
  model : Model,
  dragged : String,
  moved : Array[String],
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let group = group_of_row_id(model, dragged)
  let full = compose_order(model, group, moved)
  let next = { ..model, order_before: model.order, order: full }
  // 焦点跟着**被挪的那一条**走：列表是按位置打补丁的，不补这一下，
  // 键盘用户按完 Ctrl+↓ 焦点还停在原来那一格上，而那一格现在是别的条目了。
  (
    next,
    @cmd.batch([
      order_action_cmd(full, emit),
      focus_after_render(card_id(dragged)),
      // 落位这一拍也让位：被拖的那一条回到占位块那一格、其余各挪一格，
      // 都是位置变化，一起交给 FLIP 演（撤格子排在 FLIP 之后：
      // 先按摆好的格子把这段变化演出来，撤掉之后就是文档流里的终局）。
      @cmd.batch([reorder_after_render(), clear_cells_after_render()]),
    ]),
  )
}

///|
/// patch 行数 / lock 时刻这一行：档案的健康读数，运行中卡与停止卡共用同一口径。
fn patch_lock_note(fact : ProfileFact) -> String {
  "cordis.patch.yml " + fact.patch_lines.to_string() + " 行 | " +
  (if fact.lock_exists {
    match fact.lock_mtime {
      Some(mtime) =>
        match js_short_time(mtime) {
          "" => "lock —"
          text => "lock " + text
        }
      None => "lock —"
    }
  } else {
    "无 pnpm-lock.yaml"
  })
}

///|
/// 这只 profile 是否正被某个可见进程用着。
///
/// 判据是 **(名字, home)**：一份档案的身份是两段，同名不同 home 是两份。
/// 只按名字比是错的 —— 多 home 之后，另一 home 的同名实例在跑就会把这一行整条藏掉 ✗
fn in_use_by(fact : ProfileFact, running : Array[InstanceFact], profiles_home : String) -> Bool {
  for inst in running {
    match inst.profile {
      Some(used) =>
        if used == fact.name {
          // home 也要对上：同名不同 home 是两份档案，另一 home 的那只在跑，
          // 不等于这一只被用着。对不上就**不认**（含两边任一认不出 home 的情形）——
          // 认了就等于把这一行从列表里藏掉，而它其实规规矩矩地躺在磁盘上
          let inst_home = match inst.dsh_home {
            Some(h) => h
            None => ""
          }
          if same_home(inst_home, profiles_home) {
            return true
          }
        }
      None => ()
    }
  }
  false
}

// ── 卡片第六格「最近改动」 ──────────────────────────────────
//
// 卡片字段区是 2 列 × 3 行 = 6 格。前五格是 DSH 版本 / Profile / 访问地址 / DSH_HOME /
// 插件数量，第六格是「最近改动」：这只 profile **目录**的 mtime。
//
// **为什么不是「创建时间」**：多数文件系统上可靠的创建时间拿不到 ——
// ctime 记的是 inode 变更时间，chmod / 改名都会把它推新（不是出生时间）；
// birth time 不通用（不是每个文件系统都存，也不是每个平台都读得到）。
// 目录 mtime 是能拿到、且不会骗人的那一个 ✓
// 而且刚派生出来的 profile 一定是最新的，所以「最近改动」顺带回答了使用者那句
// 「我都不知道它忽然冒出来这个新的」—— 派生完它就排在最上面。
// 界面上这一格的标签、以及这里的所有注释，都不许写成「创建时间」✗
