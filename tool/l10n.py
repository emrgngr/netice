#!/usr/bin/env python3
"""l10n/<dil>.json çevirilerinden lib/l10n/strings.g.dart üretir ve eksikleri raporlar.
Kullanım: python3 tool/l10n.py"""
import json, os, re

LANGS = ['en', 'az', 'de', 'ar', 'es', 'ru', 'it', 'fr', 'zh', 'ja']
src = json.load(open('l10n/_kaynak.json', encoding='utf-8'))
srcset = set(src)


def dq(s):
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$').replace('\n', '\\n') + "'"


out = ['// Oluşturuldu: tool/l10n.py — elle düzenlemeyin; l10n/*.json dosyalarını düzenleyin.',
       '// ignore_for_file: lines_longer_than_80_chars', '',
       'const Map<String, Map<String, String>> translations = {']
for lang in LANGS:
    path = f'l10n/{lang}.json'
    if not os.path.exists(path):
        print(f'{lang}: dosya yok')
        continue
    tr = json.load(open(path, encoding='utf-8'))
    extra = [k for k in tr if k not in srcset]
    missing = [k for k in src if k not in tr]
    bad = [k for k, v in tr.items() if sorted(re.findall(r'\{\d+\}', k)) != sorted(re.findall(r'\{\d+\}', v))]
    print(f'{lang}: {len(tr) - len(extra)}/{len(src)} çevrildi, eksik {len(missing)}, fazla {len(extra)}, yer tutucu hatası {len(bad)}')
    for b in bad[:5]:
        print('  yer tutucu:', b[:60])
    out.append(f"  '{lang}': {{")
    for k in src:
        if k in tr and tr[k]:
            out.append(f'    {dq(k)}: {dq(tr[k])},')
    out.append('  },')
out.append('};')
open('lib/l10n/strings.g.dart', 'w', encoding='utf-8').write('\n'.join(out) + '\n')
