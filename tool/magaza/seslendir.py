"""Tanıtım videosunun seslendirmelerini ElevenLabs'tan alır (CI'da).

python3 tool/magaza/seslendir.py <ses_klasoru>

premium.json'da "ses" değeri "elevenlabs" olan her sahne için <ses_klasoru>/<kare>.mp3
yazılır. Ses bir kez üretilir ve "rehber-videolari" sürümüne
magaza_tr_<kare>_<metin-özeti>.mp3 adıyla konur; sonraki çalışmalarda oradan indirilir
(metin değişirse yeniden üretilir).

Ses (kullanıcı 2026-11-25): heyecanlı, enerjik, genç bir erkek sesi. Sırayla:
ELEVENLABS_TANITIM_VOICE_ID değişkeni; SECILI_SES; ElevenLabs ses kütüphanesindeki
Türkçe genç erkek seslerinden reklam/tanıtım için en canlısı; yoksa hazır "Liam"
(genç, enerjik erkek sesi).
"""
import hashlib
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), 'video'))
from seslendir import MODEL, RELEASE, api  # noqa: E402

LIAM = 'TX3LPaxmHKxFdv7VOQHJ'
SES_ETIKETI = 'erkek_genc'
# Önceki onaylı kadın ses: "Meloxia Turkish Pro" axtmxCPnqPghs9C5SjJ8.
# Boşsa kütüphaneden genç, enerjik Türkçe erkek sesi aranır.
SECILI_SES = ''


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


def main(folder):
    os.makedirs(folder, exist_ok=True)
    cfg = json.load(open(os.path.join(HERE, 'premium.json'), encoding='utf-8'))
    vid = None
    for sc in cfg['sahneler']:
        if sc['ses'] != 'elevenlabs':
            continue
        text = sc['metin']
        out = os.path.join(folder, sc['kare'] + '.mp3')
        asset = f"magaza_tr_{SES_ETIKETI}_{sc['kare']}_{hashlib.sha1(text.encode()).hexdigest()[:8]}.mp3"
        if subprocess.run(['gh', 'release', 'download', RELEASE, '-p', asset, '-O', out, '--clobber'],
                          capture_output=True).returncode == 0:
            print('hazır:', asset)
            continue
        if not os.environ.get('ELEVENLABS_API_KEY'):
            sys.exit(f'{asset} yok ve ELEVENLABS_API_KEY tanımlı değil')
        vid = vid or promo_voice_id()
        data = api(f'/text-to-speech/{vid}?output_format=mp3_44100_128', {
            'text': text,
            'model_id': MODEL,
            # Heyecanlı ve enerjik (kullanıcı 2026-11-25: genç erkek sesi): değişken tonlama, biraz hızlı.
            'voice_settings': {'stability': 0.3, 'similarity_boost': 0.8, 'style': 0.6, 'use_speaker_boost': True, 'speed': 1.1},
        })
        with open(out, 'wb') as f:
            f.write(data)
        tmp = os.path.join(folder, asset)
        with open(tmp, 'wb') as f:
            f.write(data)
        subprocess.run(['gh', 'release', 'upload', RELEASE, tmp, '--clobber'], check=False)
        os.remove(tmp)
        print('üretildi:', asset)


if __name__ == '__main__':
    main(sys.argv[1])
