import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/progress.dart';
import 'package:netice/core/report.dart';
import 'package:netice/core/scoring.dart';
import 'package:netice/core/term.dart';
import 'package:netice/reports/kid_pdf.dart';
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

  test('tema, büyük kart, tebrik belgesi ve dönem karnesi', () async {
    final e = exam().copyWith(kidTheme: KidTheme.forest, kidForm: true);
    expect(Exam.fromJson(e.toJson()).kidTheme, KidTheme.forest);
    expect(Exam.fromJson(exam().toJson()).kidTheme, KidTheme.rainbow);
    final res = results(e);
    final cards = await buildFormsPdf(e, students.values.take(3).toList(), bigCards: true);
    expect(String.fromCharCodes(cards.take(5)), '%PDF-');
    expect(activeKidTheme, KidTheme.forest);
    final cert = await buildKidCertificatesPdf(exam: e, results: res, students: students);
    expect(String.fromCharCodes(cert.take(5)), '%PDF-');
    final rep = ExamReport.build(e, res);
    final term = TermReport(
      '3-A',
      Term.around(DateTime(2026, 11, 24)).first,
      [TermExam(e, rep, 1)],
      [
        for (final st in rep.standings) TermRow(students[st.result.sheet.studentId]!, [st.pct], st.pct, const {'Bitkiler': (0.8, 0.6)}),
      ],
    );
    final termPdf = await buildTermCardsPdf(term);
    expect(String.fromCharCodes(termPdf).contains('Andika'), isTrue, reason: 'çocuk dönem karnesi');
  });
}
