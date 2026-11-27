#!/usr/bin/env python3
"""Netice eğitim ve tanıtım videosu (16:9, 1920x1080, 30 fps).

Pazarlama odaklı: önce sorun ve tek uygulama vaadi, sonra dört aşama (Hazırla,
Okut, Analiz et, Raporla) ve her aşamada kazandırdığı, ardından kimler için
olduğu, en sonda güven ve çağrı. Her sahnede solda adım etiketi, başlık ve sırayla
beliren fayda maddeleri; sağda uygulamanın gerçek ekranı (telefon ya da
dizüstü çerçevesinde), işaret halkası ve yavaş yakınlaşma; altta alt yazı ve
ilerleme çubuğu.

Kullanım: python3 tool/video/egitim.py <dil> [--sessiz]
Girdi:
  tool/video/egitim_<dil>.json                         sahneler ve anlatım
  build/video/frames/<dil>/*.png, hedefler.json         flutter test tool/video_test.dart
  build/screenshots/<dil>/masaustu_<ad>.png              flutter test tool/magaza/genis_ekranlar_test.dart
  build/video/audio/<dil>/egitim_<sahne>.mp3            seslendirme (seslendir.py --egitim); yoksa
                                                       süre metin uzunluğundan tahmin edilir
  build/video/muzik.mp3                                 isteğe bağlı fon müziği
Çıktı: build/video/egitim_<dil>.mp4
"""
import json
import math
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from compose import draw_mark, ease_back, ease_out, clamp, duration, font, wrap  # noqa: E402

W, H, FPS = 1920, 1080, 30
NAVY = (15, 27, 61)
NAVY_DARK = (6, 11, 28)
EMERALD = (16, 185, 129)
EMERALD_D = (5, 150, 105)
GOLD = (233, 196, 106)
CORAL = (232, 97, 60)
SOFT = (185, 195, 226)
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

LANG = sys.argv[1] if len(sys.argv) > 1 else 'tr'
SILENT = '--sessiz' in sys.argv
RTL = LANG == 'ar'
DIR = 'rtl' if RTL else None
FADE = 0.45  # sahneler arası geçiş
TAIL = 0.7   # anlatım bittikten sonra sahnenin kalma süresi

UI = {
    'tr': {'adim': 'ADIM', 'site': 'Kâğıttan sonuca, saniyeler içinde.'},
    'en': {'adim': 'STEP', 'site': 'From paper to results in seconds.'},
}.get(LANG, {'adim': 'STEP', 'site': ''})


def F(size, bold=False):
    return font(LANG, size, bold)


# ---------------------------------------------------------------- arka plan
def make_background():
    import numpy as np
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    k = np.clip((yy / H) * 0.6 + ((W - xx) / W if RTL else xx / W) * 0.4, 0, 1)[..., None]
    arr = np.array(NAVY, np.float32) * (1 - k) + np.array(NAVY_DARK, np.float32) * k
    bg = Image.fromarray(arr.astype(np.uint8), 'RGB')
    glow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([W * 0.55, -H * 0.5, W * 1.25, H * 0.6], fill=EMERALD + (60,))
    gd.ellipse([-W * 0.2, H * 0.6, W * 0.35, H * 1.4], fill=(76, 99, 210, 40))
    glow = glow.filter(ImageFilter.GaussianBlur(160))
    bg.paste(glow, (0, 0), glow)
    # Silik optik daire deseni (marka dokusu).
    tex = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    td = ImageDraw.Draw(tex)
    for y in range(40, H, 56):
        for x in range(40, W, 56):
            td.ellipse([x - 9, y - 9, x + 9, y + 9], outline=(255, 255, 255, 9), width=2)
    bg.paste(tex, (0, 0), tex)
    return bg.convert('RGBA')


BG = None


# ---------------------------------------------------------------- cihaz çerçeveleri
_dev = {}


