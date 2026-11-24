import 'package:material_ui/material_ui.dart';

import '../../bank/bank_analysis.dart';
import '../../bank/bank_models.dart';
import '../../bank/bank_store.dart';
import '../../core/models.dart';
import '../../core/scoring.dart';
import '../../l10n/l10n.dart';
import '../../main.dart';
import '../../reports/notes_pdf.dart';
import '../theme.dart';
import '../widgets.dart';
import 'bank_widgets.dart';
import 'library_screen.dart' show DifficultyBar;
import 'note_screens.dart';
import 'question_editor_screen.dart';

/// Kütüphane › Analiz.
class BankAnalysisView extends StatelessWidget {
  const BankAnalysisView({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context);
    if (bank.questions.isEmpty && bank.notes.isEmpty) {
      return ListView(children: [
        BankEmpty(
          icon: Icons.insights_rounded,
          title: tr('Analiz için soru ekleyin'),
          text: tr('Bankanızın zorluk dağılımı, konu kapsamı ve sınavlarda gerçekte nasıl çalıştığı burada görünür.'),
        ),
      ]);
    }
    final used = BankStore.usage(store.exams);
    final linked = [
      for (final e in store.exams)
        if (e.questions.any((q) => q.bankId != null)) (e, store.resultsOf(e)),
    ];
    final stats = BankAnalysis.itemStats(linked);
    final cover = BankAnalysis.coverage(bank, used: used, stats: stats);
    final mis = BankAnalysis.mislabeled(bank.questions, stats);
    final hardest = BankAnalysis.hardest(bank.questions, stats);
    final counts = [for (final d in Difficulty.values) bank.questions.where((q) => q.difficulty == d).length];
    final usedCount = bank.questions.where((q) => (used[q.id] ?? 0) > 0).length;
    final tips = bank.notes.where((n) => n.kind == NoteKind.tip).length;

    // Son sınavların zayıf konuları (konu kodu olan sınavlar).
    final recent = [...store.exams.where((e) => e.questions.any((q) => (q.outcomeCode ?? '').isNotEmpty))]
      ..sort((a, b) => b.date.compareTo(a.date));
    final weak = <(Exam, List<WeakTopic>)>[];
    for (final e in recent.take(6)) {
      final rs = store.resultsOf(e);
      if (rs.isEmpty) continue;
      final w = BankAnalysis.weakTopics(e, rs, bank);
      if (w.isNotEmpty) weak.add((e, w));
    }

    final bySubject = <String, List<int>>{};
    for (final q in bank.questions) {
      bySubject.putIfAbsent(q.subject.trim().isEmpty ? tr('Ders yazılmamış') : q.subject.trim(), () => [0, 0, 0])[q.difficulty.index]++;
    }
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);

