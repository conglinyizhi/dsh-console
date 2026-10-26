#!/usr/bin/env bash
#
# 用示例数据起一份控制台：不碰你自己的 ~/.dsh，也不要求这台机器装过 DSH。
#   ./scripts/demo.sh            → http://127.0.0.1:5390/
#   PORT=5400 ./scripts/demo.sh  → 换端口
#
# 数据落在临时目录（DSH_CONSOLE_DEMO_DIR 可指定），退出后可以随手删。

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/backend/_build/native/debug/build/dsh-console-backend.exe"
PORT="${PORT:-5390}"
BASE="${DSH_CONSOLE_DEMO_DIR:-$(mktemp -d -t dsh-console-demo-XXXXXX)}"

if [ ! -x "$BIN" ]; then
  echo "找不到后端可执行文件：$BIN" >&2
  echo "先构建：cd backend && moon build --target native" >&2
  exit 1
fi

mkdir -p "$BASE/dsh-home/profiles" "$BASE/state" "$BASE/homes"

for name in demo-alpha demo-beta demo-gamma; do
  mkdir -p "$BASE/dsh-home/profiles/$name"
  cat > "$BASE/dsh-home/profiles/$name/cordis.patch.yml" <<PATCH
# 演示用 profile，不是真实配置
- id: agent-default-model
  name: "@deepseek-ai/dsh-agent-default-model"
  config:
    provider: demo
    model: demo-model
PATCH
done

echo "示例数据：$BASE"
echo "打开：http://127.0.0.1:$PORT/"
echo "（Ctrl+C 退出；数据目录可以随手删）"

exec env \
  DSH_HOME="$BASE/dsh-home" \
  XDG_STATE_HOME="$BASE/state" \
  DSH_CONSOLE_HOMES_ROOT="$BASE/homes" \
  DSH_CONSOLE_BACKEND_PORT="$PORT" \
  "$BIN"
