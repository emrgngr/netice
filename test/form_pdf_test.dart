import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/models.dart';
import 'package:netice/reports/pdf_documents.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('öğrenci formu, boş form ve cevap anahtarı PDF olarak üretilir', () async {
    final exam = Exam.fromKeyString(id: 'demo', name: 'Fizik Quiz 2', className: '9-A', key: 'ABCDEABCDEABCDEABCDE');
    final out = Directory('build/test_output')..createSync(recursive: true);
    final named = await buildFormsPdf(exam, const [
      Student(id: '1', firstName: 'Şule', lastName: 'Güneş', number: '1042', className: '9-A'),
    ]);
    final blank = await buildFormsPdf(exam, const [], blankCopies: 3);
    final key = await buildAnswerKeyPdf(exam);
    final keyBlank = await buildAnswerKeyPdf(exam, filled: false);
    final big = Exam.fromKeyString(
        id: 'big', name: 'Deneme 100', className: '12-A', key: List.filled(25, 'ABCD').join(), choiceCount: 4);
    final bigKey = await buildAnswerKeyPdf(big);
    for (final b in [named, blank, key, keyBlank, bigKey]) {
      expect(String.fromCharCodes(b.take(5)), '%PDF-');
    }
    File('${out.path}/form_ogrenci.pdf').writeAsBytesSync(named);
    File('${out.path}/form_bos.pdf').writeAsBytesSync(blank);
    File('${out.path}/anahtar_dolu.pdf').writeAsBytesSync(key);
    File('${out.path}/anahtar_bos.pdf').writeAsBytesSync(keyBlank);
    File('${out.path}/anahtar_100.pdf').writeAsBytesSync(bigKey);
  });
}
