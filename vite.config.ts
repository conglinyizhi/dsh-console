import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import Icons from 'unplugin-icons/vite'
import { localApiPlugin } from './server/localApi.mjs'

export default defineConfig({
  // localApiPlugin 挂的是本机只读接口（/api/local/*），dev 与 preview 都有，不参与 build
  plugins: [vue(), Icons({ compiler: 'vue3' }), localApiPlugin()],
  server: { host: '127.0.0.1', port: 5320, strictPort: true },
})
