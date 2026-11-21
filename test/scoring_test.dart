import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/analysis.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/scoring.dart';

Sheet sheetFrom(String s) => Sheet(
      examId: 'e',
      answers: [
        for (final ch in s.split(''))
          ch == '-' ? const Answer.blank() : Answer.choice(ch.codeUnitAt(0) - 65)
      ],
    );

void main() {
  final exam = Exam.fromKeyString(
      id: 'e', name: 'Quiz', className: '9-A', key: 'ABCDE', choiceCount: 5);

  test('doğru, yanlış, boş sayılır ve puan 100 üzerinden hesaplanır', () {
    final r = Scorer.score(exam, sheetFrom('ABCA-'));
    expect(r.correct, 3);
    expect(r.wrong, 1);
    expect(r.blank, 1);
    expect(r.net, 3);
    expect(r.score, 60);
  });

  test('4 yanlış 1 doğruyu götürür', () {
    final e = exam.copyWith(rule: const ScoringRule(wrongsPerCorrect: 4));
    final r = Scorer.score(e, sheetFrom('AAAAA'));
    expect(r.correct, 1);
    expect(r.wrong, 4);
    expect(r.net, 0);
    expect(r.score, 0);
  });

  test('iptal edilen soru hesaba katılmaz, anahtar değişince yeniden puanlanır', () {
    final qs = [...exam.questions];
    qs[4] = qs[4].copyWith(cancelled: true);
    qs[3] = qs[3].copyWith(correct: {0, 3}); // iki doğru kabul
    final e = exam.copyWith(questions: qs);
    final r = Scorer.score(e, sheetFrom('ABCAA'));
    expect(r.correct, 4);
    expect(r.wrong, 0);
    expect(r.score, 100);
  });

  test('çift işaret yanlış sayılır', () {
    final s = Sheet(examId: 'e', answers: [
      const Answer(MarkState.multiple, {0, 1}),
      ...sheetFrom('BCDE').answers
    ]);
    expect(Scorer.score(exam, s).wrong, 1);
  });

  test('madde analizi: güçlük, ayırt edicilik ve şüpheli anahtar', () {
    // 10 öğrenci; 1. soruda üst grup hep D seçiyor (anahtar A) → uyarı.
    final sheets = <Sheet>[
      for (var i = 0; i < 5; i++) sheetFrom('DBCDE'),
      for (var i = 0; i < 5; i++) sheetFrom('AACAA'),
    ];
    final results = Scorer.scoreAll(exam, sheets);
    final items = Analysis.itemStats(exam, results);
    expect(items[0].p, 0.5);
    expect(items[0].d, lessThan(0));
    expect(items[0].suspiciousChoice, 3);
    expect(items[1].d, 1.0);
    expect(items[2].p, 1.0);
    final st = Analysis.examStats(exam, results);
    expect(st.count, 10);
    expect(st.mean, closeTo(60, 0.001)); // 5×80 + 5×40
    expect(st.histogram.reduce((a, b) => a + b), 10);
    expect(st.kr20, isNotNull);
  });
}
