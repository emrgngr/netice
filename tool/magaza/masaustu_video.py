"""Seslendirmeli bilgisayar tanıtım videosu (1920x1080, afiş/gönderi tarzı).

python3 tool/magaza/masaustu_video.py <ekran_klasoru> <ses_klasoru> <cikti.mp4> [ayar.json]

<ekran_klasoru>: masaustu_<ekran>.png (2880x1800) ekran görüntüleri
  (flutter test tool/magaza/genis_ekranlar_test.dart --dart-define=LANG_SHOT=tr).
<ses_klasoru>: masaustu.json'daki her sahne için <kare>.mp3 ve kelime zamanları
  <kare>.json (seslendir.py), ayrıca muzik.mp3 / acilis.mp3.

Her sahnede solda afiş gibi büyük, farklı yazı tipleriyle başlık; sağda program
penceresi. Seslendirmede bir özellik söylendiği anda pencere o yere yumuşakça
yakınlaşır, yeşil halka kendini çizer, el yazısı etiket ve ok belirir.
Yakınlaşma kesirli piksellerle yapılır (titreme olmaz). Ses en sonda
yüksekliği eşitlenip (-14 LUFS) yükseltilir, müzik konuşma sırasında kısılır.
Kural (kullanıcı 2026-11-26): yeşil zemin üzerinde yazı ve simge daima beyaz.
"""
import json
import math
import os
import subprocess
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), 'brand'))
from bolum_simgeleri import simge as bolum_simgesi  # noqa: E402

W, H, FPS = 1920, 1080, 30
LEAD, TAIL = 0.55, 0.9
NAVY_TOP, NAVY, NAVY_BOTTOM = (30, 46, 96), (15, 27, 61), (7, 13, 34)
EMERALD = (16, 185, 129)
GREEN = (5, 150, 105)  # #059669: üstünde beyaz yazı için koyulaştırılmış yeşil
MINT = (167, 243, 208)
WHITE = (255, 255, 255)
SRC_W, SRC_H = 2880, 1800
# Program penceresi (ekrandaki yeri) ve üst çubuğu.
WIN = (770, 196, 1870, 196 + 688)
BAR = 40
ZMAX = 2.0

JAKARTA = os.path.join(ROOT, 'assets', 'fonts', 'PlusJakartaSans_{}.ttf')
FDIR = os.path.join(HERE, 'fontlar')


def jak(weight, size):
    return ImageFont.truetype(JAKARTA.format(weight), size)


DIL = 'tr'
PDF_FONT = os.path.join(ROOT, 'assets', 'pdf_fonts')
# Latin dışı yazı sistemleri için Google Fonts'tan (OFL) indirilen yazı tipleri.
GF = 'https://raw.githubusercontent.com/google/fonts/main/ofl/'
INDIRILEN = {
    'oswald': 'oswald/Oswald%5Bwght%5D.ttf',
    'lalezar': 'lalezar/Lalezar-Regular.ttf',
    'cairo': 'cairo/Cairo%5Bslnt,wght%5D.ttf',
    'poppins_black': 'poppins/Poppins-Black.ttf',
    'poppins_bold': 'poppins/Poppins-Bold.ttf',
    'sc': 'notosanssc/NotoSansSC%5Bwght%5D.ttf',
    'jp': 'notosansjp/NotoSansJP%5Bwght%5D.ttf',
    'kr': 'notosanskr/NotoSansKR%5Bwght%5D.ttf',
}


def indir(ad):
    import urllib.request
    kat = os.path.join(os.path.expanduser('~'), '.cache', 'netice-fontlar')
    os.makedirs(kat, exist_ok=True)
    yol = os.path.join(kat, os.path.basename(INDIRILEN[ad]).replace('%5B', '[').replace('%5D', ']'))
    if not os.path.exists(yol):
        urllib.request.urlretrieve(GF + INDIRILEN[ad], yol)
    return yol


def _yt(yol, size, agirlik=None):
    f = ImageFont.truetype(yol, size)
    if agirlik:
        try:
            axes = f.get_variation_axes()
            f.set_variation_by_axes([agirlik if a.get('name', b'') in (b'Weight', 'Weight') else a['default'] for a in axes])
        except Exception:  # noqa: BLE001
            try:
                f.set_variation_by_name('Bold')
            except Exception:  # noqa: BLE001
                pass
    return f


