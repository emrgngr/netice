
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:netice/bank/bank_models.dart';
import 'package:netice/bank/booklet_builder.dart';
import 'package:netice/core/models.dart';
import 'package:netice/omr/form_code.dart';
import 'package:netice/omr/form_layout.dart';
import 'package:netice/omr/kid_layout.dart';
import 'package:netice/omr/omr_reader.dart';
import 'package:netice/omr/sheet_reader.dart';

/// Kutuyu bir sayfa görüntüsüne çizer: kutunun sol üst köşesi [ox], [oy] (mm).
/// Sayfaya kutunun dışında yanıltıcı koyu kareler ve renkli daireler de konur.
img.Image page(KidLayout l,
    {double ox = 128, double oy = 190, double px = 6, Map<int, int> answers = const {}, FormCode? code, bool distractors = true}) {
  final im = img.Image(width: (210 * px).round(), height: (297 * px).round(), numChannels: 3)
    ..clear(img.ColorRgb8(255, 255, 255));
  int p(double mm) => (mm * px).round();
  final black = img.ColorRgb8(0, 0, 0);
  if (distractors) {
    // Sayfa numarası kutusu, logo, renkli numara rozetleri, resim.
    img.fillRect(im, x1: p(14), y1: p(282), x2: p(22), y2: p(288), color: img.ColorRgb8(43, 58, 103), radius: p(2));
    img.fillRect(im, x1: p(186), y1: p(282), x2: p(192), y2: p(288), color: img.ColorRgb8(15, 27, 61));
    img.fillRect(im, x1: p(16), y1: p(16), x2: p(22), y2: p(22), color: img.ColorRgb8(30, 30, 30));
    for (var i = 0; i < 6; i++) {
      img.fillCircle(im, x: p(22), y: p(60 + i * 30), radius: p(3.2), color: img.ColorRgb8(80 + i * 20, 120, 200 - i * 20));
    }
    img.fillRect(im, x1: p(30), y1: p(130), x2: p(100), y2: p(160), color: img.ColorRgb8(120, 160, 90));
  }
  for (final o in l.markerOrigins) {
    img.fillRect(im, x1: p(ox + o.x), y1: p(oy + o.y), x2: p(ox + o.x + KidLayout.markerSize), y2: p(oy + o.y + KidLayout.markerSize), color: black);
  }
  final ring = img.ColorRgb8(125, 137, 168);
  for (var q = 0; q < l.questionCount; q++) {
    for (var c = 0; c < l.choiceCount; c++) {
      final b = l.answerBubble(q, c);
      img.drawCircle(im, x: p(ox + b.x), y: p(oy + b.y), radius: p(KidLayout.bubbleRadius), color: ring);
      if (answers[q] == c) {
        img.fillCircle(im, x: p(ox + b.x), y: p(oy + b.y), radius: p(KidLayout.bubbleRadius * 0.92), color: img.ColorRgb8(50, 50, 55));
      }
    }
  }
  final bits = code?.encode();
  if (bits != null) {
    for (var i = 0; i < bits.length; i++) {
      if (!bits[i]) continue;
      final c = l.codeCell(i);
      const h = KidLayout.codeCellSize / 2;
      img.fillRect(im, x1: p(ox + c.x - h), y1: p(oy + c.y - h), x2: p(ox + c.x + h), y2: p(oy + c.y + h), color: black);
    }
  }
  return im;
}

GrayImage gray(img.Image im) => GrayImage.fromImage(im);

