// 浏览器侧的几处副作用：焦点、滚动、时间格式化、端口探测。
//
// 全部走 extern "js"。rabbita 的 dom 包能表达这些，但这里每个都只是一行脚本，
// 直接 FFI 比引一整个包直白；本包只出 js 产物（moon.pkg 里写死了 supported_targets）。

///|
/// 按 id 聚焦。找不到就什么都不做（元素可能已经随列表卸载 —— 例如删掉的那一行）。
extern "js" fn js_focus_id(id : String) -> Unit =
  #| id => { const el = document.getElementById(id); if (el && typeof el.focus === 'function') el.focus(); }

///|
/// 聚焦并全选：重命名框打开时预填当前名并整段选中。
extern "js" fn js_focus_select_id(id : String) -> Unit =
  #| id => {
  #|   const el = document.getElementById(id);
  #|   if (!el) return;
  #|   el.focus();
  #|   if (typeof el.select === 'function') el.select();
  #| }

///|
/// 聚焦并把光标推到文末：备注框打开时预填当前备注，要接着改而不是整段覆盖。
/// 与 js_focus_select_id 相对：那个是全选（重命名要改名），这个是落在末尾（备注是接着写）。
extern "js" fn js_focus_end_id(id : String) -> Unit =
  #| id => {
  #|   const el = document.getElementById(id);
  #|   if (!el) return;
  #|   el.focus();
  #|   const n = typeof el.value === 'string' ? el.value.length : 0;
  #|   if (typeof el.setSelectionRange === 'function') el.setSelectionRange(n, n);
  #| }

///|
/// 滚到底：日志区打开与切来源都要看到最新的一行。
extern "js" fn js_scroll_bottom_id(id : String) -> Unit =
  #| id => { const el = document.getElementById(id); if (el) el.scrollTop = el.scrollHeight; }

///|
/// 把控件上的值写回 DOM。用在「保存失败要把草稿退回去」这一处：
/// 只靠 vdom 的 value 属性未必会落到真实节点上（用户改过的值是直接写在 DOM 上的，
/// 而 diff 只比上一次渲染的属性），所以失败之后显式写一次，控件上不会留着没保存的数。
extern "js" fn js_set_control_value(id : String, value : String) -> Unit =
  #| (id, value) => { const el = document.getElementById(id); if (el && 'value' in el) el.value = value; }

///|
fn set_control_after_render(id : String, value : String) -> @cmd.Cmd {
  @cmd.custom_cmd(fn(_scheduler) { js_set_control_value(id, value) }, kind=@cmd.after_render)
}

///|
/// 新标签页打开一个地址，回一句结局：'ok' / 'blocked' / 'error: …'。
///
/// 为什么要回结局：带令牌的地址是这一轮的重点，而「点开了没有」不许猜 ——
/// 浏览器拦弹窗时 window.open 给 null（被拦和没被拦长得一样，只有返回值能分）。
/// 不用 window.open(url, '_blank', 'noopener')：那样返回值恒为 null，
/// 「被拦了」与「开了」就分不出来了；改成开完再把 opener 抹掉。
extern "js" fn js_open_url(url : String) -> String =
  #| url => {
  #|   try {
  #|     const w = window.open(url, '_blank')
  #|     if (!w) return 'blocked'
  #|     try { w.opener = null } catch (e) {}
  #|     return 'ok'
  #|   } catch (e) {
  #|     return 'error: ' + String((e && e.message) || e)
  #|   }
  #| }