def rol(r, size):
    """Dile göre yazı tipi. r: baslik (afiş), ust (bölüm etiketi), vurgu (italik vurgu), el (el yazısı), govde."""
    cjk = {'zh': 'sc', 'ja': 'jp', 'ko': 'kr'}.get(DIL)
    if cjk:
        return _yt(indir(cjk), size, 900 if r == 'baslik' else 700)
    if DIL == 'ar':
        return ImageFont.truetype(indir('lalezar'), size) if r in ('baslik', 'vurgu') else _yt(indir('cairo'), size, 800)
    if DIL == 'hi':
        return ImageFont.truetype(indir('poppins_black' if r == 'baslik' else 'poppins_bold'), size)
    if DIL == 'ru':
        if r in ('baslik', 'ust'):
            return _yt(indir('oswald'), size, 700)
        if r == 'govde':
            return ImageFont.truetype(os.path.join(PDF_FONT, 'NotoSans-Bold.ttf'), size)
        return _yt(os.path.join(FDIR, 'Caveat-Variable.ttf'), size, 700)
    if r == 'baslik' or (r == 'ust' and DIL == 'az'):
        return ImageFont.truetype(os.path.join(FDIR, 'Anton-Regular.ttf'), size)
    if r == 'ust':
        return ImageFont.truetype(os.path.join(FDIR, 'BebasNeue-Regular.ttf'), size)
    if r == 'vurgu' and DIL != 'az':
        return ImageFont.truetype(os.path.join(FDIR, 'DMSerifDisplay-Italic.ttf'), size)
    if r == 'govde':
        return jak('700Bold', size)
    return _yt(os.path.join(FDIR, 'Caveat-Variable.ttf'), size, 700)


def anton(size):
    return rol('baslik', size)


def bebas(size):
    return rol('ust', size)


def serif(size):
    return rol('vurgu', size)


def el(size):
    return rol('el', size)


def ease(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def ease_out(t):
    t = max(0.0, min(1.0, t))
    return 1 - (1 - t) ** 3


def back_out(t):
    """Hafifçe taşıp yerine oturan açılış (etiketler için)."""
    t = max(0.0, min(1.0, t))
    s = 1.9
    return 1 + (s + 1) * (t - 1) ** 3 + s * (t - 1) ** 2


def kucult(s):
    return s.replace('İ', 'i').replace('I', 'ı').lower()


def duration(path):
    out = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', path],
                         capture_output=True, text=True, check=True).stdout
    return float(out.strip())


def with_alpha(im, a):
    if a >= 1:
        return im
    im = im.copy()
    im.putalpha(im.getchannel('A').point(lambda v: int(v * max(0.0, a))))
    return im


# ---------------------------------------------------------------- arka plan

def background():
    bg = Image.new('RGB', (W, H))
    top = Image.linear_gradient('L').resize((W, H))
    a = Image.new('RGB', (W, H), NAVY_TOP)
    b = Image.new('RGB', (W, H), NAVY_BOTTOM)
    bg = Image.composite(b, a, top)
    glow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(glow)
    d.ellipse((W - 700, -500, W + 500, 500), fill=EMERALD + (70,))
    d.ellipse((-500, H - 300, 500, H + 500), fill=EMERALD + (40,))
    glow = glow.filter(ImageFilter.GaussianBlur(160))
    bg = bg.convert('RGBA')
    bg.alpha_composite(glow)
    dots = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(dots)
    for y in range(40, H, 36):
        for x in range(40, 700, 36):
            d.ellipse((x - 1.6, y - 1.6, x + 1.6, y + 1.6), fill=(255, 255, 255, 14))
    bg.alpha_composite(dots)
    return bg


def outline_number(text):
    """Arkada büyük, içi boş numara (afiş havası)."""
    f = ImageFont.truetype(os.path.join(FDIR, 'Anton-Regular.ttf'), 560)
    im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.text((-30, H - 610), text, font=f, fill=(0, 0, 0, 0), stroke_width=3, stroke_fill=EMERALD + (46,))
    return im


def brand_corner():
    """Sol altta küçük logo ve site adresi (her sahnede)."""
    im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ic = Image.open(os.path.join(ROOT, 'assets', 'icon', 'netice_icon_rounded_1024.png')).convert('RGBA').resize((52, 52), Image.LANCZOS)
    im.alpha_composite(ic, (80, H - 92))
    d = ImageDraw.Draw(im)
    d.text((146, H - 88), 'Netice', font=jak('800ExtraBold', 30), fill=WHITE)
    d.text((146, H - 52), 'www.neticeoptik.com', font=jak('500Medium', 20), fill=(203, 213, 225))
    return im


# ---------------------------------------------------------------- afiş yazısı