def phone_layer(name, h=860):
    key = ('p', name, h)
    if key in _dev:
        return _dev[key]
    shot = Image.open(f'{ROOT}/build/video/frames/{LANG}/{name}.png').convert('RGB')
    w = round(h * shot.width / shot.height)
    bez = 16
    ow, oh = w + 2 * bez, h + 2 * bez
    pad = 60
    lay = Image.new('RGBA', (ow + 2 * pad, oh + 2 * pad), (0, 0, 0, 0))
    sh = Image.new('RGBA', lay.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([pad + 10, pad + 30, pad + ow - 10, pad + oh + 10], 60, fill=(0, 0, 0, 150))
    lay = Image.alpha_composite(lay, sh.filter(ImageFilter.GaussianBlur(28)))
    d = ImageDraw.Draw(lay)
    d.rounded_rectangle([pad, pad, pad + ow, pad + oh], 58, fill=(18, 22, 36, 255), outline=(70, 80, 110, 255), width=2)
    scr = shot.resize((w, h), Image.LANCZOS)
    m = Image.new('L', (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w - 1, h - 1], 44, fill=255)
    lay.paste(scr, (pad + bez, pad + bez), m)
    # Üst çentik.
    d.rounded_rectangle([pad + ow / 2 - 46, pad + bez + 10, pad + ow / 2 + 46, pad + bez + 34], 12, fill=(10, 12, 20, 255))
    info = dict(img=lay, sx=pad + bez, sy=pad + bez, sw=w, sh=h, scale=w / 360.0)
    _dev[key] = info
    return info


def laptop_layer(name, w=1060):
    key = ('l', name, w)
    if key in _dev:
        return _dev[key]
    shot = Image.open(f'{ROOT}/build/screenshots/{LANG}/masaustu_{name}.png').convert('RGB')
    h = round(w * shot.height / shot.width)
    bez = 18
    pad = 60
    ow, oh = w + 2 * bez, h + 2 * bez
    base_h = 26
    lay = Image.new('RGBA', (ow + 2 * pad + 120, oh + base_h + 2 * pad), (0, 0, 0, 0))
    ox = pad + 60
    sh = Image.new('RGBA', lay.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([ox + 20, pad + 40, ox + ow - 20, pad + oh + base_h + 10], 30, fill=(0, 0, 0, 150))
    lay = Image.alpha_composite(lay, sh.filter(ImageFilter.GaussianBlur(30)))
    d = ImageDraw.Draw(lay)
    d.rounded_rectangle([ox, pad, ox + ow, pad + oh], 22, fill=(18, 22, 36, 255), outline=(70, 80, 110, 255), width=2)
    scr = shot.resize((w, h), Image.LANCZOS)
    m = Image.new('L', (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w - 1, h - 1], 8, fill=255)
    lay.paste(scr, (ox + bez, pad + bez), m)
    # Taban.
    d.rounded_rectangle([ox - 60, pad + oh - 2, ox + ow + 60, pad + oh + base_h], 14, fill=(150, 158, 182, 255))
    d.rounded_rectangle([ox + ow / 2 - 90, pad + oh - 2, ox + ow / 2 + 90, pad + oh + 8], 6, fill=(110, 118, 142, 255))
    info = dict(img=lay, sx=ox + bez, sy=pad + bez, sw=w, sh=h, scale=w / 1440.0)
    _dev[key] = info
    return info


def place_device(frame, info, cx, cy, t, dur, appear=0.0, zoom=0.04):
    """Cihazı yavaş yakınlaşma ve kayarak gelişle yerleştirir; ekranın sol üst
    köşesinin video koordinatını ve ölçeği döndürür."""
    a = ease_out((t - appear) / 0.7)
    s = (0.94 + 0.06 * a) * (1 + zoom * clamp(t / max(dur, 0.1)))
    img = info['img']
    iw, ih = int(img.width * s), int(img.height * s)
    im = img.resize((iw, ih), Image.BILINEAR)
    if a < 1:
        im.putalpha(im.getchannel('A').point(lambda v: int(v * a)))
    x = int(cx - iw / 2 + (1 - a) * 80 * (-1 if RTL else 1))
    y = int(cy - ih / 2 + (1 - a) * 30)
    frame.paste(im, (x, y), im)
    return x + info['sx'] * s, y + info['sy'] * s, info['scale'] * s


def ring(frame, x, y, w, h, t):
    """Hedefi gösteren nabız atan yeşil çerçeve."""
    if t < 0:
        return
    d = ImageDraw.Draw(frame)
    a = ease_out(t / 0.5)
    p = 0.5 + 0.5 * math.sin(t * 4.2)
    pad = 10 + 6 * p
    d.rounded_rectangle([x - pad, y - pad, x + w + pad, y + h + pad], 18, outline=EMERALD + (int(255 * a),), width=5)
    pad2 = pad + 10 + 10 * p
    d.rounded_rectangle([x - pad2, y - pad2, x + w + pad2, y + h + pad2], 24, outline=EMERALD + (int(90 * a * (1 - p)),), width=3)


# ---------------------------------------------------------------- yazı yardımcıları
def text(frame, xy, s, fnt, fill, a=1.0, anchor='la'):
    if a <= 0:
        return
    ov = Image.new('RGBA', frame.size, (0, 0, 0, 0))
    ImageDraw.Draw(ov).text(xy, s, font=fnt, fill=fill[:3] + (int(255 * a),), anchor=anchor, direction=DIR)
    frame.alpha_composite(ov)


def pill(frame, x, y, s, fnt, bg, fg=(255, 255, 255), a=1.0, pad=(22, 12)):
    d = ImageDraw.Draw(frame)
    tw = d.textlength(s, font=fnt, direction=DIR)
    bb = fnt.getbbox('Ag')
    th = bb[3] - bb[1]
    w, h = tw + pad[0] * 2, th + pad[1] * 2
    if RTL:
        x = x - w
    ov = Image.new('RGBA', frame.size, (0, 0, 0, 0))
    od = ImageDraw.Draw(ov)
    od.rounded_rectangle([x, y, x + w, y + h], h / 2, fill=bg[:3] + (int(bg[3] * a) if len(bg) > 3 else int(255 * a),))
    od.text((x + w / 2, y + h / 2), s, font=fnt, fill=fg + (int(255 * a),), anchor='mm', direction=DIR)
    frame.alpha_composite(ov)
    return w, h


def check_icon(frame, x, y, r, a):
    ov = Image.new('RGBA', frame.size, (0, 0, 0, 0))
    od = ImageDraw.Draw(ov)
    od.ellipse([x - r, y - r, x + r, y + r], fill=EMERALD_D + (int(255 * a),))
    pts = [(x - r * 0.42, y + r * 0.02), (x - r * 0.1, y + r * 0.34), (x + r * 0.46, y - r * 0.3)]
    od.line(pts, fill=(255, 255, 255, int(255 * a)), width=max(3, int(r * 0.22)), joint='curve')
    frame.alpha_composite(ov)


# ---------------------------------------------------------------- sahneler
TEXT_X = 150 if not RTL else W - 150
COL_W = 760


def left_column(frame, sc, t, top=230, col_w=COL_W):
    """Adım etiketi, başlık ve fayda maddeleri (sırayla belirir)."""
    y = top
    lab_f = F(26, True)
    if sc.get('adim'):
        a = ease_out((t - 0.1) / 0.5)
        w, h = pill(frame, TEXT_X, y, f"{UI['adim']} {sc['adim']}", F(24, True), EMERALD_D + (255,), a=a)
        text(frame, (TEXT_X + (w + 18) * (-1 if RTL else 1), y + h / 2), sc['ust'].upper() if LANG not in ('tr', 'az') else
             sc['ust'].replace('i', 'İ').upper(), lab_f, SOFT, a, anchor='rm' if RTL else 'lm')
        y += h + 34
    elif sc.get('ust'):
        a = ease_out((t - 0.1) / 0.5)
        _, h = pill(frame, TEXT_X, y, sc['ust'], F(24, True), (255, 255, 255, 34), a=a)
        y += h + 34
    big = F(70, True)
    d = ImageDraw.Draw(frame)
    lines = wrap(d, sc['baslik'], big, col_w, LANG)
    a = ease_out((t - 0.25) / 0.6)
    for i, ln in enumerate(lines):
        text(frame, (TEXT_X, y + i * 86 + 30 * (1 - a)), ln, big, (255, 255, 255), a, anchor='ra' if RTL else 'la')
    y += len(lines) * 86 + 18
    lw = 120 * ease_out((t - 0.5) / 0.6)
    d = ImageDraw.Draw(frame)
    if RTL:
        d.rounded_rectangle([TEXT_X - lw, y, TEXT_X, y + 6], 3, fill=EMERALD)
    else:
        d.rounded_rectangle([TEXT_X, y, TEXT_X + lw, y + 6], 3, fill=EMERALD)
    y += 50
    item_f = F(36)
    for i, f in enumerate(sc.get('faydalar', [])):
        k = (t - 0.9 - i * sc['_aralik']) / 0.5
        a = ease_out(k)
        if a <= 0:
            continue
        cx = TEXT_X + (-24 if RTL else 24)
        check_icon(frame, cx, y + 22, 22 * (0.6 + 0.4 * ease_back(k)), a)
        text(frame, (TEXT_X + (-66 if RTL else 66) + (1 - a) * 30, y + 22), f, item_f, (235, 240, 252), a,
             anchor='rm' if RTL else 'lm')
        y += 74


def scene_step(frame, sc, t, dur):
    name = sc['ekran']
    left_column(frame, sc, t, col_w=620 if name.startswith('masaustu:') else COL_W)
    cx = 1390 if not RTL else 530
    if name.startswith('masaustu:'):
        info = laptop_layer(name.split(':', 1)[1], 840)
        sx, sy, s = place_device(frame, info, cx + 10 * (-1 if RTL else 1), 480, t, dur, appear=0.15, zoom=0.03)
    else:
        info = phone_layer(name, 790)
        sx, sy, s = place_device(frame, info, cx, 505, t, dur, appear=0.15)
        tg = HEDEF.get(name) or []
        if tg and sc.get('hedef', 0) is not None:
            x, y, w, h = tg[min(sc.get('hedef', 0), len(tg) - 1)]
            ring(frame, sx + x * s, sy + y * s, w * s, h * s, t - 1.4)
    badges(frame, sc, t, cx, info, name.startswith('masaustu:'))


# Ekranın çevresinde süzülen kısa etiketler (soru türleri, ölçütler…).
BADGE_COLORS = [EMERALD_D, (76, 99, 210), (200, 120, 40), (150, 80, 190)]


def badges(frame, sc, t, cx, info, laptop):
    items = sc.get('rozetler') or []
    if not items:
        return
    fnt = F(28, True)
    if laptop:
        d = ImageDraw.Draw(frame)
        ws = [d.textlength(it, font=fnt, direction=DIR) + 44 for it in items]
        x = cx + (10 if not RTL else -10) - (sum(ws) + 20 * (len(ws) - 1)) / 2
        for i, it in enumerate(items):
            a = clamp(ease_out((t - 1.8 - i * 0.7) / 0.5))
            if a > 0:
                pill(frame, x + (ws[i] if RTL else 0), 820 + 16 * (1 - a), it, fnt,
                     BADGE_COLORS[i % len(BADGE_COLORS)] + (255,), a=a, pad=(22, 13))
            x += ws[i] + 20
        return
    half_w = (info['sw'] * 1.0) / 2
    # Telefonun sol ve sağ kenarına sırayla, hafif salınımla.
    spots = [(-1, 250), (1, 420), (-1, 640), (1, 180)] if not laptop else [(-1, 200), (1, 760), (-1, 760)]
    for i, it in enumerate(items[:len(spots)]):
        side, y = spots[i]
        if RTL:
            side = -side
        k = (t - 1.8 - i * 0.7) / 0.5
        a = clamp(ease_out(k))
        if a <= 0:
            continue
        bob = 6 * math.sin(t * 1.6 + i * 1.3)
        d = ImageDraw.Draw(frame)
        tw = d.textlength(it, font=fnt, direction=DIR) + 44
        edge = cx + side * (half_w + 10)
        x = edge - tw * 0.55 if side < 0 else edge - tw * 0.45
        x += side * 30 * (1 - a)
        if RTL:
            x += tw
        pill(frame, x, y + bob, it, fnt, BADGE_COLORS[i % len(BADGE_COLORS)] + (255,), a=a, pad=(22, 13))


def scene_hook(frame, sc, t, dur):
    cx = W / 2
    a = ease_out((t - 0.1) / 0.6)
    text(frame, (cx, 300 - 20 * (1 - a)), sc['ust'], F(40, True), GOLD, a, anchor='mm')
    big = F(160, True)
    d = ImageDraw.Draw(frame)
    w_old = d.textlength(sc['eski'], font=big)
    w_new = d.textlength(sc['yeni'], font=big)
    gap = 190
    x_old = cx - (w_old + gap + w_new) / 2
    x_new = x_old + w_old + gap
    ay = 520
    # Eski süre: belirir, sonra üstü çizilip soluklaşır.
    a1 = ease_out((t - 0.5) / 0.6)
    strike = ease_out((t - 2.6) / 0.6)
    text(frame, (x_old, ay), sc['eski'], big, (255, 255, 255), a1 * (1 - 0.55 * strike), anchor='lm')
    if strike > 0:
        d = ImageDraw.Draw(frame)
        d.line([(x_old - 10, ay + 8), (x_old - 10 + (w_old + 20) * strike, ay - 6)], fill=CORAL + (255,), width=12)
    # Ok ve yeni süre.
    a2 = ease_back((t - 3.2) / 0.6)
    if a2 > 0:
        d = ImageDraw.Draw(frame)
        ax = x_old + w_old + 50
        al = clamp(a2)
        d.line([(ax, ay), (ax + 70, ay)], fill=(255, 255, 255, int(220 * al)), width=9)
        d.polygon([(ax + 66, ay - 22), (ax + 96, ay), (ax + 66, ay + 22)], fill=(255, 255, 255, int(220 * al)))
        text(frame, (x_new + 30 * (1 - al), ay), sc['yeni'], big, EMERALD, al, anchor='lm')
    a3 = ease_out((t - 1.2) / 0.6)
    lines = wrap(ImageDraw.Draw(frame), sc['alt'], F(38), 1300, LANG)
    for i, ln in enumerate(lines):
        text(frame, (cx, 700 + i * 52), ln, F(38), SOFT, a3, anchor='mm')


def scene_trust(frame, sc, t, dur):
    left_column(frame, sc, t)
    cx, cy = (1390 if not RTL else 530), 540
    a = ease_out((t - 0.2) / 0.7)
    # Kalkan: yuvarlak zemin, kilit ve dönen halka.
    r = 250 * (0.9 + 0.1 * a)
    ov = Image.new('RGBA', frame.size, (0, 0, 0, 0))
    od = ImageDraw.Draw(ov)
    od.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 255, 255, int(16 * a)), outline=(255, 255, 255, int(40 * a)), width=2)
    rr = r * 0.66
    od.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=EMERALD_D + (int(255 * a),))
    # kilit
    bw, bh = 150, 120
    od.rounded_rectangle([cx - bw / 2, cy - 20, cx + bw / 2, cy - 20 + bh], 22, fill=(255, 255, 255, int(255 * a)))
    od.arc([cx - 52, cy - 110, cx + 52, cy + 6], 180, 360, fill=(255, 255, 255, int(255 * a)), width=20)
    od.ellipse([cx - 14, cy + 22, cx + 14, cy + 50], fill=EMERALD_D + (int(255 * a),))
    od.rectangle([cx - 5, cy + 40, cx + 5, cy + 72], fill=EMERALD_D + (int(255 * a),))
    ang = t * 40
    od.arc([cx - r - 26, cy - r - 26, cx + r + 26, cy + r + 26], ang, ang + 70, fill=EMERALD + (int(200 * a),), width=6)
    od.arc([cx - r - 26, cy - r - 26, cx + r + 26, cy + r + 26], ang + 180, ang + 230, fill=GOLD + (int(160 * a),), width=6)
    frame.alpha_composite(ov)


