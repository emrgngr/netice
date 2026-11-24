#!/usr/bin/env python3
"""l10n/work/<dil>_*.json (kaynak sırası -> çeviri) parçalarını l10n/<dil>.json'a birleştirir.
Kullanım: python3 tool/l10n_merge.py en [az ...]"""
import glob, json, os, sys

# Parça dosyalarındaki sıra numaraları, çeviri yapılırken kullanılan kaynak listesine göredir.
# 2026-11'de eklenen diller (pt, hi, id, ko) _kaynak_v2.json sırasıyla çevrildi: <dil>_v2_*.json.
src = json.load(open('l10n/work/_kaynak_v1.json', encoding='utf-8'))
src2 = json.load(open('l10n/work/_kaynak_v2.json', encoding='utf-8'))
for lang in sys.argv[1:]:
    out = {}
    for p in sorted(glob.glob(f'l10n/work/{lang}_*.json')):
        if os.path.basename(p).startswith('ek_'):
            continue
        table = src2 if '_v2_' in p else src
        for i, v in json.load(open(p, encoding='utf-8')).items():
            out[table[int(i)]] = v
    ek = f'l10n/work/ek_{lang}.json'  # sonradan eklenen metinler (Türkçe anahtarla)
    if os.path.exists(ek):
        out.update(json.load(open(ek, encoding='utf-8')))
    json.dump(out, open(f'l10n/{lang}.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=0, sort_keys=False)
    print(lang, len(out))
