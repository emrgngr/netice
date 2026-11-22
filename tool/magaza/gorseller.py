"""Google Play mağaza görselleri.

Önce ekran görüntülerini üretin:  flutter test tool/screenshots_test.dart
Sonra:  python3 tool/magaza/gorseller.py <form_png> <cikti_klasoru>

Üretilenler:
  telefon/01..08.png   1080x1920 başlıklı ekran görüntüleri
  video/kare_XX.png    1920x1080 tanıtım videosu kareleri
  simge_512.png        uygulama simgesi
  kapak_1024x500.png   öne çıkan görsel
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SHOTS = os.path.join(ROOT, 'build', 'screenshots')
FONT = os.path.join(ROOT, 'assets', 'fonts', 'PlusJakartaSans_{}.ttf')
INK = (15, 27, 61)
INK_TOP = (30, 46, 96)
INK_BOTTOM = (8, 15, 38)
EMERALD = (16, 185, 129)
MINT = (167, 243, 208)

# (ekran, başlık, alt başlık)
SLIDES = [
    ('mobil_ana_sayfa', 'Kâğıttan sonuca,\nsaniyeler içinde', 'Optik formları telefon kamerasıyla okuyun'),
    ('mobil_sinav_sonuclari', 'Sonuçlar anında hazır', 'Puan, net, sıralama ve puan dağılımı'),
    ('FORM', 'Kendi optik formunuzu\nyazdırın', 'Öğrenci adlı form · A–H kitapçık · 10 haneli numara'),
    ('mobil_analiz', 'Raporlar tek dokunuşla', 'Sınav raporu, öğrenci karnesi ve Excel'),
    ('mobil_ogrenci_gecmisi', 'Her öğrencinin gelişimi', 'Gelişim grafiği ve erken uyarı'),
    ('mobil_donem_raporu', 'Dönem notu ve\nkazanım karnesi', 'Ağırlıklı ortalama, PDF ve Excel'),
    ('mobil_sube_karsilastirmasi', 'Şubeleri karşılaştırın', 'Soru bazında doğru oranları'),
    ('mobil_siniflar', 'Excel veya PDF’ten\nöğrenci aktarın', 'Tüm sınıflar kendiliğinden ayrılır'),
]


def font(weight, size):
    return ImageFont.truetype(FONT.format(weight), size)


def background(w, h):
    """Lacivert dikey geçiş ve sağ üstte zümrüt ışıma."""
    bg = Image.new('RGB', (w, h))
    px = bg.load()
    for y in range(h):
        t = y / (h - 1)
        if t < 0.5:
            a, b, k = INK_TOP, INK, t / 0.5
        else:
            a, b, k = INK, INK_BOTTOM, (t - 0.5) / 0.5
        c = tuple(int(a[i] + (b[i] - a[i]) * k) for i in range(3))
        for x in range(w):
            px[x, y] = c
    glow = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(glow)
    r = int(max(w, h) * 0.45)
    d.ellipse((w - r, -r // 2, w + r // 2, r), fill=EMERALD + (70,))
    glow = glow.filter(ImageFilter.GaussianBlur(r // 3))
    bg.paste(glow, (0, 0), glow)
    return bg


def rounded(im, radius):
    mask = Image.new('L', im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, im.width - 1, im.height - 1), radius, fill=255)
    out = Image.new('RGBA', im.size, (0, 0, 0, 0))
    out.paste(im, (0, 0), mask)
    return out


def shadow(canvas, box, radius, blur=40, alpha=150):
    sh = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(box, radius, fill=(0, 0, 0, alpha))
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    canvas.paste(sh, (0, 0), sh)


def phone(screen, width):
    """Ekranı ince çerçeveli telefona yerleştirir (1:2 oran)."""
    sw = width
    sh = sw * 2
    src = screen.convert('RGB')
    src = src.crop((0, 0, src.width, min(src.height, src.width * 2)))
    src = src.resize((sw, int(src.height * sw / src.width)), Image.LANCZOS)
    scr = Image.new('RGB', (sw, sh), (245, 246, 250))
    scr.paste(src, (0, 0))
    bez = max(10, sw // 36)
    body = Image.new('RGBA', (sw + 2 * bez, sh + 2 * bez), (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle((0, 0, body.width - 1, body.height - 1), sw // 9, fill=(17, 20, 32, 255))
    body.paste(rounded(scr, sw // 11), (bez, bez), rounded(scr, sw // 11))
    return body


def paper(form, width):
    im = form.convert('RGB')
    im = im.resize((width, int(im.height * width / im.width)), Image.LANCZOS)
    return rounded(im, width // 60)


def device_for(name, form, width):
    if name == 'FORM':
        return paper(form, 900)
    return phone(Image.open(os.path.join(SHOTS, name + '.png')), width)


def draw_lines(d, xy, text, fnt, fill, spacing, anchor_center=None):
    x, y = xy
    for line in text.split('\n'):
        if anchor_center is not None:
            w = d.textlength(line, font=fnt)
            d.text((anchor_center - w / 2, y), line, font=fnt, fill=fill)
        else:
            d.text((x, y), line, font=fnt, fill=fill)
        y += spacing
    return y


def portrait(slide, form, out):
    name, title, sub = slide
    W, H = 1080, 1920
    c = background(W, H).convert('RGBA')
    d = ImageDraw.Draw(c)
    y = 120
    y = draw_lines(d, (0, y), title, font('800ExtraBold', 76), (255, 255, 255), 92, anchor_center=W / 2)
    y += 18
    draw_lines(d, (0, y), sub, font('600SemiBold', 38), MINT, 48, anchor_center=W / 2)
    dev = device_for(name, form, 660)
    top = 520 if '\n' in title else 450
    x = (W - dev.width) // 2
    shadow(c, (x + 10, top + 30, x + dev.width - 10, top + dev.height), dev.width // 9)
    c.paste(dev, (x, top), dev)
    c.convert('RGB').save(out)


def landscape(slide, form, out, index):
    name, title, sub = slide
    W, H = 1920, 1080
    c = background(W, H).convert('RGBA')
    d = ImageDraw.Draw(c)
    title = title.replace('\n', ' ')
    # Başlığı sol sütuna sığacak şekilde satırlara böl.
    words, lines, cur = title.split(), [], ''
    f = font('800ExtraBold', 84)
    for w in words:
        t = (cur + ' ' + w).strip()
        if d.textlength(t, font=f) > 900 and cur:
            lines.append(cur)
            cur = w
        else:
            cur = t
    lines.append(cur)
    y = 540 - (len(lines) * 100 + 80) // 2
    d.rounded_rectangle((140, y - 70, 140 + 64, y - 62), 4, fill=EMERALD)
    for ln in lines:
        d.text((140, y), ln, font=f, fill=(255, 255, 255))
        y += 100
    d.text((140, y + 16), sub, font=font('600SemiBold', 40), fill=MINT)
    if name == 'FORM':
        dev = paper(form, 640)
        top = 90
    else:
        dev = phone(Image.open(os.path.join(SHOTS, name + '.png')), 430)
        top = 80
    dev = dev.crop((0, 0, dev.width, min(dev.height, H - top + 200)))
    x = 1240 if name != 'FORM' else 1150
    shadow(c, (x + 10, top + 30, x + dev.width - 10, top + dev.height), 40)
    c.paste(dev, (x, top), dev)
    c.convert('RGB').save(out)


def logo_slide(out, line1, line2):
    W, H = 1920, 1080
    c = background(W, H).convert('RGBA')
    d = ImageDraw.Draw(c)
    icon = Image.open(os.path.join(ROOT, 'assets', 'icon', 'netice_icon_rounded_1024.png')).convert('RGBA').resize((260, 260), Image.LANCZOS)
    shadow(c, (830, 230, 1090, 490), 60, blur=30, alpha=120)
    c.paste(icon, (830, 220), icon)
    f = font('800ExtraBold', 120)
    w = d.textlength('Netice', font=f)
    d.text(((W - w) / 2, 520), 'Netice', font=f, fill=(255, 255, 255))
    for i, (t, fnt, col) in enumerate([(line1, font('700Bold', 50), MINT), (line2, font('500Medium', 38), (203, 213, 225))]):
        w = d.textlength(t, font=fnt)
        d.text(((W - w) / 2, 700 + i * 80), t, font=fnt, fill=col)
    c.convert('RGB').save(out)


def feature(out):
    W, H = 1024, 500
    c = background(W, H).convert('RGBA')
    d = ImageDraw.Draw(c)
    icon = Image.open(os.path.join(ROOT, 'assets', 'icon', 'netice_icon_rounded_1024.png')).convert('RGBA').resize((120, 120), Image.LANCZOS)
    c.paste(icon, (64, 92), icon)
    d.text((204, 100), 'Netice', font=font('800ExtraBold', 74), fill=(255, 255, 255))
    d.text((66, 250), 'Optik formu telefonla okuyun,', font=font('700Bold', 38), fill=(255, 255, 255))
    d.text((66, 300), 'sonuç ve raporlar anında hazır.', font=font('700Bold', 38), fill=MINT)
    d.text((66, 380), 'Çevrimdışı çalışır · Verileriniz cihazınızda', font=font('500Medium', 24), fill=(203, 213, 225))
    dev = phone(Image.open(os.path.join(SHOTS, 'mobil_sinav_sonuclari.png')), 220)
    shadow(c, (740, 70, 740 + dev.width, 70 + dev.height), 30, blur=24)
    c.paste(dev, (740, 60), dev)
    c.convert('RGB').save(out)


def main():
    form = Image.open(sys.argv[1])
    out = sys.argv[2]
    os.makedirs(os.path.join(out, 'telefon'), exist_ok=True)
    os.makedirs(os.path.join(out, 'video'), exist_ok=True)
    for i, s in enumerate(SLIDES, 1):
        portrait(s, form, os.path.join(out, 'telefon', f'{i:02d}.png'))
        landscape(s, form, os.path.join(out, 'video', f'kare_{i:02d}.png'), i)
    logo_slide(os.path.join(out, 'video', 'kare_00.png'), 'Optik okuma ve sınav analizi', 'Öğretmenler ve kurumlar için')
    logo_slide(os.path.join(out, 'video', 'kare_99.png'), 'Google Play’de ücretsiz indirin', 'Çevrimdışı çalışır · Verileriniz cihazınızda')
    Image.open(os.path.join(ROOT, 'assets', 'icon', 'netice_icon_1024.png')).convert('RGBA').resize((512, 512), Image.LANCZOS).save(os.path.join(out, 'simge_512.png'))
    feature(os.path.join(out, 'kapak_1024x500.png'))


if __name__ == '__main__':
    main()
