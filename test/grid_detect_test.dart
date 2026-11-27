import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:netice/core/models.dart';
import 'package:netice/omr/form_layout.dart';
import 'package:netice/omr/grid_detect.dart';
import 'package:netice/omr/homography.dart';
import 'package:netice/omr/omr_reader.dart';
import 'package:netice/omr/template.dart';

/// Yayınevi formunu taklit eden sentetik kâğıt: içinde harf yazan oval
/// daireler, soru numaraları, ad soyad harf ızgarası, yazı kutuları, kenarda
/// zamanlama işaretleri, 10 haneli numara, A/B kitapçık ve cinsiyet alanı.
class FakeForm {
  final int columns; // soru sütunu sayısı
  final int perColumn;
  final int choices;
  final int digits;
  final bool letters;
  final img.Color ink;
  FakeForm({this.columns = 4, this.perColumn = 15, this.choices = 5, this.digits = 10, this.letters = true, img.Color? ink})
      : ink = ink ?? img.ColorRgb8(200, 60, 90);

  static const w = 1000, h = 1414;
  int get questions => columns * perColumn;

  // Soru (0'dan), şık → merkez.
  Pt answer(int q, int c) {
    final col = q ~/ perColumn, row = q % perColumn;
    final pitch = choices == 5 ? 32.0 : 36.0;
    final colW = 60 + pitch * choices;
    return Pt(90 + col * colW + c * pitch, 760 + row * 38.0);
  }

  Pt digit(int d, int v) => Pt(520 + d * 32.0, 200 + v * 34.0);
  Pt booklet(int k) => Pt(880 + k * 44.0, 230);
  Pt gender(int k) => Pt(880 + k * 44.0, 420);
  Pt nameCell(int col, int row) => Pt(70 + col * 22.0, 140 + row * 19.0);

  img.Image render({Map<int, int> marks = const {}, String number = '', int? bookletMark, String name = ''}) {
    final im = img.Image(width: w, height: h, numChannels: 3);
    img.fill(im, color: img.ColorRgb8(252, 251, 248));
    img.drawString(im, 'DENEME SINAVI CEVAP KAGIDI', font: img.arial24, x: 300, y: 40, color: img.ColorRgb8(20, 20, 20));
    // Zamanlama işaretleri (sağ kenar).
    for (var y = 120; y < h - 60; y += 38) {
      img.fillRect(im, x1: 975, y1: y, x2: 990, y2: y + 9, color: img.ColorRgb8(10, 10, 10));
    }
    void bubble(Pt p, double rx, double ry, String label, bool filled) {
      img.drawCircle(im, x: p.x.round(), y: p.y.round(), radius: ry.round(), color: ink);
      if (rx > ry) {
        img.drawCircle(im, x: p.x.round() - 2, y: p.y.round(), radius: ry.round(), color: ink);
        img.drawCircle(im, x: p.x.round() + 2, y: p.y.round(), radius: ry.round(), color: ink);
      }
      if (letters && label.isNotEmpty) {
        img.drawString(im, label, font: img.arial14, x: p.x.round() - 4, y: p.y.round() - 8, color: ink);
      }
      if (filled) {
        img.fillCircle(im, x: p.x.round(), y: p.y.round(), radius: (ry * 0.95).round(), color: img.ColorRgb8(35, 35, 40));
      }
    }

    // Ad soyad: 12 sütun × 29 harf.
    for (var c = 0; c < 12; c++) {
      img.drawRect(im, x1: (nameCell(c, 0).x - 9).round(), y1: 110, x2: (nameCell(c, 0).x + 9).round(), y2: 128, color: ink);
      for (var r = 0; r < 29; r++) {
        bubble(nameCell(c, r), 7, 7, '', c < name.length && NameBlock.turkish.indexOf(name[c]) == r);
      }
    }
    // Numara: yazı kutuları + 0–9.
    for (var d = 0; d < digits; d++) {
      final p = digit(d, 0);
      img.drawRect(im, x1: (p.x - 12).round(), y1: 160, x2: (p.x + 12).round(), y2: 184, color: ink);
      for (var v = 0; v < 10; v++) {
        bubble(digit(d, v), 10, 10, '$v', d < number.length && number[d] == '$v');
      }
    }
    img.drawString(im, 'KITAPCIK', font: img.arial14, x: 870, y: 190, color: ink);
    for (var k = 0; k < 2; k++) {
      bubble(booklet(k), 12, 12, 'AB'[k], bookletMark == k);
    }
    img.drawString(im, 'CINSIYET', font: img.arial14, x: 870, y: 380, color: ink);
    for (var k = 0; k < 2; k++) {
      bubble(gender(k), 11, 11, 'EK'[k], false);
    }
    for (var q = 0; q < questions; q++) {
      final p0 = answer(q, 0);
      img.drawString(im, '${q + 1}', font: img.arial14, x: (p0.x - 42).round(), y: (p0.y - 8).round(), color: img.ColorRgb8(30, 30, 30));
      for (var c = 0; c < choices; c++) {
        bubble(answer(q, c), 12, 10, 'ABCDE'[c], marks[q] == c);
      }
    }
    return im;
  }
}

