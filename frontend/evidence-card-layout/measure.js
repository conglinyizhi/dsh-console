(() => {
  const R = (el) => { const r = el.getBoundingClientRect(); return { x:+r.x.toFixed(1), y:+r.y.toFixed(1), w:+r.width.toFixed(1), h:+r.height.toFixed(1), right:+r.right.toFixed(1), bottom:+r.bottom.toFixed(1) } }
  const contentBox = (el) => {
    const cs = getComputedStyle(el), r = el.getBoundingClientRect()
    const bl = parseFloat(cs.borderLeftWidth) || 0, br = parseFloat(cs.borderRightWidth) || 0
    const bt = parseFloat(cs.borderTopWidth) || 0, bb = parseFloat(cs.borderBottomWidth) || 0
    const pl = parseFloat(cs.paddingLeft) || 0, pr = parseFloat(cs.paddingRight) || 0
    const pt = parseFloat(cs.paddingTop) || 0, pb = parseFloat(cs.paddingBottom) || 0
    return {
      left: +(r.left + bl + pl).toFixed(1), right: +(r.right - br - pr).toFixed(1),
      top: +(r.top + bt + pt).toFixed(1), bottom: +(r.bottom - bb - pb).toFixed(1),
      paddingLeft: pl, paddingRight: pr, borderLeft: bl, borderRight: br,
    }
  }
  const lineBoxes = (el) => el ? el.getClientRects().length : 0
  const cards = [...document.querySelectorAll('[data-name="instance-card"]')].map((c) => {
    const name = c.querySelector('[data-name="card-name"]')
    const port = c.querySelector('[data-name="card-port"]')
    const note = c.querySelector('[data-name="card-note"]')
    const noteText = note ? note.querySelector('.dsh-card-note-text') : null
    const head = c.querySelector('.dsh-case-head')
    const slot = c.querySelector('.dsh-tile-slot')
    const tile = c.querySelector('.dsh-tile')
    const dot = c.querySelector('.dsh-dot')
    const box = contentBox(c)
    const status = c.getAttribute('data-status')
    const running = status === 'running'
    const noted = !!note
    return {
      id: c.id,
      instance: c.getAttribute('data-instance'),
      status, light: c.getAttribute('data-light'),
      case: (running ? 'running' : 'stopped') + (noted ? '+note' : '+none'),
      text: c.textContent.replace(/\s+/g, ' ').trim(),
      nodes: { name: !!name, port: !!port, note: !!note, dot: !!dot, tile: !!tile, noteTag: !!(note && note.querySelector('.dsh-card-note-tag')) },
      card: R(c), content: box,
      head: head ? R(head) : null,
      name: name ? Object.assign(R(name), { text: name.textContent, lineBoxes: lineBoxes(name) }) : null,
      port: port ? Object.assign(R(port), { text: port.textContent, lineBoxes: lineBoxes(port), font: getComputedStyle(port).fontSize, color: getComputedStyle(port).color }) : null,
      note: note ? Object.assign(R(note), {
        text: note.textContent, lineBoxes: lineBoxes(note),
        borderLeft: getComputedStyle(note).borderLeftWidth + ' ' + getComputedStyle(note).borderLeftColor,
        paddingLeft: getComputedStyle(note).paddingLeft,
        textBox: noteText ? R(noteText) : null,
      }) : null,
      slot: slot ? R(slot) : null, tile: tile ? R(tile) : null, dot: dot ? R(dot) : null,
      deltas: {
        nameLeft: name ? +(R(name).x - box.left).toFixed(1) : null,
        portRight: port ? +(R(port).right - box.right).toFixed(1) : null,
        portGapFromName: (port && name) ? +(R(port).x - R(name).right).toFixed(1) : null,
        noteLeft: note ? +(R(note).x - box.left).toFixed(1) : null,
        noteTextLeft: noteText ? +(R(noteText).x - box.left).toFixed(1) : null,
        noteTopBelowHead: (note && head) ? +(R(note).y - R(head).bottom).toFixed(1) : null,
        dotFromTile: (dot && tile) ? { dx: +(R(dot).x - R(tile).x).toFixed(1), dy: +(R(dot).y - R(tile).y).toFixed(1), dRight: +(R(dot).right - R(tile).right).toFixed(1) } : null,
        dotFromCardRight: dot ? +(R(dot).right - R(c).right).toFixed(1) : null,
      },
      html: c.outerHTML.replace(/<!--\[-->|<!--\]-->/g, '').replace(/\s+/g, ' ').trim(),
    }
  })
  const de = document.documentElement
  const grid = document.querySelector('.dsh-card-grid')
  const tracks = grid ? getComputedStyle(grid).gridTemplateColumns.split(' ').length : null
  return JSON.stringify({
    url: location.href,
    viewport: { w: innerWidth, h: innerHeight },
    overflowX: de.scrollWidth > de.clientWidth, scrollW: de.scrollWidth, clientW: de.clientWidth,
    gridTracks: tracks, gridCols: grid ? getComputedStyle(grid).gridTemplateColumns : null,
    cards,
  })
})()