def scene_cta(frame, sc, t, dur):
    cx = W / 2
    mark, tc = draw_mark(220, t)
    frame.alpha_composite(mark, (int(cx - 110), 150))
    a = ease_out((t - 1.3) / 0.6)
    text(frame, (cx, 450 + 20 * (1 - a)), 'Netice', F(110, True), (255, 255, 255), a, anchor='mm')
    a = ease_out((t - 1.7) / 0.6)
    text(frame, (cx, 560), sc['baslik'], F(52, True), EMERALD, a, anchor='mm')
    fy = 650
    fx = cx
    d = ImageDraw.Draw(frame)
    widths = [d.textlength(f, font=F(34)) + 90 for f in sc['faydalar']]
    total = sum(widths) + 40 * (len(widths) - 1)
    x = cx - total / 2
    for i, f in enumerate(sc['faydalar']):
        k = ease_out((t - 2.2 - i * 0.3) / 0.5)
        if k > 0:
            check_icon(frame, x + 24, fy + 24, 22, k)
            text(frame, (x + 60, fy + 24), f, F(34), (235, 240, 252), k, anchor='lm')
        x += widths[i] + 40
    k = ease_back((t - 3.0) / 0.6)
    if k > 0:
        pill(frame, cx - 220, 760, sc['adres'], F(44, True), EMERALD_D + (255,), a=clamp(k), pad=(60, 22))
    k = ease_out((t - 3.5) / 0.6)
    text(frame, (cx, 900), sc['magazalar'], F(30, True), SOFT, k, anchor='mm')


