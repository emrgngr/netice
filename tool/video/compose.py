#!/usr/bin/env python3
"""Netice kullanım rehberi videosunu birleştirir.

Kullanım: python3 tool/video/compose.py <dil>            (tüm uygulama rehberi)
          python3 tool/video/compose.py <dil> --kilavuz  (kılavuzun her bölümü ayrı video, tool/video/kilavuz.json)
Girdi:
  build/video/frames/<dil>/*.png ve hedefler.json  (flutter test tool/video_test.dart)
  tool/video/anlatim_<dil>.json                     (sahne -> anlatım metni)
  build/video/audio/<dil>/<NN>.mp3                  (sahne sırasıyla seslendirme; yoksa sessiz)
Çıktı: build/video/rehber_<dil>.mp4 (720x1280, 24 fps)
"""
import json
import math
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'brand'))
from bolum_simgeleri import SIMGELER, simge as bolum_simgesi  # noqa: E402

W, H, FPS = 720, 1280, 24
NAVY = (15, 27, 61)
NAVY_DARK = (6, 11, 28)
EMERALD = (16, 185, 129)
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

TITLES = {
    'tr': 'Kullanım rehberi', 'en': 'User guide', 'de': 'Anleitung', 'fr': "Guide d'utilisation",
    'ru': 'Руководство', 'az': 'İstifadə bələdçisi', 'es': 'Guía de uso', 'it': 'Guida all\'uso',
    'ar': 'دليل الاستخدام', 'zh': '使用指南', 'ja': '使い方ガイド',
    'pt': 'Guia de uso', 'hi': 'उपयोग गाइड', 'id': 'Panduan penggunaan', 'ko': '사용 안내',
}


def font(lang, size, bold=False):
    special = {
        'ar': 'assets/pdf_fonts/NotoSansArabic-Bold.ttf' if bold else 'assets/pdf_fonts/NotoSansArabic-Regular.ttf',
        'zh': 'assets/pdf_fonts/NotoSansSC-Regular.ttf',
        'ja': 'assets/pdf_fonts/NotoSansJP-Regular.ttf',
        'ru': 'assets/pdf_fonts/NotoSans-Bold.ttf' if bold else 'assets/pdf_fonts/NotoSans-Regular.ttf',
        'hi': 'assets/pdf_fonts/NotoSansDevanagari-Regular.ttf',
        'ko': 'assets/pdf_fonts/NotoSansKR-Regular.ttf',
    }.get(lang)
    path = special or ('assets/fonts/PlusJakartaSans_700Bold.ttf' if bold else 'assets/fonts/PlusJakartaSans_500Medium.ttf')
    kw = {}
    if lang in ('ar', 'hi'):
        kw['layout_engine'] = ImageFont.Layout.RAQM
    return ImageFont.truetype(os.path.join(ROOT, path), size, **kw)


def wrap(draw, text, fnt, width, lang):
    # Çince/Japoncada boşluk yok: karakter karakter böl.
    units = list(text) if lang in ('zh', 'ja') else text.split(' ')
    sep = '' if lang in ('zh', 'ja') else ' '
    lines, cur = [], ''
    for u in units:
        t = (cur + sep + u) if cur else u
        # Satır başına noktalama düşmesin (Japonca/Çince kuralı): sığmasa da önceki satıra ekle.
        if draw.textlength(t, font=fnt, direction='rtl' if lang == 'ar' else None) <= width or (cur and u in '。、，．！？」』）)!?.,:;：；'):
            cur = t
        else:
            if cur:
                lines.append(cur)
            cur = u
    if cur:
        lines.append(cur)
    return lines


def duration(path):
    out = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', path],
                         capture_output=True, text=True).stdout.strip()
    return float(out or 0)


