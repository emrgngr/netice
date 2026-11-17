import 'dart:math' as math;

import 'models.dart';

/// Bir öğrencinin sınav sonucu.
class Result {
  final Sheet sheet;
  final List<Outcome> outcomes;
  final int correct;
  final int wrong;
  final int blank;

  /// Net = doğru − yanlış / götürme oranı.
  final double net;

  /// Ölçeklenmiş puan (0..maxScore).
  final double score;

  const Result({
    required this.sheet,
    required this.outcomes,
    required this.correct,
    required this.wrong,
    required this.blank,
    required this.net,
    required this.score,
  });
}

/// Puanlama motoru. Saf fonksiyon: cevap anahtarı değişince tüm sınıf
/// yeniden okutmaya gerek kalmadan anında yeniden puanlanır.
class Scorer {
  static Outcome outcomeFor(Question q, Answer a) {
    if (q.cancelled) return Outcome.cancelled;
    if (a.state == MarkState.blank || a.marked.isEmpty) return Outcome.blank;
    // Onaylanmamış çift işaret geçersiz sayılır (yanlış).
    if (a.marked.length > 1) return Outcome.wrong;
    return q.correct.contains(a.marked.first) ? Outcome.correct : Outcome.wrong;
  }

  static Result score(Exam exam, Sheet sheet) {
    final outcomes = <Outcome>[];
    var c = 0, w = 0, b = 0;
    var earned = 0.0, wrongPoints = 0.0, possible = 0.0;
    for (var i = 0; i < exam.questions.length; i++) {
      final q = exam.questions[i];
      final a = i < sheet.answers.length ? sheet.answers[i] : const Answer.blank();
      final o = outcomeFor(q, a);
      outcomes.add(o);
      if (o == Outcome.cancelled) continue;
      possible += q.points;
      switch (o) {
        case Outcome.correct:
          c++;
          earned += q.points;
        case Outcome.wrong:
          w++;
          wrongPoints += q.points;
        case Outcome.blank:
          b++;
        case Outcome.cancelled:
          break;
      }
    }
    final k = exam.rule.wrongsPerCorrect;
    final net = k > 0 ? c - w / k : c.toDouble();
    final rawPoints = k > 0 ? earned - wrongPoints / k : earned;
    final score = possible == 0
        ? 0.0
        : (math.max(0, rawPoints) / possible * exam.rule.maxScore);
    return Result(
      sheet: sheet,
      outcomes: outcomes,
      correct: c,
      wrong: w,
      blank: b,
      net: net,
      score: double.parse(score.toStringAsFixed(2)),
    );
  }

  static List<Result> scoreAll(Exam exam, List<Sheet> sheets) =>
      sheets.map((s) => score(exam, s)).toList();
}