img.Image photo(img.Image page, List<Pt> quad, {int w = 1500, int h = 2000, double blur = 0}) {
  final out = img.Image(width: w, height: h, numChannels: 3);
  img.fill(out, color: img.ColorRgb8(70, 60, 55));
  final inv = Homography.fromPoints(
      quad, [Pt(0, 0), Pt(page.width.toDouble(), 0), Pt(page.width.toDouble(), page.height.toDouble()), Pt(0, page.height.toDouble())]);
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
  List<Pt> full(GrayImage g) => [Pt(0, 0), Pt(g.width - 1.0, 0), Pt(g.width - 1.0, g.height - 1.0), Pt(0, g.height - 1.0)];

  void expectStructure(DetectedForm d, FakeForm f, String label, {double tol = 4}) {
    expect(d.blocks.length, f.columns, reason: '$label: blok sayısı ${[for (final b in d.blocks) '${b.start}/${b.count}x${b.choices}']}');
    for (final (i, b) in d.blocks.indexed) {
      expect(b.start, 1 + i * f.perColumn, reason: '$label: blok $i başlangıcı');
      expect(b.count, f.perColumn, reason: '$label: blok $i soru sayısı');
      expect(b.choices, f.choices, reason: '$label: blok $i şık');
      expect(b.first.x, closeTo(f.answer(i * f.perColumn, 0).x, tol), reason: '$label: blok $i ilk daire');
      expect(b.last.y, closeTo(f.answer((i + 1) * f.perColumn - 1, 0).y, tol), reason: '$label: blok $i son daire');
    }
    expect(d.number?.digits, f.digits, reason: '$label: numara');
    expect(d.number!.first.x, closeTo(f.digit(0, 0).x, tol));
    expect(d.number!.last.y, closeTo(f.digit(0, 9).y, tol));
    expect(d.booklet?.count, 2, reason: '$label: kitapçık');
    expect(d.booklet!.first.y, closeTo(f.booklet(0).y, tol), reason: '$label: kitapçık yeri (cinsiyet değil)');
  }

  final rnd = math.Random(7);

  for (final (label, form) in [
    ('5 şık, harfli oval daire', FakeForm()),
    ('4 şık, harfsiz, 3 sütun, 8 hane', FakeForm(columns: 3, perColumn: 16, choices: 4, digits: 8, letters: false)),
    ('açık gri baskı', FakeForm(ink: img.ColorRgb8(150, 150, 150))),
  ]) {
    test('boş form taranınca ızgaralar bulunur: $label', () {
      final g = GrayImage.fromImage(form.render());
      expectStructure(detectFormGrids(g, full(g)), form, label);
    });
  }

  test('dolu form fotoğrafı: ızgaralar bulunur ve okunur', () {
    final form = FakeForm();
    final key = {for (var q = 0; q < form.questions; q++) if (q % 7 != 3) q: rnd.nextInt(5)};
    final page = form.render(marks: key, number: '0012345678', bookletMark: 1);
    final im = photo(page, [Pt(210, 150), Pt(1300, 210), Pt(1350, 1830), Pt(160, 1770)], blur: 1);
    final g = GrayImage.fromImage(im);
    final corners = PageFinder.find(g);
    final d = detectFormGrids(g, corners);
    // Fotoğrafta kâğıt kenarı birkaç birim kayık bulunabilir; okuma aynı düzlemde yapıldığı için sorun değil.
    expectStructure(d, form, 'fotoğraf', tol: 12);
    final t = d.applyTo(const FormTemplate(id: 'x', name: 'x'));
    final r = TemplateReader(t, questionCount: form.questions, choiceCount: 5).read(g);
    expect(r.studentNumber, '0012345678');
    expect(r.booklet, 1);
    for (var q = 0; q < form.questions; q++) {
      final a = r.questions[q].answer;
      if (key[q] == null) {
        expect(a.state, MarkState.blank, reason: 'soru ${q + 1} ${r.questions[q].fills}');
      } else {
        expect(a.marked, {key[q]}, reason: 'soru ${q + 1} ${r.questions[q].fills}');
      }
    }
  });

  test('4 şıklı form, gölgeli eğik fotoğraf: bulunur ve okunur', () {
    final form = FakeForm(columns: 3, perColumn: 16, choices: 4, digits: 8, letters: false);
    final key = {for (var q = 0; q < form.questions; q++) if (q % 5 != 2) q: rnd.nextInt(4)};
    final page = form.render(marks: key, number: '00004217', bookletMark: 0);
    final im = photo(page, [Pt(260, 120), Pt(1330, 190), Pt(1300, 1860), Pt(190, 1800)], blur: 1);
    // Soldan sağa kararan ışık.
    for (final p in im) {
      final k = 1 - 0.35 * p.x / im.width;
      p
        ..r = p.r * k
        ..g = p.g * k
        ..b = p.b * k;
    }
    final g = GrayImage.fromImage(im);
    final d = detectFormGrids(g, PageFinder.find(g));
    expectStructure(d, form, 'gölgeli', tol: 12);
    final r = TemplateReader(d.applyTo(const FormTemplate(id: 'x', name: 'x')), questionCount: form.questions, choiceCount: 4).read(g);
    expect(r.studentNumber, '00004217');
    expect(r.booklet, 0);
    for (var q = 0; q < form.questions; q++) {
      final a = r.questions[q].answer;
      expect(a.marked, key[q] == null ? isEmpty : {key[q]}, reason: 'soru ${q + 1} ${r.questions[q].fills}');
    }
  });

  test('ad soyad alanı bulunur ve okunur; numara yoksa öğrenci addan bulunur', () {
    final form = FakeForm();
    final page = form.render(marks: {0: 1}, name: 'ŞULE ÖZ', bookletMark: 0);
    final im = photo(page, [Pt(210, 150), Pt(1300, 210), Pt(1350, 1830), Pt(160, 1770)], blur: 1);
    final g = GrayImage.fromImage(im);
    final d = detectFormGrids(g, PageFinder.find(g));
    expect(d.name, isNotNull);
    expect(d.name!.columns, 12);
    expect(d.name!.letters, NameBlock.turkish);
    final r = TemplateReader(d.applyTo(const FormTemplate(id: 'x', name: 'x')), questionCount: form.questions, choiceCount: 5).read(g);
    expect(r.name, 'ŞULE ÖZ');
  });

  test('ad soyad alfabesi satır sayısından ve dilden seçilir', () {
    expect(NameBlock.alphabetFor(29, 'tr'), NameBlock.turkish);
    expect(NameBlock.alphabetFor(29, 'de'), contains('Ä'));
    expect(NameBlock.alphabetFor(26, 'fr'), NameBlock.english);
    expect(NameBlock.alphabetFor(27, 'es'), contains('Ñ'));
    expect(NameBlock.alphabetFor(33, 'ru'), startsWith('АБВ'));
    expect(NameBlock.alphabetFor(32, 'az'), contains('Ə'));
    expect(NameBlock.alphabetFor(28, 'ar'), startsWith('ا'));
    expect(NameBlock.alphabetFor(40, 'tr'), isNull);
  });

  test('şablon paylaşım dosyası yeni kimlikle açılır', () {
    final g = GrayImage.fromImage(FakeForm().render());
    final t = detectFormGrids(g, full(g)).applyTo(const FormTemplate(id: 'a', name: 'X Yayınları'));
    final back = FormTemplate.fromShareJson(t.toShareJson())!;
    expect(back.id, isNot('a'));
    expect(back.name, 'X Yayınları');
    expect(back.blocks.length, 4);
    expect(back.booklet!.count, 2);
    expect(FormTemplate.fromShareJson({'kind': 'baska'}), isNull);
  });
}