def background():
    bg = Image.new('RGB', (W, H), NAVY)
    g = Image.new('L', (W, H))
    gd = ImageDraw.Draw(g)
    for y in range(H):
        gd.line([(0, y), (W, y)], fill=int(255 * y / H))
    bg = Image.composite(Image.new('RGB', (W, H), NAVY_DARK), bg, g)
    glow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([W - 420, -260, W + 260, 420], fill=EMERALD + (70,))
    glow = glow.filter(ImageFilter.GaussianBlur(120))
    bg.paste(glow, (0, 0), glow)
    return bg


PHONE_H = 900
PHONE_W = round(PHONE_H * 360 / 760)
PHONE_X = (W - PHONE_W) // 2
PHONE_Y = 120
SCALE = PHONE_H / 760  # mantıksal koordinat -> video pikseli


def phone(img):
    shot = img.convert('RGB').resize((PHONE_W, PHONE_H), Image.LANCZOS)
    mask = Image.new('L', (PHONE_W, PHONE_H), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, PHONE_W - 1, PHONE_H - 1], 34, fill=255)
    return shot, mask


INTRO_D = 2.8   # bölüm videolarında başlık kartı
OUTRO_D = 5.2   # logolu kapanış

TAGLINES = {
    'tr': 'Optik formları saniyeler içinde okuyun', 'en': 'Grade bubble sheets in seconds',
    'de': 'Antwortbögen in Sekunden auswerten', 'fr': 'Corrigez vos grilles en quelques secondes',
    'ru': 'Проверка бланков за секунды', 'az': 'Optik vərəqləri saniyələr içində oxuyun',
    'es': 'Corrige hojas de respuestas en segundos', 'it': 'Correggi i fogli risposta in pochi secondi',
    'ar': 'صحح أوراق الإجابة في ثوان', 'zh': '几秒钟批改答题卡', 'ja': 'マークシートを数秒で採点',
    'pt': 'Corrija cartões-resposta em segundos', 'hi': 'OMR शीट कुछ सेकंड में जाँचें',
    'id': 'Koreksi lembar jawaban dalam hitungan detik', 'ko': 'OMR 답안지를 몇 초 만에 채점',
}
PLATFORMS = 'iOS · Android · Windows · macOS'


def clamp(x, a=0.0, b=1.0):
    return max(a, min(b, x))


def ease_out(x):
    x = clamp(x)
    return 1 - (1 - x) ** 3


def ease_back(x):
    x = clamp(x)
    c1, c3 = 1.70158, 2.70158
    return 1 + c3 * (x - 1) ** 3 + c1 * (x - 1) ** 2


# Netice işareti (lib/ui/logo.dart ile aynı): 4×4 optik daire, dolu olanlar N
# harfini çizer, sağ üstteki daire yeşil onay işaretidir.
GRID = [[1, 0, 0, 2], [1, 1, 0, 1], [1, 0, 1, 1], [1, 0, 0, 1]]
# N harfinin yazılış sırası: sol sütun aşağı, çapraz, sağ sütun yukarı.
N_ORDER = [(0, 0), (0, 1), (0, 2), (0, 3), (1, 1), (2, 2), (3, 3), (3, 2), (3, 1)]


