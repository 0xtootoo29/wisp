#!/bin/bash
# Wisp 一键安装 — curl -fsSL https://raw.githubusercontent.com/<org>/wisp/main/install.sh | bash
# 装完的用户动作：Chrome 商店页点一次「添加至 Chrome」+ 登录 ChatGPT（如未登录）
set -euo pipefail

REPO="0xtootoo29/wisp"
EXT_ID="mghelpfopaeahcpdgjnbffnmkeapgpnn"          # Chrome 商店正式版扩展 ID
DEV_ID="icbpolfbnfgcloeeahjmiknhfflnefkp"          # 本地开发版（manifest 预埋 key）ID
CWS_URL="https://chromewebstore.google.com/detail/$EXT_ID"
APP_DIR="$HOME/Applications"
APP="$APP_DIR/Wisp.app"

say() { printf '\033[1;36m[Wisp]\033[0m %s\n' "$1"; }
die() { printf '\033[1;31m[Wisp]\033[0m %s\n' "$1" >&2; exit 1; }

[ "$(uname)" = "Darwin" ] || die "Wisp 只支持 macOS。"
[ -d "/Applications/Google Chrome.app" ] || [ -d "$HOME/Applications/Google Chrome.app" ] \
  || die "未找到 Google Chrome，请先安装：https://www.google.com/chrome/"

# 1. 下载最新 Release 的 Wisp.app
say "下载 Wisp.app ..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsSL "https://github.com/$REPO/releases/latest/download/Wisp.zip" -o "$TMP/Wisp.zip"
# 先解压到暂存区并验证，确认无误再替换 —— 任何一步失败都不动用户现有的 App
ditto -xk "$TMP/Wisp.zip" "$TMP/staging"
STAGED="$TMP/staging/Wisp.app"
[ -x "$STAGED/Contents/MacOS/GPTLive" ] || die "下载的安装包不完整，已中止（未改动现有安装）。"
xattr -dr com.apple.quarantine "$STAGED" 2>/dev/null || true
mkdir -p "$APP_DIR"
pkill -x GPTLive 2>/dev/null || true
rm -rf "$APP"
mv "$STAGED" "$APP"
[ -x "$APP/Contents/MacOS/GPTLive" ] || die "安装失败。"

# 2. Native Messaging 清单（Chrome 由此找到 wisp-bridge，无需任何授权弹窗）
say "配置浏览器桥接 ..."
for d in "Google/Chrome" "Google/Chrome Beta" "Arc/User Data"; do
  NM_DIR="$HOME/Library/Application Support/$d/NativeMessagingHosts"
  [ -d "$HOME/Library/Application Support/$d" ] || continue
  mkdir -p "$NM_DIR"
  cat > "$NM_DIR/com.tootoo.wisp.json" <<NM
{
  "name": "com.tootoo.wisp",
  "description": "Wisp native messaging bridge",
  "path": "$APP/Contents/MacOS/wisp-bridge",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$EXT_ID/", "chrome-extension://$DEV_ID/"]
}
NM
done

# 3. 启动 —— 首次打开会弹三步安装引导窗，剩余步骤由它接管
open "$APP"
say "已安装。跟随 Wisp 引导窗完成剩余两步（装扩展 + 登录 ChatGPT）✦"
