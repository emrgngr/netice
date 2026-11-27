"""neticeoptik.com'u 15 dilde yayına hazırlar (otomatik çeviri).

python3 tool/site/cevir.py <kaynak: web-sitesi> <çıktı: build/site> [dil ...]

Sitenin asıl metni Türkçedir (web-sitesi/*.html). Bu betik:
  1. Her Türkçe sayfanın metinlerini (başlıklar, paragraflar, düğmeler, görsel
     açıklamaları, sayfa açıklaması) parça parça ayıklar.
  2. Çeviri belleğinde olmayan parçaları Claude API ile çevirir (ANTHROPIC_API_KEY).
     Bellek: tool/site/ceviri/<dil>.json (depoda) + "site-ceviri" sürümündeki
     site_ceviri_<dil>.json (CI her yayında günceller). Böylece Türkçe sayfa
     değişince yalnız değişen cümleler yeniden çevrilir; diğer diller kendiliğinden
     güncellenir.
  3. <çıktı>/<dil>/<sayfa>.html sayfalarını yazar: lang/dir, dil menüsü,
     hreflang bağlantıları, dile uygun yazı tipi, o dildeki videolar.
  4. Türkçe sayfalara ziyaretçinin tarayıcı diline göre otomatik yönlendirme ekler
     (ziyaretçi menüden dil seçerse seçimi hatırlanır).

Örnek belgeler: <çıktı>/img/raporlar/<dil>/<ad>.jpg ve <çıktı>/belgeler/<dil>/<ad>.pdf varsa
o dilin sayfası onları gösterir (tool/site/ornek_raporlar.sh); yoksa Türkçeleri kalır.
Kılavuz: <çıktı>/kilavuz/Netice_Kullanim_Kilavuzu_<dil>.pdf (kilavuz-pdf.yml sürümünden).

Videolar: <çıktı>/video/<dil>/telefon.mp4 ve bilgisayar.mp4 (ve .jpg kapakları)
varsa o dilin sayfası onları gösterir; yoksa Türkçe videolar kalır.
"""
import concurrent.futures as cf
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

from bs4 import BeautifulSoup, NavigableString, Tag

HERE = os.path.dirname(os.path.abspath(__file__))
BELLEK = os.path.join(HERE, 'ceviri')
SITE = 'https://www.neticeoptik.com'
RELEASE = 'site-ceviri'
KILAVUZ_SURUM = 'https://github.com/emrgngr/netice/releases/download/kilavuz-pdf'
MODEL = 'claude-opus-5-5'

# (kod, menüde görünen ad, çeviri isteminde dilin adı)
DILLER = [
    ('tr', 'Türkçe', 'Turkish'),
    ('en', 'English', 'English'),
    ('de', 'Deutsch', 'German'),
    ('fr', 'Français', 'French'),
    ('es', 'Español', 'Spanish'),
    ('it', 'Italiano', 'Italian'),
    ('pt', 'Português', 'Brazilian Portuguese'),
    ('ru', 'Русский', 'Russian'),
    ('ar', 'العربية', 'Modern Standard Arabic'),
    ('az', 'Azərbaycanca', 'Azerbaijani (Latin script)'),
    ('zh', '中文', 'Simplified Chinese'),
    ('ja', '日本語', 'Japanese'),
    ('ko', '한국어', 'Korean'),
    ('hi', 'हिन्दी', 'Hindi'),
    ('id', 'Bahasa Indonesia', 'Indonesian'),
]
KODLAR = [d[0] for d in DILLER]
AD = {d[0]: d[1] for d in DILLER}
DIL_ADI = {d[0]: d[2] for d in DILLER}

# Plus Jakarta Sans'ın içermediği yazı sistemleri için Google Fonts yedeği.
YAZI_TIPI = {
    'ru': 'Noto+Sans:wght@400;500;600;700;800',
    'ar': 'Noto+Sans+Arabic:wght@400;500;600;700;800',
    'hi': 'Noto+Sans+Devanagari:wght@400;500;600;700;800',
    'zh': 'Noto+Sans+SC:wght@400;500;700;900',
    'ja': 'Noto+Sans+JP:wght@400;500;700;900',
    'ko': 'Noto+Sans+KR:wght@400;500;700;900',
}
YAZI_ADI = {'ru': 'Noto Sans', 'ar': 'Noto Sans Arabic', 'hi': 'Noto Sans Devanagari',
            'zh': 'Noto Sans SC', 'ja': 'Noto Sans JP', 'ko': 'Noto Sans KR'}

