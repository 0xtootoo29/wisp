#!/bin/bash
# Wisp 卸载 — curl -fsSL https://raw.githubusercontent.com/<org>/wisp/main/uninstall.sh | bash
set -euo pipefail
pkill -x GPTLive 2>/dev/null || true
rm -rf "$HOME/Applications/Wisp.app"
for d in "Google/Chrome" "Google/Chrome Beta" "Arc/User Data"; do
  rm -f "$HOME/Library/Application Support/$d/NativeMessagingHosts/com.tootoo.wisp.json"
done
echo "[Wisp] 已卸载。扩展请在 chrome://extensions 中手动移除。"
