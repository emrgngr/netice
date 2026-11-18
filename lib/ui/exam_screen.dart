import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../core/analysis.dart';
import '../core/import_export.dart';
import '../core/models.dart';
import '../core/report.dart';
import '../core/scoring.dart';
import '../main.dart';
import '../reports/pdf_documents.dart';
import 'review_screen.dart';
import 'camera_scan_screen.dart';
import 'exam_settings_screen.dart';
import 'report_preview_screen.dart';
import 'student_detail_screen.dart';
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
      final cls = store.studentsOf(exam.className);
      var copies = 10;
      var alternate = true;
      final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSheet) => SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ListTile(
                    title: Text('Optik form yazdır', style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('A4, %100 ölçekle yazdırın. Önce önizleme açılır.'),
                  ),
                  ListTile(
                    enabled: cls.isNotEmpty,
                    leading: const Icon(Icons.badge_outlined),
                    title: const Text('İsimli öğrenci formları'),
                    subtitle: Text(
                      cls.isEmpty
                          ? 'Bu sınıfta kayıtlı öğrenci yok'
                          : '${cls.length} öğrenci · ad, sınıf ve numara basılı gelir',
                    ),
                    onTap: () => Navigator.pop(ctx, 'named'),
                  ),
                  if (exam.hasBooklets && cls.isNotEmpty)
                    SwitchListTile(
                      contentPadding: const EdgeInsets.only(left: 72, right: 16),
                      value: alternate,
                      onChanged: (v) => setSheet(() => alternate = v),
                      title: const Text('Kitapçıkları sırayla A, B dağıt'),
                      subtitle: const Text('Kapalıysa öğrenci kitapçığını formda kendisi işaretler'),
                    ),
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: const Text('Boş öğrenci formu'),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final n in const [1, 10, 20, 30, 40])
                            ChoiceChip(
                              label: Text('$n adet'),
                              selected: copies == n,
                              onSelected: (_) => setSheet(() => copies = n),
                            ),
                        ],
                      ),
                    ),
                    onTap: () => Navigator.pop(ctx, 'blank'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.key_outlined),
                    title: const Text('Cevap anahtarı'),
                    subtitle: const Text('Doğru şıklar karartılmış form ve anahtar listesi'),
                    onTap: () => Navigator.pop(ctx, 'key'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.edit_note_outlined),
                    title: const Text('Boş cevap anahtarı formu'),
                    subtitle: const Text('Elle doldurup Sınav ayarlarından fotoğrafla okutun'),
                    onTap: () => Navigator.pop(ctx, 'keyBlank'),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      );
      if (choice == null || !context.mounted) return;
      final name = _safe(exam.name);
      switch (choice) {
        case 'named':
          await ReportPreviewScreen.open(
            context,
            title: 'Öğrenci formları',
            fileName: '${name}_optik_form.pdf',
            build: () => buildFormsPdf(exam, cls, school: store.school, alternateBooklets: alternate),
          );
        case 'blank':
          await ReportPreviewScreen.open(
            context,
            title: 'Boş optik form ($copies adet)',
            fileName: '${name}_bos_form_$copies.pdf',
            build: () => buildFormsPdf(exam, const [], blankCopies: copies, school: store.school),
          );
        case 'key':
          await ReportPreviewScreen.open(
            context,
            title: 'Cevap anahtarı',
            fileName: '${name}_cevap_anahtari.pdf',
            build: () => buildAnswerKeyPdf(exam, school: store.school),
          );
        case 'keyBlank':
          await ReportPreviewScreen.open(
            context,
            title: 'Boş cevap anahtarı formu',
            fileName: '${name}_bos_anahtar.pdf',
            build: () => buildAnswerKeyPdf(exam, filled: false, school: store.school),
          );
      }
    }

    Future<void> pdfReport() async {
      if (results.isEmpty) return toast(context, 'Rapor için önce kâğıt okutun.');
      await ReportPreviewScreen.open(context,
          title: 'Sınav raporu',
          fileName: '${_safe(exam.name)}_sinav_raporu.pdf',
          build: () => buildResultsPdf(exam: exam, results: results, students: store.studentById, school: store.school));
    }

    Future<void> studentCards() async {
      if (results.isEmpty) return toast(context, 'Karne için önce kâğıt okutun.');
      await openCardsPreview(context, exam);
    }

    Future<void> excel() async {
      final csv = resultsCsv(exam, results, store.studentById);
      await FilePicker.saveFile(
        fileName: '${_safe(exam.name)}_not_listesi.csv',
        bytes: Uint8List.fromList(utf8.encode(csv)),
        mimeType: 'text/csv',
      );
    }

    Future<void> eokul() async {
      final cls = store.studentsOf(exam.className);
      if (cls.isEmpty) return toast(context, 'Bu sınıfta kayıtlı öğrenci yok.');
      final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const ListTile(title: Text('e-Okul not giriş listesi', style: TextStyle(fontWeight: FontWeight.w800))),
            ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: const Text('PDF (yazdırmak için)'),
                onTap: () => Navigator.pop(ctx, 'pdf')),
            ListTile(
                leading: const Icon(Icons.table_view_outlined),
                title: const Text('Excel'),
                onTap: () => Navigator.pop(ctx, 'xls')),
          ]),
        ),
      );
      if (choice == 'pdf') {
        if (!context.mounted) return;
        await ReportPreviewScreen.open(context,
            title: 'e-Okul listesi',
            fileName: '${_safe(exam.name)}_eokul.pdf',
            build: () => buildEokulPdf(exam: exam, results: results, classStudents: cls, school: store.school));
      } else if (choice == 'xls') {
        await FilePicker.saveFile(
          fileName: '${_safe(exam.name)}_eokul.csv',
          bytes: Uint8List.fromList(utf8.encode(eokulCsv(exam, results, cls))),
          mimeType: 'text/csv',
        );
      }
    }

    Future<void> labels() async {
      if (results.isEmpty) return toast(context, 'Etiket için önce kâğıt okutun.');
      await ReportPreviewScreen.open(context,
          title: 'Sonuç etiketleri',
          fileName: '${_safe(exam.name)}_etiketler.pdf',
          build: () => buildLabelsPdf(exam: exam, results: results, students: store.studentById));
    }

    final actions = [
      _Action(Icons.print_outlined, 'Form yazdır', printForms),
      _Action(Icons.picture_as_pdf_outlined, 'Sınav raporu', pdfReport),
      _Action(Icons.badge_outlined, 'Öğrenci karnesi', studentCards),
      _Action(Icons.table_view_outlined, 'Excel', excel),
      _Action(Icons.school_outlined, 'e-Okul listesi', eokul),
      _Action(Icons.label_outline, 'Sonuç etiketi', labels),
    ];

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(exam.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('${exam.className} · ${dmy(exam.date)} ${hm(exam.date)} · ${exam.questionCount} soru',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall),
          ]),
          actions: [
            IconButton(
              tooltip: 'Sınav ayarları',
              icon: const Icon(Icons.tune),
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => ExamSettingsScreen(examId: exam.id))),
            ),
            if (wide)
              for (final a in actions.take(3))
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: OutlinedButton.icon(onPressed: a.run, icon: Icon(a.icon), label: Text(a.label)),
                ),
            PopupMenuButton<_Action>(
              onSelected: (a) => a.run(),
              itemBuilder: (_) => [
                for (final a in wide ? actions.skip(3) : actions)
                  PopupMenuItem(value: a, child: ListTile(leading: Icon(a.icon), title: Text(a.label))),
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
          onPressed: () => Navigator.of(context).push(scanRoute(exam.id)),
          icon: const Icon(Icons.document_scanner_outlined),
          label: const Text('Okut', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        body: Watermark(child: TabBarView(children: [
          _ResultsTab(exam: exam, results: results),
          _AnalysisTab(exam: exam, results: results, reports: actions.skip(1).toList()),
          SafeArea(top: false, child: ReviewList(exam: exam)),
        ])),
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
      HeroPanel(
        child: Row(children: [
          ScoreRing(
            value: st.mean / exam.rule.maxScore * 100,
            size: wide ? 120 : 104,
            track: Colors.white.withValues(alpha: 0.14),
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: wide ? 28 : 24, fontFeatures: tabular),
          ),
          const SizedBox(width: 22),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('SINIF ORTALAMASI',
                  style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
              const SizedBox(height: 10),
              Wrap(spacing: 22, runSpacing: 12, children: [
                _HeroStat('Medyan', fmt1(st.median)),
                _HeroStat('Std. sapma', fmt1(st.stdDev)),
                _HeroStat('KR-20', st.kr20 == null ? '–' : fmt2(st.kr20!)),
                _HeroStat('Okunan', '${st.count}'),
              ]),
            ]),
          ),
        ]),
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
              leading: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: i < 3 ? emeraldGradient : null,
                  color: i < 3 ? null : t.colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Text('${i + 1}',
                    style: t.textTheme.titleSmall?.copyWith(
                        fontFeatures: tabular, fontWeight: FontWeight.w800, color: i < 3 ? NColors.ink : null)),
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
          if (st != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => StudentDetailScreen(studentId: st.id)));
                },
                icon: const Icon(Icons.timeline, size: 18),
                label: const Text('Öğrenci geçmişi ve gelişimi'),
              ),
            ),
          if (st != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  openCardsPreview(context, exam, studentId: st.id);
                },
                icon: const Icon(Icons.badge_outlined, size: 18),
                label: const Text('Karneyi önizle'),
              ),
            ),
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
                    gradient: i == 4 ? emeraldGradient : inkGradient,
                    borderRadius: BorderRadius.circular(10),
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
  final List<_Action> reports;
  const _AnalysisTab({required this.exam, required this.results, required this.reports});

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) return const Center(child: Text('Analiz için önce kâğıt okutun.'));
    final rep = ExamReport.build(exam, results);
    final s = rep.stats;
    final items = rep.items;
    final worst = [...items.where((i) => !exam.questions[i.no - 1].cancelled)]..sort((a, b) => a.p.compareTo(b.p));
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);

    Widget itemCard(ItemStats it) {
      final warn = it.suspiciousChoice != null;
      final code = exam.questions[it.no - 1].outcomeCode;
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
                if (code != null && code.isNotEmpty) Text(code, style: t.textTheme.bodySmall?.copyWith(color: muted)),
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
                if (it.nonFunctional.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('İşlevsiz çeldirici: ${it.nonFunctional.map(letter).join(', ')} (kimse seçmedi)',
                        style: t.textTheme.bodySmall?.copyWith(color: muted)),
                  ),
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

    final kr = s.kr20;
    final stats = <StatCard>[
      StatCard(label: 'Ortalama', value: fmt1(s.mean), hint: 'Medyan ${fmt1(s.median)}', icon: Icons.functions),
      StatCard(
          label: 'Başarı oranı',
          value: '%${(rep.passRate * 100).round()}',
          hint: 'Geçme puanı ${exam.rule.pass.round()} ve üzeri',
          icon: Icons.emoji_events_outlined),
      StatCard(label: 'En yüksek', value: fmt1(s.max), hint: 'En düşük ${fmt1(s.min)}', icon: Icons.trending_up),
      StatCard(
          label: 'Std. sapma',
          value: fmt1(s.stdDev),
          hint: rep.cv == null ? null : 'Değişim %${rep.cv!.round()}',
          icon: Icons.stacked_line_chart),
      StatCard(
          label: 'Çeyrekler',
          value: '${fmt1(rep.q1)}–${fmt1(rep.q3)}',
          hint: 'Ortadaki yarı',
          icon: Icons.align_horizontal_center),
      StatCard(
          label: 'Ortalama net',
          value: fmt2(rep.meanNet),
          hint: '${fmt1(rep.meanCorrect)} D · ${fmt1(rep.meanWrong)} Y · ${fmt1(rep.meanBlank)} B',
          icon: Icons.check_circle_outline),
      StatCard(
          label: 'Güvenirlik',
          value: kr == null ? '–' : fmt2(kr),
          hint: kr == null
              ? 'KR-20 hesaplanamadı'
              : kr >= 0.8
                  ? 'KR-20 · yüksek'
                  : kr >= 0.7
                      ? 'KR-20 · kabul edilebilir'
                      : 'KR-20 · düşük',
          accent: kr != null && kr < 0.7 ? NColors.amber : null,
          icon: Icons.verified_outlined),
      StatCard(
          label: 'Ölçme hatası',
          value: rep.sem == null ? '–' : '±${fmt1(rep.sem!)}',
          hint: 'SEM, puan',
          icon: Icons.blur_on),
      StatCard(label: 'Güçlük (p)', value: fmt2(rep.meanP), hint: 'Doğru oranı', icon: Icons.speed),
      StatCard(label: 'Ayırt edicilik', value: fmt2(rep.meanD), hint: 'Üst − alt grup', icon: Icons.compare_arrows),
      StatCard(label: 'Üst %27 ort.', value: fmt1(rep.upperMean), accent: NColors.emerald, icon: Icons.north_east),
      StatCard(label: 'Alt %27 ort.', value: fmt1(rep.lowerMean), accent: NColors.coral, icon: Icons.south_east),
    ];

    const levelColors = [NColors.emerald, Color(0xFF34D399), NColors.amber, Color(0xFFF59E0B), NColors.coral];

    return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 100), children: [
      HeroPanel(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('RAPOR AL',
              style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
          const SizedBox(height: 4),
          const Text('Grafikli sınav raporu, öğrenci karneleri ve Excel listesi',
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final a in reports)
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: a.run,
                icon: Icon(a.icon, size: 20),
                label: Text(a.label),
              ),
          ]),
        ]),
      ),
      const SectionTitle('Genel istatistikler'),
      GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 240, mainAxisExtent: 134, crossAxisSpacing: 12, mainAxisSpacing: 12),
        children: stats,
      ),
      const SectionTitle('Otomatik değerlendirme'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final c in rep.comments)
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
          ]),
        ),
      ),
      const SectionTitle('Başarı düzeyleri'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            for (var i = 0; i < Level.all.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  SizedBox(
                    width: 104,
                    child: Text('${Level.all[i].name} (${Level.all[i].minPct.round()}+)',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: s.count == 0 ? 0 : rep.levelCounts[i] / s.count,
                        minHeight: 12,
                        color: levelColors[i],
                        backgroundColor: t.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text('${rep.levelCounts[i]}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontFeatures: tabular)),
                  ),
                ]),
              ),
          ]),
        ),
      ),
      const SectionTitle('Soru güçlük grafiği'),
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _DifficultyChart(exam: exam, items: items),
            const SizedBox(height: 8),
            Text('Çubuk: doğru oranı · yeşil kolay, lacivert orta, mercan zor',
                style: t.textTheme.bodySmall?.copyWith(color: muted)),
          ]),
        ),
      ),
      const SectionTitle('Soru kalitesi'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Güçlük', style: t.textTheme.labelLarge?.copyWith(color: muted)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in rep.difficultyCounts.entries) Chip(label: Text('${e.key}: ${e.value}')),
            ]),
            const SizedBox(height: 12),
            Text('Ayırt edicilik', style: t.textTheme.labelLarge?.copyWith(color: muted)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in rep.discriminationCounts.entries) Chip(label: Text('${e.key}: ${e.value}')),
            ]),
          ]),
        ),
      ),
      SectionTitle('Kazanım / konu analizi',
          trailing: TextButton.icon(
            onPressed: () => _editOutcomes(context),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Düzenle'),
          )),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: rep.outcomes.isEmpty
              ? Text('Soruları konulara bağlarsanız her konunun başarısı burada ve raporda görünür. "Düzenle"ye dokunun.',
                  style: TextStyle(color: muted))
              : Column(children: [
                  for (final o in [...rep.outcomes]..sort((a, b) => a.rate.compareTo(b.rate)))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                              child: Text('${o.code}  ·  ${o.questionNos.length} soru',
                                  style: const TextStyle(fontWeight: FontWeight.w600))),
                          Text('%${(o.rate * 100).round()}',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontFeatures: tabular)),
                        ]),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: o.rate,
                            minHeight: 10,
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
                ]),
        ),
      ),
      if (rep.outcomes.isNotEmpty) ...[
        const SectionTitle('Kazanım ısı haritası'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: _Heatmap(rep: rep),
          ),
        ),
      ],
      if (results.length < Analysis.reliableGroupSize)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text('${results.length} öğrenci ile madde istatistikleri güvenilir değildir; yol gösterici olarak okuyun.',
              style: t.textTheme.bodySmall?.copyWith(color: NColors.amber)),
        ),
      const SectionTitle('En çok yanlış yapılan sorular'),
      for (final it in worst.take(5)) Padding(padding: const EdgeInsets.only(bottom: 10), child: itemCard(it)),
      const SectionTitle('Tüm sorular'),
      for (final it in items) Padding(padding: const EdgeInsets.only(bottom: 10), child: itemCard(it)),
    ]);
  }

  Future<void> _editOutcomes(BuildContext context) async {
    final store = StoreScope.of(context);
    final ctrl = TextEditingController(text: formatOutcomeRanges(exam));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kazanımlar / konular'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: '1-5 Hareket\n6-10 Kuvvet',
              helperText: 'Her satıra soru aralığı ve konu adı yazın.',
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kaydet')),
        ],
      ),
    );
    if (ok != true) return;
    final m = parseOutcomeRanges(ctrl.text, exam.questionCount);
    store.upsertExam(exam.copyWith(questions: [
      for (final q in exam.questions)
        Question(no: q.no, correct: q.correct, points: q.points, cancelled: q.cancelled, outcomeCode: m[q.no]),
    ]));
    if (context.mounted) toast(context, 'Kazanımlar kaydedildi.');
  }

  void _cancelQuestion(BuildContext context, int no) {
    final store = StoreScope.of(context);
    final qs = [...exam.questions];
    qs[no - 1] = qs[no - 1].copyWith(cancelled: true);
    store.upsertExam(exam.copyWith(questions: qs));
    toast(context, '$no. soru iptal edildi; tüm puanlar yeniden hesaplandı.');
  }
}