class Headline:
    """Satır satır yükselen büyük başlık; vurgu satırı yeşil blok üstünde beyaz italik."""

    def __init__(self, lines, vurgu, x, y, width, start=0.3):
        self.items = []
        probe = ImageDraw.Draw(Image.new('RGB', (10, 10)))
        cy = y
        for i, text in enumerate(lines):
            if not text:
                continue
            hi = i == vurgu
            size = 150
            while True:
                f = serif(int(size * 0.78)) if hi else anton(size)
                tw = probe.textlength(text, font=f)
                if tw <= width - (60 if hi else 0) or size <= 60:
                    break
                size -= 4
            bb = probe.textbbox((0, 0), text, font=f)
            th = bb[3] - bb[1]
            pad = 22 if hi else 0
            im = Image.new('RGBA', (int(tw) + 2 * pad + 8, th + 2 * pad + 12), (0, 0, 0, 0))
            ImageDraw.Draw(im).text((pad, pad - bb[1] + 4), text, font=f, fill=WHITE)
            self.items.append(dict(im=im, x=x, y=cy, hi=hi, t0=start + 0.13 * len(self.items)))
            cy += im.height + (18 if hi else 8)
        self.bottom = cy

    def draw(self, frame, t, out_a=1.0):
        for it in self.items:
            p = ease_out((t - it['t0']) / 0.55)
            if p <= 0:
                continue
            im = it['im']
            if it['hi']:
                # Yeşil blok soldan sağa açılır, yazı ardından belirir.
                bw = int(im.width * ease_out((t - it['t0']) / 0.45))
                if bw > 2:
                    blk = Image.new('RGBA', (bw, im.height), (0, 0, 0, 0))
                    ImageDraw.Draw(blk).rounded_rectangle((0, 0, bw - 1, im.height - 1), 14, fill=GREEN + (int(255 * out_a),))
                    frame.alpha_composite(blk, (it['x'], it['y']))
                ta = ease((t - it['t0'] - 0.25) / 0.3) * out_a
                if ta > 0:
                    frame.alpha_composite(with_alpha(im, ta), (it['x'], it['y']))
            else:
                dy = int(46 * (1 - p))
                frame.alpha_composite(with_alpha(im, p * out_a), (it['x'], it['y'] + dy))


def kicker(text, icon_key):
    """Bölüm etiketi: simge + aralıklı büyük harf."""
    f = bebas(50)
    probe = ImageDraw.Draw(Image.new('RGB', (10, 10)))
    harf_harf = DIL not in ('ar', 'hi', 'zh', 'ja', 'ko')
    tw = sum(probe.textlength(ch, font=f) + 4 for ch in text) if harf_harf else probe.textlength(text, font=f)
    isz = 86 if icon_key else 0
    im = Image.new('RGBA', (int(tw) + isz + 40, max(isz, 60) + 10), (0, 0, 0, 0))
    if icon_key:
        im.alpha_composite(bolum_simgesi(icon_key, isz * 2).resize((isz, isz), Image.LANCZOS), (0, 0))
    d = ImageDraw.Draw(im)
    x = isz + (20 if isz else 0)
    y = (im.height - 50) // 2 - 2
    if not harf_harf:
        d.text((x, y), text, font=f, fill=MINT)
        return im
    for ch in text:
        d.text((x, y), ch, font=f, fill=MINT)
        x += probe.textlength(ch, font=f) + 4
    return im


def chip(text, icon_key=None, size=34):
    f = rol('govde', size)
    probe = ImageDraw.Draw(Image.new('RGB', (10, 10)))
    tw = probe.textlength(text, font=f)
    h = size + 34
    isz = h - 14 if icon_key else 0
    im = Image.new('RGBA', (int(tw) + 52 + (isz + 10 if isz else 0), h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, im.width - 1, h - 1), h // 2, fill=GREEN + (255,))
    x = 26
    if isz:
        ic = bolum_simgesi(icon_key, isz * 2).resize((isz, isz), Image.LANCZOS)
        im.alpha_composite(ic, (7, 7))
        x = isz + 18
    d.text((x, (h - size) / 2 - size * 0.12), text, font=f, fill=WHITE)
    return im


def pop(frame, im, cx, cy, t, t0, dur=0.35, rot=0.0, alpha=1.0):
    p = (t - t0) / dur
    if p <= 0 or alpha <= 0:
        return
    s = max(0.05, back_out(p))
    sp = im
    if abs(s - 1) > 0.01:
        sp = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.BICUBIC)
    if rot:
        sp = sp.rotate(rot, resample=Image.BICUBIC, expand=True)
    sp = with_alpha(sp, min(1.0, p * 2.5) * alpha)
    frame.alpha_composite(sp, (int(cx - sp.width / 2), int(cy - sp.height / 2)))


# ---------------------------------------------------------------- pencere ve kamera

