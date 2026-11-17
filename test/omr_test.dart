import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:netice/core/models.dart';
import 'package:netice/omr/form_layout.dart';
import 'package:netice/omr/form_raster.dart';
import 'package:netice/omr/homography.dart';
import 'package:netice/omr/omr_reader.dart';

/// Formu bir "telefon fotoğrafına" dönüştürür: perspektif, gri masa zemini,
/// ışık eğimi ve gürültü.
img.Image photo(img.Image form, {int seed = 1, double skew = 1}) {
  const outW = 1200, outH = 1600;
  final rnd = math.Random(seed);
  // Formun fotoğraftaki dört köşesi (çarpık).
  final dst = [
    Pt(140 + 40 * skew, 110),
    Pt(1060 - 10 * skew, 150 + 30 * skew),
    Pt(1100, 1480 - 20 * skew),
    Pt(100 + 20 * skew, 1450),
  ];
  final src = [
    const Pt(0, 0),
    Pt(form.width.toDouble(), 0),
    Pt(form.width.toDouble(), form.height.toDouble()),
    Pt(0, form.height.toDouble()),
  ];
  final inv = Homography.fromPoints(dst, src); // foto → form
  final out = img.Image(width: outW, height: outH, numChannels: 3);
  for (var y = 0; y < outH; y++) {
    for (var x = 0; x < outW; x++) {
      final p = inv.map(Pt(x.toDouble(), y.toDouble()));
      double v;
      if (p.x < 0 || p.y < 0 || p.x >= form.width - 1 || p.y >= form.height - 1) {
        v = 95; // masa
      } else {
        v = form.getPixel(p.x.round(), p.y.round()).r.toDouble();
      }
      // Soldan sağa %30 karartan ışık eğimi + gürültü.
      v = v * (1 - 0.3 * x / outW) + (rnd.nextDouble() - 0.5) * 24;
      final c = v.round().clamp(0, 255);
      out.setPixelRgb(x, y, c, c, c);
    }
  }
  return out;
}

void main() {
  final layout = FormLayout(questionCount: 40, choiceCount: 5);
  final raster = FormRaster(layout);
  final reader = OmrReader(layout);

  Map<int, List<int>> pattern() =>
      {for (var q = 0; q < 40; q++) if (q % 7 != 6) q: [(q * 3) % 5]};

  test('temiz taramada tüm cevaplar ve öğrenci no okunur', () {
    final form = raster.render(answers: pattern(), studentNumber: '104263');
    final r = reader.read(GrayImage.fromImage(form));
    expect(r.studentNumber, '104263');
    for (var q = 0; q < 40; q++) {
      final a = r.questions[q].answer;
      if (q % 7 == 6) {
        expect(a.state, MarkState.blank, reason: 'soru ${q + 1}');
      } else {
        expect(a.state, MarkState.filled, reason: 'soru ${q + 1}');
        expect(a.marked, {(q * 3) % 5}, reason: 'soru ${q + 1}');
      }
    }
    expect(r.reviewCount, 0);
  });

  test('çarpık, gölgeli ve gürültülü fotoğrafta da doğru okunur', () {
    for (final seed in [1, 2, 3]) {
      final form = raster.render(answers: pattern(), studentNumber: '000917');
      final r = reader.read(GrayImage.fromImage(photo(form, seed: seed, skew: seed.toDouble())));
      expect(r.studentNumber, '000917', reason: 'seed $seed');
      var correct = 0;
      for (var q = 0; q < 40; q++) {
        final a = r.questions[q].answer;
        final expected = q % 7 == 6 ? <int>{} : {(q * 3) % 5};
        if (a.marked.length == expected.length && a.marked.containsAll(expected)) correct++;
      }
      expect(correct, 40, reason: 'seed $seed');
    }
  });

  test('çift işaret ve silik işaret kontrol kuyruğuna düşer', () {
    final form = raster.render(answers: {0: [1, 3], 1: [2]}, studentNumber: '123456');
    // 3. soruya silik (açık gri) bir işaret ekle.
    final faint = FormRaster(layout).render(answers: {2: [4]}, fillShade: 175);
    final b = layout.answerBubble(2, 4);
    final px = raster.pxPerMm;
    for (var y = ((b.y - 3) * px).round(); y < ((b.y + 3) * px).round(); y++) {
      for (var x = ((b.x - 3) * px).round(); x < ((b.x + 3) * px).round(); x++) {
        form.setPixel(x, y, faint.getPixel(x, y));
      }
    }
    final r = reader.read(GrayImage.fromImage(form));
    expect(r.questions[0].answer.state, MarkState.multiple);
    expect(r.questions[0].answer.marked, {1, 3});
    expect(r.questions[1].answer.state, MarkState.filled);
    expect(r.questions[2].answer.state, MarkState.uncertain);
    expect(r.reviewCount, 2);
  });

  test('köşe işaretleri görünmezse anlaşılır bir mesaj verilir', () {
    final blank = img.Image(width: 800, height: 1100, numChannels: 3);
    img.fill(blank, color: img.ColorRgb8(240, 240, 240));
    expect(() => reader.read(GrayImage.fromImage(blank)),
        throwsA(isA<OmrException>()));
  });
}