BLOK = {'address', 'article', 'aside', 'blockquote', 'details', 'dialog', 'dd', 'div', 'dl', 'dt', 'fieldset',
        'figcaption', 'figure', 'footer', 'form', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'header', 'hr', 'li', 'main',
        'nav', 'ol', 'p', 'pre', 'section', 'summary', 'table', 'tbody', 'thead', 'tfoot', 'tr', 'td', 'th', 'ul',
        'video', 'picture', 'select', 'option', 'label', 'body', 'html', 'head'}
ATLA = {'script', 'style', 'svg', 'code', 'noscript', 'template', 'source', 'link'}
OZNITELIK = ('alt', 'title', 'aria-label', 'placeholder', 'data-ok', 'data-label', 'data-sel')
META = {'description', 'og:title', 'og:description', 'twitter:title', 'twitter:description'}
HARF = re.compile(r'[^\W\d_]', re.UNICODE)
MARKA = re.compile(r'^(Netice|Netice Pro|Pro|[\w.+-]+@[\w.-]+|www\.[\w.-]+|[\w.-]+\.com)$')


def ozet(s):
    return hashlib.sha1(s.encode('utf-8')).hexdigest()[:16]


def sade(s):
    return re.sub(r'\s+', ' ', s).strip()


def cevrilir(metin):
    duz = sade(re.sub(r'<[^>]+>', ' ', metin))
    return len(HARF.findall(duz)) >= 2 and not MARKA.match(duz)


# ------------------------------------------------------------------ ayıklama

def gizli(el):
    for p in [el] + list(el.parents):
        if isinstance(p, Tag) and (p.get('aria-hidden') == 'true' or p.get('translate') == 'no'
                                   or 'notranslate' in (p.get('class') or [])):
            return True
    return False


def bolum_mu(el):
    """Yalnız satır içi öğeler içeren, metni olan öğe: tek parça olarak çevrilir."""
    if el.name in ATLA or el.name in ('html', 'head', 'body'):
        return False
    if not cevrilir(el.get_text(' ')):
        return False
    return not any(isinstance(d, Tag) and d.name in BLOK for d in el.descendants)


def parcalar(soup):
    """(tür, düğüm, ek, türkçe) listesi. tür: 'ic' (innerHTML), 'yazi' (düz metin), 'oz' (öznitelik)."""
    out = []

    def gez(el):
        for c in list(el.children):
            if isinstance(c, Tag):
                if c.name in ATLA or gizli(c):
                    continue
                if bolum_mu(c):
                    out.append(('ic', c, None, sade(c.decode_contents())))
                else:
                    gez(c)
            elif isinstance(c, NavigableString) and type(c) is NavigableString:
                if cevrilir(str(c)):
                    out.append(('yazi', c, None, sade(str(c))))

    if soup.title and soup.title.string and cevrilir(soup.title.string):
        out.append(('yazi', soup.title.string, None, sade(soup.title.string)))
    for m in soup.find_all('meta'):
        if (m.get('name') in META or m.get('property') in META) and m.get('content') and cevrilir(m['content']):
            out.append(('oz', m, 'content', sade(m['content'])))
    gez(soup.body)
    for el in soup.body.find_all(True):
        if el.name in ATLA and el.name != 'code':
            continue
        if gizli(el) and el.name != 'img':
            continue
        for a in OZNITELIK:
            v = el.get(a)
            if v and cevrilir(v) and not (el.name == 'img' and gizli(el)):
                out.append(('oz', el, a, sade(v)))
    return out


# Etiketleri kısa işaretlere çevirir: <a href=...>x</a> → <t1>x</t1>; çeviri sonrası geri koyar.
ETIKET = re.compile(r'<(/?)([a-zA-Z][\w-]*)([^>]*?)(/?)>')
BOS = {'img', 'br', 'wbr', 'hr', 'input', 'source'}


