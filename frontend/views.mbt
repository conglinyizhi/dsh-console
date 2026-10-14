// 页面视图。
//
// 切片范围：关于页 + 一张运行中实例卡。两者都用接口真数据，读不到就如实写「未知」/「读取失败」。
//
// DOM 上刻意挂 data-name：类名会随样式层换（md2 的类名 vs 我们自己的），
// data-name 不会 —— 截图脚本、DOM 实测脚本、后续的渲染基线都按它定位。

///|
fn kv_row(label : String, value : String, hint : String) -> @html.Html {
  @html.div(
    class="dsh-row",
    attrs=@html.Attrs::build().data_set("name", "kv-row"),
    [
      @html.span(class="dsh-label", label),
      @html.span(class="dsh-value", title=hint, value),
    ],
  )
}

///|
/// 版本表：每项都是真实读数；读不到就写「读取失败」与原因，不写空。
///
/// 没有「node 版本」这一行 —— 后端换掉之后那个字段已经不存在了，同一行的正确含义
/// 是「后端自己的运行时」，本切片按约定直接省掉，不拿别处的数字顶上来。
fn version_rows(model : Model) -> Array[@html.Html] {
  match model.runtime {
    None => [kv_row("读取状态", "读取失败", model.runtime_error)]
    Some(facts) =>
      [
        kv_row("dsh 版本", facts.dsh_version, facts.dsh_package_name),
        kv_row(
          "控制台版本",
          if facts.console_version.length() > 0 {
            facts.console_version
          } else {
            "未知"
          },
          facts.console_package_name,
        ),
        kv_row("平台", facts.platform, ""),
      ]
  }
}

///|
fn about_panel() -> @html.Html {
  @md2.card(
    variant=Outlined,
    class="dsh-panel",
    attrs=@html.Attrs::build().data_set("name", "about-panel"),
    children=[
      @html.header(class="dsh-page-head", [
        @html.h1(class="dsh-page-title", "关于"),
      ]),
      @html.p(
        class="dsh-para",
        "面向个人本机使用的 DSH 控制台，用来查看这台机器上的 DeepSeek Harness 实例。",
      ),
      @html.p(class="dsh-para", "只读本机 ~/.dsh；页面上的动作均为演示。"),
    ],
  )
}

///|
fn version_panel(model : Model) -> @html.Html {
  @md2.card(
    variant=Outlined,
    class="dsh-panel",
    attrs=@html.Attrs::build().data_set("name", "version-panel"),
    children=[
      @html.h2(class="dsh-panel-title", "版本"),
      @html.div(class="dsh-kv", version_rows(model)),
      @html.p(
        class="dsh-foot",
        "读于 " + model.read_time + " · 来源 GET /api/local/runtime",
      ),
    ],
  )
}

///|
fn field(icon_name : String, label : String, value : String, hint : String) -> @html.Html {
  @html.li(class="dsh-field", [
    @html.span(class="dsh-field-icon", [@md2.icon(icon_name~, size=XSmall)]),
    @html.span(class="dsh-field-label", label),
    @html.span(class="dsh-field-value", title=hint, value),
  ])
}