///|
/// 启动时先占一个空白标页，回一句结局：'held' / 'blocked' / 'error: …'。
///
/// **必须在用户手势的同一个同步栈里调用**：window.open 只有在这一栈里才不会被弹窗
/// 拦截器吃掉，而启动要等实例真起来（约 2.5 秒）才拿得到带令牌的地址 —— 等响应回来
/// 再调 window.open 就是 null，用户看到的只有一个被拦的提示。
///
/// 句柄按 profile 名挂在 window 上：model 里放不了 JS 对象，跨 update 只能这么留。
/// 占位页顺手写一行「正在启动」—— 等地址的这几秒里它不是一张白纸。
///
/// navigator.userActivation.isActive 为 false 时直接回 'blocked'，不试那一枪：
/// 没有手势一定是被拦，试了只会在控制台留一条弹窗拦截的记录。
extern "js" fn js_tab_hold(profile : String) -> String =
  #| profile => {
  #|   try {
  #|     if (navigator.userActivation && navigator.userActivation.isActive === false) return 'blocked'
  #|     const tabs = (window.__dshStartTabs = window.__dshStartTabs || {})
  #|     const w = window.open('', '_blank')
  #|     if (!w) return 'blocked'
  #|     tabs[profile] = w
  #|     try { w.opener = null } catch (e) {}
  #|     try {
  #|       w.document.title = '正在启动 ' + profile
  #|       const p = w.document.createElement('p')
  #|       p.textContent = '正在启动 ' + profile + '，等控制台把带令牌的地址填进来…'
  #|       p.setAttribute('style', 'font:14px/1.7 system-ui,sans-serif;color:#555;padding:24px')
  #|       w.document.body.appendChild(p)
  #|     } catch (e) {}
  #|     return 'held'
  #|   } catch (e) {
  #|     return 'error: ' + String((e && e.message) || e)
  #|   }
  #| }

///|
/// 带令牌的地址到手：把占位标页导航过去。回 'ok' / 'closed' / 'gone' / 'error: …'。
/// 用户自己先把占位页关了就是 'closed' —— 那不算开成，提示条要照实说。
extern "js" fn js_tab_goto(profile : String, url : String) -> String =
  #| (profile, url) => {
  #|   const tabs = (window.__dshStartTabs = window.__dshStartTabs || {})
  #|   const w = tabs[profile]
  #|   delete tabs[profile]
  #|   if (!w) return 'gone'
  #|   try {
  #|     if (w.closed) return 'closed'
  #|     w.location.href = url
  #|     return 'ok'
  #|   } catch (e) {
  #|     return 'error: ' + String((e && e.message) || e)
  #|   }
  #| }

///|
/// 没有地址可填（启动失败 / 读不到令牌 / 重试耗尽）：把占位标页关掉，**不留一张白页**。
/// 回 'closed' / 'none'（本来就没有开成的标页）/ 'error: …'。
extern "js" fn js_tab_close(profile : String) -> String =
  #| profile => {
  #|   const tabs = (window.__dshStartTabs = window.__dshStartTabs || {})
  #|   const w = tabs[profile]
  #|   delete tabs[profile]
  #|   if (!w) return 'none'
  #|   try {
  #|     if (!w.closed) w.close()
  #|     return 'closed'
  #|   } catch (e) {
  #|     return 'error: ' + String((e && e.message) || e)
  #|   }
  #| }

///|
/// 写剪贴板，回一段 JSON：{ ok, how, error }。
///
/// 先 navigator.clipboard（唯一「知道成没成」的正路：它 reject 就说得出原因），
/// 它不在或拒了就退到 execCommand 那条老路 —— 两条都失败时如实回 ok:false，
/// **不假装复制成功**（提示条上那句「已复制」必须对应真写进去的东西）。
extern "js" fn js_copy_text(text : String) -> @js.Promise =
  #| text => (async () => {
  #|   let clipboardError = ''
  #|   try {
  #|     if (navigator.clipboard && navigator.clipboard.writeText) {
  #|       await navigator.clipboard.writeText(text)
  #|       return JSON.stringify({ ok: true, how: 'navigator.clipboard' })
  #|     }
  #|     clipboardError = '这个环境里没有 navigator.clipboard'
  #|   } catch (e) {
  #|     clipboardError = String((e && e.message) || e)
  #|   }
  #|   try {
  #|     const ta = document.createElement('textarea')
  #|     ta.value = text
  #|     ta.setAttribute('readonly', '')
  #|     ta.style.position = 'fixed'
  #|     ta.style.top = '-1000px'
  #|     document.body.appendChild(ta)
  #|     ta.select()
  #|     const ok = document.execCommand('copy')
  #|     document.body.removeChild(ta)
  #|     if (ok) return JSON.stringify({ ok: true, how: 'document.execCommand' })
  #|     return JSON.stringify({ ok: false, how: '', error: clipboardError + '；document.execCommand 也返回 false' })
  #|   } catch (e) {
  #|     return JSON.stringify({
  #|       ok: false, how: '',
  #|       error: clipboardError + '；' + String((e && e.message) || e),
  #|     })
  #|   }
  #| })()