def maskele(html):
    harita, yigin, n = {}, [], [0]

    def r(m):
        kapan, ad, oz, bos = m.group(1), m.group(2).lower(), m.group(3), m.group(4)
        if kapan:
            k = yigin.pop() if yigin else 'x'
            return f'</{k}>'
        n[0] += 1
        k = f't{n[0]}'
        harita[k] = (ad, oz)
        if ad in BOS or bos:
            return f'<{k}/>'
        yigin.append(k)
        return f'<{k}>'
    return ETIKET.sub(r, html), harita


def maske_ac(metin, harita):
    def r(m):
        kapan, k, bos = m.group(1), m.group(2), m.group(4)
        if k not in harita:
            return ''
        ad, oz = harita[k]
        if kapan:
            return f'</{ad}>'
        return f'<{ad}{oz}>' if not bos and ad not in BOS else f'<{ad}{oz}>'
    return ETIKET.sub(r, metin)


def etiketler(s):
    return sorted(re.findall(r'</?t\d+/?>', s))


# ------------------------------------------------------------------ çeviri belleği

def bellek_yukle(dil, kat):
    """Sürümdeki bellek + depodaki elle düzeltmeler (depodaki kazanır)."""
    b = {}
    if kat:
        hedef = os.path.join(kat, f'site_ceviri_{dil}.json')
        if os.path.exists(hedef):
            b.update(json.load(open(hedef, encoding='utf-8')))
    yol = os.path.join(BELLEK, f'{dil}.json')
    if os.path.exists(yol):
        b.update(json.load(open(yol, encoding='utf-8')))
    return b


def surumden_indir(kat):
    os.makedirs(kat, exist_ok=True)
    if not os.environ.get('GH_TOKEN'):
        return
    subprocess.run(['gh', 'release', 'download', RELEASE, '-p', 'site_ceviri_*.json', '-D', kat, '--clobber'],
                   capture_output=True)


def surume_yukle(yollar):
    if not os.environ.get('GH_TOKEN') or not yollar:
        return
    if subprocess.run(['gh', 'release', 'view', RELEASE], capture_output=True).returncode != 0:
        subprocess.run(['gh', 'release', 'create', RELEASE, '--title', 'Site çeviri belleği',
                        '--notes', 'tool/site/cevir.py tarafından güncellenir.', '--latest=false'], capture_output=True)
    subprocess.run(['gh', 'release', 'upload', RELEASE, *yollar, '--clobber'], check=False)


SISTEM = """You translate the website of Netice, an app for teachers and schools: it reads optical answer sheets
(bubble sheets) with the phone camera or from scanned PDFs, builds question banks and test booklets, and makes
exam analyses and report cards. You translate from Turkish into {dil}.

Rules:
- Write natural, fluent, persuasive marketing text the way a native teacher-facing website in {dil} would read.
  Use the terms teachers in that language really use (e.g. "answer sheet", "report card", "item analysis").
- Keep "Netice", "Netice Pro", "Pro", e-mail addresses, web addresses, numbers, prices and currency exactly
  as they are (prices stay in TL; the site states that stores show local prices).
- Where the Turkish text names something only Turkey has (e.g. e-Okul, KVKK, T.C. Kaymakamlığı),
  keep the name and, if it helps a foreign reader, add a short explanation or the general equivalent.
- Markup tokens like <t1>, </t1> and <t2/> must all appear in your translation, each exactly once,
  correctly nested, around the words they belong to. Never add other tags.
- Keep it about as long as the original; button and menu labels must stay short.
- Return every id exactly once."""


def cevir_toplu(dil, istekler):
    """istekler: [(id, maskeli türkçe)] → {id: çeviri}"""
    import anthropic
    client = anthropic.Anthropic(max_retries=6)
    sema = {
        'type': 'object',
        'properties': {'ceviriler': {'type': 'array', 'items': {
            'type': 'object',
            'properties': {'id': {'type': 'string'}, 'metin': {'type': 'string'}},
            'required': ['id', 'metin'], 'additionalProperties': False}}},
        'required': ['ceviriler'], 'additionalProperties': False,
    }
    with client.beta.messages.stream(
        model=MODEL,
        max_tokens=64000,
        betas=['server-side-fallback-2026-07-01'],
        fallbacks='default',
        system=SISTEM.format(dil=DIL_ADI[dil]),
        output_config={'format': {'type': 'json_schema', 'schema': sema}},
        messages=[{'role': 'user', 'content': 'Translate each "tr" into ' + DIL_ADI[dil] + '. Return JSON.\n\n'
                   + json.dumps([{'id': i, 'tr': t} for i, t in istekler], ensure_ascii=False, indent=0)}],
    ) as stream:
        msg = stream.get_final_message()
    if msg.stop_reason == 'refusal':
        raise RuntimeError(f'{dil}: çeviri reddedildi')
    if msg.stop_reason == 'max_tokens':
        raise RuntimeError(f'{dil}: yanıt yarıda kesildi')
    text = next(b.text for b in msg.content if b.type == 'text')
    return {c['id']: c['metin'] for c in json.loads(text)['ceviriler']}


