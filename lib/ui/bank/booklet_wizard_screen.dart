import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:printing/printing.dart';

import '../../bank/bank_models.dart';
import '../../bank/bank_store.dart';
import '../../bank/blueprint.dart';
import '../../bank/booklet_builder.dart';
import '../../core/models.dart';
import '../../core/pro.dart';
import '../../l10n/l10n.dart';
import '../../main.dart';
import '../../omr/form_code.dart';
import '../../omr/kid_layout.dart';
import '../../reports/booklet_pdf.dart';
import '../../reports/booklet_docx.dart';
import '../common_exam_ui.dart' show saveOrShareBytes;
import '../exam_screen.dart';
import '../pro_screen.dart';
import '../theme.dart';
import '../widgets.dart';
import 'bank_widgets.dart';
import 'blueprint_view.dart';
import 'library_screen.dart';

/// Soru kitapçığı sihirbazı: soruları seç → görünüm → kitapçık ve puan → önizle.
class BookletWizardScreen extends StatefulWidget {
  final Booklet? booklet;
  final List<String> questionIds;
  const BookletWizardScreen({super.key, this.booklet, this.questionIds = const []});

  static Future<void> open(BuildContext context, {Booklet? booklet, List<String> questionIds = const []}) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => BookletWizardScreen(booklet: booklet, questionIds: questionIds)));

  @override
  State<BookletWizardScreen> createState() => _BookletWizardScreenState();
}

class _BookletWizardScreenState extends State<BookletWizardScreen> {
  int _step = 0;
  late final String _id = widget.booklet?.id ?? BankStore.newId('k');
  late List<String> _ids = [...(widget.booklet?.questionIds ?? widget.questionIds)];
  late BookletOptions _o = widget.booklet?.options ??
      BookletOptions(
        title: '',
        instructions: BookletOptions.defaultInstructions().replaceAll('{0}', '40'),
        seed: DateTime.now().millisecondsSinceEpoch % 100000,
      );
  late final _name = TextEditingController(text: widget.booklet?.name ?? '');
  late final _title = TextEditingController(text: _o.title);
  late final _subtitle = TextEditingController(text: _o.subtitle);
  late final _instructions = TextEditingController(text: _o.instructions);
  late final _watermark = TextEditingController(text: _o.watermark);
  late final _total = TextEditingController(text: fmt2(_o.totalScore).replaceAll(RegExp(r'[.,]00$'), ''));
  late List<String> _examIds = [...?widget.booklet?.examIds];
  Set<int> _previewVariants = {};
  bool _saved = true;

  List<BankQuestion> get _questions => [for (final id in _ids) ?bank.questionById(id)];

  @override
  void initState() {
    super.initState();
    _saved = widget.booklet != null;
  }

  @override
  void dispose() {
    for (final c in [_name, _title, _subtitle, _instructions, _watermark, _total]) {
      c.dispose();
    }
    super.dispose();
  }

  void _setO(BookletOptions o) => setState(() {
        _o = o;
        _saved = false;
      });

  BookletOptions _collect() => _o.copyWith(
        title: _title.text.trim(),
        subtitle: _subtitle.text.trim(),
        instructions: _instructions.text.trim(),
        watermark: _watermark.text.trim(),
        totalScore: double.tryParse(_total.text.trim().replaceAll(',', '.'))?.clamp(1, 10000).toDouble() ?? 100,
      );

  String get _displayName {
    final n = _name.text.trim();
    if (n.isNotEmpty) return n;
    final t = _title.text.trim();
    return t.isNotEmpty ? t : tr('Adsız kitapçık');
  }

  void _save({bool quiet = false}) {
    _o = _collect();
    final now = DateTime.now();
    final old = bank.bookletById(_id);
    bank.upsertBooklet(Booklet(
      id: _id,
      name: _displayName,
      questionIds: _ids,
      options: _o,
      examIds: _examIds,
      created: old?.created ?? now,
      updated: now,
    ));
    setState(() => _saved = true);
    if (!quiet) toast(context, tr('Kitapçık kaydedildi.'));
  }

  List<BankNote> _tipsFor(List<BankQuestion> qs) {
    final seen = <String>{};
    final out = <BankNote>[];
    for (final q in qs) {
      for (final key in {q.topic, q.outcome}.where((s) => s.trim().isNotEmpty)) {
        for (final n in bank.notesFor(key, subject: q.subject)) {
          if (seen.add(n.id)) out.add(n);
        }
      }
    }
    return out;
  }

  Future<Uint8List> _pdf() async {
    final o = _collect();
    final qs = _questions;
    final plan = BookletPlan.build(qs, o);
    final store = StoreScope.of(context);
    // Çocuk şablonunda sınav önceden oluşturulduysa (tek sınıf) cevap kutusuna sınavın kodu basılır.
    final kidExams = o.kids ? store.exams.where((e) => e.kidForm && _examIds.contains(e.id)).toList() : const <Exam>[];
    return buildBookletPdf(
      plan,
      examCode: kidExams.length == 1 ? FormCode.examCodeOf(kidExams.first.id) : null,
      school: store.reportSchool,
      image: bank.imageBytes,
      parts: BookletPdfParts(variants: _previewVariants, answerKey: o.answerKeyPage, solutions: o.solutionsBooklet, tips: o.tipsAppendix),
      tips: o.tipsAppendix ? _tipsFor(qs) : const [],
    );
  }

  /// Kitapçığı düzenlenebilir Word belgesi olarak kaydeder / paylaşır.
  Future<void> _word() async {
    if (!await requirePro(context, ProFeature.wordExport) || !mounted) return;
    final o = _collect();
    final plan = BookletPlan.build(_questions, o);
    final store = StoreScope.of(context);
    final bytes = buildBookletDocx(plan,
        school: store.reportSchool, image: bank.imageBytes, variants: _previewVariants, answerKey: o.answerKeyPage);
    if (!mounted) return;
    await saveOrShareBytes(context,
        fileName: '${safeFileName(_displayName)}.docx',
        bytes: bytes,
        mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        message: tr('"{0}" kitapçığı (Word)', [_displayName]));
  }

