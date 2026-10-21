// 维护作业、版本选择、日志来源类 Msg 的回执落地。

///|
/// VersionSidebarOpen 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_version_sidebar_open(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    VersionSidebarOpen =>
      (
        {
          ..model,
          version_sidebar: true,
          version_query: "",
          releases_ticks: 0,
          releases_poll_pending: false,
        },
        @cmd.batch([
          load_releases(emit),
          focus_after_render(version_search_id()),
        ]),
      )
    _ => (model, @cmd.none)
  }
}

///|
/// VersionSidebarClose 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_version_sidebar_close(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    VersionSidebarClose =>
      if !model.version_sidebar {
        (model, @cmd.none)
      } else {
        (
          { ..model, version_sidebar: false, version_query: "", },
          focus_after_render(version_choose_id()),
        )
      }
    _ => (model, @cmd.none)
  }
}

///|
/// VersionQueryInput 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_version_query_input(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    VersionQueryInput(text) => ({ ..model, version_query: text, }, @cmd.none)
    // 过滤 chip：all = 全部（清空选择）；其余是开关，多选之间「或」。
    // 不认识的值一律不动模型 —— 界面只发那四个键，多一个也不该把过滤状态弄成空的。
    _ => (model, @cmd.none)
  }
}

///|
/// VersionFilterToggle 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_version_filter_toggle(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    VersionFilterToggle(key) => {
      let current = model.version_filters
      let next = if key == "all" {
        []
      } else if !version_filter_known(key) {
        current
      } else if current.contains(key) {
        current.filter(fn(item) { item != key })
      } else {
        let out = current.copy()
        out.push(key)
        out
      }
      ({ ..model, version_filters: next, }, @cmd.none)
    }
    // 排序档：只认三档，认不出的保持原样
    _ => (model, @cmd.none)
  }
}

///|
/// VersionSortPicked 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_version_sort_picked(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    VersionSortPicked(key) =>
      if version_sort_known(key) {
        ({ ..model, version_sort: key, }, @cmd.none)
      } else {
        (model, @cmd.none)
      }
    // 选中：回填表单并关闭侧栏，焦点回「选择版本」那颗按钮
    _ => (model, @cmd.none)
  }
}

///|
/// JobVersionPicked 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_job_version_picked(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    JobVersionPicked(version) =>
      (
        {
          ..model,
          job_version: version,
          version_sidebar: false,
          version_query: "",
        },
        focus_after_render(version_choose_id()),
      )
    // 打开配置侧栏：焦点落在第一张可点的卡上（一张都没有时落在关闭键上）
    _ => (model, @cmd.none)
  }
}

///|
/// ProfileSidebarOpen 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_profile_sidebar_open(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    ProfileSidebarOpen => {
      let first = job_profile_first_usable(model)
      let focus = if first == "" {
        profile_sidebar_close_id()
      } else {
        job_profile_card_id(first)
      }
      ({ ..model, profile_sidebar: true, }, focus_after_render(focus))
    }
    _ => (model, @cmd.none)
  }
}

///|
/// ProfileSidebarClose 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_profile_sidebar_close(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    ProfileSidebarClose =>
      if !model.profile_sidebar {
        (model, @cmd.none)
      } else {
        (
          { ..model, profile_sidebar: false, },
          focus_after_render(profile_choose_id()),
        )
      }
    // 点一张可用的卡：回填并关闭侧栏，焦点回「选择配置」那颗按钮
    _ => (model, @cmd.none)
  }
}

///|
/// JobProfilePicked 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_job_profile_picked(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    JobProfilePicked(name) =>
      (
        { ..model, job_profile: name, profile_sidebar: false, },
        focus_after_render(profile_choose_id()),
      )
    // 空态那颗「开始一条作业」：先滚到表单，再把焦点送进「当前版本」那一格。
    // 两步都是 after_render —— 顺序由 batch 保证：先滚（视口到位），后聚焦
    // （聚焦也会自己滚一次，那时已经离得很近了，不会再跳）。
    _ => (model, @cmd.none)
  }
}

///|
/// JobStartFocus 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_job_start_focus(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    JobStartFocus =>
      (
        model,
        @cmd.batch([
          scroll_into_view_after_render(version_choose_id()),
          focus_after_render(version_choose_id()),
        ]),
      )
    // 总览空态那颗「刷新读数」：与写动作成功之后同一条路（两份读数都重读）。
    // 特意不弹提示条：这是个「再读一遍」的动作，结果本来就会落在列表或空态上。
    _ => (model, @cmd.none)
  }
}

