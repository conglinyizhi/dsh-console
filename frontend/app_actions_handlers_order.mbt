// 拖动与排序类 Msg 的回执落地。

///|
/// DrawerClosed 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_drawer_closed(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    DrawerClosed(id) => 
      if model.drawer_closing == id {
        ({ ..model, drawer_closing: "" }, @cmd.none)
      } else {
        (model, @cmd.none)
      }

    // ── 拖动排序（第十轮）──────────────────────────────────
    //
    // 一次拖动分四拍：按下记起点 → 位移过阈值才算拖动 → 松开落位并写回 → 回执。
    // 「单击开抽屉」与「拖动换位」共用同一套按下-松开，靠**位移阈值**分开：
    // 没过阈值的那一次顺序一个字节都不动，只是把抽屉打开（随后那个 click 走 DrawerOpen）。
    _ => (model, @cmd.none)
  }
}

///|
/// DragDown 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_drag_down(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    DragDown(id, x, y) => 
      // 窄屏（单列那一档）不启动拖动：那一档里纵向拖动与页面滚动落在同一个手势上，
      // 拖一次条目页面跟着滚。断点与样式里那条 media query 是同一个数。
      if js_viewport_width() < drag_min_viewport_width {
        (model, @cmd.none)
      } else {
        (
          {
            ..model,
            drag_id: id,
            drag_start_x: x,
            drag_start_y: y,
            drag_active: false,
            drag_group: "",
            drag_from: -1,
            drag_at: "",
            drag_at_index: -1,
            drag_ghost: false,
            drag_ghost_x: x,
            drag_ghost_y: y,
            drag_ghost_w: 0.0,
            drag_ghost_h: 0.0,
            drag_key_dir: 0,
            // 上一次拖动留下的抑制标记在这里清掉：留着会吃掉这一次真正的点击
            drag_suppress_click: false,
          },
          @cmd.none,
        )
      }
    _ => (model, @cmd.none)
  }
}

///|
/// DragMove 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_drag_move(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    DragMove(x, y, buttons) => 
      if model.drag_id == "" {
        // 没按下过：划过卡片也会冒泡到这里，什么都不做
        (model, @cmd.none)
      } else if buttons == 0 {
        // 没有任何键按着：这一次的抬起没收到（松手在页面之外，抬到窗口外面那一下不送到页面），
        // 当作作废。**顺序不动** —— 没提交过的东西没有什么要回滚的。
        (
          reset_drag(model),
          @cmd.batch([reorder_after_render(), clear_cells_after_render()]),
        )
      } else if js_drop_scrolled() == 1 {
        // 这一次拖动期间页面滚过：冻下来的那份坐标是视口坐标，已经在说别处的格子了。
        // 拿它算落点会得到一个**看着对、落错格**的位置，所以当场作废（顺序一个字节不动）。
        (
          reset_drag(model),
          // 摆过的格子要撤（见 clear_cells_after_render）：不撤的话这一组会停在
          // 拖动时那个形状上，而这一次已经作废了。
          @cmd.batch([reorder_after_render(), clear_cells_after_render()]),
        )
      } else if !model.drag_active &&
        !drag_past_threshold(model.drag_start_x, model.drag_start_y, x, y) {
        // 还没过阈值，还算不上拖动。**状态一个都不改** ——
        // 在这里就把 active 置上的话，一次轻轻的点击会变成一次换位。
        (model, @cmd.none)
      } else {
        // 刚过阈值的那一拍：把这一组的格子坐标冻下来。
        // **必须在这一拍冻**（不是在按下那一拍）：库没有补上拖动态的那一次 DOM 变更，
        // 所以此刻量到的还是按下前的老布局，正好是落点判定该用的那一份；
        // 再晚一拍，占位块已经插进去、条目已经让位，量到的是挪开后的位置。
        if !model.drag_active {
          ignore(js_drop_freeze(model.drag_id))
        }
        // 指针底下那一格：卡片 id 只用来查组，落点就是那个格子序号
        let (_, group, cell) = drop_target_of(x, y)
        let size = lift_sizes_of(model.drag_id)
        // 只有落在**同一组**里才算落点：两组是语义，跨组拖动不合并两组，
        // 画一个占位块在那儿等于答应了做不到的事。
        // 「指针进到另一组」在 dom.mbt 那一层就已经返回空（那一组的盒子冻在 others 里）；
        // 这里再按组名核一次，是同一件事的第二道 —— 那边管「指针在哪儿的盒子」，
        // 这边管「这个组名是不是被拖那一条的组」。
        let same_group = group != "" && group == group_of_row_id(model, model.drag_id)
        let ids = if same_group { current_group_ids(model, group) } else { [] }
        let n = ids.length()
        // 格子序号：**预览与落位用的是这一个数**（见 state.mbt 的 drop_cell）。
        let k = if same_group && cell >= 0 && n > 1 {
          drop_cell(n, cell)
        } else {
          -1
        }
        (
          {
            ..model,
            drag_active: true,
            drag_group: if same_group { group } else { "" },
            drag_from: if same_group { index_of_row(ids, model.drag_id) } else { -1 },
            drag_at: if k >= 0 { anchor_at(ids, k) } else { "" },
            drag_at_index: k,
            drag_ghost: true,
            // 虚影**以指针为中心**：落点按指针在哪一格算，虚影也压在指针上，
            // 两者说的是同一处，不会一个偏上半格、一个偏下半格。
            drag_ghost_x: x,
            drag_ghost_y: y,
            drag_ghost_w: size.0,
            drag_ghost_h: size.1,
          },
          @cmd.batch([
            @cmd.custom_cmd(fn(_scheduler) { js_drag_ghost_move(x, y) }, kind=@cmd.after_render),
            // 摆格子与让位那一段都排在这一拍之后：DOM 刚补完，量到的正是新格子。
            // 顺序不能反 —— 先摆格子（位置变了），再让 FLIP 把这段变化演出来。
            preview_cells_after_render(group, model.drag_id, k),
            reorder_after_render(),
          ]),
        )
      }
    _ => (model, @cmd.none)
  }
}

