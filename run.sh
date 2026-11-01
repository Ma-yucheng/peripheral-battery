#!/usr/bin/env bash
# 编译并启动「外设电量」
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$ROOT/build/PeripheralBattery.app"

if [[ ! -d "$APP" ]]; then
  "$ROOT/build.sh"
fi

# 先退出已在运行的实例，避免菜单栏出现两个图标
pkill -f "PeripheralBattery.app/Contents/MacOS/PeripheralBattery" >/dev/null 2>&1 || true

open "$APP"
echo "已启动，请查看菜单栏右上角的电池图标。"