def eksikleri_cevir(dil, bellek, turkce):
    """turkce: {özet: türkçe}. Eksikleri çevirip belleğe ekler; eklenen sayısını döndürür."""
    eksik = [(k, t) for k, t in turkce.items() if k not in bellek or bellek[k].get('tr') != t]
    if not eksik:
        return 0
    if not os.environ.get('ANTHROPIC_API_KEY'):
        print(f'{dil}: {len(eksik)} çevrilmemiş parça var, ANTHROPIC_API_KEY yok; Türkçe kalacak')
        return 0
    maske = {k: maskele(t) for k, t in eksik}
    gruplar = [eksik[i:i + 60] for i in range(0, len(eksik), 60)]
    eklenen = 0
    for g in gruplar:
        for deneme in range(3):
            try:
                sonuc = cevir_toplu(dil, [(k, maske[k][0]) for k, _ in g])
                break
            except Exception as e:  # noqa: BLE001
                print(f'{dil}: deneme {deneme + 1} başarısız: {e}')
                sonuc = {}
        for k, t in g:
            c = sonuc.get(k)
            if c is None or etiketler(c) != etiketler(maske[k][0]):
                print(f'{dil}: işaretler tutmadı, Türkçe kaldı: {t[:60]}')
                continue
            bellek[k] = {'tr': t, 'c': maske_ac(c, maske[k][1])}
            eklenen += 1
    return eklenen


# ------------------------------------------------------------------ sayfa üretimi

def goreli_mi(u):
    return u and not re.match(r'^([a-z]+:|/|#|\?)', u)


def dil_menusu(soup, sayfa, dil):
    det = soup.new_tag('details', attrs={'class': 'dil'})
    sm = soup.new_tag('summary', attrs={'aria-label': 'Dil / Language'})
    sm.append(BeautifulSoup('<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="none" '
                            'stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3'
                            'c2.5 2.6 3.8 5.6 3.8 9s-1.3 6.4-3.8 9c-2.5-2.6-3.8-5.6-3.8-9S9.5 5.6 12 3z"/></svg>',
                            'html.parser'))
    kisa = soup.new_tag('span')
    kisa.string = dil.upper()
    sm.append(kisa)
    det.append(sm)
    ul = soup.new_tag('ul')
    for k in KODLAR:
        li = soup.new_tag('li')
        a = soup.new_tag('a', attrs={'href': ('/' if k == 'tr' else f'/{k}/') + sayfa, 'hreflang': k, 'lang': k,
                                     'data-dil': k})
        if k == dil:
            a['aria-current'] = 'true'
        a.string = AD[k]
        li.append(a)
        ul.append(li)
    det.append(ul)
    return det


YONLENDIR = """(function(){try{var D=%s,k='netice-dil',s=localStorage.getItem(k),r=document.referrer||'';
if(s||r.indexOf(location.host)>=0||/bot|crawl|spider|slurp|google|bing|yandex|lighthouse|headless/i.test(navigator.userAgent))return;var w='en',L=navigator.languages||[navigator.language||''];
for(var i=0;i<L.length;i++){var c=(L[i]||'').toLowerCase().split('-')[0];if(D.indexOf(c)>=0){w=c;break}}
if(w!=='tr'){var p=location.pathname.split('/').pop()||'index.html';location.replace('/'+w+'/'+p+location.hash)}}catch(e){}})();"""
SECIM = """document.addEventListener('click',function(e){var a=e.target.closest&&e.target.closest('[data-dil]');
if(a){try{localStorage.setItem('netice-dil',a.getAttribute('data-dil'))}catch(x){}}});"""


