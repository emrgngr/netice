// Çok dersli deneme sınavı ekranlarının önizlemesi (TYT düzeninde örnek sınıf).
//   flutter test tool/deneme_onizleme_test.dart
// Çıktılar build/screenshots/deneme_*.png ve build/screenshots/deneme.pdf.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/deneme.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/store.dart';
import 'package:netice/main.dart';
import 'package:netice/reports/pdf_documents.dart';
import 'package:netice/reports/report_docx.dart';
import 'package:netice/ui/deneme_screen.dart';
import 'package:netice/ui/exam_screen.dart';
import 'package:netice/ui/sections_screen.dart';
import 'package:netice/ui/theme.dart';

import 'screenshots_test.dart' show loadFonts, shot;

void main() {
  testWidgets('deneme ekranları', timeout: const Timeout(Duration(minutes: 3)), (tester) async {
    await tester.runAsync(loadFonts);
    final store = AppStore();
    await tester.runAsync(() => store.load(dir: Directory.systemTemp.createTempSync('deneme')));
    final rnd = math.Random(7);
    final key = List.generate(120, (_) => rnd.nextInt(5));
    final exam = Exam.fromKeyString(
      id: 'deneme1',
      name: 'TYT Deneme 3',
      className: '12-A',
      key: key.map((k) => String.fromCharCode(65 + k)).join(),
      rule: const ScoringRule(wrongsPerCorrect: 4, maxScore: 100),
      date: DateTime(2026, 11, 20, 10),
    ).copyWith(
      sections: ExamSection.fromCounts([
        ('Türkçe', 40, 3.3),
        ('Sosyal Bilimler', 20, 3.4),
        ('Temel Matematik', 40, 3.3),
        ('Fen Bilimleri', 20, 3.4),
      ]),
      baseScore: 100,
    );
    store.upsertExam(exam);
    const names = [
      ('Elif', 'Yılmaz'), ('Mehmet', 'Kaya'), ('Zeynep', 'Demir'), ('Ahmet', 'Şahin'), ('Ayşe', 'Çelik'),
      ('Mustafa', 'Yıldız'), ('Fatma', 'Aydın'), ('Emre', 'Öztürk'), ('Selin', 'Arslan'), ('Burak', 'Doğan'),
      ('Ece', 'Kılıç'), ('Can', 'Aslan'),
    ];
    final students = [
      for (var i = 0; i < names.length; i++)
        Student(id: 'st$i', firstName: names[i].$1, lastName: names[i].$2, number: '${101 + i}', className: '12-A'),
    ];
    store.addStudents(students);
    // Derse göre farklı başarı: Türkçe güçlü, Matematik zayıf.
    const skill = [0.78, 0.66, 0.45, 0.55];
    for (var s = 0; s < students.length; s++) {
      final ability = 0.65 + rnd.nextDouble() * 0.6;
      final answers = <Answer>[];
      for (var i = 0; i < 120; i++) {
        final sec = exam.sections.indexWhere((x) => x.contains(i));
        final p = (skill[sec] * ability).clamp(0.05, 0.97);
        final r = rnd.nextDouble();
        if (r < p) {
          answers.add(Answer(MarkState.filled, {key[i]}));
        } else if (r < p + (1 - p) * 0.6) {
          answers.add(Answer(MarkState.filled, {(key[i] + 1 + rnd.nextInt(4)) % 5}));
        } else {
          answers.add(const Answer.blank());
        }
      }
      store.sheets.add(Sheet(examId: exam.id, studentId: students[s].id, answers: answers));
    }
    store.upsertExam(exam);

    Widget app(Widget home, bool dark) => StoreScope(
        store: store,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: dark ? NTheme.dark() : NTheme.light(), home: home));
    await shot(tester, app(const DenemeScreen(examId: 'deneme1'), false), const Size(1280, 1700), 'deneme_genis');
    await shot(tester, app(const DenemeScreen(examId: 'deneme1'), false), const Size(390, 2200), 'deneme_telefon');
    await shot(tester, app(const DenemeScreen(examId: 'deneme1'), true), const Size(1280, 1700), 'deneme_gece');
    await shot(tester, app(const SectionsScreen(examId: 'deneme1'), false), const Size(820, 1300), 'deneme_bolumler');

    final rep = DenemeReport.build(exam, store.resultsOf(exam));
    final bytes = await tester.runAsync(() => buildDenemePdf(report: rep, students: store.studentById));
    File('build/screenshots/deneme.pdf').writeAsBytesSync(bytes!);
    // Word sürümleri (resmî başlıklı okul bilgisiyle).
    const school = SchoolInfo(
        province: 'Ankara', district: 'Çankaya', name: 'Atatürk Anadolu Lisesi', principal: 'Ayşe Demir', teacher: 'Mehmet Kaya', officialHeader: true);
    File('build/screenshots/deneme.docx').writeAsBytesSync(buildDenemeDocx(report: rep, students: store.studentById, school: school));
    File('build/screenshots/sinav_raporu.docx').writeAsBytesSync(
        buildResultsDocx(exam: exam, results: store.resultsOf(exam), students: store.studentById, school: school));

    // Analiz sekmesi: Bloom düzeyleri ve madde-toplam korelasyonu.
    const lv = ['remember', 'understand', 'apply', 'analyze', 'evaluate'];
    store.upsertExam(store.examById('deneme1')!.copyWith(questions: [
      for (final q in store.examById('deneme1')!.questions) q.copyWith(cognitive: lv[(q.no * 7) % 5]),
    ]));
    await shot(tester, app(const ExamScreen(examId: 'deneme1'), false), const Size(1280, 4200), 'analiz_bloom',
        then: () async {
      await tester.tap(find.text('Analiz'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Düşünme düzeyleri (Bloom)'), 400, scrollable: find.byType(Scrollable).last);
    });
  });
}
