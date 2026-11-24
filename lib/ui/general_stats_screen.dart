import 'package:material_ui/material_ui.dart';

import '../core/ads.dart';
import '../core/overview.dart';
import '../core/pro.dart';
import '../core/report.dart';
import '../l10n/l10n.dart';
import '../main.dart';
import '../reports/pdf_documents.dart';
import 'ad_slot.dart';
import 'charts.dart';
import 'illustrations.dart';
import 'pro_screen.dart';
import 'report_preview_screen.dart';
import 'student_detail_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Tüm sınıflar ve sınava giren tüm öğrenciler için genel istatistik.
/// Veriler yalnızca bu cihazdaki sınavlardan hesaplanır.
class GeneralStatsScreen extends StatefulWidget {
  const GeneralStatsScreen({super.key});

  @override
  State<GeneralStatsScreen> createState() => _GeneralStatsScreenState();
}

class _GeneralStatsScreenState extends State<GeneralStatsScreen> {
  OverviewPeriod _period = OverviewPeriod.all;
  final Set<String> _classes = {};

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    final ov = Overview.build(store, classes: _classes, period: _period);
    final classNames = {
      ...store.classNames,
      for (final e in store.exams) if (e.className.trim().isNotEmpty) e.className,
    }.toList()
      ..sort();

