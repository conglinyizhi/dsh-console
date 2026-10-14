// dsh-console 的本地只读接口层：dev 与 preview 都挂同一份中间件。
// 这里不碰文件系统，只做路由、HTTP 方法守卫和 JSON 包装。
import { readInstances } from './readInstances.mjs'
import { readProcesses } from './readProcesses.mjs'
import { readProfiles } from './readProfiles.mjs'
import { readRuntime } from './readRuntime.mjs'

const ROUTES = new Map([
  ['/api/local/runtime', readRuntime],
  ['/api/local/profiles', readProfiles],
  ['/api/local/processes', readProcesses],
  // 运行中实例的主口径：扫 /proc/net/tcp(6) 的 loopback LISTEN 端口，再逐个做 HTTP 签名探测
  ['/api/local/instances', readInstances],
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

export function createLocalApiMiddleware() {
  return async function localApi(req, res, next) {
    const pathname = (req.url ?? '').split('?')[0]
    if (!pathname.startsWith('/api/local/')) {
      next()
      return
    }

    if (req.method !== 'GET') {
      res.setHeader('Allow', 'GET')
      sendJson(res, 405, {
        ok: false,
        readOnly: true,
        error: { code: 'method-not-allowed', message: `本地接口只提供 GET，收到 ${req.method}` },
      })
      return
    }

    const reader = ROUTES.get(pathname)
    if (!reader) {
      sendJson(res, 404, {
        ok: false,
        readOnly: true,
        error: { code: 'not-found', message: `没有这个只读接口：${pathname}` },
      })
      return
    }

    const readAt = new Date().toISOString()
    try {
      const data = await reader()
      sendJson(res, 200, { ok: true, readOnly: true, readAt, data })
    } catch (err) {
      sendJson(res, 500, {
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