///|
/// 复制这一枪：回执走 CopyDone（成功与失败都要有话说，不吞）。
fn copy_cmd(
  label : String,
  text : String,
  emit : @cmd.Emit[Msg],
) -> @cmd.Cmd {
  @cmd.attempt(
    fn(res : Result[String, Error]) { emit(CopyDone(label, res)) },
    async fn() {
      let text : String = js_copy_text(text).wait().cast()
      text
    },
  )
}

///|
/// 查询串编码，与 Vue 版的 encodeURIComponent 同一口径。
extern "js" fn js_encode_uri_component(text : String) -> String =
  #| text => encodeURIComponent(text)

///|
/// ISO 时刻 → 卡片上的短格式（10-13 22:50）。解析不出来给空串，界面据此写「—」。
extern "js" fn js_short_time(iso : String) -> String =
  #| iso => {
  #|   const d = new Date(iso);
  #|   if (isNaN(d.getTime())) return '';
  #|   const p = (n) => String(n).padStart(2, '0');
  #|   return p(d.getMonth() + 1) + '-' + p(d.getDate()) + ' ' + p(d.getHours()) + ':' + p(d.getMinutes());
  #| }

///|
/// 毫秒时间戳 → 卡片上的短格式（10-15 18:50，本地时区）。
///
/// 与 js_short_time 分开是因为入参不同：那边收的是后端的 ISO 串，这里收的是
/// profiles 读数里的 dirMtimeMs（毫秒数）。**不是 0 也不是 null 当有值**：
/// 拿不到数就不该走到这里（调用方按 None 分支写「读不到」），
/// 这里对 NaN / 非有限值返回空串，调用方据此退回「读不到」。
extern "js" fn js_short_time_ms(ms : Double) -> String =
  #| ms => {
  #|   if (!Number.isFinite(ms)) return '';
  #|   const d = new Date(ms);
  #|   if (isNaN(d.getTime())) return '';
  #|   const p = (n) => String(n).padStart(2, '0');
  #|   return p(d.getMonth() + 1) + '-' + p(d.getDate()) + ' ' + p(d.getHours()) + ':' + p(d.getMinutes());
  #| }

///|
/// 同一个毫秒时间戳的完整值（UTC ISO），只给卡上那一格的悬停用：
/// 卡片显示的是本地短时刻，要跟 /api/local/profiles 的 dirMtimeMs 对上号时看这个。
extern "js" fn js_iso_time_ms(ms : Double) -> String =
  #| ms => {
  #|   if (!Number.isFinite(ms)) return '';
  #|   const d = new Date(ms);
  #|   if (isNaN(d.getTime())) return '';
  #|   return d.toISOString();
  #| }

///|
/// 使用者是不是把动效关了（prefers-reduced-motion: reduce）。1 = 关了。
///
/// 只有一处问它：抽屉收起来那一段 —— 那个设置下**不做任何位移与淡入淡出**，
/// 节点当场撤掉，而不是留着等一段看不见的动画走完（留着的这段时间它还盖着页面）。
/// 样式里有同一条 media query 把动画关掉（开的那一半归它管）；这里问一遍是为了
/// 连节点都不留。返回 Int 而不是 Bool：FFI 的数值边界最不容易出岔子。
extern "js" fn js_reduced_motion() -> Int =
  #| () => (window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) ? 1 : 0

