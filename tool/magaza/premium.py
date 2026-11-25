"""Seslendirmeli, ekranda işaretlerle anlatan tanıtım videosu (1920x1080).

python3 tool/magaza/premium.py <kare_klasoru> <ses_klasoru> <cikti.mp4>

<ses_klasoru> içinde premium.json'daki "ses" adlarıyla seslendirmeler ve
muzik.mp3 / acilis.mp3 bulunur. Her sahnede: hafif yakınlaşma, ekrana gelen
imleç ve dokunma dalgası, hedefi öne çıkaran ışık, alt yazı.
"""
import json
import math
import os
import re
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
FONT = os.path.join(ROOT, 'assets', 'fonts', 'PlusJakartaSans_{}.ttf')
W, H, FPS = 1920, 1080, 30
EMERALD = (16, 185, 129)
LEAD, TAIL, XFADE = 0.7, 0.8, 0.45


def ease(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def ease_out(t):
    t = max(0.0, min(1.0, t))
    return 1 - (1 - t) ** 3


def duration(path):
    out = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', path],
                         capture_output=True, text=True, check=True).stdout
    return float(out.strip())


def first_pause(path, after=0.8):
    """İlk cümleden sonraki sessizliğin bitişi (yoksa None)."""
    err = subprocess.run(['ffmpeg', '-i', path, '-af', 'silencedetect=noise=-35dB:d=0.22', '-f', 'null', '-'],
                         capture_output=True, text=True).stderr
    starts = [float(x) for x in re.findall(r'silence_start: ([0-9.]+)', err)]
    ends = [float(x) for x in re.findall(r'silence_end: ([0-9.]+)', err)]
    for s, e in zip(starts, ends):
        if s > after and e < duration(path) - 1.0:
            return e - 0.05
    return None


def wrap(d, text, fnt, width):
    words, lines, cur = text.split(), [], ''
    for w in words:
        t = (cur + ' ' + w).strip()
        if d.textlength(t, font=fnt) > width and cur:
            lines.append(cur)
            cur = w
        else:
            cur = t
    lines.append(cur)
    return lines


