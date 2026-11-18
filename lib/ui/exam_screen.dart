import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:printing/printing.dart';

import '../core/analysis.dart';
import '../core/import_export.dart';
import '../core/models.dart';
import '../core/scoring.dart';
import '../main.dart';
import '../reports/pdf_documents.dart';
import 'review_screen.dart';
import 'scan_screen.dart';
import 'theme.dart';
import 'widgets.dart';

class ExamScreen extends StatelessWidget {
  final String examId;
  const ExamScreen({super.key, required this.examId});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final exam = store.examById(examId);
    if (exam == null) return const Scaffold();
    final results = store.resultsOf(exam);
    final review = store.sheetsOf(exam.id).where((s) => s.needsReview).length;
    final wide = MediaQuery.sizeOf(context).width >= 900;

    Future<void> printForms() async {
      final bytes = await buildFormsPdf(exam, store.studentsOf(exam.className));
      await Printing.sharePdf(bytes: bytes, filename: '${_safe(exam.name)}_optik_form.pdf');
    }

    Future<void> pdfReport() async {
      final bytes = await buildResultsPdf(exam: exam, results: results, students: store.studentById);
      await Printing.sharePdf(bytes: bytes, filename: '${_safe(exam.name)}_sonuclar.pdf');
    }

    Future<void> excel() async {
      final csv = resultsCsv(exam, results, store.studentById);
      await FilePicker.saveFile(
        fileName: '${_safe(exam.name)}_not_listesi.csv',
        bytes: Uint8List.fromList(utf8.encode(csv)),
        mimeType: 'text/csv',
      );
    }

    final actions = [
      _Action(Icons.print_outlined, 'Form yazdır', printForms),
      _Action(Icons.picture_as_pdf_outlined, 'PDF rapor', pdfReport),
      _Action(Icons.table_view_outlined, 'Excel', excel),
    ];

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(exam.name),
            Text('${exam.className} · ${exam.questionCount} soru · ${exam.choiceCount} şık',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
          actions: [
            if (wide)
              for (final a in actions)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: OutlinedButton.icon(onPressed: a.run, icon: Icon(a.icon), label: Text(a.label)),
                )
            else
              PopupMenuButton<_Action>(
                onSelected: (a) => a.run(),
                itemBuilder: (_) => [
                  for (final a in actions) PopupMenuItem(value: a, child: ListTile(leading: Icon(a.icon), title: Text(a.label))),
                ],
              ),
            const SizedBox(width: 8),
          ],
          bottom: TabBar(tabs: [
            const Tab(text: 'Sonuçlar'),
            const Tab(text: 'Analiz'),
            Tab(text: review > 0 ? 'Kontrol ($review)' : 'Kontrol'),
          ]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: NColors.emerald,
          foregroundColor: NColors.ink,
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ScanScreen(examId: exam.id))),
          icon: const Icon(Icons.document_scanner_outlined),
          label: const Text('Okut', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        body: TabBarView(children: [
          _ResultsTab(exam: exam, results: results),
          _AnalysisTab(exam: exam, results: results),
          SafeArea(top: false, child: ReviewList(exam: exam)),
        ]),
      ),
    );
  }
}

String _safe(String s) => s.replaceAll(RegExp(r'[^\wğüşıöçĞÜŞİÖÇ -]'), '').replaceAll(' ', '_');

class _Action {
  final IconData icon;
  final String label;
  final Future<void> Function() run;
  _Action(this.icon, this.label, this.run);
}

class _ResultsTab extends StatelessWidget {
  final Exam exam;
  final List<Result> results;
  const _ResultsTab({required this.exam, required this.results});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final students = store.studentById;
    final sorted = [...results]..sort((a, b) => b.score.compareTo(a.score));
    final st = Analysis.examStats(exam, results);
    final t = Theme.of(context);
    if (results.isEmpty) {
      return const Center(child: Text('Henüz okunan kâğıt yok. "Okut" ile başlayın.'));
    }
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 100), children: [
      GridView(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: wide ? 4 : 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: 104,
        ),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          StatCard(label: 'Sınıf ortalaması', value: fmt1(st.mean)),
          StatCard(label: 'Medyan', value: fmt1(st.median)),
          StatCard(label: 'Std. sapma', value: fmt1(st.stdDev)),
          StatCard(label: 'KR-20', value: st.kr20 == null ? '–' : fmt2(st.kr20!)),
        ],
      ),
      const SectionTitle('Puan dağılımı'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _Histogram(st.histogram),
        ),
      ),
      const SectionTitle('Öğrenciler'),
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < sorted.length; i++)
            ListTile(
              leading: SizedBox(
                width: 28,
                child: Text('${i + 1}', style: t.textTheme.titleSmall?.copyWith(fontFeatures: tabular)),
              ),
              title: Text(students[sorted[i].sheet.studentId]?.fullName ?? 'Eşleşmeyen kâğıt',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: sorted[i].sheet.studentId == null ? NColors.amber : null)),
              subtitle: DybText(sorted[i].correct, sorted[i].wrong, sorted[i].blank),
              trailing: Text(fmt1(sorted[i].score),
                  style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabular)),
              onTap: () => showSheetDetail(context, exam, sorted[i]),
            ),
        ]),
      ),
    ]);
  }
}

