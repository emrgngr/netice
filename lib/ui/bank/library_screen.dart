import 'package:material_ui/material_ui.dart';

import '../../bank/bank_models.dart';
import '../../bank/bank_store.dart';
import '../../l10n/l10n.dart';
import '../../main.dart';
import '../theme.dart';
import '../widgets.dart';
import 'ai_questions_screen.dart';
import 'bank_analysis_view.dart';
import 'bank_widgets.dart';
import 'booklet_wizard_screen.dart';
import 'import_screens.dart';
import 'note_screens.dart';
import 'question_editor_screen.dart';

/// Kütüphane: soru bankası, konu özetleri / hap bilgiler, kitapçıklar ve analiz.
class LibraryScreen extends StatefulWidget {
  /// Alt menüde sekme olarak mı açıldı (geri düğmesi yok).
  final bool embedded;
  final int initialTab;
  const LibraryScreen({super.key, this.embedded = false, this.initialTab = 0});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 4, vsync: this, initialIndex: widget.initialTab)..addListener(() => setState(() {}));

  @override
  void initState() {
    super.initState();
    if (!bank.loaded) bank.load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _addMenu() {
    final tab = _tabs.index;
    final q = [
      ActionTileData(Icons.edit_note_rounded, tr('Soru yaz'), tr('Metin, şıklar, görsel ve çözümle tek tek ekleyin'), () => QuestionEditorScreen.open(context)),
      ActionTileData(Icons.crop_rounded, tr('PDF ya da fotoğraftan kes'),
          tr('Kitap, deneme ya da yaprak test sayfasında soruları seçip hızla ekleyin'), () => CropImportScreen.start(context),
          color: NColors.ink),
      ActionTileData(Icons.auto_awesome_rounded, tr('Ders notundan üret'),
          tr('Yapay zekâ notunuzdan çoktan seçmeli soru, cevap ve çözüm önerir'), () => pickNoteForAi(context),
          color: const Color(0xFF7C5CE0)),
      ActionTileData(Icons.table_view_rounded, tr('Excel\'den aktar'), tr('Şablona yazdığınız soruları ve notları tek seferde ekleyin'),
          () => importBankExcel(context),
          color: const Color(0xFF1D6F42)),
    ];
    final n = [
      ActionTileData(Icons.bolt_rounded, tr('Hap bilgi yaz'), tr('Kısa kural, formül ya da püf noktası'),
          () => NoteEditorScreen.open(context, null, NoteKind.tip),
          color: NColors.amber),
      ActionTileData(Icons.menu_book_rounded, tr('Konu özeti yaz'), tr('Ders notunuzu elle yazın'), () => NoteEditorScreen.open(context)),
      ActionTileData(Icons.description_outlined, tr('PDF ya da Word\'den not'), tr('Belgedeki yazı nota aktarılır, düzenleyebilirsiniz'),
          () => noteFromDocument(context),
          color: NColors.ink),
      ActionTileData(Icons.photo_camera_outlined, tr('Fotoğraftan not'),
          tr('Defter ya da kitap sayfasının fotoğrafı; telefonda yazısı da okunur'), () => noteFromPhoto(context),
          color: NColors.coral),
      ActionTileData(Icons.crop_rounded, tr('PDF sayfasından kes'), tr('Sayfadaki şema, tablo ya da kutuyu nota ekleyin'),
          () => CropImportScreen.start(context, target: CropTarget.note),
          color: NColors.ink),
    ];
    final more = [
      ActionTileData(Icons.download_rounded, tr('Excel şablonunu indir'), tr('Sütunları hazır, örnekli şablon'), () => saveBankTemplate(context),
          color: NColors.gray),
      ActionTileData(Icons.inventory_2_outlined, tr('Banka paketi aç (.netbank)'), tr('Meslektaşınızın paylaştığı soru ve notları ekleyin'),
          () => importBankPack(context),
          color: NColors.gray),
    ];
    if (tab == 2) {
      BookletWizardScreen.open(context);
      return;
    }
    showActionSheet(context, tab == 1 ? tr('Not ekle') : tr('Soru ekle'), [...(tab == 1 ? n : q), ...more]);
  }

  void _menu(String v) {
    switch (v) {
      case 'template':
        saveBankTemplate(context);
      case 'excel':
        exportBankExcel(context);
      case 'pack':
        exportBankPack(context);
      case 'import':
        importBankPack(context);
      case 'importExcel':
        importBankExcel(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final fabLabel = switch (_tabs.index) {
      0 => tr('Soru ekle'),
      1 => tr('Not ekle'),
      2 => tr('Yeni kitapçık'),
      _ => null,
    };
    return ListenableBuilder(
      listenable: bank,
      builder: (context, _) => Scaffold(
        backgroundColor: widget.embedded ? Colors.transparent : null,
        appBar: AppBar(
          automaticallyImplyLeading: !widget.embedded,
          backgroundColor: widget.embedded ? Colors.transparent : null,
          titleSpacing: widget.embedded ? 20 : null,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Kütüphane'), style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            Text(
              tr('{0} soru · {1} not · {2} kitapçık', [bank.questions.length, bank.notes.length, bank.booklets.length]),
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
          ]),
          actions: [
            PopupMenuButton<String>(
              tooltip: tr('Diğer'),
              onSelected: _menu,
              itemBuilder: (_) => [
                PopupMenuItem(value: 'importExcel', child: ListTile(leading: const Icon(Icons.table_view_rounded), title: Text(tr('Excel\'den aktar')))),
                PopupMenuItem(value: 'template', child: ListTile(leading: const Icon(Icons.download_rounded), title: Text(tr('Excel şablonunu indir')))),
                PopupMenuItem(value: 'excel', child: ListTile(leading: const Icon(Icons.ios_share_rounded), title: Text(tr('Tümünü Excel\'e aktar')))),
                const PopupMenuDivider(),
                PopupMenuItem(value: 'pack', child: ListTile(leading: const Icon(Icons.inventory_2_outlined), title: Text(tr('Banka paketini paylaş')))),
                PopupMenuItem(value: 'import', child: ListTile(leading: const Icon(Icons.unarchive_outlined), title: Text(tr('Banka paketi aç (.netbank)')))),
              ],
            ),
            const SizedBox(width: 6),
          ],
          bottom: TabBar(
            controller: _tabs,
            isScrollable: !wide,
            tabAlignment: wide ? TabAlignment.fill : TabAlignment.start,
            tabs: [
              Tab(icon: const Icon(Icons.quiz_outlined, size: 20), text: tr('Sorular'), iconMargin: const EdgeInsets.only(bottom: 2)),
              Tab(icon: const Icon(Icons.sticky_note_2_outlined, size: 20), text: tr('Notlar'), iconMargin: const EdgeInsets.only(bottom: 2)),
              Tab(icon: const Icon(Icons.auto_stories_outlined, size: 20), text: tr('Kitapçıklar'), iconMargin: const EdgeInsets.only(bottom: 2)),
              Tab(icon: const Icon(Icons.insights_rounded, size: 20), text: tr('Analiz'), iconMargin: const EdgeInsets.only(bottom: 2)),
            ],
          ),
        ),
        floatingActionButton: fabLabel == null
            ? null
            : FloatingActionButton.extended(
                heroTag: 'library-fab',
                onPressed: _addMenu,
                icon: Icon(_tabs.index == 2 ? Icons.auto_stories_rounded : Icons.add_rounded),
                label: Text(fabLabel),
              ),
        body: TabBarView(controller: _tabs, children: const [
          QuestionsTab(),
          NotesTab(),
          BookletsTab(),
          BankAnalysisView(),
        ]),
      ),
    );
  }
}