    Future<void> pdf() async {
      if (ov.isEmpty) return toast(context, tr('Rapor için önce kâğıt okutun.'));
      await ReportPreviewScreen.open(context,
          title: tr('Genel istatistik'),
          fileName: 'genel_istatistik.pdf',
          build: () => buildOverviewPdf(ov, school: store.reportSchool, filter: _filterText(classNames.length)));
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr('Genel istatistik')), actions: [
        IconButton(tooltip: tr('PDF rapor'), onPressed: pdf, icon: const Icon(Icons.picture_as_pdf_outlined)),
      ]),
      bottomNavigationBar: const AdBannerBar(AdPage.compare),
      body: Watermark(
        child: ListView(padding: EdgeInsets.fromLTRB(20, 8, 20, 40 + MediaQuery.paddingOf(context).bottom), children: [
          Text(tr('Tüm sınıfların ve sınava giren tüm öğrencilerin sonuçları bir arada. Dönem ve sınıf seçerek daraltabilirsiniz.'),
              style: TextStyle(color: muted)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in OverviewPeriod.values)
              ChoiceChip(
                label: Text(p.label),
                selected: _period == p,
                onSelected: (_) => setState(() => _period = p),
              ),
          ]),
          if (classNames.length > 1) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilterChip(
                label: Text(tr('Tüm sınıflar')),
                selected: _classes.isEmpty,
                onSelected: (_) => setState(_classes.clear),
              ),
              for (final c in classNames)
                FilterChip(
                  label: Text(c),
                  selected: _classes.contains(c),
                  onSelected: (v) => setState(() => v ? _classes.add(c) : _classes.remove(c)),
                ),
            ]),
          ],
          if (ov.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Card(
                child: EmptyState(
                  kind: IllustrationKind.results,
                  title: tr('Henüz istatistik yok'),
                  message: tr('Seçtiğiniz dönemde ve sınıflarda okunmuş kâğıt bulunmuyor. Kâğıt okuttukça genel istatistik burada kendiliğinden oluşur.'),
                ),
              ),
            )
          else
            ..._content(context, ov),
        ]),
      ),
    );
  }

  String _filterText(int classCount) => [
        _period.label,
        _classes.isEmpty ? tr('Tüm sınıflar') : (_classes.toList()..sort()).join(', '),
      ].join(' · ');

  List<Widget> _content(BuildContext context, Overview ov) {
    final store = StoreScope.of(context);
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    String p(double v) => L10n.percent(v.round());
    final isPro = store.isPro;
    final d = ov.dist;
    final classColor = {
      for (final (i, c) in ov.classes.indexed) c.name: seriesColors[i % seriesColors.length],
    };
    Widget card(Widget child, {EdgeInsets padding = const EdgeInsets.all(16)}) =>
        Card(child: Padding(padding: padding, child: child));
    Widget nameCell(String s, {double width = 76}) => SizedBox(
          width: width,
          child: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
        );
    void openStudent(StudentSummary s) => Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => StudentDetailScreen(studentId: s.student.id)));

    Widget studentList(List<StudentSummary> list, String Function(StudentSummary) value, {Color? color, String Function(StudentSummary)? sub}) =>
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (final (i, s) in list.indexed)
              ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: (color ?? NColors.emerald).withValues(alpha: i < 3 ? 1 : 0.18),
                  child: Text('${i + 1}',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800, color: i < 3 ? Colors.white : t.colorScheme.onSurface)),
                ),
                title: Text(s.student.fullName, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(sub?.call(s) ?? '${s.student.className} · ${tr('{0} sınav', [s.count])}'),
                trailing: Text(value(s),
                    style: TextStyle(fontWeight: FontWeight.w800, fontFeatures: tabular, color: color)),
                onTap: () => openStudent(s),
              ),
          ]),
        );

    final stats = [
      StatCard(label: tr('Medyan'), value: p(d.median), hint: tr('Öğrencilerin yarısı bunun üstünde'), icon: Icons.align_vertical_center),
      StatCard(
          label: tr('Std. sapma'),
          value: fmt1(d.std),
          hint: d.std >= 20 ? tr('Puanlar dağınık') : (d.std <= 10 ? tr('Puanlar birbirine yakın') : tr('Olağan yayılım')),
          icon: Icons.stacked_line_chart,
          accent: const Color(0xFF6C7FD8)),
      StatCard(label: tr('En yüksek'), value: p(d.max), hint: tr('En düşük {0}', [p(d.min)]), icon: Icons.trending_up),
      StatCard(
          label: tr('Çeyrekler'),
          value: '${d.q1.round()}–${d.q3.round()}',
          hint: tr('Ortadaki yarı'),
          icon: Icons.width_normal_outlined,
          accent: const Color(0xFF14B8A6)),
      StatCard(
          label: tr('Katılım'),
          value: ov.participation == null ? '–' : p(ov.participation! * 100),
          hint: tr('{0} / {1} kayıtlı öğrenci', [ov.participants, ov.registered]),
          icon: Icons.how_to_reg_outlined,
          accent: const Color(0xFF6C7FD8)),
      StatCard(
          label: tr('Doğru oranı'),
          value: p(ov.correctRate * 100),
          hint: tr('Yanlış {0} · boş {1}', [p(ov.wrongRate * 100), p(ov.blankRate * 100)]),
          icon: Icons.check_circle_outline),
      StatCard(
          label: tr('Her sınavı geçen'),
          value: '${ov.alwaysPassed}',
          hint: tr('En az iki sınava girenler'),
          icon: Icons.workspace_premium_outlined),
      StatCard(
          label: tr('Hiç geçemeyen'),
          value: '${ov.neverPassed}',
          hint: tr('En az iki sınava girenler'),
          icon: Icons.support_outlined,
          accent: ov.neverPassed > 0 ? NColors.coral : NColors.emerald),
      if (ov.timeline.length >= 2) ...[
        StatCard(
            label: tr('En yüksek ortalamalı sınav'),
            value: p(ov.easiest!.mean),
            hint: '${ov.easiest!.exam.name} · ${ov.easiest!.exam.className}',
            icon: Icons.sentiment_satisfied_alt_outlined),
        StatCard(
            label: tr('En düşük ortalamalı sınav'),
            value: p(ov.hardest!.mean),
            hint: '${ov.hardest!.exam.name} · ${ov.hardest!.exam.className}',
            icon: Icons.sentiment_dissatisfied_outlined,
            accent: NColors.coral),
      ],
    ];

    final trend = ov.trend;
    return [
      const AdSlot.card(AdPage.compare, padding: EdgeInsets.only(top: 14)),
      const SizedBox(height: 14),
      HeroPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('GENEL BAŞARI'),
              style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(p(d.mean),
                style: const TextStyle(
                    color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800, fontFeatures: tabular, height: 1)),
            const SizedBox(width: 10),
            if (trend != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('${trend >= 0 ? '▲' : '▼'} ${fmt1(trend.abs())}',
                    style: TextStyle(
                        color: trend >= 0 ? const Color(0xFF7BE0B4) : const Color(0xFFFF9C7A),
                        fontWeight: FontWeight.w800,
                        fontFeatures: tabular)),
              ),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 22, runSpacing: 12, children: [
            _HeroMini(tr('Sınav'), '${ov.exams.length}'),
            _HeroMini(tr('Kâğıt'), '${ov.sheets}'),
            _HeroMini(tr('Öğrenci'), '${ov.participants}'),
            _HeroMini(tr('Sınıf'), '${ov.classes.length}'),
            _HeroMini(tr('Geçme'), p(ov.passRate * 100)),
          ]),
        ]),
      ),
      SectionTitle(tr('Genel istatistikler')),
      GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 240, mainAxisExtent: 134, crossAxisSpacing: 12, mainAxisSpacing: 12),
        children: stats,
      ),
      SectionTitle(tr('Otomatik değerlendirme')),
      card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final c in ov.comments)
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
        Text(tr('Bu değerlendirme cihazınızda, sonuçlarınızdan üretildi; hiçbir veri dışarı gönderilmedi.'),
            style: t.textTheme.bodySmall?.copyWith(color: muted)),
      ])),
      SectionTitle(tr('Sınıf sıralaması')),
      card(Column(children: [
        for (final (i, c) in ov.classes.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              SizedBox(
                width: 24,
                child: Text('${i + 1}.', style: TextStyle(color: muted, fontWeight: FontWeight.w700, fontFeatures: tabular)),
              ),
              nameCell(c.name, width: 70),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: c.dist.mean / 100,
                    minHeight: 14,
                    color: classColor[c.name],
                    backgroundColor: t.colorScheme.surfaceContainerHighest,
                  ),
                ),
              ),
              SizedBox(
                width: 50,
                child: Text(p(c.dist.mean),
                    textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800, fontFeatures: tabular)),
              ),
              SizedBox(
                width: 46,
                child: c.trend == null
                    ? const SizedBox()
                    : Text('${c.trend! >= 0 ? '▲' : '▼'}${c.trend!.abs().round()}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: c.trend! >= 0 ? NColors.emerald : NColors.coral)),
              ),
            ]),
          ),
        const SizedBox(height: 4),
        Text(tr('Ok: sınıfın ilk sınavından son sınavına ortalama değişimi.'),
            style: t.textTheme.bodySmall?.copyWith(color: muted)),
      ])),
      SectionTitle(tr('Sınıf özet tablosu')),
      Card(
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 20,
            columns: [
              DataColumn(label: Text(tr('Sınıf'))),
              DataColumn(label: Text(tr('Sınav')), numeric: true),
              DataColumn(label: Text(tr('Kâğıt')), numeric: true),
              DataColumn(label: Text(tr('Ort.')), numeric: true),
              DataColumn(label: Text(tr('Medyan')), numeric: true),
              DataColumn(label: Text(tr('Std.')), numeric: true),
              DataColumn(label: Text(tr('Başarı')), numeric: true),
              DataColumn(label: Text(tr('Katılım')), numeric: true),
              DataColumn(label: Text(tr('Sınıf birincisi'))),
            ],
            rows: [
              for (final c in ov.classes)
                DataRow(cells: [
                  DataCell(Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                  DataCell(Text('${c.examCount}')),
                  DataCell(Text('${c.sheets}')),
                  DataCell(Text(p(c.dist.mean))),
                  DataCell(Text(p(c.dist.median))),
                  DataCell(Text(fmt1(c.dist.std))),
                  DataCell(Text(p(c.passRate * 100))),
                  DataCell(Text(c.participation == null ? '–' : p(c.participation! * 100))),
                  DataCell(Text(c.best == null ? '–' : '${c.best!.student.fullName} (${p(c.best!.average)})')),
                ]),
            ],
          ),
        ),
      ),
      SectionTitle(tr('Başarı düzeyleri')),
      card(Column(children: [
        DonutChart(pie: true, centerLabel: tr('kâğıt'), unit: tr(' kâğıt'), slices: [
          for (var i = 0; i < Level.all.length; i++)
            Slice(Level.all[i].name, ov.levelCounts[i].toDouble(), levelPalette[i % levelPalette.length],
                detail: tr('{0}: tam puanın %{1} ve üzeri', [Level.all[i].name, Level.all[i].minPct.round()])),
        ]),
      ])),
      if (!isPro) ...[
        SectionTitle(tr('Ayrıntılı grafikler ve öğrenci sıralamaları')),
        const ProLocked(ProFeature.detailedStats),
      ] else ...[
        SectionTitle(tr('Puan dağılımı (%)')),
        card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ColumnChart(
            values: [for (final v in ov.histogram10) v.toDouble()],
            labels: [for (var i = 0; i < 10; i++) '${i * 10}'],
            colors: [
              for (var i = 0; i < 10; i++)
                i >= 8
                    ? NColors.emerald
                    : i >= 5
                        ? const Color(0xFF6C7FD8)
                        : i >= 3
                            ? NColors.amber
                            : NColors.coral
            ],
          ),
          const SizedBox(height: 6),
          Text(tr('Her sütun 10 puanlık dilimdeki kâğıt sayısı (ör. 70: 70–79 arası).'),
              style: t.textTheme.bodySmall?.copyWith(color: muted)),
        ])),
        SectionTitle(tr('Puanların yayılımı (%)')),
        card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Tüm öğrenciler'), style: const TextStyle(fontWeight: FontWeight.w800)),
          BoxPlot(min: d.min, q1: d.q1, median: d.median, q3: d.q3, max: d.max, mean: d.mean, scaleMax: 100),
          for (final c in ov.classes.take(8)) ...[
            const Divider(height: 22),
            Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800)),
            BoxPlot(
                min: c.dist.min,
                q1: c.dist.q1,
                median: c.dist.median,
                q3: c.dist.q3,
                max: c.dist.max,
                mean: c.dist.mean,
                scaleMax: 100),
          ],
        ])),
        if (ov.timeline.length >= 2) ...[
          SectionTitle(tr('Sınavdan sınava genel ortalama')),
          card(LineSeriesChart(
            series: [(tr('Genel ortalama'), NColors.emerald, [for (final x in ov.timeline) x.mean])],
            xLabels: [for (final x in ov.timeline) '${x.exam.date.day}.${x.exam.date.month}'],
            target: 50,
          )),
        ],
        if (ov.monthly.length >= 2 && ov.classes.length >= 2) ...[
          SectionTitle(tr('Aylara göre sınıf ortalamaları')),
          card(() {
            final months = [for (final m in ov.monthly) m.$1];
            return LineSeriesChart(
              xLabels: [for (final m in months) _ym(m)],
              series: [
                for (final c in ov.classes.take(6))
                  (
                    c.name,
                    classColor[c.name]!,
                    [
                      for (final m in months)
                        () {
                          final xs = ov.entries
                              .where((x) => x.className == c.name && x.exam.date.year == m.year && x.exam.date.month == m.month)
                              .map((x) => x.pct)
                              .toList();
                          return xs.isEmpty ? null : xs.reduce((a, b) => a + b) / xs.length;
                        }()
                    ]
                  ),
              ],
            );
          }()),
        ],
        if (ov.monthly.length >= 2) ...[
          SectionTitle(tr('Aylık ortalama ve kâğıt sayısı')),
          card(ColumnChart(
            values: [for (final m in ov.monthly) m.$2],
            labels: [for (final m in ov.monthly) '${_ym(m.$1)} (${m.$3})'],
            format: (v) => p(v),
            colors: const [Color(0xFF6C7FD8)],
          )),
        ],
        SectionTitle(tr('Sınıflara göre doğru · yanlış · boş')),
        card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final c in ov.classes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                nameCell(c.name),
                Expanded(
                  child: StackedBar(parts: [
                    (c.correctRate, NColors.emerald),
                    (c.wrongRate, NColors.coral),
                    (c.blankRate, NColors.gray),
                  ]),
                ),
              ]),
            ),
          const SizedBox(height: 8),
          ChartLegend([(tr('Doğru'), NColors.emerald), (tr('Yanlış'), NColors.coral), (tr('Boş'), NColors.gray)]),
        ])),
        SectionTitle(tr('Sınıflara göre başarı düzeyleri')),
        card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final c in ov.classes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                nameCell(c.name),
                Expanded(
                  child: StackedBar(parts: [
                    for (var i = 0; i < c.levelCounts.length; i++)
                      (c.levelCounts[i].toDouble(), levelPalette[i % levelPalette.length])
                  ]),
                ),
              ]),
            ),
          const SizedBox(height: 8),
          ChartLegend([
            for (var i = 0; i < Level.all.length; i++) (Level.all[i].name, levelPalette[i % levelPalette.length])
          ]),
        ])),
        if (ov.students.isNotEmpty) ...[
          SectionTitle(tr('En başarılı öğrenciler')),
          studentList(ov.top.take(10).toList(), (s) => p(s.average)),
        ],
        if (ov.improved.isNotEmpty) ...[
          SectionTitle(tr('En çok gelişenler')),
          studentList(ov.improved.take(5).toList(), (s) => '▲ ${s.change.round()}',
              sub: (s) => '${s.student.className} · ${p(s.first)} → ${p(s.last)}'),
        ],
        if (ov.declined.isNotEmpty) ...[
          SectionTitle(tr('Düşüş gösterenler')),
          studentList(ov.declined.take(5).toList(), (s) => '▼ ${(-s.change).round()}',
              color: NColors.coral, sub: (s) => '${s.student.className} · ${p(s.first)} → ${p(s.last)}'),
        ],
        if (ov.steady.isNotEmpty) ...[
          SectionTitle(tr('En istikrarlı öğrenciler')),
          studentList(ov.steady.take(5).toList(), (s) => p(s.average),
              color: const Color(0xFF14B8A6),
              sub: (s) => '${s.student.className} · ${tr('{0} sınav', [s.count])} · ${tr('std. {0}', [fmt1(s.dist.std)])}'),
        ],
        if (ov.students.length >= 4) ...[
          SectionTitle(tr('Desteğe ihtiyaç duyabilecek öğrenciler')),
          studentList(ov.support.take(5).toList(), (s) => p(s.average), color: NColors.coral),
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(tr('Yalnızca size gösterilen bir hatırlatmadır.'), style: t.textTheme.bodySmall?.copyWith(color: muted)),
          ),
        ],
        if (ov.outcomes.isNotEmpty) ...[
          SectionTitle(tr('Kazanımlar: en zayıf ve en güçlü')),
          card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final o in _weakStrong(ov.outcomes))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                        child: Text(o.code,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                    Text('${p(o.rate * 100)} · ${tr('{0} sınav', [o.exams])}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: tabular, fontSize: 12)),
                  ]),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: o.rate,
                      minHeight: 8,
                      color: o.rate >= 0.7
                          ? NColors.emerald
                          : o.rate >= 0.5
                              ? NColors.amber
                              : NColors.coral,
                      backgroundColor: t.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ]),
              ),
          ])),
        ],
      ],
      SectionTitle(tr('Sınavlar')),
      Card(
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 20,
            columns: [
              DataColumn(label: Text(tr('Tarih'))),
              DataColumn(label: Text(tr('Sınav'))),
              DataColumn(label: Text(tr('Sınıf'))),
              DataColumn(label: Text(tr('Kişi')), numeric: true),
              DataColumn(label: Text(tr('Ort.')), numeric: true),
              DataColumn(label: Text(tr('Başarı')), numeric: true),
            ],
            rows: [
              for (final x in ov.timeline.reversed)
                DataRow(cells: [
                  DataCell(Text(L10n.date(x.exam.date))),
                  DataCell(Text(x.exam.name)),
                  DataCell(Text(x.exam.className)),
                  DataCell(Text('${x.n}')),
                  DataCell(Text(p(x.mean))),
                  DataCell(Text(p(x.passRate * 100))),
                ]),
            ],
          ),
        ),
      ),
      if (ov.unmatched > 0)
        Padding(
          padding: const EdgeInsets.only(top: 10, left: 4),
          child: Text(tr('{0} kâğıt bir öğrenciyle eşleşmediği için öğrenci listelerine katılmadı (genel ortalamaya katıldı).', [ov.unmatched]),
              style: t.textTheme.bodySmall?.copyWith(color: NColors.amber)),
        ),
    ];
  }

  /// En zayıf 5 ve (ayrı ise) en güçlü 5 kazanım.
  static List<OutcomeOverview> _weakStrong(List<OutcomeOverview> sorted) {
    if (sorted.length <= 10) return sorted;
    return [...sorted.take(5), ...sorted.skip(sorted.length - 5)];
  }
}

class _HeroMini extends StatelessWidget {
  final String label, value;
  const _HeroMini(this.label, this.value);
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, fontFeatures: tabular)),
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
      ]);
}

/// Ay etiketi (ör. 11/26); her dilde sayısal.
String _ym(DateTime m) => '${m.month.toString().padLeft(2, '0')}/${(m.year % 100).toString().padLeft(2, '0')}';
