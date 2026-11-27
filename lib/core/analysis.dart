import 'dart:math' as math;

import 'models.dart';
import 'scoring.dart';
import '../l10n/l10n.dart';

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

  /// Madde-toplam korelasyonu (düzeltilmiş nokta çift serili, r_pjx): sorunun
  /// doğru/yanlışı ile öğrencinin diğer sorulardaki doğru sayısı arasındaki
  /// ilişki. Hesaplanamazsa (herkes aynı, çok az öğrenci) null.
  final double? rpb;

  const ItemStats({
    required this.no,
    required this.p,
    required this.d,
    required this.choiceCounts,
    required this.upperChoiceCounts,
    required this.blankCount,
    required this.suspiciousChoice,
    this.nonFunctional = const [],
    this.rpb,
  });

  /// Madde-toplam korelasyonunun yorumu (≥ 0,30 iyi; 0,20–0,29 kabul
  /// edilebilir; < 0,20 zayıf; < 0 ters çalışıyor).
  String get rpbLabel {
    final r = rpb;
    if (r == null) return '–';
    if (r < 0) return tr('Ters çalışıyor');
    if (r < 0.20) return tr('Zayıf');
    if (r < 0.30) return tr('Kabul edilebilir');
    return tr('İyi');
  }

  String get difficultyLabel => p > 0.80
      ? tr('Kolay')
      : p >= 0.30
          ? tr('Orta')
          : tr('Zor');

  String get discriminationLabel => d >= 0.40
      ? tr('Çok iyi')
      : d >= 0.30
          ? tr('İyi')
          : d >= 0.20
              ? tr('Düzeltilmeli')
              : tr('Gözden geçirilmeli');
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

  /// Düzeltilmiş madde-toplam (madde-kalan) korelasyonu: sorunun 1/0 puanı
  /// ile o soru dışındaki doğru sayısı arasındaki Pearson korelasyonu.
  static double? itemRest(List<Result> results, List<int> totals, int i) {
    final n = results.length;
    if (n < 3) return null;
    final x = [for (final r in results) i < r.outcomes.length && r.outcomes[i] == Outcome.correct ? 1.0 : 0.0];
    final y = [for (var k = 0; k < n; k++) totals[k] - x[k]];
    final mx = x.reduce((a, b) => a + b) / n, my = y.reduce((a, b) => a + b) / n;
    var sxy = 0.0, sxx = 0.0, syy = 0.0;
    for (var k = 0; k < n; k++) {
      sxy += (x[k] - mx) * (y[k] - my);
      sxx += (x[k] - mx) * (x[k] - mx);
      syy += (y[k] - my) * (y[k] - my);
    }
    if (sxx == 0 || syy == 0) return null;
    return sxy / math.sqrt(sxx * syy);
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

    // Madde-toplam korelasyonu için öğrencilerin iptal edilmemiş sorulardaki doğru sayısı.
    final active = [for (var i = 0; i < exam.questions.length; i++) if (!exam.questions[i].cancelled) i];
    final totals = [for (final r in results) active.where((i) => i < r.outcomes.length && r.outcomes[i] == Outcome.correct).length];

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
      // Kendi anahtarıyla puanlanan kitapçıkların şıkları A'nınkiyle
      // karşılaştırılamaz; anahtar uyarısı yalnız A sırasındaki kâğıtlardan.
      final upperA = upper.where((r) => !exam.hasOwnKey(r.sheet.booklet)).toList();
      for (final r in upperA) {
        final a = r.sheet.answers[i];
        if (a.marked.length == 1) upperCounts[a.marked.first]++;
      }
      int? suspicious;
      if (!q.cancelled && upperA.isNotEmpty) {
        for (var c = 0; c < exam.choiceCount; c++) {
          if (!q.correct.contains(c) && upperCounts[c] > upperA.length / 2) {
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
        rpb: q.cancelled ? null : itemRest(results, totals, i),
      ));
    }
    return items;
  }
}
