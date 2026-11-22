import 'dart:convert';
import 'dart:io';

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

  test('eski sürümden gelen, hiç okunmamış sınav 10 haneye geçer; okunmuş olan 6 da kalır', () async {
    final dir = Directory.systemTemp.createTempSync('onhane');
    final old = AppStore()..seedDemo();
    final m = jsonDecode(jsonEncode(old.toJsonMap())) as Map<String, dynamic>;
    for (final e in m['exams'] as List) {
      (e as Map).remove('numberDigits');
    }
    // Öğretmenin kendi sınavları: biri okunmuş, biri hiç okunmamış.
    final mine = Exam.fromKeyString(id: 'benim', name: 'Kendi', className: '9-A', key: 'ABCD').toJson()..remove('numberDigits');
    final read = Exam.fromKeyString(id: 'okunmus', name: 'Okunmuş', className: '9-A', key: 'ABCD').toJson()..remove('numberDigits');
    (m['exams'] as List).addAll([mine, read]);
    final s0 = (m['sheets'] as List).first as Map;
    (m['sheets'] as List).add({...s0, 'id': 'k1', 'examId': 'okunmus'});
    File('${dir.path}/netice_data.json').writeAsStringSync(jsonEncode(m));
    final st = AppStore();
    await st.load(dir: dir);
    for (final e in st.exams) {
      expect(e.numberDigits, e.id == 'okunmus' ? 6 : 10, reason: e.id);
    }
    // Kaydedildi: yeniden açınca aynı kalır, ayarlardan seçilen 6 da korunur.
    final again = AppStore();
    await again.load(dir: dir);
    expect([for (final e in again.exams) e.numberDigits], [for (final e in st.exams) e.numberDigits]);
  });

  test('yeni sınav varsayılan olarak 10 hanelidir', () {
    final e = Exam.fromKeyString(id: 'x', name: 'x', className: '9-A', key: 'ABCD');
    expect(e.numberDigits, 10);
    expect(Exam.fromJson(e.toJson()).numberDigits, 10);
    expect(Exam.fromJson(e.copyWith(numberDigits: 6).toJson()).numberDigits, 6);
  });
}
