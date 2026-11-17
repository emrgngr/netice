import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/import_export.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/scoring.dart';
import 'package:netice/core/store.dart';
import 'package:netice/omr/form_layout.dart';
import 'package:netice/omr/form_raster.dart';
import 'package:netice/omr/omr_reader.dart';
import 'package:netice/reports/pdf_documents.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Türkçe Excel CSV listesi (noktalı virgül, başlıklı) aktarılır', () {
    const csv = 'Okul No;Adı;Soyadı;Sınıf\n1042;Elif;Kaya;9-A\n1043;Mert Can;Yıldız;9-A\n';
    final list = StudentImport.parse(csv);
    expect(list.length, 2);
    expect(list[1].firstName, 'Mert Can');
    expect(list[1].lastName, 'Yıldız');
    expect(list[0].number, '1042');
    expect(list[0].className, '9-A');
  });

  test('"Ad Soyad" tek sütun ve sınıf sütunu yoksa', () {
    final list = StudentImport.parse('No,Ad Soyad\n7,Zeynep Aydın\n', defaultClass: '10-B');
    expect(list.single.firstName, 'Zeynep');
    expect(list.single.lastName, 'Aydın');
    expect(list.single.className, '10-B');
  });

  test('örnek veri, okuma ve öğrenci eşleştirme uçtan uca çalışır', () async {
    final dir = await Directory.systemTemp.createTemp('netice');
    final store = AppStore();
    await store.load(dir: dir);
    final exam = store.exams.first;
    expect(store.sheetsOf(exam.id).length, 24);

    // Elif Kaya (1041) için örnek formu oku: önceki kâğıdı yenisiyle değiştirmeli.
    final raster = FormRaster(FormLayout(questionCount: exam.questionCount, choiceCount: exam.choiceCount));
    final key = {for (var q = 0; q < exam.questionCount; q++) q: [exam.questions[q].correct.first]};
    final r = readerFor(exam).read(GrayImage.fromImage(raster.render(answers: key, studentNumber: '001041')));
    final sheet = store.addScan(exam, r);
    expect(store.studentById[sheet.studentId]!.fullName, 'Elif Kaya');
    expect(store.sheetsOf(exam.id).length, 24);
    expect(Scorer.score(exam, sheet).score, 100);

    // Kalıcılık: yeniden yüklenince aynı veri gelir.
    final again = AppStore();
    await again.load(dir: dir);
    expect(again.sheetsOf(exam.id).length, 24);
    final csv = resultsCsv(exam, again.resultsOf(exam), again.studentById);
    expect(csv, contains('Elif;Kaya'));
  });

  test('optik form ve sonuç raporu PDF olarak üretilir', () async {
    final exam = Exam.fromKeyString(id: 'x', name: 'Deneme Sınavı', className: '9-A', key: 'ABCDEABCDEABCDEABCDE');
    final forms = await buildFormsPdf(exam, const [
      Student(id: '1', firstName: 'Şule', lastName: 'Güneş', number: '1042', className: '9-A'),
    ]);
    expect(String.fromCharCodes(forms.take(5)), '%PDF-');
    final sheets = [
      for (var i = 0; i < 5; i++)
        Sheet(examId: 'x', studentId: null, answers: [for (var q = 0; q < 20; q++) Answer.choice((q + i) % 5)])
    ];
    final report = await buildResultsPdf(exam: exam, results: Scorer.scoreAll(exam, sheets), students: const {});
    expect(report.length, greaterThan(1000));
    final out = Directory('build/test_output')..createSync(recursive: true);
    File('${out.path}/ornek_form.pdf').writeAsBytesSync(forms);
    File('${out.path}/ornek_rapor.pdf').writeAsBytesSync(report);
  });
}
