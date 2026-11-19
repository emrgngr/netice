#!/usr/bin/env python3
"""Netice kullanım rehberi videosunu birleştirir.

Kullanım: python3 tool/video/compose.py <dil>
Girdi:
  build/video/frames/<dil>/*.png ve hedefler.json  (flutter test tool/video_test.dart)
  tool/video/anlatim_<dil>.json                     (sahne -> anlatım metni)
  build/video/audio/<dil>/<NN>.mp3                  (sahne sırasıyla seslendirme; yoksa sessiz)
Çıktı: build/video/rehber_<dil>.mp4 (720x1280, 24 fps)
"""
import json
import math
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H, FPS = 720, 1280, 24
NAVY = (15, 27, 61)
NAVY_DARK = (6, 11, 28)
EMERALD = (16, 185, 129)
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

TITLES = {
    'tr': 'Kullanım rehberi', 'en': 'User guide', 'de': 'Anleitung', 'fr': "Guide d'utilisation",
    'ru': 'Руководство', 'az': 'İstifadə bələdçisi', 'es': 'Guía de uso', 'it': 'Guida all\'uso',
    'ar': 'دليل الاستخدام', 'zh': '使用指南', 'ja': '使い方ガイド',
}


def font(lang, size, bold=False):
    special = {
        'ar': 'assets/pdf_fonts/NotoSansArabic-Bold.ttf' if bold else 'assets/pdf_fonts/NotoSansArabic-Regular.ttf',
        'zh': 'assets/pdf_fonts/NotoSansSC-Regular.ttf',
        'ja': 'assets/pdf_fonts/NotoSansJP-Regular.ttf',
        'ru': 'assets/pdf_fonts/NotoSans-Bold.ttf' if bold else 'assets/pdf_fonts/NotoSans-Regular.ttf',
    }.get(lang)
    path = special or ('assets/fonts/PlusJakartaSans_700Bold.ttf' if bold else 'assets/fonts/PlusJakartaSans_500Medium.ttf')
    kw = {}
    if lang == 'ar':
        kw['layout_engine'] = ImageFont.Layout.RAQM
    return ImageFont.truetype(os.path.join(ROOT, path), size, **kw)


def wrap(draw, text, fnt, width, lang):
    # Çince/Japoncada boşluk yok: karakter karakter böl.
    units = list(text) if lang in ('zh', 'ja') else text.split(' ')
    sep = '' if lang in ('zh', 'ja') else ' '
    lines, cur = [], ''
    for u in units:
        t = (cur + sep + u) if cur else u
        if draw.textlength(t, font=fnt, direction='rtl' if lang == 'ar' else None) <= width:
            cur = t
        else:
            if cur:
                lines.append(cur)
            cur = u
    if cur:
        lines.append(cur)
    return lines


def duration(path):
    out = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', path],
                         capture_output=True, text=True).stdout.strip()
    return float(out or 0)


def background():
    bg = Image.new('RGB', (W, H), NAVY)
    g = Image.new('L', (W, H))
    gd = ImageDraw.Draw(g)
    for y in range(H):
        gd.line([(0, y), (W, y)], fill=int(255 * y / H))
    bg = Image.composite(Image.new('RGB', (W, H), NAVY_DARK), bg, g)
    glow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([W - 420, -260, W + 260, 420], fill=EMERALD + (70,))
    glow = glow.filter(ImageFilter.GaussianBlur(120))
    bg.paste(glow, (0, 0), glow)
    return bg


PHONE_H = 900
PHONE_W = round(PHONE_H * 360 / 760)
PHONE_X = (W - PHONE_W) // 2
PHONE_Y = 120
SCALE = PHONE_H / 760  # mantıksal koordinat -> video pikseli


def phone(img):
    shot = img.convert('RGB').resize((PHONE_W, PHONE_H), Image.LANCZOS)
    mask = Image.new('L', (PHONE_W, PHONE_H), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, PHONE_W - 1, PHONE_H - 1], 34, fill=255)
    return shot, mask


