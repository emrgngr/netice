import 'dart:math' as math;

import 'models.dart';
import 'report.dart';
import 'scoring.dart';
import 'store.dart';
import '../l10n/l10n.dart';

/// Bir sayı listesinin özet dağılımı (yüzde ölçeğinde kullanılır).
class Dist {
  final int n;
  final double mean, median, std, min, max, q1, q3;
  const Dist(this.n, this.mean, this.median, this.std, this.min, this.max, this.q1, this.q3);

  static const empty = Dist(0, 0, 0, 0, 0, 0, 0, 0);

  static Dist of(Iterable<double> values) {
    final v = values.toList()..sort();
    if (v.isEmpty) return empty;
    final n = v.length;
    final mean = v.reduce((a, b) => a + b) / n;
    final variance = v.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) / n;
    double q(double p) {
      final pos = (n - 1) * p;
      final lo = pos.floor(), hi = pos.ceil();
      return v[lo] + (v[hi] - v[lo]) * (pos - lo);
    }

    return Dist(n, mean, q(0.5), math.sqrt(variance), v.first, v.last, q(0.25), q(0.75));
  }

  double get iqr => q3 - q1;
}

/// Bir kâğıdın genel istatistikteki karşılığı: hangi sınav, hangi sınıf,
/// yüzde kaç.
class ScoreEntry {
  final Exam exam;
  final Result result;
  final String className;
  final double pct;
  const ScoreEntry(this.exam, this.result, this.className, this.pct);

  String? get studentId => result.sheet.studentId;
  bool get passed => result.score >= exam.rule.pass;
}

/// Bir sınavın zaman çizelgesindeki noktası.
class ExamPoint {
  final Exam exam;
  final double mean;
  final double passRate;
  final int n;
  const ExamPoint(this.exam, this.mean, this.passRate, this.n);
}

/// Bir sınıfın (şubenin) seçilen dönemdeki tüm sınavlarının özeti.
class ClassSummary {
  final String name;
  final int examCount;
  final int sheets;
  final int registered;
  final int participants;
  final Dist dist;
  final double passRate;
  final List<int> levelCounts;
  final double correctRate, wrongRate, blankRate;

  /// Sınav sırasına göre sınıf ortalamaları (yüzde).
  final List<ExamPoint> timeline;

  /// İlk sınavdan son sınava ortalama değişimi (en az iki sınav gerekir).
  final double? trend;

  /// Sınıfın en yüksek ortalamalı öğrencisi.
  final StudentSummary? best;

  const ClassSummary({
    required this.name,
    required this.examCount,
    required this.sheets,
    required this.registered,
    required this.participants,
    required this.dist,
    required this.passRate,
    required this.levelCounts,
    required this.correctRate,
    required this.wrongRate,
    required this.blankRate,
    required this.timeline,
    required this.trend,
    required this.best,
  });

  /// Kayıtlı öğrencilerin yüzde kaçı en az bir sınava girdi.
  double? get participation => registered == 0 ? null : math.min(1, participants / registered);
}

/// Bir öğrencinin seçilen dönemdeki sınavlarının özeti.
class StudentSummary {
  final Student student;
  final List<ScoreEntry> entries; // eskiden yeniye
  final Dist dist;
  final int passed;
  const StudentSummary(this.student, this.entries, this.dist, this.passed);

  double get average => dist.mean;
  double get first => entries.first.pct;
  double get last => entries.last.pct;
  double get change => last - first;
  int get count => entries.length;
}

/// Tüm sınavlardan birleştirilmiş kazanım başarısı.
class OutcomeOverview {
  final String code;
  final double rate;
  final int exams;
  final int students;
  const OutcomeOverview(this.code, this.rate, this.exams, this.students);
}

/// Dönem seçimi.
enum OverviewPeriod {
  all(null),
  last30(30),
  last90(90);

  final int? days;
  const OverviewPeriod(this.days);

  String get label => switch (this) {
        OverviewPeriod.all => tr('Tüm zamanlar'),
        OverviewPeriod.last30 => tr('Son 30 gün'),
        OverviewPeriod.last90 => tr('Son 90 gün'),
      };
}

