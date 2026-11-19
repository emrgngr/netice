#!/usr/bin/env python3
"""l10n/work parçalarını denetler: JSON, yer tutucu, eksik sıra."""
import glob, json, re, sys
src = json.load(open('l10n/work/_kaynak_v1.json', encoding='utf-8'))
ok = True
for p in sorted(glob.glob('l10n/work/*.json')):
    try:
        d = json.load(open(p, encoding='utf-8'))
    except Exception as e:
        print(p, 'JSON HATASI', e); ok = False; continue
    for i, v in d.items():
        k = src[int(i)]
        if sorted(re.findall(r'\{\d+\}', k)) != sorted(re.findall(r'\{\d+\}', v)):
            print(p, i, 'yer tutucu:', v[:50]); ok = False
        if k.startswith((' ', '\n')) != v.startswith((' ', '\n')) or k.endswith(' ') != v.endswith(' '):
            print(p, i, 'boşluk:', repr(v[:30]))
    ids = sorted(map(int, d))
    print(p, len(d), ids[0], ids[-1])
sys.exit(0 if ok else 1)