class _HeroStat extends StatelessWidget {
  final String label;
  final String value;
  const _HeroStat(this.label, this.value);

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, fontFeatures: tabular)),
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
      ]);
}

class _DifficultyChart extends StatelessWidget {
  final Exam exam;
  final List<ItemStats> items;
  const _DifficultyChart({required this.exam, required this.items});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    const barW = 22.0;
    Widget bar(ItemStats it) {
      final cancelled = exam.questions[it.no - 1].cancelled;
      final p = cancelled ? 0.0 : it.p;
      final color = cancelled
          ? NColors.gray
          : p > 0.8
              ? NColors.emerald
              : p >= 0.3
                  ? (t.brightness == Brightness.dark ? const Color(0xFF6C7BB5) : NColors.ink)
                  : NColors.coral;
      return Tooltip(
        message: cancelled ? '${it.no}. soru iptal' : '${it.no}. soru: %${(p * 100).round()} doğru',
        child: SizedBox(
          width: barW + 6,
          child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
            Text('${(p * 100).round()}', style: t.textTheme.labelSmall?.copyWith(fontSize: 9, fontFeatures: tabular)),
            const SizedBox(height: 2),
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: barW,
              height: 100 * p + 2,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
            ),
            const SizedBox(height: 4),
            Text('${it.no}', style: t.textTheme.labelSmall?.copyWith(fontFeatures: tabular)),
          ]),
        ),
      );
    }

    return SizedBox(
      height: 140,
      child: LayoutBuilder(builder: (context, c) {
        final fits = items.length * (barW + 6) <= c.maxWidth;
        final row = Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: fits ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
          children: [for (final it in items) bar(it)],
        );
        return fits ? row : SingleChildScrollView(scrollDirection: Axis.horizontal, child: row);
      }),
    );
  }
}