///|
fn prefers_reduced_motion() -> Bool {
  js_reduced_motion() == 1
}

///|
/// 视口宽度（CSS 像素，取整）。
///
/// 拖动排序要按它判「窄屏不响应」：单列那一档（< 726px）里，纵向拖动与页面滚动
/// 会互相打架 —— 拖一次条目，页面跟着滚。断点用的是与样式里那条 media query
/// 同一个数（.dsh-rows.dsh-card-grid 的 2 列起点），两处必须一起改。
extern "js" fn js_viewport_width() -> Int =
  #| () => Math.round(window.innerWidth || 0)

///|
/// 拖动的坐标冻结：把一组条目的格子位置**在拖动开始时量一次**，之后整个拖动过程都用这一份。
/// 量的时候顺手把「点着的那一条有多大」也返回去 —— 虚影照它画，形状与手上那一条一致。
///
/// 为什么非冻不可：占位块是插进栅格序列里的，它一进来，后面那些条目就真的让位挪走了。
/// 拿**挪动之后**的位置算落点会自成一个回路 —— 挪一格 → 指针底下的条目变了 → 又挪一格，
/// 落点会在两格之间来回跳。冻住的那一份是「这一组本来各占哪儿」，只随指针走，不随让位走。
/// 冻在这一拍（第一次过阈值）而不是按下那一拍：此刻库还没把拖动态补进 DOM，
/// 量到的正是按下前的布局 —— 与「如果没在拖，指针底下会是谁」完全对得上。
extern "js" fn js_drop_freeze(dragged : String) -> String =
  #| (dragged) => {
  #|   // 这一次拖动的全部中间状态都挂在 globalThis 上，不放在模块顶层：
  #|   // 每一段 extern "js" 是各自独立求值的函数，顶层 let 互不可见。
  #|   globalThis.__dshDropRef = null;
  #|   const off = globalThis.__dshDropScroll;
  #|   if (off) { window.removeEventListener('scroll', off, true); globalThis.__dshDropScroll = null; }
  #|   const card = document.querySelector('[data-row="' + CSS.escape(dragged) + '"]');
  #|   if (!card || typeof card.closest !== 'function') return '';
  #|   const grid = card.closest('[data-name="row-group"]');
  #|   if (!grid) return '';
  #|   const cards = [...grid.querySelectorAll('[data-row]')].map((el) => {
  #|     const r = el.getBoundingClientRect();
  #|     return { id: el.getAttribute('data-row') || '', top: r.top, bottom: r.bottom };
  #|   }).filter((c) => c.id);
  #|   const g = grid.getBoundingClientRect();
  #|   // 别组的盒子一起冻下来：落点判定要知道指针有没有**进到另一组**里（跨组不落）。
  #|   // 别组在这次拖动里不动（摆格子只摆被拖的那一组），所以冻一份就够，不必每动一下重量。
  #|   const others = [...document.querySelectorAll('[data-name="row-group"]')].filter((el) => el !== grid).map((el) => {
  #|     const r = el.getBoundingClientRect();
  #|     return { group: el.getAttribute('data-group') || '', top: r.top, bottom: r.bottom, left: r.left, right: r.right };
  #|   });
  #|   globalThis.__dshDropRef = { group: grid.getAttribute('data-group') || '', cards: cards,
  #|     top: g.top, bottom: g.bottom, left: g.left, right: g.right, others: others, dragged: dragged };
  #|   const r = card.getBoundingClientRect();
  #|   const out = { w: r.width, h: r.height };
  #|   // 冻下来的那一刻就挂上「滚了就作废」的监听：坐标是视口坐标，页面一滚就全对不上了。
  #|   // 与其拿一串过期坐标算出一个**看着对、落错格**的落点，不如当场作废（顺序一个字节不动）。
  #|   const on = () => { globalThis.__dshDropRef = null; globalThis.__dshDropArmed = true; };
  #|   globalThis.__dshDropScroll = on;
  #|   window.addEventListener('scroll', on, true);
  #|   return JSON.stringify(out);
  #| }

