"""Tanıtım videosunun seslendirmelerini ElevenLabs'tan alır (CI'da).

python3 tool/magaza/seslendir.py <ses_klasoru>

premium.json'da "ses" değeri "elevenlabs" olan her sahne için <ses_klasoru>/<kare>.mp3
yazılır. Ses bir kez üretilir ve "rehber-videolari" sürümüne
magaza_tr_<kare>_<metin-özeti>.mp3 adıyla konur; sonraki çalışmalarda oradan indirilir
(metin değişirse yeniden üretilir).

Ses: eğitimci, enerjik ve net bir kadın sesi. Sırayla: ELEVENLABS_KADIN_VOICE_ID
değişkeni; ElevenLabs ses kütüphanesindeki Türkçe kadın anlatıcı seslerinden
eğitim/anlatım için olanı (hesaba eklenir); yoksa hazır "Alice" sesi
(açık ve anlaşılır eğitimci sesi).
"""
import hashlib
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), 'video'))
from seslendir import MODEL, RELEASE, api  # noqa: E402

ALICE = 'Xb7hH8MSUJpSbSDYk0k2'
SES_ETIKETI = 'kadin_enerjik'
# Kullanıcının onayladığı ses: "Meloxia Turkish Pro" (Türkçe kadın anlatıcı).
SECILI_SES = 'axtmxCPnqPghs9C5SjJ8'


def female_voice_id():
    if os.environ.get('ELEVENLABS_KADIN_VOICE_ID'):
        return os.environ['ELEVENLABS_KADIN_VOICE_ID']
    if SECILI_SES:
        return SECILI_SES
    try:
        q = '/shared-voices?page_size=30&language=tr&gender=female&sort=usage_character_count_1y'
        voices = json.loads(api(q)).get('voices', [])
        def score(v):
            txt = ' '.join(str(v.get(k) or '') for k in ('name', 'description', 'use_case', 'descriptive', 'category')).lower()
            s = 0
            for w, p in (('educat', 5), ('eğitim', 5), ('teacher', 5), ('öğretmen', 5), ('narrat', 3), ('calm', 3), ('sakin', 3), ('clear', 2), ('net', 1), ('professional', 2), ('informative', 3)):
                if w in txt:
                    s += p
            if v.get('age') == 'middle_aged':
                s += 2
            if v.get('accent') in ('standard', 'turkish', 'istanbul'):
                s += 1
            return s
        voices = [v for v in voices if (v.get('gender') or 'female') == 'female']
        if voices:
            best = max(voices, key=score)
            print('kadın ses seçildi:', best.get('name'), best.get('voice_id'), '-', best.get('description'))
            try:
                added = json.loads(api(f"/voices/add/{best['public_owner_id']}/{best['voice_id']}", {'new_name': 'Netice ' + best.get('name', 'Anlatıcı')}))
                return added.get('voice_id', best['voice_id'])
            except Exception as e:  # noqa: BLE001  (zaten ekliyse ya da sınır dolduysa)
                print('ses hesaba eklenemedi, doğrudan denenecek:', e)
                return best['voice_id']
    except Exception as e:  # noqa: BLE001
        print('ses kütüphanesi aranamadı:', e)
    return ALICE


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
        vid = vid or female_voice_id()
        data = api(f'/text-to-speech/{vid}?output_format=mp3_44100_128', {
            'text': text,
            'model_id': MODEL,
            # Enerjik ama net: canlı tonlama, biraz hızlı (kullanıcı 2026-11-25: önceki uykulu çıktı).
            'voice_settings': {'stability': 0.35, 'similarity_boost': 0.8, 'style': 0.5, 'use_speaker_boost': True, 'speed': 1.08},
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