// ———————————————————————————— Sorular

enum _Sort { newest, oldest, topic, difficulty }

class QuestionsTab extends StatefulWidget {
  const QuestionsTab({super.key});

  @override
  State<QuestionsTab> createState() => _QuestionsTabState();
}

class _QuestionsTabState extends State<QuestionsTab> {
  BankFilter _f = const BankFilter();
  _Sort _sort = _Sort.newest;
  final _sel = <String>{};
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<BankQuestion> _list(Map<String, int> used) {
    final l = bank.questions.where((q) => _f.matches(q, used: (used[q.id] ?? 0) > 0)).toList();
    switch (_sort) {
      case _Sort.newest:
        l.sort((a, b) => b.created.compareTo(a.created));
      case _Sort.oldest:
        l.sort((a, b) => a.created.compareTo(b.created));
      case _Sort.topic:
        BankStore.mergeSortStable(l, (a, b) {
          final s = a.subject.toLowerCase().compareTo(b.subject.toLowerCase());
          return s != 0 ? s : a.topicLabel.toLowerCase().compareTo(b.topicLabel.toLowerCase());
        });
      case _Sort.difficulty:
        BankStore.mergeSortStable(l, (a, b) => a.difficulty.index.compareTo(b.difficulty.index));
    }
    return l;
  }

