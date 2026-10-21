// 维护页的版本表：版本解析与比较、来源与发布时间、筛选与排序、版本行与「选择版本」侧栏。
//
// 2026-10-20 从 view_maintenance.mbt 拆出来：版本这一族是纯读 + 排序的比较逻辑，
// 单独一份更好核对。只搬位置，函数体一个字没改。

///|
/// 来源 id → 正文里那个名字。认不出的 id 原样写（不编一个名字）。
fn release_source_name(id : String) -> String {
  match id {
    "github" => "GitHub"
    "npm" => "npm"
    "mirror" => "国内镜像"
    _ => id
  }
}

///|
/// 来源小字那一行的悬停：三个源各自的结果与耗时，一个都不省。
///
/// 为什么把「过了多久」也写出来：三个源里哪个慢（甚至慢到超时）是使用者判断
/// 「要不要还等它」的唯一依据；只写「成功了」等于把这一条藏起来。
fn release_sources_hint(sources : Array[ReleaseSource]) -> String {
  let parts : Array[String] = []
  for source in sources {
    let name = release_source_name(source.id)
    if source.ok {
      parts.push(
        name +
        "：" +
        source.count.to_string() +
        " 个版本，" +
        source.ms.to_string() +
        "ms",
      )
    } else {
      let why = if source.error == "" {
        "没答上来，原因没给"
      } else {
        source.error
      }
      parts.push(name + "：" + why + "（" + source.ms.to_string() + "ms）")
    }
  }
  parts.join("；")
}

///|
/// 一条版本的悬停：每枚标记凭什么打上。
///
/// 正文的标记那一格只放得下两枚（§12.2），而「registry 的 latest / next 指向哪一版」
/// 这两条读数不进正文 —— 它们与其它依据一起进悬停，不然后端算出来的东西在界面上
/// 一个落点都没有。
fn release_option_hint(item : ReleaseVersion) -> String {
  let parts : Array[String] = []
  if item.installed {
    parts.push("这台机器上装着这一版")
  }
  if item.latest {
    parts.push("registry 的 latest 指向这一版")
  }
  if item.next {
    parts.push("registry 的 next 指向这一版")
  }
  if item.prerelease {
    parts.push("这一版带预发布后缀（预发布）")
  } else {
    parts.push("这一版是正式发布（版本号不带预发布后缀）")
  }
  parts.join("；")
}

///|
/// 一次过滤给出几条候选。理由：npm 那个 registry 的 versions 键可能有几百条，
/// 全摊开的话这一块比整张作业卡都高；剩下的条数如实写在最后一行，使用者接着写就能收窄。
let job_version_list_cap : Int32 = 20

///|
/// 表单里「目标版本」那一格（§10.2 / §12.1）：一行「当前版本」+ 一颗「选择版本」按钮。
/// 没选时写「未选择」；候选不再常驻，点按钮开**右侧栏**（与「选择配置」同一套外壳）。
fn job_version_current(
  model : Model,
  disabled : Bool,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let picked = model.job_version.trim().to_owned()
  let value = if picked == "" { "未选择" } else { picked }
  @html.div(class="dsh-job-current", [
    @html.span(
      class="dsh-job-current-label",
      attrs=mark("job-version-current-label", [
        "maintenance", "start", "version-current-label",
      ]),
      "当前版本",
    ),
    @html.span(
      class="dsh-job-current-value",
      attrs=mark("job-version-current", [
        "maintenance", "start", "version-current",
      ]).data_set("state", if picked == "" { "empty" } else { "picked" }),
      value,
    ),
    @html.button(
      id=version_choose_id(),
      class="dsh-btn dsh-job-choose",
      type_="button",
      disabled~,
      attrs=mark("job-version-choose", [
        "maintenance", "start", "version-choose",
      ]).aria_label("选择目标版本"),
      on_click=emit(VersionSidebarOpen),
      [@html.span("选择版本")],
    ),
  ])
}

///|
/// 拉取时刻那一格：ISO 转浏览器本地的 MM-DD HH:MM，解析不出来就照原样显示（不吞）。
fn release_stamp_text(iso : String) -> String {
  if iso == "" {
    ""
  } else {
    let short = js_short_time(iso)
    if short == "" {
      iso
    } else {
      short
    }
  }
}

