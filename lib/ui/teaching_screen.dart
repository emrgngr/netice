import 'package:material_ui/material_ui.dart';

import '../core/misconceptions.dart';
import '../core/models.dart';
import '../core/pro.dart';
import '../core/scoring.dart';
import '../core/teaching.dart';
import '../l10n/l10n.dart';
import '../main.dart';
import '../reports/pdf_documents.dart';
import 'pro_screen.dart';
import 'report_preview_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Sınav sonrası öğretim önerileri: kavram yanılgıları, çalışma grupları ve
/// benzer yanlış uyarısı.
class TeachingScreen extends StatelessWidget {
  final String examId;
  final int initialTab;
  const TeachingScreen({super.key, required this.examId, this.initialTab = 0});

  static Future<void> open(BuildContext context, Exam exam, {int tab = 0}) {
    if (StoreScope.of(context).resultsOf(exam).isEmpty) {
      toast(context, tr('Önce kâğıt okutun.'));
      return Future.value();
    }
    return Navigator.of(context).push(MaterialPageRoute(builder: (_) => TeachingScreen(examId: exam.id, initialTab: tab)));
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final exam = store.examById(examId);
    if (exam == null) return const Scaffold();
    return DefaultTabController(
      length: 3,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Öğretim önerileri')),
            Text('${exam.name} · ${exam.className}', style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
          bottom: TabBar(isScrollable: true, tabs: [
            Tab(text: tr('Kavram yanılgıları')),
            Tab(text: tr('Çalışma grupları')),
            Tab(text: tr('Benzer yanlışlar')),
          ]),
        ),
        body: SafeArea(
          child: TabBarView(children: [
            _MisconceptionTab(exam: exam),
            _GroupsTab(exam: exam),
            _SimilarTab(exam: exam),
          ]),
        ),
      ),
    );
  }
}

Widget _page(List<Widget> children) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: children),
      ),
    );

Widget _intro(BuildContext context, IconData icon, String text) => Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IconBadge(icon, size: 34),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75)))),
        ]),
      ),
    );

// ———————————————————————————— Kavram yanılgıları

class _MisconceptionTab extends StatelessWidget {
  final Exam exam;
  const _MisconceptionTab({required this.exam});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final sheets = store.sheetsOf(exam.id);
    final students = store.studentById;
    final findings = Misconceptions.of(exam, sheets);
    final t = Theme.of(context);
    return _page([
      _intro(
          context,
          Icons.psychology_outlined,
          tr('Her yanlış şık bir düşünme hatasını yakalar. Yanlış şıklara hangi yanılgıyı ölçtüğünü yazın; Netice bu şıkları seçen öğrencileri yanılgıya göre toplar. Karnede de öğrencinin kendi yanılgıları görünür.')),
      const SizedBox(height: 12),
      FilledButton.tonalIcon(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MisconceptionEditor(examId: exam.id))),
        icon: const Icon(Icons.edit_note_rounded),
        label: Text(findings.isEmpty ? tr('Yanılgıları yaz') : tr('Yanılgıları düzenle')),
      ),
      const SizedBox(height: 12),
      if (findings.isEmpty)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
              tr('Bu sınavda henüz yanılgı yazılmamış. Sorular soru bankasından geliyorsa yanılgıları soru düzenleyicide bir kez yazmanız yeterli.'),
              style: t.textTheme.bodyMedium),
        )
      else if (!store.isPro)
        const ProLocked(ProFeature.misconceptions)
      else
        for (final f in findings)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ExpansionTile(
              leading: CircleAvatar(
                backgroundColor: (f.students.length / sheets.length >= 0.3 ? NColors.coral : NColors.amber).withValues(alpha: 0.18),
                child: Text('${f.students.length}', style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              title: Text(f.text, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(tr('{0} öğrenci (%{1}) · sorular: {2}',
                  [f.students.length, (f.students.length * 100 / sheets.length).round(), f.sources.map((x) => '${x.$1}${letter(x.$2)}').join(', ')])),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final id in f.students) Chip(label: Text(students[id]?.fullName ?? id), visualDensity: VisualDensity.compact),
                ]),
              ],
            ),
          ),
    ]);
  }
}

/// Sınavın sorularındaki yanlış şıklara yanılgı yazma ekranı.
class MisconceptionEditor extends StatefulWidget {
  final String examId;
  const MisconceptionEditor({super.key, required this.examId});

