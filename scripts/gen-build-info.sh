#!/usr/bin/env bash
# 生成构建信息常量：短 sha + 构建时刻（本地时间）。
# 产物两份：frontend/build_info.mbt（客户端侧）与 backend/store/build_info.mbt（服务端读数用）。
# 用法：scripts/gen-build-info.sh [仓库根]，默认取本脚本的上一级。
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
SHA="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo)"
AT="$(date '+%Y-%m-%d %H:%M:%S')"
if [ -z "$SHA" ]; then
  SHA="unknown"
fi

write() {
  local file="$1"
  local title="$2"
  {
    echo "// ${title}（由 scripts/gen-build-info.sh 生成，不要手改）"
    echo "//"
    echo "// build_sha：git 短 sha；build_at：构建时刻（本地时间，给人看的）。"
    echo "pub let build_sha : String = \"$SHA\""
    echo "pub let build_at : String = \"$AT\""
  } > "$file"
}

write "$ROOT/frontend/build_info.mbt" "客户端构建信息"
write "$ROOT/backend/store/build_info.mbt" "服务端构建信息"
echo "build-info: $SHA @ $AT"
