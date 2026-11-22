"""Netice uygulama simgesi üretici (Konsept A "Optik N", premium sürüm).

Kullanım: python3 tool/icon/make_icons.py  (repo kökünden)
Tüm platformların simge dosyalarını yeniden üretir.
"""
import json
import math
import os
from PIL import Image, ImageDraw, ImageFilter

S = 1024 * 4  # süper örnekleme
INK_TOP = (30, 46, 96)
INK_BOTTOM = (8, 15, 38)
EM_LIGHT = (52, 211, 153)
EM_DARK = (5, 150, 105)
GRID = [[1, 0, 0, 2], [1, 1, 0, 1], [1, 0, 1, 1], [1, 0, 0, 1]]


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def background(size):
    """Sol üstten sağ alta derin lacivert gradyan + üstte yumuşak ışık."""
    # Hızlı gradyan: önce küçük üret, sonra büyüt.
    small = Image.new("RGB", (256, 256))
    sp = small.load()
    for y in range(256):
        for x in range(256):
            t = (x * 0.35 + y * 0.65) / 255
            c = lerp(INK_TOP, INK_BOTTOM, min(1, t))
            # sol üstte hafif ışık
            d = math.hypot(x - 60, y - 40) / 256
            glow = max(0.0, 0.18 - d * 0.22)
            c = tuple(min(255, int(v + 255 * glow * 0.35)) for v in c)
            sp[x, y] = c
    return small.resize((size, size), Image.BICUBIC)