// ── 版本侧栏（§12.1 到 §12.3）────────────────────────────────
//
// 目标版本从居中弹层改成右侧栏，与「选择配置」同一套外壳（遮罩 + 右侧面板 + Esc，
// 焦点先进搜索框）。里面是一张表：版本 / 标记 / 发布时间。
// 标记四档按规格上色，文字同时在场；一版多标记时最多显示两个，其余进悬停。
// 过滤（chip，多选）与排序（三档）都在前端做，与顶部搜索三者叠加。

///|
/// 版本表上的一枚标记：key 进 data-kind 与样式（颜色），文字同时进正文 ——
/// 颜色从来不是唯一信号（§12.2）。
priv struct VersionMark {
  key : String
  text : String
}

///|
/// 现在生效的那份 dsh 是哪个版本（§12.2 的「当前在用」认它）。
///
/// 先看 runtime 读数里打了 active 的那份候选（「起实例会用这一份」，后端判的）；
/// 候选里一个 active 都没有才退回 dshVersion —— 那是同一条链的结论。
/// **不按「版本号最高」自己挑一份**：猜错就会把别的版本说成在用的那一版。
fn active_dsh_version(model : Model) -> String {
  match model.runtime {
    Some(facts) => {
      for cand in facts.dsh_candidates {
        if cand.active && cand.version != "" {
          return cand.version
        }
      }
      facts.dsh_version
    }
    None => ""
  }
}

///|
/// 一版的标记，按 §12.2 那张表的顺序排：当前在用 / 已安装 / 正式发布 / 预发布。
///
/// 正式发布与预发布互斥（判据是版本号带不带预发布后缀，后端给的 prerelease 就是它），
/// 所以每一版至少有一枚；在用的那一版通常同时是已安装的。
fn version_marks(
  item : ReleaseVersion,
  active_version : String,
) -> Array[VersionMark] {
  let out : Array[VersionMark] = []
  if active_version != "" && item.version == active_version {
    out.push({ key: "current", text: "当前在用", })
  }
  if item.installed {
    out.push({ key: "installed", text: "已安装", })
  }
  if item.prerelease {
    out.push({ key: "prerelease", text: "预发布", })
  } else {
    out.push({ key: "stable", text: "正式发布", })
  }
  out
}

///|
/// 一行的悬停全文：这一版带的所有标记（正文只放得下两枚）+ 每枚凭什么打上 +
/// 完整发布时间（正文那一格是本地短时刻）。
fn version_row_hint(
  item : ReleaseVersion,
  marks : Array[VersionMark],
) -> String {
  let parts : Array[String] = []
  if marks.length() > 0 {
    let words : Array[String] = []
    for mark in marks {
      words.push(mark.text)
    }
    parts.push("标记：" + words.join(" · "))
  }
  parts.push(release_option_hint(item))
  if item.published_at != "" {
    parts.push("发布时间：" + item.published_at)
  }
  parts.join("\n")
}

///|
/// 发布时间那一格：空串 = 不知道（§12.2 是写「不知道」，不拿拉取时间顶替）。
fn release_published_text(item : ReleaseVersion) -> String {
  if item.published_at == "" {
    "不知道"
  } else {
    let short = js_short_time(item.published_at)
    if short == "" {
      item.published_at
    } else {
      short
    }
  }
}

///|
/// 版本号切成 (core 数字段, 预发布段)："0.2.1-rc.2" → ([0, 2, 1], "rc.2")。
/// 与后端 releases.mbt 的 split_version 同一口径（两端排序必须说同一件事）。
fn version_segments(version : String) -> (Array[Int32], String) {
  let core : Array[Int32] = []
  let pre = StringBuilder()
  let mut in_pre = false
  let mut n = 0
  for c in version {
    if in_pre {
      pre.write_char(c)
    } else if c == '-' {
      core.push(n)
      n = 0
      in_pre = true
    } else if c == '.' {
      core.push(n)
      n = 0
    } else if c >= '0' && c <= '9' {
      n = n * 10 + (c.to_int() - 48)
    } else {
      // 版本号里不会出现的字符：当这一段结束，不编数字（排序照旧稳定）
      core.push(n)
      n = 0
    }
  }
  if !in_pre {
    core.push(n)
  }
  (core, pre.to_string())
}

