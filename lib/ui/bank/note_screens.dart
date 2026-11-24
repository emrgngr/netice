import 'package:material_ui/material_ui.dart';

import '../../bank/bank_models.dart';
import '../../l10n/l10n.dart';
import '../../main.dart';
import '../../reports/notes_pdf.dart';
import '../report_preview_screen.dart';
import '../theme.dart';
import '../widgets.dart';
import 'ai_questions_screen.dart';
import 'bank_widgets.dart';
import 'image_tools.dart';

Color noteColor(NoteKind k) => k == NoteKind.tip ? NColors.amber : NColors.emerald;
IconData noteIcon(NoteKind k) => k == NoteKind.tip ? Icons.bolt_rounded : Icons.menu_book_rounded;

/// Konu özeti / hap bilgi düzenleyici.
class NoteEditorScreen extends StatefulWidget {
  final BankNote note;
  final bool isNew;
  const NoteEditorScreen({super.key, required this.note, this.isNew = true});

  /// [note] verilmezse boş yeni not; bankada varsa düzenleme.
  static Future<void> open(BuildContext context, [BankNote? note, NoteKind kind = NoteKind.summary]) {
    final n = note ?? bank.newNote(kind: kind);
    return Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => NoteEditorScreen(note: n, isNew: bank.noteById(n.id) == null)));
  }

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late BankNote _n = widget.note;
  late final _title = TextEditingController(text: _n.title);
  late final _body = TextEditingController(text: _n.body);
  late final _subject = TextEditingController(text: _n.subject.isEmpty && widget.isNew ? bank.lastSubject : _n.subject);
  late final _grade = TextEditingController(text: _n.grade.isEmpty && widget.isNew ? bank.lastGrade : _n.grade);
  late final _topic = TextEditingController(text: _n.topic.isEmpty && widget.isNew ? bank.lastTopic : _n.topic);
  late final _outcome = TextEditingController(text: _n.outcome);
  late final _tags = TextEditingController(text: _n.tags.join(', '));
  late final _source = TextEditingController(text: _n.source);
  late bool _dirty = widget.isNew && (_n.body.isNotEmpty || _n.imageIds.isNotEmpty);

  @override
  void dispose() {
    for (final c in [_title, _body, _subject, _grade, _topic, _outcome, _tags, _source]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final n = _n.copyWith(
      title: _title.text.trim(),
      body: _body.text.trim(),
      subject: _subject.text.trim(),
      grade: _grade.text.trim(),
      topic: _topic.text.trim(),
      outcome: _outcome.text.trim(),
      tags: [for (final t in _tags.text.split(RegExp(r'[,;]'))) if (t.trim().isNotEmpty) t.trim()],
      source: _source.text.trim(),
    );
    if (n.body.isEmpty && n.imageIds.isEmpty && n.title.isEmpty) return toast(context, tr('Notun metnini yazın ya da görsel ekleyin.'));
    if (n.topic.isEmpty && n.outcome.isEmpty) {
      toast(context, tr('İpucu: konu yazarsanız not, analizde o konuda zayıf öğrencilere önerilir.'));
    }
    bank.upsertNote(n);
    _dirty = false;
    Navigator.pop(context);
  }

  Future<void> _addImage() async {
    final b = await pickBankImage(context);
    if (b == null) return;
    final id = await bank.saveImage(b);
    setState(() {
      _n = _n.copyWith(imageIds: [..._n.imageIds, id]);
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = noteColor(_n.kind);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (popped, _) async {
        if (popped) return;
        final r = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr('Değişiklikler kaydedilsin mi?')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: Text(tr('Kaydetme'))),
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Vazgeç'))),
              FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: Text(tr('Kaydet'))),
            ],
          ),
        );
        if (!context.mounted) return;
        if (r == 'save') _save();
        if (r == 'discard') {
          _dirty = false;
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.isNew ? tr('Yeni not') : tr('Notu düzenle')),
          actions: [
            Padding(padding: const EdgeInsets.only(right: 10), child: FilledButton(onPressed: _save, child: Text(tr('Kaydet')))),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 32), children: [
                SegmentedButton<NoteKind>(
                  segments: [
                    for (final k in NoteKind.values) ButtonSegment(value: k, label: Text(k.label), icon: Icon(noteIcon(k))),
                  ],
                  selected: {_n.kind},
                  onSelectionChanged: (s) => setState(() {
                    _n = _n.copyWith(kind: s.first);
                    _dirty = true;
                  }),
                ),
                const SizedBox(height: 6),
                Text(
                  _n.kind == NoteKind.tip
                      ? tr('Hap bilgi: kısa, akılda kalıcı kural ya da formül. Karnelerde ve zayıf konu önerilerinde önce bunlar çıkar.')
                      : tr('Konu özeti: konunun ders notu ya da özeti. Çalışma föylerine eklenir.'),
                  style: TextStyle(fontSize: 12.5, color: t.colorScheme.onSurface.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _title,
                  onChanged: (_) => _dirty = true,
                  textCapitalization: TextCapitalization.sentences,
                  style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  decoration: InputDecoration(labelText: tr('Başlık'), prefixIcon: Icon(noteIcon(_n.kind), color: c)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _body,
                  onChanged: (_) => _dirty = true,
                  minLines: 8,
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    alignLabelWithHint: true,
                    labelText: tr('Metin'),
                    hintText: tr('Konu özetini, kuralı ya da formülü yazın…'),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final id in _n.imageIds)
                    Stack(children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: t.colorScheme.outlineVariant),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.all(4),
                        child: BankImage(id, height: 120, width: 160),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: IconButton.filledTonal(
                          visualDensity: VisualDensity.compact,
                          tooltip: tr('Kaldır'),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () => setState(() {
                            _n = _n.copyWith(imageIds: [..._n.imageIds]..remove(id));
                            _dirty = true;
                          }),
                        ),
                      ),
                    ]),
                  OutlinedButton.icon(onPressed: _addImage, icon: const Icon(Icons.add_photo_alternate_outlined), label: Text(tr('Görsel ekle'))),
                ]),
                const SizedBox(height: 18),
                SectionTitle(tr('Hangi konuya ait?')),
                SuggestField(controller: _subject, label: tr('Ders'), icon: Icons.menu_book_outlined, options: () => bank.subjects, onChanged: (_) => _dirty = true),
                const SizedBox(height: 10),
                SuggestField(controller: _grade, label: tr('Sınıf / düzey'), icon: Icons.stairs_outlined, options: () => bank.grades, onChanged: (_) => _dirty = true),
                const SizedBox(height: 10),
                SuggestField(controller: _topic, label: tr('Konu / ünite'), icon: Icons.topic_outlined, options: () => bank.topicsOf(_subject.text.trim()), onChanged: (_) => _dirty = true),
                const SizedBox(height: 10),
                SuggestField(controller: _outcome, label: tr('Kazanım (isteğe bağlı)'), icon: Icons.flag_outlined, options: () => bank.outcomesOf(_subject.text.trim()), onChanged: (_) => _dirty = true),
                const SizedBox(height: 10),
                TextField(
                  controller: _tags,
                  onChanged: (_) => _dirty = true,
                  decoration: InputDecoration(labelText: tr('Etiketler'), hintText: tr('virgülle ayırın: deneme, LGS, tekrar'), prefixIcon: const Icon(Icons.tag_rounded)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _source,
                  onChanged: (_) => _dirty = true,
                  decoration: InputDecoration(labelText: tr('Kaynak (isteğe bağlı)'), prefixIcon: const Icon(Icons.bookmark_border_rounded)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Notu okuma ekranı.
class NoteViewScreen extends StatelessWidget {
  final String noteId;
  const NoteViewScreen({super.key, required this.noteId});

  static Future<void> open(BuildContext context, BankNote n) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => NoteViewScreen(noteId: n.id)));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: bank,
        builder: (context, _) {
          final n = bank.noteById(noteId);
          if (n == null) return const Scaffold();
          final t = Theme.of(context);
          final c = noteColor(n.kind);
          return Scaffold(
            appBar: AppBar(actions: [
              IconButton(
                tooltip: tr('Favori'),
                icon: Icon(n.favorite ? Icons.star_rounded : Icons.star_outline_rounded, color: n.favorite ? NColors.amber : null),
                onPressed: () => bank.upsertNote(n.copyWith(favorite: !n.favorite)),
              ),
              IconButton(
                tooltip: tr('PDF olarak yazdır / paylaş'),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                onPressed: () => openNotesPdf(context, [n], title: n.displayTitle),
              ),
              IconButton(tooltip: tr('Düzenle'), icon: const Icon(Icons.edit_outlined), onPressed: () => NoteEditorScreen.open(context, n)),
              const SizedBox(width: 4),
            ]),
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 40), children: [
                  Row(children: [
                    Pill(n.kind.label, color: c, icon: noteIcon(n.kind)),
                    const SizedBox(width: 8),
                    if (n.subject.isNotEmpty) Flexible(child: Pill(n.subject, color: NColors.ink)),
                    if (n.grade.isNotEmpty) ...[const SizedBox(width: 8), Pill(n.grade, color: NColors.gray)],
                  ]),
                  const SizedBox(height: 12),
                  Text(n.displayTitle, style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  if (n.topicLabel.isNotEmpty && n.topicLabel != n.displayTitle)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(n.topicLabel, style: TextStyle(color: t.colorScheme.onSurface.withValues(alpha: 0.6))),
                    ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FilledButton.tonalIcon(
                      onPressed: () => AiQuestionsScreen.open(context, n),
                      icon: const Icon(Icons.auto_awesome_rounded),
                      label: Text(tr('Bu nottan soru üret')),
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (n.body.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(16),
                        border: BorderDirectional(start: BorderSide(color: c, width: 4)),
                      ),
                      child: SelectableText(n.body, style: t.textTheme.bodyLarge?.copyWith(height: 1.55)),
                    ),
                  for (final id in n.imageIds)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: ClipRRect(borderRadius: BorderRadius.circular(12), child: ColoredBox(color: Colors.white, child: BankImage(id))),
                    ),
                  if (n.tags.isNotEmpty || n.source.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final tag in n.tags) Pill('#$tag', color: NColors.gray),
                      if (n.source.isNotEmpty) Pill(n.source, color: NColors.gray, icon: Icons.bookmark_border_rounded),
                    ]),
                  ],
                ]),
              ),
            ),
          );
        },
      );
}

/// Notlardan çalışma föyü PDF'i.
Future<void> openNotesPdf(BuildContext context, List<BankNote> notes, {required String title, List<NotesSection>? sections}) {
  final store = StoreScope.of(context);
  return ReportPreviewScreen.open(
    context,
    title: title,
    fileName: '${safeFileName(title)}.pdf',
    build: () => buildNotesPdf(
      title: title,
      subtitle: store.reportSchool.name,
      school: store.reportSchool,
      sections: sections ?? [NotesSection('', notes)],
      image: bank.imageBytes,
    ),
  );
}
