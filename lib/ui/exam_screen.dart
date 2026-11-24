import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:printing/printing.dart';

import '../core/analysis.dart';
import '../core/common_exam.dart';
import '../core/insights.dart';
import '../core/progress.dart';
import '../core/store.dart';
import 'common_exam_ui.dart';
import '../core/import_export.dart';
import '../core/legal.dart';
import '../core/models.dart';
import '../core/report.dart';
import '../core/scoring.dart';
import '../main.dart';
import '../reports/pdf_documents.dart';
import 'review_screen.dart';
import 'camera_scan_screen.dart';
import 'exam_settings_screen.dart';
import 'open_scores_screen.dart';
import 'report_preview_screen.dart';
import 'student_detail_screen.dart';
import 'pro_screen.dart';
import 'personal_review_ui.dart';
import 'parent_send_screen.dart';
import '../core/pro.dart';
import 'sheet_image_screen.dart';
import 'theme.dart';
import 'widgets.dart';
import 'illustrations.dart';
import 'charts.dart';
import '../l10n/l10n.dart';
import '../core/ads.dart';
import '../omr/form_layout.dart' show MiniFormLayout;
import 'ad_slot.dart';
import '../bank/bank_analysis.dart';
import '../bank/bank_store.dart';
import 'bank/bank_analysis_view.dart' show WeakTopicsCard;

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
      final tpl = store.templateById(exam.templateId);
      if (tpl != null) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr('Bu sınav başka firma formuyla okunuyor')),
            content: Text(tr('Sınav ayarlarında "{0}" şablonu seçili; öğrenciler o formu dolduracak. Yine de Netice formu basarsanız, okutmadan önce Form türünü "Netice formu" yapın.', [tpl.name])),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Vazgeç'))),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Yine de bas'))),
            ],
          ),
        );
        if (go != true || !context.mounted) return;
      }
      // Öğrencisi olan şubeler; bu sınavın şubesi her zaman başta.
      final allClasses = [
        exam.className,
        for (final c in store.classNames)
          if (c != exam.className && store.studentsOf(c).isNotEmpty) c,
      ];
      final chosen = <String>{exam.className};
      List<Student> studentsIn(Set<String> set) => [for (final c in allClasses) if (set.contains(c)) ...store.studentsOf(c)];
      // Kısa quiz formu yalnız bu sınavın şubesine isimli basılır.
      final cls = store.studentsOf(exam.className);
      var copies = 10;
      var alternate = true;
      var picked = allClasses.any((c) => store.studentsOf(c).isNotEmpty) ? 'named' : 'blank';
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
                  ListTile(
                    title: Text(tr('Optik form yazdır'), style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(tr('A4, %100 ölçekle yazdırın. Önce önizleme açılır.')),
                  ),
                  Builder(builder: (_) {
                    final cls = studentsIn(chosen);
                    return ListTile(
                      enabled: allClasses.length > 1 || cls.isNotEmpty,
                      leading: const Icon(Icons.badge_outlined),
                      title: Text(tr('İsimli öğrenci formları')),
                      subtitle: Text(
                        cls.isEmpty
                            ? tr('Seçilen sınıflarda kayıtlı öğrenci yok')
                            : chosen.length > 1
                                ? tr('{0} sınıf · {1} öğrenci · ad, sınıf ve numara basılı gelir', [chosen.length, cls.length])
                                : tr('{0} öğrenci · ad, sınıf ve numara basılı gelir', [cls.length]),
                      ),
                      selected: picked == 'named',
                      trailing: Icon(picked == 'named' ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                      onTap: () => setSheet(() => picked = 'named'),
                    );
                  }),
                  if (allClasses.length > 1)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(72, 0, 16, 6),
                      child: Wrap(spacing: 6, runSpacing: 4, children: [
                        FilterChip(
                          label: Text(tr('Tüm sınıflar')),
                          selected: chosen.length == allClasses.length,
                          onSelected: (v) => setSheet(() {
                            chosen
                              ..clear()
                              ..addAll(v ? allClasses : [exam.className]);
                            picked = 'named';
                          }),
                        ),
                        for (final c in allClasses)
                          FilterChip(
                            label: Text(c),
                            selected: chosen.contains(c),
                            onSelected: (v) => setSheet(() {
                              v ? chosen.add(c) : chosen.remove(c);
                              picked = 'named';
                            }),
                          ),
                      ]),
                    ),
                  if (exam.hasBooklets && studentsIn(chosen).isNotEmpty)
                    SwitchListTile(
                      contentPadding: const EdgeInsets.only(left: 72, right: 16),
                      value: alternate,
                      onChanged: (v) => setSheet(() => alternate = v),
                      title: Text(tr('Kitapçıkları sırayla {0} dağıt', [[for (var b = 0; b < exam.bookletCount; b++) Exam.bookletLetter(b)].join(', ')])),
                      subtitle: Text(tr('Kapalıysa öğrenci kitapçığını formda kendisi işaretler')),
                    ),
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(tr('Boş öğrenci formu')),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final n in const [1, 10, 20, 30, 40])
                            ChoiceChip(
                              label: Text(tr('{0} adet', [n])),
                              selected: copies == n,
                              onSelected: (_) => setSheet(() {
                                copies = n;
                                picked = 'blank';
                              }),
                            ),
                        ],
                      ),
                    ),
                    selected: picked == 'blank',
                    trailing: Icon(picked == 'blank' ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                    onTap: () => setSheet(() => picked = 'blank'),
                  ),
                  ListTile(
                    enabled: miniFormAllowed(exam),
                    leading: const Icon(Icons.grid_view_rounded),
                    title: Text(tr('Kısa quiz formu (4\'ü bir A4\'te)')),
                    subtitle: Text(miniFormAllowed(exam)
                        ? (cls.isNotEmpty
                            ? tr('Çeyrek A4, QR kodlu · {0} öğrenciye isimli basılır, kesip dağıtın', [cls.length])
                            : tr('Çeyrek A4, QR kodlu · {0} adet boş form, kesip dağıtın', [copies < 4 ? 4 : copies]))
                        : tr('En fazla {0} soruluk, tek kitapçıklı Netice formlu sınavlarda', [MiniFormLayout.maxQuestionsFor(exam.numberDigits)])),
                    selected: picked == 'mini',
                    trailing: Icon(picked == 'mini' ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                    onTap: () => setSheet(() => picked = 'mini'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.key_outlined),
                    title: Text(tr('Cevap anahtarı')),
                    subtitle: Text(tr('Doğru şıklar karartılmış form ve anahtar listesi')),
                    selected: picked == 'key',
                    trailing: Icon(picked == 'key' ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                    onTap: () => setSheet(() => picked = 'key'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.edit_note_outlined),
                    title: Text(tr('Boş cevap anahtarı formu')),
                    subtitle: Text(tr('Elle doldurup Sınav ayarlarından fotoğrafla okutun')),
                    selected: picked == 'keyBlank',
                    trailing: Icon(picked == 'keyBlank' ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                    onTap: () => setSheet(() => picked = 'keyBlank'),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Row(children: [
                      Expanded(
                        child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Vazgeç'))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(ctx, picked),
                          icon: const Icon(Icons.check_rounded),
                          label: Text(tr('Tamam, önizle')),
                        ),
                      ),
                    ]),
                  ),
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
          final classes = [for (final c in allClasses) if (chosen.contains(c) && store.studentsOf(c).isNotEmpty) c];
          if (classes.isEmpty) return toast(context, tr('Seçilen sınıflarda kayıtlı öğrenci yok'));
          final created = classes.where((c) => c != exam.className && !store.exams.any((e) => e.isCommon && e.commonId == exam.commonId && e.className == c)).length;
          // Her şubenin formu o şubenin sınavıyla basılır; yoksa ortak sınav olarak açılır.
          final groups = [for (final c in classes) (examForClass(store, exam, c), store.studentsOf(c))];
          if (created > 0) toast(context, tr('{0} sınıf için aynı sınav açıldı. Sonuçlar ortak raporda birleşir.', [created]));
          await ReportPreviewScreen.open(
            context,
            title: tr('Öğrenci formları'),
            fileName: '${name}_optik_form.pdf',
            build: () => buildClassFormsPdf(groups, school: store.reportSchool, alternateBooklets: alternate),
          );
        case 'blank':
          await ReportPreviewScreen.open(
            context,
            title: tr('Boş optik form ({0} adet)', [copies]),
            fileName: '${name}_bos_form_$copies.pdf',
            build: () => buildFormsPdf(exam, const [], blankCopies: copies, school: store.reportSchool),
          );
        case 'mini':
          await ReportPreviewScreen.open(
            context,
            title: tr('Kısa quiz formu'),
            fileName: '${name}_kisa_quiz_formu.pdf',
            build: () => buildMiniFormsPdf(exam, cls, blankCopies: copies < 4 ? 4 : copies, school: store.reportSchool),
          );
        case 'key':
          await ReportPreviewScreen.open(
            context,
            title: tr('Cevap anahtarı'),
            fileName: '${name}_cevap_anahtari.pdf',
            build: () => buildAnswerKeyPdf(exam, school: store.reportSchool),
          );
        case 'keyBlank':
          await ReportPreviewScreen.open(
            context,
            title: tr('Boş cevap anahtarı formu'),
            fileName: '${name}_bos_anahtar.pdf',
            build: () => buildAnswerKeyPdf(exam, filled: false, school: store.reportSchool),
          );
      }
    }

    Future<void> pdfReport() async {
      if (results.isEmpty) return toast(context, tr('Rapor için önce kâğıt okutun.'));
      await ReportPreviewScreen.open(context,
          title: tr('Sınav raporu'),
          fileName: '${_safe(exam.name)}_sinav_raporu.pdf',
          build: () => buildResultsPdf(
              exam: exam,
              results: results,
              students: store.studentById,
              school: store.reportSchool,
              classHistory: exam.kidStyle ? classHistoryOf(store, exam) : const []));
    }

    Future<void> studentCards() async {
      if (results.isEmpty) return toast(context, tr('Karne için önce kâğıt okutun.'));
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
      if (cls.isEmpty) return toast(context, tr('Bu sınıfta kayıtlı öğrenci yok.'));
      final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(title: Text(tr('e-Okul not giriş listesi'), style: TextStyle(fontWeight: FontWeight.w800))),
            ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: Text(tr('PDF (yazdırmak için)')),
                onTap: () => Navigator.pop(ctx, 'pdf')),
            ListTile(
                leading: const Icon(Icons.table_view_outlined),
                title: Text(tr('Excel')),
                onTap: () => Navigator.pop(ctx, 'xls')),
          ]),
        ),
      );
      if (choice == 'pdf') {
        if (!context.mounted) return;
        await ReportPreviewScreen.open(context,
            title: tr('e-Okul listesi'),
            fileName: '${_safe(exam.name)}_eokul.pdf',
            build: () => buildEokulPdf(exam: exam, results: results, classStudents: cls, school: store.reportSchool));
      } else if (choice == 'xls') {
        await FilePicker.saveFile(
          fileName: '${_safe(exam.name)}_eokul.csv',
          bytes: Uint8List.fromList(utf8.encode(eokulCsv(exam, results, cls))),
          mimeType: 'text/csv',
        );
      }
    }

    Future<void> labels() async {
      if (results.isEmpty) return toast(context, tr('Etiket için önce kâğıt okutun.'));
      await ReportPreviewScreen.open(context,
          title: tr('Sonuç etiketleri'),
          fileName: '${_safe(exam.name)}_etiketler.pdf',
          build: () => buildLabelsPdf(exam: exam, results: results, students: store.studentById));
    }

    final actions = [
      _Action(Icons.print_outlined, tr('Form yazdır'), printForms),
      if (exam.hasOpen)
        _Action(Icons.edit_note_rounded, tr('Klasik puan gir'), () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => OpenScoresScreen(examId: exam.id)));
        }),
      _Action(Icons.picture_as_pdf_outlined, tr('Sınav raporu'), pdfReport),
      _Action(Icons.badge_outlined, tr('Öğrenci karnesi'), studentCards),
      _Action(Icons.table_view_outlined, tr('Excel'), excel),
      _Action(Icons.school_outlined, tr('e-Okul listesi'), eokul),
      _Action(Icons.label_outline, tr('Sonuç etiketi'), labels),
      _Action(Icons.assignment_ind_outlined, tr('Kişiye özel tekrar testi'), () => openPersonalReview(context, exam)),
      _Action(Icons.forward_to_inbox_rounded, tr('Velilere toplu gönder'), () => openBulkParentSend(context, exam)),
      _Action(Icons.hub_outlined, exam.isCommon ? tr('Ortak sınav') : tr('Ortak sınav yap'), () => openCommonExamMenu(context, exam)),
    ];

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(exam.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('${exam.className} · ${dmy(exam.date)} ${hm(exam.date)} · ${tr('{0} soru', [exam.questionCount])}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall),
          ]),
          actions: [
            IconButton(
              tooltip: tr('Sınav ayarları'),
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
            Tab(text: tr('Sonuçlar')),
            Tab(text: tr('Analiz')),
            Tab(text: review > 0 ? '${tr('Kontrol')} ($review)' : tr('Kontrol')),
          ]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: NColors.emerald,
          foregroundColor: NColors.ink,
          onPressed: () => Navigator.of(context).push(scanRoute(exam.id)),
          icon: const Icon(Icons.document_scanner_outlined),
          label: Text(tr('Okut'), style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        bottomNavigationBar: const AdBannerBar(AdPage.exam),
        body: Watermark(child: TabBarView(children: [
          _ResultsTab(exam: exam, results: results),
          _AnalysisTab(exam: exam, results: results, reports: actions.where((a) => a.label != tr('Form yazdır') && a.label != tr('Klasik puan gir') && a.icon != Icons.hub_outlined).toList()),
          SafeArea(top: false, child: ReviewList(exam: exam)),
        ])),
      ),
    );
  }
}

