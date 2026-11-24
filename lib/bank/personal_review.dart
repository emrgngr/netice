// Kişiye özel tekrar testi: her öğrencinin sınavda yanlış yaptığı ya da boş
// bıraktığı soruların benzerleri (aynı ders ve konu/kazanım) soru
// bankasından seçilir ve öğrenciye özel bir test olarak basılır.

import 'dart:math' as math;

import '../core/models.dart';
import '../core/scoring.dart';
import 'bank_models.dart';
import 'bank_store.dart';

/// Bir öğrencinin tekrar testi.
class StudentReview {
  final Student student;

  /// Yanlış / boş bırakılan soru numaraları (A kitapçığı sırası, 1'den).
  final List<int> missed;

  /// Eksik kalan konular (testteki sırayla).
  final List<String> topics;

  /// Seçilen benzer sorular.
  final List<BankQuestion> questions;

  const StudentReview(this.student, this.missed, this.topics, this.questions);
}

/// Tekrar testi ayarları.
class ReviewOptions {
  /// Öğrenci başına en fazla soru.
  final int perStudent;

  /// Kaçırılan her konudan en fazla soru.
  final int perTopic;

  /// Bu sınavda zaten sorulmuş soruları da kullan (benzer yoksa).
  final bool allowSame;

  /// Öğrenci kolay/orta soruyu kaçırdıysa zor soru verme.
  final bool gentle;

  /// Yalnızca optik okunabilen sorular (tekrar testini de okutmak için).
  final bool opticalOnly;

  final int seed;

  const ReviewOptions({
    this.perStudent = 10,
    this.perTopic = 3,
    this.allowSame = false,
    this.gentle = true,
    this.opticalOnly = false,
    this.seed = 1,
  });
}

class PersonalReview {
  static String _norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Sınavın [i]. sorusunun konusu ve dersi: bankadan geldiyse sorunun kendi
  /// etiketleri, yoksa kazanım kodu.
  static (String subject, String topic, Difficulty? difficulty, String? bankId) _source(Exam exam, int i, BankStore bank) {
    final q = exam.questions[i];
    final b = bank.questionById(q.bankId);
    if (b != null) return (b.subject, b.topicLabel, b.difficulty, b.id);
    return ('', q.outcomeCode?.trim() ?? '', null, null);
  }

  /// Bankada [topic] konusuna (ya da kazanımına) uyan sorular.
  static List<BankQuestion> similar(BankStore bank, String subject, String topic, {bool opticalOnly = false}) {
    final t = _norm(topic);
    if (t.isEmpty) return const [];
    final s = _norm(subject);
    return [
      for (final q in bank.questions)
        if (q.complete &&
            (!opticalOnly || q.type.optical) &&
            (s.isEmpty || q.subject.trim().isEmpty || _norm(q.subject) == s) &&
            (_norm(q.topicLabel) == t || _norm(q.outcome) == t || _norm(q.topic) == t))
          q,
    ];
  }

  /// Sınavda en az bir öğrencinin kaçırdığı ve bankada benzeri olan konu
  /// sayısı (ekranda "kaç konu için soru var" göstermek için).
  static int coverableTopics(Exam exam, BankStore bank) {
    final seen = <String>{};
    var n = 0;
    for (var i = 0; i < exam.questions.length; i++) {
      final (subject, topic, _, _) = _source(exam, i, bank);
      if (topic.isEmpty || !seen.add('${_norm(subject)}|${_norm(topic)}')) continue;
      if (similar(bank, subject, topic).isNotEmpty) n++;
    }
    return n;
  }

  /// Her öğrenci için tekrar testi oluşturur. Hiç eksiği olmayan ya da eksik
  /// konusu için bankada soru bulunmayan öğrenciler listede yer almaz.
  static List<StudentReview> build(Exam exam, List<Result> results, Map<String, Student> students, BankStore bank,
      {ReviewOptions o = const ReviewOptions(), Set<String>? only}) {
    final inExam = {
      ...exam.questions.map((q) => q.bankId).whereType<String>(),
      ...exam.openQuestions.map((q) => q.bankId).whereType<String>(),
    };
    final out = <StudentReview>[];
    for (final r in results) {
      final st = students[r.sheet.studentId];
      if (st == null || (only != null && !only.contains(st.id))) continue;
      // Kaçırılan sorular konularına göre gruplanır (en çok kaçırılan önce).
      final groups = <String, _Group>{};
      final missed = <int>[];
      for (var i = 0; i < exam.questions.length && i < r.outcomes.length; i++) {
        final oc = r.outcomes[i];
        if (oc != Outcome.wrong && oc != Outcome.blank) continue;
        missed.add(i + 1);
        final (subject, topic, diff, id) = _source(exam, i, bank);
        if (topic.isEmpty) continue;
        final g = groups.putIfAbsent('${_norm(subject)}|${_norm(topic)}', () => _Group(subject, topic));
        g.count++;
        if (id != null) g.sourceIds.add(id);
        if (diff != null && (g.maxDifficulty == null || diff.index > g.maxDifficulty!.index)) g.maxDifficulty = diff;
      }
      if (groups.isEmpty) continue;
      final ordered = groups.values.toList()..sort((a, b) => b.count.compareTo(a.count));
      final rnd = math.Random(o.seed * 31 + st.id.hashCode);
      // Her konu için aday listesi: önce sınavda olmayanlar, kolaydan zora.
      final pools = <_Group, List<BankQuestion>>{};
      for (final g in ordered) {
        var c = similar(bank, g.subject, g.topic, opticalOnly: o.opticalOnly)
            .where((q) => !g.sourceIds.contains(q.id))
            .toList()
          ..shuffle(rnd);
        final fresh = c.where((q) => !inExam.contains(q.id)).toList();
        if (!o.allowSame || fresh.isNotEmpty) c = fresh;
        if (o.gentle && g.maxDifficulty != null && g.maxDifficulty != Difficulty.hard) {
          final soft = c.where((q) => q.difficulty.index <= g.maxDifficulty!.index).toList();
          if (soft.isNotEmpty) c = [...soft, ...c.where((q) => !soft.contains(q))];
        }
        BankStore.mergeSortStable(c, (a, b) => a.difficulty.index.compareTo(b.difficulty.index));
        if (c.isNotEmpty) pools[g] = c;
      }
      if (pools.isEmpty) continue;
      // Konulardan sırayla birer soru al (çok kaçırılan konuya daha çok).
      final picked = <BankQuestion>[];
      final taken = <_Group, int>{};
      final limit = math.max(1, o.perStudent);
      var progress = true;
      while (picked.length < limit && progress) {
        progress = false;
        for (final g in ordered) {
          final pool = pools[g];
          if (pool == null || pool.isEmpty) continue;
          final cap = math.min(o.perTopic, g.count + 1);
          if ((taken[g] ?? 0) >= cap) continue;
          final q = pool.removeAt(0);
          if (picked.any((p) => p.id == q.id)) continue;
          picked.add(q);
          taken[g] = (taken[g] ?? 0) + 1;
          progress = true;
          if (picked.length >= limit) break;
        }
      }
      if (picked.isEmpty) continue;
      out.add(StudentReview(
        st,
        missed,
        [for (final g in ordered) if (pools.containsKey(g)) g.topic],
        picked,
      ));
    }
    out.sort((a, b) => a.student.fullName.compareTo(b.student.fullName));
    return out;
  }
}

class _Group {
  final String subject;
  final String topic;
  int count = 0;
  Difficulty? maxDifficulty;
  final Set<String> sourceIds = {};
  _Group(this.subject, this.topic);
}
