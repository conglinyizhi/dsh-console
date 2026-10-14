// 手写声明：本项目的 tsconfig 不带 @types/node，运行期实现刻意放在 .mjs 里，
// 这样 vue-tsc --noEmit 不会去类型检查 node 内置模块，构建链不用多装依赖。
import type { Plugin } from 'vite'

export declare function localApiPlugin(): Plugin
export declare function createLocalApiMiddleware(): (req: unknown, res: unknown, next: () => void) => Promise<void>
