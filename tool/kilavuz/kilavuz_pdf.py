"""Netice kullanım kılavuzu PDF'i.

Önce görüntüler: flutter test tool/kilavuz_pdf_test.dart --dart-define=KILAVUZ_DIL=<dil>
Sonra:          python3 tool/kilavuz/kilavuz_pdf.py <dil> [çıktı.pdf]
Metinler icerik.py'de Türkçedir; diğer diller tool/kilavuz/ceviri/<dil>.json
(Türkçe metin -> çeviri) dosyasından gelir.
"""
import json
import math
import os
import sys
from datetime import date

from reportlab.lib.colors import HexColor, white, Color
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.utils import ImageReader
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import Paragraph

sys.path.insert(0, os.path.dirname(__file__))
from icerik import BOLUMLER, SAYFALAR  # noqa: E402

KOK = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
DIL = sys.argv[1] if len(sys.argv) > 1 else 'tr'
KARE = os.path.join(KOK, 'build', 'kilavuz', DIL, 'frames')
CIKTI = sys.argv[2] if len(sys.argv) > 2 else os.path.join(KOK, 'build', 'kilavuz', f'Netice_Kullanim_Kilavuzu_{DIL}.pdf')
RTL = DIL == 'ar'
CJK = DIL in ('zh', 'ja')

_ceviri = {}
if DIL != 'tr':
    _ceviri = json.load(open(os.path.join(os.path.dirname(__file__), 'ceviri', f'{DIL}.json'), encoding='utf-8'))


def T(s):
    """Türkçe metnin bu dildeki karşılığı."""
    if DIL == 'tr':
        return s
    if s not in _ceviri:
        raise SystemExit(f'çeviri eksik ({DIL}): {s}')
    return _ceviri[s]


def gorsel(s):
    """Arapça: harfleri birleştir ve sağdan sola sıraya koy (tek satır)."""
    if not RTL:
        return s
    import arabic_reshaper
    from bidi.algorithm import get_display
    return get_display(arabic_reshaper.reshape(s))


def ust(s):
    return s.replace('i', 'İ').upper() if DIL in ('tr', 'az') else s.upper()

INK = HexColor('#0F1B3D')
INK2 = HexColor('#1E2E60')
EMERALD = HexColor('#10B981')
EMERALD_D = HexColor('#047857')
MINT = HexColor('#D1FAE5')
IVORY = HexColor('#F6F3EC')
AMBER = HexColor('#F2B33D')
AMBER_BG = HexColor('#FDF3DC')
MUTED = HexColor('#55607A')
LINE = HexColor('#E3E6EE')

_noto = {
    'ar': ('NotoSansArabic-Regular', 'NotoSansArabic-Bold'),
    'ru': ('NotoSans-Regular', 'NotoSans-Bold'),
    'zh': ('NotoSansSC-Regular', 'NotoSansSC-Regular'),
    'ja': ('NotoSansJP-Regular', 'NotoSansJP-Regular'),
    'ko': ('NotoSansKR-Regular', 'NotoSansKR-Regular'),
    'hi': ('NotoSansDevanagari-Regular', 'NotoSansDevanagari-Regular'),
}.get(DIL)
# Devanagari harf birleştirmesi (uharfbuzz gerekir: pip install uharfbuzz).
SHAPE = DIL == 'hi'
for ad, dosya in [('J', '400Regular'), ('J5', '500Medium'), ('J6', '600SemiBold'), ('J7', '700Bold'), ('J8', '800ExtraBold')]:
    if _noto:
        yol = os.path.join(KOK, 'assets', 'pdf_fonts', (_noto[0] if ad in ('J', 'J5') else _noto[1]) + '.ttf')
    else:
        yol = os.path.join(KOK, 'assets', 'fonts', f'PlusJakartaSans_{dosya}.ttf')
    pdfmetrics.registerFont(TTFont(ad, yol))
pdfmetrics.registerFontFamily('J', normal='J', bold='J7', italic='J', boldItalic='J7')

