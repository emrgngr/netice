// Belirtke tablosu (konu × düşünme düzeyi) ve sınav öncesi soru kontrolü.
//
// Belirtke tablosu uluslararası ölçme uygulamalarında (IB, Cambridge, ABD
// "test blueprint") sınavın kapsamını ve düzeyini göstermenin standart
// yoludur. Soru kontrolü de çoktan seçmeli madde yazım ilkelerinden
// (Haladyna ve Downing) en sık yapılan hataları yakalar.

import 'dart:math' as math;

import '../l10n/l10n.dart';
import 'bank_models.dart';
import 'booklet_builder.dart';

/// Konu × düşünme düzeyi tablosu.
class Blueprint {
  /// Satırlar (konular, bankadaki ilk görülme sırasıyla).
  final List<String> topics;

  /// [konu][düzey] → soru sayısı (düzey sırası [CognitiveLevel.values]).
  final Map<String, List<int>> cells;

  /// Konuların puan toplamı (soru puanı ağırlıklarıyla; yoksa 1).
  final Map<String, double> weights;
  final int total;

  const Blueprint._(this.topics, this.cells, this.weights, this.total);

  factory Blueprint.of(List<BankQuestion> questions) {
    final topics = <String>[];
    final cells = <String, List<int>>{};
    final weights = <String, double>{};
    for (final q in questions) {
      final t = q.topicLabel.isEmpty ? tr('Konusuz') : q.topicLabel;
      if (!cells.containsKey(t)) {
        topics.add(t);
        cells[t] = List.filled(CognitiveLevel.values.length, 0);
      }
      cells[t]![q.cognitive.index]++;
      weights[t] = (weights[t] ?? 0) + (q.points <= 0 ? 1 : q.points);
    }
    return Blueprint._(topics, cells, weights, questions.length);
  }

  /// Bir düzeydeki toplam soru.
  int levelTotal(CognitiveLevel l) => topics.fold(0, (a, t) => a + cells[t]![l.index]);

  /// Bir konudaki toplam soru.
  int topicTotal(String t) => cells[t]!.fold(0, (a, b) => a + b);

  /// Düzeyi belirtilmiş soru sayısı.
  int get tagged => total - levelTotal(CognitiveLevel.none);

  /// Analiz ve üstü düzeydeki soruların oranı (belirtilmişler içinde).
  double get higherShare => tagged == 0 ? 0 : CognitiveLevel.levels.where((l) => l.higher).fold(0, (a, l) => a + levelTotal(l)) / tagged;

  /// Hatırlama düzeyinin oranı (belirtilmişler içinde).
  double get rememberShare => tagged == 0 ? 0 : levelTotal(CognitiveLevel.remember) / tagged;

  /// Tablonun kısa yorumu (kitapçık sihirbazında gösterilir).
  List<String> get remarks {
    final out = <String>[];
    if (total == 0) return out;
    if (tagged == 0) {
      out.add(tr('Soruların düşünme düzeyi belirtilmemiş. Soru düzenleyicide "Düşünme düzeyi" seçerseniz tablo dolar.'));
      return out;
    }
    if (tagged < total) out.add(tr('{0} sorunun düşünme düzeyi belirtilmemiş.', [total - tagged]));
    if (rememberShare >= 0.6) {
      out.add(tr('Soruların %{0}\'i hatırlama düzeyinde. Sınav ezber ağırlıklı görünüyor; uygulama ve analiz sorusu ekleyin.',
          [(rememberShare * 100).round()]));
    }
    if (tagged >= 6 && higherShare == 0) {
      out.add(tr('Analiz, değerlendirme ya da yaratma düzeyinde hiç soru yok. Üst düzey düşünmeyi ölçen birkaç soru önerilir.'));
    }
    if (topics.length >= 3) {
      final counts = [for (final t in topics) topicTotal(t)];
      final maxShare = counts.reduce(math.max) / total;
      if (maxShare >= 0.5) {
        final t = topics[counts.indexOf(counts.reduce(math.max))];
        out.add(tr('Soruların %{0}\'i "{1}" konusundan. Diğer konular az temsil ediliyor.', [(maxShare * 100).round(), t]));
      }
    }
    if (out.isEmpty) out.add(tr('Konu ve düzey dağılımı dengeli görünüyor.'));
    return out;
  }
}

