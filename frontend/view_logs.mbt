// 日志页。
//
// 来源下拉是**原生 select**：分层顺序靠 disabled option 当分隔线，没有分隔项这种控件可用。
// 元信息一行到底，日志区等宽 + 长行横向滚动不折断，打开与切来源都滚到底。

///|
pub let fixed_sources : Array[(String, String)] = [
  ("host", "宿主日志"),
  ("audit", "审计日志"),
]

///|
fn format_bytes(size : Int) -> String {
  if size < 1024 {
    size.to_string() + " B"
  } else if size < 1024 * 1024 {
    let kb = size.to_double() / 1024.0
    format_decimal(kb, 1) + " KB"
  } else {
    let mb = size.to_double() / 1024.0 / 1024.0
    format_decimal(mb, 2) + " MB"
  }
}

///|
/// 定点小数：只用于体积这类展示值，不做数值推导。
fn format_decimal(value : Double, digits : Int) -> String {
  let scale = if digits == 1 { 10.0 } else { 100.0 }
  let scaled = (value * scale + 0.5).to_int()
  let unit = if digits == 1 { 10 } else { 100 }
  let whole = scaled / unit
  let frac = scaled % unit
  if digits == 1 {
    whole.to_string() + "." + frac.to_string()
  } else if frac < 10 {
    whole.to_string() + ".0" + frac.to_string()
  } else {
    whole.to_string() + "." + frac.to_string()
  }
}

///|
/// 日志区里一行：时刻 + 级别 + 正文。级别只在真读得出时上色。
fn log_line(line : LogLine) -> @html.Html {
  let level_class = match line.level {
    Some("error") => "dsh-log-lv dsh-lv-error"
    Some("warn") => "dsh-log-lv dsh-lv-warn"
    _ => "dsh-log-lv dsh-lv-none"
  }
  @html.div(class="dsh-log-line", [
    @html.span(
      class="dsh-log-t",
      match line.time {
        Some(time) => time
        None => "—"
      },
    ),
    @html.span(
      class=level_class,
      match line.level {
        Some(level) => level
        None => "··"
      },
    ),
    @html.span(class="dsh-log-body", line.text),
  ])
}

///|
/// 下拉里一条实例来源的显示名：dsh :<端口>。
fn source_label(model : Model, source : String) -> String {
  let prefix = "instance:"
  if source.length() > prefix.length() && source[0:prefix.length()] == prefix {
    let id = source[prefix.length():].to_owned()
    let instance_label = match model.instances {
      Some(facts) => {
        let mut found = source
        for fact in facts.instances {
          if fact.id == id {
            found = "dsh :" + fact.port.to_string()
          }
        }
        found
      }
      None => source
    }
    instance_label
  } else {
    let mut label = source
    for fixed in fixed_sources {
      let (value, text) = fixed
      if value == source {
        label = text
      }
    }
    label
  }
}

///|
/// 元信息行：读成功写真实口径（含实际读到的文件路径），读失败写真实原因，不留空。
fn logs_meta(model : Model) -> String {
  let got = match model.logs {
    None => return "只读"
    Some(facts) => facts
  }
  let head = match got.path {
    Some(path) => path
    None => "只读"
  }
  if !got.read_ok {
    return head + " · 读取失败 · 只读"
  }
  let rows = got.lines.length().to_string() + " 行"
  let size = match got.file_size {
    Some(bytes) => format_bytes(bytes)
    None => "大小未知"
  }
  let tail_part = if got.truncated {
    "尾部 " + rows + " · " +
    (match got.truncated_note {
      Some(note) => note
      None => "窗口已截断"
    })
  } else {
    "尾部 " + rows + "（请求 " + got.effective_tail.to_string() + "）"
  }
  let home_part = if got.kind == "instance" {
    match got.home_source {
      Some(source) => " · 目录依据：" + source
      None => ""
    }
  } else {
    ""
  }
  tail_part + " · " + size + " · " + head + home_part + " · 读于 " + model.log_time + " · 只读"
}