def draw_mark(size, t=None, ink=(255, 255, 255)):
    """İşareti RGBA olarak çizer. t verilirse daireler sırayla belirir (kapanış animasyonu)."""
    ss = 2
    S = size * ss
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cell = S / 4
    r = cell * 0.36
    full = t is None
    for y in range(4):
        for x in range(4):
            if GRID[y][x] == 0:
                a = 1 if full else ease_out(t / 0.4)
                cx, cy = cell * (x + 0.5), cell * (y + 0.5)
                rr = r * 0.92
                d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=ink + (int(255 * 0.28 * a),), width=max(2, int(cell * 0.07)))
    for i, (x, y) in enumerate(N_ORDER):
        k = 1 if full else ease_back((t - 0.25 - i * 0.08) / 0.32)
        if k <= 0:
            continue
        cx, cy = cell * (x + 0.5), cell * (y + 0.5)
        rr = r * k
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=ink + (255,))
    tc = 0.25 + len(N_ORDER) * 0.08 + 0.08
    k = 1 if full else ease_back((t - tc) / 0.35)
    if k > 0:
        cx, cy = cell * 3.5, cell * 0.5
        rr = r * k
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=EMERALD + (255,))
        p = [(cx - r * 0.45, cy + r * 0.02), (cx - r * 0.1, cy + r * 0.38), (cx + r * 0.5, cy - r * 0.32)]
        prog = 1 if full else clamp((t - tc - 0.15) / 0.3)
        w = max(2, int(r * 0.26))
        segs = [(p[0], p[1]), (p[1], p[2])]
        lens = [math.dist(*s) for s in segs]
        left = prog * sum(lens)
        for (a, b), ln in zip(segs, lens):
            if left <= 0:
                break
            f = min(1, left / ln)
            e = (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f)
            d.line([a, e], fill=(255, 255, 255, 255), width=w)
            for q in (a, e):
                d.ellipse([q[0] - w / 2, q[1] - w / 2, q[0] + w / 2, q[1] + w / 2], fill=(255, 255, 255, 255))
            left -= ln
    return img.resize((size, size), Image.LANCZOS), tc


def particles(frame, t, seed=7, n=38, start=0.0):
    import random
    rnd = random.Random(seed)
    ov = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    od = ImageDraw.Draw(ov)
    fade = ease_out((t - start) / 0.8)
    for _ in range(n):
        x0, sp, sz, off = rnd.uniform(0, W), rnd.uniform(18, 60), rnd.uniform(1.5, 4.2), rnd.uniform(0, H)
        col = EMERALD if rnd.random() < 0.6 else (255, 255, 255)
        a = rnd.uniform(0.15, 0.55)
        y = H + 40 - ((t * sp + off) % (H + 80))
        x = x0 + 14 * math.sin(t * 0.8 + off)
        od.ellipse([x - sz, y - sz, x + sz, y + sz], fill=col + (int(255 * a * fade),))
    frame.paste(ov, (0, 0), ov)


_glow_cache = {}


def glow(radius, color, alpha, cy):
    key = (radius, color, cy)
    if key not in _glow_cache:
        g = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(g).ellipse([W / 2 - radius, cy - radius, W / 2 + radius, cy + radius], fill=color + (255,))
        _glow_cache[key] = g.filter(ImageFilter.GaussianBlur(radius * 0.45))
    g = _glow_cache[key].copy()
    g.putalpha(g.getchannel('A').point(lambda v: int(v * alpha)))
    return g


_small_icons = {}


def _rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


