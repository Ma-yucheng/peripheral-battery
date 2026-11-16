#!/usr/bin/env bash
# 编译最新代码 → 替换 /Applications 里已安装的版本 → 重启
# 用法：
#   ./install.sh            更新并启动
#   ./install.sh --dry-run  只演示会做什么，不编译、不动 /Applications
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="PeripheralBattery"
BUNDLE_ID="com.local.peripheralbattery"
SRC="$ROOT/build/${APP_NAME}.app"
DEST="/Applications/${APP_NAME}.app"
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) echo "未知参数: $arg"; exit 2 ;;
  esac
done

step() { printf "\n\033[1m==> %s\033[0m\n" "$1"; }
dry()  { if [[ $DRY_RUN -eq 1 ]]; then echo "   [dry-run] $1"; fi; }

# ── 1. 编译 ────────────────────────────────────────────────
step "1/5 编译最新代码"
if [[ $DRY_RUN -eq 1 ]]; then
  dry "会执行 ./build.sh（本次跳过，避免等编译）"
else
  "$ROOT/build.sh"
  [[ -d "$SRC" ]] || { echo "构建产物不存在: $SRC"; exit 1; }
fi

# ── 2. 退出正在运行的实例 ──────────────────────────────────
step "2/5 退出正在运行的实例"
RUNNING="$(pgrep -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" | tr '\n' ' ' || true)"
if [[ -n "$RUNNING" ]]; then
  if [[ $DRY_RUN -eq 1 ]]; then
    dry "会先退出正在运行的进程：PID $RUNNING"
  else
    osascript -e "tell application id \"${BUNDLE_ID}\" to quit" >/dev/null 2>&1 || true
    sleep 1
    pkill -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" >/dev/null 2>&1 || true
    sleep 1
    echo "   已退出"
  fi
else
  echo "   当前没有在运行"
fi

# ── 3. 备份旧版本 ──────────────────────────────────────────
step "3/5 备份旧版本"
if [[ -d "$DEST" ]]; then
  if [[ $DRY_RUN -eq 1 ]]; then
    dry "会把 $DEST 备份为 ${DEST}.bak"
  else
    rm -rf "${DEST}.bak"
    cp -R "$DEST" "${DEST}.bak"
    echo "   已备份：${DEST}.bak"
  fi
else
  echo "   未安装过，跳过"
fi

# ── 4. 安装 ────────────────────────────────────────────────
step "4/5 安装到 /Applications"
if [[ $DRY_RUN -eq 1 ]]; then
  dry "会用 $SRC 覆盖 $DEST"
else
  if [[ ! -w /Applications ]]; then
    echo "   ✗ 当前账号对 /Applications 没有写权限"
    echo "     请改用管理员账号，或执行：sudo ./install.sh"
    exit 1
  fi
  rm -rf "$DEST"
  cp -R "$SRC" "$DEST"
  echo "   已写入 $DEST"
fi

# ── 5. 校验并启动 ──────────────────────────────────────────
step "5/5 校验并启动"
if [[ $DRY_RUN -eq 1 ]]; then
  dry "会执行 codesign -v / plutil -lint / open \"$DEST\""
  echo
  echo "（dry-run 结束，没有做任何改动）"
  exit 0
fi

codesign -v "$DEST" 2>/dev/null && echo "   签名校验通过"
plutil -lint "$DEST/Contents/Info.plist" >/dev/null && echo "   Info.plist 正常"
if [[ -f "$DEST/Contents/Resources/build-info.txt" ]]; then
  sed 's/^/   /' "$DEST/Contents/Resources/build-info.txt"
fi

open "$DEST"

echo
echo "✅ 已更新并启动：$DEST"
echo "   • 首次启动会重新询问「蓝牙权限」——ad-hoc 签名每次重建都算新版本，点「允许」即可"
echo "   • 显示模式、设备勾选、小组件位置都会保留（Bundle ID 没变）"
echo "   • 回滚：rm -rf \"$DEST\" && mv \"${DEST}.bak\" \"$DEST\""
