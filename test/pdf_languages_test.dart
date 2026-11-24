import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/progress.dart';
import 'package:netice/core/report.dart';
import 'package:netice/core/scoring.dart';
import 'package:netice/l10n/l10n.dart';
import 'package:netice/reports/pdf_documents.dart';

/// Her dilde optik form ve sonuç raporu üretilebilmeli; Latin dışı harfler
/// yedek yazı tipleriyle yazılır.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => L10n.use('tr'));

  const names = {
    'ru': ('Иван', 'Петров', 'Школа № 57', 'Москва'),
    'ar': ('أحمد', 'علي', 'ثانوية الملك فهد', 'الرياض'),
    'zh': ('王', '小明', '北京市第一中学', '北京'),
    'ja': ('佐藤', '花子', '東京都立日比谷高等学校', '東京都'),
    'de': ('Jürgen', 'Groß', 'Goethe-Gymnasium', 'München'),
    'pt': ('João', 'Conceição', 'Colégio Estadual Dom Pedro II', 'São Paulo'),
    'hi': ('राहुल', 'शर्मा', 'केंद्रीय विद्यालय', 'नई दिल्ली'),
    'id': ('Budi', 'Santoso', 'SMA Negeri 1 Jakarta', 'Jakarta'),
    'ko': ('민준', '김', '서울과학고등학교', '서울특별시'),
  };

  for (final e in names.entries) {
    test('${e.key}: form ve rapor PDF', () async {
      L10n.use(e.key);
      final (first, last, schoolName, city) = e.value;
      final school = SchoolInfo(name: schoolName, province: city, subject: 'Fizik');
      final exam = Exam.fromKeyString(id: 'x', name: 'Test 1', className: '9-A', key: 'ABCDEABCDEABCDEABCDE');
      final st = Student(id: '1', firstName: first, lastName: last, number: '1042', className: '9-A');
      final forms = await buildFormsPdf(exam, [st], school: school);
      final sheets = [
        for (var i = 0; i < 5; i++)
          Sheet(examId: 'x', studentId: i == 0 ? '1' : null, answers: [for (var q = 0; q < 20; q++) Answer.choice((q + i) % 5)])
      ];
      final report = await buildResultsPdf(
          exam: exam, results: Scorer.scoreAll(exam, sheets), students: {'1': st}, school: school);
      expect(String.fromCharCodes(report.take(5)), '%PDF-');
      final results = Scorer.scoreAll(exam, sheets);
      final cards = await buildStudentCardsPdf(
          exam: exam, results: results, students: {'1': st}, school: school,
          notes: {'1': [tr('Son 3 sınavda istikrarlı bir çizgide.'), tr('Güçlü olduğu konu: {0} ({1}).', ['A', L10n.percent(80)])]});
      expect(String.fromCharCodes(cards.take(5)), '%PDF-');
      final b = exam.copyWith(id: 'y', className: '9-B');
      final cmp = await buildComparePdf([
        BranchRow(exam, ExamReport.build(exam, results)),
        BranchRow(b, ExamReport.build(b, Scorer.scoreAll(b, [for (final s in sheets) Sheet(examId: 'y', studentId: s.studentId, answers: s.answers)]))),
      ], school: school, students: {'1': st});
      expect(String.fromCharCodes(cmp.take(5)), '%PDF-');
      final out = Directory('build/test_output')..createSync(recursive: true);
      File('${out.path}/form_${e.key}.pdf').writeAsBytesSync(forms);
      File('${out.path}/rapor_${e.key}.pdf').writeAsBytesSync(report);
    });
  }
}