///|
/// 这一次拖动期间，坐标有没有被滚动搅掉（滚过 = true）。
/// 上层据此把拖动收掉：冻着的那份坐标已经在说别处的格子了。
extern "js" fn js_drop_scrolled() -> Int =
  #| () => (globalThis.__dshDropArmed ? 1 : 0)

///|
/// 这一次拖动用过的坐标全部丢掉：占位块、冻结、滚动监听、虚影的位置一起清。
extern "js" fn js_drop_clear() -> Unit =
  #| () => {
  #|   globalThis.__dshDropRef = null;
  #|   globalThis.__dshDropArmed = false;
  #|   const off = globalThis.__dshDropScroll;
  #|   if (off) { window.removeEventListener('scroll', off, true); globalThis.__dshDropScroll = null; }
  #| }

///|
/// 指针底下是哪一条：返回一段 JSON `{"row":"<行 id>","group":"running|stopped","rank":N}`，
/// 只有两种情形给空串（这一次没有落点）：指针**横向离开这一组的栅格**、或**进到另一组**里
/// （另加页面滚过那一路，见 js_drop_scrolled）。
///
/// `rank` 是**插入位次**，也就是结果里那个格子序号：插到某一条之前 = 它在「其余 n-1 条」里的位次，
/// 之后 = 位次 + 1。前端的落点算法（state.mbt 的 insert_at_index）只认这一个数 ——
/// 「指针越过谁的中间线」这个判定因此从代码里搬到了画面上：占位块就摆在那一格。
///
/// **纵向不设界（第十三轮改，口径变更）**：落点由「指针与各块中心的关系」算，任何 y 都算得出
/// 一个位次 —— 越过最后一块的下沿 = **最后一格**（rank 走到 n，由 insert_at_index 收口成 n-1）、
/// 越过第一块的上沿 = **第一格**（rank 0）。旧版在列表上下各留 32px 宽容带、出带即作废，
/// 于是最后 / 最前那一格**永远够不着**：指针要越过那一块才能到那一格，而越过就已经出带 ——
/// 使用者报的「拖不到最后面」就是这一条。
///
/// 两头是**先收口、再算中间**两步：中间那一段按「离得最近的那一条 + 指针在它上半还是下半」定，
/// 栅格的行间距有 12px，只认「正压在某一条上」会让这 12px 里什么提示都没有；
/// 而两头不能交给「最近一条」（同一行各块底边相同、距离并列，取并列里的第一个会落到
/// 最后一行的第一格）。两步合起来：任何纵向位置都给出一个位次。
///
/// 判定按冻结下来的那份格子走，不按活的 DOM：条目正在让位，活的位置会让落点自己跳。
extern "js" fn js_drop_target(x : Double, y : Double) -> String =
  #| (x, y) => {
  #|   const ref = globalThis.__dshDropRef;
  #|   if (!ref || ref.cards.length < 2) return '';
  #|   // 只有两种情形算「这一次没有落点」：
  #|   //   ① 指针**横向**离开这一组的栅格 —— 它已经不在这一片的排序里了。
  #|   //      留 24px 宽容带：纵向拖的时候手往旁边偏一点，不该把落点整个判没。
  #|   //      （栅格的左右缘跨着全部列，所以「往右边那一列拖」仍在缘内 ✓）
  #|   //   ② 指针**进到另一组**里 —— 两组是语义，跨组拖动不合并两组，
  #|   //      在那儿画一个占位块等于答应了做不到的事。
  #|   // 纵向**不设界**：落点由「指针与各块中心的关系」算，任何 y 都算得出一个位次 ——
  #|   // 越过最后一块 = 最后一格、越过第一块 = 第一格（见上面的说明）。
  #|   const padX = 24;
  #|   if (x < ref.left - padX || x > ref.right + padX) return '';
  #|   for (const g of ref.others || []) {
  #|     if (x >= g.left && x <= g.right && y >= g.top && y <= g.bottom) return '';
  #|   }
  #|   // 两头的**收口**先判，不能靠「离得最近那一条」—— 指针在最后一行下方时，
  #|   // 那一行各块的底边相同、距离并列，取并列里的第一个会落到「最后一行的第一格」，
  #|   // 而不是最后那一格（实测：3 条排一行时落在第 1 格而不是第 2 格）。
  #|   // 越过第一块的上沿 = 第一格（rank 0）、越过最后一块的下沿 = 最后一格（rank n，
  #|   // 由 insert_at_index 收口成 n-1）—— 中间那一段才交给下面那套「最近一条 + 上半/下半」。
  #|   let topMost = ref.cards[0].top;
  #|   let bottomMost = ref.cards[0].bottom;
  #|   for (const c of ref.cards) {
  #|     if (c.top < topMost) topMost = c.top;
  #|     if (c.bottom > bottomMost) bottomMost = c.bottom;
  #|   }
  #|   if (y <= topMost) return JSON.stringify({ row: ref.cards[0].id, group: ref.group, rank: 0 });
  #|   if (y >= bottomMost) return JSON.stringify({ row: ref.cards[ref.cards.length - 1].id, group: ref.group, rank: ref.cards.length });
  #|   let best = ref.cards[0];
  #|   let bestD = null;
  #|   for (const c of ref.cards) {
  #|     const d = y < c.top ? c.top - y : (y > c.bottom ? y - c.bottom : 0);
  #|     if (bestD === null || d < bestD) { bestD = d; best = c; }
  #|     if (d === 0) break;
  #|   }
  #|   const mid = (best.top + best.bottom) / 2;
  #|   const after = y > mid;
  #|   const i = ref.cards.indexOf(best);
  #|   // 中间这一段 rank 落在 0..n-1 里（两头已经先返回），不必再收口
  #|   const rank = after ? i + 1 : i;
  #|   return JSON.stringify({ row: best.id, group: ref.group, rank: rank });
  #| }

