import 'dart:math' as math;

import 'models.dart';
import 'scoring.dart';

/// Sınav düzeyi özet istatistikler.
class ExamStats {
  final int count;
  final double mean;
  final double median;
  final double stdDev;
  final double min;
  final double max;

  /// KR-20 güvenirlik katsayısı (hesaplanamıyorsa null).
  final double? kr20;

  /// 0-19, 20-39, 40-59, 60-79, 80-100 dilimlerindeki öğrenci sayısı.
  final List<int> histogram;

  const ExamStats({
    required this.count,
    required this.mean,
    required this.median,
    required this.stdDev,
    required this.min,
    required this.max,
    required this.kr20,
    required this.histogram,
  });
}

/// Madde (soru) analizi sonucu.
class ItemStats {
  final int no;

  /// Güçlük indeksi: doğru yanıtlayanların oranı.
  final double p;

  /// Ayırt edicilik: üst %27 ile alt %27 grubun p farkı.
  final double d;

  /// Her şıkkı seçen öğrenci sayısı.
  final List<int> choiceCounts;

  /// Her şıkkı seçen üst grup öğrenci sayısı.
  final List<int> upperChoiceCounts;
  final int blankCount;

  /// Üst grubun çoğunluğu yanlış bir şıkkı seçtiyse o şık (anahtar uyarısı).
  final int? suspiciousChoice;

  /// Hiç kimsenin seçmediği yanlış şıklar (işlevsiz çeldirici). Yeterli
  /// öğrenci yoksa boş bırakılır.
  final List<int> nonFunctional;

  const ItemStats({
    required this.no,
    required this.p,
    required this.d,
    required this.choiceCounts,
    required this.upperChoiceCounts,
    required this.blankCount,
    required this.suspiciousChoice,
    this.nonFunctional = const [],
  });

  String get difficultyLabel => p > 0.80
      ? 'Kolay'
      : p >= 0.30
          ? 'Orta'
          : 'Zor';

  String get discriminationLabel => d >= 0.40
      ? 'Çok iyi'
      : d >= 0.30
          ? 'İyi'
          : d >= 0.20
              ? 'Düzeltilmeli'
              : 'Gözden geçirilmeli';
}

class Analysis {
  /// Bu sayının altında madde istatistikleri güvenilir değildir; arayüz uyarır.
  static const reliableGroupSize = 20;

  static ExamStats examStats(Exam exam, List<Result> results) {
    final scores = results.map((r) => r.score).toList()..sort();
    final n = scores.length;
    if (n == 0) {
      return const ExamStats(
          count: 0,
          mean: 0,
          median: 0,
          stdDev: 0,
          min: 0,
          max: 0,
          kr20: null,
          histogram: [0, 0, 0, 0, 0]);
    }
    final mean = scores.reduce((a, b) => a + b) / n;
    final median = n.isOdd
        ? scores[n ~/ 2]
        : (scores[n ~/ 2 - 1] + scores[n ~/ 2]) / 2;
    final variance =
        scores.map((s) => (s - mean) * (s - mean)).reduce((a, b) => a + b) / n;
    final hist = List<int>.filled(5, 0);
    for (final s in scores) {
      final pct = s / exam.rule.maxScore * 100;
      hist[math.min(4, (pct / 20).floor())]++;
    }
    return ExamStats(
      count: n,
      mean: mean,
      median: median,
      stdDev: math.sqrt(variance),
      min: scores.first,
      max: scores.last,
      kr20: kr20(exam, results),
      histogram: hist,
    );
  }

  /// KR-20 = k/(k-1) · (1 − Σpq / σ²), σ² ham doğru sayısının varyansı.
  static double? kr20(Exam exam, List<Result> results) {
    final active = [
      for (var i = 0; i < exam.questions.length; i++)
        if (!exam.questions[i].cancelled) i
    ];
    final k = active.length;
    final n = results.length;
    if (k < 2 || n < 2) return null;
    final totals = results
        .map((r) => active.where((i) => r.outcomes[i] == Outcome.correct).length)
        .toList();
    final m = totals.reduce((a, b) => a + b) / n;
    final variance =
        totals.map((t) => (t - m) * (t - m)).reduce((a, b) => a + b) / n;
    if (variance == 0) return null;
    var sumPq = 0.0;
    for (final i in active) {
      final p =
          results.where((r) => r.outcomes[i] == Outcome.correct).length / n;
      sumPq += p * (1 - p);
    }
    return k / (k - 1) * (1 - sumPq / variance);
  }

  static List<ItemStats> itemStats(Exam exam, List<Result> results) {
    final n = results.length;
    final sorted = [...results]..sort((a, b) => b.score.compareTo(a.score));
    final g = n == 0 ? 0 : math.max(1, (n * 0.27).round());
    final upper = sorted.take(g).toList();
    final lower = sorted.reversed.take(g).toList();

    double pOf(List<Result> rs, int i) => rs.isEmpty
        ? 0
        : rs.where((r) => r.outcomes[i] == Outcome.correct).length / rs.length;

    final items = <ItemStats>[];
    for (var i = 0; i < exam.questions.length; i++) {
      final q = exam.questions[i];
      final counts = List<int>.filled(exam.choiceCount, 0);
      final upperCounts = List<int>.filled(exam.choiceCount, 0);
      var blanks = 0;
      for (final r in results) {
        final a = r.sheet.answers[i];
        if (a.marked.isEmpty) {
          blanks++;
        } else if (a.marked.length == 1) {
          counts[a.marked.first]++;
        }
      }
      for (final r in upper) {
        final a = r.sheet.answers[i];
        if (a.marked.length == 1) upperCounts[a.marked.first]++;
      }
      int? suspicious;
      if (!q.cancelled && upper.isNotEmpty) {
        for (var c = 0; c < exam.choiceCount; c++) {
          if (!q.correct.contains(c) && upperCounts[c] > upper.length / 2) {
            suspicious = c;
          }
        }
      }
      items.add(ItemStats(
        no: q.no,
        p: pOf(results, i),
        d: pOf(upper, i) - pOf(lower, i),
        choiceCounts: counts,
        upperChoiceCounts: upperCounts,
        blankCount: blanks,
        suspiciousChoice: suspicious,
        nonFunctional: q.cancelled || n < 10
            ? const []
            : [for (var c = 0; c < exam.choiceCount; c++) if (!q.correct.contains(c) && counts[c] == 0) c],
      ));
    }
    return items;
  }
}
