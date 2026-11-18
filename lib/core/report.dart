import 'dart:math' as math;

import 'analysis.dart';
import 'models.dart';
import 'scoring.dart';

/// Başarı düzeyi (100'lük sisteme göre, puan tam puana oranlanır).
class Level {
  final String name;
  final int grade; // 5..1
  final double minPct;
  const Level(this.name, this.grade, this.minPct);

  static const all = [
    Level('Pekiyi', 5, 85),
    Level('İyi', 4, 70),
    Level('Orta', 3, 60),
    Level('Geçer', 2, 50),
    Level('Geçmez', 1, 0),
  ];

  static Level of(double pct) => all.firstWhere((l) => pct >= l.minPct);
}

/// Sınıf içindeki konumuyla birlikte bir öğrencinin sonucu.
class StudentStanding {
  final Result result;

  /// Eşit puanlar aynı sırayı alır (1, 2, 2, 4 ...).
  final int rank;

  /// Yüzdelik sıra: sınıfın yüzde kaçından daha iyi (0..100).
  final double percentile;

  /// Standart puan (z) ve T puanı (ortalama 50, sapma 10).
  final double z;
  final double t;

  /// Puanın tam puana oranı (0..100).
  final double pct;
  final Level level;

  const StudentStanding({
    required this.result,
    required this.rank,
    required this.percentile,
    required this.z,
    required this.t,
    required this.pct,
    required this.level,
  });
}

/// Kazanım (konu) bazlı başarı.
class OutcomeStats {
  final String code;
  final List<int> questionNos;

  /// Sınıfın bu kazanımdaki doğru oranı (0..1).
  final double rate;
  const OutcomeStats(this.code, this.questionNos, this.rate);

  /// Bir öğrencinin bu kazanımdaki doğru oranı.
  double rateOf(Exam exam, Result r) {
    final idx = questionNos.map((n) => n - 1).where((i) => !exam.questions[i].cancelled).toList();
    if (idx.isEmpty) return 0;
    return idx.where((i) => r.outcomes[i] == Outcome.correct).length / idx.length;
  }
}

/// Raporlarda ve analiz ekranında kullanılan genişletilmiş istatistikler.
class ExamReport {
  final Exam exam;
  final List<Result> results;
  final ExamStats stats;
  final List<ItemStats> items;

  final double q1, q3;
  final double range;
  final double meanCorrect, meanWrong, meanBlank, meanNet;

  /// Geçme puanı ve üzerini alanların oranı (0..1).
  final double passRate;

  /// Değişim katsayısı (std / ortalama, %).
  final double? cv;

  /// Çarpıklık (pozitif: puanlar düşük tarafta toplanmış).
  final double skewness;

  /// Ölçmenin standart hatası (puan cinsinden).
  final double? sem;

  /// Ortalama güçlük ve ayırt edicilik.
  final double meanP, meanD;

  /// Üst %27 ve alt %27 grubun puan ortalaması.
  final double upperMean, lowerMean;

  /// 10'luk dilimler (0-9, 10-19 ... 90-100), tam puana oranla.
  final List<int> histogram10;

  /// Düzey adına göre öğrenci sayısı (Level.all sırasında).
  final List<int> levelCounts;

  /// Kolay / Orta / Zor soru sayısı.
  final Map<String, int> difficultyCounts;

  /// Ayırt edicilik etiketine göre soru sayısı.
  final Map<String, int> discriminationCounts;

  final List<OutcomeStats> outcomes;
  final List<StudentStanding> standings;

  /// Otomatik, öğretmen dostu yorumlar.
  late final List<String> comments = _buildComments();

  ExamReport._({
    required this.exam,
    required this.results,
    required this.stats,
    required this.items,
    required this.q1,
    required this.q3,
    required this.range,
    required this.meanCorrect,
    required this.meanWrong,
    required this.meanBlank,
    required this.meanNet,
    required this.passRate,
    required this.cv,
    required this.skewness,
    required this.sem,
    required this.meanP,
    required this.meanD,
    required this.upperMean,
    required this.lowerMean,
    required this.histogram10,
    required this.levelCounts,
    required this.difficultyCounts,
    required this.discriminationCounts,
    required this.outcomes,
    required this.standings,
  });

  int get activeQuestionCount => exam.questions.where((q) => !q.cancelled).length;

  StudentStanding? standingOf(Result r) => standings.where((s) => identical(s.result, r)).firstOrNull;

  static double _quantile(List<double> sorted, double q) {
    if (sorted.isEmpty) return 0;
    final pos = (sorted.length - 1) * q;
    final lo = pos.floor(), hi = pos.ceil();
    return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
  }

