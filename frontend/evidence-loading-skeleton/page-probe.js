// 页面侧的量法：探针把这一份整份注入页面，再调 __dshProbe 上的方法。
// 全部是 DOM 实测（getBoundingClientRect / getComputedStyle / elementFromPoint），
// 不从截图里认数。
globalThis.__dshProbe = {
  rect(el) {
    const r = el.getBoundingClientRect()
    return { x: +r.x.toFixed(1), y: +r.y.toFixed(1), w: +r.width.toFixed(1), h: +r.height.toFixed(1) }
  },
  tracksOf(grid) {
    if (!grid) return []
    return getComputedStyle(grid).gridTemplateColumns.split(' ').filter((s) => s.length > 0)
  },
  xsOf(nodes) {
    // 左缘取整到 2px 再分组（容忍亚像素），返回排好序的列起点。
    // 列数用这个量：占位块与真卡片都按它比，比数卡片可靠（本机只有几张卡）。
    const xs = nodes.map((n) => Math.round(n.getBoundingClientRect().x / 2) * 2)
    return [...new Set(xs)].sort((a, b) => a - b)
  },
  // 真正的栅格项：display: contents 的那一层不生成盒子，它的孩子才占格子。
  // 量列数与起点必须按这个展开，按 grid.children 量到的是那个空盒子（rect 全 0）。
  itemsOf(grid) {
    const out = []
    for (const c of grid.children) {
      if (getComputedStyle(c).display === 'contents') { for (const k of c.children) out.push(k) } else { out.push(c) }
    }
    return out
  },
  gridInfo(grid) {
    const P = globalThis.__dshProbe
    const kids = P.itemsOf(grid)
    const tracks = P.tracksOf(grid)
    const isSkeleton = (e) => e.classList.contains('dsh-skeleton')
    const isCard = (e) => e.getAttribute('data-name') === 'instance-card'
    const ph = kids.filter(isSkeleton)
    const cards = kids.filter(isCard)
    return {
      tracks: tracks.length,
      trackSizes: tracks.slice(0, 8),
      gap: getComputedStyle(grid).columnGap,
      domChildren: grid.children.length,
      itemCount: kids.length,
      itemClasses: kids.map((k) => String(k.className)),
      colXs: P.xsOf(kids),
      firstItem: kids.length ? P.rect(kids[0]) : null,
      placeholderCount: ph.length,
      placeholderColXs: P.xsOf(ph),
      firstPlaceholder: ph.length ? P.rect(ph[0]) : null,
      cardCount: cards.length,
      cardColXs: P.xsOf(cards),
      firstCard: cards.length ? P.rect(cards[0]) : null,
      overflowX: grid.scrollWidth > grid.clientWidth,
    }
  },
  measure() {
    const P = globalThis.__dshProbe
    const grids = [...document.querySelectorAll('.dsh-card-grid')]
    const placeholders = [...document.querySelectorAll('.dsh-loading .dsh-skeleton')]
    const cards = [...document.querySelectorAll('[data-name="instance-card"]')]
    const main = document.querySelector('.dsh-main')
    const region = document.querySelector('.dsh-loading')
    const note = document.querySelector('.dsh-loading-note')
    const anim = [...document.querySelectorAll('*')].filter((e) => {
      const cs = getComputedStyle(e)
      return cs.animationName && cs.animationName !== 'none'
    })
    const de = document.documentElement
    // 常规「可 Tab 到」的那一批（含 tabindex="-1" 之外的都算），看有没有落进加载区
    const tabbable = [...document.querySelectorAll('a[href], button, input, select, textarea, [tabindex]')]
      .filter((e) => e.getBoundingClientRect().width > 0 && e.getBoundingClientRect().height > 0)
    const regionHtml = region ? region.outerHTML : null
    return {
      url: location.pathname + location.search,
      viewport: { w: innerWidth, h: innerHeight },
      pageOverflowX: de.scrollWidth > de.clientWidth,
      main: main ? { width: +main.getBoundingClientRect().width.toFixed(1), rect: P.rect(main), overflowX: main.scrollWidth > main.clientWidth } : null,
      grids: grids.map((g) => P.gridInfo(g)),
      loading: region ? {
        tag: region.tagName.toLowerCase(),
        display: getComputedStyle(region).display,
        dataName: region.getAttribute('data-name'),
        dataState: region.getAttribute('data-state'),
        childCount: region.children.length,
        placeholderCount: placeholders.length,
        firstPlaceholders: placeholders.slice(0, 3).map((p) => P.rect(p)),
        placeholderHeights: [...new Set(placeholders.map((p) => +p.getBoundingClientRect().height.toFixed(1)))],
        placeholderWidths: [...new Set(placeholders.map((p) => +p.getBoundingClientRect().width.toFixed(1)))],
        placeholderBoxes: [...new Set(placeholders.map((p) => getComputedStyle(p).padding + ' / ' + getComputedStyle(p).borderTopWidth + ' / ' + getComputedStyle(p).borderRadius))],
        tileSizes: [...new Set([...document.querySelectorAll('.dsh-skeleton-tile')].map((t) => { const r = t.getBoundingClientRect(); return r.width.toFixed(1) + 'x' + r.height.toFixed(1) }))],
        nameBarSizes: [...new Set([...document.querySelectorAll('.dsh-skeleton-name')].map((t) => { const r = t.getBoundingClientRect(); return r.width.toFixed(1) + 'x' + r.height.toFixed(1) }))],
        skeletonCursor: placeholders.length ? getComputedStyle(placeholders[0]).cursor : null,
        skeletonBg: placeholders.length ? getComputedStyle(placeholders[0]).backgroundColor : null,
        note: note ? {
          role: note.getAttribute('role'),
          ariaLive: note.getAttribute('aria-live'),
          text: note.textContent,
          lines: [...note.children].map((c) => c.textContent),
          rect: P.rect(note),
        } : null,
        noteCount: document.querySelectorAll('.dsh-loading-note').length,
        placeholdersAriaHidden: placeholders.filter((p) => p.getAttribute('aria-hidden') === 'true').length,
        placeholdersWithRole: placeholders.filter((p) => p.getAttribute('role') !== null).length,
        placeholdersWithTabindex: placeholders.filter((p) => p.getAttribute('tabindex') !== null).length,
        placeholdersWithClickHandler: placeholders.filter((p) => typeof p.onclick === 'function').length,
        buttonsInside: document.querySelectorAll('.dsh-loading button').length,
        linksInside: document.querySelectorAll('.dsh-loading a').length,
        roleButtonsInside: document.querySelectorAll('.dsh-loading [role=button]').length,
        tabbablesInside: document.querySelectorAll('.dsh-loading [tabindex]').length,
        // 使用者给的那条验收查询，原样跑
        acceptanceQuery: document.querySelectorAll('.dsh-loading button, .dsh-loading [tabindex]').length,
        tabbableInPage: tabbable.length,
        tabbableInsideLoading: tabbable.filter((e) => region && region.contains(e)).length,
      } : null,
      // 页头：加载时那里会多一枚「读取中」徽标（三档里的第一档），
      // 窄屏下它会折行、把下面的内容整体推下一截 —— 那是徽标的事，不是骨架的事，
      // 但量「跳不跳」时必须把它单独记下来，不然会把它的账算到占位块头上。
      head: (() => {
        const h = document.querySelector('.dsh-overview-head')
        if (!h) return null
        return {
          rect: P.rect(h),
          badges: [...document.querySelectorAll('.dsh-badge')].map((b) => ({ text: b.textContent.trim(), cls: String(b.className), rect: P.rect(b) })),
          note: (() => { const n = document.querySelector('.dsh-head-note'); return n ? P.rect(n) : null })(),
        }
      })(),
      sectionHeadRects: [...document.querySelectorAll('.dsh-section-head')].map((s) => P.rect(s)),
      cards: {
        count: cards.length,
        rects: cards.map((c) => P.rect(c)),
        heights: [...new Set(cards.map((c) => +c.getBoundingClientRect().height.toFixed(1)))],
        widths: cards.map((c) => +c.getBoundingClientRect().width.toFixed(1)),
        withNote: cards.filter((c) => c.querySelector('.dsh-card-note')).length,
        buttonsInside: cards.reduce((n, c) => n + c.querySelectorAll('button').length, 0),
        colXs: P.xsOf(cards),
      },
      emptyStates: document.querySelectorAll('.dsh-empty').length,
      sectionTitles: [...document.querySelectorAll('.dsh-section-title')].map((e) => e.textContent.trim()),
      animations: { count: anim.length, names: anim.map((e) => getComputedStyle(e).animationName) },
      dotCount: document.querySelectorAll('.dsh-dot').length,
      regionHtml: regionHtml ? regionHtml.slice(0, 700) : null,
    }
  },
  clickFirstPlaceholder() {
    const p = document.querySelector('.dsh-loading .dsh-skeleton')
    if (!p) return null
    const r = p.getBoundingClientRect()
    const x = r.x + r.width / 2
    const y = r.y + r.height / 2
    const hit = document.elementFromPoint(x, y)
    return {
      point: { x: +x.toFixed(1), y: +y.toFixed(1) },
      hitClass: hit ? String(hit.className) : null,
      hitInside: hit ? (hit === p || p.contains(hit)) : false,
    }
  },
  snapshot() {
    const region = document.querySelector('.dsh-loading')
    return {
      url: location.pathname + location.search,
      skeletons: document.querySelectorAll('.dsh-loading .dsh-skeleton').length,
      cards: document.querySelectorAll('[data-name="instance-card"]').length,
      drawer: !!document.querySelector('.dsh-drawer'),
      scrim: !!document.querySelector('.dsh-drawer-scrim'),
      dialog: !!document.querySelector('.dsh-dialog-wrap'),
      active: document.activeElement ? document.activeElement.tagName.toLowerCase() + (document.activeElement.className ? '.' + String(document.activeElement.className).split(' ')[0] : '') : 'none',
      gridItems: [...document.querySelectorAll('.dsh-card-grid')].map((g) => g.children.length),
      regionStillThere: !!region,
    }
  },
  activeNow() {
    const a = document.activeElement
    if (!a) return 'none'
    return a.tagName.toLowerCase() + (a.id ? '#' + a.id : '') + (a.className ? '.' + String(a.className).split(' ')[0] : '')
  },
  cloneCardsTo(n) {
    // 只为量列轨：把第一张真卡片克隆到 n 张。量完整页重载，不留痕。
    const P = globalThis.__dshProbe
    const grid = document.querySelector('.dsh-card-grid')
    const card = grid ? grid.querySelector('[data-name="instance-card"]') : null
    if (!card) return null
    const made = []
    for (let i = grid.querySelectorAll('[data-name="instance-card"]').length; i < n; i++) {
      const c = card.cloneNode(true)
      c.removeAttribute('id')
      c.setAttribute('data-clone', '1')
      grid.appendChild(c)
      made.push(c)
    }
    return {
      clones: made.length,
      colXs: P.xsOf([...grid.querySelectorAll('[data-name="instance-card"]')]),
      tracks: P.tracksOf(grid).length,
      heights: [...new Set([...grid.querySelectorAll('[data-name="instance-card"]')].map((c) => +c.getBoundingClientRect().height.toFixed(1)))],
      widths: [...new Set([...grid.querySelectorAll('[data-name="instance-card"]')].map((c) => +c.getBoundingClientRect().width.toFixed(1)))],
      firstItem: P.rect(grid.querySelector('[data-name="instance-card"]')),
    }
  },
}
