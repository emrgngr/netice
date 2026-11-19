#!/usr/bin/env python3
"""l10n/work/<dil>_*.json (kaynak sırası -> çeviri) parçalarını l10n/<dil>.json'a birleştirir.
Kullanım: python3 tool/l10n_merge.py en [az ...]"""
import glob, json, sys

src = json.load(open('l10n/_kaynak.json', encoding='utf-8'))
for lang in sys.argv[1:]:
    out = {}
    for p in sorted(glob.glob(f'l10n/work/{lang}_*.json')):
        for i, v in json.load(open(p, encoding='utf-8')).items():
            out[src[int(i)]] = v
    json.dump(out, open(f'l10n/{lang}.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=0, sort_keys=False)
    print(lang, len(out), '/', len(src))