def sayfa_yaz(kaynak_html, sayfa, dil, bellek, cikti):
    soup = BeautifulSoup(kaynak_html, 'html.parser')
    kok = '' if dil == 'tr' else '../'
    if dil != 'tr':
        for kind, node, attr, tr in parcalar(soup):
            k = ozet(tr)
            c = bellek.get(k, {}).get('c')
            if not c or bellek[k].get('tr') != tr:
                continue
            if kind == 'ic':
                node.clear()
                for ch in list(BeautifulSoup(c, 'html.parser').contents):
                    node.append(ch)
            elif kind == 'yazi':
                node.replace_with(NavigableString(c))
            else:
                node[attr] = c
        # Göreli dosya yolları bir üst klasöre (sayfalar arası bağlantılar dil klasöründe kalır).
        for el in soup.find_all(True):
            for a in ('src', 'href', 'poster', 'srcset'):
                v = el.get(a)
                if v and goreli_mi(v) and not re.match(r'^[\w-]+\.html([#?].*)?$', v):
                    el[a] = kok + v
        # Google Play / App Store rozetleri o dilin resmî rozetiyle (assets/badges; yoksa İngilizce).
        for im in soup.find_all('img'):
            m = re.search(r'img/(google_play|app_store)_tr\.(png|svg)$', im.get('src', ''))
            if m:
                im['src'] = kok + 'img/' + rozet(cikti, m.group(1), m.group(2), dil)
        # O dilin videoları varsa onları göster.
        for v in soup.find_all('video'):
            ad = {'tel': 'telefon', 'pc': 'bilgisayar'}.get(v.get('data-video-panel'))
            if ad and os.path.exists(os.path.join(cikti, 'video', dil, ad + '.mp4')):
                v['poster'] = f'../video/{dil}/{ad}.jpg' if os.path.exists(os.path.join(cikti, 'video', dil, ad + '.jpg')) else v.get('poster')
                for s in v.find_all('source'):
                    s['src'] = f'../video/{dil}/{ad}.mp4'
                if ad == 'telefon':
                    v['class'] = (v.get('class') or []) + ['dikey']
    # Örnek raporlar: o dilde üretilmiş görsel varsa onu göster (ornek_raporlar.sh);
    # yalnız bir ülkeye ait kartlar (ör. e-Okul) diğer dillerde kaldırılır.
    for el in soup.find_all(attrs={'data-yalniz': True}):
        if dil not in el['data-yalniz'].split():
            el.decompose()
    for el in soup.find_all(True):
        for a in ('src', 'href', 'data-paylas'):
            v = el.get(a) or ''
            # img/raporlar/<ad>.jpg ve belgeler/<ad>.pdf|docx|csv: o dilin klasörü varsa onu kullan.
            m = re.search(r'(img/raporlar|belgeler)/([\w-]+\.\w+)$', v)
            if m and os.path.exists(os.path.join(cikti, m.group(1), dil, m.group(2))):
                el[a] = f'{kok}{m.group(1)}/{dil}/{m.group(2)}'
            # Kullanım kılavuzu: kilavuz-pdf sürümünden indirilen o dilin PDF'i ve kapağı;
            # sitede yoksa doğrudan GitHub sürümünden.
            m = re.search(r'kilavuz/Netice_Kullanim_Kilavuzu_tr\.pdf$', v)
            if m:
                ad = f'Netice_Kullanim_Kilavuzu_{dil}.pdf'
                el[a] = (f'{kok}kilavuz/{ad}' if os.path.exists(os.path.join(cikti, 'kilavuz', ad))
                         else f'{KILAVUZ_SURUM}/{ad}')
            if re.search(r'img/kilavuz_kapak\.jpg$', v) and os.path.exists(os.path.join(cikti, 'kilavuz', f'kapak_{dil}.jpg')):
                el[a] = f'{kok}kilavuz/kapak_{dil}.jpg'
    html = soup.html
    html['lang'] = dil
    if dil == 'ar':
        html['dir'] = 'rtl'
    head = soup.head
    # Arama motorları için: bu sayfanın kendi adresi ve dil karşılıkları.
    def adres(k):
        return SITE + ('/' if k in ('tr', 'x-default') else f'/{k}/') + ('' if sayfa == 'index.html' else sayfa)
    head.append(soup.new_tag('link', attrs={'rel': 'canonical', 'href': adres(dil)}))
    for k in KODLAR + ['x-default']:
        link = soup.new_tag('link', attrs={'rel': 'alternate', 'hreflang': k, 'href': adres(k)})
        head.append(link)
    if dil in YAZI_TIPI:
        head.append(soup.new_tag('link', attrs={'rel': 'stylesheet',
                                                'href': f'https://fonts.googleapis.com/css2?family={YAZI_TIPI[dil]}&display=swap'}))
        st = soup.new_tag('style')
        aile = f'"Plus Jakarta Sans", "{YAZI_ADI[dil]}", system-ui, sans-serif'
        st.string = f':root{{--display:{aile};--body:{aile}}} h1,h2,h3{{letter-spacing:0}}'
        head.append(st)
    sc = soup.new_tag('script')
    sc.string = (YONLENDIR % json.dumps(KODLAR) if dil == 'tr' else '') + SECIM
    head.append(sc)
    wrap = soup.select_one('header.nav .wrap')
    if wrap:
        wrap.append(dil_menusu(soup, sayfa, dil))
    hedef = os.path.join(cikti, '' if dil == 'tr' else dil, sayfa)
    os.makedirs(os.path.dirname(hedef), exist_ok=True)
    with open(hedef, 'w', encoding='utf-8') as f:
        f.write(str(soup))


