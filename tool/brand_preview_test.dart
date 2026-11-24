// Belgelerdeki logo ve mağaza rozeti şeridinin önizlemesi:
// flutter test tool/brand_preview_test.dart → build/brand/
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/store.dart';
import 'package:netice/reports/pdf_documents.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('belge alt şeridi', (tester) async {
    await tester.runAsync(() async {
      final store = AppStore();
      await store.load(dir: Directory.systemTemp.createTempSync('brand'));
      final exam = store.exams.first;
      const school = SchoolInfo(name: 'Örnek Anadolu Lisesi', teacher: 'Ayşe Yılmaz');
      final out = Directory('build/brand')..createSync(recursive: true);
      File('${out.path}/sinav_raporu.pdf').writeAsBytesSync(
          await buildResultsPdf(exam: exam, results: store.resultsOf(exam), students: store.studentById, school: school));
      File('${out.path}/karne.pdf').writeAsBytesSync(await buildStudentCardsPdf(
          exam: exam, results: store.resultsOf(exam).take(2).toList(), students: store.studentById, school: school));
    });
  });
}
