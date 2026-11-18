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

  test('A/B kitapçıklı sınav: sırayla A-B isimli formlar ve iki anahtar', () async {
    final exam = Exam.fromKeyString(id: 'kitapcik', name: 'Kimya Yazılı', className: '10-B', key: 'ABCDEABCDEABCDEABCDE')
        .copyWith(bookletOrder: [for (var i = 0; i < 20; i++) (i * 7) % 20]);
    final forms = await buildFormsPdf(exam, const [
      Student(id: '1', firstName: 'Ada', lastName: 'Er', number: '1201', className: '10-B'),
      Student(id: '2', firstName: 'Can', lastName: 'Su', number: '1202', className: '10-B'),
    ], alternateBooklets: true);
    final blank = await buildFormsPdf(exam, const []);
    final key = await buildAnswerKeyPdf(exam);
    final out = Directory('build/test_output')..createSync(recursive: true);
    File('${out.path}/kitapcik_formlar.pdf').writeAsBytesSync(forms);
    File('${out.path}/kitapcik_bos.pdf').writeAsBytesSync(blank);
    File('${out.path}/kitapcik_anahtar.pdf').writeAsBytesSync(key);
    expect(String.fromCharCodes(key.take(5)), '%PDF-');
  });
}