  /// Sınav öncesi soru kontrolü (seçili sorular ve şu anki kitapçık ayarlarıyla).
  List<QualityIssue> _issues() {
    final qs = _questions;
    if (qs.isEmpty) return const [];
    try {
      return QualityCheck.run(BookletPlan.build(qs, _collect()));
    } catch (_) {
      return const [];
    }
  }

  int _warnings() => _issues().where((i) => i.warning).length;

  Future<void> _pick() async {
    final r = await Navigator.of(context).push<List<String>>(MaterialPageRoute(builder: (_) => QuestionPickerScreen(selected: _ids)));
    if (r != null) {
      setState(() {
        _ids = r;
        _saved = false;
      });
    }
  }

  Future<void> _auto() async {
    final store = StoreScope.of(context);
    final r = await showModalBottomSheet<List<BankQuestion>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AutoPickSheet(used: BankStore.usage(store.exams)),
    );
    if (r == null || !mounted) return;
    if (r.isEmpty) return toast(context, tr('Bu süzgeçle bankada soru bulunamadı.'));
    var replace = true;
    if (_ids.isNotEmpty) {
      final a = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('{0} soru seçildi', [r.length])),
          content: Text(tr('Mevcut seçimin yerine mi geçsin, sonuna mı eklensin?')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'add'), child: Text(tr('Sona ekle'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'replace'), child: Text(tr('Yerine koy'))),
          ],
        ),
      );
      if (a == null) return;
      replace = a == 'replace';
    }
    setState(() {
      _ids = replace ? [for (final q in r) q.id] : [..._ids, for (final q in r) if (!_ids.contains(q.id)) q.id];
      _saved = false;
    });
  }

  Future<void> _createExam() async {
    final qs = _questions;
    if (qs.isEmpty) return;
    final store = StoreScope.of(context);
    // Birden çok kitapçık türü Pro'dadır; Pro bittiyse yalnız A ile devam edilebilir.
    if (_o.bookletCount > 1 && !store.isPro) {
      if (!await requirePro(context, ProFeature.bookletVariants)) {
        if (!mounted) return;
        _setO(_o.copyWith(bookletCount: 1));
        return;
      }
      if (!mounted) return;
    }
    final classes = <String>{};
    final other = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('Sınavı oluştur'), style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              tr('Cevap anahtarı, kitapçık sıraları, şık karışımları ve konular otomatik girilir. Optik formları sınav ekranından basabilirsiniz.'),
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Text(tr('Hangi sınıflar?'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in {...store.classNames, ...classes})
                FilterChip(
                  label: Text(c),
                  selected: classes.contains(c),
                  onSelected: (on) => set(() => on ? classes.add(c) : classes.remove(c)),
                ),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: other,
              decoration: InputDecoration(
                isDense: true,
                labelText: tr('Başka sınıf (virgülle ayırın)'),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add_rounded),
                  onPressed: () => set(() {
                    classes.addAll(other.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty));
                    other.clear();
                  }),
                ),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.fact_check_rounded),
              label: Text(classes.length > 1 ? tr('{0} sınıf için oluştur', [classes.length]) : tr('Oluştur')),
            ),
          ]),
        ),
      ),
    );
    final extra = other.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
    classes.addAll(extra);
    other.dispose();
    if (ok != true || !mounted) return;
    final o = _collect();
    final plan = BookletPlan.build(qs, o);
    final list = classes.isEmpty ? [''] : classes.toList();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final commonId = list.length > 1 ? 'ortak_${stamp.toRadixString(36)}' : null;
    final name = o.title.isNotEmpty ? o.title : _displayName;
    final ids = <String>[];
    for (var c = 0; c < list.length; c++) {
      final e = plan.toExam(id: list.length == 1 ? 'e$stamp' : 'e${stamp}_$c', name: name, className: list[c], commonId: commonId);
      store.upsertExam(e);
      ids.add(e.id);
    }
    _examIds = [..._examIds, ...ids];
    _save(quiet: true);
    if (!mounted) return;
    toast(
        context,
        plan.kidBox
            ? tr('Sınav oluşturuldu. Cevaplar kitapçığın köşesindeki kutudan okunur; isimli cevap kartlarını "Form yazdır" ile basabilirsiniz.')
            : tr('Sınav oluşturuldu. Optik formları "Form yazdır" ile basabilirsiniz.'));
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExamScreen(examId: ids.first)));
  }

  @override
  Widget build(BuildContext context) {
    final steps = [tr('Sorular'), tr('Görünüm'), tr('Kitapçık'), tr('Önizleme')];
    final t = Theme.of(context);
    return PopScope(
      canPop: _saved || _ids.isEmpty,
      onPopInvokedWithResult: (popped, _) async {
        if (popped) return;
        final r = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr('Kitapçık kaydedilsin mi?')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: Text(tr('Kaydetme'))),
              FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: Text(tr('Kaydet'))),
            ],
          ),
        );
        if (!context.mounted || r == null) return;
        if (r == 'save') _save(quiet: true);
        _saved = true;
        if (context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.booklet == null ? tr('Yeni soru kitapçığı') : _displayName),
          actions: [
            TextButton.icon(onPressed: _ids.isEmpty ? null : _save, icon: const Icon(Icons.save_outlined), label: Text(tr('Kaydet'))),
            const SizedBox(width: 6),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Row(children: [
                for (var i = 0; i < steps.length; i++) ...[
                  _StepChip(
                    n: i + 1,
                    label: steps[i],
                    active: _step == i,
                    done: _step > i,
                    onTap: _ids.isEmpty && i > 0 ? null : () => setState(() => _step = i),
                  ),
                  if (i < steps.length - 1)
                    Container(width: 18, height: 2, color: t.colorScheme.outlineVariant, margin: const EdgeInsets.symmetric(horizontal: 4)),
                ],
              ]),
            ),
          ),
        ),
        body: SafeArea(
          child: switch (_step) {
            0 => _questionsStep(t),
            1 => _layoutStep(t),
            2 => _bookletStep(t),
            _ => _previewStep(t),
          },
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: Row(children: [
              if (_step > 0) OutlinedButton.icon(onPressed: () => setState(() => _step--), icon: const Icon(Icons.arrow_back_rounded), label: Text(tr('Geri'))),
              const Spacer(),
              if (_step == 3) ...[
                OutlinedButton.icon(
                  onPressed: _ids.isEmpty ? null : _word,
                  icon: const Icon(Icons.description_outlined),
                  label: Text(tr('Word')),
                ),
                const SizedBox(width: 8),
              ],
              if (_step < 3)
                FilledButton.icon(
                  onPressed: _ids.isEmpty ? null : () => setState(() => _step++),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(tr('İleri')),
                )
              else
                FilledButton.icon(
                  onPressed: _ids.isEmpty ? null : _createExam,
                  icon: const Icon(Icons.fact_check_rounded),
                  label: Text(tr('Sınav oluştur')),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  // ———————————————————————————— 1. Sorular

  Widget _questionsStep(ThemeData t) {
    final qs = _questions;
    final counts = [for (final d in Difficulty.values) qs.where((q) => q.difficulty == d).length];
    final optical = qs.fold(0, (a, q) => a + q.opticalRows);
    final topics = qs.map((q) => q.topicLabel.toLowerCase()).where((s) => s.isNotEmpty).toSet().length;
    final incomplete = qs.where((q) => !q.complete).length;
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    final header = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _name,
        onChanged: (_) => _saved = false,
        decoration: InputDecoration(labelText: tr('Kitapçığın adı (listede görünür)'), prefixIcon: const Icon(Icons.label_outline_rounded)),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Text('${qs.length}', style: t.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, fontFeatures: tabular)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr('soru · {0} optik, {1} klasik · {2} konu', [optical, qs.length - optical, topics]),
                  style: TextStyle(color: muted),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            DifficultyBar(counts: counts),
            const SizedBox(height: 8),
            Wrap(spacing: 12, children: [
              for (final d in Difficulty.values)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.circle, size: 10, color: difficultyColor(d)),
                  const SizedBox(width: 4),
                  Text('${d.label} ${counts[d.index]}', style: t.textTheme.bodySmall),
                ]),
            ]),
            if (incomplete > 0) ...[
              const SizedBox(height: 10),
              Pill(tr('{0} sorunun cevabı eksik', [incomplete]), color: NColors.coral, icon: Icons.error_outline_rounded),
            ],
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 10, children: [
              FilledButton.icon(onPressed: _pick, icon: const Icon(Icons.checklist_rounded), label: Text(tr('Bankadan seç'))),
              FilledButton.tonalIcon(onPressed: _auto, icon: const Icon(Icons.auto_awesome_rounded), label: Text(tr('Otomatik seç'))),
              if (qs.isNotEmpty) ...[
                OutlinedButton.icon(
                  onPressed: () => showBlueprintSheet(context, qs),
                  icon: const Icon(Icons.table_chart_outlined),
                  label: Text(tr('Belirtke tablosu')),
                ),
                OutlinedButton.icon(
                  onPressed: () => showQualitySheet(context, _issues()),
                  icon: Icon(_warnings() > 0 ? Icons.warning_amber_rounded : Icons.fact_check_outlined,
                      color: _warnings() > 0 ? NColors.coral : null),
                  label: Text(_warnings() > 0 ? tr('Soru kontrolü ({0})', [_warnings()]) : tr('Soru kontrolü')),
                ),
              ],
              if (qs.isNotEmpty)
                TextButton.icon(
                  onPressed: () => setState(() {
                    _ids = [for (final q in BankStore.sortQuestions(qs, QuestionOrder.byTopic)) q.id];
                    _saved = false;
                  }),
                  icon: const Icon(Icons.sort_rounded),
                  label: Text(tr('Konuya göre diz')),
                ),
            ]),
          ]),
        ),
      ),
      if (qs.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
          child: Text(tr('Sürükleyerek sıralayın. Bu sıra A kitapçığının sırasıdır.'), style: t.textTheme.bodySmall?.copyWith(color: muted)),
        ),
    ]);
    if (qs.isEmpty) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        header,
        BankEmpty(
          icon: Icons.playlist_add_rounded,
          title: tr('Kitapçığa soru ekleyin'),
          text: tr('Soruları tek tek seçebilir ya da sayı ve kolay/orta/zor oranı verip otomatik seçtirebilirsiniz.'),
        ),
      ]);
    }
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      header: header,
      itemCount: qs.length,
      onReorderItem: (a, b) => setState(() {
        final id = _ids.removeAt(a);
        _ids.insert(b, id);
        _saved = false;
      }),
      itemBuilder: (context, i) {
        final q = qs[i];
        return Card(
          key: ValueKey(q.id),
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            contentPadding: const EdgeInsets.only(left: 6, right: 4),
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: difficultyColor(q.difficulty).withValues(alpha: 0.18),
              child: Text('${i + 1}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: t.colorScheme.onSurface)),
            ),
            title: q.text.trim().isNotEmpty
                ? Text(q.text.trim(), maxLines: 2, overflow: TextOverflow.ellipsis)
                : Align(alignment: AlignmentDirectional.centerStart, child: BankImage(q.imageId, height: 44)),
            subtitle: Text([q.topicLabel, q.type.label, if (q.answerLabel.isNotEmpty) q.answerLabel].where((s) => s.isNotEmpty).join(' · '),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: tr('Çıkar'),
                icon: const Icon(Icons.remove_circle_outline_rounded),
                onPressed: () => setState(() {
                  _ids.remove(q.id);
                  _saved = false;
                }),
              ),
              ReorderableDragStartListener(index: i, child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_indicator_rounded))),
            ]),
          ),
        );
      },
    );
  }

  // ———————————————————————————— 2. Görünüm

  /// Şablon değişince yazı boyutu, kitapçık sayısı ve (değiştirilmediyse) yönerge uyarlanır.
  void _setStyle(BookletStyle s) {
    if (s == _o.style) return;
    final kids = s == BookletStyle.kids;
    final kidText = _kidInstructions();
    final classicText = BookletOptions.defaultInstructions().replaceAll('{0}', '${_o.durationMinutes}');
    final cur = _instructions.text.trim();
    if (kids && (cur.isEmpty || cur == classicText)) _instructions.text = kidText;
    if (!kids && cur == kidText) _instructions.text = classicText;
    _setO(_o.copyWith(
      style: s,
      fontSize: kids ? 14 : 10.5,
      bookletCount: kids ? 1 : _o.bookletCount,
      compactChoices: kids ? true : _o.compactChoices,
    ));
  }

  static String _kidInstructions() =>
      tr('Soruları dikkatlice oku. Her sorunun yalnız bir doğru cevabı var. Cevabını köşedeki kutuda, doğru harfin dairesini tamamen boyayarak işaretle.');

  Widget _layoutStep(ThemeData t) {
    final store = StoreScope.of(context);
    final kids = _o.kids;
    final testCount = _questions.fold(0, (a, q) => a + q.opticalRows);
    return _page([
      _section(Icons.palette_outlined, tr('Şablon'), [
        Row(children: [
          for (final s in BookletStyle.values) ...[
            if (s != BookletStyle.values.first) const SizedBox(width: 10),
            Expanded(
              child: _StyleCard(
                style: s,
                selected: _o.style == s,
                onTap: () => _setStyle(s),
              ),
            ),
          ],
        ]),
        if (kids) ...[
          const SizedBox(height: 14),
          Text(tr('Renk teması'), style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final th in KidTheme.values)
              _KidThemeChip(theme: th, selected: _o.kidTheme == th, onTap: () => _setO(_o.copyWith(kidTheme: th))),
          ]),
          const SizedBox(height: 10),
          Text(
            testCount > KidLayout.maxQuestions
                ? tr('Köşedeki cevap kutusu en çok {0} soru alır. Bu kitapçıkta {1} test sorusu var; cevaplar standart Netice optik formuyla okunur.',
                    [KidLayout.maxQuestions, testCount])
                : tr('Cevaplar ilk sayfanın köşesindeki küçük kutudan telefonla okunur. İsimli cevap kartlarını sınav ekranındaki "Form yazdır" ile basabilirsiniz.'),
            style: t.textTheme.bodySmall,
          ),
        ],
      ]),
      _section(Icons.title_rounded, tr('Başlık'), [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('Resmi kurum başlığı')),
          subtitle: Text(store.reportSchool.name.trim().isEmpty ? tr('Ayarlar › Kurum bilgilerinden doldurun') : store.reportSchool.name),
          value: _o.officialHeader,
          onChanged: (v) => _setO(_o.copyWith(officialHeader: v)),
        ),
        TextField(
          controller: _title,
          onChanged: (_) => _saved = false,
          decoration: InputDecoration(labelText: tr('Sınav adı'), hintText: tr('Ör: 1. Dönem 2. Yazılı Sınavı')),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _subtitle,
          onChanged: (_) => _saved = false,
          decoration: InputDecoration(labelText: tr('Alt başlık (isteğe bağlı)'), hintText: tr('Ör: 9. Sınıflar Matematik')),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.event_rounded),
              label: Text(_o.date == null ? tr('Tarih: bugün') : dmy(_o.date!)),
              onPressed: () async {
                final d = await showDatePicker(
                    context: context, initialDate: _o.date ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (d != null) _setO(_o.copyWith(date: d));
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<int>(
              isExpanded: true,
              initialValue: const [0, 20, 30, 40, 45, 60, 75, 80, 90, 100, 120, 135, 150, 180].contains(_o.durationMinutes) ? _o.durationMinutes : 40,
              decoration: InputDecoration(isDense: true, labelText: tr('Süre')),
              items: [
                for (final m in const [0, 20, 30, 40, 45, 60, 75, 80, 90, 100, 120, 135, 150, 180])
                  DropdownMenuItem(value: m, child: Text(m == 0 ? tr('Yazma') : tr('{0} dk', [m]))),
              ],
              onChanged: (v) {
                final m = v ?? 40;
                final def = RegExp(r'\d+').allMatches(_instructions.text).isNotEmpty;
                if (def) _instructions.text = _instructions.text.replaceFirst(RegExp('${_o.durationMinutes}'), '$m');
                _setO(_o.copyWith(durationMinutes: m));
              },
            ),
          ),
        ]),
        const SizedBox(height: 10),
        TextField(
          controller: _instructions,
          onChanged: (_) => _saved = false,
          minLines: 2,
          maxLines: 6,
          decoration: InputDecoration(labelText: tr('Yönerge'), alignLabelWithHint: true),
        ),
        _switch(tr('Öğrenci bilgi kutusu'), tr('Ad soyad, numara, sınıf, imza'), _o.studentBox, (v) => _o.copyWith(studentBox: v)),
        _switch(tr('Kapak sayfası'), tr('Başlık ve yönerge ayrı sayfada'), _o.coverPage, (v) => _o.copyWith(coverPage: v)),
      ]),
      _section(Icons.view_column_outlined, tr('Sayfa düzeni'), [
        Row(children: [
          Expanded(
            child: SegmentedButton<PaperSize>(
              showSelectedIcon: false,
              segments: [for (final p in PaperSize.values) ButtonSegment(value: p, label: Text(p.label))],
              selected: {_o.paper},
              onSelectionChanged: (s) => _setO(_o.copyWith(paper: s.first)),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 1, label: Text(tr('Tek sütun')), icon: const Icon(Icons.view_agenda_outlined)),
            ButtonSegment(value: 2, label: Text(tr('İki sütun')), icon: const Icon(Icons.view_column_outlined)),
          ],
          selected: {_o.columns},
          onSelectionChanged: (s) => _setO(_o.copyWith(columns: s.first)),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Text(tr('Yazı boyutu'), style: const TextStyle(fontWeight: FontWeight.w600)),
          Expanded(
            child: Slider(
              value: kids ? _o.fontSize.clamp(12, 18) : _o.fontSize.clamp(8, 14),
              min: kids ? 12 : 8,
              max: kids ? 18 : 14,
              divisions: 12,
              label: fmt1(_o.fontSize),
              onChanged: (v) => _setO(_o.copyWith(fontSize: v)),
            ),
          ),
          Text(fmt1(_o.fontSize), style: const TextStyle(fontFeatures: tabular)),
        ]),
        _switch(tr('Sütun arası çizgi'), null, _o.columnRule, (v) => _o.copyWith(columnRule: v)),
        _switch(tr('Sorular arası çizgi'), null, _o.questionRule, (v) => _o.copyWith(questionRule: v)),
        _switch(tr('Şıkları yan yana diz'), tr('Kısa şıklar aynı satıra sığarsa yer kazanılır'), _o.compactChoices, (v) => _o.copyWith(compactChoices: v)),
        _switch(tr('Ders başlıkları'), tr('Farklı derslerden sorular varsa bölüm başlığı basılır'), _o.sectionHeaders, (v) => _o.copyWith(sectionHeaders: v)),
        _switch(tr('Soru puanlarını göster'), null, _o.showPoints, (v) => _o.copyWith(showPoints: v)),
        _switch(tr('Soru konusunu göster'), null, _o.showTopic, (v) => _o.copyWith(showTopic: v)),
        _switch(tr('Sayfa numaraları'), null, _o.pageNumbers, (v) => _o.copyWith(pageNumbers: v)),
        _switch(tr('"Diğer sayfaya geçiniz" uyarısı'), null, _o.nextPageHint, (v) => _o.copyWith(nextPageHint: v)),
        const SizedBox(height: 6),
        TextField(
          controller: _watermark,
          onChanged: (_) => _saved = false,
          decoration: InputDecoration(labelText: tr('Filigran (isteğe bağlı)'), hintText: tr('Ör: kurum adı ya da "DENEME"')),
        ),
      ]),
    ]);
  }

  // ———————————————————————————— 3. Kitapçık ve puan

  Widget _bookletStep(ThemeData t) {
    final qs = _questions;
    final n = qs.length;
    final per = n == 0 ? 0.0 : (double.tryParse(_total.text.replaceAll(',', '.')) ?? 100) / n;
    return _page([
      if (_o.kids)
        _section(Icons.auto_stories_outlined, tr('Kitapçık türleri'), [
          Text(tr('Çocuk şablonunda tek kitapçık basılır; cevap kutusunda kitapçık seçimi yoktur.'), style: t.textTheme.bodySmall),
        ])
      else
      _section(Icons.auto_stories_outlined, tr('Kitapçık türleri'), [
        Text(tr('Kitapçık sayısı'), style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var k = 1; k <= Exam.maxBooklets; k++)
            ChoiceChip(
              label: Text(k == 1 ? tr('Yalnız A') : 'A–${letter(k - 1)}'),
              selected: _o.bookletCount == k,
              onSelected: (_) async {
                if (k > 1 && !await requirePro(context, ProFeature.bookletVariants)) return;
                _setO(_o.copyWith(bookletCount: k));
              },
            ),
        ]),
        if (_o.bookletCount > 1) ...[
          const SizedBox(height: 6),
          _switch(tr('Soruların yerini karıştır'), tr('B ve sonraki kitapçıklarda'), _o.shuffleQuestions, (v) => _o.copyWith(shuffleQuestions: v)),
          if (_o.shuffleQuestions)
            _switch(tr('Her ders kendi bölümünde karışsın'), tr('Türkçe soruları Türkçe bölümünde kalır'), _o.shuffleWithinSections,
                (v) => _o.copyWith(shuffleWithinSections: v)),
          _switch(tr('Şıkları karıştır'), tr('"Hepsi / hiçbiri" gibi son şıklar yerinde kalır. Şıkları görselde olan sorular karışmaz.'), _o.shuffleChoices,
              (v) => _o.copyWith(shuffleChoices: v)),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => _setO(_o.copyWith(seed: DateTime.now().millisecondsSinceEpoch % 100000)),
              icon: const Icon(Icons.shuffle_rounded),
              label: Text(tr('Yeniden karıştır')),
            ),
          ),
        ],
      ]),
      _section(Icons.format_list_numbered_rounded, tr('A kitapçığında soru sırası'), [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final o in QuestionOrder.values)
            ChoiceChip(label: Text(o.label), selected: _o.order == o, onSelected: (_) => _setO(_o.copyWith(order: o))),
        ]),
      ]),
      _section(Icons.scoreboard_outlined, tr('Puanlama'), [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _total,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() => _saved = false),
              decoration: InputDecoration(labelText: tr('Toplam puan'), isDense: true),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<int>(
              isExpanded: true,
              initialValue: _o.wrongsPerCorrect,
              decoration: InputDecoration(isDense: true, labelText: tr('Yanlış doğruyu götürür')),
              items: [
                DropdownMenuItem(value: 0, child: Text(tr('Götürmez'))),
                for (final k in const [2, 3, 4, 5]) DropdownMenuItem(value: k, child: Text(tr('{0} yanlış 1 doğru', [k]))),
              ],
              onChanged: (v) => _setO(_o.copyWith(wrongsPerCorrect: v ?? 0)),
            ),
          ),
        ]),
        _switch(tr('Puanları eşit dağıt'),
            _o.equalPoints ? tr('Her soru yaklaşık {0} puan', [fmt2(per)]) : tr('Sorulara girdiğiniz puan ağırlıkları kullanılır'),
            _o.equalPoints, (v) => _o.copyWith(equalPoints: v)),
      ]),
      _section(Icons.library_add_check_outlined, tr('Ekler'), [
        _switch(tr('Cevap anahtarı sayfası'), tr('Her kitapçığın anahtarı tablo hâlinde, en sonda'), _o.answerKeyPage, (v) => _o.copyWith(answerKeyPage: v)),
        _switch(tr('Çözümlü kitapçık'), tr('Doğru cevap ve çözümler işaretli öğretmen nüshası'), _o.solutionsBooklet, (v) => _o.copyWith(solutionsBooklet: v)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('Hap bilgi eki')),
          subtitle: Text(tr('Sorulan konuların hap bilgileri ve özetleri en sona eklenir')),
          value: _o.tipsAppendix,
          onChanged: (v) async {
            if (v && !await requirePro(context, ProFeature.bookletVariants)) return;
            _setO(_o.copyWith(tipsAppendix: v));
          },
        ),
      ]),
    ]);
  }

  // ———————————————————————————— 4. Önizleme

  Widget _previewStep(ThemeData t) {
    final count = _o.bookletCount;
    final issues = _issues();
    final warn = issues.where((i) => i.warning).length;
    return Column(children: [
      if (issues.isNotEmpty)
        Material(
          color: (warn > 0 ? NColors.coral : NColors.amber).withValues(alpha: 0.12),
          child: ListTile(
            dense: true,
            leading: Icon(warn > 0 ? Icons.warning_amber_rounded : Icons.info_outline_rounded, color: warn > 0 ? NColors.coral : NColors.amber),
            title: Text(warn > 0
                ? tr('Soru kontrolü {0} uyarı buldu', [warn])
                : tr('Soru kontrolünde {0} öneri var', [issues.length])),
            trailing: TextButton(onPressed: () => showQualitySheet(context, issues), child: Text(tr('Göster'))),
          ),
        ),
      if (count > 1)
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(16, 8, 16, 6), children: [
            ChoiceChip(label: Text(tr('Tüm kitapçıklar')), selected: _previewVariants.isEmpty, onSelected: (_) => setState(() => _previewVariants = {})),
            for (var b = 0; b < count; b++) ...[
              const SizedBox(width: 6),
              ChoiceChip(
                label: Text(tr('{0} kitapçığı', [letter(b)])),
                selected: _previewVariants.length == 1 && _previewVariants.contains(b),
                onSelected: (_) => setState(() => _previewVariants = {b}),
              ),
            ],
          ]),
        ),
      Expanded(
        child: PdfPreview(
          key: ValueKey('${_previewVariants.join(',')}-${_o.hashCode}'),
          build: (_) => _pdf(),
          canChangeOrientation: false,
          canChangePageFormat: false,
          canDebug: false,
          pdfFileName: '${safeFileName(_displayName)}.pdf',
          loadingWidget: const CircularProgressIndicator(),
        ),
      ),
    ]);
  }

  // ———————————————————————————— Yardımcılar

  Widget _page(List<Widget> children) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: children),
        ),
      );

  Widget _section(IconData icon, String title, List<Widget> children) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              IconBadge(icon, size: 30),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 10),
            ...children,
          ]),
        ),
      );

  Widget _switch(String title, String? subtitle, bool value, BookletOptions Function(bool) apply) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        value: value,
        onChanged: (v) => _setO(apply(v)),
      );
}

