import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/overview.dart';
import '../core/pro.dart';
import '../core/progress.dart';
import '../core/report.dart';
import '../main.dart';
import '../reports/pdf_documents.dart';
import 'charts.dart';
import 'general_stats_screen.dart';
import 'pro_screen.dart';
import 'report_preview_screen.dart';
import 'theme.dart';
import 'widgets.dart';
import '../l10n/l10n.dart';
import '../core/ads.dart';
import 'ad_slot.dart';

/// Sınıf sınıf analiz (şube karşılaştırması): aynı sınavın farklı
/// şubelerdeki sonuçları (veya öğretmenin seçtiği herhangi sınavlar).
class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key});

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

/// Bir şubenin karşılaştırmada kullanılan, yüzde ölçeğine çevrilmiş özeti.
class _Branch {
  final BranchRow row;
  final Dist dist;
  final int registered;
  _Branch(this.row, this.registered)
      : dist = Dist.of(row.report.standings.map((s) => s.pct));

  String get name => row.exam.className;
  ExamReport get rep => row.report;
  double get mean => dist.mean;
  double get passRate => rep.passRate;
  double? get participation => registered == 0 ? null : math.min(1, rep.results.length / registered);
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
    final branches = [for (final r in rows) _Branch(r, store.studentsOf(r.exam.className).length)];