///|
/// ReleasesText 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_releases_text(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    ReleasesText(res) => {
      // 三个源全没答上来**不是失败**：那是读数里的一个事实，照实摆在页面上（spec §1.3）。
      // 真正的失败只有一种：这一条接口没读到（网络、后端没这个路由）。
      let next = match res {
        Ok(text) =>
          match parse_releases(text) {
            Ok(facts) =>
              {
                ..model,
                releases: Some(facts),
                releases_error: "",
                releases_loading: false,
              }
            Err(reason) =>
              {
                ..model,
                releases: None,
                releases_error: reason,
                releases_loading: false,
              }
          }
        Err(err) =>
          {
            ..model,
            releases: None,
            releases_error: "读不到版本来源（" + describe(err) + "）",
            releases_loading: false,
          }
      }
      // 后端那条 GET 只回缓存：读到「还在拉」就隔一拍再问一次，结果才能落到页面上。
      // **同一时刻只排一个定时器**（releases_poll_pending）：进页面与打开侧栏会各发一次
      // GET，两个回执各排一个的话补问会翻倍，几拍就把上限吃完。
      // 上限 releases_poll_cap 拍（≈8 秒，长过三个源最坏 6 秒），不会变成永动机。
      if releases_still_loading(next) &&
        !next.releases_poll_pending &&
        next.releases_ticks < releases_poll_cap &&
        next.page is Maintenance {
        (
          {
            ..next,
            releases_ticks: next.releases_ticks + 1,
            releases_poll_pending: true,
          },
          @cmd.delay(emit(ReleasesTick), releases_poll_ms),
        )
      } else {
        (next, @cmd.none)
      }
    }
    // 补问一次：还在拉就再读一遍缓存（这一条请求不花网络时间）。
    // 定时器在这时候才放开，回执回来再决定排不排下一拍 —— 一拍一个，不叠加。
    _ => (model, @cmd.none)
  }
}

///|
/// ReleasesTick 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_releases_tick(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    ReleasesTick =>
      if releases_still_loading(model) && model.page is Maintenance {
        ({ ..model, releases_poll_pending: false, }, load_releases(emit))
      } else {
        ({ ..model, releases_poll_pending: false, }, @cmd.none)
      }
    // 手动重拉（§11.3）：立刻把按钮按成「正在重新拉取」（loading），排一趟后台刷新。
    // 补问计数清零：这是使用者亲手要的一次刷新，轮询预算该从头算。
    _ => (model, @cmd.none)
  }
}

///|
/// ReleasesRefresh 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_releases_refresh(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    ReleasesRefresh =>
      (
        {
          ..model,
          releases_loading: true,
          releases_ticks: 0,
          releases_poll_pending: false,
        },
        refresh_releases_cmd(emit),
      )
    // 刷新那一枪的回执：排上了就读回当前缓存（state 应当是 loading），
    // 之后照旧由 ReleasesText / ReleasesTick 的轮询接上新读数；没排上就写进侧栏底部。
    _ => (model, @cmd.none)
  }
}

///|
/// ReleasesRefreshDone 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_releases_refresh_done(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    ReleasesRefreshDone(res) => {
      let (ok, note) = interpret_http(res)
      if !ok {
        (
          notice_err(
            { ..model, releases_loading: false, },
            "重新拉取没成：" + note,
          ),
          @cmd.none,
        )
      } else {
        (model, load_releases(emit))
      }
    }
    _ => (model, @cmd.none)
  }
}

///|
/// JobStart 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_job_start(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    JobStart => job_start_command(model, emit)
    _ => (model, @cmd.none)
  }
}

///|
/// JobAction 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_job_action(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    JobAction(id, step) => job_step_command(model, id, step, emit)
    _ => (model, @cmd.none)
  }
}

///|
/// JobToggle 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_job_toggle(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    JobToggle(id) => {
      let kept = model.job_collapsed.filter(fn(collapsed) { collapsed != id })
      if kept.length() == model.job_collapsed.length() {
        // 现在展开着 → 收起
        kept.push(id)
      }
      ({ ..model, job_collapsed: kept, }, @cmd.none)
    }
    _ => (model, @cmd.none)
  }
}

///|
/// JobDone 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_job_done(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    JobDone(action, res) => job_settled(model, action, res, emit)
    // 手动折过就记一笔：ui.archiveOpenByDefault 之后不再覆盖用户的选择
    _ => (model, @cmd.none)
  }
}

///|
/// LogSourcePicked 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_log_source_picked(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    LogSourcePicked(value) => {
      let (next, read) = start_logs(
        { ..model, log_user_picked: true, },
        value,
        emit,
      )
      (
        next,
        @cmd.batch([
          read,
          push_route(route_url(Logs, model.settings_group, value)),
        ]),
      )
    }
    // 刷新不是走一步：地址不变，只是重读一遍当前来源
    _ => (model, @cmd.none)
  }
}

///|
/// LogRefresh 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_log_refresh(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    LogRefresh => start_logs(model, model.log_source, emit)
    // ── 设置页 ─────────────────────────────────────────────
    _ => (model, @cmd.none)
  }
}