/// Soru kontrolünde bulunan bir sorun.
class QualityIssue {
  /// true: düzeltilmesi önerilir; false: bilgi.
  final bool warning;
  final String title;
  final String detail;

  /// İlgili sorular (A kitapçığındaki numaralar).
  final List<int> questions;
  const QualityIssue(this.title, this.detail, {this.warning = true, this.questions = const []});
}

/// Sınav öncesi soru kontrolü.
class QualityCheck {
  /// Olumsuz soru kökleri (birkaç dilde). Bu sözcükler büyük harfle ya da
  /// altı çizili yazılmazsa öğrenci gözden kaçırabilir.
  static final negative = RegExp(
      r'(değildir|yanlıştır|olamaz|söylenemez|ulaşılamaz|çıkarılamaz|yoktur|hangisi değil|aşağıdakilerden hangisi .{0,40}(değil|olmaz)|\bnot\b|\bexcept\b|\bleast\b|\bnicht\b|\bkein|\bno es\b|\bexcepto\b|\bnon\b|\bsauf\b|не является|кроме|ليس|不是|ではない)',
      caseSensitive: false);

  static final _allNone = RegExp(
      r'^(hepsi|hiçbiri|hicbiri|yukarıdakilerin hepsi|yukarıdakilerin hiçbiri|all of the above|none of the above|alle|keine|todas|ninguna|tutti|nessuna|toutes|aucune)\b',
      caseSensitive: false);