void showSheetDetail(BuildContext context, Exam exam, Result r) {
  final st = StoreScope.of(context).studentById[r.sheet.studentId];
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(st?.fullName ?? 'Eşleşmeyen kâğıt', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          Text('No ${st?.number ?? '–'} · Puan ${fmt1(r.score)} · Net ${fmt2(r.net)}'),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (var i = 0; i < exam.questionCount; i++)
              Container(
                width: 52,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: switch (r.outcomes[i]) {
                    Outcome.correct => NColors.emerald.withValues(alpha: 0.15),
                    Outcome.wrong => NColors.coral.withValues(alpha: 0.15),
                    _ => NColors.gray.withValues(alpha: 0.15),
                  },
                ),
                child: Column(children: [
                  Text('${i + 1}', style: Theme.of(ctx).textTheme.labelSmall),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                        switch (r.outcomes[i]) {
                          Outcome.correct => Icons.check,
                          Outcome.wrong => Icons.close,
                          Outcome.blank => Icons.remove,
                          Outcome.cancelled => Icons.block,
                        },
                        size: 14),
                    const SizedBox(width: 2),
                    Text(answerText(r.sheet.answers[i]), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                ]),
              ),
          ]),
        ]),
      ),
    ),
  );
}

class _Histogram extends StatelessWidget {
  final List<int> bins;
  const _Histogram(this.bins);

  @override
  Widget build(BuildContext context) {
    final maxV = bins.fold<int>(1, (a, b) => a > b ? a : b);
    const labels = ['0–19', '20–39', '40–59', '60–79', '80–100'];
    return SizedBox(
      height: 140,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < bins.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text('${bins[i]}', style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: tabular)),
                const SizedBox(height: 4),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  height: 90 * bins[i] / maxV + 2,
                  decoration: BoxDecoration(
                    color: i == 4 ? NColors.emerald : Theme.of(context).colorScheme.primary.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 6),
                Text(labels[i], style: Theme.of(context).textTheme.labelSmall),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _AnalysisTab extends StatelessWidget {
  final Exam exam;
  final List<Result> results;
  const _AnalysisTab({required this.exam, required this.results});

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) return const Center(child: Text('Analiz için önce kâğıt okutun.'));
    final items = Analysis.itemStats(exam, results);
    final worst = [...items.where((i) => !exam.questions[i.no - 1].cancelled)]..sort((a, b) => a.p.compareTo(b.p));
    final t = Theme.of(context);

    Widget itemCard(ItemStats it) {
      final warn = it.suspiciousChoice != null;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: (warn ? NColors.amber : t.colorScheme.primary).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('S${it.no}', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Doğru oranı %${(it.p * 100).round()} · ${it.difficultyLabel}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  warn
                      ? '! Üst grubun çoğu ${letter(it.suspiciousChoice!)} şıkkını seçti; anahtarı kontrol edin'
                      : 'Ayırt edicilik ${fmt2(it.d)} · ${it.discriminationLabel}',
                  style: TextStyle(color: warn ? NColors.amber : t.colorScheme.onSurface.withValues(alpha: 0.65)),
                ),
                const SizedBox(height: 6),
                Wrap(spacing: 10, children: [
                  for (var c = 0; c < exam.choiceCount; c++)
                    Text('${letter(c)}: ${it.choiceCounts[c]}',
                        style: TextStyle(
                          fontFeatures: tabular,
                          fontWeight: exam.questions[it.no - 1].correct.contains(c) ? FontWeight.w800 : FontWeight.w400,
                          color: exam.questions[it.no - 1].correct.contains(c) ? NColors.emerald : null,
                        )),
                  Text('Boş: ${it.blankCount}', style: const TextStyle(color: NColors.gray)),
                ]),
              ]),
            ),
            if (warn)
              IconButton(
                tooltip: 'Bu soruyu iptal et',
                icon: const Icon(Icons.block),
                onPressed: () => _cancelQuestion(context, it.no),
              ),
          ]),
        ),
      );
    }

    return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 100), children: [
      if (results.length < Analysis.reliableGroupSize)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('${results.length} öğrenci ile madde istatistikleri güvenilir değildir; yol gösterici olarak okuyun.',
              style: t.textTheme.bodySmall?.copyWith(color: NColors.amber)),
        ),
      const SectionTitle('En çok yanlış yapılan sorular'),
      for (final it in worst.take(5)) Padding(padding: const EdgeInsets.only(bottom: 10), child: itemCard(it)),
      const SectionTitle('Tüm sorular'),
      for (final it in items) Padding(padding: const EdgeInsets.only(bottom: 10), child: itemCard(it)),
    ]);
  }

  void _cancelQuestion(BuildContext context, int no) {
    final store = StoreScope.of(context);
    final qs = [...exam.questions];
    qs[no - 1] = qs[no - 1].copyWith(cancelled: true);
    store.upsertExam(exam.copyWith(questions: qs));
    toast(context, '$no. soru iptal edildi; tüm puanlar yeniden hesaplandı.');
  }
}
