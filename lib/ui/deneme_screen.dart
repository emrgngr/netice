// Çok dersli deneme sınavı sonuçları: ders ortalamaları, ders başarı
// sıralaması ve öğrenci sıralaması (ders ders D/Y/N, toplam net, puan).
import '../reports/report_docx.dart';
import 'package:material_ui/material_ui.dart';

import '../core/deneme.dart';
import '../l10n/l10n.dart';
import '../main.dart';
import '../reports/pdf_documents.dart';
import 'report_preview_screen.dart';
import 'sections_screen.dart';
import 'student_detail_screen.dart';
import 'theme.dart';
import 'widgets.dart';

String _f(double v) => v.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '').replaceAll('.', L10n.decimal);

class DenemeScreen extends StatelessWidget {
  final String examId;
  const DenemeScreen({super.key, required this.examId});

  static Future<void> open(BuildContext context, String examId) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => DenemeScreen(examId: examId)));

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final exam = store.examById(examId);
    if (exam == null) return const Scaffold();
    final results = store.resultsOf(exam);
    final rep = DenemeReport.build(exam, results);
    final students = store.studentById;
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final muted = t.colorScheme.onSurfaceVariant;
    final good = dark ? NColors.emerald : NColors.deepEmerald;

    Color tone(double p) => p >= 70 ? good : (p >= 40 ? (dark ? NColors.amber : const Color(0xFFB45309)) : NColors.coral);

    Future<void> pdf() => ReportPreviewScreen.open(context,
        title: tr('Deneme sonuç listesi'),
        fileName: '${exam.name.replaceAll(RegExp(r'[^\wğüşıöçĞÜŞİÖÇ -]'), '').replaceAll(' ', '_')}_deneme.pdf',
        build: () => buildDenemePdf(report: rep, students: students, school: store.reportSchool),
        word: () => buildDenemeDocx(report: rep, students: students, school: store.reportSchool));

    final ranked = rep.ranked;
    final w = exam.hasWeightedScore;

    Widget subjectCard(SectionSummary s) => Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.section.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text.rich(TextSpan(children: [
                TextSpan(text: _f(s.meanNet), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: tone(s.percent))),
                TextSpan(text: ' / ${s.counted} ${tr('net')}', style: TextStyle(color: muted, fontWeight: FontWeight.w600)),
              ])),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (s.percent / 100).clamp(0, 1),
                  minHeight: 8,
                  color: tone(s.percent),
                  backgroundColor: t.colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 6),
              Text(tr('Ort. {0} doğru · {1} yanlış · en yüksek {2}', [_f(s.meanCorrect), _f(s.meanWrong), _f(s.maxNet)]),
                  style: t.textTheme.bodySmall?.copyWith(color: muted)),
            ]),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Ders ders sonuçlar')),
          Text(exam.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.bodySmall),
        ]),
        actions: [
          IconButton(tooltip: tr('Ders bölümleri'), onPressed: () => SectionsScreen.open(context, exam.id), icon: const Icon(Icons.tune)),
          if (results.isNotEmpty)
            IconButton(tooltip: tr('PDF'), onPressed: pdf, icon: const Icon(Icons.picture_as_pdf_outlined)),
          const SizedBox(width: 8),
        ],
      ),
      body: results.isEmpty
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(tr('Sonuçlar için önce kâğıt okutun.'))))
          : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 40), children: [
              HeroPanel(
                child: Wrap(spacing: 28, runSpacing: 14, children: [
                  _HeroNum(tr('ORTALAMA TOPLAM NET'), '${_f(rep.meanTotalNet)} / ${exam.questionCount}'),
                  if (w) _HeroNum(tr('ORTALAMA PUAN'), _f(rep.meanWeighted ?? 0)),
                  _HeroNum(tr('EN BAŞARILI DERS'), ranked.first.section.name),
                  _HeroNum(tr('EN ÇOK ÇALIŞILACAK DERS'), ranked.last.section.name),
                ]),
              ),
              SectionTitle(tr('Dersler')),
              LayoutBuilder(builder: (context, c) {
                final n = rep.summaries.length;
                final cols = c.maxWidth >= 900 ? (n <= 4 ? n : (n == 6 ? 3 : 4)) : (c.maxWidth >= 560 ? 2 : 1);
                final cw = (c.maxWidth - (cols - 1) * 8) / cols;
                return Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final s in rep.summaries) SizedBox(width: cw, child: subjectCard(s)),
                ]);
              }),
              SectionTitle(tr('Ders başarı sıralaması')),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    for (final (i, s) in ranked.indexed)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(children: [
                          SizedBox(width: 26, child: Text('${i + 1}.', style: TextStyle(color: muted, fontWeight: FontWeight.w700))),
                          Expanded(flex: 4, child: Text(s.section.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                          Expanded(
                            flex: 5,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: (s.percent / 100).clamp(0, 1),
                                minHeight: 10,
                                color: tone(s.percent),
                                backgroundColor: t.colorScheme.surfaceContainerHighest,
                              ),
                            ),
                          ),
                          SizedBox(
                              width: 56,
                              child: Text('%${s.percent.round()}',
                                  textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.w800, color: tone(s.percent)))),
                        ]),
                      ),
                  ]),
                ),
              ),
              SectionTitle(tr('Öğrenci sıralaması')),
              Card(
                clipBehavior: Clip.antiAlias,
                child: LayoutBuilder(builder: (context, c) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: c.maxWidth),
                  child: DataTable(
                    showCheckboxColumn: false,
                    columnSpacing: 18,
                    headingTextStyle: const TextStyle(fontWeight: FontWeight.w800),
                    columns: [
                      DataColumn(label: Text(tr('Sıra')), numeric: true),
                      DataColumn(label: Text(tr('Ad Soyad'))),
                      for (final s in exam.sections)
                        DataColumn(
                            label: Tooltip(
                                message: s.name,
                                child: Text(s.name.length > 12 ? '${s.name.substring(0, 11)}.' : s.name)),
                            numeric: true),
                      DataColumn(label: Text(tr('Toplam net')), numeric: true),
                      DataColumn(label: Text(w ? tr('Puan') : tr('Not')), numeric: true),
                    ],
                    rows: [
                      for (final r in rep.rows)
                        DataRow(
                          onSelectChanged: r.result.sheet.studentId == null
                              ? null
                              : (_) => Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => StudentDetailScreen(studentId: r.result.sheet.studentId!))),
                          cells: [
                            DataCell(Text('${r.rank}', style: const TextStyle(fontWeight: FontWeight.w800))),
                            DataCell(Text(students[r.result.sheet.studentId]?.fullName ?? tr('Eşleşmeyen kâğıt'))),
                            for (final s in r.sections)
                              DataCell(Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                                Text(_f(s.net), style: TextStyle(fontWeight: FontWeight.w800, color: tone(s.percent))),
                                Text('${s.correct}D ${s.wrong}Y', style: t.textTheme.bodySmall?.copyWith(color: muted)),
                              ])),
                            DataCell(Text(_f(r.totalNet), style: const TextStyle(fontWeight: FontWeight.w800))),
                            DataCell(Text(w ? _f(r.weighted!) : _f(r.result.score))),
                          ],
                        ),
                    ],
                  ),
                  ),
                )),
              ),
              const SizedBox(height: 8),
              Text(
                w
                    ? tr('Puan = taban puan + her dersin neti × katsayısı (tahmini).')
                    : tr('Sıralama toplam nete göredir. Katsayılı puan için Ders bölümleri\'nden açın.'),
                style: t.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ]),
    );
  }
}

class _HeroNum extends StatelessWidget {
  final String label;
  final String value;
  const _HeroNum(this.label, this.value);

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
      ]);
}