void main() {
  final l = KidLayout(questionCount: 10, choiceCount: 3);
  final answers = {0: 1, 1: 2, 2: 0, 3: 0, 4: 1, 5: 1, 6: 0, 8: 1, 9: 2};

  void expectAnswers(OmrResult r) {
    for (var q = 0; q < 10; q++) {
      final a = r.questions[q].answer;
      if (answers.containsKey(q)) {
        expect(a.state, MarkState.filled, reason: 'soru ${q + 1} ${r.questions[q].fills}');
        expect(a.marked, {answers[q]}, reason: 'soru ${q + 1}');
      } else {
        expect(a.state, MarkState.blank, reason: 'soru ${q + 1} ${r.questions[q].fills}');
      }
    }
  }

  test('kutu geometrisi: 10 soru tek sütun, 25 soru üç sütun', () {
    expect(l.columns, 1);
    expect(l.width, KidLayout.minWidth);
    final big = KidLayout(questionCount: 25, choiceCount: 3);
    expect(big.columns, 3);
    expect(big.width, greaterThan(KidLayout.minWidth));
    // Daireler birbirine ve köşe karelerine değmez.
    for (var q = 0; q < 25; q++) {
      for (var c = 0; c < 3; c++) {
        final b = big.answerBubble(q, c);
        expect(b.x - KidLayout.bubbleRadius, greaterThan(KidLayout.markerSize));
        expect(b.x + KidLayout.bubbleRadius, lessThan(big.width - KidLayout.markerSize));
      }
    }
    expect(big.codeCell(43).y, lessThan(big.height - KidLayout.markerSize));
  });

  test('sayfanın tamamı çekildiğinde kutu bulunur ve okunur', () {
    final r = KidReader(l).read(gray(page(l, answers: answers)));
    expectAnswers(r);
    expect(r.code, isNull);
  });

  test('yalnız kutu yakından çekildiğinde okunur (makine kodu ile)', () {
    final code = FormCode(examCode: FormCode.examCodeOf('kid1'), studentNumber: 27);
    final full = page(l, answers: answers, code: code, px: 12);
    // Kutunun çevresinden biraz pay bırakarak kırp.
    final crop = img.copyCrop(full, x: (120 * 12), y: (182 * 12), width: ((l.width + 16) * 12).round(), height: ((l.height + 16) * 12).round());
    final r = KidReader(l).read(gray(crop));
    expectAnswers(r);
    expect(r.code?.studentNumber, 27);
    expect(r.code?.resolve(FormCode.examCodeOf('kid1')), isNotNull);
  });

  test('ters ve yan çekilmiş sayfa okunur', () {
    final im = page(l, answers: answers);
    for (final angle in [90, 180, 270]) {
      final r = KidReader(l).read(gray(img.copyRotate(im, angle: angle)));
      expectAnswers(r);
    }
    // Hafif eğik çekim
    final r = KidReader(l).read(gray(img.copyRotate(im, angle: 7, interpolation: img.Interpolation.linear)));
    expectAnswers(r);
  });

  test('kutu yoksa anlaşılır hata verir', () {
    final im = img.Image(width: 800, height: 1100, numChannels: 3)..clear(img.ColorRgb8(255, 255, 255));
    img.fillRect(im, x1: 50, y1: 50, x2: 90, y2: 90, color: img.ColorRgb8(0, 0, 0));
    expect(() => KidReader(l).read(gray(im)), throwsA(isA<OmrException>()));
  });

  test('ReadSpec çocuk formunu seçer; kitapçık planı çocuk sınavı üretir', () {
    final spec = ReadSpec(questions: 10, choices: 3, kids: true);
    expectAnswers(readSheet(gray(page(l, answers: answers)), spec));
    final now = DateTime(2026);
    final qs = [
      for (var i = 0; i < 12; i++)
        BankQuestion(
          id: 'q$i',
          text: 'Soru $i',
          choices: const ['a', 'b', 'c'],
          choiceCount: 3,
          correct: {i % 3},
          created: now,
          updated: now,
        ),
    ];
    final plan = BookletPlan.build(qs, const BookletOptions(style: BookletStyle.kids, bookletCount: 4));
    expect(plan.variants.length, 1, reason: 'çocuk şablonunda tek kitapçık');
    final exam = plan.toExam(id: 'e', name: 'Fen', className: '3-A');
    expect(exam.kidForm, isTrue);
    expect(exam.choiceCount, 3);
    final back = Exam.fromJson(exam.toJson());
    expect(back.kidForm, isTrue);
    // Standart form da 3 şıkla çizilebilir (cevap anahtarı formu için).
    expect(FormLayout(questionCount: 12, choiceCount: 3).answerBubble(0, 2).x, greaterThan(0));
    // Klasik şablon değişmedi.
    final classic = BookletPlan.build(qs, const BookletOptions(bookletCount: 2)).toExam(id: 'c', name: 'x', className: 'y');
    expect(classic.kidForm, isFalse);
    expect(classic.choiceCount, 4);
  });
}
