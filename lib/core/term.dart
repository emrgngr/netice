import 'models.dart';
import 'report.dart';
import 'store.dart';
import '../l10n/l10n.dart';

/// Eğitim-öğretim yılının bir dönemi.
class Term {
  final String label;
  final DateTime start, end;
  const Term(this.label, this.start, this.end);

  bool contains(DateTime d) => !d.isBefore(start) && d.isBefore(end);

  /// [now] tarihine göre içinde bulunulan yılın 1. dönem, 2. dönem ve tüm yıl
  /// aralıkları. Eylül–Ocak 1. dönem, Şubat–Ağustos 2. dönem sayılır.
  static List<Term> around(DateTime now) {
    final y = now.month >= 9 ? now.year : now.year - 1;
    return [
      Term(tr('1. dönem ({0}-{1})', [y, y + 1]), DateTime(y, 9), DateTime(y + 1, 2)),
      Term(tr('2. dönem ({0}-{1})', [y, y + 1]), DateTime(y + 1, 2), DateTime(y + 1, 9)),
      Term(tr('Tüm yıl ({0}-{1})', [y, y + 1]), DateTime(y, 9), DateTime(y + 1, 9)),
    ];
  }

  /// Bugünün içinde olduğu dönem.
  static Term current(DateTime now) => around(now).firstWhere((t) => t.contains(now));
}

/// Dönem raporundaki bir sınav ve ağırlığı.
class TermExam {
  final Exam exam;
  final ExamReport report;
  final double weight;
  const TermExam(this.exam, this.report, this.weight);

  /// Sınıf ortalaması, 100 üzerinden.
  double get mean100 => exam.rule.maxScore <= 0 ? 0 : report.stats.mean / exam.rule.maxScore * 100;
}

/// Bir öğrencinin dönem satırı.
class TermRow {
  final Student student;

  /// Her sınavdaki puan, 100 üzerinden; girmediyse null.
  final List<double?> scores;

  /// Ağırlıklı ortalama (100 üzerinden); hiç sınava girmediyse null.
  final double? average;

  /// Kazanım kodu → (öğrencinin doğru oranı, sınıfın doğru oranı), 0..1.
  final Map<String, (double, double)> outcomes;

  const TermRow(this.student, this.scores, this.average, this.outcomes);

  int get taken => scores.where((s) => s != null).length;

  /// e-Okul'a girilecek tam sayı not.
  int? get grade => average?.round();
}

/// Bir sınıfın seçilen sınavlarından dönem sonu not çizelgesi ve
/// kazanım karnesi verisi.
class TermReport {
  final String className;
  final Term term;
  final List<TermExam> exams;
  final List<TermRow> rows;
  const TermReport(this.className, this.term, this.exams, this.rows);

  /// Sınıfın dönem ortalaması (sınava giren öğrencilerin ağırlıklı ortalamaları).
  double get classAverage {
    final a = rows.map((r) => r.average).whereType<double>().toList();
    return a.isEmpty ? 0 : a.reduce((x, y) => x + y) / a.length;
  }

  /// Okul numarasına göre sıralı öğrenciler. Sınava girmeyen bir sınav
  /// öğrencinin ortalamasına katılmaz (ağırlıklar yeniden dağıtılır).
  static TermReport build(AppStore store, String className, Term term, List<Exam> exams,
      {Map<String, double> weights = const {}}) {
    final sorted = [...exams]..sort((a, b) => a.date.compareTo(b.date));
    final te = [
      for (final e in sorted) TermExam(e, ExamReport.build(e, store.resultsOf(e)), weights[e.id] ?? 1),
    ];
    final ids = <String>{};
    final students = <Student>[];
    void add(Student? s) {
      if (s != null && ids.add(s.id)) students.add(s);
    }

    for (final s in store.studentsOf(className)) {
      add(s);
    }
    for (final t in te) {
      for (final r in t.report.results) {
        add(store.studentById[r.sheet.studentId]);
      }
    }
    students.sort((a, b) {
      final c = (int.tryParse(a.number) ?? 1 << 30).compareTo(int.tryParse(b.number) ?? 1 << 30);
      return c != 0 ? c : a.fullName.compareTo(b.fullName);
    });

    final rows = <TermRow>[];
    for (final s in students) {
      final scores = <double?>[];
      var sum = 0.0, w = 0.0;
      final acc = <String, List<(double, double)>>{};
      for (final t in te) {
        final r = t.report.results.where((x) => x.sheet.studentId == s.id).firstOrNull;
        if (r == null) {
          scores.add(null);
          continue;
        }
        final v = t.exam.rule.maxScore <= 0 ? 0.0 : r.score / t.exam.rule.maxScore * 100;
        scores.add(v);
        sum += v * t.weight;
        w += t.weight;
        for (final o in t.report.outcomes) {
          acc.putIfAbsent(o.code, () => []).add((o.rateOf(t.exam, r), o.rate));
        }
      }
      double avg(Iterable<double> xs) => xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;
      rows.add(TermRow(
        s,
        scores,
        w > 0 ? sum / w : null,
        {for (final e in acc.entries) e.key: (avg(e.value.map((x) => x.$1)), avg(e.value.map((x) => x.$2)))},
      ));
    }
    return TermReport(className, term, te, rows);
  }
}

/// Kazanım takip çizelgesi: dönem boyunca her kazanımın sınavlardaki sınıf
/// başarısı ve her öğrencinin dönem içindeki birikimli başarısı.
class OutcomeTrack {
  /// Kazanımlar, ilk sorulduğu sınav sırasıyla.
  final List<String> codes;

  /// [codes][i] kazanımının sınav sınav sınıf başarısı (0..1; sorulmadıysa null).
  final List<List<double?>> byExam;

  /// Öğrenci → kazanım → dönem başarısı (0..1); hiç sorulmadıysa yok.
  final Map<String, Map<String, double>> byStudent;

  const OutcomeTrack(this.codes, this.byExam, this.byStudent);

  /// Kazanıldı sayılan başarı (ve üstü).
  static const mastered = 0.70;

  /// Kısmen kazanıldı alt sınırı.
  static const partial = 0.50;

  /// Kazanımın dönem ortalaması (sorulduğu sınavların ortalaması).
  double? termRate(int i) {
    final xs = byExam[i].whereType<double>().toList();
    return xs.isEmpty ? null : xs.reduce((a, b) => a + b) / xs.length;
  }

  /// İlk ve son soruluşu arasındaki değişim (puan, −100..100); tek sınavdaysa null.
  double? trend(int i) {
    final xs = byExam[i].whereType<double>().toList();
    return xs.length < 2 ? null : (xs.last - xs.first) * 100;
  }

  /// Öğrencinin kazandığı kazanım sayısı / ölçülen kazanım sayısı.
  (int, int) masteredOf(String studentId) {
    final m = byStudent[studentId] ?? const {};
    return (m.values.where((v) => v >= mastered).length, m.length);
  }

  static OutcomeTrack build(TermReport t) {
    final codes = <String>[];
    for (final e in t.exams) {
      for (final o in e.report.outcomes) {
        if (!codes.contains(o.code)) codes.add(o.code);
      }
    }
    final byExam = [
      for (final c in codes)
        [for (final e in t.exams) e.report.outcomes.where((o) => o.code == c).firstOrNull?.rate],
    ];
    final byStudent = <String, Map<String, double>>{
      for (final r in t.rows)
        if (r.outcomes.isNotEmpty) r.student.id: {for (final e in r.outcomes.entries) e.key: e.value.$1},
    };
    return OutcomeTrack(codes, byExam, byStudent);
  }
}