class Video:
    def __init__(self, lang, title, section=None):
        self.lang = lang
        # Bölüm videolarında uygulamadaki bölüm simgesi ve rengi kullanılır.
        self.section = section if section in SIMGELER else None
        if self.section:
            self.icon = bolum_simgesi(self.section, 512)
            self.accent = _rgb(SIMGELER[self.section][1])
        self.rtl = lang == 'ar'
        self.title = title
        self.bg = background()
        self.title_f = font(lang, 26, bold=True)
        self.step_f = font('en', 22, bold=True)
        self.cap_f = font(lang, 30)
        self.cache = {}

    # --- Başlık kartı (bölüm videoları) ---
    def render_intro(self, seg, t):
        frame = self.bg.copy()
        particles(frame, t + 3, seed=11, n=24)
        dr = ImageDraw.Draw(frame)
        lang = self.lang

        def show(k):
            return ease_out((t - k) / 0.55)

        a = show(0.0)
        if self.section:
            # Bölüm renginde ışıma + bölüm simgesi (hafif büyüyerek gelir).
            g = glow(260, self.accent, 0.35 * a, 440)
            frame.paste(g, (0, 0), g)
            sz = int(230 * (0.82 + 0.18 * ease_back(min(1, max(0, t / 0.6)))))
            ic = self.icon.resize((sz, sz), Image.LANCZOS)
            ic.putalpha(ic.getchannel('A').point(lambda v: int(v * a)))
            bob = 6 * math.sin(max(0, t - 0.8) * 2.0)
            frame.paste(ic, (int(W / 2 - sz / 2), int(440 - sz / 2 - 20 * (1 - a) + bob)), ic)
        else:
            mark, _ = draw_mark(96)
            mark.putalpha(mark.getchannel('A').point(lambda v: int(v * a)))
            frame.paste(mark, (int(W / 2 - 48), int(450 - 20 * (1 - a))), mark)
        dr = ImageDraw.Draw(frame)
        a = show(0.18)
        lab_f = font(lang, 26, bold=True)
        dr.text((W / 2, 612 - 16 * (1 - a)), seg['label'], font=lab_f, anchor='mm',
                fill=EMERALD + (int(255 * a),), direction='rtl' if self.rtl else None)
        a = show(0.32)
        big = font(lang, 62, bold=True)
        lines = wrap(dr, seg['heading'], big, W - 120, lang)
        ov = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        od = ImageDraw.Draw(ov)
        for i, line in enumerate(lines):
            od.text((W / 2, 700 + i * 78 + 24 * (1 - a)), line, font=big, anchor='mm', fill=(255, 255, 255, int(255 * a)),
                    direction='rtl' if self.rtl else None)
        frame.paste(ov, (0, 0), ov)
        dr = ImageDraw.Draw(frame)
        yl = 700 + len(lines) * 78 - 10
        w = 140 * ease_out((t - 0.55) / 0.6)
        dr.rounded_rectangle([W / 2 - w / 2, yl, W / 2 + w / 2, yl + 5], 3, fill=EMERALD)
        a = show(0.7)
        chip = seg['chip']
        cw = dr.textlength(chip, font=self.step_f) + 36
        ov = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        od = ImageDraw.Draw(ov)
        cy = yl + 60
        od.rounded_rectangle([W / 2 - cw / 2, cy - 22, W / 2 + cw / 2, cy + 22], 22, outline=(255, 255, 255, int(110 * a)), width=2)
        od.text((W / 2, cy), chip, font=self.step_f, anchor='mm', fill=(255, 255, 255, int(230 * a)))
        frame.paste(ov, (0, 0), ov)
        return frame

    # --- Logolu kapanış ---
    def render_outro(self, seg, t):
        frame = Image.new('RGB', (W, H), NAVY_DARK)
        base = self.bg.copy()
        frame = Image.blend(base, frame, 0.55)
        mark_size = 300
        mx, my = W / 2, 470
        mark, tc = draw_mark(mark_size, t)
        # Onay işaretiyle birlikte parlayan yeşil hale.
        pulse = math.exp(-((t - tc - 0.2) ** 2) / 0.12)
        g = glow(240, EMERALD, 0.22 + 0.35 * pulse, my)
        frame.paste(g, (0, 0), g)
        particles(frame, t, seed=3, n=42, start=0.6)
        # Hafif yakınlaşma ve süzülme.
        s = 0.9 + 0.1 * ease_out(t / 0.9)
        s *= 1 + 0.012 * math.sin(max(0, t - 1.6) * 2.2)
        ms = int(mark_size * s)
        m = mark.resize((ms, ms), Image.LANCZOS)
        frame.paste(m, (int(mx - ms / 2), int(my - ms / 2)), m)
        # Onaydan yayılan halka.
        dr = ImageDraw.Draw(frame, 'RGBA')
        cell = ms / 4
        ccx, ccy = mx - ms / 2 + cell * 3.5, my - ms / 2 + cell * 0.5
        for delay in (0.0, 0.18):
            k = (t - tc - 0.1 - delay) / 0.9
            if 0 < k < 1:
                rr = cell * 0.36 + cell * 2.6 * ease_out(k)
                dr.ellipse([ccx - rr, ccy - rr, ccx + rr, ccy + rr], outline=EMERALD + (int(220 * (1 - k)),), width=4)
        # "Netice" yazısı + ışık süpürmesi.
        a = ease_out((t - 1.45) / 0.6)
        if a > 0:
            wf = font('en', 112, bold=True)
            y = 760 + 34 * (1 - a)
            ov = Image.new('RGBA', (W, H), (0, 0, 0, 0))
            ImageDraw.Draw(ov).text((W / 2, y), 'Netice', font=wf, anchor='mm', fill=(255, 255, 255, int(255 * a)))
            k = (t - 2.15) / 0.9
            if 0 < k < 1:
                mask = ov.getchannel('A')
                band = Image.new('L', (W, H), 0)
                bx = -200 + (W + 400) * ease_out(k)
                bd = ImageDraw.Draw(band)
                for i in range(60):
                    v = int(255 * (1 - abs(i - 30) / 30))
                    bd.polygon([(bx + i - 60, 600), (bx + i, 600), (bx + i - 120, 900), (bx + i - 180, 900)], fill=v)
                band = band.filter(ImageFilter.GaussianBlur(6))
                shine = Image.new('RGBA', (W, H), (190, 255, 228, 0))
                shine.putalpha(Image.composite(band, Image.new('L', (W, H), 0), mask))
                ov = Image.alpha_composite(ov, shine)
            frame.paste(ov, (0, 0), ov)
            dr = ImageDraw.Draw(frame, 'RGBA')
        w = 170 * ease_out((t - 1.9) / 0.6)
        if w > 1:
            dr.rounded_rectangle([W / 2 - w / 2, 838, W / 2 + w / 2, 843], 3, fill=EMERALD)
        a = ease_out((t - 2.05) / 0.6)
        if a > 0:
            tf = font(self.lang, 34 if self.lang not in ('zh', 'ja') else 36)
            dr.text((W / 2, 900 + 14 * (1 - a)), TAGLINES.get(self.lang, TAGLINES['en']), font=tf, anchor='mm',
                    fill=(255, 255, 255, int(235 * a)), direction='rtl' if self.rtl else None)
        a = ease_out((t - 2.5) / 0.6)
        if a > 0:
            pf = font('en', 24)
            dr.text((W / 2, 1150), PLATFORMS, font=pf, anchor='mm', fill=(255, 255, 255, int(140 * a)))
        # Son yarım saniyede hafif kararma.
        k = clamp((t - (seg['d'] - 0.45)) / 0.45)
        if k > 0:
            frame = Image.blend(frame, Image.new('RGB', (W, H), NAVY_DARK), 0.6 * k)
        return frame

    # --- Ekran sahnesi ---
    def scene_image(self, seg, t):
        frames_dir = seg['frames_dir']
        if seg['frame'] == '00_acilis':
            splash = sorted(f for f in os.listdir(frames_dir) if f.startswith('00_acilis_'))
            k = min(len(splash) - 1, int(t / (seg['d'] * 0.8) * len(splash)))
            key = splash[k]
        else:
            key = seg['frame'] + '.png'
        if key not in self.cache:
            self.cache[key] = phone(Image.open(f'{frames_dir}/{key}'))
        return self.cache[key]

    def render_scene(self, seg, t, segs, total):
        lang, rtl = self.lang, self.rtl
        d = seg['d']
        frame = self.bg.copy()
        dr = ImageDraw.Draw(frame)
        tx = 40
        sec = self.section or seg.get('section')
        if sec in SIMGELER:
            if sec not in _small_icons:
                _small_icons[sec] = bolum_simgesi(sec, 208).resize((52, 52), Image.LANCZOS)
            ic = _small_icons[sec]
            ix = W - 40 - 52 if rtl else 36
            frame.paste(ic, (ix, 42), ic)
            dr = ImageDraw.Draw(frame)
            tx = 100
        if rtl:
            dr.text((W - tx, 52), self.title, font=self.title_f, fill='white', anchor='ra', direction='rtl')
        else:
            dr.text((tx, 52), self.title, font=self.title_f, fill='white')
        n_sc = sum(1 for s in segs if s['kind'] == 'scene')
        step = f"{seg['step'] + 1}/{n_sc}"
        sw = dr.textlength(step, font=self.step_f) + 28
        sx = 40 if rtl else W - 40 - sw
        dr.rounded_rectangle([sx, 48, sx + sw, 86], 19, fill=EMERALD)
        dr.text((sx + sw / 2, 67), step, font=self.step_f, fill='white', anchor='mm')  # yeşil üstünde daima beyaz
        done = seg['t0'] + t
        dr.rounded_rectangle([40, 100, W - 40, 104], 2, fill=(255, 255, 255, 40))
        px = 40 + (W - 80) * done / total
        if rtl:
            dr.rounded_rectangle([W - 40 - (px - 40), 100, W - 40, 104], 2, fill=EMERALD)
        else:
            dr.rounded_rectangle([40, 100, px, 104], 2, fill=EMERALD)

        shot, mask = self.scene_image(seg, t)
        shadow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).rounded_rectangle([PHONE_X - 6, PHONE_Y + 14, PHONE_X + PHONE_W + 6, PHONE_Y + PHONE_H + 24], 40,
                                                  fill=(0, 0, 0, 120))
        shadow = shadow.filter(ImageFilter.GaussianBlur(18))
        frame.paste(shadow, (0, 0), shadow)
        dr = ImageDraw.Draw(frame)
        dr.rounded_rectangle([PHONE_X - 8, PHONE_Y - 8, PHONE_X + PHONE_W + 8, PHONE_Y + PHONE_H + 8], 42, fill=(20, 24, 40),
                             outline=(70, 80, 110), width=2)
        frame.paste(shot, (PHONE_X, PHONE_Y), mask)

        tg = seg['targets']
        if tg:
            ov = Image.new('RGBA', (W, H), (0, 0, 0, 0))
            od = ImageDraw.Draw(ov)
            start = 0.6
            span = max(0.1, (d - start - 0.3) / len(tg))
            for j, (x, y, w, h) in enumerate(tg):
                t0 = start + j * span
                if t < t0:
                    continue
                active = t < t0 + span or j == len(tg) - 1
                p = 6
                x0, y0 = PHONE_X + x * SCALE - p, PHONE_Y + y * SCALE - p
                x1, y1 = PHONE_X + (x + w) * SCALE + p, PHONE_Y + (y + h) * SCALE + p
                k = min(1, (t - t0) / 0.25)
                alpha = int(255 * k) if active else 90
                pulse = (math.sin((t - t0) * 2 * math.pi * 1.2) + 1) / 2
                grow = 4 + 6 * pulse if active else 0
                od.rounded_rectangle([x0 - grow, y0 - grow, x1 + grow, y1 + grow], 14, outline=EMERALD + (alpha,), width=4)
                if active:
                    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
                    cx, cy = min(x1 - 8, cx + 18), min(y1 + 2, cy + 14)
                    ph = ((t - t0) % 1.2) / 1.2
                    r = 10 + 34 * ph
                    od.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(255, 255, 255, int(220 * (1 - ph))), width=3)
                    od.ellipse([cx - 9, cy - 9, cx + 9, cy + 9], fill=(255, 255, 255, 150), outline=EMERALD + (255,), width=3)
                    if len(tg) > 1:
                        bx, by = (x0 - 4, y0 - 4) if not rtl else (x1 + 4, y0 - 4)
                        od.ellipse([bx - 15, by - 15, bx + 15, by + 15], fill=EMERALD + (255,))
                        od.text((bx, by), str(j + 1), font=self.step_f, fill=(255, 255, 255, 255), anchor='mm')
            frame.paste(ov, (0, 0), ov)

        dr = ImageDraw.Draw(frame)
        lines = wrap(dr, seg['text'], self.cap_f, W - 120, lang)
        lh = 42
        box_h = lh * len(lines) + 36
        by = H - 40 - box_h
        cap = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(cap).rounded_rectangle([36, by, W - 36, by + box_h], 24, fill=(255, 255, 255, 240))
        frame.paste(cap, (0, 0), cap)
        dr = ImageDraw.Draw(frame)
        for li, line in enumerate(lines):
            yy = by + 18 + li * lh + lh / 2
            dr.text((W / 2, yy), line, font=self.cap_f, fill=NAVY, anchor='mm', direction='rtl' if rtl else None)
        return frame

    def build(self, segs, out, stings=()):
        """segs: [{'kind': 'intro'|'scene'|'outro', ...}]. Sahne süreleri seslendirmeden."""
        tmp = tempfile.mkdtemp()
        wavs = []
        step = 0
        for i, s in enumerate(segs):
            mp3 = s.get('audio')
            lead = 0.5
            if s['kind'] == 'intro':
                s['d'] = INTRO_D
            elif s['kind'] == 'outro':
                s['d'] = OUTRO_D
            elif mp3 and os.path.exists(mp3):
                s['d'] = max(3.0, duration(mp3) + lead + 0.9)
            else:
                s['d'] = max(3.0, len(s['text']) / 14 + 1.4)
            if s['kind'] == 'scene':
                s['step'] = step
                step += 1
            wav = f'{tmp}/{i:02d}.wav'
            if s['kind'] == 'scene' and mp3 and os.path.exists(mp3):
                subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', mp3, '-af',
                                f'adelay={int(lead * 1000)}:all=1,apad', '-t', f"{s['d']:.3f}", '-ar', '44100', '-ac', '2', wav],
                               check=True)
            else:
                subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'lavfi', '-i', 'anullsrc=r=44100:cl=stereo',
                                '-t', f"{s['d']:.3f}", wav], check=True)
            wavs.append(wav)
        t0 = 0
        for s in segs:
            s['t0'] = t0
            t0 += s['d']
        total = t0
        with open(f'{tmp}/list.txt', 'w') as f:
            for w in wavs:
                f.write(f"file '{w}'\n")
        audio = f'{tmp}/audio.wav'
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', f'{tmp}/list.txt', '-c', 'copy', audio],
                       check=True)

        # Fon müziği (konuşmada kısılır, kapanışta söner) ve melodi vuruşları.
        music, sting = 'build/video/muzik.mp3', 'build/video/acilis.mp3'
        outro_t0 = next((s['t0'] for s in segs if s['kind'] == 'outro'), total)
        if os.path.exists(music):
            inputs = ['-i', audio, '-stream_loop', '-1', '-i', music]
            fade_st = max(0, outro_t0 + 1.2)
            fc = (f'[1:a]volume=0.22,afade=t=in:d=1.5,afade=t=out:st={fade_st:.2f}:d={max(0.5, total - fade_st):.2f}[m];'
                  '[0:a]asplit=2[v][sc];'
                  '[m][sc]sidechaincompress=threshold=0.02:ratio=8:attack=30:release=500[md];')
            mix_in = '[v][md]'
            n = 2
            if os.path.exists(sting):
                for j, at in enumerate(stings):
                    at = outro_t0 if at == 'outro' else at
                    inputs += ['-i', sting]
                    ms = int(at * 1000)
                    fc += f'[{2 + j}:a]volume=0.85,adelay={ms}:all=1[st{j}];'
                    mix_in += f'[st{j}]'
                    n += 1
            fc += f'{mix_in}amix=inputs={n}:duration=first:normalize=0,alimiter=limit=0.95[out]'
            mixed = f'{tmp}/mixed.wav'
            subprocess.run(['ffmpeg', '-v', 'error', '-y', *inputs, '-filter_complex', fc, '-map', '[out]',
                            '-t', f'{total:.3f}', '-ar', '44100', '-ac', '2', mixed], check=True)
            audio = mixed

        ff = subprocess.Popen(['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', str(FPS),
                               '-i', '-', '-i', audio, '-c:v', 'libx264', '-preset', 'medium', '-crf', '24', '-pix_fmt', 'yuv420p',
                               '-c:a', 'aac', '-b:a', '128k', '-shortest', '-movflags', '+faststart', out], stdin=subprocess.PIPE)

        def render(i, t):
            s = segs[i]
            if s['kind'] == 'intro':
                return self.render_intro(s, t)
            if s['kind'] == 'outro':
                return self.render_outro(s, t)
            return self.render_scene(s, t, segs, total)

        for i, s in enumerate(segs):
            n = int(s['d'] * FPS)
            prev_last = None
            xf = 9 if s['kind'] == 'outro' else 6
            for f in range(n):
                t = f / FPS
                img = render(i, t)
                if i > 0 and f < xf:
                    if prev_last is None:
                        prev_last = render(i - 1, segs[i - 1]['d'] - 1 / FPS)
                    img = Image.blend(prev_last, img, (f + 1) / (xf + 1))
                ff.stdin.write(img.convert('RGB').tobytes())
        ff.stdin.close()
        ff.wait()
        print(out, f'{total:.1f} sn')


