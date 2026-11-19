import 'package:material_ui/material_ui.dart';

import '../core/progress.dart';
import '../main.dart';
import '../reports/pdf_documents.dart';
import 'report_preview_screen.dart';
import 'theme.dart';
import 'widgets.dart';
import '../l10n/l10n.dart';

/// Şube karşılaştırması: aynı sınavın farklı şubelerdeki sonuçları
/// (veya öğretmenin seçtiği herhangi sınavlar).
class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key});

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  final Set<String> _selected = {};
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final groups = sameNameGroups(StoreScope.of(context));
    if (groups.isNotEmpty) _selected.addAll(groups.values.first.map((e) => e.id));
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    final groups = sameNameGroups(store);
    final exams = store.exams.where((e) => _selected.contains(e.id)).toList()
      ..sort((a, b) => a.className.compareTo(b.className));
    final rows = compareExams(store, exams).where((r) => r.report.results.isNotEmpty).toList();
    final sameShape = rows.length >= 2 &&
        rows.every((r) => r.exam.questionCount == rows.first.exam.questionCount);

    Future<void> pdf() async {
      if (rows.length < 2) return toast(context, tr('Karşılaştırmak için en az iki sınav seçin.'));
      await ReportPreviewScreen.open(context,
          title: tr('Şube karşılaştırması'), fileName: 'sube_karsilastirmasi.pdf', build: () => buildComparePdf(rows, school: store.reportSchool));
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr('Şube karşılaştırması')), actions: [
        IconButton(tooltip: tr('PDF rapor'), onPressed: pdf, icon: const Icon(Icons.picture_as_pdf_outlined)),
      ]),
      body: Watermark(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
          Text(tr('Karşılaştırmak istediğiniz sınavları seçin. Aynı adlı sınavlar (farklı şubeler) hızlı seçim olarak üstte.'),
              style: TextStyle(color: muted)),
          if (groups.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final g in groups.values)
                ActionChip(
                  avatar: const Icon(Icons.bolt, size: 18),
                  label: Text(tr('{0} ({1} şube)', [g.first.name, g.length])),
                  onPressed: () => setState(() => _selected
                    ..clear()
                    ..addAll(g.map((e) => e.id))),
                ),
            ]),
          ],
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in store.exams)
              FilterChip(
                label: Text('${e.name} · ${e.className}'),
                selected: _selected.contains(e.id),
                onSelected: (v) => setState(() => v ? _selected.add(e.id) : _selected.remove(e.id)),
              ),
          ]),
          if (rows.length < 2)
            Padding(
              padding: EdgeInsets.only(top: 24),
              child: Text(tr('Karşılaştırma için okunmuş kâğıdı olan en az iki sınav seçin.')),
            )
          else ...[
            SectionTitle(tr('Ortalama puan')),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  for (final r in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        SizedBox(
                          width: 110,
                          child: Text(r.exam.className, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: r.report.stats.mean / r.exam.rule.maxScore,
                              minHeight: 14,
                              color: r == rows.reduce((a, b) => a.report.stats.mean >= b.report.stats.mean ? a : b)
                                  ? NColors.emerald
                                  : (t.brightness == Brightness.dark ? const Color(0xFF6C7BB5) : NColors.ink),
                              backgroundColor: t.colorScheme.surfaceContainerHighest,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 54,
                          child: Text(fmt1(r.report.stats.mean),
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontFeatures: tabular)),
                        ),
                      ]),
                    ),
                ]),
              ),
            ),
            SectionTitle(tr('Özet tablo')),
            Card(
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 22,
                  columns: [
                    DataColumn(label: Text(tr('Şube'))),
                    DataColumn(label: Text(tr('Kişi')), numeric: true),
                    DataColumn(label: Text(tr('Ort.')), numeric: true),
                    DataColumn(label: Text(tr('Medyan')), numeric: true),
                    DataColumn(label: Text(tr('Std.')), numeric: true),
                    DataColumn(label: Text(tr('Başarı')), numeric: true),
                    DataColumn(label: Text(tr('En yüksek')), numeric: true),
                    DataColumn(label: Text('KR-20'), numeric: true),
                  ],
                  rows: [
                    for (final r in rows)
                      DataRow(cells: [
                        DataCell(Text(r.exam.className, style: const TextStyle(fontWeight: FontWeight.w700))),
                        DataCell(Text('${r.report.stats.count}')),
                        DataCell(Text(fmt1(r.report.stats.mean))),
                        DataCell(Text(fmt1(r.report.stats.median))),
                        DataCell(Text(fmt1(r.report.stats.stdDev))),
                        DataCell(Text('%${(r.report.passRate * 100).round()}')),
                        DataCell(Text(fmt1(r.report.stats.max))),
                        DataCell(Text(r.report.stats.kr20 == null ? '–' : fmt2(r.report.stats.kr20!))),
                      ]),
                  ],
                ),
              ),
            ),
            if (sameShape) ...[
              SectionTitle(tr('Soru bazında doğru oranı (%)')),
              Card(
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const SizedBox(width: 70),
                      for (var q = 0; q < rows.first.exam.questionCount; q++)
                        SizedBox(
                            width: 40,
                            child: Text('${q + 1}', textAlign: TextAlign.center, style: t.textTheme.labelSmall)),
                    ]),
                    for (final r in rows)
                      Row(children: [
                        SizedBox(
                            width: 70,
                            child: Text(r.exam.className, style: const TextStyle(fontWeight: FontWeight.w700))),
                        for (final it in r.report.items)
                          Container(
                            width: 38,
                            height: 28,
                            margin: const EdgeInsets.all(1),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              color: (it.p > 0.8
                                      ? NColors.emerald
                                      : it.p >= 0.3
                                          ? NColors.amber
                                          : NColors.coral)
                                  .withValues(alpha: 0.22),
                            ),
                            child: Text('${(it.p * 100).round()}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFeatures: tabular)),
                          ),
                      ]),
                  ]),
                ),
              ),
            ],
            if (rows.every((r) => r.report.outcomes.isNotEmpty)) ...[
              SectionTitle(tr('Kazanım başarısı')),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final code in {for (final r in rows) ...r.report.outcomes.map((o) => o.code)})
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(children: [
                          Expanded(child: Text(code, style: const TextStyle(fontWeight: FontWeight.w600))),
                          for (final r in rows)
                            SizedBox(
                              width: 72,
                              child: Text(
                                '${r.exam.className} %${((r.report.outcomes.where((o) => o.code == code).firstOrNull?.rate ?? 0) * 100).round()}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontFeatures: tabular),
                              ),
                            ),
                        ]),
                      ),
                  ]),
                ),
              ),
            ],
          ],
        ]),
      ),
    );
  }
}