/// Tüm sınıflar ve sınava giren tüm öğrenciler için genel istatistik.
class Overview {
  final List<Exam> exams;
  final List<ScoreEntry> entries;
  final Dist dist;
  final double passRate;
  final List<int> histogram10;
  final List<int> levelCounts;
  final double correctRate, wrongRate, blankRate;
  final int registered;
  final int participants;
  final int unmatched;
  final List<ClassSummary> classes;
  final List<ExamPoint> timeline;
  final List<(DateTime month, double mean, int n)> monthly;
  final List<StudentSummary> students;
  final List<OutcomeOverview> outcomes;

  const Overview({
    required this.exams,
    required this.entries,
    required this.dist,
    required this.passRate,
    required this.histogram10,
    required this.levelCounts,
    required this.correctRate,
    required this.wrongRate,
    required this.blankRate,
    required this.registered,
    required this.participants,
    required this.unmatched,
    required this.classes,
    required this.timeline,
    required this.monthly,
    required this.students,
    required this.outcomes,
  });

  bool get isEmpty => entries.isEmpty;
  int get sheets => entries.length;
  double? get participation => registered == 0 ? null : math.min(1, participants / registered);

  /// Ortalaması en yüksek öğrenciler (eşitlikte daha çok sınava giren önde).
  List<StudentSummary> get top => [...students]..sort((a, b) {
      final c = b.average.compareTo(a.average);
      return c != 0 ? c : b.count.compareTo(a.count);
    });

  /// En az iki sınava girip en çok yükselenler.
  List<StudentSummary> get improved =>
      students.where((s) => s.count >= 2 && s.change > 0).toList()..sort((a, b) => b.change.compareTo(a.change));

  /// En az iki sınava girip en çok düşenler.
  List<StudentSummary> get declined =>
      students.where((s) => s.count >= 2 && s.change < 0).toList()..sort((a, b) => a.change.compareTo(b.change));

  /// Ortalaması en düşük öğrenciler.
  List<StudentSummary> get support => [...students]..sort((a, b) => a.average.compareTo(b.average));

  /// En az iki sınava girip hepsini geçenler / hiçbirini geçemeyenler.
  int get alwaysPassed => students.where((s) => s.count >= 2 && s.passed == s.count).length;
  int get neverPassed => students.where((s) => s.count >= 2 && s.passed == 0).length;

  /// Sınavlara düzenli katılan (en az iki sınav) öğrenciler arasında
  /// puanı en istikrarlı olanlar (en küçük sapma).
  List<StudentSummary> get steady =>
      students.where((s) => s.count >= 3).toList()..sort((a, b) => a.dist.std.compareTo(b.dist.std));

  ExamPoint? get easiest => timeline.isEmpty ? null : timeline.reduce((a, b) => a.mean >= b.mean ? a : b);
  ExamPoint? get hardest => timeline.isEmpty ? null : timeline.reduce((a, b) => a.mean <= b.mean ? a : b);

  /// En yüksek ve en düşük sınıf ortalaması arasındaki fark.
  double get classGap => classes.length < 2 ? 0 : classes.first.dist.mean - classes.last.dist.mean;

  /// İlk ve son sınav arasındaki genel değişim.
  double? get trend => timeline.length < 2 ? null : timeline.last.mean - timeline.first.mean;

  /// Kısa otomatik değerlendirme cümleleri.
  List<String> get comments {
    if (isEmpty) return const [];
    String p(double v) => L10n.percent(v.round());
    final out = <String>[
      tr('{0} sınavda {1} kâğıt okundu; sınava giren öğrencilerin genel başarısı {2}.', [exams.length, sheets, p(dist.mean)]),
    ];
    if (passRate >= 0.85) {
      out.add(tr('Kâğıtların {0} kadarı geçme puanını aştı; genel tablo çok iyi.', [p(passRate * 100)]));
    } else if (passRate >= 0.6) {
      out.add(tr('Kâğıtların {0} kadarı geçme puanını aştı.', [p(passRate * 100)]));
    } else {
      out.add(tr('Kâğıtların yalnızca {0} kadarı geçme puanını aştı; genel bir tekrar faydalı olabilir.', [p(passRate * 100)]));
    }
    if (classes.length >= 2) {
      if (classGap > 5) {
        out.add(tr('En başarılı sınıf {0} ({1}), en çok desteğe ihtiyaç duyan sınıf {2} ({3}).',
            [classes.first.name, p(classes.first.dist.mean), classes.last.name, p(classes.last.dist.mean)]));
      }
      if (classGap >= 15) {
        out.add(tr('Sınıflar arasındaki fark {0} puan; düzeyler belirgin biçimde ayrışıyor.', [classGap.round()]));
      } else if (classGap <= 5) {
        out.add(tr('Sınıfların ortalamaları birbirine çok yakın (en fazla {0} puan fark).', [classGap.round()]));
      }
    }
    final tr0 = trend;
    if (tr0 != null && tr0.abs() >= 3) {
      out.add(tr0 > 0
          ? tr('İlk sınavdan son sınava genel ortalama {0} puan yükseldi.', [tr0.round()])
          : tr('İlk sınavdan son sınava genel ortalama {0} puan düştü.', [(-tr0).round()]));
    }
    final part = participation;
    if (part != null && part < 0.9) {
      out.add(tr('Kayıtlı öğrencilerin {0} kadarı en az bir sınava girdi; {1} öğrenci hiç kâğıt vermedi.',
          [p(part * 100), math.max(0, registered - participants)]));
    }
    if (dist.std >= 20) {
      out.add(tr('Puanlar çok dağınık (std. {0}); öğrenciler arasında büyük düzey farkı var.', [dist.std.round()]));
    }
    final weak = outcomes.where((o) => o.rate < 0.5).toList();
    if (weak.isNotEmpty) {
      out.add(tr('Genel olarak en zayıf konu: {0} ({1}).', [weak.first.code, p(weak.first.rate * 100)]));
    }
    return out;
  }