  static List<QualityIssue> run(BookletPlan plan) {
    final out = <QualityIssue>[];
    final a = plan.variants.isEmpty ? const <PrintedQuestion>[] : plan.variants.first.test;
    final mc = [for (final p in a) if (p.question.type == QuestionType.multiple && p.printedCorrect.length == 1) p];

    // 1. Cevap harflerinin dağılımı.
    if (mc.length >= 8) {
      final counts = List.filled(plan.choiceCount, 0);
      for (final p in mc) {
        final c = p.printedCorrect.first;
        if (c < counts.length) counts[c]++;
      }
      final share = counts.reduce(math.max) / mc.length;
      final most = counts.indexOf(counts.reduce(math.max));
      final ideal = (100 / plan.choiceCount).round();
      final summary = [for (var i = 0; i < counts.length; i++) '${String.fromCharCode(65 + i)}: ${counts[i]}'].join(' · ');
      if (share >= 0.4) {
        out.add(QualityIssue(
          tr('Cevapların %{0}\'i {1} şıkkı', [(share * 100).round(), String.fromCharCode(65 + most)]),
          tr('Dağılım: {0}. Her şık yaklaşık %{1} olmalı; öğrenci tahminle puan toplayabilir. Kitapçıkta şıkları karıştırmayı açın ya da birkaç sorunun şık sırasını değiştirin.',
              [summary, ideal]),
          questions: [for (final p in mc) if (p.printedCorrect.first == most) p.no],
        ));
      } else if (mc.length >= plan.choiceCount * 3 && counts.contains(0)) {
        final none = counts.indexOf(0);
        out.add(QualityIssue(
          tr('Hiçbir sorunun cevabı {0} değil', [String.fromCharCode(65 + none)]),
          tr('Dağılım: {0}. Öğrenciler bu şıkkı hiç işaretlememeyi öğrenebilir.', [summary]),
          warning: false,
        ));
      }
    }

    // 2. Art arda aynı cevap (her kitapçıkta).
    for (final v in plan.variants) {
      var run = 1;
      for (var i = 1; i <= v.test.length; i++) {
        final same = i < v.test.length &&
            v.test[i].printedCorrect.length == 1 &&
            v.test[i - 1].printedCorrect.length == 1 &&
            v.test[i].printedCorrect.first == v.test[i - 1].printedCorrect.first;
        if (same) {
          run++;
          continue;
        }
        if (run >= 4) {
          final from = v.test[i - run].no, to = v.test[i - 1].no;
          out.add(QualityIssue(
            plan.variants.length > 1
                ? tr('{0} kitapçığında {1}–{2}. soruların cevabı hep {3}', [v.letter, from, to, String.fromCharCode(65 + v.test[i - 1].printedCorrect.first)])
                : tr('{0}–{1}. soruların cevabı hep {2}', [from, to, String.fromCharCode(65 + v.test[i - 1].printedCorrect.first)]),
            tr('Art arda {0} aynı cevap öğrencide "yanlış yapıyorum" kaygısı yaratır ve cevap değiştirmeye iter.', [run]),
            questions: [for (var k = i - run; k < i; k++) v.test[k].no],
          ));
        }
        run = 1;
      }
    }

    // 3. Doğru şık hep en uzun olan.
    final written = [for (final p in mc) if (p.question.choices.where((c) => c.trim().isNotEmpty).length >= 3) p];
    if (written.length >= 5) {
      final longest = [
        for (final p in written)
          if (_strictlyLongest(p.choices, p.printedCorrect.first)) p.no
      ];
      if (longest.length / written.length > 0.5) {
        out.add(QualityIssue(
          tr('Doğru şık çoğunlukla en uzun şık'),
          tr('{0} sorunun {1}\'inde doğru cevap en uzun şık. Deneyimli öğrenci bunu ipucu olarak kullanır; yanlış şıkları da benzer uzunlukta yazın.',
              [written.length, longest.length]),
          questions: longest,
        ));
      }
    }

    // 4. Olumsuz kök vurgulanmamış.
    final neg = <int>[];
    for (final p in a) {
      final m = negative.firstMatch(p.question.text);
      if (m == null) continue;
      final word = m.group(0)!;
      // Büyük harfle yazılmışsa vurgulanmış sayılır.
      if (word == word.toUpperCase() && word != word.toLowerCase()) continue;
      neg.add(p.no);
    }
    for (final p in [for (final v in plan.variants.take(1)) ...v.open]) {
      final m = negative.firstMatch(p.question.text);
      if (m != null && m.group(0)! != m.group(0)!.toUpperCase()) neg.add(-p.no);
    }
    if (neg.isNotEmpty) {
      out.add(QualityIssue(
        tr('Olumsuz soru kökü vurgulanmamış'),
        tr('"değildir", "yanlıştır", "olamaz" gibi sözcükleri BÜYÜK HARFLE yazın. Hızlı okuyan öğrenci olumsuzluğu kaçırır ve bildiği soruyu yanlış yapar.'),
        questions: [for (final n in neg) if (n > 0) n],
      ));
    }

    // 5. "Hepsi / hiçbiri" şıkları.
    final allNone = [
      for (final p in mc)
        if (p.choices.any((c) => _allNone.hasMatch(c.trim()))) p.no
    ];
    if (allNone.isNotEmpty) {
      out.add(QualityIssue(
        tr('"Hepsi / hiçbiri" şıkkı kullanılmış'),
        tr('Bu şıklar ölçmeyi zayıflatır: iki doğru şıkkı tanıyan öğrenci "hepsi"ni bilmeden bulur. Mümkünse anlamlı bir çeldiriciyle değiştirin.'),
        warning: false,
        questions: allNone,
      ));
    }

    // 6. Eksik şık metni.
    final missing = [
      for (final p in mc)
        if (p.question.choices.isNotEmpty && p.question.choices.any((c) => c.trim().isEmpty)) p.no
    ];
    if (missing.isNotEmpty) {
      out.add(QualityIssue(
        tr('Boş şık var'),
        tr('Bu soruların bazı şıkları yazılmamış. Şıklar görseldeyse metin kutularının hepsini boş bırakın.'),
        questions: missing,
      ));
    }

    // 7. Aynı soru iki kez.
    final seen = <String, int>{};
    final dup = <int>[];
    for (final p in a) {
      if (p.question.parent != null) continue;
      final key = p.question.text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      if (key.length < 12) continue;
      if (seen.containsKey(key)) {
        dup.add(p.no);
      } else {
        seen[key] = p.no;
      }
    }
    if (dup.isNotEmpty) {
      out.add(QualityIssue(tr('Aynı soru birden çok kez var'), tr('Metni aynı olan sorular bulundu.'), questions: dup));
    }

    // 8. Benzer cevap ipucu: doğru şık kökteki bir sözcüğü tekrar ediyor, yanlışlar etmiyor.
    final clue = <int>[];
    for (final p in written) {
      final stem = _words(p.question.text);
      if (stem.isEmpty) continue;
      final right = p.choices[p.printedCorrect.first];
      final hit = _words(right).intersection(stem).isNotEmpty;
      final others = [for (var i = 0; i < p.choices.length; i++) if (i != p.printedCorrect.first) _words(p.choices[i]).intersection(stem).isNotEmpty];
      if (hit && others.every((o) => !o)) clue.add(p.no);
    }
    if (clue.length >= 2) {
      out.add(QualityIssue(
        tr('Doğru şık kökteki sözcüğü tekrar ediyor'),
        tr('Bu sorularda yalnız doğru şık, soru kökündeki bir sözcüğü içeriyor. Bu bir ipucudur; yanlış şıklarda da benzer sözcükler kullanın.'),
        warning: false,
        questions: clue,
      ));
    }

    // 9. Zorluk ve düzey dengesi.
    final all = [...plan.testMaster, ...plan.openMaster];
    if (all.length >= 8) {
      final hard = all.where((q) => q.difficulty == Difficulty.hard).length / all.length;
      final easy = all.where((q) => q.difficulty == Difficulty.easy).length / all.length;
      if (hard >= 0.6) {
        out.add(QualityIssue(tr('Sınav çok zor olabilir'),
            tr('Soruların %{0}\'i zor olarak etiketli. Ortalama düşük çıkar ve sınav öğrencileri ayırt etmez.', [(hard * 100).round()]),
            warning: false));
      } else if (easy >= 0.7) {
        out.add(QualityIssue(tr('Sınav çok kolay olabilir'),
            tr('Soruların %{0}\'i kolay olarak etiketli. Üst düzeydeki öğrenciler ayırt edilemez.', [(easy * 100).round()]),
            warning: false));
      }
    }
    final bp = Blueprint.of(all);
    if (bp.tagged >= 6 && bp.rememberShare >= 0.6) {
      out.add(QualityIssue(tr('Sınav ezber ağırlıklı'), bp.remarks.firstWhere((r) => r.contains('%'), orElse: () => ''), warning: false));
    }
    return out;
  }

  static bool _strictlyLongest(List<String> choices, int correct) {
    if (correct < 0 || correct >= choices.length) return false;
    final len = choices[correct].trim().length;
    for (var i = 0; i < choices.length; i++) {
      if (i != correct && choices[i].trim().length >= len * 0.95) return false;
    }
    return true;
  }

  static final _wordRe = RegExp(r'[\p{L}]{5,}', unicode: true);
  static const _stop = {
    'aşağıdakilerden', 'hangisidir', 'hangisi', 'olarak', 'göre', 'which', 'following', 'there', 'their', 'about', 'these', 'olduğu', 'yukarıdaki'
  };
  static Set<String> _words(String s) =>
      {for (final m in _wordRe.allMatches(s.toLowerCase())) if (!_stop.contains(m.group(0))) m.group(0)!};
}