/// "Ne yapmalı?" kartı: sınav sonrası öğretmene somut adımlar.
List<Widget> _actionPlan(BuildContext context, ExamReport rep) {
  final plan = classActionPlan(rep, StoreScope.of(context).studentById);
  if (plan.isEmpty) return const [];
  return [
    SectionTitle(tr('Ne yapmalı?')),
    Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < plan.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsetsDirectional.only(end: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: NColors.emerald.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800, color: NColors.emerald, fontSize: 12)),
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(plan[i].title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(plan[i].detail),
                  ]),
                ),
              ]),
            ),
          Text(tr('Bu öneriler cihazınızda, sonuçlarınızdan üretildi; hiçbir veri dışarı gönderilmedi.'),
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55))),
        ]),
      ),
    ),
  ];
}

/// Karneler için gelişim notları (öğrencinin tüm sınavlarına bakılarak).
Map<String, List<String>> developmentNotes(AppStore store, Iterable<String?> ids) => {
      for (final id in ids)
        if (id != null && store.studentById[id] != null) id: studentDevelopmentNote(historyOf(store, store.studentById[id]!)),
    };

/// Çocuk karnelerindeki gelişim grafiği için öğrencilerin tüm sınavları.
Map<String, List<HistoryEntry>> developmentHistory(AppStore store, Exam exam, Iterable<String?> ids) => {
      if (exam.kidStyle)
        for (final id in ids)
          if (id != null && store.studentById[id] != null)
            id: historyOf(store, store.studentById[id]!).where((h) => !h.exam.date.isAfter(exam.date)).toList(),
    };

