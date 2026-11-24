"""iPhone imzası için App Store Connect API ile geçici sertifika ve profil.

python3 tool/ios_imza.py hazirla   -> build/imza/ altında anahtar, sertifika, profil
python3 tool/ios_imza.py temizle   -> bu çalışmada oluşturulan profil ve sertifikayı siler

Xcode'un kendi bulut imzası (allowProvisioningUpdates) bu hesapta 401 verdiği
için imza elle yapılır. Her çalışma kendi "Apple Distribution" sertifikasını ve
App Store profilini oluşturur; yükleme bitince ikisini de siler. Hesaptaki
diğer sertifikalara dokunulmaz.

Gerekenler: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, APPLE_TEAM_ID.
"""
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

import jwt

BUNDLE = 'com.netice.netice'
API = 'https://api.appstoreconnect.apple.com/v1'
OUT = 'build/imza'
STATE = os.path.join(OUT, 'durum.json')


def token():
    key = open(os.environ['ASC_KEY_PATH']).read()
    now = int(time.time())
    return jwt.encode({'iss': os.environ['ASC_ISSUER_ID'].strip(), 'iat': now, 'exp': now + 900,
                       'aud': 'appstoreconnect-v1'}, key, algorithm='ES256',
                      headers={'kid': os.environ['ASC_KEY_ID'].strip(), 'typ': 'JWT'})


def call(method, path, body=None):
    req = urllib.request.Request(API + path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={'Authorization': 'Bearer ' + token(), 'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        sys.exit(f'Apple {method} {path} → {e.code}: {e.read().decode()[:800]}')


def hazirla():
    os.makedirs(OUT, exist_ok=True)
    key, csr = f'{OUT}/dagitim.key', f'{OUT}/dagitim.csr'
    subprocess.run(['openssl', 'req', '-new', '-newkey', 'rsa:2048', '-nodes', '-keyout', key, '-out', csr,
                    '-subj', '/CN=Netice CI/C=TR'], check=True, capture_output=True)
    csr_text = ''.join(l for l in open(csr).read().splitlines() if 'CERTIFICATE REQUEST' not in l)
    cert = call('POST', '/certificates', {'data': {'type': 'certificates', 'attributes': {
        'certificateType': 'DISTRIBUTION', 'csrContent': csr_text}}})['data']
    state = {'certificate': cert['id']}
    json.dump(state, open(STATE, 'w'))
    open(f'{OUT}/dagitim.cer', 'wb').write(base64.b64decode(cert['attributes']['certificateContent']))

    bid = call('GET', f'/bundleIds?filter[identifier]={BUNDLE}')['data']
    bid = next(b for b in bid if b['attributes']['identifier'] == BUNDLE)['id']
    name = f'Netice CI {os.environ.get("GITHUB_RUN_ID", int(time.time()))}'
    prof = call('POST', '/profiles', {'data': {'type': 'profiles', 'attributes': {'name': name, 'profileType': 'IOS_APP_STORE'},
                                               'relationships': {
                                                   'bundleId': {'data': {'type': 'bundleIds', 'id': bid}},
                                                   'certificates': {'data': [{'type': 'certificates', 'id': cert['id']}]}}}})['data']
    state['profile'] = prof['id']
    state['name'] = name
    state['uuid'] = prof['attributes']['uuid']
    json.dump(state, open(STATE, 'w'))
    open(f'{OUT}/netice.mobileprovision', 'wb').write(base64.b64decode(prof['attributes']['profileContent']))
    with open(os.environ['GITHUB_ENV'], 'a') as f:
        f.write(f'PROFILE_NAME={name}\nPROFILE_UUID={prof["attributes"]["uuid"]}\n')
    print('Sertifika ve profil hazır:', name)


def temizle():
    if not os.path.exists(STATE):
        return
    state = json.load(open(STATE))
    for kind in ('profile', 'certificate'):
        if state.get(kind):
            req = urllib.request.Request(f'{API}/{kind}s/{state[kind]}', method='DELETE',
                                         headers={'Authorization': 'Bearer ' + token()})
            try:
                urllib.request.urlopen(req, timeout=60)
                print(kind, 'silindi')
            except urllib.error.HTTPError as e:
                print(kind, 'silinemedi:', e.code, e.read().decode()[:300])


def runner_ayarla():
    """Runner hedefinin Release ayarlarını elle imzaya çevirir."""
    p = 'ios/Runner.xcodeproj/project.pbxproj'
    t = open(p).read()
    parts = t.split('isa = XCBuildConfiguration;')
    for i, b in enumerate(parts):
        end = b.find('name = ')
        head = b[:end + 20]
        if f'PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE};' in head and 'name = Release;' in head:
            extra = (f'\n\t\t\t\tCODE_SIGN_STYLE = Manual;'
                     f'\n\t\t\t\tDEVELOPMENT_TEAM = {os.environ["APPLE_TEAM_ID"].strip()};'
                     f'\n\t\t\t\t"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "Apple Distribution";'
                     f'\n\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = "{json.load(open(STATE))["name"]}";')
            parts[i] = b.replace(f'PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE};', f'PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE};' + extra, 1)
            open(p, 'w').write('isa = XCBuildConfiguration;'.join(parts))
            print('Runner Release imza ayarı yazıldı')
            return
    sys.exit('Runner Release yapılandırması bulunamadı')


if __name__ == '__main__':
    {'hazirla': hazirla, 'temizle': temizle, 'runner': runner_ayarla}[sys.argv[1]]()