///|
/// 被拖的那一条的盒子尺寸（虚影照它画）。盒子不在就给空串。
extern "js" fn js_card_box(cardId : String) -> String =
  #| (id) => {
  #|   const el = document.getElementById(id);
  #|   if (!el) return '';
  #|   const r = el.getBoundingClientRect();
  #|   return JSON.stringify({ w: r.width, h: r.height });
  #| }

///|
/// 让虚影跟着指针走。**只动这一个节点的 transform**，不回状态、不重渲染 ——
/// 指针每一动一下就重渲一次整页是没必要的：跟着指针走的不变量只有这一个。
///
/// 位置：整块**往右下挪一点**（10, 14），不是正压在指针上。两个原因：
///   · 正压在指针上时，虚影正好盖住占位块 —— 预览里最要紧的那一格反而看不见了
///     （实测截图里就是这样：占位块被虚影压着，只剩一层虚线边露在外面）；
///   · 手上拎着东西的样子本来就是偏一点的，压在手底下反而像贴上去的。
extern "js" fn js_drag_ghost_move(x : Double, y : Double) -> Unit =
  #| (x, y) => {
  #|   const ghost = document.querySelector('.dsh-drag-ghost');
  #|   if (!ghost) return;
  #|   ghost.style.transform = 'translate(' + (x + 10) + 'px, ' + (y + 14) + 'px)';
  #| }

