"""ElevenLabs ile eksik seslendirmeleri üretir (CI'da, video işinden önce).

python3 tool/video/seslendir.py <dil>

ses_<dil>.json ya da kilavuz_ses_<dil>.json içinde dosya adı yerine
"elevenlabs" yazan sahnelerin sesi ElevenLabs'tan alınır ve compose.py'nin
beklediği yere (build/video/audio/<dil>/) yazılır. Her ses bir kez üretilir:
"rehber-videolari" sürümüne ses_<dil>_<sahne>_<özet>.mp3 olarak yüklenir,
sonraki çalışmalarda oradan indirilir (metin değişirse yeniden üretilir).

Gerekenler: ELEVENLABS_API_KEY (GitHub gizli değişkeni). İsteğe bağlı
ELEVENLABS_VOICE_ID; yoksa hesaptaki "Julian" sesi, o da yoksa George.
"""
import hashlib
import json
import os
import subprocess
import sys
import urllib.request

RELEASE = 'rehber-videolari'
MODEL = 'eleven_multilingual_v2'
API = 'https://api.elevenlabs.io/v1'


def api(path, body=None):
    req = urllib.request.Request(API + path, data=json.dumps(body).encode() if body is not None else None,
                                 headers={'xi-api-key': os.environ['ELEVENLABS_API_KEY'], 'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def voice_id():
    if os.environ.get('ELEVENLABS_VOICE_ID'):
        return os.environ['ELEVENLABS_VOICE_ID']
    try:
        for v in json.loads(api('/voices'))['voices']:
            if v['name'].lower().startswith('julian'):
                return v['voice_id']
    except Exception as e:  # noqa: BLE001
        print('ses listesi alınamadı:', e)
    return 'JBFqnCBsd6RMkjVDRZzb'  # George


def main(lang):
    base = json.load(open(f'tool/video/anlatim_{lang}.json', encoding='utf-8'))
    ses = json.load(open(f'tool/video/ses_{lang}.json'))
    order = list(base.keys())
    jobs = []  # (sahne, metin, hedef dosya)
    for i, (k, name) in enumerate(zip(order, ses)):
        if name == 'elevenlabs':
            jobs.append((k, base[k], f'build/video/audio/{lang}/{i:02d}.mp3'))
    kp = f'tool/video/kilavuz_ses_{lang}.json'
    if os.path.exists(kp):
        extra = json.load(open(f'tool/video/kilavuz_anlatim_{lang}.json', encoding='utf-8'))
        for k, name in json.load(open(kp)).items():
            if name == 'elevenlabs':
                jobs.append((k, extra[k], f'build/video/audio/{lang}/{k}.mp3'))
    if not jobs:
        return
    os.makedirs(f'build/video/audio/{lang}', exist_ok=True)
    vid = None
    for k, text, out in jobs:
        tag = hashlib.sha1(text.encode()).hexdigest()[:8]
        asset = f'ses_{lang}_{k}_{tag}.mp3'
        got = subprocess.run(['gh', 'release', 'download', RELEASE, '-p', asset, '-O', out, '--clobber'],
                             capture_output=True).returncode == 0
        if got:
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
        tmp = f'build/video/{asset}'
        with open(tmp, 'wb') as f:
            f.write(data)
        subprocess.run(['gh', 'release', 'upload', RELEASE, tmp, '--clobber'], check=False)
        print('üretildi:', asset)


if __name__ == '__main__':
    main(sys.argv[1])
