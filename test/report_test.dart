import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/report.dart';
import 'package:netice/core/scoring.dart';

void main() {
  test('kazanım aralıkları okunur ve geri yazılır', () {
    final m = parseOutcomeRanges('1-3 Hareket; 4 Kuvvet\n5-6: Enerji', 6);
    expect(m, {1: 'Hareket', 2: 'Hareket', 3: 'Hareket', 4: 'Kuvvet', 5: 'Enerji', 6: 'Enerji'});
    final exam = Exam.fromKeyString(id: 'x', name: 'x', className: 'x', key: 'ABCDEA', date: DateTime(2026));
    final e2 = exam.copyWith(questions: [for (final q in exam.questions) q.copyWith(outcomeCode: m[q.no])]);
    expect(formatOutcomeRanges(e2), '1-3 Hareket\n4 Kuvvet\n5-6 Enerji');
  });

  test('genişletilmiş istatistikler: sıra, yüzdelik, düzey, kazanım', () {
    final base = Exam.fromKeyString(id: 'x', name: 'x', className: 'x', key: 'AAAA', date: DateTime(2026));
    final exam = base.copyWith(questions: [
      for (final q in base.questions) q.copyWith(outcomeCode: q.no <= 2 ? 'K1' : 'K2'),
    ]);
    Sheet sheet(List<int?> a) => Sheet(
        examId: 'x', answers: [for (final c in a) c == null ? const Answer.blank() : Answer.choice(c)]);
    final results = Scorer.scoreAll(exam, [
      sheet([0, 0, 0, 0]), // 100
      sheet([0, 0, 0, 1]), // 75
      sheet([0, 0, 1, 1]), // 50
      sheet([0, 0, 1, 1]), // 50
      sheet([1, 1, null, 1]), // 0
    ]);
    final r = ExamReport.build(exam, results);
    expect(r.standings.map((s) => s.rank).toList(), [1, 2, 3, 3, 5]);
    expect(r.standings.first.level.name, 'Pekiyi');
    expect(r.standings.last.level.name, 'Geçmez');
    expect(r.levelCounts, [1, 1, 0, 2, 1]);
    expect(r.passRate, closeTo(0.8, 1e-9));
    expect(r.standings.first.percentile, closeTo(90, 1e-9));
    expect(r.standings.first.t, greaterThan(50));
    expect(r.q1, 50);
    expect(r.q3, 75);
    expect(r.range, 100);
    expect(r.outcomes.firstWhere((o) => o.code == 'K1').rate, closeTo(0.8, 1e-9));
    expect(r.outcomes.firstWhere((o) => o.code == 'K2').rate, closeTo(0.3, 1e-9));
    expect(r.comments, isNotEmpty);
    expect(r.comments.any((c) => c.contains('K2')), isTrue);
  });
}