/// Aynı sınıfın bu sınava kadarki sınavları (ad, sınıf ortalaması yüzdesi).
List<(String, double)> classHistoryOf(AppStore store, Exam exam) {
  final exams = store.exams
      .where((e) => e.className.trim() == exam.className.trim() && !e.date.isAfter(exam.date))
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  return [
    for (final e in exams)
      if (store.resultsOf(e).isNotEmpty && e.rule.maxScore > 0)
        (e.name, ExamReport.build(e, store.resultsOf(e)).stats.mean / e.rule.maxScore * 100),
  ];
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
      return Center(
        child: SingleChildScrollView(
          child: EmptyState(
            kind: IllustrationKind.scan,
            title: tr('Henüz okunan kâğıt yok'),
            message: tr('Aşağıdaki "Okut" düğmesine dokunun ve kâğıtları sırayla kameraya gösterin. Formları henüz basmadıysanız önce "Form yazdır"ı kullanın.'),
          ),
        ),
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final openMissing = exam.hasOpen ? results.where((r) => r.openMissing).length : 0;
    final absent = store.missingStudents(exam);
    return ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 100), children: [
      if (absent.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Card(
            color: NColors.amber.withValues(alpha: 0.10),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              leading: const Icon(Icons.person_search_rounded, color: NColors.amber),
              title: Text(tr('{0} öğrencinin kâğıdı okutulmadı', [absent.length]),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(tr('Sınava girmediyse sorun yok; kâğıt atlandıysa okutun.')),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              expandedAlignment: Alignment.centerLeft,
              children: [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final s in absent) Chip(label: Text('${s.number} · ${s.fullName}')),
                ]),
              ],
            ),
          ),
        ),
      if (openMissing > 0)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Card(
            color: NColors.amber.withValues(alpha: 0.14),
            child: ListTile(
              leading: const Icon(Icons.edit_note_rounded, color: NColors.amber),
              title: Text(tr('{0} öğrencinin klasik puanı eksik', [openMissing]),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(tr('Puanlar girilene kadar toplamda yalnızca test kısmı görünür.')),
              trailing: FilledButton(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => OpenScoresScreen(examId: exam.id))),
                child: Text(tr('Gir')),
              ),
            ),
          ),
        ),
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
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(tr('SINIF ORTALAMASI'),
                    maxLines: 1,
                    style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 22, runSpacing: 12, children: [
                _HeroStat(tr('Medyan'), fmt1(st.median)),
                _HeroStat(tr('Std. sapma'), fmt1(st.stdDev)),
                _HeroStat('KR-20', st.kr20 == null ? '–' : fmt2(st.kr20!)),
                _HeroStat(tr('Okunan'), '${st.count}'),
              ]),
            ]),
          ),
        ]),
      ),
      SectionTitle(tr('Puan dağılımı')),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _Histogram(st.histogram),
        ),
      ),
      SectionTitle(tr('Öğrenciler')),
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
              title: Text(students[sorted[i].sheet.studentId]?.fullName ?? tr('Eşleşmeyen kâğıt'),
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
      const AdSlot.card(AdPage.exam, padding: EdgeInsets.only(top: 16)),
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
          Text(st?.fullName ?? tr('Eşleşmeyen kâğıt'), style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          Text('${tr('No')} ${st?.number ?? '–'} · ${tr('Puan')} ${fmt1(r.score)} · ${tr('Net')} ${fmt2(r.net)}'),
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
                label: Text(tr('Öğrenci geçmişi ve gelişimi')),
              ),
            ),
          if (hasSheetImage(context, r.sheet))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  openSheetImage(context, exam, r);
                },
                icon: const Icon(Icons.image_search_rounded, size: 18),
                label: Text(tr('İşaretli kâğıdı gör')),
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
                label: Text(tr('Karneyi önizle')),
              ),
            ),
          if (st != null && r.outcomes.any((o) => o == Outcome.wrong || o == Outcome.blank))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  openPersonalReview(context, exam, onlyStudentId: st.id);
                },
                icon: const Icon(Icons.assignment_ind_outlined, size: 18),
                label: Text(tr('Kişiye özel tekrar testi')),
              ),
            ),
          if (st != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => shareStudentCard(context, exam, st.id),
                icon: const Icon(Icons.send_outlined, size: 18),
                label: Text(tr('Karneyi veliye gönder')),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () {
                Navigator.pop(ctx);
                deleteSheetWithUndo(context, r.sheet);
              },
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: Text(tr('Bu okumayı sil')),
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
    if (results.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          child: EmptyState(
            kind: IllustrationKind.results,
            title: tr('Analiz kâğıtları bekliyor'),
            message: tr('Kâğıtları okuttuğunuzda başarı dağılımı, soru analizi ve kazanım başarısı burada belirir.'),
          ),
        ),
      );
    }
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
                Text(tr('Doğru oranı %{0} · {1}', [(it.p * 100).round(), it.difficultyLabel]),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (code != null && code.isNotEmpty) Text(code, style: t.textTheme.bodySmall?.copyWith(color: muted)),
                const SizedBox(height: 2),
                Text(
                  warn
                      ? tr('! Üst grubun çoğu {0} şıkkını seçti; anahtarı kontrol edin', [letter(it.suspiciousChoice!)])
                      : tr('Ayırt edicilik {0} · {1}', [fmt2(it.d), it.discriminationLabel]),
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
                  Text(tr('Boş: {0}', [it.blankCount]), style: const TextStyle(color: NColors.gray)),
                ]),
                if (it.nonFunctional.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(tr('İşlevsiz çeldirici: {0} (kimse seçmedi)', [it.nonFunctional.map(letter).join(', ')]),
                        style: t.textTheme.bodySmall?.copyWith(color: muted)),
                  ),
              ]),
            ),
            if (warn)
              IconButton(
                tooltip: tr('Bu soruyu iptal et'),
                icon: const Icon(Icons.block),
                onPressed: () => _cancelQuestion(context, it.no),
              ),
          ]),
        ),
      );
    }

    final kr = s.kr20;
    final stats = <StatCard>[
      StatCard(label: tr('Ortalama'), value: fmt1(s.mean), hint: tr('Medyan {0}', [fmt1(s.median)]), icon: Icons.functions),
      StatCard(
          label: tr('Başarı oranı'),
          value: L10n.percent((rep.passRate * 100).round()),
          hint: tr('Geçme puanı {0} ve üzeri', [exam.rule.pass.round()]),
          icon: Icons.emoji_events_outlined),
      StatCard(label: tr('En yüksek'), value: fmt1(s.max), hint: tr('En düşük {0}', [fmt1(s.min)]), icon: Icons.trending_up),
      StatCard(
          label: tr('Std. sapma'),
          value: fmt1(s.stdDev),
          hint: rep.cv == null ? null : tr('Değişim %{0}', [rep.cv!.round()]),
          icon: Icons.stacked_line_chart),
      StatCard(
          label: tr('Çeyrekler'),
          value: '${fmt1(rep.q1)}–${fmt1(rep.q3)}',
          hint: tr('Ortadaki yarı'),
          icon: Icons.align_horizontal_center),
      StatCard(
          label: tr('Ortalama net'),
          value: fmt2(rep.meanNet),
          hint: '${fmt1(rep.meanCorrect)} ${tr('D')} · ${fmt1(rep.meanWrong)} ${tr('Y')} · ${fmt1(rep.meanBlank)} ${tr('B')}',
          icon: Icons.check_circle_outline),
      StatCard(
          label: tr('Güvenirlik'),
          value: kr == null ? '–' : fmt2(kr),
          hint: kr == null
              ? tr('KR-20 hesaplanamadı')
              : kr >= 0.8
                  ? tr('KR-20 · yüksek')
                  : kr >= 0.7
                      ? tr('KR-20 · kabul edilebilir')
                      : tr('KR-20 · düşük'),
          accent: kr != null && kr < 0.7 ? NColors.amber : null,
          icon: Icons.verified_outlined),
      StatCard(
          label: tr('Ölçme hatası'),
          value: rep.sem == null ? '–' : '±${fmt1(rep.sem!)}',
          hint: tr('SEM, puan'),
          icon: Icons.blur_on),
      StatCard(label: tr('Güçlük (p)'), value: fmt2(rep.meanP), hint: tr('Doğru oranı'), icon: Icons.speed),
      StatCard(label: tr('Ayırt edicilik'), value: fmt2(rep.meanD), hint: tr('Üst − alt grup'), icon: Icons.compare_arrows),
      StatCard(label: tr('Üst %27 ort.'), value: fmt1(rep.upperMean), accent: NColors.emerald, icon: Icons.north_east),
      StatCard(label: tr('Alt %27 ort.'), value: fmt1(rep.lowerMean), accent: NColors.coral, icon: Icons.south_east),
    ];

    const levelColors = [NColors.emerald, Color(0xFF34D399), NColors.amber, Color(0xFFF59E0B), NColors.coral];

    return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 100), children: [
      HeroPanel(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('RAPOR AL'),
              style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
          const SizedBox(height: 4),
          Text(tr('Grafikli sınav raporu, öğrenci karneleri ve Excel listesi'),
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
      SectionTitle(tr('Genel istatistikler')),
      GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 240, mainAxisExtent: 134, crossAxisSpacing: 12, mainAxisSpacing: 12),
        children: stats,
      ),
      SectionTitle(tr('Otomatik değerlendirme')),
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
      ..._actionPlan(context, rep),
      if (!StoreScope.of(context).isPro) ...[
        SectionTitle(tr('Grafikler')),
        const ProLocked(ProFeature.advancedCharts),
      ] else ...[
      SectionTitle(tr('Grafikler')),
      _ChartsPanel(rep: rep),
      SectionTitle(tr('Puanların yayılımı')),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: BoxPlot(
              min: s.min, q1: rep.q1, median: s.median, q3: rep.q3, max: s.max, mean: s.mean, scaleMax: exam.rule.maxScore),
        ),
      ),
      SectionTitle(tr('Madde haritası')),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ItemMap(items: [
            for (final it in items)
              if (!exam.questions[it.no - 1].cancelled) (it.no, it.p, it.d)
          ]),
        ),
      ),
      if (rep.outcomes.length >= 3) ...[
        SectionTitle(tr('Kazanım radarı')),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              RadarChart(axes: [for (final o in rep.outcomes) (o.code, o.rate)]),
              Text(tr('Yeşil alan: sınıfın doğru oranı · sarı çizgi: %70 hedef'),
                  style: t.textTheme.bodySmall?.copyWith(color: muted)),
            ]),
          ),
        ),
      ],
      ],
      SectionTitle(tr('Başarı düzeyleri')),
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
      SectionTitle(tr('Soru güçlük grafiği')),
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _DifficultyChart(exam: exam, items: items),
            const SizedBox(height: 8),
            Text(tr('Çubuk: doğru oranı · yeşil kolay, lacivert orta, mercan zor'),
                style: t.textTheme.bodySmall?.copyWith(color: muted)),
          ]),
        ),
      ),
      SectionTitle(tr('Soru kalitesi')),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Güçlük'), style: t.textTheme.labelLarge?.copyWith(color: muted)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in rep.difficultyCounts.entries) Chip(label: Text('${e.key}: ${e.value}')),
            ]),
            const SizedBox(height: 12),
            Text(tr('Ayırt edicilik'), style: t.textTheme.labelLarge?.copyWith(color: muted)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in rep.discriminationCounts.entries) Chip(label: Text('${e.key}: ${e.value}')),
            ]),
          ]),
        ),
      ),
      SectionTitle(tr('Kazanım / konu analizi'),
          trailing: TextButton.icon(
            onPressed: () => _editOutcomes(context),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: Text(tr('Düzenle')),
          )),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: rep.outcomes.isEmpty
              ? Text(tr('Soruları konulara bağlarsanız her konunun başarısı burada ve raporda görünür. "Düzenle"ye dokunun.'),
                  style: TextStyle(color: muted))
              : Column(children: [
                  for (final o in [...rep.outcomes]..sort((a, b) => a.rate.compareTo(b.rate)))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                              child: Text('${o.code}  ·  ${tr('{0} soru', [o.questionNos.length])}',
                                  style: const TextStyle(fontWeight: FontWeight.w600))),
                          Text(L10n.percent((o.rate * 100).round()),
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
      if (rep.outcomes.isNotEmpty) WeakTopicsCard(exam: exam, results: rep.results),
      if (rep.outcomes.isNotEmpty) ...[
        SectionTitle(tr('Kazanım ısı haritası')),
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
          child: Text(tr('{0} öğrenci ile madde istatistikleri güvenilir değildir; yol gösterici olarak okuyun.', [results.length]),
              style: t.textTheme.bodySmall?.copyWith(color: NColors.amber)),
        ),
      SectionTitle(tr('En çok yanlış yapılan sorular')),
      for (final it in worst.take(5)) Padding(padding: const EdgeInsets.only(bottom: 10), child: itemCard(it)),
      SectionTitle(tr('Tüm sorular')),
      for (final it in items) Padding(padding: const EdgeInsets.only(bottom: 10), child: itemCard(it)),
    ]);
  }

  Future<void> _editOutcomes(BuildContext context) async {
    final store = StoreScope.of(context);
    final ctrl = TextEditingController(text: formatOutcomeRanges(exam));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Kazanımlar / konular')),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            minLines: 4,
            maxLines: 10,
            decoration: InputDecoration(
              hintText: tr('1-5 Hareket\n6-10 Kuvvet'),
              helperText: tr('Her satıra soru aralığı ve konu adı yazın.'),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Vazgeç'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Kaydet'))),
        ],
      ),
    );
    if (ok != true) return;
    final m = parseOutcomeRanges(ctrl.text, exam.questionCount);
    store.upsertExam(exam.copyWith(questions: [
      for (final q in exam.questions)
        Question(no: q.no, correct: q.correct, points: q.points, cancelled: q.cancelled, outcomeCode: m[q.no]),
    ]));
    if (context.mounted) toast(context, tr('Kazanımlar kaydedildi.'));
  }

  void _cancelQuestion(BuildContext context, int no) {
    final store = StoreScope.of(context);
    final qs = [...exam.questions];
    qs[no - 1] = qs[no - 1].copyWith(cancelled: true);
    store.upsertExam(exam.copyWith(questions: qs));
    toast(context, tr('{0}. soru iptal edildi; tüm puanlar yeniden hesaplandı.', [no]));
  }
}

