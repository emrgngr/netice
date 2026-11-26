// Eşdeğer telafi (mazeret) sınavı: soru bankasından hazırlanmış bir sınavın
// her sorusu yerine aynı ders, konu, soru türü ve zorlukta başka bir soru
// seçilir. Böylece iki sınav kapsam ve güçlük bakımından denk olur
// (uluslararası sınavlardaki "paralel form" yaklaşımı).

import 'dart:math' as math;

import '../core/models.dart';
import 'bank_models.dart';
import 'bank_store.dart';

class MakeupPlan {
  /// Yeni sınavın soruları (asıl sınavın sırasıyla).
  final List<BankQuestion> questions;

  /// Eşdeğeri bulunamadığı için aynısı bırakılan sorular.
  final int kept;

  /// Zorluğu farklı bir eşdeğerle değiştirilen sorular.
  final int relaxed;

  /// Asıl sınavda bankadan gelen soru sayısı.
  final int fromBank;

  const MakeupPlan(this.questions, this.kept, this.relaxed, this.fromBank);
}

class Makeup {
  static String _n(String s) => s.trim().toLowerCase();

  /// Sınavın bankadaki soruları (grup maddeleri tek soru sayılır), sırasıyla.
  static List<BankQuestion> sourceOf(Exam exam, BankStore bank) {
    final ids = <String>[];
    for (final q in exam.questions) {
      if (q.bankId != null && !ids.contains(q.bankId)) ids.add(q.bankId!);
    }
    for (final q in exam.openQuestions) {
      if (q.bankId != null && !ids.contains(q.bankId)) ids.add(q.bankId!);
    }
    return [for (final id in ids) ?bank.questionById(id)];
  }

  static MakeupPlan build(Exam exam, BankStore bank, {Map<String, int> used = const {}, int seed = 1}) {
    final source = sourceOf(exam, bank);
    final rnd = math.Random(seed);
    final taken = {for (final q in source) q.id};
    final out = <BankQuestion>[];
    var kept = 0, relaxed = 0;
    for (final q in source) {
      bool same(BankQuestion c, {bool strictDifficulty = true}) =>
          !taken.contains(c.id) &&
          c.complete &&
          c.type == q.type &&
          _n(c.subject) == _n(q.subject) &&
          _n(c.topicLabel) == _n(q.topicLabel) &&
          (!strictDifficulty || c.difficulty == q.difficulty) &&
          c.items.length == q.items.length;
      var pool = bank.questions.where((c) => same(c)).toList();
      var strict = true;
      if (pool.isEmpty) {
        pool = bank.questions.where((c) => same(c, strictDifficulty: false)).toList();
        strict = false;
      }
      if (pool.isEmpty) {
        out.add(q);
        kept++;
        continue;
      }
      // Düşünme düzeyi aynı olanlar, sonra daha az kullanılmış olanlar öne.
      pool.shuffle(rnd);
      pool.sort((a, b) {
        final la = a.cognitive == q.cognitive ? 0 : 1, lb = b.cognitive == q.cognitive ? 0 : 1;
        if (la != lb) return la.compareTo(lb);
        return (used[a.id] ?? 0).compareTo(used[b.id] ?? 0);
      });
      final pick = pool.first;
      taken.add(pick.id);
      out.add(pick);
      if (!strict) relaxed++;
    }
    return MakeupPlan(out, kept, relaxed, source.length);
  }
}
