import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/progress.dart';
import 'package:netice/core/report.dart';
import 'package:netice/core/scoring.dart';
import 'package:netice/l10n/l10n.dart';
import 'package:netice/reports/kid_reports_pdf.dart';
import 'package:netice/reports/pdf_documents.dart';

/// Çocuk sınavlarında karne ve sınıf raporu çocuk görünümüyle üretilir.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => L10n.use('tr'));

  Exam exam({bool kidReports = true, String id = 'k', DateTime? date}) => Exam.fromKeyString(
    id: id,
    name: 'Canlılar $id',
    className: '3-A',
    key: 'ABCABCABCA',
  ).copyWith(kidReports: kidReports, date: date ?? DateTime(2026, 11, 24));

  final students = {
    for (var i = 0; i < 6; i++) 's$i': Student(id: 's$i', firstName: 'Ad$i', lastName: 'Soyad', number: '${i + 1}', className: '3-A'),
  };
  List<Result> results(Exam e) => Scorer.scoreAll(e, [
    for (var i = 0; i < 6; i++)
      Sheet(
        examId: e.id,
        studentId: 's$i',
        answers: [for (var q = 0; q < 10; q++) q < 4 + i ? Answer.choice(q % 3) : const Answer.blank()],
      ),
  ]);

  test('yıldızlar ve kidStyle', () {
    expect([kidStars(95), kidStars(85), kidStars(72), kidStars(50), kidStars(31), kidStars(0)], [5, 5, 4, 3, 2, 1]);
    final e = exam();
    expect(e.kidStyle, isTrue);
    expect(Exam.fromJson(e.toJson()).kidReports, isTrue);
    expect(exam(kidReports: false).kidStyle, isFalse);
    expect(exam(kidReports: false).copyWith(kidForm: true).kidStyle, isTrue);
  });

  for (final lang in ['tr', 'en', 'ar', 'ko']) {
    test('$lang: çocuk karnesi ve sınıf raporu', () async {
      L10n.use(lang);
      final old = exam(id: 'o', date: DateTime(2026, 10, 1));
      final cur = exam();
      final oldRep = ExamReport.build(old, results(old));
      final curRes = results(cur);
      final curRep = ExamReport.build(cur, curRes);
      final history = {
        for (final id in students.keys)
          id: [
            for (final (e, rep) in [(old, oldRep), (cur, curRep)])
              HistoryEntry(e, rep.standings.firstWhere((s) => s.result.sheet.studentId == id), rep.stats.mean, 6, const []),
          ],
      };
      final cards = await buildStudentCardsPdf(exam: cur, results: curRes, students: students, history: history);
      final classic = await buildStudentCardsPdf(exam: exam(kidReports: false), results: curRes, students: students);
      final report = await buildResultsPdf(exam: cur, results: curRes, students: students, classHistory: [('Eski', 40), ('Yeni', 60)]);
      expect(String.fromCharCodes(cards.take(5)), '%PDF-');
      expect(String.fromCharCodes(report.take(5)), '%PDF-');
      // Çocuk karnesi Andika yazı tipini gömer; klasik karne gömmez.
      if (lang != 'ar') {
        expect(String.fromCharCodes(cards).contains('Andika'), isTrue);
        expect(String.fromCharCodes(classic).contains('Andika'), isFalse);
      }
    });
  }
}
