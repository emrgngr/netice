#!/usr/bin/env python3
"""Türkçe metinleri tr(...) çağrısına saran tek seferlik dönüştürücü.

Kullanım: python3 tool/l10n_wrap.py lib/ui/foo.dart ...
Kaynak metinler (Dart'ın çalışma anındaki değeriyle) l10n/_kaynak.json'a eklenir.
"""
import json, os, re, sys

TR_CHARS = set('çğıöşüÇĞİÖŞÜâÂîÎ')


def scan(src):
    """Dart kaynağındaki string literal'lerini (başlangıç, bitiş, ham) döndürür."""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith('//', i):
            j = src.find('\n', i)
            i = n if j < 0 else j
            continue
        if src.startswith('/*', i):
            j = src.find('*/', i + 2)
            i = n if j < 0 else j + 2
            continue
        raw = False
        if c in 'rR' and i + 1 < n and src[i + 1] in '\'"' and (i == 0 or not (src[i - 1].isalnum() or src[i - 1] == '_')):
            raw = True
            start = i
            i += 1
            c = src[i]
        elif c in '\'"':
            start = i
        else:
            i += 1
            continue
        q = src[i:i + 3] if src[i:i + 3] in ("'''", '"""') else c
        i += len(q)
        parts_end = None
        depth = 0
        while i < n:
            if not raw and src[i] == '\\':
                i += 2
                continue
            if not raw and src[i] == '$' and i + 1 < n and src[i + 1] == '{':
                # iç içe ifadeyi atla (içinde string olabilir)
                i += 2
                d = 1
                while i < n and d > 0:
                    ch = src[i]
                    if ch in '\'"':
                        # iç string
                        qq = src[i:i + 3] if src[i:i + 3] in ("'''", '"""') else ch
                        i += len(qq)
                        while i < n and not src.startswith(qq, i):
                            if src[i] == '\\':
                                i += 1
                            i += 1
                        i += len(qq)
                        continue
                    if ch == '{':
                        d += 1
                    elif ch == '}':
                        d -= 1
                    i += 1
                continue
            if src.startswith(q, i):
                i += len(q)
                parts_end = i
                break
            i += 1
        out.append((start, parts_end or n, src[start:parts_end or n], raw, q))
    return out


def evaluate(body, q):
    """Literal gövdesini (tırnaksız) Dart değerine çevirir; ${...} ve $x yer tutucuya dönüşür.
    Dönen: (şablon_değeri, [ifadeler])"""
    vals, exprs = [], []
    i, n = 0, len(body)
    esc = {'n': '\n', 't': '\t', '\\': '\\', "'": "'", '"': '"', '$': '$', 'r': '\r'}
    while i < n:
        c = body[i]
        if c == '\\' and i + 1 < n:
            vals.append(esc.get(body[i + 1], body[i + 1]))
            i += 2
            continue
        if c == '$':
            if i + 1 < n and body[i + 1] == '{':
                d, j = 1, i + 2
                while j < n and d:
                    if body[j] == '{':
                        d += 1
                    elif body[j] == '}':
                        d -= 1
                    j += 1
                exprs.append(body[i + 2:j - 1])
                vals.append('{%d}' % (len(exprs) - 1))
                i = j
                continue
            m = re.match(r'[A-Za-z_][A-Za-z0-9_]*', body[i + 1:])
            if m:
                exprs.append(m.group(0))
                vals.append('{%d}' % (len(exprs) - 1))
                i += 1 + len(m.group(0))
                continue
        vals.append(c)
        i += 1
    return ''.join(vals), exprs


def translatable(text):
    t = re.sub(r'\{\d+\}', '', text)
    if not re.search(r'[A-Za-zçğıöşüÇĞİÖŞÜ]{2,}', t):
        return False
    if re.search(r'https?://|www\.|\.(dart|json|png|jpg|ttf|pdf|xlsx|csv)\b', t):
        return False
    if ' ' not in t.strip() and re.search(r'[a-z][A-Z]|_', t):
        return False
    if any(ch in TR_CHARS for ch in t):
        return True
    if re.search(r'[A-Za-z]{2,}\s+[A-Za-z]{2,}', t):
        return True
    # Tek kelime: büyük harfle başlıyorsa (Kaydet, Sınav…)
    return bool(re.fullmatch(r'[A-ZÇĞİÖŞÜ][a-zçğıöşü]{2,}[.:!?…]*', t.strip()))


def dart_single(s):
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$').replace('\n', '\\n') + "'"


SKIP_BEFORE = re.compile(r"(import|export|part|Key\(|RegExp\(|fontFamily:\s*|case\s+|[\w\)\]]\[\s*|@\w+\(|jsonDecode\(|tr\()\s*$")


def process(path, sources):
    single_word_skip = path.endswith('store.dart')
    src = open(path, encoding='utf-8').read()
    lits = scan(src)
    # yan yana literal'leri grupla
    groups = []
    for lit in lits:
        if groups and re.fullmatch(r'\s*', src[groups[-1][-1][1]:lit[0]]):
            groups[-1].append(lit)
        else:
            groups.append([lit])
    edits = []
    for g in groups:
        if any(l[3] for l in g) or any(l[4] in ("'''", '"""') for l in g):
            continue
        start, end = g[0][0], g[-1][1]
        before = src[max(0, start - 40):start]
        if SKIP_BEFORE.search(before):
            continue
        after = src[end:end + 3]
        if re.match(r'\s*:(?!:)', after) and re.search(r'[{,]\s*$', before):
            # map anahtarı (json) — ama üçlü koşul ? 'a' : 'b' değil
            continue
        line_start = src.rfind('\n', 0, start) + 1
        if src[line_start:start].lstrip().startswith(('import', 'export', 'part')):
            continue
        value, exprs = '', []
        for l in g:
            q = l[4]
            body = l[2][len(q):-len(q)]
            v, e = evaluate(body, q)
            # yer tutucu numaralarını kaydır
            off = len(exprs)
            v = re.sub(r'\{(\d+)\}', lambda m: '{%d}' % (int(m.group(1)) + off), v)
            value += v
            exprs += e
        if not translatable(value) or '[^' in value or (single_word_skip and ' ' not in value.strip()):
            continue
        sources.add(value)
        call = 'tr(' + dart_single(value) + (', [' + ', '.join(e.strip() for e in exprs) + '])' if exprs else ')')
        edits.append((start, end, call))
    if not edits:
        return 0
    for s, e, c in reversed(edits):
        src = src[:s] + c + src[e:]
    # import ekle
    rel = os.path.relpath('lib/l10n/l10n.dart', os.path.dirname(path)).replace(os.sep, '/')
    imp = "import '%s';\n" % rel
    if imp not in src:
        idx = [m.end() for m in re.finditer(r"^import [^\n]*\n", src, re.M)]
        pos = idx[-1] if idx else 0
        src = src[:pos] + imp + src[pos:]
    open(path, 'w', encoding='utf-8').write(src)
    return len(edits)


if __name__ == '__main__':
    store = 'l10n/_kaynak.json'
    sources = set(json.load(open(store, encoding='utf-8'))) if os.path.exists(store) else set()
    total = 0
    for p in sys.argv[1:]:
        k = process(p, sources)
        total += k
        print(f'{k:4d} {p}')
    os.makedirs('l10n', exist_ok=True)
    json.dump(sorted(sources), open(store, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print('toplam', total, 'kaynak metin', len(sources))