/// Dokunmatik pasta/halka grafikler: düzeyler, cevaplar, geçme, güçlük.
class _ChartsPanel extends StatefulWidget {
  final ExamReport rep;
  const _ChartsPanel({required this.rep});
  @override
  State<_ChartsPanel> createState() => _ChartsPanelState();
}

class _ChartsPanelState extends State<_ChartsPanel> {
  int _tab = 0;
  static List<String> get _tabs => [tr('Düzeyler'), tr('Cevaplar'), tr('Geçme'), tr('Güçlük')];
  static const _levelPalette = [NColors.emerald, Color(0xFF34D399), NColors.amber, Color(0xFFF59E0B), NColors.coral];

  /// Düzey sayısı not sistemine göre değişir; renkler yeşilden kırmızıya yayılır.
  static Color _levelColor(int i) {
    final n = Level.all.length;
    return _levelPalette[n <= 1 ? 0 : (i * (_levelPalette.length - 1) / (n - 1)).round()];
  }

  @override
  Widget build(BuildContext context) {
    final rep = widget.rep;
    final n = rep.results.length;
    final passed = rep.standings.where((x) => x.result.score >= rep.exam.rule.pass).length;
    final c = rep.results.fold<int>(0, (a, r) => a + r.correct);
    final w = rep.results.fold<int>(0, (a, r) => a + r.wrong);
    final b = rep.results.fold<int>(0, (a, r) => a + r.blank);
    final chart = switch (_tab) {
      0 => DonutChart(key: const ValueKey(0), pie: true, centerLabel: tr('öğrenci'), unit: tr(' kişi'), slices: [
          for (var i = 0; i < Level.all.length; i++)
            Slice(Level.all[i].name, rep.levelCounts[i].toDouble(), _levelColor(i),
                detail: tr('{0}: tam puanın %{1} ve üzeri', [Level.all[i].name, Level.all[i].minPct.round()])),
        ]),
      1 => DonutChart(key: const ValueKey(1), centerLabel: 'cevap', slices: [
          Slice(tr('Doğru'), c.toDouble(), NColors.emerald, detail: tr('Öğrenci başına {0} doğru', [fmt1(n == 0 ? 0 : c / n)])),
          Slice(tr('Yanlış'), w.toDouble(), NColors.coral, detail: tr('Öğrenci başına {0} yanlış', [fmt1(n == 0 ? 0 : w / n)])),
          Slice(tr('Boş'), b.toDouble(), NColors.gray, detail: tr('Öğrenci başına {0} boş', [fmt1(n == 0 ? 0 : b / n)])),
        ]),
      2 => DonutChart(key: const ValueKey(2), centerLabel: tr('öğrenci'), unit: tr(' kişi'), slices: [
          Slice(tr('Geçti'), passed.toDouble(), NColors.emerald, detail: tr('Geçme puanı {0}', [rep.exam.rule.pass.round()])),
          Slice(tr('Geçemedi'), (n - passed).toDouble(), NColors.coral),
        ]),
      _ => DonutChart(key: const ValueKey(3), centerLabel: tr('soru'), unit: ' ${tr('soru')}', slices: [
          Slice(tr('Kolay'), (rep.difficultyCounts[tr('Kolay')] ?? 0).toDouble(), NColors.emerald, detail: tr('Doğru oranı %80 üzeri')),
          Slice(tr('Orta'), (rep.difficultyCounts[tr('Orta')] ?? 0).toDouble(), NColors.ink, detail: tr('Doğru oranı %30–80')),
          Slice(tr('Zor'), (rep.difficultyCounts[tr('Zor')] ?? 0).toDouble(), NColors.coral, detail: tr('Doğru oranı %30 altı')),
        ]),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (var i = 0; i < _tabs.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(_tabs[i]),
                    selected: _tab == i,
                    onSelected: (_) => setState(() => _tab = i),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: chart),
          const SizedBox(height: 6),
          Text(tr('Dilime veya açıklamaya dokunarak ayrıntıyı görün.'),
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55))),
        ]),
      ),
    );
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
        message: cancelled ? tr('{0}. soru iptal', [it.no]) : tr('{0}. soru: %{1} doğru', [it.no, (p * 100).round()]),
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
          child: Text(L10n.percent((v * 100).round()),
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
          name(students[st.result.sheet.studentId]?.fullName ?? tr('Eşleşmeyen kâğıt')),
          for (final o in rep.outcomes) cell(o.rateOf(rep.exam, st.result)),
        ]),
      Row(children: [
        name(tr('Sınıf'), bold: true),
        for (final o in rep.outcomes) cell(o.rate, bold: true),
      ]),
    ]);
  }
}

