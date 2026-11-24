import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../bank/ai_questions.dart';
import '../../bank/bank_models.dart';
import '../../core/legal.dart';
import '../../core/pro.dart';
import '../../l10n/l10n.dart';
import '../../main.dart';
import '../pro_screen.dart';
import '../theme.dart';
import '../widgets.dart';
import 'bank_widgets.dart';
import 'booklet_wizard_screen.dart';
import 'note_screens.dart';
import 'question_editor_screen.dart';

/// Bir notu seçtirip soru üretme ekranını açar.
Future<void> pickNoteForAi(BuildContext context) async {
  if (bank.notes.isEmpty) {
    toast(context, tr('Önce bir ders notu ekleyin: PDF, Word, fotoğraf ya da elle.'));
    return;
  }
  final notes = [...bank.notes]..sort((a, b) => b.updated.compareTo(a.updated));
  final n = await showModalBottomSheet<BankNote>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(tr('Hangi nottan soru üretilsin?'),
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final x in notes)
                ListTile(
                  leading: IconBadge(noteIcon(x.kind), color: noteColor(x.kind)),
                  title: Text(x.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text([x.subject, x.topicLabel].where((s) => s.isNotEmpty).toSet().join(' · '),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.pop(ctx, x),
                ),
            ]),
          ),
        ]),
      ),
    ),
  );
  if (n != null && context.mounted) await AiQuestionsScreen.open(context, n);
}

/// "Nottan soru üret": yapay zekâ nottan çoktan seçmeli soru önerir,
/// öğretmen seçtiklerini bankaya ekler.
class AiQuestionsScreen extends StatefulWidget {
  final String noteId;

  /// Önizleme ve testler için hazır öneriler.
  final List<BankQuestion> initialDrafts;
  const AiQuestionsScreen({super.key, required this.noteId, this.initialDrafts = const []});

  static Future<void> open(BuildContext context, BankNote n) async {
    await AiUsage.instance.load();
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AiQuestionsScreen(noteId: n.id)));
  }

  @override
  State<AiQuestionsScreen> createState() => _AiQuestionsScreenState();
}

class _Draft {
  BankQuestion q;
  bool selected = true;
  bool added = false;
  _Draft(this.q);
}

class _AiQuestionsScreenState extends State<AiQuestionsScreen> {
  AiUsage get _usage => AiUsage.instance;
  late BankNote? _note = bank.noteById(widget.noteId);
  int _count = 20;
  late bool _kids = _defaultKids();
  late int _choices = _kids ? 3 : _defaultChoices();
  AiDifficulty _difficulty = AiDifficulty.mixed;
  Set<QuestionType> _types = {QuestionType.multiple};
  bool _busy = false;
  int _done = 0;
  int _target = 0;
  String? _error;
  String _problem = '';
  late final List<_Draft> _drafts = widget.initialDrafts.map(_Draft.new).toList();

  int _defaultChoices() {
    final g = int.tryParse(RegExp(r'\d+').firstMatch(_note?.grade ?? '')?.group(0) ?? '');
    return g != null && g <= 8 ? 4 : 5;
  }

  /// Not ilkokul düzeyindeyse (1–4. sınıf) çocuk dili açık başlar.
  bool _defaultKids() {
    final grade = (_note?.grade ?? '').toLowerCase();
    if (grade.contains('ilkokul') || grade.contains('primary') || grade.contains('grundschule')) return true;
    final g = int.tryParse(RegExp(r'\d+').firstMatch(grade)?.group(0) ?? '');
    return g != null && g >= 1 && g <= 4;
  }

  bool get _pending => _drafts.any((d) => !d.added && d.selected);

