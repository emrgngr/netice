#!/usr/bin/env python3
"""tr(...) sarmalamasından sonra 'const' bağlamı hatalarını düzeltir:
hatanın bulunduğu ifadeyi saran en yakın const kaldırılır (bildirimse final yapılır).
Kullanım: python3 tool/l10n_fixconst.py   (lib/ üzerinde döngüyle çalışır)"""
import os, re, subprocess, sys

sys.path.insert(0, os.path.dirname(__file__))
from l10n_wrap import scan  # noqa: E402

CODES = {
    'CONST_EVAL_METHOD_INVOCATION', 'INVALID_CONSTANT', 'CONST_WITH_NON_CONSTANT_ARGUMENT',
    'NON_CONSTANT_LIST_ELEMENT', 'NON_CONSTANT_MAP_VALUE', 'NON_CONSTANT_MAP_ELEMENT',
    'CONST_INITIALIZED_WITH_NON_CONSTANT_VALUE', 'NON_CONSTANT_SET_ELEMENT',
    'CONST_CONSTRUCTOR_PARAM_TYPE_MISMATCH', 'CONST_EVAL_TYPE_BOOL_NUM_STRING',
    'CONST_INITIALIZED_WITH_NON_CONSTANT_VALUE_FROM_DEFERRED_LIBRARY', 'CONST_EVAL_EXTENSION_METHOD',
    'CONST_EVAL_EXTENSION_TYPE_METHOD',
}


def analyze():
    env = dict(os.environ)
    r = subprocess.run(['dart', 'analyze', '--format=machine', 'lib'], capture_output=True, text=True, env=env)
    out = []
    for line in (r.stdout + r.stderr).splitlines():
        p = line.split('|')
        if len(p) >= 8 and p[0] == 'ERROR':
            out.append((p[2], p[3], int(p[4]), int(p[5]), p[7]))
    return out


def match_end(src, i):
    """src[i] açılış parantezi; eşleşen kapanışın sonrasını döndürür (stringleri atlar)."""
    pairs = {'(': ')', '[': ']', '{': '}', '<': '>'}
    strs = [(s, e) for s, e, *_ in scan(src[i:])]
    stack = []
    j = i
    k = 0
    while j < len(src):
        while k < len(strs) and strs[k][1] + i <= j:
            k += 1
        if k < len(strs) and strs[k][0] + i <= j < strs[k][1] + i:
            j = strs[k][1] + i
            continue
        c = src[j]
        if c in '([{':
            stack.append(pairs[c])
        elif c in ')]}':
            if stack and stack[-1] == c:
                stack.pop()
            if not stack:
                return j + 1
        j += 1
    return len(src)


def fix_file(path, offsets):
    src = open(path, encoding='utf-8').read()
    strings = [(s, e) for s, e, *_ in scan(src)]

    def in_string(p):
        return any(s <= p < e for s, e in strings)

    consts = [m.start() for m in re.finditer(r'\bconst\b', src) if not in_string(m.start())]
    changes = {}
    for off in offsets:
        for c in reversed([c for c in consts if c < off]):
            j = c + 5
            while j < len(src) and src[j].isspace():
                j += 1
            # bildirim mi? const Tip? isim = ... ;  ya da const isim = ...
            decl = re.match(r'(?:[A-Za-z_][\w<>, ?]*\s+)?[A-Za-z_]\w*\s*=(?!=)', src[j:])
            if decl and not re.match(r'[A-Z]\w*\s*\(', src[j:]):
                end = src.find(';', j)
                if c <= off <= end:
                    changes[c] = 'final'
                    break
                continue
            # const İfade( / const [ / const { / const <T>[
            m = re.match(r'(?:[A-Za-z_][\w.]*\s*)?(?:<[^()]*?>\s*)?', src[j:])
            k = j + (m.end() if m else 0)
            if k < len(src) and src[k] in '([{':
                end = match_end(src, k)
                if c <= off < end:
                    changes[c] = ''
                    break
    if not changes:
        return 0
    for c in sorted(changes, reverse=True):
        rep = changes[c]
        if rep == '':
            e = c + 5
            while e < len(src) and src[e] == ' ':
                e += 1
            src = src[:c] + src[e:]
        else:
            src = src[:c] + rep + src[c + 5:]
    open(path, 'w', encoding='utf-8').write(src)
    return len(changes)


def main():
    for it in range(30):
        errs = [e for e in analyze() if e[0] in CODES]
        if not errs:
            print('const hatası kalmadı')
            break
        by = {}
        for code, path, line, col, _msg in errs:
            src = open(path, encoding='utf-8').read()
            lines = src.split('\n')
            off = sum(len(l) + 1 for l in lines[:line - 1]) + col - 1
            by.setdefault(path, []).append(off)
        n = sum(fix_file(p, offs) for p, offs in by.items())
        print(f'tur {it + 1}: {len(errs)} hata, {n} düzeltme')
        if n == 0:
            for e in errs[:20]:
                print(e)
            break
    rest = [e for e in analyze()]
    for e in rest[:40]:
        print('KALAN', e)


if __name__ == '__main__':
    main()
