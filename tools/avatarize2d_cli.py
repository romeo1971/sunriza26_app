#!/usr/bin/env python3
# Improved avatarize2d_cli.py – similar to earlier version, with cell meta
import argparse, json, math
from pathlib import Path
from PIL import Image, ImageFilter, ImageDraw
import numpy as np, cv2

def feather_mask(w, h, feather=12):
    m = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle((0,0,w-1,h-1), radius=int(min(w,h)*0.12), fill=255)
    return m.filter(ImageFilter.GaussianBlur(radius=feather))

def save_idle_loop(photo: Image.Image, out_dir: Path, fps=30, loop_sec=4):
    W, H = photo.size
    frames = int(fps*loop_sec)
    path = str(out_dir/"idle.mp4")
    vw = cv2.VideoWriter(path, cv2.VideoWriter_fourcc(*"mp4v"), fps, (W, H))
    for i in range(frames):
        t = i/frames * 2*math.pi
        tx = 2.0*math.sin(t); ty = 1.5*math.cos(1.3*t); rot = 0.8*math.sin(0.7*t)
        fr = photo.copy()
        fr = fr.rotate(rot, resample=Image.BICUBIC, expand=False)
        fr = fr.transform(fr.size, Image.AFFINE, (1,0,tx/W, 0,1,ty/H), resample=Image.BICUBIC)
        frame = cv2.cvtColor(np.array(fr), cv2.COLOR_RGB2BGR)
        vw.write(frame)
    vw.release(); return path

def save_atlas(photo: Image.Image, out_dir: Path, roi, classes):
    x,y,w,h = roi
    mouth = photo.crop((x,y,x+w,y+h)).convert("RGBA")
    cols = rows = int(math.ceil(math.sqrt(len(classes))))
    cell_w, cell_h = w, h
    atlas = Image.new("RGBA", (cell_w*cols, cell_h*rows), (0,0,0,0))
    cells = {}
    for idx, name in enumerate(classes):
        cx, cy = idx%cols, idx//cols
        atlas.paste(mouth, (cx*cell_w, cy*cell_h))
        cells[name] = {"x": cx*cell_w, "y": cy*cell_h, "w": cell_w, "h": cell_h}
    atlas.save(out_dir/"atlas.png")
    meta = {"grid":{"cols":cols,"rows":rows},"classes":classes,"cells":cells,"mask":"mask.png","roi":{"x":x,"y":y,"w":w,"h":h}}
    (out_dir/"atlas.json").write_text(json.dumps(meta, indent=2))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--photo", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--roi", default=None, help="x,y,w,h")
    ap.add_argument("--visemes", default="Rest,AI,E,U,O,MBP,FV,L,WQ,R,CH,TH")
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--loop_sec", type=int, default=4)
    ap.add_argument("--feather", type=int, default=12)
    a = ap.parse_args()

    out = Path(a.out); out.mkdir(parents=True, exist_ok=True)
    img = Image.open(a.photo).convert("RGB"); W,H = img.size
    if a.roi:
        x,y,w,h = map(int, a.roi.split(","))
    else:
        w = int(W*0.32); h = int(H*0.18); x = int(W*0.34); y = int(H*0.68)
    roi = (x,y,w,h)
    (out/"roi.json").write_text(json.dumps({"x":x,"y":y,"w":w,"h":h}, indent=2))

    m = feather_mask(w,h, a.feather); m.save(out/"mask.png")
    save_idle_loop(img, out, a.fps, a.loop_sec)

    classes = [c.strip() for c in a.visemes.split(",") if c.strip()]
    save_atlas(img, out, roi, classes)
    print("OK:", out)

if __name__ == "__main__":
    main()

