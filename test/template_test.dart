import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'dart:io';

import 'package:netice/core/models.dart';
import 'package:netice/core/store.dart';
import 'package:netice/omr/sheet_reader.dart';
import 'package:netice/omr/form_layout.dart';
import 'package:netice/omr/homography.dart';
import 'package:netice/omr/omr_reader.dart';
import 'package:netice/omr/template.dart';

/// Başka bir firmanın formunu taklit eden sentetik kâğıt: köşe işareti yok,
/// pembe daireler, iki sütun soru ve 6 haneli numara bloğu.
const template = FormTemplate(
  id: 't',
  name: 'Yayınevi formu',
  blocks: [
    TemplateBlock(start: 1, count: 20, choices: 5, first: Pt(120, 520), last: Pt(360, 1330)),
    TemplateBlock(start: 21, count: 20, choices: 5, first: Pt(560, 520), last: Pt(800, 1330)),
  ],
  number: NumberBlock(digits: 6, first: Pt(560, 80), last: Pt(860, 440)),
);

img.Image renderPage(Map<int, int> answers, String number) {
  final w = FormTemplate.width.round(), h = template.height.round();
  final im = img.Image(width: w, height: h, numChannels: 3);
  img.fill(im, color: img.ColorRgb8(250, 248, 245));
  img.drawString(im, 'YAYINEVI DENEME SINAVI', font: img.arial24, x: 80, y: 120, color: img.ColorRgb8(30, 30, 30));
  void bubble(Pt p, double r, bool filled) {
    img.drawCircle(im, x: p.x.round(), y: p.y.round(), radius: r.round(), color: img.ColorRgb8(225, 120, 140));
    if (filled) img.fillCircle(im, x: p.x.round(), y: p.y.round(), radius: (r * 0.85).round(), color: img.ColorRgb8(40, 40, 45));
  }

  for (final b in template.blocks) {
    for (var q = 0; q < b.count; q++) {
      for (var c = 0; c < b.choices; c++) {
        bubble(b.bubble(q, c), b.radius, answers[b.start - 1 + q] == c);
      }
    }
  }
  final nb = template.number!;
  for (var d = 0; d < nb.digits; d++) {
    for (var v = 0; v < 10; v++) {
      bubble(nb.bubble(d, v), nb.radius, int.parse(number[d]) == v);
    }
  }
  return im;
}

/// Sayfayı koyu masaya perspektifle yerleştirir.
img.Image photo(img.Image page, List<Pt> quad, {int w = 1500, int h = 2000, double blur = 0}) {
  final out = img.Image(width: w, height: h, numChannels: 3);
  img.fill(out, color: img.ColorRgb8(70, 60, 55));
  final inv = Homography.fromPoints(quad, [Pt(0, 0), Pt(page.width.toDouble(), 0), Pt(page.width.toDouble(), page.height.toDouble()), Pt(0, page.height.toDouble())]);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = inv.map(Pt(x.toDouble(), y.toDouble()));
      if (p.x < 0 || p.y < 0 || p.x >= page.width || p.y >= page.height) continue;
      out.setPixel(x, y, page.getPixel(p.x.toInt(), p.y.toInt()));
    }
  }
  var r = blur > 0 ? img.gaussianBlur(out, radius: blur.round()) : out;
  r = img.decodeJpg(Uint8List.fromList(img.encodeJpg(r, quality: 80)))!;
  return r;
}

void main() {
  final rnd = math.Random(3);
  final key = {for (var q = 0; q < 40; q++) if (q % 9 != 4) q: rnd.nextInt(5)};
  final page = renderPage(key, '004217');

  void expectRead(OmrResult r, String label) {
    expect(r.studentNumber, '004217', reason: '$label: numara');
    for (var q = 0; q < 40; q++) {
      final a = r.questions[q].answer;
      if (key[q] == null) {
        expect(a.state, MarkState.blank, reason: '$label: soru ${q + 1} ${r.questions[q].fills}');
      } else {
        expect(a.marked, {key[q]}, reason: '$label: soru ${q + 1} ${r.questions[q].fills}');
      }
    }
  }

  TemplateReader reader() => TemplateReader(template, questionCount: 40, choiceCount: 5);

  test('tarayıcı görüntüsü (sayfa tüm görüntü)', () {
    expectRead(reader().read(GrayImage.fromImage(page)), 'tarama');
  });

  test('masada, eğik çekilmiş fotoğraf', () {
    final im = photo(page, [Pt(230, 160), Pt(1290, 230), Pt(1360, 1840), Pt(150, 1760)], blur: 1);
    final g = GrayImage.fromImage(im);
    final corners = PageFinder.find(g);
    expect(corners[0].x, closeTo(230, 8));
    expect(corners[0].y, closeTo(160, 8));
    expect(corners[2].x, closeTo(1360, 8));
    expectRead(reader().read(g), 'eğik');
  });

  test('yan çekilmiş (yatay) fotoğraf doğru yöne çevrilir', () {
    final im = photo(page, [Pt(1850, 120), Pt(1880, 1380), Pt(140, 1420), Pt(120, 90)], w: 2000, h: 1500);
    expectRead(reader().read(GrayImage.fromImage(im)), 'yatay');
  });

  test('şablon JSON ile saklanır', () {
    final t2 = FormTemplate.fromJson(template.toJson());
    expect(t2.blocks.length, 2);
    expect(t2.number!.digits, 6);
    expect(t2.blocks[1].bubble(19, 4).x, closeTo(800, 1e-9));
    expect(t2.questionCount, 40);
  });

  test('ters çekilmiş fotoğraf', () {
    final im = photo(page, [Pt(1300, 1850), Pt(200, 1800), Pt(160, 150), Pt(1340, 200)]);
    expectRead(reader().read(GrayImage.fromImage(im)), 'ters');
  });

  test('şablonlu sınav: kayıt, okuma ve öğrenci eşleştirme', () async {
    final dir = Directory.systemTemp.createTempSync('sablon');
    final store = AppStore();
    await store.load(dir: dir);
    store.saveTemplate(template);
    final keyStr = [for (var q = 0; q < 40; q++) String.fromCharCode(65 + (key[q] ?? 0))].join();
    final exam = Exam.fromKeyString(id: 'yay', name: 'Yayınevi denemesi', className: '9-A', key: keyStr)
        .copyWith(templateId: template.id);
    store.upsertExam(exam);
    store.students.add(const Student(id: 'x', firstName: 'Deniz', lastName: 'Ak', number: '4217', className: '9-A'));
    final spec = specFor(store, exam);
    expect(spec.template, isNotNull);
    final r = readSheet(GrayImage.fromImage(page), spec);
    final sheet = store.addScan(exam, r);
    expect(sheet.studentId, 'x');
    expect(sheetJpeg(GrayImage.fromImage(page), r, spec).length, greaterThan(1000));
    await store.save();
    final again = AppStore();
    await again.load(dir: dir);
    expect(again.templates.single.name, 'Yayınevi formu');
    expect(again.examById('yay')!.templateId, template.id);
    again.deleteTemplate(template.id);
    expect(again.examById('yay')!.templateId, isNull);
  });
}