///|
/// 一串按 '.' 切的段。版本号这种小串，逐字符扫一遍就够，不引别的库。
fn segments_of(text : String) -> Array[String] {
  let out : Array[String] = []
  let mut buf = StringBuilder()
  for c in text {
    if c == '.' {
      out.push(buf.to_string())
      buf = StringBuilder()
    } else {
      buf.write_char(c)
    }
  }
  out.push(buf.to_string())
  out
}

///|
fn is_digits_text(text : String) -> Bool {
  if text == "" {
    return false
  }
  for c in text {
    if c < '0' || c > '9' {
      return false
    }
  }
  true
}

///|
fn dec_text(text : String) -> Int32 {
  let mut n = 0
  for c in text {
    n = n * 10 + (c.to_int() - 48)
  }
  n
}

///|
/// 预发布段逐段比：两边都是数字就按数字，否则按字面；前缀相同、段数多的那份更大。
fn compare_pre_text(a : String, b : String) -> Int32 {
  let xs = segments_of(a)
  let ys = segments_of(b)
  let n = if xs.length() < ys.length() { xs.length() } else { ys.length() }
  for i = 0; i < n; i = i + 1 {
    let x = xs[i]
    let y = ys[i]
    if x == y {
      continue
    }
    if is_digits_text(x) && is_digits_text(y) {
      let xi = dec_text(x)
      let yi = dec_text(y)
      if xi != yi {
        return if xi < yi { -1 } else { 1 }
      }
      continue
    }
    let c = x.lexical_compare(y)
    if c != 0 {
      return if c < 0 { -1 } else { 1 }
    }
  }
  if xs.length() == ys.length() {
    0
  } else if xs.length() < ys.length() {
    -1
  } else {
    1
  }
}

///|
/// 两个版本号谁大（-1 / 0 / 1）：core 逐段比（缺的段当 0），core 相同则正式版更大，
/// 两个都预发布时比预发布段。与后端 compare_version 同一口径。
fn compare_version_text(a : String, b : String) -> Int32 {
  let (ac, ap) = version_segments(a)
  let (bc, bp) = version_segments(b)
  let n = if ac.length() < bc.length() { bc.length() } else { ac.length() }
  for i = 0; i < n; i = i + 1 {
    let x = if i < ac.length() { ac[i] } else { 0 }
    let y = if i < bc.length() { bc[i] } else { 0 }
    if x != y {
      return if x < y { -1 } else { 1 }
    }
  }
  if ap == "" && bp == "" {
    return 0
  }
  if ap == "" {
    return 1
  }
  if bp == "" {
    return -1
  }
  compare_pre_text(ap, bp)
}

///|
/// 「按发布时间」这一档的比较：新的在前，**没有发布时间的沉底**
/// （不知道就是不知道，不排到最前面冒充最新）。
///
/// 发布时间按 ISO 串字面比：两个源给的都是 UTC（Z 结尾），字面次序就是时间次序。
fn compare_published_desc(a : ReleaseVersion, b : ReleaseVersion) -> Int32 {
  if a.published_at == "" && b.published_at == "" {
    0
  } else if a.published_at == "" {
    1
  } else if b.published_at == "" {
    -1
  } else {
    let c = a.published_at.lexical_compare(b.published_at)
    if c > 0 {
      -1
    } else if c < 0 {
      1
    } else {
      0
    }
  }
}

///|
/// 按当前那一档排序（§12.3）。三档都拿版本的次序当兜底，结果是全序 ——
/// 不因为排序算法稳不稳定而换个样子。只动这一份副本，不改读数。
fn version_sorted(
  items : Array[ReleaseVersion],
  sort : String,
) -> Array[ReleaseVersion] {
  let out = items.copy()
  out.sort_by(fn(a, b) {
    let by_version = compare_version_text(a.version, b.version)
    if sort == "old" {
      by_version
    } else if sort == "published" {
      let by_time = compare_published_desc(a, b)
      if by_time != 0 {
        by_time
      } else {
        -by_version
      }
    } else {
      -by_version
    }
  })
  out
}