def mark(size, box, with_empty=True, shadow=True):
    """Şeffaf zemine 4×4 optik daire işaretini çizer. box = (x0, y0, w)."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    x0, y0, w = box
    cell = w / 4
    r = cell * 0.36
    # Gölge katmanı
    if shadow:
        sh = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        sd = ImageDraw.Draw(sh)
        for yy in range(4):
            for xx in range(4):
                if GRID[yy][xx] == 1:
                    cx, cy = x0 + cell * (xx + 0.5), y0 + cell * (yy + 0.5) + r * 0.18
                    sd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(0, 0, 0, 120))
        sh = sh.filter(ImageFilter.GaussianBlur(r * 0.35))
        layer.alpha_composite(sh)
    d = ImageDraw.Draw(layer)
    for yy in range(4):
        for xx in range(4):
            cx, cy = x0 + cell * (xx + 0.5), y0 + cell * (yy + 0.5)
            kind = GRID[yy][xx]
            if kind == 0 and with_empty:
                d.ellipse([cx - r * 0.92, cy - r * 0.92, cx + r * 0.92, cy + r * 0.92],
                          outline=(255, 255, 255, 52), width=max(2, int(cell * 0.055)))
            elif kind == 1:
                # Fildişi dolu daire, üstten alta hafif gradyan
                dot = Image.new("RGBA", (int(r * 2) + 2, int(r * 2) + 2), (0, 0, 0, 0))
                dd = ImageDraw.Draw(dot)
                n = int(r * 2)
                for i in range(n):
                    c = lerp((255, 255, 255), (226, 222, 210), i / n)
                    dd.line([(0, i), (n, i)], fill=c + (255,))
                m = Image.new("L", dot.size, 0)
                ImageDraw.Draw(m).ellipse([0, 0, n, n], fill=255)
                dot.putalpha(m)
                layer.alpha_composite(dot, (int(cx - r), int(cy - r)))
            elif kind == 2:
                # Zümrüt onay dairesi + parıltı
                glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
                ImageDraw.Draw(glow).ellipse([cx - r * 1.5, cy - r * 1.5, cx + r * 1.5, cy + r * 1.5],
                                             fill=EM_LIGHT + (110,))
                glow = glow.filter(ImageFilter.GaussianBlur(r * 0.6))
                layer.alpha_composite(glow)
                n = int(r * 2)
                dot = Image.new("RGBA", (n + 2, n + 2), (0, 0, 0, 0))
                dd = ImageDraw.Draw(dot)
                for i in range(n):
                    dd.line([(0, i), (n, i)], fill=lerp(EM_LIGHT, EM_DARK, i / n) + (255,))
                m = Image.new("L", dot.size, 0)
                ImageDraw.Draw(m).ellipse([0, 0, n, n], fill=255)
                dot.putalpha(m)
                layer.alpha_composite(dot, (int(cx - r), int(cy - r)))
                d = ImageDraw.Draw(layer)
                pts = [(cx - r * 0.42, cy + r * 0.02), (cx - r * 0.1, cy + r * 0.34), (cx + r * 0.46, cy - r * 0.3)]
                wdt = max(3, int(r * 0.22))
                d.line(pts, fill=(255, 255, 255, 255), width=wdt, joint="curve")
                for p in (pts[0], pts[2]):
                    d.ellipse([p[0] - wdt / 2, p[1] - wdt / 2, p[0] + wdt / 2, p[1] + wdt / 2], fill=(255, 255, 255, 255))
    return layer


def full_icon(px, rounded=False, scale=0.56):
    bg = background(S).convert("RGBA")
    w = S * scale
    bg.alpha_composite(mark(S, ((S - w) / 2, (S - w) / 2, w)))
    # İnce iç kenar ışığı
    edge = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle([S * 0.004, S * 0.004, S * 0.996, S * 0.996], radius=S * 0.22 if rounded else 0,
                                           outline=(255, 255, 255, 26), width=int(S * 0.006))
    bg.alpha_composite(edge)
    if rounded:
        m = Image.new("L", (S, S), 0)
        ImageDraw.Draw(m).rounded_rectangle([0, 0, S, S], radius=S * 0.225, fill=255)
        bg.putalpha(m)
    return bg.resize((px, px), Image.LANCZOS)


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)


def main():
    root = os.getcwd()
    master = full_icon(1024)
    save(master, f"{root}/assets/icon/netice_icon_1024.png")
    save(full_icon(1024, rounded=True), f"{root}/assets/icon/netice_icon_rounded_1024.png")

    # Android: eski tip + uyarlanabilir (adaptive) simge.
    dens = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    res = f"{root}/android/app/src/main/res"
    bg_big = background(S).convert("RGBA")
    fg_big = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    w = S * 0.40  # 108dp tuvalde güvenli alan 66dp
    fg_big.alpha_composite(mark(S, ((S - w) / 2, (S - w) / 2, w)))
    for name, f in dens.items():
        save(full_icon(int(48 * f), rounded=True), f"{res}/mipmap-{name}/ic_launcher.png")
        save(bg_big.resize((int(108 * f),) * 2, Image.LANCZOS), f"{res}/mipmap-{name}/ic_launcher_background.png")
        save(fg_big.resize((int(108 * f),) * 2, Image.LANCZOS), f"{res}/mipmap-{name}/ic_launcher_foreground.png")
    os.makedirs(f"{res}/mipmap-anydpi-v26", exist_ok=True)
    with open(f"{res}/mipmap-anydpi-v26/ic_launcher.xml", "w") as fh:
        fh.write('<?xml version="1.0" encoding="utf-8"?>\n'
                 '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                 '    <background android:drawable="@mipmap/ic_launcher_background"/>\n'
                 '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
                 '    <monochrome android:drawable="@mipmap/ic_launcher_foreground"/>\n'
                 '</adaptive-icon>\n')

    # iOS (köşeleri sistem yuvarlar; saydamlık olmamalı).
    ios = f"{root}/ios/Runner/Assets.xcassets/AppIcon.appiconset"
    with open(f"{ios}/Contents.json") as fh:
        contents = json.load(fh)
    for im in contents["images"]:
        fn = im.get("filename")
        if not fn:
            continue
        base = float(im["size"].split("x")[0])
        sc = int(im["scale"].replace("x", ""))
        save(master.convert("RGB").resize((int(round(base * sc)),) * 2, Image.LANCZOS), f"{ios}/{fn}")

    # macOS (kendi yuvarlak köşeli biçimi, kenar boşluklu).
    mac = f"{root}/macos/Runner/Assets.xcassets/AppIcon.appiconset"
    rounded = full_icon(1024, rounded=True)
    canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    canvas.alpha_composite(rounded.resize((824, 824), Image.LANCZOS), (100, 100))
    for s in [16, 32, 64, 128, 256, 512, 1024]:
        save(canvas.resize((s, s), Image.LANCZOS), f"{mac}/app_icon_{s}.png")

    # Windows .ico
    win = full_icon(256, rounded=True)
    win.save(f"{root}/windows/runner/resources/app_icon.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])

    # Uygulama içi önizleme
    preview = Image.new("RGB", (1400, 520), (246, 243, 236))
    preview.paste(rounded.resize((420, 420), Image.LANCZOS), (50, 50), rounded.resize((420, 420), Image.LANCZOS))
    for i, s in enumerate([180, 96, 48]):
        im = rounded.resize((s, s), Image.LANCZOS)
        preview.paste(im, (560 + sum([180, 96, 48][:i]) + 60 * i, 260 - s // 2), im)
    save(preview, f"{root}/build/icon_preview.png")


if __name__ == "__main__":
    main()
