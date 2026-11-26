// Sınav sonrası öğretim araçları: çalışma grupları (RTI / MTSS katmanları)
// ve benzer yanlış (kopya şüphesi) uyarısı.

import 'dart:math' as math;

import '../l10n/l10n.dart';
import 'misconceptions.dart';
import 'models.dart';
import 'report.dart';
import 'scoring.dart';

/// Çalışma grubu katmanı.
enum StudyTier {
  support,
  reinforce,
  enrich;

  String get label => switch (this) {
        StudyTier.support => tr('Destek grubu'),
        StudyTier.reinforce => tr('Pekiştirme grubu'),
        StudyTier.enrich => tr('Zenginleştirme grubu'),
      };

  String get rule => switch (this) {
        StudyTier.support => tr('Geçme sınırının altında kalanlar'),
        StudyTier.reinforce => tr('Geçen ama %85\'in altında kalanlar'),
        StudyTier.enrich => tr('%85 ve üzeri alanlar'),
      };

  /// Gruba önerilen çalışma (uluslararası farklılaştırılmış öğretim uygulamalarından).
  List<String> get plan => switch (this) {
        StudyTier.support => [
            tr('Öğretmenle küçük grup çalışması: zayıf kazanımları somut örnekle yeniden anlatın.'),
            tr('Kısa ve sık geri bildirim: her derste 3–5 soruluk çıkış kartı.'),
            tr('Kişiye özel tekrar testi ile 1–2 hafta içinde yeniden ölçün.'),
          ],
        StudyTier.reinforce => [
            tr('Eşli çalışma: yanlış yaptığı soruları arkadaşına açıklayarak çözme.'),
            tr('Zayıf kazanımlarda karışık alıştırma (farklı soru türleriyle).'),
            tr('Bir sonraki sınavdan önce kısa bir quiz ile kontrol.'),
          ],
        StudyTier.enrich => [
            tr('Üst düzey düşünme: analiz ve değerlendirme gerektiren açık uçlu görevler.'),
            tr('Akran rehberliği: destek grubundaki arkadaşlarına yardımcı olma.'),
            tr('Konuyu günlük hayata bağlayan küçük bir proje ya da sunum.'),
          ],
      };
}

class StudyGroup {
  final StudyTier tier;
  final List<Result> members;

  /// Grubun en zayıf olduğu kazanımlar (kod, grubun doğru oranı).
  final List<(String, double)> weakOutcomes;

  /// Grupta en sık görülen yanılgılar (metin, öğrenci sayısı).
  final List<(String, int)> misconceptions;

  /// Grubun puan ortalaması (yüzde).
  final double meanPct;

  const StudyGroup(this.tier, this.members, this.weakOutcomes, this.misconceptions, this.meanPct);
}

class StudyGroups {
  static List<StudyGroup> of(Exam exam, List<Result> results) {
    final scorable = results.where((r) => !r.openMissing || !exam.hasOpen).toList();
    if (scorable.isEmpty) return const [];
    final report = ExamReport.build(exam, scorable);
    final max = exam.rule.maxScore;
    final passPct = max == 0 ? 50.0 : exam.rule.pass / max * 100;
    double pct(Result r) => max == 0 ? 0 : r.score / max * 100;
    StudyTier tierOf(Result r) {
      final p = pct(r);
      if (p < passPct) return StudyTier.support;
      if (p >= 85) return StudyTier.enrich;
      return StudyTier.reinforce;
    }

    final out = <StudyGroup>[];
    for (final t in StudyTier.values) {
      final members = scorable.where((r) => tierOf(r) == t).toList()..sort((a, b) => a.score.compareTo(b.score));
      if (members.isEmpty) continue;
      final weak = <(String, double)>[];
      for (final o in report.outcomes) {
        final rate = members.map((r) => o.rateOf(exam, r)).reduce((a, b) => a + b) / members.length;
        if (rate < 0.7) weak.add((o.code, rate));
      }
      weak.sort((a, b) => a.$2.compareTo(b.$2));
      // Kazanım girilmemişse en çok yanlış yapılan sorular.
      if (report.outcomes.isEmpty) {
        final miss = <(String, double)>[];
        for (var i = 0; i < exam.questions.length; i++) {
          if (exam.questions[i].cancelled) continue;
          final rate = members.where((r) => i < r.outcomes.length && r.outcomes[i] == Outcome.correct).length / members.length;
          if (rate < 0.5) miss.add((tr('{0}. soru', [i + 1]), rate));
        }
        miss.sort((a, b) => a.$2.compareTo(b.$2));
        weak.addAll(miss.take(5));
      }
      final mis = <String, int>{};
      for (final r in members) {
        for (final m in Misconceptions.ofSheet(exam, r.sheet)) {
          mis[m] = (mis[m] ?? 0) + 1;
        }
      }
      final misList = [for (final e in mis.entries) (e.key, e.value)]..sort((a, b) => b.$2.compareTo(a.$2));
      final mean = members.map(pct).reduce((a, b) => a + b) / members.length;
      out.add(StudyGroup(t, members, weak.take(5).toList(), misList.take(3).toList(), mean));
    }
    return out;
  }
}