def main(lang):
    os.chdir(ROOT)
    frames_dir = f'build/video/frames/{lang}'
    targets = json.load(open(f'{frames_dir}/hedefler.json'))
    script = json.load(open(f'tool/video/anlatim_{lang}.json'))
    audio_dir = f'build/video/audio/{lang}'
    scenes = list(script.keys())

    bg = background()
    title_f = font(lang, 26, bold=True)
    step_f = font('en', 22, bold=True)
    cap_f = font(lang, 30 if lang not in ('zh', 'ja') else 30)
    rtl = lang == 'ar'

    # Sahne süreleri seslendirmeden.
    tmp = tempfile.mkdtemp()
    durs, wavs = [], []
    for i, name in enumerate(scenes):
        mp3 = f'{audio_dir}/{i:02d}.mp3'
        lead = 0.5
        if os.path.exists(mp3):
            d = max(3.0, duration(mp3) + lead + 0.9)
        else:
            d = max(3.0, len(script[name]) / 14 + 1.4)
        durs.append(d)
        wav = f'{tmp}/{i:02d}.wav'
        if os.path.exists(mp3):
            subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', mp3, '-af',
                            f'adelay={int(lead*1000)}:all=1,apad', '-t', f'{d:.3f}', '-ar', '44100', '-ac', '2', wav], check=True)
        else:
            subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'lavfi', '-i', 'anullsrc=r=44100:cl=stereo',
                            '-t', f'{d:.3f}', wav], check=True)
        wavs.append(wav)
    with open(f'{tmp}/list.txt', 'w') as f:
        for w in wavs:
            f.write(f"file '{w}'\n")
    audio = f'{tmp}/audio.wav'
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', f'{tmp}/list.txt', '-c', 'copy', audio], check=True)

    out = f'build/video/rehber_{lang}.mp4'
    ff = subprocess.Popen(['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', str(FPS),
                           '-i', '-', '-i', audio, '-c:v', 'libx264', '-preset', 'medium', '-crf', '26', '-pix_fmt', 'yuv420p',
                           '-c:a', 'aac', '-b:a', '96k', '-shortest', '-movflags', '+faststart', out], stdin=subprocess.PIPE)

    splash = sorted(f for f in os.listdir(frames_dir) if f.startswith('00_acilis_'))
    cache = {}

    def scene_image(name, t, d):
        if name == '00_acilis':
            k = min(len(splash) - 1, int(t / (d * 0.8) * len(splash)))
            key = splash[k]
        else:
            key = name + '.png'
        if key not in cache:
            cache[key] = phone(Image.open(f'{frames_dir}/{key}'))
        return cache[key]

    def render(i, t):
        name, d = scenes[i], durs[i]
        frame = bg.copy()
        dr = ImageDraw.Draw(frame)
        # Üst başlık ve adım.
        title = f'Netice · {TITLES.get(lang, TITLES["en"])}'
        if rtl:
            dr.text((W - 40, 52), title, font=title_f, fill='white', anchor='ra', direction='rtl')
        else:
            dr.text((40, 52), title, font=title_f, fill='white')
        step = f'{i + 1}/{len(scenes)}'
        sw = dr.textlength(step, font=step_f) + 28
        sx = 40 if rtl else W - 40 - sw
        dr.rounded_rectangle([sx, 48, sx + sw, 86], 19, fill=EMERALD)
        dr.text((sx + sw / 2, 67), step, font=step_f, fill=NAVY, anchor='mm')
        # İlerleme çubuğu.
        total = sum(durs)
        done = sum(durs[:i]) + t
        dr.rounded_rectangle([40, 100, W - 40, 104], 2, fill=(255, 255, 255, 40))
        px = 40 + (W - 80) * done / total
        if rtl:
            dr.rounded_rectangle([W - 40 - (px - 40), 100, W - 40, 104], 2, fill=EMERALD)
        else:
            dr.rounded_rectangle([40, 100, px, 104], 2, fill=EMERALD)

        # Telefon: hafif yakınlaşma ve gölge.
        shot, mask = scene_image(name, t, d)
        shadow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).rounded_rectangle([PHONE_X - 6, PHONE_Y + 14, PHONE_X + PHONE_W + 6, PHONE_Y + PHONE_H + 24], 40,
                                                  fill=(0, 0, 0, 120))
        shadow = shadow.filter(ImageFilter.GaussianBlur(18))
        frame.paste(shadow, (0, 0), shadow)
        dr = ImageDraw.Draw(frame)
        dr.rounded_rectangle([PHONE_X - 8, PHONE_Y - 8, PHONE_X + PHONE_W + 8, PHONE_Y + PHONE_H + 8], 42, fill=(20, 24, 40),
                             outline=(70, 80, 110), width=2)
        frame.paste(shot, (PHONE_X, PHONE_Y), mask)

        # İşaretler: hedefler sırayla, nabız gibi atan halka ve dokunma noktası.
        tg = targets.get(name, [])
        if tg:
            ov = Image.new('RGBA', (W, H), (0, 0, 0, 0))
            od = ImageDraw.Draw(ov)
            start = 0.6
            span = max(0.1, (d - start - 0.3) / len(tg))
            for j, (x, y, w, h) in enumerate(tg):
                t0 = start + j * span
                if t < t0:
                    continue
                active = t < t0 + span or j == len(tg) - 1
                p = 6
                x0, y0 = PHONE_X + x * SCALE - p, PHONE_Y + y * SCALE - p
                x1, y1 = PHONE_X + (x + w) * SCALE + p, PHONE_Y + (y + h) * SCALE + p
                k = min(1, (t - t0) / 0.25)
                alpha = int(255 * k) if active else 90
                pulse = (math.sin((t - t0) * 2 * math.pi * 1.2) + 1) / 2
                grow = 4 + 6 * pulse if active else 0
                od.rounded_rectangle([x0 - grow, y0 - grow, x1 + grow, y1 + grow], 14, outline=EMERALD + (alpha,), width=4)
                if active:
                    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
                    cx, cy = min(x1 - 8, cx + 18), min(y1 + 2, cy + 14)
                    # Dokunma dalgası.
                    ph = ((t - t0) % 1.2) / 1.2
                    r = 10 + 34 * ph
                    od.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(255, 255, 255, int(220 * (1 - ph))), width=3)
                    od.ellipse([cx - 9, cy - 9, cx + 9, cy + 9], fill=(255, 255, 255, 150), outline=EMERALD + (255,), width=3)
                    # Numara rozeti.
                    if len(tg) > 1:
                        bx, by = (x0 - 4, y0 - 4) if not rtl else (x1 + 4, y0 - 4)
                        od.ellipse([bx - 15, by - 15, bx + 15, by + 15], fill=EMERALD + (255,))
                        od.text((bx, by), str(j + 1), font=step_f, fill=NAVY, anchor='mm')
            frame.paste(ov, (0, 0), ov)

        # Altyazı kutusu.
        dr = ImageDraw.Draw(frame)
        text = script[name]
        lines = wrap(dr, text, cap_f, W - 120, lang)
        lh = 42
        box_h = lh * len(lines) + 36
        by = H - 40 - box_h
        cap = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(cap).rounded_rectangle([36, by, W - 36, by + box_h], 24, fill=(255, 255, 255, 240))
        frame.paste(cap, (0, 0), cap)
        dr = ImageDraw.Draw(frame)
        for li, line in enumerate(lines):
            yy = by + 18 + li * lh + lh / 2
            dr.text((W / 2, yy), line, font=cap_f, fill=NAVY, anchor='mm', direction='rtl' if rtl else None)
        return frame

    for i in range(len(scenes)):
        n = int(durs[i] * FPS)
        prev_last = None
        for f in range(n):
            t = f / FPS
            img = render(i, t)
            # Sahne geçişinde kısa çapraz geçiş.
            if i > 0 and f < 6:
                if prev_last is None:
                    prev_last = render(i - 1, durs[i - 1] - 1 / FPS)
                img = Image.blend(prev_last, img, (f + 1) / 7)
            ff.stdin.write(img.tobytes())
    ff.stdin.close()
    ff.wait()
    print(out, f'{sum(durs):.1f} sn')


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'tr')
