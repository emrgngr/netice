"""Netice'nin faydalarını anlatan sosyal medya gönderi afişleri (1080x1350, 4:5).

Kullanım: python3 tool/sosyal/afisler.py <dil> [çıktı klasörü]

Metinler tool/sosyal/afisler_<dil>.json. Uygulama ekranları eğitim videosuyla
aynı kaynaktan gelir:
  build/video/frames/<dil>/*.png          flutter test tool/video_test.dart --dart-define=LANG_SHOT=<dil>
  build/screenshots/<dil>/masaustu_*.png  flutter test tool/magaza/genis_ekranlar_test.dart --dart-define=LANG_SHOT=<dil>
Yeşil zemindeki yazı ve simgeler daima beyazdır (renk kuralı).
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

LANG = sys.argv[1] if len(sys.argv) > 1 else 'tr'
OUT = sys.argv[2] if len(sys.argv) > 2 else None
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.argv = ['egitim.py', LANG]
sys.path.insert(0, os.path.join(ROOT, 'tool', 'video'))
import egitim as E  # noqa: E402  (cihaz çizimleri, rozetler, yazı tipleri)

W, H = 1080, 1350
NAVY, NAVY_DARK, EMERALD, EMERALD_D, GOLD, SOFT = E.NAVY, E.NAVY_DARK, E.EMERALD, E.EMERALD_D, E.GOLD, E.SOFT
RTL = E.RTL
DIR = E.DIR
M = 72  # kenar boşluğu
LATIN = LANG not in ('ar', 'hi', 'ja', 'ko', 'zh', 'ru')


def F(size, bold=False):
    return E.F(size, bold)


def display(size):
    """Büyük rakamlar için gösterişli yazı tipi (Latin dillerde Anton)."""
    if LATIN:
        return ImageFont.truetype(os.path.join(ROOT, 'tool/magaza/fontlar/Anton-Regular.ttf'), size)
    return F(size, True)


def slogan_font(size):
    if LATIN:
        return ImageFont.truetype(os.path.join(ROOT, 'tool/magaza/fontlar/DMSerifDisplay-Italic.ttf'), size)
    return F(size, True)


def background(seed):
    import numpy as np
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    k = np.clip(yy / H * 0.75 + xx / W * 0.25, 0, 1)[..., None]
    arr = np.array(NAVY, np.float32) * (1 - k) + np.array(NAVY_DARK, np.float32) * k
    bg = Image.fromarray(arr.astype(np.uint8), 'RGB').convert('RGBA')
    glow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    g = ImageDraw.Draw(glow)
    # Işık lekeleri her afişte biraz yer değiştirir.
    ox = (seed * 97) % 240 - 120
    g.ellipse([W * 0.45 + ox, -H * 0.25, W * 1.35 + ox, H * 0.42], fill=EMERALD + (70,))
    g.ellipse([-W * 0.45 - ox, H * 0.62, W * 0.45 - ox, H * 1.3], fill=(76, 99, 210, 60))
    bg.alpha_composite(glow.filter(ImageFilter.GaussianBlur(150)))
    tex = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    t = ImageDraw.Draw(tex)
    for y in range(36, H, 54):
        for x in range(36, W, 54):
            t.ellipse([x - 8, y - 8, x + 8, y + 8], outline=(255, 255, 255, 10), width=2)
    bg.alpha_composite(tex)
    return bg


def tx(img, xy, s, fnt, fill, anchor='la'):
    ImageDraw.Draw(img).text(xy, s, font=fnt, fill=fill, anchor=anchor, direction=DIR)


def width(s, fnt):
    return ImageDraw.Draw(Image.new('RGB', (1, 1))).textlength(s, font=fnt, direction=DIR)


def X(x, w=0):
    """Sağdan sola dillerde yatay konumu aynalar."""
    return W - x - w if RTL else x


def header(img, data):
    logo = Image.open(os.path.join(ROOT, 'assets/brand/netice_logo_160.png')).convert('RGBA').resize((58, 58), Image.LANCZOS)
    img.alpha_composite(logo, (int(X(M, 58)), 58))
    tx(img, (X(M + 74), 87), 'Netice', F(36, True), (255, 255, 255), 'rm' if RTL else 'lm')
    tx(img, (X(W - M), 87), data['site'], F(24), SOFT, 'lm' if RTL else 'rm')


def footer(img, data):
    d = ImageDraw.Draw(img)
    d.line([M, H - 96, W - M, H - 96], fill=(255, 255, 255, 40), width=2)
    tx(img, (X(M), H - 52), data['alt'], slogan_font(36), EMERALD, 'rm' if RTL else 'lm')


def pill(img, x, y, s, fnt, bg, fg=(255, 255, 255), pad=(24, 12)):
    w = width(s, fnt) + pad[0] * 2
    h = fnt.size + pad[1] * 2 + 4
    x0 = X(x, w)
    ImageDraw.Draw(img).rounded_rectangle([x0, y, x0 + w, y + h], h / 2, fill=bg)
    tx(img, (x0 + w / 2, y + h / 2), s, fnt, fg, 'mm')
    return w, h


def wrap_words(text, fnt, maxw):
    if LANG in ('ja', 'zh'):
        return E.wrap(ImageDraw.Draw(Image.new('RGB', (1, 1))), text, fnt, maxw, LANG)
    lines, cur = [], ''
    for wd in text.split():
        cand = (cur + ' ' + wd).strip()
        if cur and width(cand, fnt) > maxw:
            lines.append(cur)
            cur = wd
        else:
            cur = cand
    if cur:
        lines.append(cur)
    return lines


def headline(img, y, text, accent, maxw, size=76):
    """Başlık; 'vurgu' kısmı yeşil. Sığmazsa küçülür (en çok 3 satır)."""
    while True:
        fnt = F(size, True)
        lines = wrap_words(text, fnt, maxw)
        if len(lines) <= 3 or size <= 54:
            break
        size -= 4
    lh = int(size * 1.16)
    a0 = text.find(accent) if accent else -1
    a1 = a0 + len(accent) if a0 >= 0 else -1
    pos = 0
    for i, ln in enumerate(lines):
        start = text.find(ln, pos)
        pos = start + len(ln)
        yy = y + i * lh
        if RTL or a0 < 0 or start >= a1 or start + len(ln) <= a0:
            colour = EMERALD if (a0 >= 0 and start >= a0 and start + len(ln) <= a1) else (255, 255, 255)
            tx(img, (X(M), yy), ln, fnt, colour, 'ra' if RTL else 'la')
            continue
        # Satırın vurgulu parçasını ayrı renkte çiz.
        s0, s1 = max(a0, start) - start, min(a1, start + len(ln)) - start
        parts = [(ln[:s0], (255, 255, 255)), (ln[s0:s1], EMERALD), (ln[s1:], (255, 255, 255))]
        x = M
        for s, c in parts:
            if s:
                tx(img, (x, yy), s, fnt, c)
                x += width(s, fnt)
    # Altına kısa yeşil çizgi.
    yb = y + len(lines) * lh + 10
    ImageDraw.Draw(img).rounded_rectangle([X(M, 110), yb, X(M, 110) + 110, yb + 7], 3, fill=EMERALD)
    return yb + 36


def check(img, x, y, r=20):
    lay = Image.new('RGBA', img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    d.ellipse([x - r, y - r, x + r, y + r], fill=EMERALD_D)
    d.line([(x - r * 0.45, y + r * 0.02), (x - r * 0.1, y + r * 0.38), (x + r * 0.5, y - r * 0.35)], fill=(255, 255, 255), width=max(3, int(r / 5)))
    img.alpha_composite(lay)


def benefits(img, y, items, maxw, size=34):
    while size > 24 and max(width(f, F(size)) for f in items) > maxw - 60:
        lines_ok = all(len(wrap_words(f, F(size), maxw - 60)) <= 2 for f in items)
        if lines_ok:
            break
        size -= 1
    fnt = F(size)
    for f in items:
        lines = wrap_words(f, fnt, maxw - 60)
        check(img, X(M + 20), y + size * 0.62)
        for j, ln in enumerate(lines):
            tx(img, (X(M + 60), y + j * size * 1.25), ln, fnt, (235, 240, 252), 'ra' if RTL else 'la')
        y += len(lines) * size * 1.25 + 26
    return y


def stat(img, left, cy, big, small, center=False):
    """Büyük rakam kartı; sol kenarı [left] (RTL'de sağ kenar), dikey ortası [cy]."""
    fnt = display(92)
    while width(big, fnt) > 330 and fnt.size > 48:
        fnt = display(fnt.size - 6)
    sf = F(24, True)
    w = max(width(big, fnt), width(small, sf)) + 80
    h = fnt.size * 1.15 + 66
    cx = W / 2 if center else X(left, w) + w / 2
    lay = Image.new('RGBA', img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    d.rounded_rectangle([cx - w / 2 + 6, cy - h / 2 + 14, cx + w / 2 + 6, cy + h / 2 + 14], 30, fill=(0, 0, 0, 120))
    lay = lay.filter(ImageFilter.GaussianBlur(14))
    d = ImageDraw.Draw(lay)
    d.rounded_rectangle([cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2], 30, fill=(255, 255, 255, 250))
    img.alpha_composite(lay)
    tx(img, (cx, cy - 14), big, fnt, NAVY, 'mm')
    tx(img, (cx, cy + h / 2 - 30), small, sf, EMERALD_D, 'mm')


def device(img, name, region):
    """Cihazı verilen bölgeye sığdırıp yerleştirir. region = (x0, y0, x1, y1)."""
    x0, y0, x1, y1 = region
    if name.startswith('masaustu:'):
        info = E.laptop_layer(name.split(':', 1)[1], 1060)
    else:
        info = E.phone_layer(name, 860)
    lay = info['img']
    s = min((x1 - x0) / lay.width, (y1 - y0) / lay.height)
    lay = lay.resize((int(lay.width * s), int(lay.height * s)), Image.LANCZOS)
    img.alpha_composite(lay, (int((x0 + x1 - lay.width) / 2), int(y1 - lay.height)))


def chips(img, y, groups):
    fnt = F(30, True)
    colours = [EMERALD_D, (79, 70, 229), (217, 119, 6), (147, 51, 234), (14, 116, 144)]
    rows, cur, cw = [], [], 0
    for g in groups:
        w = width(g, fnt) + 52
        if cur and cw + w + 16 > W - 2 * M:
            rows.append(cur)
            cur, cw = [], 0
        cur.append((g, w))
        cw += w + 16
    rows.append(cur)
    i = 0
    for r in rows:
        total = sum(w for _, w in r) + 16 * (len(r) - 1)
        x = (W - total) / 2
        for g, w in r:
            ImageDraw.Draw(img).rounded_rectangle([x, y, x + w, y + 64], 32, fill=colours[i % len(colours)])
            tx(img, (x + w / 2, y + 32), g, fnt, (255, 255, 255), 'mm')
            x += w + 16
            i += 1
        y += 82
    return y


def lock(img, cx, cy, r=190):
    lay = Image.new('RGBA', img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    d.ellipse([cx - r - 40, cy - r - 40, cx + r + 40, cy + r + 40], outline=(255, 255, 255, 40), width=3)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=EMERALD_D)
    bw, bh = r * 0.9, r * 0.72
    d.arc([cx - bw * 0.32, cy - r * 0.62, cx + bw * 0.32, cy + r * 0.05], 180, 360, fill=(255, 255, 255), width=int(r * 0.12))
    d.line([cx - bw * 0.32 + r * 0.06, cy - r * 0.27, cx - bw * 0.32 + r * 0.06, cy - r * 0.02], fill=(255, 255, 255), width=int(r * 0.12))
    d.line([cx + bw * 0.32 - r * 0.06, cy - r * 0.27, cx + bw * 0.32 - r * 0.06, cy - r * 0.02], fill=(255, 255, 255), width=int(r * 0.12))
    d.rounded_rectangle([cx - bw / 2, cy - r * 0.05, cx + bw / 2, cy - r * 0.05 + bh], r * 0.12, fill=(255, 255, 255))
    d.ellipse([cx - r * 0.08, cy + r * 0.18, cx + r * 0.08, cy + r * 0.34], fill=EMERALD_D)
    d.rounded_rectangle([cx - r * 0.035, cy + r * 0.28, cx + r * 0.035, cy + r * 0.48], 4, fill=EMERALD_D)
    img.alpha_composite(lay)


def download(img, y):
    a = E.cta_assets()
    qr = a.get('qr')
    if qr is not None:
        q = qr.resize((300, 300), Image.NEAREST)
        card = Image.new('RGBA', (340, 340), (255, 255, 255, 255))
        m = Image.new('L', card.size, 0)
        ImageDraw.Draw(m).rounded_rectangle([0, 0, 339, 339], 28, fill=255)
        card.alpha_composite(q, (20, 20))
        img.paste(card, (int((W - 340) / 2), y), m)
        y += 370
    badges = a.get('badges', [])
    if badges:
        bh = 74
        ims = [b.resize((int(b.width * bh / b.height), bh), Image.LANCZOS) for b in badges]
        row1, row2 = ims[:2], ims[2:]
        for row in (row1, row2):
            if not row:
                continue
            total = sum(i.width for i in row) + 20 * (len(row) - 1)
            x = (W - total) / 2
            for im in row:
                img.alpha_composite(im, (int(x), y))
                x += im.width + 20
            y += bh + 18
    return y


def render(data, p, idx):
    img = background(idx)
    header(img, data)
    y = 160
    _, ph = pill(img, M, y, p['ust'], F(24, True), EMERALD_D)
    y += ph + 30
    y = headline(img, y, p['baslik'], p.get('vurgu'), W - 2 * M)
    scr = p.get('ekran', '')
    bottom = H - 120
    if p.get('gruplar'):
        y = chips(img, y + 10, p['gruplar'])
        if p.get('sayi'):
            stat(img, 0, (y + bottom) / 2 + 10, p['sayi'], p['sayi_alt'], center=True)
    elif p.get('kilit'):
        y = benefits(img, y, p['faydalar'], W - 2 * M)
        lock(img, W / 2, (y + bottom) / 2 + 10, min(190, (bottom - y) / 2 - 60))
    elif p.get('indir'):
        y = benefits(img, y, p['faydalar'], W - 2 * M)
        download(img, int(y + 10))
    elif scr.startswith('masaustu:'):
        y = benefits(img, y, p['faydalar'], W - 2 * M)
        device(img, scr, (M - 70, y - 30, W - M + 70, bottom + 30))
        if p.get('sayi'):
            stat(img, M, bottom - 150, p['sayi'], p['sayi_alt'])
    else:
        # Solda maddeler, sağda telefon.
        col = 520
        yb = benefits(img, y + 10, p['faydalar'], col)
        dx0 = (M - 40) if RTL else (M + col - 20)
        device(img, scr, (dx0, y - 40, dx0 + W - M - col + 60, bottom + 40))
        if p.get('sayi'):
            stat(img, M, max(yb + 130, bottom - 190), p['sayi'], p['sayi_alt'])
    footer(img, data)
    return img.convert('RGB')


def main():
    data = json.load(open(os.path.join(HERE, f'afisler_{LANG}.json'), encoding='utf-8'))
    out = OUT or os.path.join(ROOT, 'build', 'sosyal', LANG)
    os.makedirs(out, exist_ok=True)
    for i, p in enumerate(data['afisler']):
        img = render(data, p, i)
        path = os.path.join(out, f'netice_{p["id"]}.png')
        img.save(path, optimize=True)
        print(path)


if __name__ == '__main__':
    main()
