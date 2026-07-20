#!/bin/bash
# GPT Live 菜单栏小球 — 重编译部署脚本
set -e
cd "$(dirname "$0")"
APP=/tmp/Wisp.app
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Wisp</string>
  <key>CFBundleDisplayName</key><string>Wisp</string>
  <key>CFBundleIdentifier</key><string>local.tootoo.gptlive</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleExecutable</key><string>GPTLive</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
swiftc -O -o "$APP/Contents/MacOS/GPTLive" GPTLive.swift WispUI.swift -framework Cocoa -framework Carbon
swiftc -O -o "$APP/Contents/MacOS/wisp-bridge" wisp-bridge.swift
mkdir -p "$APP/Contents/Resources/skins"
cp skins/skin*.png "$APP/Contents/Resources/skins/"
cp icon/AppIcon.icns "$APP/Contents/Resources/"
codesign -s - --force "$APP"

# Native Messaging 清单：Chrome 由此找到 wisp-bridge
# 双 ID：本地开发版（extension-id.txt，manifest 预埋 key）+ Chrome 商店正式版
DEV_ID=$(head -1 extension-id.txt)
STORE_ID="mghelpfopaeahcpdgjnbffnmkeapgpnn"
NM_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
mkdir -p "$NM_DIR"
cat > "$NM_DIR/com.tootoo.wisp.json" <<NM
{
  "name": "com.tootoo.wisp",
  "description": "Wisp native messaging bridge",
  "path": "$HOME/Applications/Wisp.app/Contents/MacOS/wisp-bridge",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$STORE_ID/", "chrome-extension://$DEV_ID/"]
}
NM
pkill -x GPTLive 2>/dev/null || true
rm -rf ~/Applications/Wisp.app ~/Applications/GPTLive.app && cp -R "$APP" ~/Applications/
open ~/Applications/Wisp.app
echo "deployed to ~/Applications/Wisp.app"
