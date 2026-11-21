#!/usr/bin/env python3
"""Koddaki tr('...') çağrılarından ve l10n/_ek.json'daki ek metinlerden l10n/_kaynak.json üretir."""
import glob, json, os, re, sys
sys.path.insert(0, os.path.dirname(__file__))
from l10n_wrap import scan, evaluate  # noqa

keys = set()
for f in glob.glob('lib/**/*.dart', recursive=True):
    if f.endswith('strings.g.dart'):
        continue
    s = open(f, encoding='utf-8').read()
    for st, en, raw, isr, q in scan(s):
        if isr or not re.search(r'\btr\(\s*$', s[max(0, st - 6):st]):
            continue
        v, _ = evaluate(raw[len(q):-len(q)], q)
        keys.add(v)
extra = json.load(open('l10n/_ek.json', encoding='utf-8'))
keys |= set(extra)
json.dump(sorted(keys), open('l10n/_kaynak.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print(len(keys), 'metin')
