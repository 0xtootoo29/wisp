#!/bin/bash
# 打包 Wisp.app 成拖拽式 DMG（含 Applications 快捷方式 + 首次打开说明）
set -e
cd "$(dirname "$0")"
APP=~/Applications/Wisp.app
[ -d "$APP" ] || { echo "找不到 $APP，先跑 build.sh"; exit 1; }
STAGE=$(mktemp -d); trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/Wisp.app"
ln -s /Applications "$STAGE/应用程序"
cat > "$STAGE/首次打开必读.txt" <<'TXT'
安装：把 Wisp.app 拖到「应用程序」文件夹。

首次打开（重要）：
Wisp 尚未做 Apple 公证，第一次打开会被系统拦一下。任选一种：
  · 在「应用程序」里右键点 Wisp → 选「打开」→ 弹窗里再点「打开」；
  · 或：系统设置 → 隐私与安全性 → 下拉找到 Wisp → 点「仍要打开」。
只需做这一次，之后正常双击即可。

更省事的装法（无需上面这步）：
终端粘贴运行——
curl -fsSL https://raw.githubusercontent.com/0xtootoo29/wisp/main/install.sh | bash

装好后点悬浮球（或 ⌥⌘V）开始语音。
项目主页：https://github.com/0xtootoo29/wisp
TXT
rm -f dist/Wisp.dmg
hdiutil create -volname "Wisp" -srcfolder "$STAGE" -ov -format UDZO -quiet dist/Wisp.dmg
echo "built dist/Wisp.dmg ($(du -h dist/Wisp.dmg | cut -f1))"