class Caption:
    """Alt yazı: koyu yarı saydam şerit üzerinde beyaz metin."""

    def __init__(self, text, left=False):
        fnt = ImageFont.truetype(FONT.format('600SemiBold'), 36 if left else 38)
        probe = ImageDraw.Draw(Image.new('RGB', (10, 10)))
        lines = wrap(probe, text, fnt, 900 if left else 1500)
        lh = 52
        bw = int(max(probe.textlength(l, font=fnt) for l in lines)) + 80
        bh = lh * len(lines) + 36
        im = Image.new('RGBA', (bw, bh), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        d.rounded_rectangle((0, 0, bw - 1, bh - 1), 22, fill=(6, 12, 32, 200))
        for i, l in enumerate(lines):
            w = d.textlength(l, font=fnt)
            x = 40 if left else (bw - w) / 2
            d.text((x, 16 + i * lh), l, font=fnt, fill=(255, 255, 255, 255))
        self.im = im
        self.pos = (110, H - bh - 70) if left else ((W - bw) // 2, H - bh - 42)

    def draw(self, frame, alpha):
        if alpha <= 0:
            return
        im = self.im
        if alpha < 1:
            im = im.copy()
            im.putalpha(im.getchannel('A').point(lambda a: int(a * alpha)))
        frame.alpha_composite(im, self.pos)


def pointer_sprite():
    s = Image.new('RGBA', (90, 90), (0, 0, 0, 0))
    sh = Image.new('RGBA', (90, 90), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse((27, 31, 63, 67), fill=(0, 0, 0, 120))
    s.alpha_composite(sh.filter(ImageFilter.GaussianBlur(6)))
    d = ImageDraw.Draw(s)
    d.ellipse((27, 27, 63, 63), fill=(255, 255, 255, 240), outline=EMERALD + (255,), width=5)
    return s


POINTER = None


def render_scene(base, sc, dur, caption, pipe, prev_last):
    """Bir sahnenin karelerini üretir; son kareyi döndürür."""
    global POINTER
    if POINTER is None:
        POINTER = pointer_sprite()
    n = int(round(dur * FPS))
    tgt = sc.get('hedef')
    if tgt:
        cx, cy = (tgt[0] + tgt[2]) / 2, (tgt[1] + tgt[3]) / 2
        zoom_to = 1.07
    else:
        cx, cy = W / 2, H / 2
        zoom_to = 1.05
    last = None
    for f in range(n):
        t = f / FPS
        p = f / max(1, n - 1)
        z = 1 + (zoom_to - 1) * ease(p)
        # Yakınlaşma hedefe doğru kayar ama kenarlardan taşmaz.
        vw, vh = W / z, H / z
        fx = min(max(cx - vw / 2, 0), W - vw) if tgt else (W - vw) / 2
        fy = min(max(cy - vh / 2, 0), H - vh) if tgt else (H - vh) / 2
        # Yakınlaşmayı yumuşat: odak ekran merkezinden hedefe kayar.
        k = 0.5 * ease(p)
        ox = (W - vw) / 2 * (1 - k) + fx * k
        oy = (H - vh) / 2 * (1 - k) + fy * k
        frame = base.resize((W, H), Image.BILINEAR, box=(ox, oy, ox + vw, oy + vh)).convert('RGBA')

        def tr(x, y):
            return (x - ox) * z, (y - oy) * z

        if tgt:
            x0, y0 = tr(tgt[0] - 12, tgt[1] - 12)
            x1, y1 = tr(tgt[2] + 12, tgt[3] + 12)
            tx, ty = tr(cx, cy)
            arrive = 1.3
            # Işık: hedef dışı kararır.
            a = ease((t - arrive) / 0.4)
            if a > 0:
                ov = Image.new('RGBA', (W, H), (4, 8, 24, int(120 * a)))
                ImageDraw.Draw(ov).rounded_rectangle((x0, y0, x1, y1), 20, fill=(0, 0, 0, 0))
                frame.alpha_composite(ov)
                ring = Image.new('RGBA', (W, H), (0, 0, 0, 0))
                rd = ImageDraw.Draw(ring)
                rd.rounded_rectangle((x0, y0, x1, y1), 20, outline=EMERALD + (int(255 * a),), width=5)
                # Nabız gibi dışa açılan ikinci çizgi.
                ph = ((t - arrive) % 1.6) / 1.6
                g = 6 + 22 * ph
                rd.rounded_rectangle((x0 - g, y0 - g, x1 + g, y1 + g), 24, outline=EMERALD + (int(150 * a * (1 - ph)),), width=3)
                frame.alpha_composite(ring)
            # İmleç sağ alttan gelir, dokunur ve biraz sonra çekilir.
            if t < arrive + 1.6:
                m = ease_out((t - 0.35) / (arrive - 0.35))
                sx, sy = W + 60, H + 60
                px = sx + (tx - sx) * m
                py = sy + (ty - sy) * m + math.sin(m * math.pi) * -60
                fade = 1 - ease((t - arrive - 1.1) / 0.5)
                tap = (t - arrive) / 0.6
                if 0 <= tap <= 1:
                    rip = Image.new('RGBA', (W, H), (0, 0, 0, 0))
                    r = 18 + 70 * ease_out(tap)
                    ImageDraw.Draw(rip).ellipse((px - r, py - r, px + r, py + r), outline=(255, 255, 255, int(220 * (1 - tap))), width=4)
                    frame.alpha_composite(rip)
                if m > 0 and fade > 0:
                    sp = POINTER
                    sc_ = 0.85 if 0 <= tap <= 0.25 else 1.0
                    if sc_ != 1.0:
                        sp = POINTER.resize((int(90 * sc_), int(90 * sc_)), Image.BILINEAR)
                    if fade < 1:
                        sp = sp.copy()
                        sp.putalpha(sp.getchannel('A').point(lambda v: int(v * fade)))
                    frame.alpha_composite(sp, (int(px - sp.width / 2), int(py - sp.height / 2)))
        caption.draw(frame, ease((t - LEAD + 0.25) / 0.3) * (1 - ease((t - (dur - 0.35)) / 0.3)))
        out = frame.convert('RGB')
        if prev_last is not None and f < XFADE * FPS:
            out = Image.blend(prev_last, out, ease(f / (XFADE * FPS)))
        pipe.write(out.tobytes())
        last = out
    return last


def main():
    frames, audio, out = sys.argv[1:4]
    cfg = json.load(open(os.path.join(HERE, 'premium.json')))
    tmp = os.path.join(os.path.dirname(os.path.abspath(out)), '_premium_ses')
    os.makedirs(tmp, exist_ok=True)
    plan = []
    for i, sc in enumerate(cfg['sahneler']):
        src = os.path.join(audio, sc['kare'] + '.mp3' if sc['ses'] == 'elevenlabs' else sc['ses'])
        text = sc['metin']
        voice = os.path.join(tmp, f'{i:02d}.wav')
        start = first_pause(src) if sc.get('kirp_ilk_cumle') else None
        cmd = ['ffmpeg', '-y', '-loglevel', 'error']
        if start:
            cmd += ['-ss', f'{start:.3f}']
            text = sc.get('metin_kirpik', text)
        subprocess.run(cmd + ['-i', src, '-ar', '44100', '-ac', '2', voice], check=True)
        vd = duration(voice)
        d = LEAD + vd + TAIL
        if i == 0:
            d = max(d, 3.6)
        if i == len(cfg['sahneler']) - 1:
            d += 1.2
        plan.append((sc, voice, d, text))
    total = sum(p[2] for p in plan)
    silent = out + '.video.mp4'
    enc = subprocess.Popen(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}',
                            '-r', str(FPS), '-i', '-', '-c:v', 'libx264', '-preset', 'medium', '-crf', '18',
                            '-pix_fmt', 'yuv420p', silent], stdin=subprocess.PIPE)
    last = None
    for sc, _, d, text in plan:
        base = Image.open(os.path.join(frames, sc['kare'] + '.png')).convert('RGB')
        last = render_scene(base, sc, d, Caption(text, left=bool(sc.get('hedef'))), enc.stdin, last)
    enc.stdin.close()
    enc.wait()
    # Ses: seslendirmeler sahne başına göre yerleşir, müzik altta kısık.
    inputs, filt, labels, t = [], [], [], 0.0
    for i, (_, voice, d, _) in enumerate(plan):
        inputs += ['-i', voice]
        ms = int((t + LEAD) * 1000)
        filt.append(f'[{i + 1}:a]adelay={ms}|{ms},volume=1.6[v{i}]')
        labels.append(f'[v{i}]')
        t += d
    k = len(plan) + 1
    music = os.path.join(audio, 'muzik.mp3')
    intro = os.path.join(audio, 'acilis.mp3')
    if os.path.exists(music):
        inputs += ['-stream_loop', '-1', '-i', music]
        filt.append(f'[{k}:a]volume=0.22,afade=t=in:d=1.5,afade=t=out:st={total - 2.5:.2f}:d=2.5[m]')
        labels.append('[m]')
        k += 1
    if os.path.exists(intro):
        inputs += ['-i', intro]
        filt.append(f'[{k}:a]volume=0.55[i]')
        labels.append('[i]')
    filt.append(f'{"".join(labels)}amix=inputs={len(labels)}:duration=longest:normalize=0,atrim=0:{total:.2f},alimiter=limit=0.95[a]')
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', silent] + inputs +
                   ['-filter_complex', ';'.join(filt), '-map', '0:v', '-map', '[a]', '-c:v', 'copy',
                    '-c:a', 'aac', '-b:a', '192k', '-t', f'{total:.2f}', '-movflags', '+faststart', out], check=True)
    os.remove(silent)
    print(f'{out} ({total:.1f} sn)')


if __name__ == '__main__':
    main()