W, H = A4
M = 40  # kenar boşluğu
SW, SH = 360.0, 760.0  # ekran görüntüsünün mantıksal boyutu
hedefler = json.load(open(os.path.join(KARE, 'hedefler.json'), encoding='utf-8'))

st_giris = ParagraphStyle('giris', fontName='J', fontSize=10.5, leading=15, textColor=MUTED, shaping=int(SHAPE))
st_adim_b = ParagraphStyle('ab', fontName='J7', fontSize=10.5, leading=13.5, textColor=INK, shaping=int(SHAPE))
st_adim = ParagraphStyle('a', fontName='J', fontSize=9.2, leading=12.8, textColor=MUTED, shaping=int(SHAPE))
st_ipucu = ParagraphStyle('ip', fontName='J', fontSize=9.4, leading=13.2, textColor=INK, shaping=int(SHAPE))
st_kapak = ParagraphStyle('k', fontName='J', fontSize=12, leading=18, textColor=HexColor('#C9D2EA'), shaping=int(SHAPE))


if CJK:
    for _st in (st_giris, st_adim_b, st_adim, st_ipucu, st_kapak):
        _st.wordWrap = 'CJK'


def _rtl_satirlar(text, style, width):
    import re
    text = re.sub(r'<[^>]+>', '', text)
    satirlar = []
    for parca in text.split('\n'):
        cur = ''
        for w in parca.split(' '):
            dene = (cur + ' ' + w).strip()
            if cur and pdfmetrics.stringWidth(gorsel(dene), style.fontName, style.fontSize) > width:
                satirlar.append(cur)
                cur = w
            else:
                cur = dene
        satirlar.append(cur)
    return satirlar


def para(c, text, style, x, y_top, width):
    if RTL:
        satirlar = _rtl_satirlar(text, style, width)
        c.setFillColor(style.textColor)
        c.setFont(style.fontName, style.fontSize)
        for i, sat in enumerate(satirlar):
            c.drawRightString(x + width, y_top - style.fontSize - i * style.leading, gorsel(sat))
        return len(satirlar) * style.leading
    p = Paragraph(text, style)
    _, h = p.wrap(width, 1000)
    p.drawOn(c, x, y_top - h)
    return h


def para_h(text, style, width):
    if RTL:
        return len(_rtl_satirlar(text, style, width)) * style.leading
    return Paragraph(text, style).wrap(width, 1000)[1]


def yaz(c, x, y, s, sag=False, orta=False):
    """Tek satır yazı (Arapçada şekillendirilmiş)."""
    s = gorsel(s)
    if SHAPE:
        from reportlab.pdfbase.ttfonts import shapeStr
        s = shapeStr(s, c._fontname, c._fontsize, force=True)
    if orta:
        c.drawCentredString(x, y, s)
    elif sag:
        c.drawRightString(x, y, s)
    else:
        c.drawString(x, y, s)


def rozet(c, x, y, n, r=10, renk=EMERALD, yazi=INK):
    c.setFillColor(white)
    c.circle(x, y, r + 1.6, stroke=0, fill=1)
    c.setFillColor(renk)
    c.circle(x, y, r, stroke=0, fill=1)
    c.setFillColor(yazi)
    c.setFont('J8', r * 1.05)
    c.drawCentredString(x, y - r * 0.37, str(n))


def ok(c, x1, y1, x2, y2):
    """x1,y1'den x2,y2'ye ok; koyu zeminde de görünsün diye beyaz kenarlı."""
    ang = math.atan2(y2 - y1, x2 - x1)
    L = 8.5
    # gövde
    for renk, kal in [(white, 4.2), (EMERALD_D, 2.0)]:
        c.setStrokeColor(renk)
        c.setLineWidth(kal)
        c.setLineCap(1)
        bx, by = x2 - (L - 1) * math.cos(ang), y2 - (L - 1) * math.sin(ang)
        c.line(x1, y1, bx, by)
    # uç
    p = c.beginPath()
    p.moveTo(x2, y2)
    p.lineTo(x2 - L * math.cos(ang - 0.45), y2 - L * math.sin(ang - 0.45))
    p.lineTo(x2 - L * math.cos(ang + 0.45), y2 - L * math.sin(ang + 0.45))
    p.close()
    c.setStrokeColor(white)
    c.setLineWidth(1.2)
    c.setFillColor(EMERALD_D)
    c.drawPath(p, stroke=1, fill=1)


