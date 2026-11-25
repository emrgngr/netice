"""App Store, Google Play tableti, Mac App Store, Microsoft Store ve
web/sosyal medya için başlıklı tanıtım görselleri.

Önce ekranları çekin (her dil için):
  flutter test tool/magaza/genis_ekranlar_test.dart --dart-define=LANG_SHOT=tr
Sonra:
  python3 tool/magaza/paketler.py <cikti_klasoru> [tr en]

Üretilenler (<dil> = tr, en):
  app-store/<dil>/iphone-6.9/01..08.png     1320x2868
  app-store/<dil>/iphone-6.5/01..08.png     1284x2778
  app-store/<dil>/ipad-13/01..08.png        2064x2752
  app-store/simge_1024.png                  saydamlıksız uygulama simgesi
  google-play/tablet/<dil>/01..08.png       1600x2560
  masaustu/mac-app-store/<dil>/01..08.png   2880x1800
  masaustu/microsoft-store/<dil>/01..08.png 2560x1440
  masaustu/microsoft-store/logolar/*.png    kutu (1:1), poster (2:3), kahraman (16:9)
  masaustu/web-ve-sosyal/<dil>/*.png        site afişi, kare gönderi, hikâye
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gorseller import EMERALD, MINT, ROOT, font, rounded, shadow  # noqa: E402
from gorseller import background as _background  # noqa: E402

_BG = {}


def background(w, h):
    """Aynı boyuttaki arka planı bir kez çizer (piksel döngüsü yavaş)."""
    if (w, h) not in _BG:
        _BG[(w, h)] = _background(w, h)
    return _BG[(w, h)].copy()

SHOTS = os.path.join(ROOT, 'build', 'screenshots')
ICON = os.path.join(ROOT, 'assets', 'icon', 'netice_icon_rounded_1024.png')
ICON_FLAT = os.path.join(ROOT, 'assets', 'icon', 'netice_icon_1024.png')
WHITE = (255, 255, 255)
SOFT = (203, 213, 225)

SCREENS = ['ana_sayfa', 'sonuclar', 'analiz', 'kutuphane', 'kitapcik', 'veli', 'istatistik', 'donem']

TEXT = {
    'tr': {
        'ana_sayfa': ('Kâğıttan sonuca,\nsaniyeler içinde', 'Kayıt gerekmez · Verileriniz cihazınızda'),
        'sonuclar': ('Sonuçlar\nanında hazır', 'Puan, net, sıralama ve puan dağılımı'),
        'analiz': ('Soru ve konu\nanalizi', 'Güvenilirlik, madde güçlüğü, otomatik yorum'),
        'kutuphane': ('Soru bankanız\nher zaman yanınızda', 'Soru, konu özeti ve hap bilgi tek yerde'),
        'kitapcik': ('Sınav kitapçığını\nkendiniz hazırlayın', 'A–H kitapçık · karışık şıklar · PDF ve Word'),
        'veli': ('Velilere toplu\ngönderin', 'Karneler hazır mesajla, sırayla WhatsApp’tan'),
        'istatistik': ('Bütün sınıflar\ntek bakışta', 'Genel başarı, sınıf sıralaması ve eğilimler'),
        'donem': ('Dönem notu ve\nkazanım karnesi', 'Ağırlıklı dönem notu, kazanım takip çizelgesi'),
        'slogan': 'Optik okuma, soru bankası ve sınav analizi',
        'kitle': 'Okullar, kurslar, akademiler ve üniversiteler için',
        'gizlilik': 'Kayıt gerekmez · Verileriniz cihazınızda',
        'masaustu': 'Şimdi bilgisayarınızda da',
        'platform': 'Windows · Mac · iPhone · iPad · Android',
        'kapanis': 'Windows ve Mac için indirin',
        'deneme': '14 gün ücretsiz deneyin · Kayıt gerekmez',
    },
    'en': {
        'ana_sayfa': ('From paper to results\nin seconds', 'No sign-up · Your data stays on your device'),
        'sonuclar': ('Results\nin an instant', 'Scores, rankings and score distribution'),
        'analiz': ('Item and topic\nanalysis', 'Reliability, item difficulty, automatic insights'),
        'kutuphane': ('Your question bank,\nalways with you', 'Questions, summaries and quick tips in one place'),
        'kitapcik': ('Build your own\ntest booklets', 'Versions A–H · shuffled options · PDF and Word'),
        'veli': ('Send to parents\nin bulk', 'Report cards with a ready message via WhatsApp'),
        'istatistik': ('All your classes\nat a glance', 'Overall success, class ranking and trends'),
        'donem': ('Term grades and\noutcome reports', 'Weighted term grades and outcome tracking'),
        'slogan': 'Answer sheet scanning, question bank and exam analysis',
        'kitle': 'For schools, courses, academies and universities',
        'gizlilik': 'No sign-up · Your data stays on your device',
        'masaustu': 'Now on your computer too',
        'platform': 'Windows · Mac · iPhone · iPad · Android',
        'kapanis': 'Download for Windows and Mac',
        'deneme': 'Try it free for 14 days · No sign-up',
    },
}


def shot(lang, size, name):
    return Image.open(os.path.join(SHOTS, lang, f'{size}_{name}.png')).convert('RGB')


# ---------------------------------------------------------------- çerçeveler
def phone(screen, width):
    """Ekran oranını koruyan ince çerçeveli telefon."""
    sw = width
    sh = int(screen.height * sw / screen.width)
    scr = screen.resize((sw, sh), Image.LANCZOS)
    bez = max(10, sw // 32)
    body = Image.new('RGBA', (sw + 2 * bez, sh + 2 * bez), (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle((0, 0, body.width - 1, body.height - 1), sw // 7, fill=(17, 20, 32, 255))
    r = rounded(scr, sw // 8)
    body.paste(r, (bez, bez), r)
    return body


def tablet(screen, width):
    sw = width
    sh = int(screen.height * sw / screen.width)
    scr = screen.resize((sw, sh), Image.LANCZOS)
    bez = max(14, sw // 40)
    body = Image.new('RGBA', (sw + 2 * bez, sh + 2 * bez), (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle((0, 0, body.width - 1, body.height - 1), sw // 22, fill=(17, 20, 32, 255))
    r = rounded(scr, sw // 36)
    body.paste(r, (bez, bez), r)
    return body


def window(screen, width, style='mac'):
    """Başlık çubuklu masaüstü penceresi (mac: renkli düğmeler, win: _ □ ×)."""
    sw = width
    sh = int(screen.height * sw / screen.width)
    scr = screen.resize((sw, sh), Image.LANCZOS)
    bar = max(28, sw // 40)
    win = Image.new('RGB', (sw, sh + bar), (236, 239, 244))
    d = ImageDraw.Draw(win)
    if style == 'mac':
        r = bar // 5
        for i, col in enumerate([(255, 95, 87), (254, 188, 46), (40, 200, 64)]):
            cx = bar // 2 + i * int(r * 3.2) + r
            d.ellipse((cx - r, bar // 2 - r, cx + r, bar // 2 + r), fill=col)
        f = font('600SemiBold', int(bar * 0.42))
        w = d.textlength('Netice', font=f)
        d.text(((sw - w) / 2, bar * 0.26), 'Netice', font=f, fill=(90, 98, 115))
    else:
        icon = Image.open(ICON).convert('RGBA').resize((int(bar * 0.55),) * 2, Image.LANCZOS)
        win.paste(icon, (int(bar * 0.4), int(bar * 0.22)), icon)
        f = font('500Medium', int(bar * 0.38))
        d.text((int(bar * 1.15), bar * 0.28), 'Netice', font=f, fill=(60, 66, 80))
        s = int(bar * 0.16)
        for i, g in enumerate(['min', 'max', 'close']):
            cx = sw - int(bar * (0.75 + 1.35 * (2 - i)))
            cy = bar // 2
            if g == 'min':
                d.line((cx - s, cy, cx + s, cy), fill=(60, 66, 80), width=2)
            elif g == 'max':
                d.rectangle((cx - s, cy - s, cx + s, cy + s), outline=(60, 66, 80), width=2)
            else:
                d.line((cx - s, cy - s, cx + s, cy + s), fill=(60, 66, 80), width=2)
                d.line((cx - s, cy + s, cx + s, cy - s), fill=(60, 66, 80), width=2)
    win.paste(scr, (0, bar))
    return rounded(win, max(10, sw // 110))


def laptop(screen, width):
    """Dizüstü bilgisayar (ekran + gövde)."""
    sw = width
    sh = int(screen.height * sw / screen.width)
    scr = screen.resize((sw, sh), Image.LANCZOS)
    bez = max(12, sw // 45)
    lid = Image.new('RGBA', (sw + 2 * bez, sh + 2 * bez), (0, 0, 0, 0))
    ImageDraw.Draw(lid).rounded_rectangle((0, 0, lid.width - 1, lid.height - 1), bez * 2, fill=(22, 26, 38, 255))
    lid.paste(scr, (bez, bez))
    base_h = max(14, sw // 36)
    total_w = int(lid.width * 1.16)
    out = Image.new('RGBA', (total_w, lid.height + base_h), (0, 0, 0, 0))
    out.paste(lid, ((total_w - lid.width) // 2, 0), lid)
    d = ImageDraw.Draw(out)
    d.rounded_rectangle((0, lid.height - 2, total_w - 1, lid.height + base_h - 1), base_h // 2, fill=(196, 202, 214, 255))
    notch = total_w // 7
    d.rounded_rectangle(((total_w - notch) // 2, lid.height - 2, (total_w + notch) // 2, lid.height + base_h // 3),
                        base_h // 4, fill=(160, 167, 182, 255))
    return out


# ---------------------------------------------------------------- yerleşim
def wrap_title(d, title, fnt, max_w):
    """Başlıktaki elle satır sonlarını korur; sığmayan satırı böler."""
    lines = []
    for part in title.split('\n'):
        cur = ''
        for w in part.split():
            t = (cur + ' ' + w).strip()
            if cur and d.textlength(t, font=fnt) > max_w:
                lines.append(cur)
                cur = w
            else:
                cur = t
        lines.append(cur)
    return lines


def centered(d, lines, fnt, fill, y, W, step):
    for ln in lines:
        w = d.textlength(ln, font=fnt)
        d.text(((W - w) / 2, y), ln, font=fnt, fill=fill)
        y += step
    return y


def header(c, title, sub, W, H, scale):
    """Üstte ortalanmış başlık + alt başlık; sonraki y'yi döndürür."""
    d = ImageDraw.Draw(c)
    ft = font('800ExtraBold', int(scale * 0.066))
    fs = font('600SemiBold', int(scale * 0.032))
    y = int(H * 0.05)
    lines = wrap_title(d, title, ft, W * 0.88)
    y = centered(d, lines, ft, WHITE, y, W, int(scale * 0.08))
    y += int(scale * 0.018)
    y = centered(d, wrap_title(d, sub, fs, W * 0.86), fs, MINT, y, W, int(scale * 0.042))
    return y + int(scale * 0.04)