  factory ExamReport.build(Exam exam, List<Result> results) {
    final stats = Analysis.examStats(exam, results);
    final items = Analysis.itemStats(exam, results);
    final n = results.length;
    final max = exam.rule.maxScore;
    final scores = results.map((r) => r.score).toList()..sort();
    double avg(num Function(Result) f) => n == 0 ? 0 : results.map(f).fold<double>(0, (a, b) => a + b) / n;

    // Çarpıklık.
    var skew = 0.0;
    if (n > 2 && stats.stdDev > 0) {
      skew = results.map((r) => math.pow((r.score - stats.mean) / stats.stdDev, 3)).fold<double>(0, (a, b) => a + b) / n;
    }

    // Dağılım ve düzeyler.
    final hist = List<int>.filled(10, 0);
    final levelCounts = List<int>.filled(Level.all.length, 0);
    for (final s in scores) {
      final pct = max == 0 ? 0.0 : s / max * 100;
      hist[math.min(9, (pct / 10).floor())]++;
      levelCounts[Level.all.indexOf(Level.of(pct))]++;
    }

    // Sıralama, yüzdelik, T puanı.
    final sorted = [...results]..sort((a, b) => b.score.compareTo(a.score));
    final standings = <StudentStanding>[];
    for (var i = 0; i < sorted.length; i++) {
      final r = sorted[i];
      final rank = sorted.indexWhere((x) => x.score == r.score) + 1;
      final below = scores.where((s) => s < r.score).length;
      final equal = scores.where((s) => s == r.score).length;
      final z = stats.stdDev == 0 ? 0.0 : (r.score - stats.mean) / stats.stdDev;
      final pct = max == 0 ? 0.0 : r.score / max * 100;
      standings.add(StudentStanding(
        result: r,
        rank: rank,
        percentile: n == 0 ? 0 : (below + 0.5 * equal) / n * 100,
        z: z,
        t: 50 + 10 * z,
        pct: pct,
        level: Level.of(pct),
      ));
    }

    // Üst / alt grup ortalamaları.
    final g = n == 0 ? 0 : math.max(1, (n * 0.27).round());
    double meanOf(Iterable<Result> rs) => rs.isEmpty ? 0 : rs.map((r) => r.score).reduce((a, b) => a + b) / rs.length;

    // Soru kalitesi.
    final active = items.where((it) => !exam.questions[it.no - 1].cancelled).toList();
    final diff = {'Kolay': 0, 'Orta': 0, 'Zor': 0};
    final disc = {'Çok iyi': 0, 'İyi': 0, 'Düzeltilmeli': 0, 'Gözden geçirilmeli': 0};
    for (final it in active) {
      diff[it.difficultyLabel] = diff[it.difficultyLabel]! + 1;
      disc[it.discriminationLabel] = disc[it.discriminationLabel]! + 1;
    }
    final meanP = active.isEmpty ? 0.0 : active.map((i) => i.p).reduce((a, b) => a + b) / active.length;
    final meanD = active.isEmpty ? 0.0 : active.map((i) => i.d).reduce((a, b) => a + b) / active.length;

    // Kazanımlar.
    final byCode = <String, List<int>>{};
    for (final q in exam.questions) {
      final c = q.outcomeCode?.trim();
      if (c != null && c.isNotEmpty) byCode.putIfAbsent(c, () => []).add(q.no);
    }
    final outcomes = [
      for (final e in byCode.entries)
        () {
          final idx = e.value.map((no) => no - 1).where((i) => !exam.questions[i].cancelled).toList();
          final total = idx.length * n;
          final correct = idx.fold<int>(0, (a, i) => a + results.where((r) => r.outcomes[i] == Outcome.correct).length);
          return OutcomeStats(e.key, e.value, total == 0 ? 0 : correct / total);
        }()
    ];

    final kr = stats.kr20;
    final sem = kr == null ? null : stats.stdDev * math.sqrt(math.max(0, 1 - kr));
    final passRate = n == 0 ? 0.0 : scores.where((s) => s >= exam.rule.pass).length / n;

    return ExamReport._(
      exam: exam,
      results: results,
      stats: stats,
      items: items,
      q1: _quantile(scores, 0.25),
      q3: _quantile(scores, 0.75),
      range: n == 0 ? 0 : scores.last - scores.first,
      meanCorrect: avg((r) => r.correct),
      meanWrong: avg((r) => r.wrong),
      meanBlank: avg((r) => r.blank),
      meanNet: avg((r) => r.net),
      passRate: passRate,
      cv: stats.mean == 0 ? null : stats.stdDev / stats.mean * 100,
      skewness: skew,
      sem: sem,
      meanP: meanP,
      meanD: meanD,
      upperMean: meanOf(sorted.take(g)),
      lowerMean: meanOf(sorted.reversed.take(g)),
      histogram10: hist,
      levelCounts: levelCounts,
      difficultyCounts: diff,
      discriminationCounts: disc,
      outcomes: outcomes,
      standings: standings,
    );
  }