def window_chrome():
    x0, y0, x1, y1 = WIN
    im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    sh = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((x0 + 10, y0 - BAR + 30, x1 + 10, y1 + 40), 26, fill=(0, 0, 0, 150))
    im.alpha_composite(sh.filter(ImageFilter.GaussianBlur(34)))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((x0 - 2, y0 - BAR - 2, x1 + 2, y1 + 2), 20, fill=(226, 232, 240, 255))
    d.rectangle((x0, y0 - 8, x1, y0), fill=(226, 232, 240, 255))
    for i, c in enumerate([(255, 95, 87), (254, 188, 46), (40, 200, 64)]):
        cx = x0 + 26 + i * 26
        d.ellipse((cx - 8, y0 - BAR / 2 - 8, cx + 8, y0 - BAR / 2 + 8), fill=c + (255,))
    f = jak('600SemiBold', 18)
    t = 'Netice'
    d.text(((x0 + x1) / 2 - d.textlength(t, font=f) / 2, y0 - BAR / 2 - 12), t, font=f, fill=(71, 85, 105))
    return im


WIN_MASK = None


def win_mask():
    global WIN_MASK
    if WIN_MASK is None:
        ww, wh = WIN[2] - WIN[0], WIN[3] - WIN[1]
        m = Image.new('L', (ww, wh), 0)
        d = ImageDraw.Draw(m)
        d.rounded_rectangle((0, -30, ww - 1, wh - 1), 18, fill=255)
        WIN_MASK = m
    return WIN_MASK


class Camera:
    """Ekran görüntüsünde yumuşak kaydırma/yakınlaşma (kaynak koordinatlarında)."""

    def __init__(self):
        self.keys = [(0.0, SRC_W / 2, SRC_H / 2, 1.0)]

    def move(self, t, box, dur=0.8):
        bw, bh = box[2] - box[0], box[3] - box[1]
        z = min(ZMAX, SRC_W / (bw * 1.45 + 300), SRC_H / (bh * 1.6 + 260))
        z = max(1.0, z)
        t = max(t, self.keys[-1][0] + 0.05)
        self.keys.append((t, (box[0] + box[2]) / 2, (box[1] + box[3]) / 2, z, dur))

    def state(self, t):
        cx, cy, z = self.keys[0][1:4]
        for k in self.keys[1:]:
            t0, tx, ty, tz, dur = k
            if t <= t0:
                break
            p = ease((t - t0) / dur)
            lz = math.log(z) + (math.log(tz) - math.log(z)) * p
            cx, cy, z = cx + (tx - cx) * p, cy + (ty - cy) * p, math.exp(lz)
        vw, vh = SRC_W / z, SRC_H / z
        x0 = min(max(cx - vw / 2, 0), SRC_W - vw)
        y0 = min(max(cy - vh / 2, 0), SRC_H - vh)
        return x0, y0, vw, vh

    def to_screen(self, st, x, y):
        x0, y0, vw, vh = st
        return WIN[0] + (x - x0) / vw * (WIN[2] - WIN[0]), WIN[1] + (y - y0) / vh * (WIN[3] - WIN[1])


def render_window(frame, src, st, spot=None, spot_a=0.0):
    x0, y0, vw, vh = st
    ww, wh = WIN[2] - WIN[0], WIN[3] - WIN[1]
    sx = src.width / SRC_W
    view = src.resize((ww, wh), Image.BICUBIC, box=(x0 * sx, y0 * sx, (x0 + vw) * sx, (y0 + vh) * sx))
    view = view.convert('RGBA')
    if spot and spot_a > 0:
        ov = Image.new('RGBA', (ww, wh), (6, 12, 32, int(125 * spot_a)))
        r = (spot[0] - WIN[0], spot[1] - WIN[1], spot[2] - WIN[0], spot[3] - WIN[1])
        ImageDraw.Draw(ov).rounded_rectangle(r, 16, fill=(0, 0, 0, 0))
        view.alpha_composite(ov)
    frame.paste(view, (WIN[0], WIN[1]), win_mask())


# ---------------------------------------------------------------- işaretler

def rrect_points(box, r, n=28):
    x0, y0, x1, y1 = box
    r = min(r, (x1 - x0) / 2, (y1 - y0) / 2)
    pts = []
    # Üst ortadan başlayıp saat yönünde.
    corners = [((x1 - r, y0 + r), -90), ((x1 - r, y1 - r), 0), ((x0 + r, y1 - r), 90), ((x0 + r, y0 + r), 180)]
    pts.append(((x0 + x1) / 2, y0))
    for (cx, cy), a0 in corners:
        for i in range(n + 1):
            a = math.radians(a0 + 90 * i / n)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    pts.append(((x0 + x1) / 2, y0))
    return pts


def partial(pts, frac):
    if frac >= 1:
        return pts
    seg = [math.dist(pts[i], pts[i + 1]) for i in range(len(pts) - 1)]
    goal = sum(seg) * max(0.0, frac)
    out = [pts[0]]
    for i, s in enumerate(seg):
        if goal <= s:
            k = goal / s if s else 0
            out.append((pts[i][0] + (pts[i + 1][0] - pts[i][0]) * k, pts[i][1] + (pts[i + 1][1] - pts[i][1]) * k))
            break
        goal -= s
        out.append(pts[i + 1])
    return out