///|
/// 这一版过不过当前的 chip（§12.3）：空数组 = 「全部」。
///
/// 多个 chip 之间是「或」：勾「已安装」与「预发布」要的是两类的并集 ——
/// 交集在真实使用里几乎总是空的（装着的预发布很少），那不是一个帮得上忙的过滤。
fn version_passes_filters(
  item : ReleaseVersion,
  filters : Array[String],
) -> Bool {
  if filters.length() == 0 {
    return true
  }
  for key in filters {
    if key == "installed" && item.installed {
      return true
    }
    if key == "stable" && !item.prerelease {
      return true
    }
    if key == "prerelease" && item.prerelease {
      return true
    }
  }
  false
}

///|
/// 一枚过滤 chip。选中的那一枚除了颜色，还有 aria-pressed=true 与 data-on ——
/// 颜色不是唯一信号。
fn version_chip(
  label : String,
  key : String,
  active : Bool,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  @html.button(
    class=if active { "dsh-version-chip on" } else { "dsh-version-chip" },
    type_="button",
    attrs=mark("job-version-filter", [
        "maintenance", "version-sidebar", "filter", key,
      ])
      .data_set("filter", key)
      .data_set("on", if active { "true" } else { "false" })
      .aria_pressed(if active { "true" } else { "false" }),
    on_click=emit(VersionFilterToggle(key)),
    [@html.span(label)],
  )
}

///|
/// 版本表的一行：版本 / 标记 / 发布时间。
///
/// 整行可点（鼠标 / Enter / 空格，与侧栏里的卡同一套），选中的那一行多一档底色与
/// 左侧竖线 —— 但「选中」这件事同时写在 aria 里，不只靠那一道线。
fn version_row(
  item : ReleaseVersion,
  active_version : String,
  selected : Bool,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let marks = version_marks(item, active_version)
  // 最多显示两枚（§12.2），其余进悬停
  let shown = if marks.length() > 2 { marks[:2].to_owned() } else { marks }
  let mark_cells : Array[@html.Html] = []
  for badge in shown {
    mark_cells.push(
      @html.span(
        class="dsh-version-mark",
        attrs=mark("job-version-mark", [
          "maintenance",
          "version-sidebar",
          item.version,
          "mark",
          badge.key,
        ]).data_set("kind", badge.key),
        badge.text,
      ),
    )
  }
  let words : Array[String] = []
  for badge in marks {
    words.push(badge.text)
  }
  let label = if words.length() == 0 {
    "选这一版 " + item.version
  } else {
    "选这一版 " + item.version + "（" + words.join("、") + "）"
  }
  @html.tr(
    class=if selected { "dsh-version-row selected" } else { "dsh-version-row" },
    attrs=mark("job-version-option", [
        "maintenance",
        "version-sidebar",
        "option",
        item.version,
      ])
      .data_set("version", item.version)
      .data_set("selected", if selected { "true" } else { "false" })
      .data_set("installed", if item.installed { "true" } else { "false" })
      .data_set("prerelease", if item.prerelease { "true" } else { "false" })
      .role("button")
      .tabindex(0)
      .aria_label(label)
      .title(version_row_hint(item, marks))
      .on_click(fn(_event) { emit(JobVersionPicked(item.version)) })
      .on_keydown(fn(event) {
        if event.key() == "Enter" || event.key() == " " {
          emit(JobVersionPicked(item.version))
        } else {
          @cmd.none
        }
      }),
    [
      @html.td(
        class="dsh-version-cell",
        attrs=mark("job-version-cell", [
          "maintenance",
          "version-sidebar",
          item.version,
          "version",
        ]),
        item.version,
      ),
      @html.td(
        class="dsh-version-marks",
        attrs=mark("job-version-marks-cell", [
          "maintenance",
          "version-sidebar",
          item.version,
          "marks",
        ]),
        mark_cells,
      ),
      @html.td(
        class="dsh-version-published",
        attrs=mark("job-version-published", [
          "maintenance",
          "version-sidebar",
          item.version,
          "published",
        ]),
        release_published_text(item),
      ),
    ],
  )
}

