"""Bilgisayar tanıtım videosunun sahne metinlerini başka dile çevirir (Claude API).

python3 tool/magaza/masaustu_cevir.py <dil> <çıktı.json>

masaustu.json (Türkçe) → aynı yapıda <dil> metinleri: anlatım ("metin"), afiş
başlığı ("baslik"), bölüm etiketi ("ust"), ekrandaki kısa etiketler ve her etiketin
seslendirmede söylendiği kelime ("kelime": çeviride birebir geçen bir parça).
Bulunamayan kelimeler için Türkçedeki yeri ("oran") yedek olarak kalır.
Çeviri bir kez yapılır: "site-ceviri" sürümüne masaustu_<dil>_<özet>.json olarak
konur ve sonra oradan alınır (Türkçe metin değişirse yeniden çevrilir).
Depoda tool/magaza/masaustu_ceviri/<dil>.json varsa o kullanılır (elle düzeltme).
"""
import copy
import hashlib
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), 'site'))
from cevir import DIL_ADI, MODEL  # noqa: E402

RELEASE = 'site-ceviri'
# Büyük/küçük harfi olan yazı sistemleri: afiş başlıkları büyük harf.
BUYUK_HARF = {'en', 'de', 'fr', 'es', 'it', 'pt', 'ru', 'az', 'id'}

SISTEM = """You localize the narrated promo video of Netice, a desktop and mobile app for teachers and schools
(reads optical answer sheets, question bank, test booklets A-H, exam analysis, report cards, sends results to
parents). Translate from Turkish into {dil} for a short energetic promo voice-over.

Per scene you get: "metin" (voice-over, keep it about as long or shorter so it fits the same time),
"baslik" (poster headline lines; one line index "vurgu" is the highlighted accent line), "ust" (small section
label, e.g. "02 · RESULTS"), and "isaret": short on-screen labels ("etiket", max ~24 characters) with "kelime",
the word or phrase of the voice-over said at the moment the label appears.

Rules:
- Natural, punchy, native {dil}; terms teachers really use.
- "Netice", "Pro", "Windows", "Mac", "PDF", "Word", "WhatsApp", "A–H" stay as they are.
- baslik: 2–3 very short lines (1–2 words each), same count as the Turkish; {harf}
  keep the accent line (vurgu) in normal case; an empty line stays empty.
- ust: keep the leading number and " · ", translate the rest {harf2}.
- Every "kelime" MUST be copied character for character from your translated "metin" (a short phrase
  that appears in it), and should be the phrase that corresponds to the Turkish "kelime".
- "etiketler" / "etiket_kelime" (lists) follow the same rule as etiket / kelime.
"""


def ozet(obj):
    return hashlib.sha1(json.dumps(obj, ensure_ascii=False, sort_keys=True).encode()).hexdigest()[:10]