/// İki öğrencinin cevapları arasındaki olağan dışı benzerlik.
class SimilarPair {
  final Result a, b;

  /// İkisinin de aynı yanlış şıkkı işaretlediği sorular (1'den numara).
  final List<int> sameWrong;

  /// İkisinin de yanlış yaptığı soru sayısı.
  final int bothWrong;

  /// Ortak cevap oranı (aynı şık / cevaplanan soru).
  final double agreement;
  const SimilarPair(this.a, this.b, this.sameWrong, this.bothWrong, this.agreement);
}

class SimilarAnswers {
  /// En az bu kadar ortak yanlış olmadan uyarı verilmez.
  static const minSameWrong = 4;

  /// Bu sayıdan az soru ya da öğrencide yöntem güvenilir değildir.
  static const minQuestions = 10, minStudents = 6;

  static bool applicable(Exam exam, List<Result> results) =>
      exam.questions.where((q) => !q.cancelled).length >= minQuestions && results.length >= minStudents;

  /// Ortak yanlış sayısı sınıftaki çiftlerin ortalamasından belirgin biçimde
  /// yüksek olan çiftler (çoktan seçmeli sınavlarda kullanılan "aynı yanlış"
  /// göstergesinin sade hali). Kesin kanıt değildir; yalnız öğretmene gösterilir.
  static List<SimilarPair> of(Exam exam, List<Result> results) {
    if (!applicable(exam, results)) return const [];
    final active = [for (var i = 0; i < exam.questions.length; i++) if (!exam.questions[i].cancelled) i];
    int? choice(Result r, int i) {
      if (i >= r.sheet.answers.length) return null;
      final m = r.sheet.answers[i].marked;
      return m.length == 1 ? m.first : null;
    }

    final pairs = <SimilarPair>[];
    final counts = <int>[];
    for (var x = 0; x < results.length; x++) {
      for (var y = x + 1; y < results.length; y++) {
        final a = results[x], b = results[y];
        final same = <int>[];
        var both = 0, agree = 0, answered = 0;
        for (final i in active) {
          final ca = choice(a, i), cb = choice(b, i);
          if (ca != null && cb != null) {
            answered++;
            if (ca == cb) agree++;
          }
          final wa = i < a.outcomes.length && a.outcomes[i] == Outcome.wrong;
          final wb = i < b.outcomes.length && b.outcomes[i] == Outcome.wrong;
          if (wa && wb) {
            both++;
            if (ca != null && ca == cb) same.add(i + 1);
          }
        }
        counts.add(same.length);
        if (same.length >= minSameWrong) {
          pairs.add(SimilarPair(a, b, same, both, answered == 0 ? 0 : agree / answered));
        }
      }
    }
    if (pairs.isEmpty) return const [];
    final mean = counts.reduce((a, b) => a + b) / counts.length;
    final sd = math.sqrt(counts.map((c) => (c - mean) * (c - mean)).reduce((a, b) => a + b) / counts.length);
    final limit = math.max(minSameWrong.toDouble(), mean + 3 * sd);
    final out = pairs.where((p) => p.sameWrong.length >= limit && p.sameWrong.length / math.max(1, p.bothWrong) >= 0.7).toList()
      ..sort((a, b) => b.sameWrong.length.compareTo(a.sameWrong.length));
    return out.take(10).toList();
  }
}