  @override
  State<MisconceptionEditor> createState() => _MisconceptionEditorState();
}

class _MisconceptionEditorState extends State<MisconceptionEditor> {
  late final Exam _exam = StoreScope.of(context).examById(widget.examId)!;
  late final List<List<TextEditingController>> _c = [
    for (final q in _exam.questions)
      [for (var k = 0; k < _exam.choiceCount; k++) TextEditingController(text: q.misconceptions[k] ?? '')],
  ];
  bool _dirty = false;

  @override
  void dispose() {
    for (final row in _c) {
      for (final c in row) {
        c.dispose();
      }
    }
    super.dispose();
  }

  void _save() {
    final store = StoreScope.of(context);
    final exam = store.examById(widget.examId) ?? _exam;
    store.upsertExam(exam.copyWith(questions: [
      for (var i = 0; i < exam.questions.length; i++)
        exam.questions[i].copyWith(misconceptions: {
          for (var k = 0; k < _c[i].length; k++)
            if (_c[i][k].text.trim().isNotEmpty && !exam.questions[i].correct.contains(k)) k: _c[i][k].text.trim()
        }),
    ]));
    _dirty = false;
    Navigator.pop(context);
    toast(context, tr('Yanılgılar kaydedildi.'));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (popped, _) async {
        if (popped) return;
        final r = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr('Değişiklikler kaydedilsin mi?')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Kaydetme'))),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Kaydet'))),
            ],
          ),
        );
        if (!context.mounted || r == null) return;
        if (r) {
          _save();
        } else {
          _dirty = false;
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('Kavram yanılgılarını yaz')),
          actions: [Padding(padding: const EdgeInsets.only(right: 10), child: FilledButton(onPressed: _save, child: Text(tr('Kaydet'))))],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                itemCount: _exam.questions.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                          tr('Yalnız yanılgısını bildiğiniz şıkları doldurun. Ör: "Kesirleri toplarken paydaları da topluyor". Doğru şıklar soluk görünür.'),
                          style: t.textTheme.bodySmall),
                    );
                  }
                  final q = _exam.questions[i - 1];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          [tr('{0}. soru', [q.no]), if ((q.outcomeCode ?? '').isNotEmpty) q.outcomeCode!, tr('Doğru: {0}', [q.correct.map(letter).join('/')])].join(' · '),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        for (var k = 0; k < _exam.choiceCount; k++)
                          if (!q.correct.contains(k))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: TextField(
                                controller: _c[i - 1][k],
                                onChanged: (_) => _dirty = true,
                                textCapitalization: TextCapitalization.sentences,
                                decoration: InputDecoration(
                                  isDense: true,
                                  prefixIcon: SizedBox(
                                      width: 36,
                                      child: Center(child: Text(letter(k), style: const TextStyle(fontWeight: FontWeight.w800)))),
                                  hintText: tr('{0} şıkkını seçen öğrencinin yanılgısı', [letter(k)]),
                                ),
                              ),
                            ),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ———————————————————————————— Çalışma grupları

class _GroupsTab extends StatelessWidget {
  final Exam exam;
  const _GroupsTab({required this.exam});