def cevir(dil, tr):
    import anthropic
    client = anthropic.Anthropic(max_retries=6)
    alanlar = []
    for sc in tr['sahneler']:
        alanlar.append({k: copy.deepcopy(sc[k]) for k in ('kare', 'metin', 'baslik', 'vurgu', 'ust', 'isaret', 'etiketler', 'etiket_kelime')
                        if k in sc})
        for i in alanlar[-1].get('isaret', []):
            i.pop('hedef', None)
    harf = 'write the other lines in CAPITAL letters;' if dil in BUYUK_HARF else ''
    sema = {
        'type': 'object', 'additionalProperties': False, 'required': ['sahneler'],
        'properties': {'sahneler': {'type': 'array', 'items': {
            'type': 'object', 'additionalProperties': False,
            'required': ['kare', 'metin', 'baslik', 'ust', 'isaret', 'etiketler', 'etiket_kelime'],
            'properties': {
                'kare': {'type': 'string'}, 'metin': {'type': 'string'}, 'ust': {'type': 'string'},
                'baslik': {'type': 'array', 'items': {'type': 'string'}},
                'isaret': {'type': 'array', 'items': {'type': 'object', 'additionalProperties': False,
                                                      'required': ['etiket', 'kelime'],
                                                      'properties': {'etiket': {'type': 'string'},
                                                                     'kelime': {'type': 'string'}}}},
                'etiketler': {'type': 'array', 'items': {'type': 'string'}},
                'etiket_kelime': {'type': 'array', 'items': {'type': 'string'}},
            }}}},
    }
    with client.beta.messages.stream(
        model=MODEL, max_tokens=32000,
        betas=['server-side-fallback-2026-07-01'], fallbacks='default',
        system=SISTEM.format(dil=DIL_ADI[dil], harf=harf, harf2='in CAPITAL letters' if harf else ''),
        output_config={'format': {'type': 'json_schema', 'schema': sema}},
        messages=[{'role': 'user', 'content': 'Scenes (Turkish). Missing fields: return empty strings/lists.\n'
                   + json.dumps(alanlar, ensure_ascii=False, indent=1)}],
    ) as stream:
        msg = stream.get_final_message()
    if msg.stop_reason in ('refusal', 'max_tokens'):
        raise SystemExit(f'{dil}: çeviri tamamlanamadı ({msg.stop_reason})')
    gelen = {s['kare']: s for s in json.loads(next(b.text for b in msg.content if b.type == 'text'))['sahneler']}
    out = copy.deepcopy(tr)
    out['dil'] = dil
    for sc in out['sahneler']:
        g = gelen.get(sc['kare'])
        if not g:
            raise SystemExit(f'{dil}: {sc["kare"]} sahnesi çevrilmedi')
        trm = sc['metin']
        sc['metin'] = g['metin']
        if g['baslik']:
            sc['baslik'] = g['baslik'][:len(sc['baslik'])] + [''] * max(0, len(sc['baslik']) - len(g['baslik']))
        if 'ust' in sc and g['ust']:
            sc['ust'] = g['ust']
        for i, s in enumerate(sc.get('isaret', [])):
            s['oran'] = max(0, trm.lower().find(s['kelime'].lower())) / max(1, len(trm))
            if i < len(g['isaret']):
                s['etiket'], s['kelime'] = g['isaret'][i]['etiket'], g['isaret'][i]['kelime']
        if sc.get('etiketler'):
            oran = [max(0, trm.lower().find(k.lower())) / max(1, len(trm)) for k in sc['etiket_kelime']]
            if len(g['etiketler']) == len(sc['etiketler']):
                sc['etiketler'] = g['etiketler']
            if len(g['etiket_kelime']) == len(sc['etiket_kelime']):
                sc['etiket_kelime'] = g['etiket_kelime']
            sc['etiket_oran'] = oran
    return out


def main():
    dil, cikti = sys.argv[1], sys.argv[2]
    tr = json.load(open(os.path.join(HERE, 'masaustu.json'), encoding='utf-8'))
    if dil == 'tr':  # Türkçe: çeviri yok, ayar olduğu gibi
        json.dump(dict(tr, dil='tr'), open(cikti, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
        return
    elle = os.path.join(HERE, 'masaustu_ceviri', f'{dil}.json')
    if os.path.exists(elle):
        json.dump(json.load(open(elle, encoding='utf-8')), open(cikti, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
        print('elle düzeltilmiş çeviri:', elle)
        return
    asset = f'masaustu_v2_{dil}_{ozet(tr)}.json'
    if subprocess.run(['gh', 'release', 'download', RELEASE, '-p', asset, '-O', cikti, '--clobber'],
                      capture_output=True).returncode == 0:
        print('hazır:', asset)
        return
    out = cevir(dil, tr)
    with open(cikti, 'w', encoding='utf-8') as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    tmp = os.path.join(os.path.dirname(os.path.abspath(cikti)), asset)
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    if subprocess.run(['gh', 'release', 'view', RELEASE], capture_output=True).returncode != 0:
        subprocess.run(['gh', 'release', 'create', RELEASE, '--title', 'Site çeviri belleği',
                        '--notes', 'tool/site ve tool/magaza çevirileri.', '--latest=false'], capture_output=True)
    subprocess.run(['gh', 'release', 'upload', RELEASE, tmp, '--clobber'], check=False)
    print('çevrildi:', asset)


if __name__ == '__main__':
    main()
