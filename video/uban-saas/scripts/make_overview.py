# 影格總覽：每隔 STEP 秒抽一格，拼成一張圖，每格左下角標時間。
# 用法：python scripts/make_overview.py out/ad_60s.mp4 out/ad_60s_overview.png [STEP 秒] [每列幾格] [每格寬度]
import subprocess, sys, tempfile, os
from PIL import Image, ImageDraw, ImageFont

src, dst = sys.argv[1], sys.argv[2]
step = float(sys.argv[3]) if len(sys.argv) > 3 else 1.5
cols = int(sys.argv[4]) if len(sys.argv) > 4 else 5
W = int(sys.argv[5]) if len(sys.argv) > 5 else 480  # 每格寬度
PAD = 8

dur = float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", src]).decode().strip())
times = []
t = step / 2
while t < dur:
    times.append(t)
    t += step

font = ImageFont.truetype("C:/Windows/Fonts/msjhbd.ttc", 22)
tiles = []
with tempfile.TemporaryDirectory() as tmp:
    for i, t in enumerate(times):
        f = os.path.join(tmp, f"{i:03d}.png")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", f"{t:.3f}", "-i", src, "-frames:v", "1", "-vf", f"scale={W}:-2", f], check=True)
        im = Image.open(f).convert("RGB")
        d = ImageDraw.Draw(im)
        label = f"{int(t // 60)}:{t % 60:04.1f}"
        h = im.height
        d.rectangle([0, h - 34, 92, h], fill=(0, 0, 0))
        d.text((8, h - 30), label, font=font, fill=(255, 220, 90))
        tiles.append(im)

H = tiles[0].height
rows = (len(tiles) + cols - 1) // cols
sheet = Image.new("RGB", (cols * W + (cols + 1) * PAD, rows * H + (rows + 1) * PAD), (255, 255, 255))
for i, im in enumerate(tiles):
    sheet.paste(im, (PAD + (i % cols) * (W + PAD), PAD + (i // cols) * (H + PAD)))
sheet.save(dst)
print(dst, sheet.size, len(tiles), "格")