def telefon(c, ekran, x, y_top, w):
    """Telefon çerçevesi içinde ekran görüntüsü. Dönüş: (ölçek, sol, üst)."""
    h = w * SH / SW
    bez = w * 0.045
    c.saveState()
    c.setFillColor(Color(0.06, 0.1, 0.24, alpha=0.18))
    c.roundRect(x - bez + 3, y_top - h - bez - 6, w + 2 * bez, h + 2 * bez, w * 0.12, stroke=0, fill=1)
    c.setFillColor(INK)
    c.roundRect(x - bez, y_top - h - bez, w + 2 * bez, h + 2 * bez, w * 0.12, stroke=0, fill=1)
    p = c.beginPath()
    p.roundRect(x, y_top - h, w, h, w * 0.085)
    c.clipPath(p, stroke=0)
    c.drawImage(ImageReader(os.path.join(KARE, ekran + '.png')), x, y_top - h, w, h)
    c.restoreState()
    return w / SW, x, y_top


def hedef_kutusu(c, olcek, sol, ust, r):
    x = sol + r[0] * olcek
    y = ust - (r[1] + r[3]) * olcek
    w, h = r[2] * olcek, r[3] * olcek
    pad = 2.5
    c.setStrokeColor(white)
    c.setLineWidth(3.6)
    c.roundRect(x - pad, y - pad, w + 2 * pad, h + 2 * pad, 6, stroke=1, fill=0)
    c.setStrokeColor(EMERALD)
    c.setLineWidth(2)
    c.roundRect(x - pad, y - pad, w + 2 * pad, h + 2 * pad, 6, stroke=1, fill=0)
    return x - pad, y - pad, w + 2 * pad, h + 2 * pad


def ust_bant(c, bolum, baslik, sayfa_no):
    c.setFillColor(IVORY)
    c.rect(0, 0, W, H, stroke=0, fill=1)
    ad = T(dict(BOLUMLER)[bolum])
    c.setFillColor(EMERALD_D)
    c.setFont('J7', 8.5)
    etiket = f'第{bolum}章' if CJK else f'{ust(T("BÖLÜM"))} {bolum}'
    yaz(c, W - M if RTL else M, H - 44, f'{etiket}  ·  {ust(ad)}', sag=RTL)
    c.setFillColor(INK)
    c.setFont('J8', 22)
    yaz(c, W - M if RTL else M, H - 70, T(baslik), sag=RTL)
    # alt bilgi
    c.setStrokeColor(LINE)
    c.setLineWidth(0.8)
    c.line(M, 34, W - M, 34)
    c.setFillColor(MUTED)
    c.setFont('J5', 8)
    yaz(c, M, 22, 'Netice · ' + T('Kullanım kılavuzu'))
    c.drawRightString(W - M, 22, str(sayfa_no))


def ipucu_kutusu(c, metin, x, y_top, w):
    ic = w - 46
    h = para_h('<b>' + T('İpucu:') + ' </b>' + metin, st_ipucu, ic) + 22
    c.setFillColor(AMBER_BG)
    c.roundRect(x, y_top - h, w, h, 10, stroke=0, fill=1)
    c.setFillColor(AMBER)
    c.roundRect(x, y_top - h, 5, h, 2.5, stroke=0, fill=1)
    # ampul
    c.setFillColor(AMBER)
    c.circle(x + 24, y_top - 20, 8, stroke=0, fill=1)
    c.setFillColor(INK)
    c.setFont('J8', 10)
    c.drawCentredString(x + 24, y_top - 23.5, '!')
    para(c, '<b>' + T('İpucu:') + ' </b>' + metin, st_ipucu, x + 40, y_top - 11, ic)
    return h