  static String _c(String v) => v.replaceAll('.', ',');

  List<String> _buildComments() {
    if (results.isEmpty) return const [];
    String pct(double v) => '%${(v * 100).round()}';
    final c = <String>[];
    c.add(meanP < 0.40
        ? 'Sınav zor: soruların ortalama doğru oranı ${pct(meanP)}.'
        : meanP <= 0.70
            ? 'Sınav orta güçlükte: soruların ortalama doğru oranı ${pct(meanP)}.'
            : 'Sınav kolay: soruların ortalama doğru oranı ${pct(meanP)}.');
    c.add('Öğrencilerin ${pct(passRate)}\'i geçme puanını (${exam.rule.pass.round()}) aldı.');
    final kr = stats.kr20;
    if (kr != null) {
      c.add(kr >= 0.80
          ? 'Güvenirlik yüksek (KR-20 = ${_c(kr.toStringAsFixed(2))}): sınav tutarlı ölçüyor.'
          : kr >= 0.70
              ? 'Güvenirlik kabul edilebilir (KR-20 = ${_c(kr.toStringAsFixed(2))}).'
              : 'Güvenirlik düşük (KR-20 = ${_c(kr.toStringAsFixed(2))}): soru sayısını artırmak veya zayıf soruları gözden geçirmek önerilir.');
    }
    if (skewness > 0.5) {
      c.add('Puanlar düşük tarafta toplanmış: sınıfın çoğu ortalamanın altında kaldı.');
    } else if (skewness < -0.5) {
      c.add('Puanlar yüksek tarafta toplanmış: sınıfın çoğu ortalamanın üstünde.');
    } else {
      c.add('Puanlar ortalama çevresinde dengeli dağılmış.');
    }
    c.add('En başarılı %27 ile en düşük %27 arasındaki fark ${_c((upperMean - lowerMean).toStringAsFixed(1))} puan.');
    final suspicious = items.where((i) => i.suspiciousChoice != null).map((i) => i.no).toList();
    if (suspicious.isNotEmpty) {
      c.add('Cevap anahtarı kontrol edilmeli: ${suspicious.join(', ')}. soru (başarılı öğrencilerin çoğu başka şıkkı seçti).');
    }
    final weak = items
        .where((i) => !exam.questions[i.no - 1].cancelled && i.d < 0.20 && i.suspiciousChoice == null)
        .map((i) => i.no)
        .toList();
    if (weak.isNotEmpty) {
      c.add('Ayırt ediciliği düşük sorular: ${weak.join(', ')}. Bu sorular başarılı ve başarısız öğrenciyi ayırmakta zorlanıyor.');
    }
    if (outcomes.isNotEmpty) {
      final s = [...outcomes]..sort((a, b) => a.rate.compareTo(b.rate));
      c.add('En çok tekrar gereken kazanım: ${s.first.code} (${pct(s.first.rate)} başarı).');
    }
    if (results.length < Analysis.reliableGroupSize) {
      c.add('Not: ${results.length} öğrenci ile madde istatistikleri yol göstericidir, kesin hüküm değildir.');
    }
    return c;
  }
}

/// "1-5 Hareket; 6-10 Kuvvet" biçimindeki kazanım/konu tanımını soru
/// numarası → kazanım eşlemesine çevirir. Satır sonu, ";" veya "," ayırır.
Map<int, String> parseOutcomeRanges(String text, int questionCount) {
  final out = <int, String>{};
  final re = RegExp(r'^\s*(\d+)\s*(?:[-–]\s*(\d+))?\s*[:.)]?\s*(.+?)\s*$');
  for (final part in text.split(RegExp(r'[;\n]'))) {
    final m = re.firstMatch(part);
    if (m == null) continue;
    final a = int.parse(m.group(1)!);
    final b = int.tryParse(m.group(2) ?? '') ?? a;
    final name = m.group(3)!;
    for (var q = math.min(a, b); q <= math.max(a, b); q++) {
      if (q >= 1 && q <= questionCount) out[q] = name;
    }
  }
  return out;
}

/// [parseOutcomeRanges] tersi: ardışık aynı kazanımları aralık olarak yazar.
String formatOutcomeRanges(Exam exam) {
  final parts = <String>[];
  int? start;
  String? code;
  void flush(int end) {
    if (start != null && code != null) parts.add(start == end ? '$start $code' : '$start-$end $code');
  }

  for (final q in exam.questions) {
    final c = q.outcomeCode?.trim();
    if (c != code || c == null || c.isEmpty) {
      flush(q.no - 1);
      start = (c == null || c.isEmpty) ? null : q.no;
      code = (c == null || c.isEmpty) ? null : c;
    }
  }
  flush(exam.questions.length);
  return parts.join('\n');
}
