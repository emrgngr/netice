// Soru bankası analizi: dağılımlar, konu kapsamı, sınav sonuçlarından
// gerçek zorluk ve zayıf konular için hap bilgi önerisi.

import '../core/models.dart';
import '../core/scoring.dart';
import 'bank_models.dart';
import 'bank_store.dart';

/// Bir banka sorusunun sınavlardaki sonucu.
class BankItemStat {
  final String id;
  int answered = 0;
  int correct = 0;
  int exams = 0;
  BankItemStat(this.id);

  /// Doğru cevaplama oranı (güçlük indeksi).
  double get p => answered == 0 ? 0 : correct / answered;

  /// Sonuca göre olması gereken zorluk.
  Difficulty get measured => Difficulty.fromP(p);
}

/// Bir konunun bankadaki durumu.
class TopicCoverage {
  final String subject;
  final String topic;
  final List<int> byDifficulty = [0, 0, 0];
  int notes = 0;
  int tips = 0;
  int used = 0;

  /// Sınavlarda bu konudaki doğru oranı (veri yoksa null).
  double? p;
  TopicCoverage(this.subject, this.topic);

  int get questions => byDifficulty.fold(0, (a, b) => a + b);
}

/// Sınavda zayıf çıkan bir konu ve ona bağlı notlar.
class WeakTopic {
  final String topic;

  /// Konudaki başarı oranı (0–1).
  final double rate;
  final List<BankNote> notes;
  const WeakTopic(this.topic, this.rate, this.notes);
}

class BankAnalysis {
  /// Sınav sonuçlarından banka sorularının istatistikleri.
  static Map<String, BankItemStat> itemStats(Iterable<(Exam, List<Result>)> data) {
    final out = <String, BankItemStat>{};
    for (final (exam, results) in data) {
      for (var i = 0; i < exam.questions.length; i++) {
        final q = exam.questions[i];
        final id = q.bankId;
        if (id == null || q.cancelled) continue;
        final s = out.putIfAbsent(id, () => BankItemStat(id));
        s.exams++;
        for (final r in results) {
          if (i >= r.outcomes.length) continue;
          s.answered++;
          if (r.outcomes[i] == Outcome.correct) s.correct++;
        }
      }
    }
    return out;
  }

  /// Etiketi ölçülen zorluktan farklı olan sorular (en az [minAnswers] cevap).
  static List<(BankQuestion, BankItemStat)> mislabeled(List<BankQuestion> qs, Map<String, BankItemStat> stats,
      {int minAnswers = 10}) {
    final out = <(BankQuestion, BankItemStat)>[];
    for (final q in qs) {
      final s = stats[q.id];
      if (s == null || s.answered < minAnswers) continue;
      if (s.measured != q.difficulty) out.add((q, s));
    }
    out.sort((a, b) => (b.$2.p - b.$1.difficultyTarget).abs().compareTo((a.$2.p - a.$1.difficultyTarget).abs()));
    return out;
  }

  /// En çok yanlış yapılan sorular.
  static List<(BankQuestion, BankItemStat)> hardest(List<BankQuestion> qs, Map<String, BankItemStat> stats,
      {int minAnswers = 5, int limit = 10}) {
    final byId = {for (final q in qs) q.id: q};
    final list = [
      for (final s in stats.values)
        if (s.answered >= minAnswers && byId[s.id] != null) (byId[s.id]!, s),
    ]..sort((a, b) => a.$2.p.compareTo(b.$2.p));
    return list.take(limit).toList();
  }

