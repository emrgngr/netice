import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/store.dart';
import 'package:netice/omr/form_layout.dart';
import 'package:netice/omr/form_raster.dart';
import 'package:netice/omr/omr_reader.dart';

void main() {
  Exam exam({int booklets = 1}) => Exam(
        id: 'e10',
        name: 'On hane',
        className: '9-A',
        date: DateTime(2026, 11, 22),
        choiceCount: 5,
        questions: [for (var i = 0; i < 30; i++) Question(no: i + 1, correct: {i % 5})],
        bookletOrders: [
          for (var b = 1; b < booklets; b++) [for (var i = 0; i < 30; i++) i]
        ],
        numberDigits: 10,
      );

  test('10 haneli numara okunur, öğrenciyle eşleşir', () {
    for (final n in [1, 2, 4, 8]) {
      final e = exam(booklets: n);
      final layout = FormLayout(questionCount: 30, choiceCount: 5, booklets: n, digits: 10);
      final im = FormRaster(layout).render(
        answers: {for (var i = 0; i < 30; i++) i: [i % 5]},
        studentNumber: '2026104217',
        booklet: n > 1 ? n - 1 : null,
      );
      final r = readerFor(e).read(GrayImage.fromImage(im));
      expect(r.studentNumber, '2026104217', reason: '$n kitapçık');
      if (n > 1) expect(r.booklet, n - 1, reason: '$n kitapçık');
      final store = AppStore()
        ..students.add(Student(id: 's1', firstName: 'Ali', lastName: 'Kaya', number: '2026104217', className: '9-A'))
        ..exams.add(e);
      expect(store.addScan(e, r).studentId, 's1');
    }
  });

  test('10 haneli yerleşimde daireler birbirine ve bilgi alanlarına değmez', () {
    for (var n = 1; n <= FormLayout.maxBooklets; n++) {
      final l = FormLayout(questionCount: 100, choiceCount: 5, booklets: n, digits: 10);
      final first = l.studentBubble(0, 0), last = l.studentBubble(9, 9);
      expect(first.x - 6, greaterThan(l.infoRight + 2));
      expect(last.x + 6, lessThanOrEqualTo(186));
      expect(l.studentBubble(1, 0).x - first.x, greaterThan(FormLayout.bubbleRadius * 2.4));
      for (var k = 0; k < n && n > 1; k++) {
        final p = l.bookletBubble(k);
        expect(p.x + FormLayout.bubbleRadius, lessThan(l.infoRight), reason: '$n kitapçık');
      }
    }
  });

  test('eski sınavlar 6 hane kalır; yeni alan JSON ile korunur', () {
    final old = Exam.fromJson({...exam().toJson()}..remove('numberDigits'));
    expect(old.numberDigits, 6);
    expect(Exam.fromJson(exam().toJson()).numberDigits, 10);
  });
}
