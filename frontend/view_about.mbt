// 关于页。
//
// 版本表每项都是真实读数；读不到就写「读取失败」与原因，不写空。
// 没有「node 版本」这一行 —— 后端换掉之后那个字段已经不存在了。

///|
fn version_rows(model : Model) -> Array[@html.Html] {
  match model.runtime {
    // 读数还没回来与读取失败是两件事：前者说「正在读」，后者把原因摆出来
    None =>
      if model.read_runtime {
        [kv_row("读取状态", "读取失败", model.runtime_error)]
      } else {
        [kv_row("读取状态", "正在读取…", "本机读数还没返回")]
      }
    Some(facts) =>
      [
        kv_row("dsh 版本", facts.dsh_version, facts.dsh_package_name),
        kv_row(
          "控制台版本",
          match facts.console_version {
            Some(version) => version
            None => "未知"
          },
          facts.console_package_name,
        ),
        kv_row("平台", facts.platform, ""),
      ]
  }
}

///|
fn about_view(model : Model) -> @html.Html {
  @html.section(
    class="dsh-page",
    attrs=mark("about-page", ["about", "page"]),
    [
      @html.header(class="dsh-page-head", [@html.h1(class="dsh-page-title", "关于")]),
      @html.div(
        class="dsh-panel",
        attrs=mark("about-panel", ["about", "about-panel"]),
        [
          @html.p(
            class="dsh-para",
            "面向个人本机使用的 DSH 控制台，用来查看这台机器上的 DeepSeek Harness 实例。",
          ),
          @html.p(
            class="dsh-para",
            "读数只读本机 ~/.dsh；动作（启动 / 停止 / 重启 / 派生 / 归档 / 重命名 / 编辑备注 / 删除）会真的作用到本机实例与 profile，不是预览。",
          ),
        ],
      ),
      @html.div(
        class="dsh-panel",
        attrs=mark("version-panel", ["about", "version-panel"]),
        [
          @html.h2(class="dsh-panel-title", "版本"),
          @html.div(class="dsh-kv", version_rows(model)),
          @html.p(
            class="dsh-foot",
            "读于 " + model.runtime_time + " | 读自本机",
          ),
        ],
      ),
    ],
  )
}
