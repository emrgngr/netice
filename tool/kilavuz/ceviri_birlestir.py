"""Kılavuz çevirilerini birleştirir.

python3 tool/kilavuz/ceviri_birlestir.py <dil> <numaralı.json> <kaynak_listesi.json>
Numaralı dosya {"1": "çeviri", ...}; kaynak listesi Türkçe metinlerin sırası.
Uygulamanın l10n/<dil>.json çevirileri (kısa düğme adları) de eklenir, böylece
kılavuz ekran görüntüleriyle aynı adları kullanır.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from icerik import BOLUMLER, SAYFALAR  # noqa: E402

KOK = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
dil, numarali, liste = sys.argv[1:4]
kaynak = json.load(open(liste, encoding='utf-8'))
ceviri = json.load(open(numarali, encoding='utf-8'))
uyg = json.load(open(os.path.join(KOK, 'l10n', f'{dil}.json'), encoding='utf-8'))
out = {}
for i, tr in enumerate(kaynak, 1):
    if str(i) in ceviri:
        out[tr] = ceviri[str(i)]


def gerekli():
    for _, a in BOLUMLER:
        yield a
    for s in SAYFALAR:
        yield s['baslik']
        giris, adimlar = s['giris'], s['adimlar']
        if 'adimlar_diger' in s:
            giris, adimlar = s['giris_diger'], s['adimlar_diger']
        yield giris
        for _, b, m in adimlar:
            yield b
            yield m
        if s.get('ipucu'):
            yield s['ipucu']
    yield from SABIT


SABIT = ['BÖLÜM', 'Kullanım kılavuzu', 'İpucu:', 'Sürüm', 'İletişim:', 'İçindekiler', 'Beş adımda ilk sınavınız',
         'Optik formu telefonla okuyun; puan, analiz, karne ve raporlar saniyeler içinde. '
         'Bu kılavuz, uygulamayı ilk açılıştan rapor almaya kadar adım adım anlatır.',
         'Öğrencileri\nekleyin', 'Sınavı\noluşturun', 'Formu\nyazdırın', 'Kâğıtları\nokutun', 'Raporu\nalın']


eksik = []
for k in gerekli():
    if k not in out:
        if k in uyg:
            out[k] = uyg[k]
        else:
            eksik.append(k)
yol = os.path.join(os.path.dirname(__file__), 'ceviri', f'{dil}.json')
os.makedirs(os.path.dirname(yol), exist_ok=True)
json.dump(out, open(yol, 'w', encoding='utf-8'), ensure_ascii=False, indent=1, sort_keys=True)
print(dil, len(out), 'metin', 'EKSİK:' if eksik else '', *eksik)