  Future<bool> _askConsent() async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.cloud_upload_outlined),
        title: Text(tr('Not internet üzerinden gönderilecek')),
        content: Text(tr('Soru üretmek için bu notun metni ve görselleri Netice\'nin soru sunucusu üzerinden yapay zekâ hizmetine (Anthropic Claude) gönderilir. Netice notu saklamaz; Anthropic de bu içeriği yapay zekâ eğitiminde kullanmaz.\n\nÖğrenci adı ya da numarası gibi kişisel bilgi içeren notları göndermeyin. Uygulamanın geri kalanı internetsiz çalışmaya devam eder.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Vazgeç'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Anladım, devam et'))),
        ],
      ),
    );
    return r ?? false;
  }

  Future<void> _openPro() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const ProScreen(feature: ProFeature.aiQuestions), fullscreenDialog: true));

  Future<void> _generate() async {
    final note = _note;
    if (note == null || _busy) return;
    final store = StoreScope.of(context);
    final tier = AiUsage.tierOf(store);
    final left = _usage.remaining(tier);
    if (left <= 0) {
      // Pro ekranında ek soru paketi ve Pro + Yapay Zekâ seçenekleri var.
      toast(context, quotaMessage(tier));
      await _openPro();
      return;
    }
    if (!_usage.consent) {
      if (!await _askConsent()) return;
      _usage.giveConsent();
    }
    final count = math.min(_count, left);
    setState(() {
      _busy = true;
      _error = null;
      _problem = '';
      _done = 0;
      _target = count;
    });
    // 20'den fazlası 20'şerlik parçalarla üretilir; her parça öncekileri tekrar etmez.
    final made = <String>[];
    try {
      while (_done < count) {
        final n = math.min(aiMaxPerRequest, count - _done);
        final r = await generateAiQuestions(
          note,
          AiOptions(count: n, choices: _choices, difficulty: _difficulty, types: _types, kids: _kids),
          store: bank,
          usage: _usage,
          tier: tier,
          alsoAvoid: made,
        );
        if (!mounted) return;
        made.addAll(r.questions.map((q) => q.text));
        setState(() {
          _drafts.insertAll(0, r.questions.map(_Draft.new));
          _done += n;
          _problem = r.problem;
        });
        // Not daha fazlasına yetmiyorsa durulur.
        if (r.questions.isEmpty || r.problem.isNotEmpty) break;
      }
      if (made.isEmpty && _problem.isEmpty && mounted) {
        setState(() => _error = tr('Bu nottan soru üretilemedi. Notun ders içeriği olduğundan emin olun.'));
      }
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      if (e.quota) await _openPro();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _addSelected() {
    final list = [for (final d in _drafts) if (d.selected && !d.added) d];
    if (list.isEmpty) return;
    bank.addQuestions(list.map((d) => d.q.copyWith(updated: DateTime.now())));
    setState(() {
      for (final d in list) {
        d.added = true;
      }
    });
    toast(context, tr('{0} soru bankaya eklendi.', [list.length]));
  }

  Future<void> _edit(_Draft d) async {
    await QuestionEditorScreen.open(context, bank.questionById(d.q.id) ?? d.q);
    if (!mounted) return;
    final saved = bank.questionById(d.q.id);
    if (saved != null) {
      setState(() {
        d.q = saved;
        d.added = true;
      });
    }
  }

  Future<void> _report(_Draft d) async {
    final body = '${d.q.text}\n\n${[for (var i = 0; i < d.q.choices.length; i++) '${String.fromCharCode(65 + i)}) ${d.q.choices[i]}'].join('\n')}';
    final uri = Uri(
      scheme: 'mailto',
      path: contactEmail,
      query: 'subject=${Uri.encodeComponent(tr('Netice: uygunsuz yapay zekâ sorusu'))}&body=${Uri.encodeComponent(body)}',
    );
    if (!await launchUrl(uri) && mounted) toast(context, contactEmail);
    if (mounted) setState(() => _drafts.remove(d));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final store = StoreScope.of(context);
    final note = _note = bank.noteById(widget.noteId) ?? _note;
    final tier = AiUsage.tierOf(store);
    final paid = tier != AiTier.trial;
    final selected = _drafts.where((d) => d.selected && !d.added).length;
    final added = [for (final d in _drafts) if (d.added && bank.questionById(d.q.id) != null) d.q.id];
    if (note == null) return const Scaffold();

    return PopScope(
      canPop: !_pending,
      onPopInvokedWithResult: (popped, _) async {
        if (popped) return;
        final r = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr('Seçilen sorular bankaya eklenmedi')),
            content: Text(tr('Çıkarsanız bu öneriler kaybolur.')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Eklemeden çık'))),
              FilledButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Vazgeç'))),
            ],
          ),
        );
        if (r == true && context.mounted) {
          _drafts.clear();
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(tr('Nottan soru üret'))),
        bottomNavigationBar: selected == 0 && added.isEmpty
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: selected > 0
                      ? FilledButton.icon(
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                          onPressed: _addSelected,
                          icon: const Icon(Icons.library_add_check_rounded),
                          label: Text(tr('Seçilen {0} soruyu bankaya ekle', [selected])),
                        )
                      : FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                          onPressed: () => BookletWizardScreen.open(context, questionIds: added),
                          icon: const Icon(Icons.menu_book_rounded),
                          label: Text(tr('{0} soruyla kitapçık ve cevap anahtarı oluştur', [added.length])),
                        ),
                ),
              ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(padding: const EdgeInsets.fromLTRB(14, 4, 14, 32), children: [
              _NoteHeader(note),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('Soru sayısı'), style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    SegmentedButton<int>(
                      segments: [for (final n in const [5, 10, 15, 20]) ButtonSegment(value: n, label: Text('$n'))],
                      selected: {if (const [5, 10, 15, 20].contains(_count)) _count},
                      emptySelectionAllowed: true,
                      onSelectionChanged: _busy ? null : (s) => setState(() => _count = s.isEmpty ? _count : s.first),
                    ),
                    const SizedBox(height: 10),
                    Text(tr('ya da sayıyı kendiniz girin (en fazla {0})', [aiMaxTotal]),
                        style: TextStyle(fontSize: 12.5, color: t.colorScheme.onSurface.withValues(alpha: 0.6))),
                    const SizedBox(height: 4),
                    IgnorePointer(
                      ignoring: _busy,
                      child: NumberStepper(
                        value: _count,
                        min: 1,
                        max: aiMaxTotal,
                        semanticLabel: tr('Soru sayısı'),
                        onChanged: (v) => setState(() => _count = v),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(tr('Soru türleri'), style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final ty in QuestionType.values)
                        FilterChip(
                          label: Text(ty.label),
                          selected: _types.contains(ty),
                          onSelected: _busy
                              ? null
                              : (v) => setState(() {
                                    final next = {..._types};
                                    v ? next.add(ty) : next.remove(ty);
                                    // En az bir tür seçili kalır.
                                    if (next.isNotEmpty) _types = next;
                                  }),
                        ),
                    ]),
                    if (_types.length > 1) ...[
                      const SizedBox(height: 6),
                      Text(tr('Soru sayısı seçilen türlere yaklaşık eşit bölünür.'), style: t.textTheme.bodySmall),
                    ],
                    const SizedBox(height: 14),
                    Text(tr('Zorluk'), style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final d in AiDifficulty.values)
                        ChoiceChip(
                          label: Text(d.label),
                          selected: _difficulty == d,
                          onSelected: _busy ? null : (_) => setState(() => _difficulty = d),
                        ),
                    ]),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.child_care_rounded),
                      title: Text(tr('Çocuklar için (ilkokul)')),
                      subtitle: Text(tr('Kısa cümleler, basit kelimeler; sorular çocuğa hitap eder. Çocuk kitapçık şablonuyla uyumlu (A–B–C).')),
                      value: _kids,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() {
                                _kids = v;
                                _choices = v ? 3 : _defaultChoices();
                              }),
                    ),
                    if (_types.contains(QuestionType.multiple)) ...[
                      const SizedBox(height: 6),
                      Text(tr('Şık sayısı'), style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 3, label: Text('A–C')),
                          ButtonSegment(value: 4, label: Text('A–D')),
                          ButtonSegment(value: 5, label: Text('A–E')),
                        ],
                        selected: {_choices},
                        onSelectionChanged: _busy ? null : (s) => setState(() => _choices = s.first),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                      onPressed: _busy ? null : _generate,
                      icon: _busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4))
                          : const Icon(Icons.auto_awesome_rounded),
                      label: Text(_busy
                          ? (_target > aiMaxPerRequest ? tr('Sorular hazırlanıyor… {0} / {1}', [_done, _target]) : tr('Sorular hazırlanıyor…'))
                          : (_drafts.isEmpty ? tr('Soruları üret') : tr('Yeni sorular üret'))),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Icon(Icons.wifi_rounded, size: 16, color: t.colorScheme.onSurface.withValues(alpha: 0.55)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          (paid
                                  ? tr('İnternet gerekir · bu ay kalan: {0} / {1} soru', [_usage.planRemaining(tier), AiUsage.limitOf(tier)])
                                  : tr('İnternet gerekir · deneme hakkı: {0} / {1} soru', [_usage.planRemaining(tier), AiUsage.trialLimit])) +
                              (_usage.credits > 0 ? tr(' · ek paket: {0} soru', [_usage.credits]) : ''),
                          style: TextStyle(fontSize: 12.5, color: t.colorScheme.onSurface.withValues(alpha: 0.6)),
                        ),
                      ),
                      if (!paid) ...[const SizedBox(width: 6), const ProBadge()],
                    ]),
                  ]),
                ),
              ),
              if (_busy)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _InfoCard(
                    icon: Icons.hourglass_top_rounded,
                    color: NColors.ink,
                    text: _target > aiMaxPerRequest
                        ? tr('Sorular 20\'şer hazırlanıyor; hazır olanlar hemen aşağıya eklenir. Çok sayıda soru birkaç dakika sürebilir, ekrandan çıkmayın.')
                        : tr('Yapay zekâ notunuzu okuyor ve soruları yazıyor. Notun uzunluğuna göre bir dakika kadar sürebilir.'),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _InfoCard(icon: Icons.error_outline_rounded, color: NColors.coral, text: _error!),
                ),
              if (_problem.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _InfoCard(icon: Icons.info_outline_rounded, color: NColors.amber, text: _problem),
                ),
              if (_drafts.isNotEmpty) ...[
                SectionTitle(
                  tr('Öneriler'),
                  trailing: TextButton(
                    onPressed: () => setState(() {
                      final all = _drafts.where((d) => !d.added).every((d) => d.selected);
                      for (final d in _drafts) {
                        if (!d.added) d.selected = !all;
                      }
                    }),
                    child: Text(tr('Tümünü seç / bırak')),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                  child: Text(
                    tr('Yapay zekâ yanılabilir. Soruları ve doğru cevapları kontrol edin; gerekirse düzenleyin.'),
                    style: TextStyle(fontSize: 12.5, color: t.colorScheme.onSurface.withValues(alpha: 0.6)),
                  ),
                ),
                for (var i = 0; i < _drafts.length; i++)
                  _DraftCard(
                    index: i + 1,
                    draft: _drafts[i],
                    onToggle: (v) => setState(() => _drafts[i].selected = v),
                    onEdit: () => _edit(_drafts[i]),
                    onReport: () => _report(_drafts[i]),
                  ),
              ] else if (!_busy && _error == null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _InfoCard(
                    icon: Icons.tips_and_updates_outlined,
                    color: NColors.emerald,
                    text: tr('Yapay zekâ bu notun metninden ve görsellerinden çoktan seçmeli sorular, doğru cevaplar ve kısa çözümler önerir. Beğendiklerinizi seçip bankaya eklersiniz; ders, konu ve kazanım nottan alınır.'),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _NoteHeader extends StatelessWidget {
  final BankNote note;
  const _NoteHeader(this.note);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = noteColor(note.kind);
    final words = note.body.trim().isEmpty ? 0 : note.body.trim().split(RegExp(r'\s+')).length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: BorderDirectional(start: BorderSide(color: c, width: 4)),
      ),
      child: Row(children: [
        IconBadge(noteIcon(note.kind), color: c),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(note.displayTitle, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              [
                if (note.subject.isNotEmpty) note.subject,
                if (note.grade.isNotEmpty) note.grade,
                if (note.topicLabel.isNotEmpty && note.topicLabel != note.subject) note.topicLabel,
                tr('{0} kelime', [words]),
                if (note.imageIds.isNotEmpty) tr('{0} görsel', [note.imageIds.length]),
              ].join(' · '),
              style: TextStyle(fontSize: 12.5, color: t.colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _InfoCard({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(14)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
        ]),
      );
}

class _DraftCard extends StatelessWidget {
  final int index;
  final _Draft draft;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onReport;
  const _DraftCard({required this.index, required this.draft, required this.onToggle, required this.onEdit, required this.onReport});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final q = draft.q;
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (draft.added)
              const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.check_circle_rounded, color: NColors.emerald))
            else
              Checkbox(value: draft.selected, onChanged: (v) => onToggle(v ?? false)),
            Text(tr('Soru {0}', [index]), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            DifficultyPill(q.difficulty),
            const Spacer(),
            if (draft.added) Pill(tr('Bankada'), color: NColors.emerald),
            PopupMenuButton<String>(
              tooltip: tr('Diğer'),
              onSelected: (v) => v == 'edit' ? onEdit() : onReport(),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit', child: ListTile(leading: const Icon(Icons.edit_outlined), title: Text(tr('Düzenle')))),
                PopupMenuItem(
                    value: 'report',
                    child: ListTile(leading: const Icon(Icons.flag_outlined), title: Text(tr('Uygunsuz içerik bildir')))),
              ],
            ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (q.type != QuestionType.multiple)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(q.type.label.toUpperCase(),
                      style: t.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.6, color: t.colorScheme.primary)),
                ),
              SelectableText(q.text, style: t.textTheme.bodyLarge?.copyWith(height: 1.45)),
              const SizedBox(height: 8),
              for (var i = 0; i < q.choices.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: q.correct.contains(i) ? NColors.emerald : Colors.transparent,
                        border: Border.all(color: q.correct.contains(i) ? NColors.emerald : t.colorScheme.outline),
                      ),
                      child: Text(String.fromCharCode(65 + i),
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 12.5, color: q.correct.contains(i) ? Colors.white : null)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(q.choices[i],
                            style: TextStyle(fontWeight: q.correct.contains(i) ? FontWeight.w700 : null)),
                      ),
                    ),
                  ]),
                ),
              if (!q.type.optical || q.type == QuestionType.trueFalse) ...[
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  decoration: BoxDecoration(
                    color: NColors.emerald.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text.rich(TextSpan(children: [
                    TextSpan(
                        text: '${q.type == QuestionType.open ? tr('Örnek cevap') : tr('Cevap')}: ',
                        style: const TextStyle(fontWeight: FontWeight.w800, color: NColors.emerald)),
                    TextSpan(text: q.answerLabel),
                  ])),
                ),
              ],
              if (q.solution.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${tr('Çözüm')}: ', style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: q.solution),
                  ]),
                  style: TextStyle(fontSize: 13, color: muted, height: 1.4),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