def place(c, dev, x, y, radius):
    shadow(c, (x + 10, y + 30, x + dev.width - 10, y + dev.height), radius)
    c.paste(dev, (x, y), dev)


def portrait(scr, title, sub, W, H, kind):
    c = background(W, H).convert('RGBA')
    top = header(c, title, sub, W, H, W)
    if kind == 'phone':
        dev = phone(scr, int(W * 0.76))
    else:
        dev = tablet(scr, int(W * 0.80))
    place(c, dev, (W - dev.width) // 2, top, dev.width // 9)
    return c.convert('RGB')


def landscape(scr, title, sub, W, H, style):
    c = background(W, H).convert('RGBA')
    d = ImageDraw.Draw(c)
    ft = font('800ExtraBold', int(H * 0.068))
    fs = font('600SemiBold', int(H * 0.032))
    y = int(H * 0.06)
    y = centered(d, [title.replace('\n', ' ')], ft, WHITE, y, W, int(H * 0.085))
    y = centered(d, [sub], fs, MINT, y + int(H * 0.005), W, int(H * 0.04))
    top = y + int(H * 0.045)
    dev = window(scr, int(W * 0.80), style)
    place(c, dev, (W - dev.width) // 2, top, 30)
    return c.convert('RGB')


def save(im, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path, optimize=True)


# ---------------------------------------------------------------- logolar / tanıtım
def icon(size):
    return Image.open(ICON).convert('RGBA').resize((size, size), Image.LANCZOS)


def logo_block(c, cx, cy, size, with_text=True, lines=()):
    """Simge + 'Netice' + isteğe bağlı satırlar, (cx, cy) merkezli."""
    d = ImageDraw.Draw(c)
    ic = icon(size)
    fn = font('800ExtraBold', int(size * 0.55))
    total = size + (int(size * 0.75) if with_text else 0) + len(lines) * int(size * 0.32)
    y = cy - total // 2
    shadow(c, (cx - size // 2, y + 10, cx + size // 2, y + size), size // 5, blur=size // 8, alpha=110)
    c.paste(ic, (cx - size // 2, y), ic)
    y += size + int(size * 0.08)
    if with_text:
        w = d.textlength('Netice', font=fn)
        d.text((cx - w / 2, y), 'Netice', font=fn, fill=WHITE)
        y += int(size * 0.72)
    for i, (t, col) in enumerate(lines):
        f = font('700Bold' if i == 0 else '500Medium', int(size * (0.19 if i == 0 else 0.15)))
        w = d.textlength(t, font=f)
        d.text((cx - w / 2, y), t, font=f, fill=col)
        y += int(size * 0.3)


def store_logos(out):
    # Kutu resmi 1:1 ve poster 2:3: yalnız simge ve ad (Microsoft yazı kullanılmamasını önerir).
    for name, (W, H) in {'kutu_1x1_2160.png': (2160, 2160), 'kutu_1x1_1080.png': (1080, 1080),
                         'poster_2x3_1440x2160.png': (1440, 2160), 'poster_2x3_720x1080.png': (720, 1080)}.items():
        c = background(W, H).convert('RGBA')
        logo_block(c, W // 2, H // 2, int(min(W, H) * 0.36))
        save(c.convert('RGB'), os.path.join(out, name))
    # Kahraman görseli 16:9: sağda uygulama, solda simge; yazısız.
    for name, (W, H) in {'kahraman_16x9_3840x2160.png': (3840, 2160), 'kahraman_16x9_1920x1080.png': (1920, 1080)}.items():
        c = background(W, H).convert('RGBA')
        logo_block(c, int(W * 0.22), H // 2, int(H * 0.28))
        dev = window(shot('tr', 'masaustu', 'ana_sayfa'), int(W * 0.58), 'win')
        place(c, dev, int(W * 0.38), (H - dev.height) // 2, 30)
        save(c.convert('RGB'), os.path.join(out, name))


def web_social(lang, out):
    t = TEXT[lang]
    # Site afişi 1920x1080: solda başlık, sağda dizüstü + telefon.
    W, H = 1920, 1080
    c = background(W, H).convert('RGBA')
    d = ImageDraw.Draw(c)
    ic = icon(96)
    c.paste(ic, (120, 150), ic)
    d.text((236, 160), 'Netice', font=font('800ExtraBold', 64), fill=WHITE)
    ft = font('800ExtraBold', 70)
    y = 330
    for ln in wrap_title(d, t['slogan'], ft, 720):
        d.text((120, y), ln, font=ft, fill=WHITE)
        y += 84
    y += 20
    d.text((120, y), t['kitle'], font=font('600SemiBold', 32), fill=MINT)
    y += 70
    d.rounded_rectangle((120, y, 120 + 64, y + 8), 4, fill=EMERALD)
    y += 36
    d.text((120, y), t['gizlilik'], font=font('500Medium', 28), fill=SOFT)
    d.text((120, y + 46), t['platform'], font=font('700Bold', 28), fill=WHITE)
    lap = laptop(shot(lang, 'masaustu', 'ana_sayfa'), 800)
    place(c, lap, 860, 270, 30)
    ph = phone(shot(lang, 'telefon', 'sonuclar'), 240)
    place(c, ph, 1600, 420, 40)
    save(c.convert('RGB'), os.path.join(out, 'site_afisi_1920x1080.png'))

    # Kare gönderi 1080x1080.
    W = H = 1080
    c = background(W, H).convert('RGBA')
    d = ImageDraw.Draw(c)
    y = centered(d, [t['masaustu']], font('800ExtraBold', 64), WHITE, 80, W, 80)
    centered(d, [t['platform']], font('600SemiBold', 30), MINT, y + 6, W, 40)
    lap = laptop(shot(lang, 'masaustu', 'analiz'), 820)
    place(c, lap, (W - lap.width) // 2 - 40, 300, 30)
    ph = phone(shot(lang, 'telefon', 'ana_sayfa'), 220)
    place(c, ph, 800, 500, 40)
    centered(d, [t['gizlilik']], font('600SemiBold', 30), SOFT, 1000, W, 40)
    save(c.convert('RGB'), os.path.join(out, 'sosyal_kare_1080.png'))

    # Hikâye 1080x1920.
    W, H = 1080, 1920
    c = background(W, H).convert('RGBA')
    d = ImageDraw.Draw(c)
    ic = icon(150)
    c.paste(ic, ((W - 150) // 2, 120), ic)
    y = centered(d, ['Netice'], font('800ExtraBold', 90), WHITE, 300, W, 110)
    ft = font('700Bold', 50)
    y = centered(d, wrap_title(d, t['slogan'], ft, 900), ft, WHITE, y + 10, W, 64)
    y = centered(d, [t['gizlilik']], font('600SemiBold', 32), MINT, y + 20, W, 44)
    lap = laptop(shot(lang, 'masaustu', 'istatistik'), 860)
    ly = y + 80
    place(c, lap, (W - lap.width) // 2, ly, 30)
    ph = phone(shot(lang, 'telefon', 'kutuphane'), 300)
    py = ly + lap.height - ph.height // 3
    place(c, ph, W - ph.width - 70, py, 40)
    centered(d, [t['platform']], font('700Bold', 34), WHITE, min(H - 110, py + ph.height + 50), W, 44)
    save(c.convert('RGB'), os.path.join(out, 'sosyal_hikaye_1080x1920.png'))


def video_frames(lang, out):
    """Bilgisayar tanıtım videosu kareleri (1920x1080): açılış, 8 ekran, kapanış."""
    t = TEXT[lang]
    W, H = 1920, 1080
    for name, l1, l2 in (('kare_00.png', t['masaustu'], t['slogan']), ('kare_99.png', t['kapanis'], t['deneme'])):
        c = background(W, H).convert('RGBA')
        logo_block(c, W // 2, H // 2 - 20, 260, lines=((l1, MINT), (l2, SOFT)))
        d = ImageDraw.Draw(c)
        centered(d, [t['platform']], font('700Bold', 34), WHITE, H - 120, W, 40)
        save(c.convert('RGB'), os.path.join(out, name))
    for i, n in enumerate(SCREENS, 1):
        title, sub = t[n]
        style = 'mac' if i % 2 == 0 else 'win'
        save(landscape(shot(lang, 'masaustu', n), title, sub, W, H, style), os.path.join(out, f'kare_{i:02d}.png'))


def main():
    out = sys.argv[1]
    langs = sys.argv[2:] or ['tr', 'en']
    for lang in langs:
        for i, name in enumerate(SCREENS, 1):
            title, sub = TEXT[lang][name]
            n = f'{i:02d}.png'
            ph = shot(lang, 'telefon', name)
            tb = shot(lang, 'tablet', name)
            dk = shot(lang, 'masaustu', name)
            save(portrait(ph, title, sub, 1320, 2868, 'phone'), os.path.join(out, 'app-store', lang, 'iphone-6.9', n))
            save(portrait(ph, title, sub, 1284, 2778, 'phone'), os.path.join(out, 'app-store', lang, 'iphone-6.5', n))
            save(portrait(tb, title, sub, 2064, 2752, 'tablet'), os.path.join(out, 'app-store', lang, 'ipad-13', n))
            save(portrait(tb, title, sub, 1600, 2560, 'tablet'), os.path.join(out, 'google-play', 'tablet', lang, n))
            save(landscape(dk, title, sub, 2880, 1800, 'mac'), os.path.join(out, 'masaustu', 'mac-app-store', lang, n))
            save(landscape(dk, title, sub, 2560, 1440, 'win'), os.path.join(out, 'masaustu', 'microsoft-store', lang, n))
        web_social(lang, os.path.join(out, 'masaustu', 'web-ve-sosyal', lang))
        video_frames(lang, os.path.join(out, 'masaustu', 'video-kareleri', lang))
    store_logos(os.path.join(out, 'masaustu', 'microsoft-store', 'logolar'))
    # App Store simgesi saydamlık içermemeli.
    flat = Image.open(ICON_FLAT).convert('RGBA')
    bg = Image.new('RGB', flat.size, (15, 27, 61))
    bg.paste(flat, (0, 0), flat)
    save(bg, os.path.join(out, 'app-store', 'simge_1024.png'))


if __name__ == '__main__':
    main()