    Widget card(IconData icon, String title, String? sub, List<Widget> children, {Widget? trailing, Color color = NColors.emerald}) => Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                IconBadge(icon, color: color, size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    if (sub != null) Text(sub, style: t.textTheme.bodySmall?.copyWith(color: muted)),
                  ]),
                ),
                ?trailing,
              ]),
              const SizedBox(height: 12),
              ...children,
            ]),
          ),
        );

    final statTiles = [
      StatCard(label: tr('Soru'), value: '${bank.questions.length}', icon: Icons.quiz_outlined),
      StatCard(label: tr('Hap bilgi / özet'), value: '$tips / ${bank.notes.length - tips}', icon: Icons.bolt_rounded),
      StatCard(label: tr('Sınavda kullanılan'), value: bank.questions.isEmpty ? '–' : '%${(usedCount * 100 / bank.questions.length).round()}', icon: Icons.history_rounded),
      StatCard(label: tr('Konu'), value: '${cover.length}', icon: Icons.topic_outlined),
    ];

    return ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 40), children: [
      if (wide)
        Row(children: [for (final s in statTiles) Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: s))])
      else
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.55,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: statTiles,
        ),
      const SizedBox(height: 12),
      card(Icons.signal_cellular_alt_rounded, tr('Zorluk dağılımı'), tr('Önerilen denge: %30 kolay, %50 orta, %20 zor'), [
        DifficultyBar(counts: counts, height: 14),
        const SizedBox(height: 8),
        Wrap(spacing: 14, children: [
          for (final d in Difficulty.values)
            Text('${d.label}: ${counts[d.index]} (%${bank.questions.isEmpty ? 0 : (counts[d.index] * 100 / bank.questions.length).round()})',
                style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
        if (bySubject.length > 1) ...[
          const Divider(height: 24),
          for (final e in bySubject.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                SizedBox(width: 110, child: Text(e.key, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                Expanded(child: DifficultyBar(counts: e.value, height: 9)),
                SizedBox(width: 40, child: Text('${e.value.fold(0, (a, b) => a + b)}', textAlign: TextAlign.end, style: const TextStyle(fontFeatures: tabular))),
              ]),
            ),
        ],
      ]),
      card(Icons.grid_view_rounded, tr('Konu kapsamı'), tr('Her konudaki soru sayısı ve notlar. Eksikleri buradan tamamlayın.'), [
        for (var i = 0; i < cover.length; i++) ...[
          if (i == 0 || cover[i - 1].subject.toLowerCase() != cover[i].subject.toLowerCase())
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 10, bottom: 4),
              child: Text(cover[i].subject.isEmpty ? tr('Ders yazılmamış') : cover[i].subject,
                  style: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800, color: muted)),
            ),
          _CoverageRow(c: cover[i]),
        ],
      ]),
      if (mis.isNotEmpty)
        card(
          Icons.compare_arrows_rounded,
          tr('Zorluk etiketi gözden geçirilmeli'),
          tr('Sınav sonuçlarına göre etiketi gerçek zorluğundan farklı {0} soru', [mis.length]),
          [
            for (final (q, s) in mis.take(12))
              _QRow(
                q: q,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('%${(s.p * 100).round()}', style: const TextStyle(fontWeight: FontWeight.w800, fontFeatures: tabular)),
                  const SizedBox(width: 6),
                  DifficultyPill(q.difficulty),
                  const Icon(Icons.arrow_right_alt_rounded, size: 18),
                  DifficultyPill(s.measured),
                ]),
              ),
          ],
          color: NColors.amber,
          trailing: FilledButton.tonal(
            onPressed: () {
              final m = {for (final (q, s) in mis) q.id: s.measured};
              bank.updateMany(m.keys, (q) => q.copyWith(difficulty: m[q.id]));
              toast(context, tr('{0} sorunun zorluğu sonuçlara göre güncellendi.', [m.length]));
            },
            child: Text(tr('Tümünü güncelle')),
          ),
        ),
      if (hardest.isNotEmpty)
        card(Icons.trending_down_rounded, tr('En çok yanlış yapılan sorular'), tr('Doğru cevaplama oranı en düşük olanlar'), [
          for (final (q, s) in hardest)
            _QRow(
              q: q,
              trailing: Text(tr('%{0} doğru', [(s.p * 100).round()]),
                  style: TextStyle(fontWeight: FontWeight.w800, color: s.p < 0.3 ? NColors.coral : null, fontFeatures: tabular)),
            ),
        ], color: NColors.coral),
      if (linked.isEmpty)
        card(Icons.info_outline_rounded, tr('Sonuçlarla bağlantı'), null, [
          Text(tr('Kitapçık sihirbazından "Sınav oluştur" ile yaptığınız sınavlar okutuldukça, soruların gerçek zorluğu ve en çok yanlış yapılan sorular burada görünür.'),
              style: TextStyle(color: muted)),
        ], color: NColors.ink),
      if (weak.isNotEmpty)
        card(Icons.school_outlined, tr('Son sınavlarda zayıf konular'), tr('Başarının %50\'nin altında kaldığı konular ve hap bilgileri'), [
          for (final (e, w) in weak) ...[
            Row(children: [
              Expanded(
                child: Text('${e.name} · ${e.className.isEmpty ? '' : e.className}',
                    style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              TextButton.icon(
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: Text(tr('Çalışma föyü')),
                onPressed: () => openWeakTopicsPdf(context, e, w),
              ),
            ]),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final x in w)
                Pill('${x.topic} · %${(x.rate * 100).round()}${x.notes.isEmpty ? '' : ' · ${x.notes.length} ${tr('not')}'}',
                    color: x.notes.isEmpty ? NColors.coral : NColors.emerald, icon: x.notes.isEmpty ? Icons.error_outline_rounded : Icons.bolt_rounded),
            ]),
            const SizedBox(height: 10),
          ],
        ], color: NColors.ink),
    ]);
  }
}