///|
fn source_select(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let options : Array[@html.Html] = []
  match model.instances {
    Some(facts) =>
      for fact in facts.instances {
        let value = "instance:" + fact.id
        options.push(
          @html.option(
            value~,
            selected=model.log_source == value,
            attrs=mark("log-source-option", ["logs", "source-option", value]).title(
              "读该实例 DSH_HOME 下 logs 目录里最新的日志文件；实例未带 home 时按本机默认位置定位",
            ),
            [@html.text("dsh :" + fact.port.to_string())],
          ),
        )
      }
    None => ()
  }
  options.push(
    @html.option(
      class="divider",
      disabled=true,
      value="__divider__",
      selected=false,
      attrs=mark("log-source-divider", ["logs", "source-option", "divider"]),
      [@html.text("————")],
    ),
  )
  for fixed in fixed_sources {
    let (value, label) = fixed
    options.push(
      @html.option(
        value~,
        selected=model.log_source == value,
        attrs=mark("log-source-option", ["logs", "source-option", value]),
        @html.text(label),
      ),
    )
  }
  @html.select(
    id="log-source",
    class="dsh-select",
    attrs=mark("log-source", ["logs", "source-select"]),
    on_change=emit.map(fn(value) { LogSourcePicked(value) }),
    options,
  )
}

///|
fn logs_view(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let lines : Array[@html.Html] = match model.logs {
    Some(facts) => facts.lines.map(log_line)
    None => []
  }
  // 三种「空白」是三件不同的事，分档摆：
  //   还在读（这一份内容不属于当前来源）→ 加载态
  //   读回来了、确实一行都没有      → 空态
  //   读失败了                      → 空态 + 那个「读取失败」标记（既有行为，不混进加载态）
  let reading = model.log_loading && (lines.length() == 0 || model.log_source_read != model.log_source)
  let body = if reading {
    loading_block(
      "log-loading",
      "正在读取日志…",
      "GET /api/local/logs?source=" + model.log_source +
      " 还没返回。回来之前这里显示的是加载态。",
    )
  } else if lines.length() > 0 {
    @html.div(
      id="dsh-log-box",
      class="dsh-log-box",
      attrs=mark("log-box", ["logs", "box"]),
      lines,
    )
  } else {
    @html.div(class="dsh-log-empty", attrs=mark("log-empty", ["logs", "empty"]), [
      @html.p(class="dsh-log-empty-title", "没有可显示的行"),
      @html.p(class="dsh-log-empty-detail", model.log_tag.detail),
    ])
  }
  let note = if model.instances_error.length() > 0 {
    @html.p(
      class="dsh-inst-note",
      "实例列表读取失败，实例条目为空：" + model.instances_error,
    )
  } else {
    @html.nothing
  }
  @html.section(
    class="dsh-logs",
    attrs=mark("logs-page", ["logs", "page"]),
    [
      @html.header(class="dsh-logs-head", [
        @html.h1(class="dsh-page-title", "日志"),
        source_badge(model.log_tag, ["logs", "head", "source-badge"]),
      ]),
      @html.div(class="dsh-toolbar", [
        @html.div(class="dsh-tool-left", [
          @html.label(
            class="dsh-log-label",
            for_="log-source",
            attrs=mark("log-source-label", ["logs", "source-label"]),
            "来源",
          ),
          source_select(model, emit),
        ]),
        @html.span(
          class="dsh-meta",
          attrs=mark("logs-meta", ["logs", "meta"]).title(logs_meta(model)),
          logs_meta(model),
        ),
        @html.button(
          class="dsh-refresh",
          type_="button",
          attrs=mark("log-refresh", ["logs", "refresh"]),
          on_click=emit(LogRefresh),
          [icon("refresh", size=13), @html.span("刷新")],
        ),
      ]),
      note,
      body,
    ],
  )
}