/// Öğrenci karnesi önizlemesini açar; [studentId] verilirse o öğrenciyle başlar.
Future<void> openCardsPreview(BuildContext context, Exam exam, {String? studentId}) async {
  if (!await requirePro(context, ProFeature.studentCards) || !context.mounted) return;
  final store = StoreScope.of(context);
  final results = store.resultsOf(exam);
  final byId = store.studentById;
  final students = [
    for (final r in results)
      if (byId[r.sheet.studentId] != null) (byId[r.sheet.studentId]!.id, byId[r.sheet.studentId]!.fullName),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => StudentCardsPreview(
      title: tr('Öğrenci karnesi'),
      baseFileName: '${_safe(exam.name)}_karne',
      students: students,
      initialStudentId: studentId,
      build: (id) => buildStudentCardsPdf(
          exam: exam,
          results: results,
          students: byId,
          onlyStudentId: id,
          school: store.reportSchool,
          notes: developmentNotes(store, id == null ? results.map((r) => r.sheet.studentId) : [id]),
          history: developmentHistory(store, exam, id == null ? results.map((r) => r.sheet.studentId) : [id]),
          studyTopics: BankAnalysis.studyTopics(exam, results, BankStore.instance, only: id == null ? null : [id])),
    ),
  ));
}

/// Tek öğrencinin karnesini PDF olarak oluşturup telefonun paylaşım
/// menüsünü açar (WhatsApp, e-posta, Drive…). Hazır bir veli mesajı eklenir.
/// Paylaşım menüsü açıldıysa true döner.
Future<bool> shareStudentCard(BuildContext context, Exam exam, String studentId, {bool askPro = true}) async {
  if (askPro && (!await requirePro(context, ProFeature.parentShare) || !context.mounted)) return false;
  final store = StoreScope.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final st = store.studentById[studentId];
  final results = store.resultsOf(exam);
  final r = results.where((x) => x.sheet.studentId == studentId).firstOrNull;
  if (st == null || r == null) return false;
  try {
    final bytes = await buildStudentCardsPdf(
        exam: exam,
        results: results,
        students: store.studentById,
        onlyStudentId: studentId,
        school: store.reportSchool,
        notes: developmentNotes(store, [studentId]),
        history: developmentHistory(store, exam, [studentId]),
        studyTopics: BankAnalysis.studyTopics(exam, results, BankStore.instance, only: [studentId]));
    final rep = ExamReport.build(exam, results);
    await Printing.sharePdf(
      bytes: bytes,
      filename: '${_safe(st.fullName)}_${_safe(exam.name)}_karne.pdf',
      subject: tr('{0} – {1} sınav karnesi', [st.fullName, exam.name]),
      body: parentMessage(store, exam, st, r, rep.stats.mean),
    );
    return true;
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(tr('Karne paylaşılamadı: {0}', [e]))));
    return false;
  }
}