///|
/// DragUp 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_drag_up(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    DragUp => 
      if model.drag_id == "" {
        (model, @cmd.none)
      } else if !model.drag_active {
        // 按下了但没拖动：起点清掉就完事，抽屉由随后的 click 打开。
        // 这一档本来就什么都没摆过，格子那一下是空枪（撤一次是幂等的）。
        (reset_drag(model), clear_cells_after_render())
      } else {
        let k = model.drag_at_index
        let moved = moved_group_ids(model, model.drag_id, k)
        let dragged = model.drag_id
        let cleared = {
          ..reset_drag(model),
          // 拖动之后的这一次 click 不许再开抽屉（下一次按下会把它清掉）
          drag_suppress_click: true,
        }
        match moved {
          // 横向出栅格 / 跨组 / 组里只有这一条：这一次拖动作废，顺序不动，也不发请求
          None => (cleared, @cmd.batch([reorder_after_render(), clear_cells_after_render()]))
          // 落点就是原位（指针在被拖的那张自己身上）：顺序逐格没变，同样不发请求
          Some(ids) =>
            if same_order(current_group_ids(model, group_of_row_id(model, dragged)), ids) {
              (cleared, @cmd.batch([reorder_after_render(), clear_cells_after_render()]))
            } else {
              commit_order(cleared, dragged, ids, emit)
            }
        }
      }
    // 指针被取消（触控被打断等）：这一次拖动作废。**不回滚也不提交** ——
    // 顺序还没动过，没有什么要回滚的。
    _ => (model, @cmd.none)
  }
}

///|
/// DragCancel 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_drag_cancel(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    DragCancel => 
      (
        reset_drag(model),
        @cmd.batch([reorder_after_render(), clear_cells_after_render()]),
      )
    // 键盘换位：Ctrl+↑ / Ctrl+↓。与拖动走**同一条**提交路径，也走**同一个落点算法**：
    // 第一拍只把占位块摆出来（与拖动时那个块是同一个块），第二拍才真的换。
    // 这样键盘用户看到的也是「要落到哪儿」，而不是按下去才发现跳了一格。
    _ => (model, @cmd.none)
  }
}