  Future<void> _filters() async {
    final r = await showModalBottomSheet<BankFilter>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FilterSheet(initial: _f),
    );
    if (r != null) setState(() => _f = r);
  }

  void _delete() {
    final removed = bank.removeQuestions(_sel);
    setState(_sel.clear);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(tr('{0} soru silindi.', [removed.length])),
        duration: const Duration(seconds: 3),
        persist: false,
        action: SnackBarAction(label: tr('Geri al'), onPressed: () => bank.restoreQuestions(removed)),
      ));
  }

  Future<void> _bulkEdit() async {
    final subject = TextEditingController(), grade = TextEditingController(), topic = TextEditingController(), tag = TextEditingController();
    Difficulty? d;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('{0} soruyu toplu düzenle', [_sel.length]), style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(tr('Yalnız doldurduğunuz alanlar değişir.'), style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 14),
            SegmentedButton<Difficulty?>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: null, label: Text(tr('Aynı kalsın'))),
                for (final x in Difficulty.values) ButtonSegment(value: x, label: Text(x.label)),
              ],
              selected: {d},
              onSelectionChanged: (s) => set(() => d = s.first),
            ),
            const SizedBox(height: 12),
            SuggestField(controller: subject, label: tr('Ders'), options: () => bank.subjects),
            const SizedBox(height: 8),
            SuggestField(controller: grade, label: tr('Sınıf / düzey'), options: () => bank.grades),
            const SizedBox(height: 8),
            SuggestField(controller: topic, label: tr('Konu / ünite'), options: () => bank.topicsOf(subject.text.trim())),
            const SizedBox(height: 8),
            SuggestField(controller: tag, label: tr('Etiket ekle'), options: () => bank.tags),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Uygula'))),
          ]),
        ),
      ),
    );
    if (ok == true) {
      bank.updateMany(_sel, (q) => q.copyWith(
            difficulty: d,
            subject: subject.text.trim().isEmpty ? null : subject.text.trim(),
            grade: grade.text.trim().isEmpty ? null : grade.text.trim(),
            topic: topic.text.trim().isEmpty ? null : topic.text.trim(),
            tags: tag.text.trim().isEmpty || q.tags.contains(tag.text.trim()) ? null : [...q.tags, tag.text.trim()],
          ));
      if (mounted) toast(context, tr('{0} soru güncellendi.', [_sel.length]));
    }
    for (final c in [subject, grade, topic, tag]) {
      c.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final used = BankStore.usage(store.exams);
    final list = _list(used);
    final t = Theme.of(context);
    if (bank.questions.isEmpty) {
      return ListView(children: [
        BankEmpty(
          icon: Icons.quiz_outlined,
          title: tr('Soru bankanız boş'),
          text: tr('Sorularınızı elle yazın, kitap ya da PDF sayfasından kesin veya Excel şablonuyla toplu ekleyin. Hepsi bu cihazda saklanır.'),
          actions: [
            FilledButton.icon(onPressed: () => QuestionEditorScreen.open(context), icon: const Icon(Icons.edit_note_rounded), label: Text(tr('Soru yaz'))),
            OutlinedButton.icon(onPressed: () => CropImportScreen.start(context), icon: const Icon(Icons.crop_rounded), label: Text(tr('PDF\'ten kes'))),
            OutlinedButton.icon(onPressed: () => importBankExcel(context), icon: const Icon(Icons.table_view_rounded), label: Text(tr('Excel\'den aktar'))),
          ],
        ),
      ]);
    }
    final counts = [for (final d in Difficulty.values) bank.questions.where((q) => q.difficulty == d).length];
    return Column(children: [
      if (_sel.isNotEmpty)
        Material(
          color: NColors.emerald.withValues(alpha: 0.12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(children: [
              IconButton(tooltip: tr('Seçimi kaldır'), onPressed: () => setState(_sel.clear), icon: const Icon(Icons.close_rounded)),
              Text(tr('{0} seçili', [_sel.length]), style: const TextStyle(fontWeight: FontWeight.w800)),
              const Spacer(),
              IconButton(
                tooltip: tr('Tümünü seç'),
                onPressed: () => setState(() => _sel.addAll(list.map((q) => q.id))),
                icon: const Icon(Icons.select_all_rounded),
              ),
              IconButton(
                tooltip: tr('Bu sorularla kitapçık oluştur'),
                onPressed: () => BookletWizardScreen.open(context, questionIds: [for (final q in list) if (_sel.contains(q.id)) q.id]),
                icon: const Icon(Icons.auto_stories_rounded),
              ),
              IconButton(tooltip: tr('Toplu düzenle'), onPressed: _bulkEdit, icon: const Icon(Icons.edit_attributes_outlined)),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'excel') exportBankExcel(context, questionIds: _sel);
                  if (v == 'pack') exportBankPack(context, questionIds: _sel, noteIds: const []);
                  if (v == 'delete') _delete();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'excel', child: Text(tr('Excel\'e aktar'))),
                  PopupMenuItem(value: 'pack', child: Text(tr('Paket olarak paylaş'))),
                  PopupMenuItem(value: 'delete', child: Text(tr('Sil'), style: const TextStyle(color: NColors.coral))),
                ],
              ),
            ]),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _f = _f.copyWith(query: v)),
              decoration: InputDecoration(
                isDense: true,
                hintText: tr('Soru, konu, etiket ara'),
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () => setState(() {
                          _search.clear();
                          _f = _f.copyWith(query: '');
                        })),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Badge(
            isLabelVisible: _f.activeCount > 0,
            label: Text('${_f.activeCount}'),
            backgroundColor: NColors.emerald,
            child: IconButton.filledTonal(tooltip: tr('Süzgeç'), onPressed: _filters, icon: const Icon(Icons.tune_rounded)),
          ),
          PopupMenuButton<_Sort>(
            tooltip: tr('Sırala'),
            icon: const Icon(Icons.sort_rounded),
            initialValue: _sort,
            onSelected: (s) => setState(() => _sort = s),
            itemBuilder: (_) => [
              PopupMenuItem(value: _Sort.newest, child: Text(tr('En yeni'))),
              PopupMenuItem(value: _Sort.oldest, child: Text(tr('En eski'))),
              PopupMenuItem(value: _Sort.topic, child: Text(tr('Ders ve konuya göre'))),
              PopupMenuItem(value: _Sort.difficulty, child: Text(tr('Kolaydan zora'))),
            ],
          ),
        ]),
      ),
      SizedBox(
        height: 48,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), children: [
          ChoiceChip(
            label: Text(tr('Tümü · {0}', [bank.questions.length])),
            selected: _f.difficulties.isEmpty,
            onSelected: (_) => setState(() => _f = _f.copyWith(difficulties: {})),
          ),
          for (final d in Difficulty.values) ...[
            const SizedBox(width: 6),
            ChoiceChip(
              avatar: Icon(Icons.circle, size: 10, color: difficultyColor(d)),
              label: Text('${d.label} · ${counts[d.index]}'),
              selected: _f.difficulties.contains(d),
              selectedColor: difficultyColor(d).withValues(alpha: 0.22),
              labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600),
              onSelected: (on) => setState(() => _f = _f.copyWith(difficulties: on ? {..._f.difficulties, d} : ({..._f.difficulties}..remove(d)))),
            ),
          ],
          const SizedBox(width: 6),
          FilterChip(
            avatar: const Icon(Icons.star_rounded, size: 16, color: NColors.amber),
            label: Text(tr('Favoriler')),
            selected: _f.favoritesOnly,
            showCheckmark: false,
            onSelected: (v) => setState(() => _f = _f.copyWith(favoritesOnly: v)),
          ),
          const SizedBox(width: 6),
          FilterChip(
            label: Text(tr('Hiç kullanılmamış')),
            selected: _f.unusedOnly,
            onSelected: (v) => setState(() => _f = _f.copyWith(unusedOnly: v)),
          ),
        ]),
      ),
      Expanded(
        child: list.isEmpty
            ? ListView(children: [
                BankEmpty(
                  icon: Icons.filter_alt_off_outlined,
                  title: tr('Eşleşen soru yok'),
                  text: tr('Süzgeçleri gevşetin ya da aramayı temizleyin.'),
                  actions: [
                    TextButton(
                        onPressed: () => setState(() {
                              _search.clear();
                              _f = const BankFilter();
                            }),
                        child: Text(tr('Süzgeçleri temizle'))),
                  ],
                ),
              ])
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                itemCount: list.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
                      child: Text(tr('{0} soru listeleniyor', [list.length]),
                          style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.onSurface.withValues(alpha: 0.55))),
                    );
                  }
                  final q = list[i - 1];
                  final selected = _sel.contains(q.id);
                  return QuestionCard(
                    q: q,
                    used: used[q.id] ?? 0,
                    selected: selected,
                    selecting: _sel.isNotEmpty,
                    onTap: () => _sel.isNotEmpty
                        ? setState(() => selected ? _sel.remove(q.id) : _sel.add(q.id))
                        : QuestionEditorScreen.open(context, q),
                    onLongPress: () => setState(() => selected ? _sel.remove(q.id) : _sel.add(q.id)),
                  );
                },
              ),
      ),
    ]);
  }
}