  /// Ders → konu kapsamı.
  static List<TopicCoverage> coverage(BankStore bank, {Map<String, int> used = const {}, Map<String, BankItemStat> stats = const {}}) {
    final map = <String, TopicCoverage>{};
    String key(String s, String t) => '${s.trim().toLowerCase()}|${t.trim().toLowerCase()}';
    final answered = <String, (int, int)>{};
    for (final q in bank.questions) {
      final c = map.putIfAbsent(key(q.subject, q.topicLabel), () => TopicCoverage(q.subject.trim(), q.topicLabel));
      c.byDifficulty[q.difficulty.index]++;
      if ((used[q.id] ?? 0) > 0) c.used++;
      final s = stats[q.id];
      if (s != null && s.answered > 0) {
        final k = key(q.subject, q.topicLabel);
        final (a, b) = answered[k] ?? (0, 0);
        answered[k] = (a + s.correct, b + s.answered);
      }
    }
    for (final n in bank.notes) {
      final c = map.putIfAbsent(key(n.subject, n.topicLabel), () => TopicCoverage(n.subject.trim(), n.topicLabel));
      if (n.kind == NoteKind.tip) {
        c.tips++;
      } else {
        c.notes++;
      }
    }
    for (final e in answered.entries) {
      if (e.value.$2 > 0) map[e.key]!.p = e.value.$1 / e.value.$2;
    }
    final list = map.values.toList()
      ..sort((a, b) {
        final s = a.subject.toLowerCase().compareTo(b.subject.toLowerCase());
        return s != 0 ? s : a.topic.toLowerCase().compareTo(b.topic.toLowerCase());
      });
    return list;
  }

  /// Bir sınavın zayıf konuları (başarı < [threshold]) ve bağlı notlar.
  static List<WeakTopic> weakTopics(Exam exam, List<Result> results, BankStore bank, {double threshold = 0.5}) {
    final byTopic = <String, (int, int)>{};
    for (var i = 0; i < exam.questions.length; i++) {
      final q = exam.questions[i];
      final code = q.outcomeCode?.trim() ?? '';
      if (code.isEmpty || q.cancelled) continue;
      var (c, n) = byTopic[code] ?? (0, 0);
      for (final r in results) {
        if (i >= r.outcomes.length) continue;
        n++;
        if (r.outcomes[i] == Outcome.correct) c++;
      }
      byTopic[code] = (c, n);
    }
    final subject = _subjectOf(exam, bank);
    final out = <WeakTopic>[
      for (final e in byTopic.entries)
        if (e.value.$2 > 0 && e.value.$1 / e.value.$2 < threshold)
          WeakTopic(e.key, e.value.$1 / e.value.$2, bank.notesFor(e.key, subject: subject)),
    ]..sort((a, b) => a.rate.compareTo(b.rate));
    return out;
  }

  /// Bir öğrencinin bu sınavda zayıf kaldığı konular (yarıdan azını doğru).
  static List<WeakTopic> studentWeakTopics(Exam exam, Result r, BankStore bank, {double threshold = 0.5}) =>
      weakTopics(exam, [r], bank, threshold: threshold);

  /// Karneler için: öğrenci → zayıf konular ve kısaltılmış hap bilgiler.
  static Map<String, List<(String, double, List<String>)>> studyTopics(Exam exam, List<Result> results, BankStore bank,
      {Iterable<String>? only}) {
    final want = only?.toSet();
    final out = <String, List<(String, double, List<String>)>>{};
    for (final r in results) {
      final id = r.sheet.studentId;
      if (id == null || (want != null && !want.contains(id))) continue;
      final w = studentWeakTopics(exam, r, bank);
      if (w.isEmpty) continue;
      out[id] = [
        for (final x in w.take(3))
          (x.topic, x.rate, [for (final n in x.notes.take(2)) _short(n)]),
      ];
    }
    return out;
  }

  static String _short(BankNote n) {
    final body = n.body.trim().replaceAll(RegExp(r'\s+'), ' ');
    final t = n.title.trim();
    var s = t.isEmpty ? body : (body.isEmpty ? t : '$t: $body');
    if (s.length > 170) s = '${s.substring(0, 167).trimRight()}…';
    return s;
  }

  /// Sınav bankadan geldiyse sorularının ortak dersi.
  static String? _subjectOf(Exam exam, BankStore bank) {
    final subjects = {
      for (final q in exam.questions)
        if (bank.questionById(q.bankId) case final b?) b.subject,
    };
    return subjects.length == 1 ? subjects.first : null;
  }
}

extension on BankQuestion {
  /// Zorluk etiketinin beklenen doğru oranı (karşılaştırma için).
  double get difficultyTarget => switch (difficulty) {
        Difficulty.easy => 0.8,
        Difficulty.medium => 0.55,
        Difficulty.hard => 0.3,
      };
}