///|
/// 版本侧栏（§12.1）：与「选择配置」同一套外壳（遮罩 + 右侧面板 + Esc），
/// 打开时焦点进搜索框，关掉之后焦点回「选择版本」那颗按钮。
///
/// 从上到下：搜索框 → 过滤 chip → 排序 → 版本表（最多 20 条）→ 自定义版本那一行 →
/// 底部小字（来源、拉取时间、「正在重新拉取」或失败原因）与「重新拉取」。
///
/// 状态说三档，与后端缓存那三格对齐：
///   loading  → 还没有候选时写「正在拉版本列表」；有旧候选就照旧列出来（底部说正在重新拉取）
///   ready    → 候选 + 来源 + 拉取时间
///   failed   → 写明上次没拉到的原因，搜索框照旧能写（写了就是自定义版本）
fn job_version_sidebar(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let facts = model.releases
  let versions = match facts {
    Some(got) => got.versions
    None => []
  }
  let state = match facts {
    Some(got) => got.state
    None => if model.releases_loading { "loading" } else { "" }
  }
  let loading = state == "loading" || model.releases_loading
  let query = model.version_query.trim().to_owned()
  let active_version = active_dsh_version(model)
  // 搜索 + 过滤叠加（两者都是「这一版要不要进表」），再按当前那一档排序，最后封顶 20 条
  let matched : Array[ReleaseVersion] = []
  for item in versions {
    if (query == "" || job_version_matches(item.version, query)) &&
      version_passes_filters(item, model.version_filters) {
      matched.push(item)
    }
  }
  let sorted = version_sorted(matched, model.version_sort)
  let shown = if sorted.length() > job_version_list_cap {
    sorted[:job_version_list_cap].to_owned()
  } else {
    sorted
  }
  let mut exact = false
  for item in versions {
    if item.version == query {
      exact = true
    }
  }
  let body : Array[@html.Html] = [
    @html.input(
      input_type=Text,
      id=version_search_id(),
      class="dsh-dialog-input dsh-version-search",
      value=model.version_query,
      placeholder="输入版本号过滤，或直接写自定义版本",
      autofocus=true,
      attrs=mark("job-version-search", [
          "maintenance", "version-sidebar", "search",
        ])
        .aria_label("搜索版本")
        .spellcheck(false),
      on_input=emit.map(fn(text) { VersionQueryInput(text) }),
    ),
  ]
  // 过滤 chip：全部 / 已安装 / 正式发布 / 预发布。多选，全部 = 一个都不选。
  body.push(
    @html.div(
      class="dsh-version-filters",
      attrs=mark("job-version-filters", [
          "maintenance", "version-sidebar", "filters",
        ])
        .role("group")
        .aria_label("过滤"),
      [
        version_chip("全部", "all", model.version_filters.length() == 0, emit),
        version_chip(
          "已安装",
          "installed",
          model.version_filters.contains("installed"),
          emit,
        ),
        version_chip(
          "正式发布",
          "stable",
          model.version_filters.contains("stable"),
          emit,
        ),
        version_chip(
          "预发布",
          "prerelease",
          model.version_filters.contains("prerelease"),
          emit,
        ),
      ],
    ),
  )
  // 排序三档。用下拉而不是一排 chip：它选的是**同一样东西的读法**，不是三个并列的条件。
  let sort_options : Array[@html.Html] = []
  let sort_choices : Array[(String, String)] = [
    ("new", "版本从新到旧"),
    ("old", "从旧到新"),
    ("published", "按发布时间"),
  ]
  for choice in sort_choices {
    let (key, label) = choice
    sort_options.push(
      @html.option(
        value=key,
        selected=model.version_sort == key,
        attrs=mark("job-version-sort-option", [
          "maintenance", "version-sidebar", "sort", key,
        ]),
        [@html.text(label)],
      ),
    )
  }
  body.push(
    @html.div(class="dsh-version-sort", [
      @html.select(
        id="dsh-job-version-sort",
        class="dsh-select",
        attrs=mark("job-version-sort", [
          "maintenance", "version-sidebar", "sort",
        ]).aria_label("排序"),
        on_change=emit.map(fn(value) { VersionSortPicked(value) }),
        sort_options,
      ),
    ]),
  )
  if shown.length() > 0 {
    let rows : Array[@html.Html] = []
    for item in shown {
      let selected = item.version == model.job_version
      rows.push(version_row(item, active_version, selected, emit))
    }
    let head_cells : Array[@html.Html] = [
      @html.th(
        scope=@html.Scope::Col,
        attrs=mark("job-version-th", [
          "maintenance", "version-sidebar", "th", "version",
        ]),
        [@html.text("版本")],
      ),
      @html.th(
        scope=@html.Scope::Col,
        attrs=mark("job-version-th", [
          "maintenance", "version-sidebar", "th", "marks",
        ]),
        [@html.text("标记")],
      ),
      @html.th(
        scope=@html.Scope::Col,
        attrs=mark("job-version-th", [
          "maintenance", "version-sidebar", "th", "published",
        ]),
        [@html.text("发布时间")],
      ),
    ]
    body.push(
      @html.div(class="dsh-version-table-wrap", [
        @html.table(
          class="dsh-version-table",
          attrs=mark("job-version-table", [
            "maintenance", "version-sidebar", "table",
          ]),
          [@html.thead([@html.tr(head_cells)]), @html.tbody(rows)],
        ),
      ]),
    )
    if sorted.length() > shown.length() {
      body.push(
        @html.span(
          class="dsh-job-version-more",
          attrs=mark("job-version-more", [
            "maintenance", "version-sidebar", "more",
          ]),
          "还有 " +
          (sorted.length() - shown.length()).to_string() +
          " 条匹配，继续输入缩小范围",
        ),
      )
    }
  } else if versions.length() > 0 || query != "" {
    // 有候选却一条都不剩：要么被过滤掉了，要么搜索没命中。两件事一句话说都不够准确，
    // 所以只写「没有符合条件的版本」—— 它同时是搜索与过滤的结果，不替使用者判定是哪一个。
    body.push(
      @html.span(
        class="dsh-job-version-none",
        attrs=mark("job-version-empty", [
          "maintenance", "version-sidebar", "empty",
        ]),
        "没有符合条件的版本",
      ),
    )
    // 没有候选、也没输入：要么还在拉，要么拉到了却没有答案 —— 两件事分开说
  } else if loading {
    body.push(
      @html.span(
        class="dsh-version-dialog-note",
        attrs=mark("job-version-loading", [
          "maintenance", "version-sidebar", "loading",
        ]),
        "正在拉版本列表",
      ),
    )
  } else {
    let (text, hint) = match facts {
      Some(got) =>
        (
          "一个源都没答上来，直接写版本号再点「用这个版本」",
          release_sources_hint(got.sources),
        )
      None =>
        (
          "没读到版本来源，直接写版本号再点「用这个版本」",
          if model.releases_error == "" {
            "这一版读数里没有版本来源"
          } else {
            model.releases_error
          },
        )
    }
    body.push(
      @html.span(
        class="dsh-job-version-none",
        attrs=mark("job-version-none", [
          "maintenance", "version-sidebar", "none",
        ]).title(hint),
        text,
      ),
    )
  }
  // 自定义版本：输入串不在列表里（没有一模一样的版本号）就给这一行，点了按它开工。
  // 过滤把结果清空时这一行照样在：它说的是「你写的那串可以直接用」，与列表里剩几条无关。
  // 不做存在性校验（控制台不猜远端有什么），装不上由安装那一步如实报失败。
  if query != "" && !exact {
    body.push(
      @html.div(class="dsh-version-custom-row", [
        @html.span(
          class="dsh-job-version-custom",
          attrs=mark("job-version-custom", [
            "maintenance", "version-sidebar", "custom",
          ]),
          "列表里没有 " + query + "，",
        ),
        @html.button(
          id="dsh-job-version-use-custom",
          class="dsh-dialog-btn",
          type_="button",
          attrs=mark("job-version-use-custom", [
            "maintenance", "version-sidebar", "use-custom",
          ]),
          on_click=emit(JobVersionPicked(query)),
          [@html.span("用这个版本")],
        ),
      ]),
    )
  }
  // 底部小字：**只剩来源与拉取时间**（§14.3）。「重新拉取没成」走全局提示 ——
  // 它是动作结果；「正在重新拉取」由那颗按钮自己说（按下去之后按钮就是这个字）。
  // 悬停里是三个源各自的结果与耗时。
  let chosen = match facts {
    Some(got) => got.chosen
    None => ""
  }
  let fetched_at = match facts {
    Some(got) => got.fetched_at
    None => ""
  }
  let fetch_error = match facts {
    Some(got) => got.fetch_error
    None => ""
  }
  let source_name = if chosen == "" {
    "没有答上来的来源"
  } else {
    release_source_name(chosen)
  }
  let mut meta = "来源：" + source_name
  let stamp = release_stamp_text(fetched_at)
  if stamp != "" {
    meta = meta + " · 拉取于 " + stamp
  }
  // 「上次没拉到」是**读取失败**，不是动作结果：按 §14.4 留在原位（这一栏里），
  // 不进全局提示，也不从界面上消失。
  if fetch_error != "" && !loading {
    body.push(
      @html.span(
        class="dsh-version-dialog-status",
        attrs=mark("job-version-status", [
          "maintenance", "version-sidebar", "status",
        ]),
        "上次没拉到：" + fetch_error,
      ),
    )
  }
  let foot : Array[@html.Html] = [
    @html.span(
      class="dsh-version-dialog-meta",
      attrs=mark("job-version-meta", ["maintenance", "version-sidebar", "meta"]).title(
        match facts {
          Some(got) => release_sources_hint(got.sources)
          None => "读数里没有三个源的结果"
        },
      ),
      meta,
    ),
  ]
  // 手动重拉（§11.3）：只负责排一趟后台刷新，结果照旧靠轮询接上。
  // 在路上时按钮按成「正在重新拉取」并禁用，避免同一拍连点把补问预算耗掉。
  foot.push(
    @html.div(class="dsh-version-foot-btn", [
      @html.button(
        id="dsh-job-version-refresh",
        class="dsh-dialog-btn",
        type_="button",
        disabled=loading,
        attrs=mark("job-version-refresh", [
          "maintenance", "version-sidebar", "refresh",
        ]),
        on_click=emit(ReleasesRefresh),
        [
          @html.text(
            if loading {
              "正在重新拉取"
            } else {
              "重新拉取"
            },
          ),
        ],
      ),
    ]),
  )
  body.push(
    @html.div(
      class="dsh-version-dialog-foot",
      attrs=mark("job-version-foot", ["maintenance", "version-sidebar", "foot"]),
      foot,
    ),
  )
  @html.fragment([
    @html.div(
      class="dsh-drawer-scrim",
      attrs=mark("job-version-sidebar-scrim", [
        "maintenance", "version-sidebar", "scrim",
      ]).data_set("state", "open"),
      on_click=emit(VersionSidebarClose),
      @html.nothing,
    ),
    @html.aside(
      id="dsh-job-version-sidebar",
      class="dsh-drawer",
      attrs=mark("job-version-sidebar", ["maintenance", "version-sidebar"])
        .role("dialog")
        .aria_modal("true")
        .aria_label("选择版本")
        .data_set("state", "open")
        .on_keydown(fn(event) {
          if event.key() == "Escape" {
            emit(VersionSidebarClose)
          } else {
            @cmd.none
          }
        }),
      [
        @html.div(class="dsh-drawer-head", [
          @html.span(
            class="dsh-drawer-name",
            attrs=mark("job-version-sidebar-title", [
              "maintenance", "version-sidebar", "title",
            ]),
            "选择版本",
          ),
          @html.button(
            id=version_sidebar_close_id(),
            class="dsh-btn icon-only",
            type_="button",
            attrs=mark("job-version-sidebar-close", [
              "maintenance", "version-sidebar", "close",
            ]).aria_label("关闭选择版本"),
            on_click=emit(VersionSidebarClose),
            [icon("close", size=16)],
          ),
        ]),
        @html.div(class="dsh-drawer-body", body),
      ],
    ),
  ])
}

///|
/// 候选是否匹配输入框里的那串：按包含判（写 "0.2.2" 能列出 0.2.2 与 0.2.2-rc.1）。
/// 大小写不敏感 —— 版本号里偶尔带字母（rc / beta），不该逼使用者记住大小写。
fn job_version_matches(version : String, query : String) -> Bool {
  version.to_lower().contains(query.to_lower())
}
