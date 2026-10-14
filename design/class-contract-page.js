(async () => {
  let css = ''
  for (const st of document.querySelectorAll('style')) css += st.textContent + '\n'
  for (const lk of document.querySelectorAll('link[rel=stylesheet]')) {
    try { css += await (await fetch(lk.href)).text() + '\n' } catch (e) {}
  }
  const classes = [...new Set([...document.querySelectorAll('*')].flatMap((e) => [...e.classList]))].sort()
  const wordChar = /[A-Za-z0-9_-]/
  const missing = []
  for (const c of classes) {
    const needle = '.' + c
    let idx = css.indexOf(needle)
    let found = false
    while (idx >= 0) {
      const next = css[idx + needle.length]
      if (next === undefined || !wordChar.test(next)) { found = true; break }
      idx = css.indexOf(needle, idx + 1)
    }
    if (!found) missing.push(c)
  }
  return JSON.stringify({ cssBytes: css.length, totalClasses: classes.length, missingCount: missing.length, missing })
})()