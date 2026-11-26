import 'package:material_ui/material_ui.dart';

import '../../bank/bank_models.dart';
import '../../bank/blueprint.dart';
import '../../l10n/l10n.dart';
import '../theme.dart';
import 'bank_widgets.dart' show Pill;

/// Belirtke tablosunu alttan açılan sayfada gösterir.
Future<void> showBlueprintSheet(BuildContext context, List<BankQuestion> questions) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => SafeArea(
          child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
            Text(tr('Belirtke tablosu'), style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(tr('Hangi konudan, hangi düşünme düzeyinde kaç soru sorduğunuzu gösterir. Uluslararası sınavlarda (IB, Cambridge) sınav planı böyle yapılır.'),
                style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 14),
            BlueprintTable(Blueprint.of(questions)),
          ]),
        ),
      ),
    );

/// Konu × düşünme düzeyi tablosu ve yorumu.
class BlueprintTable extends StatelessWidget {
  final Blueprint bp;
  const BlueprintTable(this.bp, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final levels = [...CognitiveLevel.levels, if (bp.levelTotal(CognitiveLevel.none) > 0) CognitiveLevel.none];
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    Color heat(int n) {
      if (n == 0 || bp.total == 0) return Colors.transparent;
      final a = (0.12 + 0.6 * n / bp.total * 3).clamp(0.12, 0.7);
      return NColors.emerald.withValues(alpha: a);
    }

    Widget cell(String s, {bool bold = false, Color? bg, double width = 64, TextAlign align = TextAlign.center}) => Container(
          width: width,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
          decoration: BoxDecoration(color: bg, border: Border(bottom: BorderSide(color: t.dividerColor.withValues(alpha: 0.5)))),
          child: Text(s,
              textAlign: align,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, fontSize: 12.5, fontFeatures: tabular)),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            cell(tr('Konu'), bold: true, width: 150, align: TextAlign.start),
            for (final l in levels) cell(l.label, bold: true, width: 78),
            cell(tr('Toplam'), bold: true),
            cell('%', bold: true, width: 52),
          ]),
          for (final topic in bp.topics)
            Row(children: [
              cell(topic, width: 150, align: TextAlign.start),
              for (final l in levels)
                cell(bp.cells[topic]![l.index] == 0 ? '·' : '${bp.cells[topic]![l.index]}', bg: heat(bp.cells[topic]![l.index]), width: 78),
              cell('${bp.topicTotal(topic)}', bold: true),
              cell('${(bp.topicTotal(topic) * 100 / bp.total).round()}', width: 52),
            ]),
          Row(children: [
            cell(tr('Toplam'), bold: true, width: 150, align: TextAlign.start),
            for (final l in levels) cell('${bp.levelTotal(l)}', bold: true, width: 78),
            cell('${bp.total}', bold: true),
            cell('100', bold: true, width: 52),
          ]),
          Row(children: [
            cell('%', bold: true, width: 150, align: TextAlign.start),
            for (final l in levels) cell(bp.total == 0 ? '0' : '${(bp.levelTotal(l) * 100 / bp.total).round()}', width: 78),
          ]),
        ]),
      ),
      const SizedBox(height: 14),
      for (final r in bp.remarks)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.tips_and_updates_outlined, size: 18, color: NColors.amber),
            const SizedBox(width: 8),
            Expanded(child: Text(r)),
          ]),
        ),
      const SizedBox(height: 6),
      Text(tr('Düşünme düzeyleri: Hatırlama ve Anlama temel; Uygulama orta; Analiz, Değerlendirme ve Yaratma üst düzey düşünmedir.'),
          style: TextStyle(fontSize: 12, color: muted)),
    ]);
  }
}

/// Soru kontrolü sonuçlarını alttan açılan sayfada gösterir.
Future<void> showQualitySheet(BuildContext context, List<QualityIssue> issues) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => SafeArea(
          child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
            Text(tr('Soru kontrolü'), style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(tr('Basmadan önce en sık yapılan soru yazım hatalarını arar. Uyarılar öneridir; sınavı yine de basabilirsiniz.'),
                style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 14),
            if (issues.isEmpty)
              Row(children: [
                const Icon(Icons.verified_rounded, color: NColors.emerald),
                const SizedBox(width: 10),
                Expanded(child: Text(tr('Sorun bulunamadı. Cevap dağılımı, şıklar ve soru kökleri uygun görünüyor.'))),
              ]),
            for (final i in issues) QualityIssueTile(i),
          ]),
        ),
      ),
    );

class QualityIssueTile extends StatelessWidget {
  final QualityIssue issue;
  const QualityIssueTile(this.issue, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = issue.warning ? NColors.coral : NColors.amber;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(issue.warning ? Icons.warning_amber_rounded : Icons.info_outline_rounded, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(issue.title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(issue.detail),
              if (issue.questions.isNotEmpty) ...[
                const SizedBox(height: 6),
                Pill(tr('Sorular: {0}', [issue.questions.take(20).join(', ')]), color: color, icon: Icons.format_list_numbered_rounded),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
