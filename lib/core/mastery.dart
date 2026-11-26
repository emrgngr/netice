// Ustalık (mastery) takibi ve aralıklı tekrar.
//
// Bir kazanım, en az iki ayrı sınavda %80 ve üstü başarıyla "öğrenildi"
// sayılır (ustalığa dayalı öğrenme ölçütü). Öğrenilen kazanım uzun süre
// sorulmazsa unutma riskine karşı kısa bir hatırlatma testi önerilir
// (aralıklı tekrar / geri çağırma uygulaması).

import '../l10n/l10n.dart';
import 'report.dart';
import 'store.dart';

enum MasteryStatus {
  mastered,
  developing,
  notYet;

  String get label => switch (this) {
        MasteryStatus.mastered => tr('Öğrenildi'),
        MasteryStatus.developing => tr('Gelişiyor'),
        MasteryStatus.notYet => tr('Henüz değil'),
      };
}

class MasteryOutcome {
  final String code;

  /// Sınav tarihi ve sınıfın doğru oranı (eskiden yeniye).
  final List<(DateTime, double)> attempts;

  /// Öğrenci kimliği → bu kazanımdaki denemeleri (eskiden yeniye, 0..1).
  final Map<String, List<double>> students;

  const MasteryOutcome(this.code, this.attempts, this.students);

  DateTime get lastAssessed => attempts.last.$1;
  double get lastRate => attempts.last.$2;

  MasteryStatus get status => Mastery.statusOf([for (final a in attempts) a.$2]);

  /// Öğrenildi sayılan öğrenci sayısı.
  int get masteredStudents => students.values.where((xs) => Mastery.statusOf(xs) == MasteryStatus.mastered).length;

  /// Hatırlatma zamanı geldi mi: öğrenilmiş ya da gelişiyor, ve son
  /// soruluşundan beri [Mastery.reviewAfter] geçti.
  bool dueAt(DateTime now) => status != MasteryStatus.notYet && now.difference(lastAssessed) >= Mastery.reviewAfter;

  /// Son soruluşu öncekinden belirgin biçimde düşük mü (unutma belirtisi)?
  bool get slipping => attempts.length >= 2 && attempts[attempts.length - 2].$2 - attempts.last.$2 >= 0.15;
}

class Mastery {
  /// Öğrenildi eşiği ve gereken sınav sayısı.
  static const threshold = 0.80;
  static const attemptsNeeded = 2;

  /// Bu kadar süre sorulmayan kazanım için hatırlatma önerilir.
  static const reviewAfter = Duration(days: 21);

  static MasteryStatus statusOf(List<double> rates) {
    if (rates.isEmpty) return MasteryStatus.notYet;
    final good = rates.where((r) => r >= threshold).length;
    if (good >= attemptsNeeded && rates.last >= threshold) return MasteryStatus.mastered;
    if (rates.last >= 0.5) return MasteryStatus.developing;
    return MasteryStatus.notYet;
  }

  /// Bir sınıfın sonuç okunmuş bütün sınavlarından kazanım ustalığı.
  static List<MasteryOutcome> of(AppStore store, String className) {
    final exams = store.exams.where((e) => e.className == className && store.sheetsOf(e.id).isNotEmpty).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final attempts = <String, List<(DateTime, double)>>{};
    final students = <String, Map<String, List<double>>>{};
    final names = <String, String>{};
    for (final e in exams) {
      final rep = ExamReport.build(e, store.resultsOf(e));
      for (final o in rep.outcomes) {
        final key = o.code.trim().toLowerCase();
        names.putIfAbsent(key, () => o.code.trim());
        attempts.putIfAbsent(key, () => []).add((e.date, o.rate));
        final m = students.putIfAbsent(key, () => {});
        for (final r in rep.results) {
          final id = r.sheet.studentId;
          if (id == null) continue;
          m.putIfAbsent(id, () => []).add(o.rateOf(e, r));
        }
      }
    }
    final out = [for (final k in attempts.keys) MasteryOutcome(names[k]!, attempts[k]!, students[k] ?? const {})];
    out.sort((a, b) => a.status.index != b.status.index ? a.status.index.compareTo(b.status.index) : a.code.compareTo(b.code));
    return out;
  }

  /// Öğrencinin öğrendiği ve ölçülen kazanım sayısı.
  static (int, int) studentSummary(List<MasteryOutcome> outcomes, String studentId) {
    var m = 0, n = 0;
    for (final o in outcomes) {
      final xs = o.students[studentId];
      if (xs == null || xs.isEmpty) continue;
      n++;
      if (statusOf(xs) == MasteryStatus.mastered) m++;
    }
    return (m, n);
  }

  /// Hatırlatma testi için kazanım kodları: zamanı gelenler ve düşüş gösterenler.
  static List<MasteryOutcome> dueForReview(List<MasteryOutcome> outcomes, DateTime now) =>
      outcomes.where((o) => o.dueAt(now) || (o.slipping && o.status != MasteryStatus.notYet)).toList();
}