/// Veliye gidecek hazır mesaj. [withSummary] ise karne eki olmadan da
/// anlaşılsın diye zayıf konular da yazılır (WhatsApp'ta yalnız mesaj).
String parentMessage(AppStore store, Exam exam, Student st, Result r, double classMean, {bool withSummary = false}) {
  final school = store.school.name.trim();
  final teacher = store.school.teacher.trim().isEmpty ? tr('Ders öğretmeni') : store.school.teacher.trim();
  if (!withSummary) {
    return tr('Sayın Velimiz,\n\n{0} adlı öğrencimizin "{1}" ({2}) sınav karnesi ektedir.\nPuanı: {3} / {4} · Sınıf ortalaması: {5}\n\nSaygılarımızla,\n{6}{7}{8}', [st.fullName, exam.name, dmy(exam.date), fmt1(r.score), fmt1(exam.rule.maxScore), fmt1(classMean), teacher, school.isEmpty ? '' : '\n$school', downloadSignature]);
  }
  final weak = BankAnalysis.studyTopics(exam, [r], BankStore.instance, only: [st.id])[st.id] ?? const [];
  final topics = weak.isEmpty ? '' : tr('\nÇalışması gereken konular: {0}', [weak.map((w) => w.$1).join(', ')]);
  return tr('Sayın Velimiz,\n\n{0} adlı öğrencimizin "{1}" ({2}) sınav sonucu:\nPuanı: {3} / {4} · Doğru {5}, yanlış {6}, boş {7} · Sınıf ortalaması: {8}{9}\n\nSaygılarımızla,\n{10}{11}', [st.fullName, exam.name, dmy(exam.date), fmt1(r.score), fmt1(exam.rule.maxScore), r.correct, r.wrong, r.blank, fmt1(classMean), topics, teacher, school.isEmpty ? '' : '\n$school']);
}

/// Tek okunan kâğıdı onay alarak siler; öğrenci bilgileri kalır. Geri alınabilir.
Future<void> deleteSheetWithUndo(BuildContext context, Sheet sheet) async {
  final store = StoreScope.of(context);
  final name = store.studentById[sheet.studentId]?.fullName;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Bu okuma silinsin mi?')),
      content: Text(name == null
          ? tr('Yalnızca bu kâğıdın okuma sonucu silinir. Öğrencileriniz ve sınıflarınız olduğu gibi kalır; kâğıdı yeniden okutabilirsiniz.')
          : tr('{0} için okunan kâğıt silinir. Öğrenci kaydı ve diğer sınavları olduğu gibi kalır; kâğıdı yeniden okutabilirsiniz.', [name])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Vazgeç'))),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.delete_outline_rounded),
          label: Text(tr('Sil')),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final index = store.removeSheet(sheet);
  if (index < 0) return;
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger
      .showSnackBar(SnackBar(
        content: Text(tr('Okuma silindi.')),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(label: tr('Geri al'), onPressed: () => store.restoreSheet(index, sheet)),
      ))
      .closed
      .then((reason) {
    if (reason != SnackBarClosedReason.action) store.forgetRemoved();
  });
}