class QuestionCard extends StatelessWidget {
  final BankQuestion q;
  final int used;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  const QuestionCard({
    super.key,
    required this.q,
    this.used = 0,
    this.selected = false,
    this.selecting = false,
    required this.onTap,
    this.onLongPress,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    final c = difficultyColor(q.difficulty);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? NColors.emerald : Colors.transparent, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 5, color: c),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (selecting)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                          color: selected ? NColors.emerald : muted),
                    ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(typeIcon(q.type), size: 15, color: muted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            [q.subject, q.grade, q.topicLabel].where((s) => s.trim().isNotEmpty).toSet().join(' · ').ifEmpty(tr('Konu yazılmamış')),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.textTheme.labelMedium?.copyWith(color: muted, fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (q.favorite) const Icon(Icons.star_rounded, size: 16, color: NColors.amber),
                      ]),
                      const SizedBox(height: 6),
                      if (q.text.trim().isNotEmpty)
                        Text(q.text.trim(), maxLines: 3, overflow: TextOverflow.ellipsis, style: t.textTheme.bodyMedium?.copyWith(height: 1.35)),
                      if (q.imageId != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: ColoredBox(
                              color: Colors.white,
                              child: Align(alignment: AlignmentDirectional.centerStart, child: BankImage(q.imageId, height: q.text.trim().isEmpty ? 110 : 64)),
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        DifficultyPill(q.difficulty),
                        if (q.type.optical || q.answerText.isNotEmpty)
                          Pill(q.answerLabel.isEmpty ? tr('Cevap yok') : tr('Cevap: {0}', [q.answerLabel]),
                              color: q.complete ? NColors.ink : NColors.coral, icon: q.complete ? Icons.check_rounded : Icons.error_outline_rounded),
                        if (!q.complete && !q.type.optical) Pill(tr('Eksik'), color: NColors.coral, icon: Icons.error_outline_rounded),
                        if (used > 0) Pill(tr('{0} sınavda', [used]), color: NColors.gray, icon: Icons.history_rounded),
                        if (q.hasSolution) Pill(tr('Çözümlü'), color: NColors.emerald, icon: Icons.lightbulb_outline_rounded),
                      ]),
                    ]),
                  ),
                  ?trailing,
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Ayrıntılı süzgeç.
class FilterSheet extends StatefulWidget {
  final BankFilter initial;
  final bool notes;
  const FilterSheet({super.key, required this.initial, this.notes = false});

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late BankFilter _f = widget.initial;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    Widget head(String s) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(s, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        );
    final topics = _f.subjects.isEmpty ? bank.topicsOf() : {for (final s in _f.subjects) ...bank.topicsOf(s)}.toList();
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (context, scroll) => Column(children: [
          Expanded(
            child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 12), children: [
              Text(tr('Süzgeç'), style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              if (bank.subjects.isNotEmpty) ...[
                head(tr('Ders')),
                ChoiceChips<String>(values: bank.subjects, selected: _f.subjects, label: (s) => s, onChanged: (s) => setState(() => _f = _f.copyWith(subjects: s))),
              ],
              if (bank.grades.isNotEmpty) ...[
                head(tr('Sınıf / düzey')),
                ChoiceChips<String>(values: bank.grades, selected: _f.grades, label: (s) => s, onChanged: (s) => setState(() => _f = _f.copyWith(grades: s))),
              ],
              if (topics.isNotEmpty) ...[
                head(tr('Konu')),
                ChoiceChips<String>(values: topics, selected: _f.topics, label: (s) => s, onChanged: (s) => setState(() => _f = _f.copyWith(topics: s))),
              ],
              if (!widget.notes) ...[
                head(tr('Zorluk')),
                ChoiceChips<Difficulty>(
                  values: Difficulty.values,
                  selected: _f.difficulties,
                  label: (d) => d.label,
                  color: difficultyColor,
                  onChanged: (s) => setState(() => _f = _f.copyWith(difficulties: s)),
                ),
                head(tr('Soru türü')),
                ChoiceChips<QuestionType>(values: QuestionType.values, selected: _f.types, label: (d) => d.label, onChanged: (s) => setState(() => _f = _f.copyWith(types: s))),
              ],
              if (bank.tags.isNotEmpty) ...[
                head(tr('Etiket')),
                ChoiceChips<String>(values: bank.tags, selected: _f.tags, label: (s) => '#$s', onChanged: (s) => setState(() => _f = _f.copyWith(tags: s))),
              ],
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Yalnız favoriler')),
                value: _f.favoritesOnly,
                onChanged: (v) => setState(() => _f = _f.copyWith(favoritesOnly: v)),
              ),
              if (!widget.notes)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Yalnız hiç sınavda kullanılmamışlar')),
                  value: _f.unusedOnly,
                  onChanged: (v) => setState(() => _f = _f.copyWith(unusedOnly: v)),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(children: [
              TextButton(onPressed: () => Navigator.pop(context, BankFilter(query: _f.query)), child: Text(tr('Temizle'))),
              const Spacer(),
              FilledButton(onPressed: () => Navigator.pop(context, _f), child: Text(tr('Uygula'))),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ———————————————————————————— Notlar

class NotesTab extends StatefulWidget {
  const NotesTab({super.key});

  @override
  State<NotesTab> createState() => _NotesTabState();
}

class _NotesTabState extends State<NotesTab> {
  BankFilter _f = const BankFilter();
  NoteKind? _kind;
  final _sel = <String>{};

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (bank.notes.isEmpty) {
      return ListView(children: [
        BankEmpty(
          icon: Icons.sticky_note_2_outlined,
          title: tr('Henüz not yok'),
          text: tr('Konu özetleri ve hap bilgiler ekleyin. Sınav analizinde zayıf çıkan konular için bu notlar öğrenciye ve veliye önerilir.'),
          actions: [
            FilledButton.icon(
                onPressed: () => NoteEditorScreen.open(context, null, NoteKind.tip), icon: const Icon(Icons.bolt_rounded), label: Text(tr('Hap bilgi yaz'))),
            OutlinedButton.icon(onPressed: () => noteFromDocument(context), icon: const Icon(Icons.description_outlined), label: Text(tr('PDF / Word / Excel\'den'))),
            OutlinedButton.icon(onPressed: () => noteFromPhoto(context), icon: const Icon(Icons.photo_camera_outlined), label: Text(tr('Fotoğraftan'))),
          ],
        ),
      ]);
    }
    final list = bank.notes.where((n) => (_kind == null || n.kind == _kind) && _f.matchesNote(n)).toList()
      ..sort((a, b) {
        final s = a.subject.toLowerCase().compareTo(b.subject.toLowerCase());
        if (s != 0) return s;
        final tp = a.topicLabel.toLowerCase().compareTo(b.topicLabel.toLowerCase());
        return tp != 0 ? tp : b.kind.index.compareTo(a.kind.index);
      });
    return Column(children: [
      if (_sel.isNotEmpty)
        Material(
          color: NColors.emerald.withValues(alpha: 0.12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(children: [
              IconButton(onPressed: () => setState(_sel.clear), icon: const Icon(Icons.close_rounded)),
              Text(tr('{0} seçili', [_sel.length]), style: const TextStyle(fontWeight: FontWeight.w800)),
              const Spacer(),
              IconButton(
                tooltip: tr('Çalışma föyü (PDF)'),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                onPressed: () => openNotesPdf(context, [for (final n in list) if (_sel.contains(n.id)) n], title: tr('Çalışma föyü')),
              ),
              IconButton(
                tooltip: tr('Paket olarak paylaş'),
                icon: const Icon(Icons.ios_share_rounded),
                onPressed: () => exportBankPack(context, questionIds: const [], noteIds: _sel),
              ),
              IconButton(
                tooltip: tr('Sil'),
                icon: const Icon(Icons.delete_outline_rounded, color: NColors.coral),
                onPressed: () {
                  final removed = bank.removeNotes(_sel);
                  setState(_sel.clear);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    behavior: SnackBarBehavior.floating,
                    content: Text(tr('{0} not silindi.', [removed.length])),
                    duration: const Duration(seconds: 3),
                    persist: false,
                    action: SnackBarAction(label: tr('Geri al'), onPressed: () => bank.restoreNotes(removed)),
                  ));
                },
              ),
            ]),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() => _f = _f.copyWith(query: v)),
              decoration: InputDecoration(isDense: true, hintText: tr('Not ara'), prefixIcon: const Icon(Icons.search_rounded)),
            ),
          ),
          const SizedBox(width: 8),
          Badge(
            isLabelVisible: _f.activeCount > 0,
            label: Text('${_f.activeCount}'),
            backgroundColor: NColors.emerald,
            child: IconButton.filledTonal(
              tooltip: tr('Süzgeç'),
              icon: const Icon(Icons.tune_rounded),
              onPressed: () async {
                final r = await showModalBottomSheet<BankFilter>(
                    context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => FilterSheet(initial: _f, notes: true));
                if (r != null) setState(() => _f = r);
              },
            ),
          ),
          IconButton(
            tooltip: tr('Listedekilerden çalışma föyü (PDF)'),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: list.isEmpty ? null : () => openNotesPdf(context, list, title: tr('Çalışma föyü')),
          ),
        ]),
      ),
      SizedBox(
        height: 48,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), children: [
          ChoiceChip(label: Text(tr('Tümü · {0}', [bank.notes.length])), selected: _kind == null, onSelected: (_) => setState(() => _kind = null)),
          for (final k in NoteKind.values) ...[
            const SizedBox(width: 6),
            ChoiceChip(
              avatar: Icon(noteIcon(k), size: 16, color: noteColor(k)),
              label: Text('${k.label} · ${bank.notes.where((n) => n.kind == k).length}'),
              selected: _kind == k,
              selectedColor: noteColor(k).withValues(alpha: 0.2),
              labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600),
              onSelected: (on) => setState(() => _kind = on ? k : null),
            ),
          ],
        ]),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final n = list[i];
            final c = noteColor(n.kind);
            final sel = _sel.contains(n.id);
            final showHead = i == 0 || list[i - 1].subject != n.subject;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (showHead)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
                  child: Text(n.subject.isEmpty ? tr('Ders yazılmamış') : n.subject,
                      style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: t.colorScheme.onSurface.withValues(alpha: 0.7))),
                ),
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: sel ? NColors.emerald : Colors.transparent, width: 2),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                  leading: IconBadge(noteIcon(n.kind), color: c, size: 42),
                  title: Text(n.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (n.topicLabel.isNotEmpty && n.topicLabel != n.displayTitle)
                      Text(n.topicLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 12.5)),
                    if (n.body.isNotEmpty) Text(n.body.replaceAll('\n', ' '), maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (n.body.isEmpty && n.imageIds.isNotEmpty) Text(tr('{0} görsel', [n.imageIds.length])),
                  ]),
                  trailing: _sel.isNotEmpty
                      ? Icon(sel ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: sel ? NColors.emerald : null)
                      : (n.favorite ? const Icon(Icons.star_rounded, color: NColors.amber) : null),
                  onTap: () => _sel.isNotEmpty ? setState(() => sel ? _sel.remove(n.id) : _sel.add(n.id)) : NoteViewScreen.open(context, n),
                  onLongPress: () => setState(() => sel ? _sel.remove(n.id) : _sel.add(n.id)),
                ),
              ),
            ]);
          },
        ),
      ),
    ]);
  }
}

