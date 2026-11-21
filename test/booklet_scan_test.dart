import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/scoring.dart';
import 'package:netice/core/store.dart';
import 'package:netice/omr/form_code.dart';
import 'package:netice/omr/form_layout.dart';
import 'package:netice/omr/form_raster.dart';
import 'package:netice/omr/omr_reader.dart';

/// Basılı A/B kitapçıklı formların (PDF'ten üretilip kalemle doldurulmuş gibi
/// işaretlenmiş, döndürülmüş JPEG) okunması.
void main() {
  Exam exam() => Exam.fromKeyString(id: 'kitapcik', name: 'Kimya Yazılı', className: '10-B', key: 'ABCDEABCDEABCDEABCDE')
      .copyWith(bookletOrders: [
        [for (var i = 0; i < 20; i++) (i * 7) % 20]
      ]);

  AppStore store(Exam e) => AppStore()
    ..exams.add(e)
    ..students.addAll(const [
      Student(id: 's1', firstName: 'Ada', lastName: 'Er', number: '1201', className: '10-B'),
      Student(id: 's2', firstName: 'Can', lastName: 'Su', number: '1202', className: '10-B'),
    ]);

  test('isimli B formu: numara işaretlenmese de öğrenci ve kitapçık makine kodundan bulunur', () {
    final e = exam();
    final r = readerFor(e).read(GrayImage.decode(File('test/fixtures/booklet_named_b.jpg').readAsBytesSync())!);
    expect(r.code, isNotNull);
    expect(r.code!.examCode, FormCode.examCodeOf('kitapcik'));
    expect(r.code!.studentNumber, 1202);
    expect(r.booklet, 1);
    final st = store(e);
    final sheet = st.addScan(e, r);
    expect(sheet.studentId, 's2');
    expect(sheet.booklet, 1);
    final res = Scorer.score(e, sheet);
    expect(res.correct, 19, reason: 'B sırasıyla işaretlenen 19 doğru A sırasına çevrilmeli');
    expect(res.blank, 1);
    // B'deki 8. soru (boş bırakıldı) A'daki ${e.bookletOrders[0][7] + 1}. sorudur.
    expect(sheet.answers[e.bookletOrders[0][7]].state, MarkState.blank);
  });

  test('boş B formu: öğrencinin işaretlediği kitapçık ve numara okunur', () {
    final e = exam();
    final r = readerFor(e).read(GrayImage.decode(File('test/fixtures/booklet_blank_b.jpg').readAsBytesSync())!);
    expect(r.studentNumber, '001201');
    expect(r.booklet, 1);
    expect(r.code?.studentNumber, isNull);
    final sheet = store(e).addScan(e, r);
    expect(sheet.studentId, 's1');
    expect(Scorer.score(e, sheet).score, 100);
  });

  test('başka sınavın kâğıdı okutulursa makine koduyla doğru sınava kaydedilir', () {
    final e = exam();
    final other = Exam.fromKeyString(id: 'baska', name: 'Başka', className: '10-B', key: 'EEEEEEEEEEEEEEEEEEEE')
        .copyWith(bookletOrders: e.bookletOrders);
    final st = store(e)..exams.add(other);
    final r = readerFor(other).read(GrayImage.decode(File('test/fixtures/booklet_named_b.jpg').readAsBytesSync())!);
    final sheet = st.addScan(other, r);
    expect(sheet.examId, 'kitapcik');
  });

  group('C, D… kitapçıkları', () {
    // 20 soru, 4 ve 8 kitapçık; her kitapçık farklı bir kaydırmalı sıra.
    Exam many(int n) => Exam.fromKeyString(id: 'cok_kitapcik_$n', name: 'Tarih', className: '10-B', key: 'ABCDEABCDEABCDEABCDE')
        .copyWith(bookletOrders: [
      for (var b = 1; b < n; b++) [for (var i = 0; i < 20; i++) (i * const [3, 7, 9, 11, 13, 17, 19][b - 1] + b) % 20]
    ]);

    for (final n in [3, 4, 6, 8]) {
      test('$n kitapçık: her kitapçığın dairesi okunur ve kâğıt kendi anahtarıyla puanlanır', () {
        final e = many(n);
        final layout = FormLayout(questionCount: 20, choiceCount: 5, booklets: n);
        for (var b = 0; b < n; b++) {
          // Öğrenci tüm soruları kendi kitapçığının doğru şıkkıyla doldurur.
          final key = e.questionsOf(b);
          final im = FormRaster(layout).render(
            answers: {for (var i = 0; i < 20; i++) i: [key[i].correct.first]},
            studentNumber: '001201',
            booklet: b,
          );
          final r = readerFor(e).read(GrayImage.fromImage(im));
          expect(r.booklet, b, reason: 'kitapçık ${Exam.bookletLetter(b)}');
          final sheet = store(e).addScan(e, r);
          expect(sheet.booklet, b);
          expect(Scorer.score(e, sheet).score, 100, reason: 'kitapçık ${Exam.bookletLetter(b)}');
        }
      });
    }

    test('daire işaretlenmemişse kitapçık makine kodundan bulunur', () {
      final e = many(5);
      final layout = FormLayout(questionCount: 20, choiceCount: 5, booklets: 5);
      final key = e.questionsOf(4);
      final im = FormRaster(layout).render(
        answers: {for (var i = 0; i < 20; i++) i: [key[i].correct.first]},
        code: FormCode(examCode: FormCode.examCodeOf(e.id), studentNumber: 1202, booklet: 4),
      );
      final r = readerFor(e).read(GrayImage.fromImage(im));
      expect(r.booklet, isNull);
      expect(r.code?.resolve(FormCode.examCodeOf(e.id))?.booklet, 4);
      final sheet = store(e).addScan(e, r);
      expect(sheet.studentId, 's2');
      expect(sheet.booklet, 4);
      expect(Scorer.score(e, sheet).score, 100);
    });

    test('kitapçık daireleri birbirine ve diğer alanlara değmez', () {
      for (var n = 2; n <= FormLayout.maxBooklets; n++) {
        final l = FormLayout(questionCount: 100, choiceCount: 5, booklets: n);
        final pts = [for (var k = 0; k < n; k++) l.bookletBubble(k)];
        for (var i = 0; i < n; i++) {
          final p = pts[i];
          // Öğrenci numarası kutusu (x ≥ 134) ve cevap alanı (y ≥ 101.8) dışında.
          expect(p.x + FormLayout.bubbleRadius, lessThan(132), reason: '$n kitapçık');
          expect(p.y + FormLayout.bubbleRadius, lessThan(97), reason: '$n kitapçık');
          for (var j = i + 1; j < n; j++) {
            final d = (p.x - pts[j].x).abs() + (p.y - pts[j].y).abs();
            expect(d, greaterThan(FormLayout.bubbleRadius * 2.5), reason: '$n kitapçık: $i–$j');
          }
        }
      }
    });
  });
}