  static const _colors = {StudyTier.support: NColors.coral, StudyTier.reinforce: NColors.amber, StudyTier.enrich: NColors.emerald};
  static const _icons = {
    StudyTier.support: Icons.support_rounded,
    StudyTier.reinforce: Icons.fitness_center_rounded,
    StudyTier.enrich: Icons.rocket_launch_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    if (!store.isPro) {
      return _page([
        _intro(context, Icons.diversity_3_rounded,
            tr('Netice sınıfı sonuca göre üç gruba ayırır ve her gruba ne çalışacağını yazar. Bu, dünyada "farklılaştırılmış öğretim" ve "katmanlı destek" (RTI) olarak bilinen yöntemdir.')),
        const SizedBox(height: 12),
        const ProLocked(ProFeature.studyGroups),
      ]);
    }
    final results = store.resultsOf(exam);
    final groups = StudyGroups.of(exam, results);
    final students = store.studentById;
    return _page([
      _intro(context, Icons.diversity_3_rounded,
          tr('Sınıf sonuca göre üç gruba ayrıldı. Her grubun odaklanacağı kazanımlar ve önerilen çalışma aşağıda. Grupları derste köşe çalışması ya da etüt için kullanabilirsiniz.')),
      const SizedBox(height: 12),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          onPressed: () => ReportPreviewScreen.open(context,
              title: tr('Çalışma grupları'),
              fileName: 'calisma_gruplari.pdf',
              build: () => buildStudyGroupsPdf(exam: exam, groups: groups, students: students, school: store.reportSchool)),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: Text(tr('PDF olarak yazdır')),
        ),
      ),
      const SizedBox(height: 8),
      for (final g in groups)
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                IconBadge(_icons[g.tier]!, color: _colors[g.tier]!, size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(g.tier.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(g.tier.rule, style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ),
                Text(tr('{0} kişi', [g.members.length]), style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final m in g.members)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('${students[m.sheet.studentId]?.fullName ?? tr('Eşleşmedi')} · ${fmt1(m.score)}'),
                  ),
              ]),
              if (g.weakOutcomes.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(tr('Odaklanılacak kazanımlar'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                for (final (code, rate) in g.weakOutcomes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      Expanded(flex: 3, child: Text(code, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      Expanded(
                        flex: 2,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(value: rate, minHeight: 7, color: rate >= 0.5 ? NColors.amber : NColors.coral),
                        ),
                      ),
                      SizedBox(width: 44, child: Text(L10n.percent((rate * 100).round()), textAlign: TextAlign.end)),
                    ]),
                  ),
              ],
              if (g.misconceptions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(tr('Grupta sık görülen yanılgılar'), style: const TextStyle(fontWeight: FontWeight.w700)),
                for (final (m, n) in g.misconceptions) Text('• $m ($n)'),
              ],
              const SizedBox(height: 10),
              Text(tr('Önerilen çalışma'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              for (final p in g.tier.plan)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.check_rounded, size: 16, color: _colors[g.tier]),
                    const SizedBox(width: 6),
                    Expanded(child: Text(p)),
                  ]),
                ),
            ]),
          ),
        ),
    ]);
  }
}

// ———————————————————————————— Benzer yanlışlar

class _SimilarTab extends StatelessWidget {
  final Exam exam;
  const _SimilarTab({required this.exam});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final intro = _intro(
        context,
        Icons.compare_rounded,
        tr('Aynı yanlış şıkları işaretleyen öğrenci çiftlerini bulur. İki öğrencinin aynı soruda aynı yanlışı yapması tesadüf olabilir; çok sayıda ortak yanlış ise dikkat gerektirir. Bu bilgi kesin kanıt değildir ve yalnız size gösterilir, hiçbir rapora yazılmaz.'));
    if (!store.isPro) return _page([intro, const SizedBox(height: 12), const ProLocked(ProFeature.similarAnswers)]);
    final results = store.resultsOf(exam);
    if (!SimilarAnswers.applicable(exam, results)) {
      return _page([
        intro,
        const SizedBox(height: 16),
        Text(tr('Bu kontrol için en az {0} soru ve {1} öğrenci gerekir.', [SimilarAnswers.minQuestions, SimilarAnswers.minStudents])),
      ]);
    }
    final pairs = SimilarAnswers.of(exam, results);
    final students = store.studentById;
    String name(Result r) => students[r.sheet.studentId]?.fullName ?? tr('Eşleşmeyen kâğıt');
    return _page([
      intro,
      const SizedBox(height: 12),
      if (pairs.isEmpty)
        Card(
          child: ListTile(
            leading: const Icon(Icons.verified_rounded, color: NColors.emerald),
            title: Text(tr('Olağan dışı benzerlik bulunmadı')),
            subtitle: Text(tr('Hiçbir öğrenci çiftinde sınıfın genelinden belirgin biçimde fazla ortak yanlış yok.')),
          ),
        )
      else
        for (final p in pairs)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: const Icon(Icons.warning_amber_rounded, color: NColors.amber),
              title: Text('${name(p.a)}  ·  ${name(p.b)}', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(tr('{0} soruda aynı yanlış şık ({1}). İkisinin ortak yanlışı: {2}. Cevaplarının %{3}\'i aynı.', [
                p.sameWrong.length,
                p.sameWrong.join(', '),
                p.bothWrong,
                (p.agreement * 100).round(),
              ])),
            ),
          ),
    ]);
  }
}
