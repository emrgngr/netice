import 'dart:math' as math;

import '../l10n/l10n.dart';
import 'models.dart';
import 'progress.dart';
import 'report.dart';

/// Cihazda, kurallarla üretilen öğretmen yorumları. Hiçbir veri dışarı
/// gönderilmez; aynı sonuçlar her zaman aynı yorumu üretir (itirazda
/// açıklanabilir).

/// Bir eylem önerisi: ne yapılmalı ve kimin için.
class ActionItem {
  final String title;
  final String detail;
  const ActionItem(this.title, this.detail);
}

String _pct(double v) => L10n.percent((v * 100).round());

/// Sınav sonrası "ne yapmalı?" planı: önce anahtar hataları, sonra konu
/// tekrarı, destek gereken öğrenciler ve zenginleştirme.
List<ActionItem> classActionPlan(ExamReport r, Map<String, Student> students) {
  if (r.results.isEmpty) return const [];
  final exam = r.exam;
  final out = <ActionItem>[];

  final suspicious = r.items.where((i) => i.suspiciousChoice != null).toList();
  if (suspicious.isNotEmpty) {
    out.add(ActionItem(
      tr('Önce cevap anahtarını kontrol edin'),
      tr('{0}. soruda başarılı öğrencilerin çoğu başka şıkkı seçti. Anahtar hatalıysa düzeltin ya da soruyu iptal edin; puanlar kendiliğinden yenilenir.',
          [suspicious.map((i) => '${i.no} (${String.fromCharCode(65 + i.suspiciousChoice!)})').join(', ')]),
    ));
  }

  final weakOutcomes = [...r.outcomes.where((o) => o.rate < 0.5)]..sort((a, b) => a.rate.compareTo(b.rate));
  if (weakOutcomes.isNotEmpty) {
    out.add(ActionItem(
      tr('Sınıfça tekrar edilecek konular'),
      tr('{0}. Bu konularda sınıfın yarısından azı doğru yaptı; bir ders saati tekrar ve kısa bir ara sınav önerilir.',
          [weakOutcomes.take(4).map((o) => '${o.code} (${_pct(o.rate)})').join(', ')]),
    ));
  } else {
    final hard = r.items
        .where((i) => !exam.questions[i.no - 1].cancelled && i.p < 0.4 && i.suspiciousChoice == null)
        .map((i) => i.no)
        .toList();
    if (hard.isNotEmpty) {
      out.add(ActionItem(
        tr('Sınıfça tekrar edilecek sorular'),
        tr('{0}. soruları öğrencilerin çoğu yapamadı; bu soruların konularını derste birlikte çözün.', [hard.take(8).join(', ')]),
      ));
    }
  }

  final below = r.standings.where((s) => s.result.score < exam.rule.pass).toList()
    ..sort((a, b) => a.pct.compareTo(b.pct));
  if (below.isNotEmpty) {
    final names = below
        .take(6)
        .map((s) => students[s.result.sheet.studentId]?.fullName)
        .whereType<String>()
        .toList();
    out.add(ActionItem(
      tr('Destek gereken öğrenciler ({0})', [below.length]),
      names.isEmpty
          ? tr('{0} öğrenci geçme puanının altında kaldı. Birebir görüşme veya telafi çalışması planlayın.', [below.length])
          : tr('{0}{1} geçme puanının altında kaldı. Birebir görüşme veya telafi çalışması planlayın.',
              [names.join(', '), below.length > names.length ? tr(' ve {0} öğrenci daha', [below.length - names.length]) : '']),
    ));
  }

  final topCut = math.max(1, (r.standings.length * 0.15).round());
  final top = [...r.standings]..sort((a, b) => b.pct.compareTo(a.pct));
  final stars = top.take(topCut).where((s) => s.pct >= 85).toList();
  if (stars.isNotEmpty) {
    final names = stars.map((s) => students[s.result.sheet.studentId]?.fullName).whereType<String>().toList();
    if (names.isNotEmpty) {
      out.add(ActionItem(
        tr('Zenginleştirme'),
        tr('{0} konuya hâkim görünüyor; üst düzey sorular veya akran öğretimi için görevlendirilebilir.', [names.join(', ')]),
      ));
    }
  }

  final blankRate = exam.questionCount == 0 ? 0.0 : r.meanBlank / exam.questionCount;
  if (blankRate >= 0.2) {
    out.add(ActionItem(
      tr('Süre ve sınav stratejisi'),
      tr('Soruların ortalama {0}\'i boş bırakıldı. Süre yetmemiş ya da öğrenciler emin olmadıkları soruları atlamış olabilir.', [_pct(blankRate)]),
    ));
  }

  if (out.isEmpty) {
    out.add(ActionItem(
      tr('Sınıf hedefte'),
      tr('Belirgin bir eksik görünmüyor. Bir sonraki konuya geçilebilir.'),
    ));
  }
  return out;
}

/// Öğrencinin tüm sınavlarına bakarak karneye eklenecek kısa gelişim notu.
List<String> studentDevelopmentNote(List<HistoryEntry> h) {
  if (h.isEmpty) return const [];
  final out = <String>[];
  final last = h.last;
  final diff = last.pct - (last.classSize > 0 ? _classPct(last) : last.pct);

  if (h.length >= 3) {
    final recent = h.sublist(h.length - 3);
    final change = recent.last.pct - recent.first.pct;
    if (change >= 8) {
      out.add(tr('Son 3 sınavda yükselişte: başarı {0} puan arttı.', [change.round()]));
    } else if (change <= -8) {
      out.add(tr('Son 3 sınavda düşüşte: başarı {0} puan geriledi. Görüşme önerilir.', [(-change).round()]));
    } else {
      out.add(tr('Son 3 sınavda istikrarlı bir çizgide.'));
    }
  } else if (h.length == 2) {
    final change = h[1].pct - h[0].pct;
    if (change.abs() >= 5) {
      out.add(change > 0
          ? tr('Önceki sınava göre {0} puan yükseldi.', [change.round()])
          : tr('Önceki sınava göre {0} puan geriledi.', [(-change).round()]));
    } else {
      out.add(tr('Önceki sınavla benzer düzeyde.'));
    }
  }

  if (diff >= 10) {
    out.add(tr('Son sınavda sınıf ortalamasının {0} puan üzerinde.', [diff.round()]));
  } else if (diff <= -10) {
    out.add(tr('Son sınavda sınıf ortalamasının {0} puan altında.', [(-diff).round()]));
  } else {
    out.add(tr('Son sınavda sınıf ortalaması düzeyinde.'));
  }

  final o = outcomeSummary(h);
  if (o.length >= 2) {
    final sorted = o.entries.toList()..sort((a, b) => a.value.$1.compareTo(b.value.$1));
    final weak = sorted.first;
    final strong = sorted.last;
    if (strong.value.$1 >= 0.7) out.add(tr('Güçlü olduğu konu: {0} ({1}).', [strong.key, _pct(strong.value.$1)]));
    if (weak.value.$1 < 0.6) out.add(tr('Çalışması gereken konu: {0} ({1}).', [weak.key, _pct(weak.value.$1)]));
  }

  final passes = h.where((e) => e.passed).length;
  if (h.length >= 2) out.add(tr('{0} sınavın {1} tanesinde geçme puanını aldı.', [h.length, passes]));
  return out;
}

/// Sınıf ortalamasının tam puana oranı (0..100).
double _classPct(HistoryEntry e) => e.exam.rule.maxScore == 0 ? 0 : e.classMean / e.exam.rule.maxScore * 100;