def cevir(s):
    s = dict(s)
    if DIL != 'tr' and 'adimlar_diger' in s:
        s['giris'], s['adimlar'] = s['giris_diger'], s['adimlar_diger']
    s['giris'] = T(s['giris'])
    s['adimlar'] = [(k, T(b), T(m)) for k, b, m in s['adimlar']]
    if s.get('ipucu'):
        s['ipucu'] = T(s['ipucu'])
    return s


def menu_sayfasi(c, s, no):
    ust_bant(c, s['bolum'], s['baslik'], no)
    gh = para(c, s['giris'], st_giris, M, H - 84, W - 2 * M)
    tel_w = 190
    olcek, sol, ust = telefon(c, s['ekran'], (W - tel_w) / 2, H - 84 - gh - 20, tel_w)
    tel_alt = ust - SH * olcek
    # Alt menünün büyütülmüş hâli.
    from PIL import Image
    im = Image.open(os.path.join(KARE, s['ekran'] + '.png'))
    k = im.width / SW
    y0, y1 = 676, 752
    kirp = im.crop((0, int(y0 * k), im.width, int(y1 * k)))
    bw = W - 2 * M
    bh = bw * (y1 - y0) / SW
    by = tel_alt - 30 - bh
    c.saveState()
    p = c.beginPath()
    p.roundRect(M, by, bw, bh, 14)
    c.clipPath(p, stroke=0)
    c.drawImage(ImageReader(kirp), M, by, bw, bh)
    c.restoreState()
    c.setStrokeColor(LINE)
    c.roundRect(M, by, bw, bh, 14, stroke=1, fill=0)
    # Telefondaki menüden büyütmeye kılavuz çizgileri.
    c.setStrokeColor(EMERALD)
    c.setDash(3, 3)
    c.setLineWidth(1)
    c.line(sol + 4, tel_alt + 12 * olcek, M + 6, by + bh)
    c.line(sol + SW * olcek - 4, tel_alt + 12 * olcek, W - M - 6, by + bh)
    c.setDash()
    rects = hedefler.get(s['ekran'], {})
    kw = (bw - 4 * 8) / 5
    ky = by - 26
    for i, (anahtar, bas, met) in enumerate(s['adimlar']):
        r = rects.get(anahtar)
        kx = M + i * (kw + 8)
        if r:
            cx = M + (r[0] + r[2] / 2) / SW * bw
            rozet(c, cx, by + bh - 8, i + 1, r=9)
            ok(c, kx + kw / 2, ky + 2, cx, by + 6)
        h = para_h(bas, st_adim_b, kw - 16) + 4 + para_h(met, st_adim, kw - 16) + 18
        c.setFillColor(white)
        c.setStrokeColor(LINE)
        c.roundRect(kx, ky - h, kw, h, 10, stroke=1, fill=1)
        hb = para(c, bas, st_adim_b, kx + 8, ky - 9, kw - 16)
        para(c, met, st_adim, kx + 8, ky - 9 - hb - 4, kw - 16)