def scene_promise(frame, sc, t, dur):
    left_column(frame, sc, t)
    cx = 1390 if not RTL else 530
    lap = laptop_layer('ana_sayfa', 900)
    place_device(frame, lap, cx - 40, 470, t, dur, appear=0.15, zoom=0.02)
    ph = phone_layer(sc['ekran'], 560)
    place_device(frame, ph, cx - 290, 590, t, dur, appear=0.55, zoom=0.03)


def scene_cycle(frame, sc, t, dur):
    """Dört aşama: yan yana yuvarlak kartlar, aralarında ok, sırayla belirir."""
    cx = W / 2
    a = ease_out((t - 0.1) / 0.5)
    uw = ImageDraw.Draw(frame).textlength(sc['ust'], font=F(26, True)) + 44
    pill(frame, cx - uw / 2 if not RTL else cx + uw / 2, 190, sc['ust'], F(26, True), (255, 255, 255, 34), a=a)
    a = ease_out((t - 0.3) / 0.6)
    text(frame, (cx, 330 + 24 * (1 - a)), sc['baslik'], F(66, True), (255, 255, 255), a, anchor='mm')
    cards = sc['kartlar']
    n = len(cards)
    cw, ch, gap = 360, 360, 70
    total = n * cw + (n - 1) * gap
    x0 = cx - total / 2
    y0 = 450
    colors = [EMERALD_D, (76, 99, 210), (200, 120, 40), (150, 80, 190)]
    step = max(0.6, min(1.3, (dur - 3.0) / max(n, 1)))
    for i, (title, sub) in enumerate(cards):
        j = (n - 1 - i) if RTL else i
        k = (t - 1.0 - i * step) / 0.55
        a = clamp(ease_out(k))
        if a <= 0:
            continue
        x = x0 + j * (cw + gap)
        y = y0 + 40 * (1 - a)
        ov = Image.new('RGBA', frame.size, (0, 0, 0, 0))
        od = ImageDraw.Draw(ov)
        od.rounded_rectangle([x, y, x + cw, y + ch], 34, fill=(255, 255, 255, int(20 * a)), outline=(255, 255, 255, int(46 * a)), width=2)
        # Köşede yumuşak daire (hizmet kartlarıyla aynı dil), kartın içine kırpılmış.
        blob = Image.new('RGBA', frame.size, (0, 0, 0, 0))
        ImageDraw.Draw(blob).ellipse([x + cw - 130, y - 60, x + cw + 50, y + 120], fill=colors[i % 4] + (int(70 * a),))
        mask = Image.new('L', frame.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle([x + 2, y + 2, x + cw - 2, y + ch - 2], 32, fill=255)
        ov.paste(blob, (0, 0), Image.composite(blob, Image.new('RGBA', frame.size), mask).getchannel('A'))
        r = 52
        ccx, ccy = x + cw / 2, y + 96
        od.ellipse([ccx - r, ccy - r, ccx + r, ccy + r], fill=colors[i % 4] + (int(255 * a),))
        od.text((ccx, ccy), str(i + 1), font=F(54, True), fill=(255, 255, 255, int(255 * a)), anchor='mm')
        od.text((ccx, y + 200), title, font=F(46, True), fill=(255, 255, 255, int(255 * a)), anchor='mm', direction=DIR)
        frame.alpha_composite(ov)
        lines = wrap(ImageDraw.Draw(frame), sub, F(28), cw - 50, LANG)
        for li, ln in enumerate(lines[:3]):
            text(frame, (ccx, y + 262 + li * 38), ln, F(28), SOFT, a, anchor='mm')
        # Bir sonraki karta ok.
        if i < n - 1:
            ka = clamp(ease_out((t - 1.0 - (i + 0.6) * step) / 0.4))
            if ka > 0:
                d = ImageDraw.Draw(frame)
                if RTL:
                    ax = x - gap / 2
                    d.polygon([(ax + 14, y0 + ch / 2 - 18), (ax - 14, y0 + ch / 2), (ax + 14, y0 + ch / 2 + 18)],
                              fill=(255, 255, 255, int(200 * ka)))
                else:
                    ax = x + cw + gap / 2
                    d.polygon([(ax - 14, y0 + ch / 2 - 18), (ax + 14, y0 + ch / 2), (ax - 14, y0 + ch / 2 + 18)],
                              fill=(255, 255, 255, int(200 * ka)))


def scene_audience(frame, sc, t, dur):
    """Kimler için: ortada başlık, altında sırayla beliren kurum hapları."""
    cx = W / 2
    a = ease_out((t - 0.1) / 0.5)
    d = ImageDraw.Draw(frame)
    uw = d.textlength(sc['ust'], font=F(26, True)) + 44
    pill(frame, cx - uw / 2 if not RTL else cx + uw / 2, 170, sc['ust'], F(26, True), (255, 255, 255, 34), a=a)
    a = ease_out((t - 0.3) / 0.6)
    text(frame, (cx, 310 + 24 * (1 - a)), sc['baslik'], F(70, True), (255, 255, 255), a, anchor='mm')
    groups = sc['gruplar']
    fnt = F(36, True)
    pad = (34, 20)
    widths = [d.textlength(g, font=fnt, direction=DIR) + pad[0] * 2 for g in groups]
    rows, cur, cw = [], [], 0
    for i, w in enumerate(widths):
        if cur and cw + w + 24 > 1500:
            rows.append(cur)
            cur, cw = [], 0
        cur.append(i)
        cw += w + 24
    if cur:
        rows.append(cur)
    colors = [EMERALD_D, (76, 99, 210), (200, 120, 40), (150, 80, 190)]
    step = max(0.3, min(0.8, (dur - 4.0) / max(len(groups), 1)))
    y = 440
    for row in rows:
        rw = sum(widths[i] for i in row) + 24 * (len(row) - 1)
        x = cx - rw / 2
        order = list(reversed(row)) if RTL else row
        for i in order:
            k = (t - 1.0 - i * step) / 0.5
            a = clamp(ease_back(k))
            if a > 0:
                pill(frame, x + (widths[i] if RTL else 0), y + 20 * (1 - a), groups[i], fnt,
                     colors[i % 4] + (255,), a=a, pad=pad)
            x += widths[i] + 24
        y += 110
    k = ease_out((t - 1.4 - len(groups) * step) / 0.6)
    text(frame, (cx, y + 70), sc.get('alt', ''), F(36, True), GOLD, k, anchor='mm')


RENDER = {'adim': scene_step, 'masaustu': scene_step, 'kanca': scene_hook, 'vaat': scene_promise,
          'guven': scene_trust, 'kapanis': scene_cta, 'dongu': scene_cycle, 'kitle': scene_audience}


# ---------------------------------------------------------------- üst ve alt katman
def chrome(frame, sc, idx, t, total_t, steps_total):
    if sc['tur'] not in ('kanca', 'kapanis', 'dongu', 'kitle'):
        mk, _ = draw_mark(46)
        x = 70 if not RTL else W - 116
        frame.alpha_composite(mk, (x, 50))
        text(frame, (x + 62 if not RTL else x - 16, 73), 'Netice', F(30, True), (255, 255, 255), 1, anchor='rm' if RTL else 'lm')
        # Adım noktaları.
        n = steps_total
        cur = sc.get('adim', 0)
        d = ImageDraw.Draw(frame)
        x0 = W - 70 - n * 38 if not RTL else 70
        for i in range(1, n + 1):
            on = i <= cur
            cx = x0 + (i - 1) * 38 + 12
            if i == cur:
                d.rounded_rectangle([cx - 12, 64, cx + 30, 82], 9, fill=EMERALD)
            else:
                d.ellipse([cx - 9, 64, cx + 9, 82], fill=(EMERALD_D if on else (255, 255, 255, 50)))
    # İlerleme çubuğu.
    d = ImageDraw.Draw(frame)
    d.rectangle([0, H - 8, W, H], fill=(255, 255, 255, 22))
    d.rectangle([0, H - 8, W * clamp(total_t), H], fill=EMERALD)


def subtitle(frame, sc, t, dur):
    """Anlatımın o anki cümlesi alt yazı olarak (sesi kapalı izleyenler için)."""
    parts = sc['_cumleler']
    if not parts:
        return
    talk = max(dur - TAIL, 0.1)
    tot = sum(len(p) for p in parts)
    acc = 0
    cur = parts[-1]
    for p in parts:
        acc += len(p)
        if t < talk * acc / tot:
            cur = p
            break
    fnt = F(32)
    d = ImageDraw.Draw(frame)
    lines = wrap(d, cur, fnt, 1400, LANG)[:2]
    lh = 44
    bh = len(lines) * lh + 28
    y0 = H - 34 - bh
    widths = [d.textlength(ln, font=fnt, direction=DIR) for ln in lines]
    bw = max(widths) + 60
    a = clamp(t / 0.3) * clamp((dur - t) / 0.3)
    ov = Image.new('RGBA', frame.size, (0, 0, 0, 0))
    od = ImageDraw.Draw(ov)
    od.rounded_rectangle([W / 2 - bw / 2, y0, W / 2 + bw / 2, y0 + bh], 18, fill=(6, 11, 28, int(190 * a)))
    for i, ln in enumerate(lines):
        od.text((W / 2, y0 + 14 + i * lh + lh / 2), ln, font=fnt, fill=(255, 255, 255, int(255 * a)), anchor='mm', direction=DIR)
    frame.alpha_composite(ov)


# ---------------------------------------------------------------- ana akış
HEDEF = {}


def sentences(s):
    out, cur = [], ''
    for ch in s:
        cur += ch
        if ch in '.!?。！？' and len(cur.strip()) > 1:
            out.append(cur.strip())
            cur = ''
    if cur.strip():
        out.append(cur.strip())
    return out


def main():
    global BG, HEDEF
    data = json.load(open(f'{ROOT}/tool/video/egitim_{LANG}.json', encoding='utf-8'))
    scenes = data['sahneler']
    hp = f'{ROOT}/build/video/frames/{LANG}/hedefler.json'
    HEDEF = json.load(open(hp)) if os.path.exists(hp) else {}
    BG = make_background()
    audio_dir = f'{ROOT}/build/video/audio/{LANG}'
    steps_total = max((s.get('adim', 0) for s in scenes), default=0)
    timeline = []
    t0 = 0.0
    for sc in scenes:
        ap = f'{audio_dir}/egitim_{sc["id"]}.mp3'
        has = os.path.exists(ap) and not SILENT
        speech = duration(ap) if has else max(3.0, len(sc['metin']) / 15.5)
        lead = 0.5
        dur = lead + speech + TAIL
        if sc['tur'] == 'kanca':
            dur = max(dur, 6.5)
        if sc['tur'] == 'kapanis':
            dur = max(dur, 7.0)
        sc['_cumleler'] = sentences(sc['metin'])
        n = len(sc.get('faydalar', []))
        sc['_aralik'] = min(1.4, max(0.5, (speech - 1.0) / max(n, 1)))
        timeline.append(dict(sc=sc, start=t0, dur=dur, audio=ap if has else None, lead=lead))
        t0 += dur
    total = t0
    print(f'toplam {total:.1f} sn, {len(scenes)} sahne')

    os.makedirs(f'{ROOT}/build/video', exist_ok=True)
    silent_mp4 = f'{ROOT}/build/video/egitim_{LANG}_goruntu.mp4'
    ff = subprocess.Popen(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}',
                           '-r', str(FPS), '-i', '-', '-c:v', 'libx264', '-preset', 'medium', '-crf', '19',
                           '-pix_fmt', 'yuv420p', silent_mp4], stdin=subprocess.PIPE)
    nframes = int(total * FPS)

    def draw(seg, gt):
        t = gt - seg['start']
        fr = BG.copy()
        RENDER[seg['sc']['tur']](fr, seg['sc'], t, seg['dur'])
        chrome(fr, seg['sc'], 0, t, gt / total, steps_total)
        subtitle(fr, seg['sc'], t - seg['lead'], seg['dur'] - seg['lead'])
        return fr

    si = 0
    for f in range(nframes):
        gt = f / FPS
        while si < len(timeline) - 1 and gt >= timeline[si]['start'] + timeline[si]['dur']:
            si += 1
        seg = timeline[si]
        fr = draw(seg, gt)
        # Geçiş: bir sonraki sahneye yumuşak çapraz geçiş.
        end = seg['start'] + seg['dur']
        if si < len(timeline) - 1 and gt > end - FADE:
            nxt = draw(timeline[si + 1], end)
            fr = Image.blend(fr, nxt, ease_out((gt - (end - FADE)) / FADE))
        ff.stdin.write(fr.convert('RGB').tobytes())
        if f % (FPS * 10) == 0:
            print(f'{gt:.0f} sn')
    ff.stdin.close()
    ff.wait()

    # Ses: anlatımlar kendi başlangıçlarında, altta kısık müzik.
    out = f'{ROOT}/build/video/egitim_{LANG}.mp4'
    inputs, filters, labels = ['-i', silent_mp4], [], []
    n = 1
    for seg in timeline:
        if seg['audio']:
            inputs += ['-i', seg['audio']]
            ms = int((seg['start'] + seg['lead']) * 1000)
            filters.append(f'[{n}:a]adelay={ms}|{ms},volume=1.0[a{n}]')
            labels.append(f'[a{n}]')
            n += 1
    music = f'{ROOT}/build/video/muzik.mp3'
    if os.path.exists(music):
        inputs += ['-stream_loop', '-1', '-i', music]
        filters.append(f'[{n}:a]volume={0.10 if labels else 0.35},afade=t=out:st={max(total - 3, 0):.2f}:d=3[m]')
        labels.append('[m]')
        n += 1
    if labels:
        filters.append(f'{"".join(labels)}amix=inputs={len(labels)}:normalize=0:duration=longest[aout]')
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', *inputs, '-filter_complex', ';'.join(filters),
                        '-map', '0:v', '-map', '[aout]', '-c:v', 'copy', '-c:a', 'aac', '-b:a', '160k',
                        '-t', f'{total:.2f}', out], check=True)
        os.remove(silent_mp4)
    else:
        os.replace(silent_mp4, out)
    print(out)


if __name__ == '__main__':
    main()