def load_targets(frames_dir):
    p = f'{frames_dir}/hedefler.json'
    return json.load(open(p)) if os.path.exists(p) else {}


def rehber(lang):
    """Tüm uygulamayı anlatan tek video: build/video/rehber_<dil>.mp4"""
    frames_dir = f'build/video/frames/{lang}'
    targets = load_targets(frames_dir)
    script = json.load(open(f'tool/video/anlatim_{lang}.json'))
    # Sahne hangi kılavuz bölümündeyse başlıkta o bölümün simgesi görünür.
    sec_of = {}
    for sec, keys in json.load(open('tool/video/kilavuz.json'))['bolumler'].items():
        for k in keys:
            sec_of.setdefault(k, sec)
    sec_of.update({'01_tanitim': 'start', '03_siniflar': 'classes', '11_kurum': 'classes'})
    segs = [dict(kind='scene', frame=name, text=text, audio=f'build/video/audio/{lang}/{i:02d}.mp3',
                 targets=targets.get(name, []), frames_dir=frames_dir, section=sec_of.get(name))
            for i, (name, text) in enumerate(script.items())]
    segs.append(dict(kind='outro'))
    Video(lang, f'Netice · {TITLES.get(lang, TITLES["en"])}').build(segs, f'build/video/rehber_{lang}.mp4', stings=(0, 'outro'))


