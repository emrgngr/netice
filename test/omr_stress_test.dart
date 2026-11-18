import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:netice/omr/form_layout.dart';
import 'package:netice/omr/form_raster.dart';
import 'package:netice/omr/omr_reader.dart';

/// Gerçek fotoğraf koşullarını taklit eden zor durumlar: gölge, bulanıklık,
/// gürültü, açık kurşun kalem, eğim, düşük çözünürlük ve sıkıştırma.
void main() {
  final layout = FormLayout(questionCount: 30, choiceCount: 5);
  final rnd = math.Random(7);
  final key = {for (var q = 0; q < 30; q++) q: [rnd.nextInt(5)]};

  img.Image photo({
    int shade = 45,
    double rotate = 0,
    double blur = 0,
    double noise = 0,
    double shadow = 0,
    double scale = 1,
    int quality = 85,
  }) {
    var im = FormRaster(layout).render(answers: key, studentNumber: '001042', fillShade: shade);
    // Masa: formu daha büyük gri bir zemine koy.
    final bg = img.Image(width: im.width + 160, height: im.height + 160, numChannels: 3);
    img.fill(bg, color: img.ColorRgb8(150, 140, 120));
    img.compositeImage(bg, im, dstX: 80, dstY: 80);
    im = bg;
    if (rotate != 0) im = img.copyRotate(im, angle: rotate);
    if (shadow > 0) {
      // Soldan sağa koyulaşan gölge (telefonun ya da elin gölgesi).
      for (final p in im) {
        final f = 1 - shadow * (p.x / im.width);
        p
          ..r = (p.r * f)
          ..g = (p.g * f)
          ..b = (p.b * f);
      }
    }
    if (noise > 0) img.noise(im, noise, type: img.NoiseType.gaussian);
    if (blur > 0) im = img.gaussianBlur(im, radius: blur.round());
    if (scale != 1) im = img.copyResize(im, width: (im.width * scale).round());
    return img.decodeJpg(img.encodeJpg(im, quality: quality))!;
  }

  void expectRead(img.Image im, String label) {
    final r = OmrReader(layout).read(GrayImage.fromImage(im));
    expect(r.studentNumber, '001042', reason: '$label: öğrenci no');
    for (var q = 0; q < 30; q++) {
      final a = r.questions[q].answer;
      expect(a.marked, key[q]!.toSet(), reason: '$label: soru ${q + 1} ${r.questions[q].fills}');
    }
  }

  test('güçlü gölge (köşeler uyarlamalı eşikle bulunur)', () => expectRead(photo(shadow: 0.65, rotate: 2), 'güçlü gölge'));
  test('çok açık kalemle öğrenci numarası', () => expectRead(photo(shade: 150), 'çok açık'));
  test('çok düşük çözünürlük', () => expectRead(photo(scale: 0.4, quality: 40), 'çok düşük'));
  test('yan gölge', () => expectRead(photo(shadow: 0.45, rotate: 3), 'gölge'));
  test('bulanık ve gürültülü', () => expectRead(photo(blur: 2, noise: 12), 'bulanık'));
  test('açık kurşun kalem', () => expectRead(photo(shade: 120, rotate: -4), 'açık kalem'));
  test('düşük çözünürlük ve sıkıştırma', () => expectRead(photo(scale: 0.55, quality: 45, rotate: 6), 'düşük çözünürlük'));
  test('hepsi birlikte', () => expectRead(photo(shade: 100, shadow: 0.3, blur: 1, noise: 8, rotate: -7, scale: 0.7, quality: 60), 'karma'));
}