    Future<void> pdf() async {
      if (rows.length < 2) return toast(context, tr('Karşılaştırmak için en az iki sınav seçin.'));
      await ReportPreviewScreen.open(context,
          title: tr('Şube karşılaştırması'), fileName: 'sube_karsilastirmasi.pdf', build: () => buildComparePdf(rows, school: store.reportSchool, students: store.studentById));
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr('Sınıf sınıf analiz')), actions: [
        IconButton(
          tooltip: tr('Genel istatistik'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GeneralStatsScreen())),
          icon: const Icon(Icons.query_stats_rounded),
        ),
        IconButton(tooltip: tr('PDF rapor'), onPressed: pdf, icon: const Icon(Icons.picture_as_pdf_outlined)),
      ]),
      bottomNavigationBar: const AdBannerBar(AdPage.compare),
      body: Watermark(
        child: ListView(padding: EdgeInsets.fromLTRB(20, 8, 20, 40 + MediaQuery.paddingOf(context).bottom), children: [
          Text(tr('Karşılaştırmak istediğiniz sınavları seçin. Aynı adlı sınavlar (farklı şubeler) hızlı seçim olarak üstte.'),
              style: TextStyle(color: muted)),
          const AdSlot.card(AdPage.compare, padding: EdgeInsets.only(top: 12)),
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
          else
            ..._analysis(context, branches, sameShape),
        ]),
      ),
    );
  }

  List<Widget> _analysis(BuildContext context, List<_Branch> bs, bool sameShape) {
    final store = StoreScope.of(context);
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    final rows = [for (final b in bs) b.row];
    String p(double v) => L10n.percent(v.round());
    final all = Dist.of([for (final b in bs) ...b.rep.standings.map((s) => s.pct)]);
    final allPass = all.n == 0
        ? 0.0
        : bs.fold<int>(0, (a, b) => a + b.rep.results.where((r) => r.score >= b.row.exam.rule.pass).length) / all.n;
    final byMean = [...bs]..sort((a, b) => b.mean.compareTo(a.mean));
    final best = byMean.first, last = byMean.last;
    final steady = bs.reduce((a, b) => a.dist.std <= b.dist.std ? a : b);
    final topPass = bs.reduce((a, b) => a.passRate >= b.passRate ? a : b);
    final gap = best.mean - last.mean;
    final registered = bs.fold<int>(0, (a, b) => a + b.registered);
    final inkBar = t.brightness == Brightness.dark ? const Color(0xFF6C7BB5) : NColors.ink;
    final isPro = store.isPro;

    Widget nameCell(String s, {double width = 76}) => SizedBox(
          width: width,
          child: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
        );
    Widget valueCell(String s, {double width = 54, Color? color}) => SizedBox(
          width: width,
          child: Text(s,
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w800, fontFeatures: tabular, color: color)),
        );
    Widget card(Widget child, {EdgeInsets padding = const EdgeInsets.all(16)}) =>
        Card(child: Padding(padding: padding, child: child));

    // Sınıfı diğer tüm sınıflarla karşılaştıran yorumlar.
    final comments = <String>[
      tr('En başarılı sınıf {0} ({1}); en düşük ortalama {2} ({3}). Aradaki fark {4} puan.',
          [best.name, p(best.mean), last.name, p(last.mean), gap.round()]),
      for (final b in bs)
        () {
          final rest = Dist.of([for (final o in bs) if (!identical(o, b)) ...o.rep.standings.map((s) => s.pct)]);
          final d = cohenD(b.dist, rest);
          final diff = b.mean - all.mean;
          return diff >= 0
              ? tr('{0}: genel ortalamanın {1} puan üstünde ({2}).', [b.name, diff.abs().toStringAsFixed(1).replaceAll('.', L10n.decimal), effectLabel(d)])
              : tr('{0}: genel ortalamanın {1} puan altında ({2}).', [b.name, diff.abs().toStringAsFixed(1).replaceAll('.', L10n.decimal), effectLabel(d)]);
        }(),
      if (steady.dist.std > 0)
        tr('Puanları en dengeli dağılan sınıf {0} (std. {1}); öğrenciler arasında düzey farkı en az orada.',
            [steady.name, steady.dist.std.round()]),
    ];

    // Şubeler arasında doğru oranı en çok ayrışan sorular.
    final spread = <(int q, double lo, double hi)>[];
    if (sameShape) {
      for (var q = 0; q < bs.first.rep.items.length; q++) {
        if (bs.first.row.exam.questions[q].cancelled) continue;
        final ps = [for (final b in bs) b.rep.items[q].p];
        spread.add((q + 1, ps.reduce(math.min), ps.reduce(math.max)));
      }
      spread.sort((a, b) => (b.$3 - b.$2).compareTo(a.$3 - a.$2));
    }

    // Tüm şubeler birlikte genel sıralama.
    final ranking = [
      for (final b in bs)
        for (final s in b.rep.standings) (b, s),
    ]..sort((a, b) => b.$2.pct.compareTo(a.$2.pct));

    return [
      SectionTitle(tr('Öne çıkanlar')),
      GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 240, mainAxisExtent: 134, crossAxisSpacing: 12, mainAxisSpacing: 12),
        children: [
          StatCard(label: tr('En başarılı'), value: best.name, hint: tr('Ortalama {0}', [p(best.mean)]), icon: Icons.emoji_events_outlined),
          StatCard(
              label: tr('Genel ortalama'),
              value: p(all.mean),
              hint: tr('{0} öğrenci · {1} sınıf', [all.n, bs.length]),
              icon: Icons.functions,
              accent: const Color(0xFF6C7FD8)),
          StatCard(
              label: tr('En yüksek geçme'),
              value: topPass.name,
              hint: tr('Geçme oranı {0}', [p(topPass.passRate * 100)]),
              icon: Icons.verified_outlined),
          StatCard(
              label: tr('En dengeli'),
              value: steady.name,
              hint: tr('Std. sapma {0}', [fmt1(steady.dist.std)]),
              icon: Icons.balance_outlined,
              accent: const Color(0xFF14B8A6)),
          StatCard(
              label: tr('Sınıflar arası fark'),
              value: fmt1(gap),
              hint: tr('En yüksek − en düşük ortalama'),
              icon: Icons.swap_vert_rounded,
              accent: gap >= 15 ? NColors.coral : NColors.amber),
          StatCard(
              label: tr('Genel geçme oranı'),
              value: p(allPass * 100),
              hint: registered == 0 ? tr('Tüm sınıflar birlikte') : tr('Katılım {0}', [p(math.min(1, all.n / registered) * 100)]),
              icon: Icons.groups_2_outlined,
              accent: NColors.emerald),
        ],
      ),
      SectionTitle(tr('Otomatik değerlendirme')),
      card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final c in comments)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.only(top: 2, right: 10),
                child: Icon(Icons.auto_awesome, size: 16, color: NColors.emerald),
              ),
              Expanded(child: Text(c)),
            ]),
          ),
      ])),
      SectionTitle(tr('Ortalama başarı (%)')),
      card(Column(children: [
        for (final b in byMean)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              nameCell(b.name),
              Expanded(
                child: LayoutBuilder(builder: (context, c) {
                  return Stack(clipBehavior: Clip.none, children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: b.mean / 100,
                        minHeight: 14,
                        color: identical(b, best) ? NColors.emerald : inkBar,
                        backgroundColor: t.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                    // Genel ortalama çizgisi
                    PositionedDirectional(
                      start: (c.maxWidth * all.mean / 100).clamp(0, c.maxWidth - 2),
                      top: -3,
                      child: Container(width: 2, height: 20, color: NColors.amber),
                    ),
                  ]);
                }),
              ),
              valueCell(p(b.mean)),
            ]),
          ),
        const SizedBox(height: 6),
        ChartLegend([(tr('En başarılı'), NColors.emerald), (tr('Diğer sınıflar'), inkBar), (tr('Genel ortalama'), NColors.amber)]),
      ])),
      SectionTitle(tr('Genel ortalamaya göre fark')),
      card(Column(children: [
        for (final b in byMean)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              nameCell(b.name),
              Expanded(
                child: LayoutBuilder(builder: (context, c) {
                  final maxAbs = math.max(5.0, bs.map((x) => (x.mean - all.mean).abs()).reduce(math.max));
                  final diff = b.mean - all.mean;
                  final half = c.maxWidth / 2;
                  final w = half * diff.abs() / maxAbs;
                  return SizedBox(
                    height: 16,
                    child: Stack(children: [
                      Positioned(left: half - 0.5, top: 0, bottom: 0, child: Container(width: 1, color: t.colorScheme.outline)),
                      Positioned(
                        left: diff >= 0 ? half : half - w,
                        top: 2,
                        bottom: 2,
                        child: Container(
                          width: math.max(2, w),
                          decoration: BoxDecoration(
                            color: diff >= 0 ? NColors.emerald : NColors.coral,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ]),
                  );
                }),
              ),
              valueCell('${b.mean - all.mean >= 0 ? '+' : '−'}${fmt1((b.mean - all.mean).abs())}',
                  color: b.mean >= all.mean ? NColors.emerald : NColors.coral),
            ]),
          ),
        const SizedBox(height: 4),
        Text(tr('Sağa uzanan çubuk genel ortalamanın üstünü, sola uzanan altını gösterir.'),
            style: t.textTheme.bodySmall?.copyWith(color: muted)),
      ])),
      SectionTitle(tr('Geçme ve katılım')),
      card(Column(children: [
        for (final b in bs)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              nameCell(b.name),
              Expanded(
                child: Column(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                        value: b.passRate,
                        minHeight: 9,
                        color: NColors.emerald,
                        backgroundColor: t.colorScheme.surfaceContainerHighest),
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                        value: b.participation ?? 0,
                        minHeight: 9,
                        color: const Color(0xFF6C7FD8),
                        backgroundColor: t.colorScheme.surfaceContainerHighest),
                  ),
                ]),
              ),
              SizedBox(
                width: 64,
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(p(b.passRate * 100), style: const TextStyle(fontWeight: FontWeight.w800, fontFeatures: tabular, fontSize: 12)),
                  Text(b.participation == null ? '${b.rep.results.length}' : '${b.rep.results.length}/${b.registered}',
                      style: TextStyle(fontFeatures: tabular, fontSize: 12, color: muted)),
                ]),
              ),
            ]),
          ),
        const SizedBox(height: 6),
        ChartLegend([(tr('Geçme oranı'), NColors.emerald), (tr('Katılım (okunan / kayıtlı)'), const Color(0xFF6C7FD8))]),
      ])),
      if (!isPro) ...[
        SectionTitle(tr('Yayılım, düzeyler ve soru farkları')),
        const ProLocked(ProFeature.detailedStats),
      ] else ...[
        SectionTitle(tr('Puanların yayılımı (%)')),
        card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final b in bs) ...[
            Text(b.name, style: const TextStyle(fontWeight: FontWeight.w800)),
            BoxPlot(
                min: b.dist.min,
                q1: b.dist.q1,
                median: b.dist.median,
                q3: b.dist.q3,
                max: b.dist.max,
                mean: b.dist.mean,
                scaleMax: 100),
            if (!identical(b, bs.last)) const Divider(height: 22),
          ],
        ])),
        SectionTitle(tr('Başarı düzeyleri')),
        card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final b in bs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                nameCell(b.name),
                Expanded(
                  child: StackedBar(parts: [
                    for (var i = 0; i < b.rep.levelCounts.length; i++)
                      (b.rep.levelCounts[i].toDouble(), levelPalette[i % levelPalette.length])
                  ]),
                ),
              ]),
            ),
          const SizedBox(height: 8),
          ChartLegend([
            for (var i = 0; i < Level.all.length; i++) (Level.all[i].name, levelPalette[i % levelPalette.length])
          ]),
          const SizedBox(height: 4),
          Text(tr('Çubuktaki sayılar sınıfın yüzde kaçının o düzeyde olduğunu gösterir.'),
              style: t.textTheme.bodySmall?.copyWith(color: muted)),
        ])),
        SectionTitle(tr('Doğru · yanlış · boş dağılımı')),
        card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final b in bs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                nameCell(b.name),
                Expanded(
                  child: StackedBar(parts: [
                    (b.rep.meanCorrect, NColors.emerald),
                    (b.rep.meanWrong, NColors.coral),
                    (b.rep.meanBlank, NColors.gray),
                  ]),
                ),
                valueCell(fmt1(b.rep.meanNet), width: 50),
              ]),
            ),
          const SizedBox(height: 8),
          ChartLegend([(tr('Doğru'), NColors.emerald), (tr('Yanlış'), NColors.coral), (tr('Boş'), NColors.gray)]),
          const SizedBox(height: 4),
          Text(tr('Sağdaki sayı öğrenci başına ortalama net.'), style: t.textTheme.bodySmall?.copyWith(color: muted)),
        ])),
        if (spread.isNotEmpty) ...[
          SectionTitle(tr('Sınıflar arasında en çok ayrışan sorular')),
          card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final (q, lo, hi) in spread.take(6))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                        child: Text(tr('{0}. soru', [q]), style: const TextStyle(fontWeight: FontWeight.w700))),
                    Text(tr('fark {0} puan', [((hi - lo) * 100).round()]),
                        style: const TextStyle(fontWeight: FontWeight.w700, color: NColors.coral, fontSize: 12)),
                  ]),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final b in bs)
                      _Pill('${b.name} ${p(b.rep.items[q - 1].p * 100)}', _rateColor(b.rep.items[q - 1].p)),
                  ]),
                ]),
              ),
            Text(tr('Bir sınıfta iyi, diğerinde zayıf yapılan sorular, o konunun sınıflarda farklı işlendiğine işaret edebilir.'),
                style: t.textTheme.bodySmall?.copyWith(color: muted)),
          ])),
        ],
        SectionTitle(tr('Sınıf birincileri')),
        card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final b in bs) ...[
            Text(b.name, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            for (final (i, s) in b.rep.standings.take(3).indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Text(['🥇', '🥈', '🥉'][i]),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(store.studentById[s.result.sheet.studentId]?.fullName ?? tr('Eşleşmeyen kâğıt'),
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Text(p(s.pct), style: const TextStyle(fontWeight: FontWeight.w800, fontFeatures: tabular)),
                ]),
              ),
            if (!identical(b, bs.last)) const Divider(height: 18),
          ],
        ])),
        SectionTitle(tr('Genel sıralama (tüm sınıflar)')),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (final (i, (b, s)) in ranking.take(10).indexed)
              ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: i < 3 ? NColors.emerald : t.colorScheme.surfaceContainerHighest,
                  child: Text('${i + 1}',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800, color: i < 3 ? Colors.white : t.colorScheme.onSurface)),
                ),
                title: Text(store.studentById[s.result.sheet.studentId]?.fullName ?? tr('Eşleşmeyen kâğıt'),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(b.name),
                trailing: Text(p(s.pct), style: const TextStyle(fontWeight: FontWeight.w800, fontFeatures: tabular)),
              ),
          ]),
        ),
      ],
      SectionTitle(tr('Özet tablo')),
      Card(
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 20,
            columns: [
              DataColumn(label: Text(tr('Şube'))),
              DataColumn(label: Text(tr('Kişi')), numeric: true),
              DataColumn(label: Text(tr('Ort.')), numeric: true),
              DataColumn(label: Text(tr('Medyan')), numeric: true),
              DataColumn(label: Text(tr('Std.')), numeric: true),
              DataColumn(label: Text(tr('Başarı')), numeric: true),
              DataColumn(label: Text(tr('En yüksek')), numeric: true),
              DataColumn(label: Text(tr('En düşük')), numeric: true),
              DataColumn(label: Text(tr('Ort. net')), numeric: true),
              DataColumn(label: Text(tr('Katılım')), numeric: true),
              const DataColumn(label: Text('KR-20'), numeric: true),
            ],
            rows: [
              for (final r in rows)
                DataRow(cells: [
                  DataCell(Text(r.exam.className, style: const TextStyle(fontWeight: FontWeight.w700))),
                  DataCell(Text('${r.report.stats.count}')),
                  DataCell(Text(fmt1(r.report.stats.mean))),
                  DataCell(Text(fmt1(r.report.stats.median))),
                  DataCell(Text(fmt1(r.report.stats.stdDev))),
                  DataCell(Text(L10n.percent((r.report.passRate * 100).round()))),
                  DataCell(Text(fmt1(r.report.stats.max))),
                  DataCell(Text(fmt1(r.report.stats.min))),
                  DataCell(Text(fmt2(r.report.meanNet))),
                  DataCell(Text(() {
                    final b = bs.firstWhere((b) => identical(b.row, r));
                    return b.participation == null ? '–' : p(b.participation! * 100);
                  }())),
                  DataCell(Text(r.report.stats.kr20 == null ? '–' : fmt2(r.report.stats.kr20!))),
                ]),
              DataRow(color: WidgetStatePropertyAll(t.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)), cells: [
                DataCell(Text(tr('Tümü'), style: const TextStyle(fontWeight: FontWeight.w800))),
                DataCell(Text('${all.n}')),
                DataCell(Text(p(all.mean))),
                DataCell(Text(p(all.median))),
                DataCell(Text(fmt1(all.std))),
                DataCell(Text(p(allPass * 100))),
                DataCell(Text(p(all.max))),
                DataCell(Text(p(all.min))),
                const DataCell(Text('–')),
                DataCell(Text(registered == 0 ? '–' : p(math.min(1, all.n / registered) * 100))),
                const DataCell(Text('–')),
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
                  for (final it in r.report.items) _HeatCell(it.p),
                ]),
            ]),
          ),
        ),
      ],
      if (rows.any((r) => r.report.outcomes.isNotEmpty)) ...[
        SectionTitle(tr('Kazanım başarısı')),
        Card(
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const SizedBox(width: 150),
                for (final r in rows)
                  SizedBox(
                      width: 56,
                      child: Text(r.exam.className,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700))),
              ]),
              for (final code in {for (final r in rows) ...r.report.outcomes.map((o) => o.code)})
                Row(children: [
                  SizedBox(
                      width: 150,
                      child: Text(code,
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                  for (final r in rows)
                    () {
                      final o = r.report.outcomes.where((o) => o.code == code).firstOrNull;
                      return o == null
                          ? const SizedBox(width: 56, child: Text('–', textAlign: TextAlign.center))
                          : _HeatCell(o.rate, width: 54);
                    }(),
                ]),
            ]),
          ),
        ),
      ],
    ];
  }
}

Color _rateColor(double p) => p > 0.8
    ? NColors.emerald
    : p >= 0.5
        ? NColors.amber
        : NColors.coral;

class _HeatCell extends StatelessWidget {
  final double p;
  final double width;
  const _HeatCell(this.p, {this.width = 38});

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: 28,
        margin: const EdgeInsets.all(1),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: (p > 0.8
                  ? NColors.emerald
                  : p >= 0.3
                      ? NColors.amber
                      : NColors.coral)
              .withValues(alpha: 0.22),
        ),
        child: Text('${(p * 100).round()}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFeatures: tabular)),
      );
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFeatures: tabular)),
      );
}