def bezier(p0, p1, p2, n=40):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]) for t in (i / n for i in range(n + 1))]


def label_image(text):
    f = el(58)
    probe = ImageDraw.Draw(Image.new('RGB', (10, 10)))
    bb = probe.textbbox((0, 0), text, font=f)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    im = Image.new('RGBA', (tw + 64, th + 40), (0, 0, 0, 0))
    sh = Image.new('RGBA', im.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((6, 10, im.width - 6, im.height - 2), 18, fill=(0, 0, 0, 110))
    im.alpha_composite(sh.filter(ImageFilter.GaussianBlur(5)))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((2, 2, im.width - 6, im.height - 8), 18, fill=GREEN + (255,), outline=WHITE + (255,), width=3)
    d.text((30 - bb[0], (im.height - 8 - th) / 2 - bb[1]), text, font=f, fill=WHITE)
    return im


# Halka ile hedef arasındaki boşluk (ekran pikseli): düğme/kart çerçeveye tam girsin.
PAD = 24


class Callout:
    def __init__(self, spec, t_on, t_off):
        self.box = spec['hedef']
        self.t_on, self.t_off = t_on, t_off
        self.label = label_image(spec['etiket'])
        self.lpos = None

    def place(self, r):
        """Etiketi hedefin üstüne/altına/soluna, ekrandan taşmadan koyar."""
        lw, lh = self.label.width, self.label.height
        cx = (r[0] + r[2]) / 2
        cands = [
            (min(max(cx + 140, lw / 2 + 30), W - lw / 2 - 30), r[1] - lh / 2 - 90),
            (min(max(cx + 140, lw / 2 + 30), W - lw / 2 - 30), r[3] + lh / 2 + 90),
            (r[0] - lw / 2 - 110, (r[1] + r[3]) / 2 - 60),
            (min(max(cx, lw / 2 + 30), W - lw / 2 - 30), (r[1] + r[3]) / 2),
        ]
        for x, y in cands:
            if lh / 2 + 24 <= y <= H - lh / 2 - 110 and lw / 2 + 20 <= x <= W - lw / 2 - 20:
                return x, y
        return cands[-1]

    def draw(self, frame, t, cam, st, final_st):
        if t < self.t_on - 0.1:
            return
        fade = 1 - ease((t - self.t_off) / 0.3)
        if fade <= 0:
            return
        a = cam.to_screen(st, self.box[0], self.box[1])
        b = cam.to_screen(st, self.box[2], self.box[3])
        pad = PAD
        r = (max(WIN[0] + 4, a[0] - pad), max(WIN[1] + 4, a[1] - pad), min(WIN[2] - 4, b[0] + pad), min(WIN[3] - 4, b[1] + pad))
        if r[2] - r[0] < 12 or r[3] - r[1] < 12:  # hedef henüz pencerede görünmüyor
            return
        if self.lpos is None:
            fa = cam.to_screen(final_st, self.box[0], self.box[1])
            fb = cam.to_screen(final_st, self.box[2], self.box[3])
            self.lpos = self.place((fa[0] - pad, fa[1] - pad, fb[0] + pad, fb[1] + pad))
        ov = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(ov)
        # Halka kendini çizer, sonra nabız gibi dışa açılır.
        ring = partial(rrect_points(r, 18), ease((t - self.t_on) / 0.5))
        if len(ring) > 1:
            d.line(ring, fill=WHITE + (int(200 * fade),), width=11, joint='curve')
            d.line(ring, fill=EMERALD + (int(255 * fade),), width=6, joint='curve')
        if t > self.t_on + 0.5:
            ph = ((t - self.t_on - 0.5) % 1.4) / 1.4
            g = 6 + 20 * ph
            d.rounded_rectangle((r[0] - g, r[1] - g, r[2] + g, r[3] + g), 22, outline=EMERALD + (int(150 * (1 - ph) * fade),), width=3)
        # Ok: etiketten halkaya, el çizimi gibi kavisli.
        lx, ly = self.lpos
        tx = min(max(lx, r[0] + 30), r[2] - 30)
        ty = r[1] - 4 if ly < r[1] else (r[3] + 4 if ly > r[3] else (r[1] + r[3]) / 2)
        if ly > r[1] and ly < r[3]:
            tx = r[0] - 4
        sx = lx
        sy = ly + (self.label.height / 2 - 6 if ly < ty else -self.label.height / 2 + 6)
        if r[1] <= ly <= r[3]:
            sx, sy = lx + self.label.width / 2 - 6, ly
        mx, my = (sx + tx) / 2 + (ty - sy) * 0.35, (sy + ty) / 2 - (tx - sx) * 0.35
        curve = bezier((sx, sy), (mx, my), (tx, ty))
        ap = ease((t - self.t_on - 0.35) / 0.4)
        if ap > 0 and math.dist((sx, sy), (tx, ty)) > 30:
            seg = partial(curve, ap)
            d.line(seg, fill=WHITE + (int(230 * fade),), width=11, joint='curve')
            d.line(seg, fill=GREEN + (int(255 * fade),), width=6, joint='curve')
            if ap >= 0.98:
                ex, ey = curve[-1]
                px, py = curve[-4]
                ang = math.atan2(ey - py, ex - px)
                head = [(ex, ey), (ex - 30 * math.cos(ang - 0.45), ey - 30 * math.sin(ang - 0.45)),
                        (ex - 30 * math.cos(ang + 0.45), ey - 30 * math.sin(ang + 0.45))]
                d.polygon(head, fill=GREEN + (int(255 * fade),), outline=WHITE + (int(230 * fade),), width=3)
        frame.alpha_composite(ov)
        pop(frame, self.label, lx, ly, t, self.t_on + 0.15, rot=3, alpha=fade)


# ---------------------------------------------------------------- sahneler

def word_time(sc, audio, word, voice_dur, oran=None):
    """Seslendirmede kelimenin söylendiği an (sn). Kelime zamanı yoksa metindeki yerine göre."""
    text = sc['metin']
    zp = os.path.join(audio, sc['kare'] + '.json')
    if os.path.exists(zp):
        al = json.load(open(zp, encoding='utf-8'))
        chars = al.get('characters') or []
        starts = al.get('character_start_times_seconds') or []
        s = kucult(''.join(chars))
        i = s.find(kucult(word))
        if i >= 0 and i < len(starts):
            return starts[i]
    i = kucult(text).find(kucult(word))
    if i < 0 and oran is not None:
        return voice_dur * oran
    return voice_dur * max(0, i) / max(1, len(text))


class Scene:
    def __init__(self, sc, idx, total_screens, shots, audio, dur, vdur):
        self.sc, self.dur = sc, dur
        self.bg = BG.copy()
        kind = sc['kare']
        self.kind = kind
        num = None
        if kind not in ('giris', 'kapanis'):
            num = f'{idx:02d}'
            self.bg.alpha_composite(outline_number(num))
            self.src = Image.open(os.path.join(shots, f'masaustu_{kind}.png')).convert('RGB')
            if self.src.size != (SRC_W, SRC_H):
                self.src = self.src.resize((SRC_W, SRC_H), Image.LANCZOS)
            self.src = self.src.resize((2200, 1375), Image.LANCZOS)
        elif kind == 'giris':
            self.src = Image.open(os.path.join(shots, 'masaustu_ana_sayfa.png')).convert('RGB').resize((2200, 1375), Image.LANCZOS)
        else:
            self.src = None
        self.bg.alpha_composite(BRAND)
        if self.src is not None:
            self.bg.alpha_composite(CHROME)
        self.cam = Camera()
        self.callouts = []
        specs = [dict(s) for s in sc.get('isaret', [])]
        if DIL == 'ar':  # Arapça arayüz sağdan sola: hedefler aynalanır
            for s in specs:
                x0, y0, x1, y1 = s['hedef']
                s['hedef'] = [SRC_W - x1, y0, SRC_W - x0, y1]
        times = [LEAD + word_time(sc, audio, s['kelime'], vdur, s.get('oran')) for s in specs]
        # Her işaret en az ~1,6 sn ekranda kalsın (kelimeler çok yakınsa sonrakini kaydır).
        for i in range(1, len(times)):
            times[i] = max(times[i], times[i - 1] + 1.9)
        for i, s in enumerate(specs):
            t_on = times[i]
            t_off = (times[i + 1] - 0.85) if i + 1 < len(specs) else dur - 0.35
            self.cam.move(t_on - 0.55, s['hedef'])
            self.callouts.append(Callout(s, t_on + 0.2, t_off))
        self.final_states = [self.cam.state(c.t_on + 0.65) for c in self.callouts]
        if kind == 'kapanis':
            self.head = Headline(sc['baslik'], sc.get('vurgu', -1), 0, 0, 1500)
            # Ortalamak için satırları yeniden yerleştir.
            y = 330
            for it in self.head.items:
                it['x'] = (W - it['im'].width) // 2
                it['y'] = y
                y += it['im'].height + 10
            self.head.bottom = y
        else:
            top = 190 if kind != 'giris' else 230
            self.kick = kicker(sc.get('ust', 'NETİCE'), sc.get('bolum'))
            self.head = Headline(sc['baslik'], sc.get('vurgu', -1), 84, top + self.kick.height + 34, 640)
        self.chips = []
        for i, lab in enumerate(sc.get('etiketler', [])):
            key = sc.get('etiket_kelime', sc.get('etiketler'))[i]
            ik = {'giris': ['scan', 'library', 'report']}.get(kind, [None, None, None])[i]
            oran = (sc.get('etiket_oran') or [None] * 3)[i]
            self.chips.append((chip(lab, ik), LEAD + word_time(sc, audio, key, vdur, oran)))

    def frame(self, t):
        f = self.bg.copy()
        out_a = 1.0
        if self.kind == 'kapanis':
            ic = ICON_BIG
            pop(f, ic, W // 2, 190, t, 0.15, dur=0.5)
            self.head.draw(f, t)
            x = W // 2
            tot = sum(c.width for c, _ in self.chips) + 30 * (len(self.chips) - 1)
            cx = x - tot / 2
            for c, t0 in self.chips:
                pop(f, c, cx + c.width / 2, self.head.bottom + 70, t, t0)
                cx += c.width + 30
            if t > 1.2:
                pop(f, URL, W // 2, self.head.bottom + 200, t, max(1.2, self.chips[-1][1] + 0.4 if self.chips else 1.2), dur=0.4)
            pop(f, PLATFORM, W // 2, H - 150, t, 0.9, dur=0.4)
            return f
        # Pencere: sağdan kayarak gelir (giriş sahnesinde) ya da sabit.
        st = self.cam.state(t)
        if self.src is not None:
            active = None
            spot_a = 0.0
            for c in self.callouts:
                if c.t_on - 0.1 <= t < c.t_off + 0.3:
                    active = c
                    spot_a = ease((t - c.t_on) / 0.35) * (1 - ease((t - c.t_off) / 0.3))
            spot = None
            if active:
                a = self.cam.to_screen(st, active.box[0], active.box[1])
                b = self.cam.to_screen(st, active.box[2], active.box[3])
                spot = (a[0] - PAD, a[1] - PAD, b[0] + PAD, b[1] + PAD)
            render_window(f, self.src, st, spot, spot_a)
        # Sol sütun: afiş yazısı.
        kp = ease_out((t - 0.1) / 0.45)
        if kp > 0:
            f.alpha_composite(with_alpha(self.kick, kp), (int(84 - 60 * (1 - kp)), 190 if self.kind != 'giris' else 230))
        self.head.draw(f, t, out_a)
        y = self.head.bottom + 30
        for c, t0 in self.chips:
            pop(f, c, 84 + c.width / 2, y + c.height / 2, t, t0)
            y += c.height + 18
        for c, fs in zip(self.callouts, self.final_states):
            c.draw(f, t, self.cam, st, fs)
        return f


def wipe(prev, cur, p):
    """Afiş geçişi: çapraz yeşil şerit soldan sağa geçer, arkasında yeni sahne."""
    if p >= 1:
        return cur
    e = ease(p)
    edge = -400 + (W + 800) * e
    m = Image.new('L', (W, H), 0)
    ImageDraw.Draw(m).polygon([(edge, 0), (W + 400, 0), (W + 400, H), (edge - 300, H)], fill=255)
    out = Image.composite(prev, cur, m)
    band = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(band)
    d.polygon([(edge - 70, 0), (edge, 0), (edge - 300, H), (edge - 370, H)], fill=GREEN + (255,))
    d.polygon([(edge - 100, 0), (edge - 82, 0), (edge - 382, H), (edge - 400, H)], fill=MINT + (255,))
    out = out.convert('RGBA')
    out.alpha_composite(band)
    return out.convert('RGB')


def main():
    shots, audio, out = sys.argv[1:4]
    ayar = sys.argv[4] if len(sys.argv) > 4 else os.path.join(HERE, 'masaustu.json')
    cfg = json.load(open(ayar, encoding='utf-8'))
    global DIL
    DIL = cfg.get('dil', 'tr')
    if os.environ.get('SAHNELER'):  # deneme için yalnız bazı sahneler
        secili = os.environ['SAHNELER'].split(',')
        cfg['sahneler'] = [s for s in cfg['sahneler'] if s['kare'] in secili]
    global BG, BRAND, CHROME, ICON_BIG, URL, PLATFORM
    BG = background()
    BRAND = brand_corner()
    CHROME = window_chrome()
    ICON_BIG = Image.open(os.path.join(ROOT, 'assets', 'icon', 'netice_icon_rounded_1024.png')).convert('RGBA').resize((200, 200), Image.LANCZOS)
    u = Image.new('RGBA', (620, 84), (0, 0, 0, 0))
    ud = ImageDraw.Draw(u)
    ud.rounded_rectangle((0, 0, 619, 83), 42, fill=(255, 255, 255, 26), outline=MINT + (255,), width=3)
    uf = jak('700Bold', 40)
    ud.text((310 - ud.textlength('www.neticeoptik.com', font=uf) / 2, 15), 'www.neticeoptik.com', font=uf, fill=WHITE)
    URL = u
    pf = jak('700Bold', 32)
    pt = 'Windows · Mac · iPhone · iPad · Android'
    PLATFORM = Image.new('RGBA', (int(ImageDraw.Draw(u).textlength(pt, font=pf)) + 10, 50), (0, 0, 0, 0))
    ImageDraw.Draw(PLATFORM).text((5, 2), pt, font=pf, fill=(203, 213, 225))

    tmp = os.path.join(os.path.dirname(os.path.abspath(out)), '_masaustu_ses')
    os.makedirs(tmp, exist_ok=True)
    plan = []
    n = len(cfg['sahneler'])
    for i, sc in enumerate(cfg['sahneler']):
        src = os.path.join(audio, sc['kare'] + '.mp3')
        voice = os.path.join(tmp, f'{i:02d}.wav')
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', src, '-ar', '44100', '-ac', '2', voice], check=True)
        vd = duration(voice)
        d = LEAD + vd + TAIL
        if i == 0:
            d = max(d, 5.0)
        if i == n - 1:
            d += 1.8
        plan.append((sc, voice, d, vd))
    total = sum(p[2] for p in plan)
    silent = out + '.video.mp4'
    enc = subprocess.Popen(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}',
                            '-r', str(FPS), '-i', '-', '-c:v', 'libx264', '-preset', 'medium', '-crf', '18',
                            '-pix_fmt', 'yuv420p', silent], stdin=subprocess.PIPE)
    last = None
    for i, (sc, _, d, vd) in enumerate(plan):
        scene = Scene(sc, i, n - 2, shots, audio, d, vd)
        frames = int(round(d * FPS))
        for k in range(frames):
            fr = scene.frame(k / FPS).convert('RGB')
            if last is not None and k < 0.55 * FPS:
                fr = wipe(last, fr, k / (0.55 * FPS))
            enc.stdin.write(fr.tobytes())
            if k == frames - 1:
                last = fr
        print(f'sahne {sc["kare"]}: {d:.1f} sn', flush=True)
    enc.stdin.close()
    enc.wait()

    # Ses: anlatım sahne başına göre yerleşir; müzik konuşurken kısılır;
    # en sonda yükseklik -14 LUFS'e eşitlenir (önceki video çok kısıktı).
    inputs, filt, labels, t = [], [], [], 0.0
    for i, (_, voice, d, _) in enumerate(plan):
        inputs += ['-i', voice]
        ms = int((t + LEAD) * 1000)
        filt.append(f'[{i + 1}:a]adelay={ms}|{ms},volume=1.8[v{i}]')
        labels.append(f'[v{i}]')
        t += d
    filt.append(f'{"".join(labels)}amix=inputs={len(labels)}:duration=longest:normalize=0,apad=whole_dur={total:.2f}[vox]')
    filt.append('[vox]asplit=2[vo][vsc]')
    k = len(plan) + 1
    mix = ['[vo]']
    music = os.path.join(audio, 'muzik.mp3')
    intro = os.path.join(audio, 'acilis.mp3')
    if os.path.exists(music):
        inputs += ['-stream_loop', '-1', '-i', music]
        filt.append(f'[{k}:a]volume=0.32,afade=t=in:d=1.2,afade=t=out:st={total - 2.5:.2f}:d=2.5[m0]')
        filt.append('[m0][vsc]sidechaincompress=threshold=0.04:ratio=5:attack=30:release=450[m]')
        mix.append('[m]')
        k += 1
    else:
        filt.append('[vsc]anullsink')
    if os.path.exists(intro):
        inputs += ['-i', intro]
        filt.append(f'[{k}:a]volume=0.6[i]')
        mix.append('[i]')
    filt.append(f'{"".join(mix)}amix=inputs={len(mix)}:duration=first:normalize=0,atrim=0:{total:.2f},'
                f'loudnorm=I=-14:TP=-1.2:LRA=11,aresample=44100[a]')
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', silent] + inputs +
                   ['-filter_complex', ';'.join(filt), '-map', '0:v', '-map', '[a]', '-c:v', 'copy',
                    '-c:a', 'aac', '-b:a', '192k', '-t', f'{total:.2f}', '-movflags', '+faststart', out], check=True)
    os.remove(silent)
    print(f'{out} ({total:.1f} sn)')


if __name__ == '__main__':
    main()
