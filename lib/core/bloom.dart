// Düşünme düzeylerine (yenilenmiş Bloom sınıflaması) göre sınav başarısı:
// her düzeydeki soruların sınıf doğru oranı; alt düzey (Hatırlama, Anlama),
// uygulama ve üst düzey (Analiz, Değerlendirme, Yaratma) özeti.
import 'models.dart';
import 'scoring.dart';
import '../l10n/l10n.dart';

const bloomLevels = ['remember', 'understand', 'apply', 'analyze', 'evaluate', 'create'];

String bloomLabel(String level) => switch (level) {
      'remember' => tr('Hatırlama'),
      'understand' => tr('Anlama'),
      'apply' => tr('Uygulama'),
      'analyze' => tr('Analiz'),
      'evaluate' => tr('Değerlendirme'),
      'create' => tr('Yaratma'),
      _ => tr('Belirtilmemiş'),
    };

class BloomRow {
  final String level;
  final List<int> questionNos;

  /// Sınıfın bu düzeydeki doğru oranı (0–1).
  final double rate;
  const BloomRow(this.level, this.questionNos, this.rate);

  String get label => bloomLabel(level);
}

class BloomReport {
  final List<BloomRow> rows;

  /// Alt düzey (Hatırlama + Anlama) ve üst düzey (Analiz + Değerlendirme +
  /// Yaratma) doğru oranları; o düzeyde soru yoksa null.
  final double? lower;
  final double? higher;

  /// Düzeyi bilinen soru sayısı / toplam (iptal edilmemiş) soru.
  final int tagged;
  final int total;

  const BloomReport(this.rows, this.lower, this.higher, this.tagged, this.total);

  bool get isEmpty => rows.isEmpty;

  /// [lookup]: sorunun düzeyi sınavda yazılı değilse (eski sınavlar) bankadan bulmak için.
  static BloomReport build(Exam exam, List<Result> results, {String? Function(Question q)? lookup}) {
    final by = <String, List<int>>{};
    var total = 0;
    for (var i = 0; i < exam.questions.length; i++) {
      final q = exam.questions[i];
      if (q.cancelled) continue;
      total++;
      final l = q.cognitive ?? lookup?.call(q);
      if (l != null && bloomLevels.contains(l)) by.putIfAbsent(l, () => []).add(i);
    }
    double? rateOf(List<int> idx) {
      if (idx.isEmpty || results.isEmpty) return null;
      var c = 0;
      for (final r in results) {
        for (final i in idx) {
          if (i < r.outcomes.length && r.outcomes[i] == Outcome.correct) c++;
        }
      }
      return c / (idx.length * results.length);
    }

    final rows = [
      for (final l in bloomLevels)
        if (by[l] != null) BloomRow(l, [for (final i in by[l]!) exam.questions[i].no], rateOf(by[l]!) ?? 0),
    ];
    final tagged = by.values.fold(0, (a, b) => a + b.length);
    return BloomReport(
      rows,
      rateOf([...?by['remember'], ...?by['understand']]),
      rateOf([...?by['analyze'], ...?by['evaluate'], ...?by['create']]),
      tagged,
      total,
    );
  }
}
