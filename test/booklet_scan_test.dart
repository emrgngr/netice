import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/scoring.dart';
import 'package:netice/core/store.dart';
import 'package:netice/omr/form_code.dart';
import 'package:netice/omr/omr_reader.dart';

/// Basılı A/B kitapçıklı formların (PDF'ten üretilip kalemle doldurulmuş gibi
/// işaretlenmiş, döndürülmüş JPEG) okunması.
void main() {
  Exam exam() => Exam.fromKeyString(id: 'kitapcik', name: 'Kimya Yazılı', className: '10-B', key: 'ABCDEABCDEABCDEABCDE')
      .copyWith(bookletOrder: [for (var i = 0; i < 20; i++) (i * 7) % 20]);

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
    // B'deki 8. soru (boş bırakıldı) A'daki ${e.bookletOrder![7] + 1}. sorudur.
    expect(sheet.answers[e.bookletOrder![7]].state, MarkState.blank);
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
        .copyWith(bookletOrder: e.bookletOrder);
    final st = store(e)..exams.add(other);
    final r = readerFor(other).read(GrayImage.decode(File('test/fixtures/booklet_named_b.jpg').readAsBytesSync())!);
    final sheet = st.addScan(other, r);
    expect(sheet.examId, 'kitapcik');
  });
}