///|
/// 运行中实例卡。
///
/// 形状照着现有 Vue 版那张卡来：两行卡头（标题行 + 副标题行：类型标签 / 状态点 /
/// 状态文案 / 末轨）+ 四个按钮（打开 Web UI、停止、重启、⋯）+ 五个字段。
/// 四个按钮都是**演示**：本切片不接写接口，点击不发请求。
fn instance_card(fact : InstanceFact) -> @html.Html {
  let name = if fact.profile.length() > 0 {
    fact.profile + " :" + fact.port.to_string()
  } else {
    "dsh :" + fact.port.to_string()
  }
  let kind_hint = "从 /proc/net/tcp(6) 的 loopback LISTEN 端口探测到，命中判据 " +
    fact.signature_id
  let uptime = match fact.uptime_seconds {
    None => "运行时长未知"
    Some(seconds) =>
      if seconds < 3600 {
        "已运行 " + (seconds / 60).to_string() + " 分钟"
      } else {
        "已运行 " + (seconds / 3600).to_string() + " 小时 " +
        ((seconds % 3600) / 60).to_string() + " 分钟"
      }
  }
  let uptime_hint = match fact.uptime_seconds {
    None => "探测到监听端口，但本进程读不到宿主进程（PID 命名空间被隔离），运行时长未知"
    Some(_) => ""
  }
  @md2.card(
    variant=Outlined,
    class="dsh-case",
    attrs=@html.Attrs::build()
      .data_set("name", "instance-card")
      .data_set("instance", name),
    children=[
      @html.div(class="dsh-case-head", [
        @html.span(class="dsh-tile", [
          @md2.icon(icon_name="mdi-open-in-new", size=Small),
        ]),
        @html.div(class="dsh-ident", [
          @html.div(class="dsh-title-line", [
            @html.span(class="dsh-name", name),
          ]),
          @html.div(
            class="dsh-sub",
            attrs=@html.Attrs::build().data_set("status", "running"),
            [
              @html.span(class="dsh-kind", title=kind_hint, "本机监听的 dsh 实例"),
              @html.span(class="dsh-dot-slot", [
                @html.i(class="dsh-dot", @html.nothing),
              ]),
              @html.span(class="dsh-state", "运行中"),
              @html.span(class="dsh-tail", [
                @html.span(class="dsh-uptime", title=uptime_hint, uptime),
              ]),
            ],
          ),
        ]),
        @html.div(class="dsh-actions", [
          @md2.btn(
            children=[
              @md2.icon(icon_name="mdi-open-in-new", size=XSmall),
              @html.text(" 打开 Web UI"),
            ],
            color="primary",
            variant=Flat,
            class="dsh-btn-primary",
          ),
          @md2.btn(
            children=[
              @html.i(class="dsh-dot-danger", @html.nothing),
              @html.text(" 停止"),
            ],
            variant=Outlined,
            class="dsh-btn",
          ),
          @md2.btn(
            children=[
              @md2.icon(icon_name="mdi-refresh", size=XSmall),
              @html.text(" 重启"),
            ],
            variant=Outlined,
            class="dsh-btn",
          ),
          @md2.btn(
            children=[@md2.icon(icon_name="mdi-dots-horizontal", size=Small)],
            variant=Outlined,
            icon=true,
            class="dsh-btn-icon",
          ),
        ]),
      ]),
      @html.ul(class="dsh-fields", [
        field("mdi-label-outline", "DSH 版本 / 来源", "未知", ""),
        field("mdi-layers-outline", "Profile", "未知", ""),
        field("mdi-link-variant", "访问地址", fact.url, ""),
        field("mdi-home-outline", "DSH_HOME", "未知", ""),
        field("mdi-puzzle-outline", "插件数量", "—", ""),
      ]),
    ],
  )
}

///|
/// 实例区：接口没回内容时也要有话说，不留白。
fn instances_section(model : Model) -> @html.Html {
  let body = if model.instances_error.length() > 0 {
    [
      @html.p(
        class="dsh-para",
        "读取失败：" + model.instances_error,
      ),
    ]
  } else if model.instances.length() == 0 {
    [@html.p(class="dsh-para", "没有探测到运行中的实例。")]
  } else {
    model.instances.map(instance_card)
  }
  @html.section(class="dsh-instances", [
    @html.h2(class="dsh-section-title", "运行中实例（GET /api/local/instances）"),
    @html.div(class="dsh-instance-list", body),
  ])
}

///|
pub fn page(model : Model) -> @html.Html {
  @html.div(
    class="dsh-page",
    attrs=@html.Attrs::build().data_set("name", "about-page"),
    [
      about_panel(),
      version_panel(model),
      instances_section(model),
    ],
  )
}