ROZETLER = os.path.join(HERE, '..', '..', 'assets', 'badges')


def rozet(cikti, ad, uzanti, dil):
    """Resmî mağaza rozetini (uygulamadaki assets/badges) sitenin img klasörüne koyar."""
    for d in (dil, 'en'):
        dosya = f'{ad}_{d}.{uzanti}'
        yol = os.path.join(ROZETLER, dosya)
        if os.path.exists(yol):
            hedef = os.path.join(cikti, 'img', dosya)
            if not os.path.exists(hedef):
                shutil.copyfile(yol, hedef)
            return dosya
    return f'{ad}_tr.{uzanti}'


def main():
    kaynak, cikti = sys.argv[1], sys.argv[2]
    diller = [d for d in (sys.argv[3:] or KODLAR) if d != 'tr']
    if os.path.abspath(kaynak) != os.path.abspath(cikti):
        # Önceden konmuş dil videolarını koru, gerisini kaynaktan kopyala.
        shutil.copytree(kaynak, cikti, dirs_exist_ok=True, ignore=shutil.ignore_patterns('BENIOKU.md'))
    # google*.html: Google Search Console doğrulama dosyası; olduğu gibi kopyalanır, çevrilmez.
    sayfalar = sorted(f for f in os.listdir(kaynak) if f.endswith('.html') and not f.startswith('google'))
    kaynaklar = {s: open(os.path.join(kaynak, s), encoding='utf-8').read() for s in sayfalar}
    turkce = {}
    for s in sayfalar:
        for _, _, _, tr in parcalar(BeautifulSoup(kaynaklar[s], 'html.parser')):
            turkce[ozet(tr)] = tr
    print(f'{len(sayfalar)} sayfa, {len(turkce)} çevrilecek parça')
    kat = os.path.join(cikti, '..', '_site_ceviri')
    surumden_indir(kat)
    bellekler = {d: bellek_yukle(d, kat) for d in diller}
    with cf.ThreadPoolExecutor(max_workers=5) as ex:
        sayilar = dict(zip(diller, ex.map(lambda d: eksikleri_cevir(d, bellekler[d], turkce), diller)))
    guncel = []
    for d in diller:
        # Bellekte yalnız sitede hâlâ geçen parçalar kalsın.
        bellekler[d] = {k: v for k, v in bellekler[d].items() if k in turkce}
        yol = os.path.join(kat, f'site_ceviri_{d}.json')
        with open(yol, 'w', encoding='utf-8') as f:
            json.dump(bellekler[d], f, ensure_ascii=False, indent=1, sort_keys=True)
        if sayilar[d]:
            guncel.append(yol)
        eksik = sum(1 for k in turkce if k not in bellekler[d])
        print(f'{d}: {sayilar[d]} yeni çeviri, {eksik} eksik')
    surume_yukle(guncel)
    for s in sayfalar:
        sayfa_yaz(kaynaklar[s], s, 'tr', {}, cikti)
        for d in diller:
            sayfa_yaz(kaynaklar[s], s, d, bellekler[d], cikti)
    print('yazıldı:', cikti)


if __name__ == '__main__':
    main()