class _StepChip extends StatelessWidget {
  final int n;
  final String label;
  final bool active;
  final bool done;
  final VoidCallback? onTap;
  const _StepChip({required this.n, required this.label, required this.active, required this.done, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = active || done ? NColors.emerald : t.colorScheme.outline;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: active ? NColors.emerald : (done ? NColors.emerald.withValues(alpha: 0.18) : null), border: Border.all(color: c, width: 1.6)),
            child: done
                ? const Icon(Icons.check_rounded, size: 15, color: NColors.emerald)
                : Text('$n', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: active ? Colors.white : c)),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontWeight: active ? FontWeight.w800 : FontWeight.w600, color: active ? null : t.colorScheme.onSurface.withValues(alpha: 0.7))),
        ]),
      ),
    );
  }
}

// ———————————————————————————— Soru seçici

class QuestionPickerScreen extends StatefulWidget {
  final List<String> selected;
  const QuestionPickerScreen({super.key, required this.selected});

  @override
  State<QuestionPickerScreen> createState() => _QuestionPickerScreenState();
}

class _QuestionPickerScreenState extends State<QuestionPickerScreen> {
  late final List<String> _sel = [...widget.selected];
  BankFilter _f = const BankFilter();

  @override
  Widget build(BuildContext context) {
    final used = BankStore.usage(StoreScope.of(context).exams);
    final list = bank.questions.where((q) => _f.matches(q, used: (used[q.id] ?? 0) > 0)).toList()
      ..sort((a, b) {
        final s = a.subject.toLowerCase().compareTo(b.subject.toLowerCase());
        return s != 0 ? s : a.topicLabel.toLowerCase().compareTo(b.topicLabel.toLowerCase());
      });
    final allOn = list.isNotEmpty && list.every((q) => _sel.contains(q.id));
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('{0} soru seçili', [_sel.length])),
        actions: [
          TextButton(
            onPressed: list.isEmpty
                ? null
                : () => setState(() {
                      if (allOn) {
                        _sel.removeWhere((id) => list.any((q) => q.id == id));
                      } else {
                        _sel.addAll(list.map((q) => q.id).where((id) => !_sel.contains(id)));
                      }
                    }),
            child: Text(allOn ? tr('Görünenleri bırak') : tr('Görünenleri seç')),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10, left: 4),
            child: FilledButton(onPressed: () => Navigator.pop(context, _sel), child: Text(tr('Tamam'))),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => _f = _f.copyWith(query: v)),
                decoration: InputDecoration(isDense: true, hintText: tr('Soru, konu, etiket ara'), prefixIcon: const Icon(Icons.search_rounded)),
              ),
            ),
            const SizedBox(width: 8),
            Badge(
              isLabelVisible: _f.activeCount > 0,
              label: Text('${_f.activeCount}'),
              backgroundColor: NColors.emerald,
              child: IconButton.filledTonal(
                icon: const Icon(Icons.tune_rounded),
                onPressed: () async {
                  final r = await showModalBottomSheet<BankFilter>(
                      context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => FilterSheet(initial: _f));
                  if (r != null) setState(() => _f = r);
                },
              ),
            ),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final q = list[i];
              final on = _sel.contains(q.id);
              return QuestionCard(
                q: q,
                used: used[q.id] ?? 0,
                selected: on,
                selecting: true,
                onTap: () => setState(() => on ? _sel.remove(q.id) : _sel.add(q.id)),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ———————————————————————————— Otomatik seçim

class AutoPickSheet extends StatefulWidget {
  final Map<String, int> used;
  const AutoPickSheet({super.key, required this.used});

  @override
  State<AutoPickSheet> createState() => _AutoPickSheetState();
}

class _AutoPickSheetState extends State<AutoPickSheet> {
  int _count = 20;
  int _easy = 30, _medium = 50;
  bool _balance = true, _unused = true, _optical = true, _levels = false;
  BankFilter _f = const BankFilter();

  int get _hard => 100 - _easy - _medium;

  List<BankQuestion> get _pool => bank.questions.where((q) => q.complete && _f.matches(q) && (!_optical || q.type.optical)).toList();

  void _preset(int e, int m) => setState(() {
        _easy = e;
        _medium = m;
      });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final pool = _pool;
    final poolCounts = [for (final d in Difficulty.values) pool.where((q) => q.difficulty == d).length];
    final count = _count.clamp(1, pool.isEmpty ? 1 : pool.length);
    final want = [count * _easy / 100, count * _medium / 100, count * _hard / 100].map((x) => x.round()).toList();
    final topics = _f.subjects.isEmpty ? bank.topicsOf() : {for (final s in _f.subjects) ...bank.topicsOf(s)}.toList();
    Widget head(String s) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 8),
          child: Text(s, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        );
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) => SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 12), children: [
              Text(tr('Otomatik soru seç'), style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(tr('Uygun havuzda {0} soru var.', [pool.length]), style: t.textTheme.bodySmall),
              if (bank.subjects.isNotEmpty) ...[
                head(tr('Ders')),
                ChoiceChips<String>(values: bank.subjects, selected: _f.subjects, label: (s) => s, onChanged: (s) => setState(() => _f = _f.copyWith(subjects: s, topics: {}))),
              ],
              if (bank.grades.isNotEmpty) ...[
                head(tr('Sınıf / düzey')),
                ChoiceChips<String>(values: bank.grades, selected: _f.grades, label: (s) => s, onChanged: (s) => setState(() => _f = _f.copyWith(grades: s))),
              ],
              if (topics.length > 1) ...[
                head(tr('Konular (boşsa hepsi)')),
                ChoiceChips<String>(values: topics, selected: _f.topics, label: (s) => s, onChanged: (s) => setState(() => _f = _f.copyWith(topics: s))),
              ],
              head(tr('Soru sayısı')),
              NumberStepper(value: count, min: 1, max: pool.isEmpty ? 1 : pool.length.clamp(1, 200), onChanged: (v) => setState(() => _count = v)),
              head(tr('Zorluk dağılımı')),
              Wrap(spacing: 8, runSpacing: 8, children: [
                ActionChip(label: Text(tr('Dengeli 30/50/20')), onPressed: () => _preset(30, 50)),
                ActionChip(label: Text(tr('Kolay ağırlıklı 50/40/10')), onPressed: () => _preset(50, 40)),
                ActionChip(label: Text(tr('Seçici 20/40/40')), onPressed: () => _preset(20, 40)),
                ActionChip(label: Text(tr('Eşit')), onPressed: () => _preset(34, 33)),
              ]),
              const SizedBox(height: 8),
              _pctRow(Difficulty.easy, _easy, want[0], poolCounts[0], (v) => setState(() {
                    _easy = v;
                    if (_easy + _medium > 100) _medium = 100 - _easy;
                  })),
              _pctRow(Difficulty.medium, _medium, want[1], poolCounts[1], (v) => setState(() {
                    _medium = v;
                    if (_easy + _medium > 100) _easy = 100 - _medium;
                  })),
              _pctRow(Difficulty.hard, _hard, want[2], poolCounts[2], null),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Konulara eşit dağıt')),
                value: _balance,
                onChanged: (v) => setState(() => _balance = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Row(children: [
                  Flexible(child: Text(tr('Düşünme düzeylerini dengele'))),
                  const SizedBox(width: 6),
                  const ProBadge(),
                ]),
                subtitle: Text(tr('Hatırlamadan analize kadar her düzeyden soru seçer (belirtke tablosu)')),
                value: _levels,
                onChanged: (v) async {
                  if (v && !await requirePro(context, ProFeature.balancedBlueprint)) return;
                  if (mounted) setState(() => _levels = v);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Daha önce sorulmamışları öne al')),
                value: _unused,
                onChanged: (v) => setState(() => _unused = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Yalnız optik okunabilen sorular')),
                subtitle: Text(tr('Çoktan seçmeli ve doğru/yanlış')),
                value: _optical,
                onChanged: (v) => setState(() => _optical = v),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.auto_awesome_rounded),
                label: Text(tr('{0} soru seç', [count])),
                onPressed: pool.isEmpty
                    ? null
                    : () => Navigator.pop(
                          context,
                          BankStore.autoPick(
                            pool,
                            AutoPick(
                              count: count,
                              easyPct: _easy,
                              mediumPct: _medium,
                              hardPct: _hard,
                              balanceTopics: _balance,
                              balanceLevels: _levels,
                              preferUnused: _unused,
                              opticalOnly: _optical,
                              seed: DateTime.now().millisecondsSinceEpoch % 100000,
                            ),
                            used: widget.used,
                          ),
                        ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _pctRow(Difficulty d, int pct, int want, int have, ValueChanged<int>? onChanged) => Row(children: [
        Icon(Icons.circle, size: 12, color: difficultyColor(d)),
        const SizedBox(width: 8),
        SizedBox(width: 54, child: Text(d.label, style: const TextStyle(fontWeight: FontWeight.w700))),
        Expanded(
          child: Slider(
            value: pct.toDouble().clamp(0, 100),
            max: 100,
            divisions: 20,
            activeColor: difficultyColor(d),
            onChanged: onChanged == null ? null : (v) => onChanged((v / 5).round() * 5),
          ),
        ),
        SizedBox(
          width: 92,
          child: Text(
            '%$pct · $want/$have',
            textAlign: TextAlign.end,
            style: TextStyle(fontFeatures: tabular, color: want > have ? NColors.coral : null, fontWeight: want > have ? FontWeight.w700 : null),
          ),
        ),
      ]);
}

/// Şablon seçim kartı: küçük bir sayfa çizimi, adı ve kısa açıklaması.
class _StyleCard extends StatelessWidget {
  final BookletStyle style;
  final bool selected;
  final VoidCallback onTap;
  const _StyleCard({required this.style, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final kids = style == BookletStyle.kids;
    final border = selected ? t.colorScheme.primary : t.dividerColor;
    return Material(
      color: selected ? t.colorScheme.primary.withValues(alpha: 0.06) : Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: border, width: selected ? 2 : 1)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AspectRatio(aspectRatio: 1.5, child: CustomPaint(painter: _MiniPagePainter(kids))),
            const SizedBox(height: 8),
            Text(style.label, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              kids
                  ? tr('İri yazı, renkli numaralar, A–B–C şıkları, köşede cevap kutusu')
                  : tr('Resmi başlık, iki sütun, A–E şıkları, ayrı optik form'),
              style: t.textTheme.bodySmall,
            ),
          ]),
        ),
      ),
    );
  }
}

