"""Tanıtım videosunun seslendirmelerini ElevenLabs'tan alır (CI'da).

python3 tool/magaza/seslendir.py <ses_klasoru>

premium.json'da "ses" değeri "elevenlabs" olan her sahne için <ses_klasoru>/<kare>.mp3
yazılır. Ses bir kez üretilir ve "rehber-videolari" sürümüne
magaza_tr_<kare>_<metin-özeti>.mp3 adıyla konur; sonraki çalışmalarda oradan indirilir
(metin değişirse yeniden üretilir). Ses, rehber videolarıyla aynıdır.
"""
import hashlib
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), 'video'))
from seslendir import MODEL, RELEASE, api, voice_id  # noqa: E402


def main(folder):
    os.makedirs(folder, exist_ok=True)
    cfg = json.load(open(os.path.join(HERE, 'premium.json'), encoding='utf-8'))
    vid = None
    for sc in cfg['sahneler']:
        if sc['ses'] != 'elevenlabs':
            continue
        text = sc['metin']
        out = os.path.join(folder, sc['kare'] + '.mp3')
        asset = f"magaza_tr_{sc['kare']}_{hashlib.sha1(text.encode()).hexdigest()[:8]}.mp3"
        if subprocess.run(['gh', 'release', 'download', RELEASE, '-p', asset, '-O', out, '--clobber'],
                          capture_output=True).returncode == 0:
            print('hazır:', asset)
            continue
        if not os.environ.get('ELEVENLABS_API_KEY'):
            sys.exit(f'{asset} yok ve ELEVENLABS_API_KEY tanımlı değil')
        vid = vid or voice_id()
        data = api(f'/text-to-speech/{vid}?output_format=mp3_44100_128', {
            'text': text,
            'model_id': MODEL,
            'voice_settings': {'stability': 0.5, 'similarity_boost': 0.75},
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
