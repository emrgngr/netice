import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/import_export.dart';
import 'package:netice/core/store.dart';
import 'package:netice/core/term.dart';
import 'package:netice/reports/pdf_documents.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dönem aralıkları: Kasım 1. döneme, Mart 2. döneme düşer', () {
    expect(Term.current(DateTime(2026, 11, 18)).label, '1. dönem (2026-2027)');
    expect(Term.current(DateTime(2027, 3, 1)).label, '2. dönem (2026-2027)');
    expect(Term.around(DateTime(2026, 11, 18)).last.contains(DateTime(2027, 5, 1)), isTrue);
  });

  test('dönem notu: ağırlıklı ortalama, girmeyen sınav ortalamaya katılmaz', () async {
    final store = AppStore()..seedDemo();
    final exams = store.exams.where((e) => e.className == '9-A' && store.sheetsOf(e.id).isNotEmpty).toList();
    expect(exams.length, greaterThanOrEqualTo(2));
    final term = Term('Tüm', DateTime(2000), DateTime(2100));
    // Bir öğrencinin ilk sınav kâğıdını kaldır.
    final first = (exams..sort((a, b) => a.date.compareTo(b.date))).first;
    store.sheets.removeWhere((s) => s.examId == first.id && s.studentId == 'demo_0');
    final rep = TermReport.build(store, '9-A', term, exams, weights: {exams.last.id: 2});
    final r0 = rep.rows.firstWhere((r) => r.student.id == 'demo_0');
    expect(r0.scores.first, isNull);
    expect(r0.average, closeTo(r0.scores.last!, 1e-9));
    final r1 = rep.rows.firstWhere((r) => r.student.id == 'demo_1');
    expect(r1.average, closeTo((r1.scores.first! + 2 * r1.scores.last!) / 3, 1e-9));
    expect(r1.outcomes, isNotEmpty);
    expect(termCsv(rep), contains('Dönem notu'));

    final grades = await buildTermGradesPdf(rep);
    final cards = await buildTermCardsPdf(rep);
    for (final b in [grades, cards]) {
      expect(String.fromCharCodes(b.take(5)), '%PDF-');
    }
    final out = Directory('build/test_output')..createSync(recursive: true);
    File('${out.path}/donem_not_cizelgesi.pdf').writeAsBytesSync(grades);
    File('${out.path}/donem_karnesi.pdf').writeAsBytesSync(await buildTermCardsPdf(rep, onlyStudentId: 'demo_1'));
  });
}