// ———————————————————————————— Kitapçıklar

class BookletsTab extends StatelessWidget {
  const BookletsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final store = StoreScope.of(context);
    final list = [...bank.booklets]..sort((a, b) => b.updated.compareTo(a.updated));
    if (list.isEmpty) {
      return ListView(children: [
        BankEmpty(
          icon: Icons.auto_stories_outlined,
          title: tr('Soru kitapçığı oluşturun'),
          text: tr('Bankadan soruları elle ya da zorluk oranına göre otomatik seçin; A–H kitapçıklarını, cevap anahtarını ve optik okunabilir sınavı tek adımda hazırlayın.'),
          actions: [
            FilledButton.icon(
              onPressed: bank.questions.isEmpty ? null : () => BookletWizardScreen.open(context),
              icon: const Icon(Icons.auto_stories_rounded),
              label: Text(tr('Yeni kitapçık')),
            ),
          ],
        ),
        if (bank.questions.isEmpty)
          Center(child: Text(tr('Önce bankaya soru ekleyin.'), style: TextStyle(color: t.colorScheme.onSurface.withValues(alpha: 0.6)))),
      ]);
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final b = list[i];
        final qs = [for (final id in b.questionIds) ?bank.questionById(id)];
        final diff = [for (final d in Difficulty.values) qs.where((q) => q.difficulty == d).length];
        final exams = b.examIds.where((id) => store.examById(id) != null).length;
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => BookletWizardScreen.open(context, booklet: b),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Container(
                  width: 54,
                  height: 68,
                  decoration: BoxDecoration(gradient: inkGradient, borderRadius: BorderRadius.circular(8)),
                  alignment: Alignment.center,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(b.options.bookletCount > 1 ? 'A–${letter(b.options.bookletCount - 1)}' : 'A',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                    Text('${qs.length}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ]),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(b.name.isEmpty ? tr('Adsız kitapçık') : b.name, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      tr('{0} soru · {1} kitapçık · {2}', [qs.length, b.options.bookletCount, dmy(b.updated)]),
                      style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurface.withValues(alpha: 0.6)),
                    ),
                    const SizedBox(height: 8),
                    DifficultyBar(counts: diff, height: 7),
                    if (exams > 0) ...[
                      const SizedBox(height: 8),
                      Pill(tr('{0} sınıfta sınav yapıldı', [exams]), icon: Icons.fact_check_outlined),
                    ],
                  ]),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'copy') {
                      final now = DateTime.now();
                      bank.upsertBooklet(Booklet(
                        id: BankStore.newId('k'),
                        name: tr('{0} (kopya)', [b.name]),
                        questionIds: b.questionIds,
                        options: b.options,
                        created: now,
                        updated: now,
                      ));
                    }
                    if (v == 'delete') {
                      final removed = bank.removeBooklets([b.id]);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        behavior: SnackBarBehavior.floating,
                        content: Text(tr('Kitapçık silindi. Sorular bankada kalır.')),
                        duration: const Duration(seconds: 3),
                        persist: false,
                        action: SnackBarAction(label: tr('Geri al'), onPressed: () => bank.restoreBooklets(removed)),
                      ));
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'copy', child: Text(tr('Kopyasını oluştur'))),
                    PopupMenuItem(value: 'delete', child: Text(tr('Sil'), style: const TextStyle(color: NColors.coral))),
                  ],
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// Kolay / orta / zor oranı çubuğu.
class DifficultyBar extends StatelessWidget {
  final List<int> counts;
  final double height;
  const DifficultyBar({super.key, required this.counts, this.height = 10});

  @override
  Widget build(BuildContext context) {
    final total = counts.fold(0, (a, b) => a + b);
    if (total == 0) {
      return Container(height: height, decoration: BoxDecoration(color: NColors.gray.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(height)));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final d in Difficulty.values)
            if (counts[d.index] > 0) Expanded(flex: counts[d.index], child: ColoredBox(color: difficultyColor(d))),
        ]),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => trim().isEmpty ? other : this;
}