///|
/// 拖动预览的格子：把这一组里每一条**直接摆进它该在的那一格**。
///
/// 为什么不交给 CSS 的 `order`：试过，两条路都堵死 ——
///   ① 栅格的自动排布**碰不得空档**：order 不是一份完整的 0..n-1 排列时，后一条会
///      自己往后跳一格（实测第 0 格的占位块被摆到了第三列）；
///   ② 就算补齐成完整排列，被拖的那一条也得跟着一起重排，而它必须稳稳待在最后一格。
/// 也不靠节点上的 data 属性 + 属性选择器：虚拟 DOM 那一层按位置比对，属性会被对到
/// 别的节点上（实测被拖那一条拿到了别人的格号）。**直接给格子**没有这些连带：
/// 谁在哪一格，由这里一次算清、一次写完。
///
/// 格号 → 行列：列 = 格号 mod 列数 + 1，行 = 格号 div 列数 + 1。列数从栅格自己身上量
/// （读计算样式里的 grid-template-columns 有几个轨），所以这里不必跟着那五条断点改 ——
/// 810 宽的两列、1280 宽的四列，都走同一份代码。
/// 谁在哪一格：占位块在第 k 格、被拖的那一条在最后一格、其余各条按现在的次序填满
/// 剩下的格子 —— 与「真把它抽走、再插进第 k 格」的终局逐格相同。
extern "js" fn js_grid_cells(group : String, dragged : String, k : Int) -> Int =
  #| (group, dragged, k) => {
  #|   const grid = document.querySelector('[data-name="row-group"][data-group="' + group + '"]');
  #|   if (!grid) return -1;
  #|   const slot = [...grid.children].find((n) => n.classList.contains('dsh-drop-slot'));
  #|   if (!slot) return -1;
  #|   // **对着 DOM 再核一次**：这一步挂在「渲染之后」，但库的渲染时序并不保证这一拍
  #|   // 看到的 DOM 已经是最新那一版（实测有一拍的滞后：占位块还在上一格时，这一步
  #|   // 已经按新的 k 摆过一次格子了 —— 摆出来的是一份对不上号的布局）。
  #|   // 占位块自己身上写着它该在第几格（data-slot-index）：对不上就什么都不做，
  #|   // 等真正与这一版 DOM 配套的那一拍来做（下一拍会带上正确的 k）。
  #|   if (String(k) !== (slot.getAttribute('data-slot-index') || '')) return -2;
  #|   const tr = getComputedStyle(grid).gridTemplateColumns || '';
  #|   const cols = tr.trim() === 'none' ? 1 : tr.trim().split(/\s+/).length;
  #|   const place = (el, cell) => {
  #|     el.style.gridColumn = String((cell % cols) + 1);
  #|     el.style.gridRow = String(Math.floor(cell / cols) + 1);
  #|   };
  #|   // 一份**排列**：被拖的那一条在 k 格、占位块在 k 格、其余各条按现在的次序填满
  #|   // 剩下的格子。与「真把它抽走、再插进第 k 格」的终局逐格相同。
  #|   let cell = 0;
  #|   let seen = 0;
  #|   for (const el of [...grid.children]) {
  #|     const id = el.getAttribute('data-row');
  #|     if (!id) continue;
  #|     seen = seen + 1;
  #|     if (id === dragged) continue;
  #|     if (cell === k) cell = cell + 1;
  #|     place(el, cell);
  #|     cell = cell + 1;
  #|   }
  #|   place(slot, k);
  #|   return seen > 1 ? k : -1;
  #| }

///|
/// 把预览摆过的格子全部撤掉：回到「栅格自己按孩子次序发格子」。
/// 落位之后（或这一次拖动作废之后）必须走它，不然那一组会停在拖动时摆的那个形状上。
extern "js" fn js_grid_cells_clear() -> Unit =
  #| () => {
  #|   for (const n of document.querySelectorAll('[data-name="row-group"] > *')) {
  #|     n.style.gridColumn = '';
  #|     n.style.gridRow = '';
  #|   }
  #| }