def kilavuz(lang, only=None):
    """Kılavuzun her bölümü için ayrı video: build/video/kilavuz_<bölüm>_<dil>.mp4"""
    frames_dir = f'build/video/frames/{lang}'
    targets = load_targets(frames_dir)
    cfg = json.load(open('tool/video/kilavuz.json'))
    base = json.load(open(f'tool/video/anlatim_{lang}.json'))
    extra = json.load(open(f'tool/video/kilavuz_anlatim_{lang}.json'))
    order = list(base.keys())
    sections = cfg['bolumler']
    for n, (sec, keys) in enumerate(sections.items()):
        if only and sec not in only:
            continue
        heading = extra['_baslik'][sec]
        label = {'tr': 'Kullanma kılavuzu', 'de': 'Benutzerhandbuch'}.get(lang, TITLES.get(lang, TITLES['en']))
        segs = [dict(kind='intro', label=label, heading=heading, chip=f'{n + 1} / {len(sections)}')]
        for k in keys:
            if k in base:
                text, audio = base[k], f'build/video/audio/{lang}/{order.index(k):02d}.mp3'
            else:
                text, audio = extra[k], f'build/video/audio/{lang}/{k}.mp3'
            frame = cfg['kareler'].get(k, k)
            segs.append(dict(kind='scene', frame=frame, text=text, audio=audio, targets=targets.get(k, targets.get(frame, [])),
                             frames_dir=frames_dir))
        segs.append(dict(kind='outro'))
        Video(lang, heading, section=sec).build(segs, f'build/video/kilavuz_{sec}_{lang}.mp4', stings=('outro',))


if __name__ == '__main__':
    os.chdir(ROOT)
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    lang = args[0] if args else 'tr'
    if '--kilavuz' in sys.argv:
        kilavuz(lang, args[1:] or None)
    else:
        rehber(lang)
