// dsh-console 的本地只读接口层：dev 与 preview 都挂同一份中间件。
// 这里不碰文件系统，只做路由、HTTP 方法守卫和 JSON 包装。
import { readInstances } from './readInstances.mjs'
import { readLogs, DEFAULT_TAIL, MAX_TAIL, resolveSource as resolveLogSource } from './readLogs.mjs'
import { readProcesses } from './readProcesses.mjs'
import { readProfiles } from './readProfiles.mjs'
import { readRuntime } from './readRuntime.mjs'

const ROUTES = new Map([
  ['/api/local/runtime', readRuntime],
  ['/api/local/profiles', readProfiles],
  ['/api/local/processes', readProcesses],
  // 运行中实例的主口径：扫 /proc/net/tcp(6) 的 loopback LISTEN 端口，再逐个做 HTTP 签名探测
  ['/api/local/instances', readInstances],
  // 日志页：只读尾部若干行，来源认 host / audit 与 instance:<实例 id>
  ['/api/local/logs', readLogsRoute],
])

function sendJson(res, status, payload) {
  const body = JSON.stringify(payload)
  res.statusCode = status
  res.setHeader('Content-Type', 'application/json; charset=utf-8')
  res.setHeader('Cache-Control', 'no-store')
  // 只读的自我标识，前端和 curl 都看得到
  res.setHeader('X-Local-Api', 'read-only')
  res.end(body)
}

/** 只认正整数 tail；缺省 200，超过上限不报错但如实说明被截断 */
function parseTail(raw) {
  if (raw === null || raw === undefined || raw === '') return { tail: DEFAULT_TAIL, note: null }
  if (!/^\d+$/.test(String(raw))) {
    return { tail: null, note: 'tail 只接受正整数' }
  }
  const value = Number.parseInt(String(raw), 10)
  if (value <= 0) return { tail: null, note: 'tail 只接受正整数' }
  if (value > MAX_TAIL) {
    return { tail: MAX_TAIL, note: 'tail 超过上限 ' + MAX_TAIL + '，按 ' + MAX_TAIL + ' 返回' }
  }
  return { tail: value, note: null }
}

async function readLogsRoute(req) {
  const query = new URL(req.url ?? '', 'http://127.0.0.1').searchParams
  const source = query.get('source')
  if (source === null || source === '') {
    const err = new Error('缺少 source 参数，只支持 host / audit / instance:<实例 id>')
    err.code = 'missing-source'
    throw err
  }
  const { tail, note } = parseTail(query.get('tail'))
  if (tail === null) {
    const err = new Error(note ?? 'tail 参数不合法')
    err.code = 'bad-tail'
    throw err
  }
  const found = resolveLogSource(source)
  if (!found) {
    const err = new Error('没有这个来源：' + source + '，只支持 host / audit / instance:<实例 id>')
    err.code = 'unknown-source'
    throw err
  }
  const data = await readLogs(found.id, tail)
  if (note) data.tailNote = note
  return data
}

export function createLocalApiMiddleware() {
  return async function localApi(req, res, next) {
    const pathname = (req.url ?? '').split('?')[0]
    // 浏览器扩展（React DevTools 等）会请求它自己注入脚本的 sourcemap，形如 /installHook.js.map。
    // 这类根级 .map 请求被 SPA 回退成 HTML，DevTools 一 JSON.parse 就在控制台报错。
    // 对根级 .map 明确回 404 + JSON 消掉这条噪声；只碰根级，
    // /src、/node_modules、/@ 下的真实 sourcemap 一律放行走 Vite 自己。
    if (req.method === 'GET' && /^\/[^/]+\.map$/.test(pathname)) {
      sendJson(res, 404, { error: 'not-found', message: '没有这个 sourcemap：' + pathname })
      return
    }
    if (!pathname.startsWith('/api/local/')) {
      next()
      return
    }

    if (req.method !== 'GET') {
      res.setHeader('Allow', 'GET')
      sendJson(res, 405, {
        ok: false,
        readOnly: true,
        error: { code: 'method-not-allowed', message: '本地接口只提供 GET，收到 ' + req.method },
      })
      return
    }

    const reader = ROUTES.get(pathname)
    if (!reader) {
      sendJson(res, 404, {
        ok: false,
        readOnly: true,
        error: { code: 'not-found', message: '没有这个只读接口：' + pathname },
      })
      return
    }

    const readAt = new Date().toISOString()
    try {
      const data = await reader(req)
      sendJson(res, 200, { ok: true, readOnly: true, readAt, data })
    } catch (err) {
      sendJson(res, err?.code === 'unknown-source' || err?.code === 'bad-tail' || err?.code === 'missing-source' ? 400 : 500, {
        ok: false,
        readOnly: true,
        readAt,
        error: {
          code: typeof err?.code === 'string' ? err.code : 'read-failed',
          message: err instanceof Error ? err.message : String(err),
        },
      })
    }
  }
}

export function localApiPlugin() {
  return {
    name: 'dsh-console-local-api',
    configureServer(server) {
      server.middlewares.use(createLocalApiMiddleware())
    },
    configurePreviewServer(server) {
      server.middlewares.use(createLocalApiMiddleware())
    },
  }
}
