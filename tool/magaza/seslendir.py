"""Tanıtım videosunun seslendirmelerini ElevenLabs'tan alır (CI'da).

python3 tool/magaza/seslendir.py <ses_klasoru> [ayar.json] [ön_ek]

Ayar verilmezse premium.json ve ön ek "magaza_tr" kullanılır. masaustu.json gibi
"ses" alanı olmayan sahneler de seslendirilir; bunlar için ElevenLabs'ın kelime
zamanlamaları da <kare>.json olarak yazılır (ekrandaki okların sesle eş zamanlı
çıkması için).

premium.json'da "ses" değeri "elevenlabs" olan her sahne için <ses_klasoru>/<kare>.mp3
yazılır. Ses bir kez üretilir ve "rehber-videolari" sürümüne
magaza_tr_<kare>_<metin-özeti>.mp3 adıyla konur; sonraki çalışmalarda oradan indirilir
(metin değişirse yeniden üretilir).

Ses (kullanıcı 2026-11-25): heyecanlı, enerjik, genç bir erkek sesi. Sırayla:
ELEVENLABS_TANITIM_VOICE_ID değişkeni; SECILI_SES; ElevenLabs ses kütüphanesindeki
Türkçe genç erkek seslerinden reklam/tanıtım için en canlısı; yoksa hazır "Liam"
(genç, enerjik erkek sesi).
"""
import base64
import hashlib
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), 'video'))
from seslendir import MODEL, RELEASE, api  # noqa: E402

LIAM = 'TX3LPaxmHKxFdv7VOQHJ'
SES_ETIKETI = 'erkek_murat'
# Önceki onaylı kadın ses: "Meloxia Turkish Pro" axtmxCPnqPghs9C5SjJ8.
# Seçili ses: "Murat - Dynamic, Higher and Young" (ana dili Türkçe, genç, enerjik,
# reklam/tanıtım için). Aramanın ilk adayı "Lucas" çok dilli İngilizce bir sesti;
# Türkçe telaffuz için ana dili Türkçe olan ses seçildi. Boş bırakılırsa aranır.
SECILI_SES = 'dgeCtiGkvIwzoR09qzjl'


def promo_voice_id():
    if os.environ.get('ELEVENLABS_TANITIM_VOICE_ID'):
        return os.environ['ELEVENLABS_TANITIM_VOICE_ID']
    if SECILI_SES:
        return SECILI_SES
    try:
        voices = []
        for q in ('/shared-voices?page_size=50&language=tr&gender=male&age=young&sort=usage_character_count_1y',
                  '/shared-voices?page_size=50&language=tr&gender=male&sort=usage_character_count_1y'):
            voices = json.loads(api(q)).get('voices', [])
            voices = [v for v in voices if (v.get('gender') or 'male') == 'male']
            if voices:
                break
        def score(v):
            txt = ' '.join(str(v.get(k) or '') for k in ('name', 'description', 'use_case', 'descriptive', 'category')).lower()
            s = 0
            for w, p in (('energ', 6), ('enerj', 6), ('excit', 6), ('heyecan', 6), ('upbeat', 5), ('dynamic', 4), ('dinamik', 4),
                         ('advert', 5), ('reklam', 5), ('commercial', 4), ('promo', 4), ('social', 3), ('youth', 3), ('genç', 3),
                         ('young', 3), ('cheer', 3), ('lively', 4), ('clear', 1), ('professional', 1)):
                if w in txt:
                    s += p
            if v.get('age') == 'young':
                s += 4
            if v.get('accent') in ('standard', 'turkish', 'istanbul'):
                s += 1
            for w in ('calm', 'sakin', 'deep', 'old', 'whisper', 'meditat', 'asmr', 'sleep'):
                if w in txt:
                    s -= 4
            return s
        for v in sorted(voices, key=score, reverse=True)[:8]:
            print('aday:', score(v), v.get('name'), v.get('voice_id'), v.get('age'), '-', v.get('description'))
        if voices:
            best = max(voices, key=score)
            print('erkek ses seçildi:', best.get('name'), best.get('voice_id'), '-', best.get('description'))
            try:
                added = json.loads(api(f"/voices/add/{best['public_owner_id']}/{best['voice_id']}", {'new_name': 'Netice ' + best.get('name', 'Anlatıcı')}))
                return added.get('voice_id', best['voice_id'])
            except Exception as e:  # noqa: BLE001  (zaten ekliyse ya da sınır dolduysa)
                print('ses hesaba eklenemedi, doğrudan denenecek:', e)
                return best['voice_id']
    except Exception as e:  # noqa: BLE001
        print('ses kütüphanesi aranamadı:', e)
    return LIAM


def _indir(asset, out):
    return subprocess.run(['gh', 'release', 'download', RELEASE, '-p', asset, '-O', out, '--clobber'],
                          capture_output=True).returncode == 0


def _yukle(folder, asset, data):
    tmp = os.path.join(folder, asset)
    with open(tmp, 'wb') as f:
        f.write(data)
    subprocess.run(['gh', 'release', 'upload', RELEASE, tmp, '--clobber'], check=False)
    os.remove(tmp)


def main(folder, ayar='premium.json', on_ek='magaza_tr'):
    os.makedirs(folder, exist_ok=True)
    cfg = json.load(open(ayar if os.path.isabs(ayar) or os.path.exists(ayar) else os.path.join(HERE, ayar), encoding='utf-8'))
    vid = None
    # Heyecanlı ve enerjik (kullanıcı 2026-11-25: genç erkek sesi): değişken tonlama, biraz hızlı.
    ayarlar = {'stability': 0.3, 'similarity_boost': 0.8, 'style': 0.6, 'use_speaker_boost': True, 'speed': 1.1}
    for sc in cfg['sahneler']:
        if sc.get('ses', 'elevenlabs') != 'elevenlabs':
            continue
        text = sc['metin']
        zaman = 'ses' not in sc  # yeni ayar dosyaları kelime zamanlamasını da ister
        out = os.path.join(folder, sc['kare'] + '.mp3')
        asset = f"{on_ek}_{SES_ETIKETI}_{sc['kare']}_{hashlib.sha1(text.encode()).hexdigest()[:8]}.mp3"
        zasset = asset[:-4] + '.json'
        if _indir(asset, out) and (not zaman or _indir(zasset, os.path.join(folder, sc['kare'] + '.json'))):
            print('hazır:', asset)
            continue
        if not os.environ.get('ELEVENLABS_API_KEY'):
            sys.exit(f'{asset} yok ve ELEVENLABS_API_KEY tanımlı değil')
        vid = vid or promo_voice_id()
        body = {'text': text, 'model_id': MODEL, 'voice_settings': ayarlar}
        if zaman:
            r = json.loads(api(f'/text-to-speech/{vid}/with-timestamps?output_format=mp3_44100_128', body))
            data = base64.b64decode(r['audio_base64'])
            hiza = json.dumps(r.get('alignment') or r.get('normalized_alignment') or {}, ensure_ascii=False).encode()
            with open(os.path.join(folder, sc['kare'] + '.json'), 'wb') as f:
                f.write(hiza)
            _yukle(folder, zasset, hiza)
        else:
            data = api(f'/text-to-speech/{vid}?output_format=mp3_44100_128', body)
        with open(out, 'wb') as f:
            f.write(data)
        _yukle(folder, asset, data)
        print('üretildi:', asset)


if __name__ == '__main__':
    main(*sys.argv[1:4])