def adim_sayfasi(c, s, no):
    s = cevir(s)
    if s.get('menu'):
        return menu_sayfasi(c, s, no)
    ust_bant(c, s['bolum'], s['baslik'], no)
    gh = para(c, s['giris'], st_giris, M, H - 84, W - 2 * M)
    tel_w = 240
    tel_x = M + 10
    tel_ust = H - 84 - gh - 24
    olcek, sol, ust = telefon(c, s['ekran'], tel_x, tel_ust, tel_w)
    tel_alt = ust - SH * olcek

    sag_x = tel_x + tel_w + 46
    sag_w = W - M - sag_x
    rects = hedefler.get(s['ekran'], {})
    adimlar = s['adimlar']

    # Kartların yükseklikleri ve hedeflere göre istenen dikey konumları.
    kartlar = []
    for i, (anahtar, bas, met) in enumerate(adimlar):
        h = para_h(bas, st_adim_b, sag_w - 34) + 4 + para_h(met, st_adim, sag_w - 34) + 18
        r = rects.get(anahtar)
        hy = ust - (r[1] + r[3] / 2) * olcek if r else None
        kartlar.append(dict(i=i + 1, anahtar=anahtar, bas=bas, met=met, h=h, r=r, hy=hy))
    # Kartları hedefin hizasına koy; çakışanları aşağı it, taşanları yukarı çek.
    bosluk = 10
    y = tel_ust
    for k in kartlar:
        istenen = (k['hy'] + 14) if k['hy'] is not None else y
        k['ust'] = min(y, istenen)
        y = k['ust'] - k['h'] - bosluk
    alt_sinir = tel_alt
    if kartlar and kartlar[-1]['ust'] - kartlar[-1]['h'] < alt_sinir:
        fark = alt_sinir - (kartlar[-1]['ust'] - kartlar[-1]['h'])
        for k in reversed(kartlar):
            k['ust'] += fark
            onceki = [x for x in kartlar if x['i'] == k['i'] - 1]
            if onceki and onceki[0]['ust'] - onceki[0]['h'] - bosluk >= k['ust']:
                break
            if onceki:
                fark = k['ust'] + bosluk - (onceki[0]['ust'] - onceki[0]['h'])
                if fark <= 0:
                    break
    # Hedef kutuları ve numaralar (ekran üstünde).
    for k in kartlar:
        if not k['r']:
            continue
        bx, by, bw, bh = hedef_kutusu(c, olcek, sol, ust, k['r'])
        k['hedef'] = (bx, by, bw, bh)
    # Kartlar ve oklar.
    for k in kartlar:
        kx, ky = sag_x, k['ust']
        c.setFillColor(white)
        c.setStrokeColor(LINE)
        c.setLineWidth(0.8)
        c.roundRect(kx, ky - k['h'], sag_w, k['h'], 10, stroke=1, fill=1)
        rozet(c, kx + 17, ky - 17, k['i'], r=9.5)
        hb = para(c, k['bas'], st_adim_b, kx + 32, ky - 9, sag_w - 42)
        para(c, k['met'], st_adim, kx + 32, ky - 9 - hb - 4, sag_w - 42)
        if 'hedef' in k:
            bx, by, bw, bh = k['hedef']
            tx = bx + bw
            ty = by + bh / 2
            # Hedef sağ kenarı ekranın dışına taşıyorsa (geniş düğme) kutunun içine bak.
            tx = min(tx, sol + SW * olcek - 4)
            ok(c, kx - 2, ky - 17, tx + 3, ty)
            rozet(c, max(bx - 6, sol + 2), by + bh + 2, k['i'], r=7.5)
    alt = min(tel_alt, min((k['ust'] - k['h'] for k in kartlar), default=tel_alt))
    if s.get('ipucu'):
        ipucu_kutusu(c, s['ipucu'], M, alt - 26, W - 2 * M)


def kapak(c):
    c.setFillColor(INK)
    c.rect(0, 0, W, H, stroke=0, fill=1)
    for i, a in enumerate([0.05, 0.05, 0.06, 0.07]):
        c.setFillColor(Color(0.06, 0.73, 0.5, alpha=a))
        c.circle(W * 0.88, H * 0.32, 300 - i * 60, stroke=0, fill=1)
    logo = os.path.join(KOK, 'assets', 'icon', 'netice_icon_rounded_1024.png')
    c.setFillColor(white)
    c.roundRect(M, H - 150, 76, 76, 20, stroke=0, fill=1)
    if os.path.exists(logo):
        c.drawImage(ImageReader(logo), M + 6, H - 144, 64, 64, mask='auto')
    c.setFillColor(EMERALD)
    c.setFont('J7', 11)
    yaz(c, M, H - 200, ust(T('Kullanım kılavuzu')))
    c.setFillColor(white)
    c.setFont('J8', 52)
    c.drawString(M, H - 252, 'Netice')
    para(c, T('Optik formu telefonla okuyun; puan, analiz, karne ve raporlar saniyeler içinde. '
              'Bu kılavuz, uygulamayı ilk açılıştan rapor almaya kadar adım adım anlatır.'), st_kapak, M, H - 272, 300)
    telefon(c, '13_sonuclar', W - M - 330, 400, 150)
    telefon(c, '02_ana', W - M - 170, 450, 170)
    c.setFillColor(HexColor('#8C97B8'))
    c.setFont('J5', 9)
    yaz(c, M, 40, T('Sürüm') + ' ' + date.today().strftime('%d.%m.%Y'))
    yaz(c, M, 26, T('İletişim:') + ' bilgi@cooktatlihayat.com')