  /// Seçilen sınıf ve döneme göre genel istatistiği hesaplar. [classes]
  /// boşsa tüm sınıflar alınır.
  static Overview build(AppStore store,
      {Set<String> classes = const {}, OverviewPeriod period = OverviewPeriod.all, DateTime? now}) {
    final since = period.days == null ? null : (now ?? DateTime.now()).subtract(Duration(days: period.days!));
    final byId = store.studentById;
    String classOf(Exam e, Result r) => byId[r.sheet.studentId]?.className.trim().isNotEmpty == true
        ? byId[r.sheet.studentId]!.className
        : e.className;

    final exams = <Exam>[];
    final entries = <ScoreEntry>[];
    final reports = <String, ExamReport>{};
    for (final e in store.exams) {
      if (since != null && e.date.isBefore(since)) continue;
      final rs = store.resultsOf(e);
      final mine = [
        for (final r in rs)
          if (classes.isEmpty || classes.contains(classOf(e, r))) r
      ];
      if (mine.isEmpty) continue;
      exams.add(e);
      reports[e.id] = ExamReport.build(e, mine);
      final max = e.rule.maxScore;
      for (final r in mine) {
        entries.add(ScoreEntry(e, r, classOf(e, r), max == 0 ? 0 : r.score / max * 100));
      }
    }
    exams.sort((a, b) => a.date.compareTo(b.date));

    final pcts = [for (final x in entries) x.pct];
    final hist = List<int>.filled(10, 0);
    final levels = List<int>.filled(Level.all.length, 0);
    for (final v in pcts) {
      hist[math.min(9, (v / 10).floor().clamp(0, 9))]++;
      levels[Level.all.indexOf(Level.of(v))]++;
    }
    (double, double, double) dyb(Iterable<ScoreEntry> xs) {
      var c = 0, w = 0, b = 0;
      for (final x in xs) {
        c += x.result.correct;
        w += x.result.wrong;
        b += x.result.blank;
      }
      final t = c + w + b;
      return t == 0 ? (0, 0, 0) : (c / t, w / t, b / t);
    }

    ExamPoint point(Exam e, Iterable<ScoreEntry> xs) {
      final l = xs.toList();
      return ExamPoint(e, l.isEmpty ? 0 : l.map((x) => x.pct).reduce((a, b) => a + b) / l.length,
          l.isEmpty ? 0 : l.where((x) => x.passed).length / l.length, l.length);
    }

    final timeline = [for (final e in exams) point(e, entries.where((x) => x.exam.id == e.id))];

    final monthMap = <DateTime, List<double>>{};
    for (final x in entries) {
      monthMap.putIfAbsent(DateTime(x.exam.date.year, x.exam.date.month), () => []).add(x.pct);
    }
    final monthly = [
      for (final m in monthMap.keys.toList()..sort())
        (m, monthMap[m]!.reduce((a, b) => a + b) / monthMap[m]!.length, monthMap[m]!.length)
    ];

    // Öğrenciler
    final perStudent = <String, List<ScoreEntry>>{};
    var unmatched = 0;
    for (final x in entries) {
      final id = x.studentId;
      if (id == null || byId[id] == null) {
        unmatched++;
        continue;
      }
      perStudent.putIfAbsent(id, () => []).add(x);
    }
    final students = [
      for (final e in perStudent.entries)
        StudentSummary(
          byId[e.key]!,
          e.value..sort((a, b) => a.exam.date.compareTo(b.exam.date)),
          Dist.of(e.value.map((x) => x.pct)),
          e.value.where((x) => x.passed).length,
        )
    ];

    // Sınıflar
    final classNames = classes.isNotEmpty
        ? classes.toList()
        : {for (final x in entries) x.className}.toList();
    final summaries = <ClassSummary>[];
    for (final c in classNames) {
      final xs = entries.where((x) => x.className == c).toList();
      if (xs.isEmpty) continue;
      final lv = List<int>.filled(Level.all.length, 0);
      for (final x in xs) {
        lv[Level.all.indexOf(Level.of(x.pct))]++;
      }
      final (cr, wr, br) = dyb(xs);
      final ex = {for (final x in xs) x.exam.id: x.exam}.values.toList()..sort((a, b) => a.date.compareTo(b.date));
      final tl = [for (final e in ex) point(e, xs.where((x) => x.exam.id == e.id))];
      final mates = students.where((s) => s.student.className == c).toList()
        ..sort((a, b) => b.average.compareTo(a.average));
      summaries.add(ClassSummary(
        name: c,
        examCount: ex.length,
        sheets: xs.length,
        registered: store.studentsOf(c).length,
        participants: {for (final x in xs) if (x.studentId != null && byId[x.studentId] != null) x.studentId}.length,
        dist: Dist.of(xs.map((x) => x.pct)),
        passRate: xs.where((x) => x.passed).length / xs.length,
        levelCounts: lv,
        correctRate: cr,
        wrongRate: wr,
        blankRate: br,
        timeline: tl,
        trend: tl.length < 2 ? null : tl.last.mean - tl.first.mean,
        best: mates.firstOrNull,
      ));
    }
    summaries.sort((a, b) => b.dist.mean.compareTo(a.dist.mean));

    // Kazanımlar: her sınavın kazanım oranı, öğrenci sayısıyla ağırlıklı.
    final oc = <String, (double sum, int n, int exams)>{};
    for (final e in exams) {
      final rep = reports[e.id]!;
      for (final o in rep.outcomes) {
        final key = o.code.trim();
        if (key.isEmpty) continue;
        final prev = oc[key] ?? (0.0, 0, 0);
        oc[key] = (prev.$1 + o.rate * rep.results.length, prev.$2 + rep.results.length, prev.$3 + 1);
      }
    }
    final outcomes = [
      for (final e in oc.entries)
        if (e.value.$2 > 0) OutcomeOverview(e.key, e.value.$1 / e.value.$2, e.value.$3, e.value.$2)
    ]..sort((a, b) => a.rate.compareTo(b.rate));

    final registered = classes.isEmpty
        ? store.students.length
        : store.students.where((s) => classes.contains(s.className)).length;
    final (cr, wr, br) = dyb(entries);
    return Overview(
      exams: exams,
      entries: entries,
      dist: Dist.of(pcts),
      passRate: entries.isEmpty ? 0 : entries.where((x) => x.passed).length / entries.length,
      histogram10: hist,
      levelCounts: levels,
      correctRate: cr,
      wrongRate: wr,
      blankRate: br,
      registered: registered,
      participants: students.length,
      unmatched: unmatched,
      classes: summaries,
      timeline: timeline,
      monthly: monthly,
      students: students,
      outcomes: outcomes,
    );
  }
}

/// Sınıf sınıf analiz için iki grup arasındaki etki büyüklüğü (Cohen d).
/// 0,2 küçük, 0,5 orta, 0,8 büyük fark sayılır.
double cohenD(Dist a, Dist b) {
  if (a.n < 2 || b.n < 2) return 0;
  final pooled = math.sqrt(((a.n - 1) * a.std * a.std + (b.n - 1) * b.std * b.std) / (a.n + b.n - 2));
  return pooled == 0 ? 0 : (a.mean - b.mean) / pooled;
}

/// Etki büyüklüğünün sözlü karşılığı.
String effectLabel(double d) {
  final x = d.abs();
  return x >= 0.8
      ? tr('büyük fark')
      : x >= 0.5
          ? tr('orta düzey fark')
          : x >= 0.2
              ? tr('küçük fark')
              : tr('fark yok denecek kadar az');
}
