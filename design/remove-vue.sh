#!/usr/bin/env bash
#
# 收尾：移除 Vue 前端那一套，只留 backend/ frontend/ design/。
#
# 这是**破坏性操作**，所以：
#   - 要删的路径全部硬编码在下面（不做任何计算、不用 find/ls 的输出当目标）
#   - 先跑不带参数的（只列清单），确认无误再加 --yes 真删
#
# 前置条件（都不满足就别跑）：
#   1. frontend/ 已构建且通过验收（design/run-acceptance.mjs 全过）
#   2. frontend/ 的改动已提交
#   3. 没有 worker 还在读 src/（它生成样式时会读 Vue 源码）

set -euo pipefail
cd "$(dirname "$0")/.."   # → dsh-console/

TARGETS_FILES=(
  "index.html"
  "vite.config.ts"
  "tsconfig.json"
  "package.json"
  "pnpm-lock.yaml"
)
TARGETS_DIRS=(
  "src"
  "node_modules"
  "dist"
)

echo "== 将删除的文件 =="
for f in "${TARGETS_FILES[@]}"; do [ -e "$f" ] && echo "  $f" || echo "  （不存在，跳过）$f"; done
echo "== 将删除的目录（递归） =="
for d in "${TARGETS_DIRS[@]}"; do [ -e "$d" ] && echo "  $d/" || echo "  （不存在，跳过）$d/"; done

if [ "${1:-}" != "--yes" ]; then
  echo
  echo "这是清单预览。确认后重跑：bash design/remove-vue.sh --yes"
  exit 0
fi

for f in "${TARGETS_FILES[@]}"; do [ -e "$f" ] && rm -f "$f"; done
for d in "${TARGETS_DIRS[@]}"; do [ -e "$d" ] && rm -rf "$d"; done

echo
echo "== 删除完成，剩下的顶层内容 =="
ls -A
echo
echo "== 下一步：验证自动上溯仍然找得到产物 =="
echo "  cd backend && MOON_HOME=\$PWD/.sandbox/moonhome moon build --target native"
echo "  起后端（不设 DSH_CONSOLE_DIST），确认 / 返回 200 且是新栈页面"