class _MiniPagePainter extends CustomPainter {
  final bool kids;
  _MiniPagePainter(this.kids);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final page = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8));
    canvas.drawRRect(page, Paint()..color = Colors.white);
    canvas.drawRRect(page, Paint()
      ..color = const Color(0xFFDDE2EC)
      ..style = PaintingStyle.stroke);
    final line = Paint()..color = const Color(0xFFCBD3E3);
    if (!kids) {
      canvas.drawRect(Rect.fromLTWH(w * 0.25, h * 0.08, w * 0.5, h * 0.06), Paint()..color = const Color(0xFF0F1B3D));
      for (var c = 0; c < 2; c++) {
        for (var i = 0; i < 5; i++) {
          canvas.drawRect(Rect.fromLTWH(w * (0.08 + c * 0.46), h * (0.26 + i * 0.14), w * 0.38, h * 0.035), line);
        }
      }
      return;
    }
    final band = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.05, h * 0.06, w * 0.9, h * 0.16), const Radius.circular(6));
    canvas.drawRRect(
        band,
        Paint()
          ..shader = const LinearGradient(colors: [Color(0xFFFFE7A8), Color(0xFFFFD1DC), Color(0xFFCDEAFE)])
              .createShader(band.outerRect));
    canvas.drawCircle(Offset(w * 0.13, h * 0.14), h * 0.05, Paint()..color = const Color(0xFFF6B632));
    const colors = [Color(0xFFFF8A5B), Color(0xFF4CB6E8), Color(0xFF7CC25A), Color(0xFFB38AE6)];
    for (var i = 0; i < 4; i++) {
      final x = w * (0.08 + (i ~/ 2) * 0.46), y = h * (0.34 + (i % 2) * 0.3);
      canvas.drawCircle(Offset(x + h * 0.035, y + h * 0.02), h * 0.04, Paint()..color = colors[i]);
      canvas.drawRect(Rect.fromLTWH(x + h * 0.1, y, w * 0.28, h * 0.04), line);
      canvas.drawRect(Rect.fromLTWH(x + h * 0.1, y + h * 0.08, w * 0.18, h * 0.03), line);
    }
    final box = Rect.fromLTWH(w * 0.74, h * 0.66, w * 0.2, h * 0.28);
    canvas.drawRect(box, Paint()
      ..color = const Color(0xFFC9D3EA)
      ..style = PaintingStyle.stroke);
    for (final o in [box.topLeft, box.topRight, box.bottomLeft, box.bottomRight]) {
      canvas.drawRect(Rect.fromCenter(center: o, width: h * 0.04, height: h * 0.04), Paint()..color = Colors.black);
    }
  }

  @override
  bool shouldRepaint(_MiniPagePainter old) => old.kids != kids;
}


/// Çocuk şablonu renk teması seçimi: üç renkli şerit ve adı.
class _KidThemeChip extends StatelessWidget {
  final KidTheme theme;
  final bool selected;
  final VoidCallback onTap;
  const _KidThemeChip({required this.theme, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final accent = Color(theme.accent);
    return Semantics(
      button: true,
      selected: selected,
      label: theme.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 118,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: t.colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? accent : t.dividerColor, width: selected ? 2.2 : 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              height: 30,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [for (final c in theme.gradient) Color(c)]),
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(children: [
                for (final c in theme.badges.take(4))
                  Container(
                    width: 11,
                    height: 11,
                    margin: const EdgeInsets.only(right: 3),
                    decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle),
                  ),
              ]),
            ),
            const SizedBox(height: 6),
            Row(children: [
              if (selected) ...[Icon(Icons.check_circle_rounded, size: 16, color: accent), const SizedBox(width: 4)],
              Expanded(child: Text(theme.label, style: const TextStyle(fontWeight: FontWeight.w700))),
            ]),
          ]),
        ),
      ),
    );
  }
}
