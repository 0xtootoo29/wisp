#!/usr/bin/env python
"""Wisp AppIcon.icns 生成：源图圆角方 → 透明四角 + macOS 留白 → iconset → icns"""
import os, subprocess, sys
from PIL import Image, ImageDraw

if len(sys.argv) < 2:
    sys.exit("用法: python make_icon.py <logo源图.png>（深底方形，四角待抠）")
SRC = sys.argv[1]
ROOT = os.path.dirname(os.path.abspath(__file__))
ICON_DIR = os.path.join(ROOT, "icon")
MASTER = os.path.join(ICON_DIR, "wisp_master.png")
ICONSET = os.path.join(ICON_DIR, "AppIcon.iconset")
ICNS = os.path.join(ICON_DIR, "AppIcon.icns")

os.makedirs(ICONSET, exist_ok=True)

src = Image.open(SRC).convert("RGBA")

# 1) 测圆角方 bbox：亮度 > 12 的像素（四角纯黑；深藏蓝底板亮度约 20，阈值必须低于它）
gray = src.convert("L")
bbox = gray.point(lambda p: 255 if p > 12 else 0).getbbox()
assert bbox, "bbox 检测失败：全图都低于阈值"
plate = src.crop(bbox)

# 2) 贴到 1024 透明画布，内容 824px（macOS Big Sur 标准留白），自绘圆角遮罩
CANVAS, CONTENT = 1024, 824
plate = plate.resize((CONTENT, CONTENT), Image.LANCZOS)
radius = int(CONTENT * 0.2237)  # macOS 圆角比例
mask = Image.new("L", (CONTENT, CONTENT), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, CONTENT - 1, CONTENT - 1], radius=radius, fill=255)
plate.putalpha(mask)
canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
off = (CANVAS - CONTENT) // 2
canvas.paste(plate, (off, off), plate)
canvas.save(MASTER)

# 自检：四角透明、中心不透明
px = canvas.load()
for x, y in [(0, 0), (1023, 0), (0, 1023), (1023, 1023), (60, 60)]:
    assert px[x, y][3] == 0, f"角 ({x},{y}) 不透明: {px[x,y]}"
assert px[512, 512][3] == 255, "中心透明了"

# 3) iconset 全尺寸
for size in [16, 32, 128, 256, 512]:
    for scale in [1, 2]:
        n = size * scale
        suffix = "" if scale == 1 else "@2x"
        canvas.resize((n, n), Image.LANCZOS).save(
            os.path.join(ICONSET, f"icon_{size}x{size}{suffix}.png"))

# 4) icns
subprocess.run(["iconutil", "-c", "icns", ICONSET, "-o", ICNS], check=True)
assert os.path.getsize(ICNS) > 100_000, "icns 太小，可疑"
print("OK", ICNS, os.path.getsize(ICNS))
