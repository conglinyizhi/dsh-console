import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import Icons from 'unplugin-icons/vite'

// 这份配置跑在 Node 里，但 tsconfig 的 types 只列了 vite/client，没有 @types/node。
// 只用到 env 一个成员，就地声明形状，不为了一个环境变量把整包 Node 类型拖进来。
declare const process: { env: Record<string, string | undefined> }

// /api/local/* 由 MoonBit 后端提供：默认 127.0.0.1:5390，可用 DSH_CONSOLE_BACKEND_PORT 覆盖。
// 前端一律用相对路径，dev / preview / 生产各自由所在服务器把这一段转给后端，前端零改动。
const backendTarget = `http://127.0.0.1:${process.env.DSH_CONSOLE_BACKEND_PORT ?? '5390'}`

/** dev 与 preview 共用一份：路径与查询串原样转发；后端没起时让代理如实回 5xx，不吞成 404 HTML */
const localApiProxy = {
  '/api/local': {
    target: backendTarget,
    changeOrigin: false,
  },
}

export default defineConfig({
  plugins: [vue(), Icons({ compiler: 'vue3' })],
  server: { host: '127.0.0.1', port: 5320, strictPort: true, proxy: localApiProxy },
  preview: { proxy: localApiProxy },
})
