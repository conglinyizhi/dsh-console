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
/// 容器里的第一个匹配元素落焦：菜单打开要落到第一项。
extern "js" fn js_focus_first_in(container_id : String, selector : String) -> Unit =
  #| (id, sel) => {
  #|   const root = document.getElementById(id);
  #|   if (!root) return;
  #|   const el = root.querySelector(sel);
  #|   if (el && typeof el.focus === 'function') el.focus();
  #| }

///|
fn focus_first_after_render(container_id : String, selector : String) -> @cmd.Cmd {
  @cmd.custom_cmd(fn(_scheduler) { js_focus_first_in(container_id, selector) }, kind=@cmd.after_render)
}

///|
/// 行菜单的锚点矫正：量一次，下面放不下就向上折，结论写回 data-flip。
///
/// 为什么要等渲染落地再量：菜单高度由项数与文字换行决定（运行中 12 项、已停止 8 项），
/// 这个高度在 CSS 里写不出来，只能在 DOM 落地之后量。调用时机是 after_render ——
/// 与 DOM 补丁在同一个 rAF 回调里跑完，浏览器还没画，不会先闪一帧向下的菜单。
///
/// 约束盒取的不是 window，而是**最近一层会裁剪的祖先**：主区 .dsh-main 是
/// overflow-y: auto，绝对定位的下拉一旦探出它的可视盒就被裁掉 —— 视口里明明还有地方，
/// 菜单却看不见。所以先找裁剪盒，再与视口取交。
///
/// 返回 'up' / 'down'（同一个结论也写在 data-flip 上），探针直接读得到。
extern "js" fn js_menu_flip(id : String) -> String =
  #| id => {
  #|   const menu = document.getElementById(id)
  #|   const anchor = menu && menu.parentElement
  #|   if (!menu || !anchor) return ''
  #|   const MARGIN = 8       // 与屏边的留白
  #|   const GAP = 6          // 与按钮组之间的缝，与 CSS 的 calc(100% + 6px) 同源
  #|   const MIN_USABLE = 80  // 极端矮窗的保底：宁可略出界，也不留一条点不到的缝
  #|   // 量之前先清掉上一次的内联钳制，否则第二次量拿的是钳过的高度，越钳越小
  #|   menu.style.maxHeight = ''
  #|   const contentH = menu.scrollHeight
  #|   let clip = null
  #|   for (let p = menu.parentElement; p; p = p.parentElement) {
  #|     const cs = getComputedStyle(p)
  #|     if (cs.overflowY !== 'visible' || cs.overflowX !== 'visible') { clip = p.getBoundingClientRect(); break }
  #|   }
  #|   const vh = window.innerHeight || document.documentElement.clientHeight
  #|   const limitTop = Math.max(0, clip ? clip.top : 0)
  #|   const limitBottom = Math.min(vh, clip ? clip.bottom : vh)
  #|   // 锚点 = 按钮组（.dsh-actions，菜单的定位祖先），不是触发按钮：
  #|   // 向下时 top 与右缘、向上时 bottom 与右缘，都是对着它量的
  #|   const box = anchor.getBoundingClientRect()
  #|   const spaceDown = limitBottom - MARGIN - (box.bottom + GAP)
  #|   const spaceUp = box.top - GAP - (limitTop + MARGIN)
  #|   const fitsDown = box.bottom + GAP + contentH <= limitBottom - MARGIN
  #|   // 两边都放不下时挑空间大的那一侧：此时「上面放得下」必然蕴含 spaceUp > spaceDown
  #|   const dir = fitsDown ? 'down' : (spaceUp >= spaceDown ? 'up' : 'down')
  #|   const avail = dir === 'up' ? spaceUp : spaceDown
  #|   if (avail < contentH) menu.style.maxHeight = Math.max(avail, MIN_USABLE) + 'px'
  #|   menu.dataset.flip = dir
  #|   return dir
  #| }

///|
fn flip_after_render(menu_id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(fn(_scheduler) {
    js_menu_flip(menu_id) |> ignore
  }, kind=@cmd.after_render)
}

///|
fn scroll_bottom_after_render(id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(fn(_scheduler) { js_scroll_bottom_id(id) }, kind=@cmd.after_render)
}