class _CoverageRow extends StatelessWidget {
  final TopicCoverage c;
  const _CoverageRow({required this.c});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: c.notes + c.tips == 0
          ? () => NoteEditorScreen.open(
              context, bank.newNote(kind: NoteKind.tip).copyWith(subject: c.subject, topic: c.topic), NoteKind.tip)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(child: Text(c.topic.isEmpty ? '—' : c.topic, maxLines: 1, overflow: TextOverflow.ellipsis)),
          for (final d in Difficulty.values)
            Container(
              width: 28,
              margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.symmetric(vertical: 2),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: difficultyColor(d).withValues(alpha: c.byDifficulty[d.index] == 0 ? 0.06 : 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('${c.byDifficulty[d.index]}', style: t.textTheme.labelMedium?.copyWith(fontFeatures: tabular, fontWeight: FontWeight.w700)),
            ),
          const SizedBox(width: 8),
          SizedBox(
            width: 74,
            child: c.notes + c.tips == 0
                ? Text(tr('+ hap bilgi'), textAlign: TextAlign.end, style: const TextStyle(color: NColors.coral, fontWeight: FontWeight.w700, fontSize: 12.5))
                : Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    const Icon(Icons.bolt_rounded, size: 15, color: NColors.amber),
                    Text('${c.tips}', style: const TextStyle(fontFeatures: tabular)),
                    const SizedBox(width: 6),
                    const Icon(Icons.menu_book_rounded, size: 14, color: NColors.emerald),
                    Text('${c.notes}', style: const TextStyle(fontFeatures: tabular)),
                  ]),
          ),
        ]),
      ),
    );
  }
}

class _QRow extends StatelessWidget {
  final BankQuestion q;
  final Widget trailing;
  const _QRow({required this.q, required this.trailing});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => QuestionEditorScreen.open(context, q),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(q.text.trim().isEmpty ? tr('(görselli soru)') : q.text.trim(), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(q.topicLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
            const SizedBox(width: 8),
            trailing,
          ]),
        ),
      );
}

/// Bir sınavın zayıf konuları için hap bilgi föyü.
Future<void> openWeakTopicsPdf(BuildContext context, Exam e, List<WeakTopic> w, {String? studentName}) => openNotesPdf(
      context,
      const [],
      title: studentName == null ? tr('{0} · Çalışılması gereken konular', [e.name]) : tr('{0} · Çalışması gereken konular', [studentName]),
      sections: [
        for (final x in w) NotesSection(x.topic, x.notes, subtitle: tr('Başarı %{0}', [(x.rate * 100).round()])),
      ],
    );

/// Sınav analizinde: zayıf konular ve bağlı hap bilgiler.
class WeakTopicsCard extends StatelessWidget {
  final Exam exam;
  final List<Result> results;
  const WeakTopicsCard({super.key, required this.exam, required this.results});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: bank,
        builder: (context, _) {
          final t = Theme.of(context);
          final w = BankAnalysis.weakTopics(exam, results, bank);
          final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionTitle(tr('Zayıf konular ve hap bilgiler'),
                trailing: w.isEmpty
                    ? null
                    : TextButton.icon(
                        onPressed: () => openWeakTopicsPdf(context, exam, w),
                        icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                        label: Text(tr('Çalışma föyü')),
                      )),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: w.isEmpty
                    ? Row(children: [
                        const Icon(Icons.verified_rounded, color: NColors.emerald),
                        const SizedBox(width: 10),
                        Expanded(child: Text(tr('Sınıf her konuda %50\'nin üzerinde başarılı.'), style: TextStyle(color: muted))),
                      ])
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text(tr('Kütüphanedeki hap bilgiler öğrenci karnesine "Çalışması gereken konular" olarak eklenir.'),
                            style: t.textTheme.bodySmall?.copyWith(color: muted)),
                        const SizedBox(height: 8),
                        for (final x in w)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(children: [
                              SizedBox(
                                width: 48,
                                child: Text(L10n.percent((x.rate * 100).round()),
                                    style: const TextStyle(fontWeight: FontWeight.w800, color: NColors.coral, fontFeatures: tabular)),
                              ),
                              Expanded(child: Text(x.topic, style: const TextStyle(fontWeight: FontWeight.w600))),
                              if (x.notes.isNotEmpty)
                                ActionChip(
                                  avatar: const Icon(Icons.bolt_rounded, size: 16, color: NColors.amber),
                                  label: Text(tr('{0} not', [x.notes.length])),
                                  onPressed: () => x.notes.length == 1
                                      ? NoteViewScreen.open(context, x.notes.first)
                                      : openNotesPdf(context, x.notes, title: x.topic),
                                )
                              else
                                TextButton.icon(
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  label: Text(tr('Hap bilgi ekle')),
                                  onPressed: () => NoteEditorScreen.open(
                                      context, bank.newNote(kind: NoteKind.tip).copyWith(topic: x.topic), NoteKind.tip),
                                ),
                            ]),
                          ),
                      ]),
              ),
            ),
          ]);
        },
      );
}
