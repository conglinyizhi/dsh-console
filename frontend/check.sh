#!/usr/bin/env bash
#
# 改完代码跑这个：类型检查 + 构建。单退出码。
#   ./check.sh            类型 + 构建
#   ./check.sh --fast     只做类型检查（几秒）

set -euo pipefail

cd "$(dirname "$0")"

export MOON_CC=clang MOON_AR=ar MOON_LD=clang
export MOON_HOME="${MOON_HOME:-$PWD/.sandbox/moonhome}"

echo "== moon check --target js =="
moon check --target js

if [ "${1:-}" = "--fast" ]; then
  echo
  echo "（--fast：跳过构建）"
  exit 0
fi

echo
./build.sh

echo
echo "check 通过。"
