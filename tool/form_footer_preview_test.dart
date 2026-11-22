// Formun alt kısmındaki tanıtım satırlarını önizler:
// flutter test tool/form_footer_preview_test.dart --dart-define=LANG_SHOT=tr
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/store.dart';
import 'package:netice/l10n/l10n.dart';
import 'package:netice/reports/pdf_documents.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('form alt bilgisi', () async {
    const lang = String.fromEnvironment('LANG_SHOT', defaultValue: 'tr');
    L10n.use(lang);
    final store = AppStore()..seedDemo();
    final exam = store.exams.first;
    final pdf = await buildFormsPdf(exam, store.studentsOf(exam.className).take(1).toList(), school: store.reportSchool);
    final out = Directory('build/form_footer')..createSync(recursive: true);
    File('${out.path}/form_$lang.pdf').writeAsBytesSync(pdf);
    L10n.use('tr');
  });
}
