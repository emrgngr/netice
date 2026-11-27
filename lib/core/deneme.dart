// Çok dersli deneme sınavı: ders ders doğru/yanlış/net, toplam net,
// ağırlıklı (katsayılı) puan, sınıf içi sıralama ve ders başarı sıralaması.
// Saf fonksiyonlar; kâğıtlar yeniden okutulmadan hesaplanır.
import 'dart:math' as math;

import 'models.dart';
import 'scoring.dart';

/// Bir öğrencinin bir dersteki sonucu.
class SectionScore {
  final ExamSection section;
  final int correct;
  final int wrong;
  final int blank;

  /// Puanlanan (iptal edilmemiş) soru sayısı.
  final int counted;
  final double net;

  const SectionScore(this.section, this.correct, this.wrong, this.blank, this.counted, this.net);

  /// Net başarı yüzdesi (0–100).
  double get percent => counted == 0 ? 0 : math.max(0, net) / counted * 100;
}

/// Bir öğrencinin deneme satırı.
class DenemeRow {
  final Result result;
  final List<SectionScore> sections;
  final double totalNet;

  /// Ağırlıklı puan (taban + Σ net × katsayı); hesaplanmıyorsa null.
  final double? weighted;

  /// Sınıf içi sıra (eşitler aynı sırayı alır).
  final int rank;

  const DenemeRow(this.result, this.sections, this.totalNet, this.weighted, this.rank);

  /// Sıralamada kullanılan değer.
  double get key => weighted ?? totalNet;

  /// En güçlü ve en zayıf ders (net yüzdesine göre).
  SectionScore get strongest => sections.reduce((a, b) => b.percent > a.percent ? b : a);
  SectionScore get weakest => sections.reduce((a, b) => b.percent < a.percent ? b : a);
}

/// Bir dersin sınıf özeti.
class SectionSummary {
  final ExamSection section;
  final double meanCorrect;
  final double meanWrong;
  final double meanNet;
  final double maxNet;

  /// Ortalama net yüzdesi (0–100).
  final double percent;
  final int counted;

  const SectionSummary(this.section, this.meanCorrect, this.meanWrong, this.meanNet, this.maxNet, this.percent, this.counted);
}

class DenemeReport {
  final Exam exam;

  /// Sıralı satırlar (1. öğrenci başta).
  final List<DenemeRow> rows;

  /// Sınavdaki sırasıyla ders özetleri.
  final List<SectionSummary> summaries;

  final double meanTotalNet;
  final double? meanWeighted;

  const DenemeReport._(this.exam, this.rows, this.summaries, this.meanTotalNet, this.meanWeighted);

  /// Dersler, başarıya göre en yüksekten en düşüğe.
  List<SectionSummary> get ranked => [...summaries]..sort((a, b) => b.percent.compareTo(a.percent));

  static SectionScore sectionScore(Exam exam, Result r, ExamSection s) {
    var c = 0, w = 0, b = 0, n = 0;
    for (var i = s.start; i < s.end && i < r.outcomes.length; i++) {
      switch (r.outcomes[i]) {
        case Outcome.correct:
          c++;
          n++;
        case Outcome.wrong:
          w++;
          n++;
        case Outcome.blank:
          b++;
          n++;
        case Outcome.cancelled:
          break;
      }
    }
    final k = exam.rule.wrongsPerCorrect;
    final net = k > 0 ? c - w / k : c.toDouble();
    return SectionScore(s, c, w, b, n, _r2(net));
  }

  static DenemeReport build(Exam exam, List<Result> results) {
    final raw = <(Result, List<SectionScore>, double, double?)>[];
    for (final r in results) {
      final ss = [for (final s in exam.sections) sectionScore(exam, r, s)];
      final total = _r2(ss.fold(0.0, (a, s) => a + s.net));
      final weighted = exam.hasWeightedScore
          ? _r2(exam.baseScore! + ss.fold(0.0, (a, s) => a + math.max(0, s.net) * s.section.weight))
          : null;
      raw.add((r, ss, total, weighted));
    }
    raw.sort((a, b) {
      final ka = a.$4 ?? a.$3, kb = b.$4 ?? b.$3;
      final c = kb.compareTo(ka);
      return c != 0 ? c : b.$1.score.compareTo(a.$1.score);
    });
    final rows = <DenemeRow>[];
    for (var i = 0; i < raw.length; i++) {
      final key = raw[i].$4 ?? raw[i].$3;
      final rank = i > 0 && (rows[i - 1].key - key).abs() < 1e-9 ? rows[i - 1].rank : i + 1;
      rows.add(DenemeRow(raw[i].$1, raw[i].$2, raw[i].$3, raw[i].$4, rank));
    }
    final n = rows.length;
    final summaries = <SectionSummary>[];
    for (var k = 0; k < exam.sections.length; k++) {
      final s = exam.sections[k];
      final list = [for (final r in rows) r.sections[k]];
      final counted = list.isEmpty ? s.count : list.first.counted;
      final mc = n == 0 ? 0.0 : list.fold(0.0, (a, x) => a + x.correct) / n;
      final mw = n == 0 ? 0.0 : list.fold(0.0, (a, x) => a + x.wrong) / n;
      final mn = n == 0 ? 0.0 : list.fold(0.0, (a, x) => a + x.net) / n;
      final mx = list.isEmpty ? 0.0 : list.map((x) => x.net).reduce(math.max);
      summaries.add(SectionSummary(s, _r2(mc), _r2(mw), _r2(mn), mx, counted == 0 ? 0 : _r2(math.max(0, mn) / counted * 100), counted));
    }
    final meanTotal = n == 0 ? 0.0 : _r2(rows.fold(0.0, (a, r) => a + r.totalNet) / n);
    final meanW = exam.hasWeightedScore && n > 0 ? _r2(rows.fold(0.0, (a, r) => a + r.weighted!) / n) : null;
    return DenemeReport._(exam, rows, summaries, meanTotal, meanW);
  }

  /// [studentId] öğrencisinin satırı.
  DenemeRow? rowOf(String? studentId) {
    if (studentId == null) return null;
    for (final r in rows) {
      if (r.result.sheet.studentId == studentId) return r;
    }
    return null;
  }

  static double _r2(double v) => (v * 100).round() / 100;
}

/// Hazır deneme düzenleri (soru sayıları resmî kitapçıklardaki gibidir;
/// katsayıları öğretmen girer).
class DenemePreset {
  final String label;
  final List<(String, int)> parts;
  const DenemePreset(this.label, this.parts);

  int get total => parts.fold(0, (a, p) => a + p.$2);
}

List<DenemePreset> denemePresets() => [
      DenemePreset('TYT', [('Türkçe', 40), ('Sosyal Bilimler', 20), ('Temel Matematik', 40), ('Fen Bilimleri', 20)]),
      DenemePreset('LGS', [
        ('Türkçe', 20),
        ('T.C. İnkılap Tarihi ve Atatürkçülük', 10),
        ('Din Kültürü ve Ahlak Bilgisi', 10),
        ('Yabancı Dil', 10),
        ('Matematik', 20),
        ('Fen Bilimleri', 20),
      ]),
    ];