def icindekiler(c, sayfa_baslari):
    c.setFillColor(IVORY)
    c.rect(0, 0, W, H, stroke=0, fill=1)
    c.setFillColor(INK)
    c.setFont('J8', 26)
    yaz(c, W - M if RTL else M, H - 80, T('İçindekiler'), sag=RTL)
    y = H - 120
    for no, ad in BOLUMLER:
        c.setFillColor(white)
        c.setStrokeColor(LINE)
        c.roundRect(M, y - 32, W - 2 * M, 42, 12, stroke=1, fill=1)
        rozet(c, M + 26, y - 12, no, r=12)
        c.setFillColor(INK)
        c.setFont('J7', 13)
        yaz(c, M + 50, y - 8, T(ad))
        konular = [T(s['baslik']) for s in SAYFALAR if s['bolum'] == no]
        c.setFillColor(MUTED)
        c.setFont('J', 8.5)
        satir = '  ·  '.join(konular)
        while pdfmetrics.stringWidth(gorsel(satir), 'J', 8.5) > W - 2 * M - 110 and len(konular) > 1:
            konular = konular[:-1]
            satir = '  ·  '.join(konular) + '  …'
        yaz(c, M + 50, y - 22, satir)
        c.setFillColor(EMERALD_D)
        c.setFont('J8', 13)
        c.drawRightString(W - M - 16, y - 16, str(sayfa_baslari[no]))
        y -= 50
    # Hızlı başlangıç
    y -= 14
    c.setFillColor(INK)
    c.setFont('J8', 16)
    yaz(c, W - M if RTL else M, y, T('Beş adımda ilk sınavınız'), sag=RTL)
    y -= 18
    adim = [T(a) for a in ['Öğrencileri\nekleyin', 'Sınavı\noluşturun', 'Formu\nyazdırın', 'Kâğıtları\nokutun', 'Raporu\nalın']]
    bw = (W - 2 * M - 4 * 22) / 5
    for i, a in enumerate(adim):
        x = M + i * (bw + 22)
        c.setFillColor(INK if i % 2 == 0 else INK2)
        c.roundRect(x, y - 78, bw, 70, 12, stroke=0, fill=1)
        rozet(c, x + bw / 2, y - 8, i + 1, r=11)
        c.setFillColor(white)
        c.setFont('J7', 10)
        for j, satir in enumerate(a.split('\n')):
            yaz(c, x + bw / 2, y - 42 - j * 13, satir, orta=True)
        if i < 4:
            ok(c, x + bw + 3, y - 43, x + bw + 19, y - 43)


def main():
    from reportlab.pdfgen import canvas
    os.makedirs(os.path.dirname(CIKTI), exist_ok=True)
    c = canvas.Canvas(CIKTI, pagesize=A4)
    c.setTitle('Netice · ' + T('Kullanım kılavuzu'))
    c.setAuthor('Netice')
    # sayfa numaraları: kapak 1, içindekiler 2, bölüm sayfaları 3'ten başlar
    basi = {}
    for i, s in enumerate(SAYFALAR):
        basi.setdefault(s['bolum'], i + 3)
    kapak(c)
    c.showPage()
    icindekiler(c, basi)
    c.showPage()
    for i, s in enumerate(SAYFALAR):
        adim_sayfasi(c, s, i + 3)
        c.showPage()
    c.save()
    print(CIKTI, len(SAYFALAR) + 2, 'sayfa')


if __name__ == '__main__':
    main()