///|
/// ReorderKey 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_reorder_key(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    ReorderKey(id, dir) => {
      let group = group_of_row_id(model, id)
      let ids = current_group_ids(model, group)
      let at = index_of_row(ids, id)
      let to = at + dir
      if at < 0 || to < 0 || to >= ids.length() {
        // 已经在头 / 尾：没有可换的位置，一个节点都不动。
        // **上一次按键留下的预览也要收掉** —— 不然它会一直挂在那儿，
        // 而这一次按下的方向并没有可去的地方。
        (
          { ..reset_drag(model), drag_key_dir: 0 },
          clear_cells_after_render(),
        )
      } else {
        // 目标格就是 to：卡槽语义下「换到第 to 格」= 被拖的那一条落在第 to 格。
        // 与指针那条路同一个 drop_cell，预览与落位因此不会分叉。
        let k = drop_cell(ids.length(), to)
        (
          {
            ..model,
            drag_id: id,
            drag_active: true,
            drag_ghost: false,
            drag_group: group,
            drag_from: at,
            drag_at: anchor_at(ids, k),
            drag_at_index: k,
            drag_key_dir: dir,
          },
          @cmd.batch([
            // 与指针那条路**同一套摆格子**：键盘用户看到的也是「将要落到哪一格」
            preview_cells_after_render(group, id, k),
            // 预览摆够了才落位（这两拍就是键盘换位的「先看见、再落下」）
            @cmd.delay(emit(ReorderCommit(dir)), reorder_preview_ms),
          ]),
        )
      }
    }
    // 键盘换位第二拍：预览摆够了，落位。
    // 号（方向）对不上就作废 —— 这中间使用者可能又按了别的方向，那时预览已经跟着换了，
    // 这一枪还是按它出发时的方向落，就会落在一个**看不到**的格子上（预览与结果分叉）。
    _ => (model, @cmd.none)
  }
}

///|
/// ReorderCommit 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_reorder_commit(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    ReorderCommit(dir) => 
      if model.drag_key_dir != dir || model.drag_id == "" || model.drag_at_index < 0 {
        (model, @cmd.none)
      } else {
        let dragged = model.drag_id
        let k = model.drag_at_index
        // 落位这一拍**先把「等着的那一步」清掉**（drag_key_dir 归 0）：
        // 连着按两次方向键时，第一拍留下的那条计时回来会看到号对不上，自己作废，
        // 不会多换一次位。
        let settled = { ..reset_drag(model), drag_key_dir: 0 }
        match moved_group_ids(model, dragged, k) {
          None => (settled, clear_cells_after_render())
          Some(ids) => commit_order(settled, dragged, ids, emit)
        }
      }
    _ => (model, @cmd.none)
  }
}

///|
/// OrderDone 的回执落地（从 update_inner 的分支体原样搬出来）。
fn handle_order_done(model : Model, msg : Msg, _emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    OrderDone(res) => {
      let (ok, text) = interpret_http(res)
      if ok {
        // 成功：顺序在松手那一刻就已经就地生效了，这里只是报一句。
        //
        // 正文只留「顺序已保存」：后端那句话说的是「顺序表已写入 <落盘路径>（N 条）」——
        // 「顺序表」是内部的叫法，落盘路径也不是使用者要读的东西（第六轮契约第二节：
        // 细节收进悬停，正文说人话）。路径与条数一个字都没丢，它们在悬停里。
        (
          notice_ok({ ..model, order_before: [] }, "顺序已保存", text),
          @cmd.none,
        )
      } else {
        // 失败：**回滚到提交前那一份**。停在「看着是新的、其实没存下」比不做还糟 ——
        // 下一次刷新列表会跳回原样，而使用者不知道自己刚才拖的那一下去哪了。
        (
          notice_err({ ..model, order: model.order_before, order_before: [] },
            "顺序没保存：" + text),
          @cmd.none,
        )
      }
    }

    // 启动的展示下限到了：等回执一起收尾（收尾里不伪造成「运行中」——
    // 真的起来了的那张卡由重读 instances 给出）
    _ => (model, @cmd.none)
  }
}