class _Heatmap extends StatelessWidget {
  final ExamReport rep;
  const _Heatmap({required this.rep});

  static Color colorOf(double v) => v >= 0.7
      ? NColors.emerald
      : v >= 0.5
          ? NColors.amber
          : NColors.coral;

  @override
  Widget build(BuildContext context) {
    final students = StoreScope.of(context).studentById;
    final t = Theme.of(context);
    Widget cell(double v, {bool bold = false}) => Container(
          width: 64,
          height: 30,
          margin: const EdgeInsets.all(1.5),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: colorOf(v).withValues(alpha: 0.22), borderRadius: BorderRadius.circular(6)),
          child: Text('%${(v * 100).round()}',
              style: TextStyle(fontSize: 12, fontFeatures: tabular, fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        );
    Widget name(String s, {bool bold = false}) => SizedBox(
          width: 140,
          child: Text(s,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        name(''),
        for (final o in rep.outcomes)
          SizedBox(
            width: 67,
            child: Text(o.code,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: t.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
      ]),
      const SizedBox(height: 4),
      for (final st in rep.standings)
        Row(children: [
          name(students[st.result.sheet.studentId]?.fullName ?? 'Eşleşmeyen kâğıt'),
          for (final o in rep.outcomes) cell(o.rateOf(rep.exam, st.result)),
        ]),
      Row(children: [
        name('Sınıf', bold: true),
        for (final o in rep.outcomes) cell(o.rate, bold: true),
      ]),
    ]);
  }
}

/// Öğrenci karnesi önizlemesini açar; [studentId] verilirse o öğrenciyle başlar.
Future<void> openCardsPreview(BuildContext context, Exam exam, {String? studentId}) {
  final store = StoreScope.of(context);
  final results = store.resultsOf(exam);
  final byId = store.studentById;
  final students = [
    for (final r in results)
      if (byId[r.sheet.studentId] != null) (byId[r.sheet.studentId]!.id, byId[r.sheet.studentId]!.fullName),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  return Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => StudentCardsPreview(
      title: 'Öğrenci karnesi',
      baseFileName: '${_safe(exam.name)}_karne',
      students: students,
      initialStudentId: studentId,
      build: (id) => buildStudentCardsPdf(exam: exam, results: results, students: byId, onlyStudentId: id, school: store.school),
    ),
  ));
}
