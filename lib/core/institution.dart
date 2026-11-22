import 'common_exam.dart';
import 'models.dart';
import 'progress.dart';
import 'store.dart';

/// Kurum yönetici paneli için özetler (tüm şubeler, tüm sınavlar).
class ClassSummary {
  final String className;
  final int students;
  final int exams;

  /// Son sınavın ortalaması (tam puana oranla, 0..100); sınav yoksa null.
  final double? lastPct;

  /// Son sınav ile bir önceki arasındaki fark (puan); iki sınav yoksa null.
  final double? trend;
  final int warnings;
  const ClassSummary(this.className, this.students, this.exams, this.lastPct, this.trend, this.warnings);
}

class CommonSummary {
  final String commonId;
  final String name;
  final List<(String className, double pct, int count)> classes;
  const CommonSummary(this.commonId, this.name, this.classes);

  int get total => classes.fold(0, (a, c) => a + c.$3);
  double get meanPct =>
      total == 0 ? 0 : classes.fold(0.0, (a, c) => a + c.$2 * c.$3) / total;
}

class InstitutionSummary {
  final int classes, students, exams, sheets;

  /// Tüm okunan kâğıtların ortalama başarısı (0..100).
  final double meanPct;
  final List<ClassSummary> byClass;
  final List<CommonSummary> common;
  final List<EarlyWarning> warnings;
  const InstitutionSummary({
    required this.classes,
    required this.students,
    required this.exams,
    required this.sheets,
    required this.meanPct,
    required this.byClass,
    required this.common,
    required this.warnings,
  });
}

double _examPct(AppStore store, Exam e) {
  final rs = store.resultsOf(e);
  if (rs.isEmpty || e.rule.maxScore == 0) return 0;
  return rs.map((r) => r.score).reduce((a, b) => a + b) / rs.length / e.rule.maxScore * 100;
}

InstitutionSummary summarizeInstitution(AppStore store) {
  final warnings = earlyWarnings(store);
  final warnByClass = <String, int>{};
  for (final w in warnings) {
    warnByClass[w.student.className] = (warnByClass[w.student.className] ?? 0) + 1;
  }

  final byClass = <ClassSummary>[];
  for (final c in store.classNames) {
    final exams = store.exams.where((e) => e.className == c && store.sheetsOf(e.id).isNotEmpty).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final last = exams.isEmpty ? null : _examPct(store, exams.last);
    final prev = exams.length < 2 ? null : _examPct(store, exams[exams.length - 2]);
    byClass.add(ClassSummary(c, store.studentsOf(c).length, exams.length, last,
        last != null && prev != null ? last - prev : null, warnByClass[c] ?? 0));
  }

  var sum = 0.0;
  var n = 0;
  for (final e in store.exams) {
    if (e.rule.maxScore == 0) continue;
    for (final r in store.resultsOf(e)) {
      sum += r.score / e.rule.maxScore * 100;
      n++;
    }
  }

  final common = <CommonSummary>[
    for (final g in commonGroups(store).entries)
      CommonSummary(g.key, g.value.first.name, [
        for (final e in g.value)
          if (store.sheetsOf(e.id).isNotEmpty) (e.className, _examPct(store, e), store.resultsOf(e).length),
      ]),
  ]..sort((a, b) => b.classes.length.compareTo(a.classes.length));

  return InstitutionSummary(
    classes: store.classNames.length,
    students: store.students.length,
    exams: store.exams.length,
    sheets: store.sheets.length,
    meanPct: n == 0 ? 0 : sum / n,
    byClass: byClass,
    common: common,
    warnings: warnings,
  );
}