///|
/// 让位那一段：把「刚发生的格子变化」演出来。
///
/// 三件事按顺序做完（顺序不能换）：
///   ① 先量一遍每个节点**现在看上去在哪**（量在撤动画之前 —— 上一段 FLIP 还没走完时，
///      元素真正的视觉位置就是它，从那儿接着走才对得上）；
///   ② 撤掉上一段动画与 transform，量一遍它在**新布局**里的位置；
///   ③ 从这里补一个「先退回旧位置、再走回新位置」的动画。
///
/// 为什么不用 CSS 的 transition：让位是**节点在序列里换了位置**，不是某个属性值变了，
/// transition 根本不触发。占位块进来时后面那几条是「整块换了一格」，只有 FLIP 演得出来。
/// 减少动效那一档直接不做（返回 0），让位当场完成 —— 提示保留，动画撤掉。
///
/// 时长 180 与 state.mbt 的 reorder_ms 是同一个数（改一处得改另一处）：
/// 那边那份是给读代码的人看的，真正生效的是这里这一行。
extern "js" fn js_drop_flip() -> Int =
  #| () => {
  #|   if (!globalThis.__dshDropRef) return 0;
  #|   if (window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) return 0;
  #|   const nodes = [...document.querySelectorAll('[data-name="row-group"] .dsh-case, [data-name="row-group"] .dsh-drop-slot')];
  #|   const from = new Map();
  #|   for (const n of nodes) { const r = n.getBoundingClientRect(); from.set(n, { x: r.left, y: r.top }); }
  #|   for (const n of nodes) {
  #|     if (n.getAnimations) for (const a of n.getAnimations()) { try { a.cancel(); } catch (e) {} }
  #|     n.style.transform = '';
  #|   }
  #|   let moved = 0;
  #|   for (const n of nodes) {
  #|     const was = from.get(n);
  #|     const now = n.getBoundingClientRect();
  #|     const dx = was.x - now.left;
  #|     const dy = was.y - now.top;
  #|     if (Math.abs(dx) < 0.5 && Math.abs(dy) < 0.5) continue;
  #|     moved = moved + 1;
  #|     n.animate(
  #|       [{ transform: 'translate(' + dx + 'px, ' + dy + 'px)' }, { transform: 'translate(0, 0)' }],
  #|       { duration: 180, easing: 'ease-out' },
  #|     );
  #|   }
  #|   return moved;
  #| }

///|
/// 让位那一段排在渲染之后跑（见 dom.mbt 顶上的说明：AfterRender 时 DOM 才刚补完）。
fn reorder_after_render() -> @cmd.Cmd {
  @cmd.custom_cmd(fn(_scheduler) { ignore(js_drop_flip()) }, kind=@cmd.after_render)
}

///|
/// 摆格子：把这一组的每一条直接放进它该在的那一格（见 js_grid_cells）。
/// 排在渲染之后 —— 节点得先在文档里，量列数、找占位块才有对象。
fn preview_cells_after_render(group : String, dragged : String, k : Int) -> @cmd.Cmd {
  @cmd.custom_cmd(fn(_scheduler) { ignore(js_grid_cells(group, dragged, k)) }, kind=@cmd.after_render)
}

///|
/// 撤掉摆过的格子（落位 / 作废之后）。
fn clear_cells_after_render() -> @cmd.Cmd {
  @cmd.custom_cmd(fn(_scheduler) { js_grid_cells_clear() }, kind=@cmd.after_render)
}


///|
/// 渲染完成之后再聚焦：菜单打开要落到第一项，关闭要把焦点还给触发元素。
/// 用 AfterRender 时机，否则 DOM 还没打补丁，query 到的是上一帧的节点。
fn focus_after_render(id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(fn(_scheduler) { js_focus_id(id) }, kind=@cmd.after_render)
}

///|
fn focus_select_after_render(id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(fn(_scheduler) { js_focus_select_id(id) }, kind=@cmd.after_render)
}

///|
fn focus_end_after_render(id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(fn(_scheduler) { js_focus_end_id(id) }, kind=@cmd.after_render)
}



///|
fn scroll_bottom_after_render(id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(fn(_scheduler) { js_scroll_bottom_id(id) }, kind=@cmd.after_render)
}
