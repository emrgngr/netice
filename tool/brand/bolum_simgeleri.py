"""Bölüm simgeleri: uygulamadaki lib/ui/section_icons.dart ile aynı stil.

Kare kutu, köşe %30, sol üstten sağ alta iki renkli gradyan, üst yarıda beyaz
parlama, ortada beyaz Material (rounded) simge (%55), altta yumuşak gölge.
Kullanım: python3 tool/brand/bolum_simgeleri.py [çıktı_klasörü] [boyut]
Kılavuz PDF'i, rehber videoları ve web sitesi bu dosyaları kullanır.
"""
import os
import shutil
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

KOK = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FONT_ADAYLARI = [
    os.environ.get('ICON_FONT', ''),
    '/home/claude/sdk/flutter/bin/cache/dart-sdk/bin/resources/devtools/assets/fonts/MaterialIcons-Regular.otf',
    os.path.join(os.environ.get('FLUTTER_ROOT', ''), 'bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'),
    os.path.join(os.path.dirname(shutil.which('flutter') or '/x'), 'cache/artifacts/material_fonts/MaterialIcons-Regular.otf'),
]

# anahtar: (Material rounded kod noktası, açık renk, koyu renk, simge rengi)
SIMGELER = {
    'start':    (0xf01af, '#8391E0', '#4E5C99', '#FFFFFF'),  # Pano / Başlarken
    'classes':  (0xf7c8, '#A78BFA', '#6D28D9', '#FFFFFF'),   # Sınıflar ve öğrenciler
    'exam':     (0xf69b, '#60A5FA', '#1D4ED8', '#FFFFFF'),   # Sınavlar
    'print':    (0xf00c0, '#E879F9', '#A21CAF', '#FFFFFF'),  # Form yazdırma
    'scan':     (0xf6ce, '#34D399', '#047857', '#FFFFFF'),   # Kâğıt okut
    'report':   (0xf00ce, '#22D3EE', '#0E7490', '#FFFFFF'),  # Sonuçlar ve raporlar
    'library':  (0xf872, '#FB923C', '#C2410C', '#FFFFFF'),   # Soru bankası
    'booklet':  (0xf8b4, '#FB7185', '#BE123C', '#FFFFFF'),   # Kitapçık
    'fix':      (0xf732, '#FBBF24', '#D97706', '#FFFFFF'),   # Kontrol ve düzeltme
    'data':     (0xf0164, '#94A3B8', '#475569', '#FFFFFF'),  # Ayarlar ve verileriniz
    'pro':      (0xf0306, '#F7D774', '#D99A2B', '#3A2800'),  # Netice Pro
    # Web sitesi ve tanıtım için ek konular
    'ai':       (0xf596, '#A5B4FC', '#4F46E5', '#FFFFFF'),   # Yapay zekâ / nottan soru
    'parents':  (0xf733, '#38BDF8', '#0369A1', '#FFFFFF'),   # Veliler ve paylaşım
    'privacy':  (0xf016b, '#3B4C8C', '#0F1B3D', '#FFFFFF'),  # Gizlilik
    'offline':  (0xf02bd, '#5EEAD4', '#0D9488', '#FFFFFF'),  # İnternetsiz çalışır
    'language': (0xf0250, '#F472B6', '#BE185D', '#FFFFFF'),  # Diller
    'compare':  (0xf65d, '#2DD4BF', '#0F766E', '#FFFFFF'),   # Sınıf sınıf analiz
    'term':     (0xf03c0, '#3B4C8C', '#0F1B3D', '#FFFFFF'),  # Dönem raporu
}

# Kılavuz bölüm numarası → simge anahtarı
KILAVUZ = {'1': 'start', '2': 'classes', '3': 'exam', '4': 'print', '5': 'scan',
           '6': 'report', '7': 'library', '8': 'fix', '9': 'data', '10': 'pro'}


def _hex(h, a=255):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (a,)


def _font(px):
    for f in FONT_ADAYLARI:
        if f and os.path.exists(f):
            return ImageFont.truetype(f, px)
    raise SystemExit('MaterialIcons-Regular.otf bulunamadı (ICON_FONT ile verin)')


def simge(anahtar, boyut=512):
    kod, acik, koyu, renk = SIMGELER[anahtar]
    S = boyut * 4  # pürüzsüz kenar için büyük çiz, sonra küçült
    pad = int(S * 0.08)
    kutu = S - 2 * pad
    r = int(kutu * 0.30)
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))

    # gölge
    g = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(g).rounded_rectangle([pad, pad + int(kutu * 0.06), pad + kutu, pad + kutu + int(kutu * 0.04)], r,
                                        fill=_hex(koyu, int(255 * 0.35)))
    img.alpha_composite(g.filter(ImageFilter.GaussianBlur(S * 0.03)))

    # gradyan (sol üst → sağ alt)
    a, b = _hex(acik), _hex(koyu)
    grad = Image.new('RGBA', (kutu, kutu))
    gp = grad.load()
    for y in range(0, kutu, 4):
        for x in range(0, kutu, 4):
            t = (x + y) / (2 * kutu)
            c = tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3)) + (255,)
            for dy in range(4):
                for dx in range(4):
                    if x + dx < kutu and y + dy < kutu:
                        gp[x + dx, y + dy] = c
    # parlama: üst yarıda beyaz %28 → %0
    parla = Image.new('RGBA', (kutu, kutu), (0, 0, 0, 0))
    pd = ImageDraw.Draw(parla)
    for y in range(kutu // 2):
        pd.line([(0, y), (kutu, y)], fill=(255, 255, 255, int(255 * 0.28 * (1 - y / (kutu / 2)))))
    grad.alpha_composite(parla)
    maske = Image.new('L', (kutu, kutu), 0)
    ImageDraw.Draw(maske).rounded_rectangle([0, 0, kutu - 1, kutu - 1], r, fill=255)
    img.paste(grad, (pad, pad), maske)

    # simge
    f = _font(int(kutu * 0.55))
    d = ImageDraw.Draw(img)
    d.text((S / 2, S / 2), chr(kod), font=f, fill=_hex(renk), anchor='mm')
    return img.resize((boyut, boyut), Image.LANCZOS)


def hepsi(klasor, boyut=512):
    os.makedirs(klasor, exist_ok=True)
    yollar = {}
    for k in SIMGELER:
        p = os.path.join(klasor, f'{k}.png')
        if not os.path.exists(p) or os.path.getsize(p) == 0:
            simge(k, boyut).save(p)
        yollar[k] = p
    return yollar


if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(KOK, 'build', 'bolum_simgeleri')
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 512
    for k, p in hepsi(out, n).items():
        print(k, p)
