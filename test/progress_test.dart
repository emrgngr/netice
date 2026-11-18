import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/import_export.dart';
import 'package:netice/core/progress.dart';
import 'package:netice/core/store.dart';
import 'package:netice/reports/pdf_documents.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('örnek veride öğrenci geçmişi, erken uyarı ve şube grupları', () {
    final store = AppStore()..seedDemo();
    final s = store.studentById['demo_0']!;
    final h = historyOf(store, s);
    expect(h.length, 2);
    expect(h.first.exam.date.isBefore(h.last.exam.date), isTrue);
    expect(outcomeSummary(h).keys, containsAll(['Hareket', 'Enerji']));
    final w = earlyWarnings(store);
    expect(w, isNotEmpty);
    expect(w.every((x) => x.reason.isNotEmpty), isTrue);
    final g = sameNameGroups(store);
    expect(g.values.single.map((e) => e.className).toSet(), {'9-A', '9-B'});
  });

  test('e-Okul listesi numara sırasında; girmeyen öğrenci G', () {
    final store = AppStore()..seedDemo();
    final exam = store.examById('demo_exam')!;
    final cls = store.studentsOf('9-A');
    final results = store.resultsOf(exam).where((r) => r.sheet.studentId != 'demo_3').toList();
    final rows = eokulRows(exam, results, cls);
    expect(rows.map((r) => int.parse(r.$1.number)).toList(), [for (var i = 0; i < 24; i++) 1040 + i]);
    expect(rows[3].$2, isNull);
    expect(eokulCsv(exam, results, cls), contains('Sınava girmedi'));
  });

  test('karşılaştırma, e-Okul ve etiket PDF\'leri üretilir', () async {
    final store = AppStore()..seedDemo();
    final groups = sameNameGroups(store).values.single;
    final cmp = await buildComparePdf(compareExams(store, groups));
    final exam = store.examById('demo_exam')!;
    final results = store.resultsOf(exam);
    final eokul = await buildEokulPdf(exam: exam, results: results, classStudents: store.studentsOf('9-A'));
    final labels = await buildLabelsPdf(exam: exam, results: results, students: store.studentById);
    for (final b in [cmp, eokul, labels]) {
      expect(String.fromCharCodes(b.take(5)), '%PDF-');
    }
    final out = Directory('build/test_output')..createSync(recursive: true);
    File('${out.path}/sube_karsilastirmasi.pdf').writeAsBytesSync(cmp);
    File('${out.path}/eokul_listesi.pdf').writeAsBytesSync(eokul);
    File('${out.path}/sonuc_etiketleri.pdf').writeAsBytesSync(labels);
  });
}
