import 'models.dart';
import 'report.dart';
import 'store.dart';
import '../l10n/l10n.dart';

/// Bir öğrencinin bir sınavdaki sonucu ve sınıf içindeki yeri.
class HistoryEntry {
  final Exam exam;
  final StudentStanding standing;
  final double classMean;
  final int classSize;
  final List<(String code, double student, double klass)> outcomes;
  const HistoryEntry(this.exam, this.standing, this.classMean, this.classSize, this.outcomes);

  double get pct => standing.pct;
  bool get passed => standing.result.score >= exam.rule.pass;
}

/// Öğrencinin tüm sınavları, eskiden yeniye.
List<HistoryEntry> historyOf(AppStore store, Student s) {
  final out = <HistoryEntry>[];
  for (final exam in store.exams) {
    final results = store.resultsOf(exam);
    if (!results.any((r) => r.sheet.studentId == s.id)) continue;
    final rep = ExamReport.build(exam, results);
    final st = rep.standings.firstWhere((x) => x.result.sheet.studentId == s.id);
    out.add(HistoryEntry(exam, st, rep.stats.mean, results.length, [
      for (final o in rep.outcomes) (o.code, o.rateOf(exam, st.result), o.rate),
    ]));
  }
  out.sort((a, b) => a.exam.date.compareTo(b.exam.date));
  return out;
}

/// Kazanım bazında birikimli başarı (tüm sınavlar): kod → (öğrenci, sınıf).
Map<String, (double, double)> outcomeSummary(List<HistoryEntry> h) {
  final acc = <String, List<(double, double)>>{};
  for (final e in h) {
    for (final o in e.outcomes) {
      acc.putIfAbsent(o.$1, () => []).add((o.$2, o.$3));
    }
  }
  return {
    for (final e in acc.entries)
      e.key: (
        e.value.map((x) => x.$1).reduce((a, b) => a + b) / e.value.length,
        e.value.map((x) => x.$2).reduce((a, b) => a + b) / e.value.length,
      )
  };
}

/// Öğretmene sessiz hatırlatma: destek gerekebilecek öğrenci.
class EarlyWarning {
  final Student student;
  final String reason;
  final double lastPct;
  const EarlyWarning(this.student, this.reason, this.lastPct);
}

/// Son sınavında geçme puanının altında kalan veya art arda iki sınavda
/// puanı düşen öğrenciler. Bir etiket değil, hatırlatıcıdır.
List<EarlyWarning> earlyWarnings(AppStore store) {
  final out = <EarlyWarning>[];
  // Her sınav için raporu bir kez hesapla.
  final reports = {for (final e in store.exams) e.id: ExamReport.build(e, store.resultsOf(e))};
  for (final s in store.students) {
    final h = <(Exam, StudentStanding)>[];
    for (final e in store.exams) {
      final st = reports[e.id]!.standings.where((x) => x.result.sheet.studentId == s.id).firstOrNull;
      if (st != null) h.add((e, st));
    }
    if (h.isEmpty) continue;
    h.sort((a, b) => a.$1.date.compareTo(b.$1.date));
    final last = h.last;
    final reasons = <String>[];
    if (h.length >= 3 && h[h.length - 1].$2.pct < h[h.length - 2].$2.pct && h[h.length - 2].$2.pct < h[h.length - 3].$2.pct) {
      reasons.add(tr('art arda iki sınavda düşüş'));
    } else if (h.length >= 2 && last.$2.pct <= h[h.length - 2].$2.pct - 15) {
      reasons.add(tr('son sınavda belirgin düşüş ({0} puan)', [(h[h.length - 2].$2.pct - last.$2.pct).round()]));
    }
    if (last.$2.result.score < last.$1.rule.pass) {
      reasons.add(tr('son sınavda geçme puanının altında'));
    }
    if (reasons.isNotEmpty) out.add(EarlyWarning(s, reasons.join(', '), last.$2.pct));
  }
  out.sort((a, b) => a.lastPct.compareTo(b.lastPct));
  return out;
}

/// Birden çok şubenin aynı (veya benzer) sınavdaki karşılaştırması.
class BranchRow {
  final Exam exam;
  final ExamReport report;
  const BranchRow(this.exam, this.report);
}

List<BranchRow> compareExams(AppStore store, List<Exam> exams) => [
      for (final e in exams) BranchRow(e, ExamReport.build(e, store.resultsOf(e))),
    ];

/// Adı aynı olan sınavları (farklı şubeler) gruplar; en az iki şubesi olanlar.
Map<String, List<Exam>> sameNameGroups(AppStore store) {
  final g = <String, List<Exam>>{};
  for (final e in store.exams) {
    g.putIfAbsent(e.commonId ?? e.name.trim().toLowerCase(), () => []).add(e);
  }
  g.removeWhere((_, v) => v.length < 2);
  return g;
}
