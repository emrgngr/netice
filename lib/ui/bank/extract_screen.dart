// "Belgeden soruları ayıkla": test kitabı, yaprak test, çıkmış sınav ya da
// soru bankası belgesindeki (PDF, Word, fotoğraf) hazır sorular yapay zekâyla
// kökü, şıkları, cevabı ve konusuyla bankaya alınır.
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:printing/printing.dart';

import '../../bank/ai_extract.dart';
import '../../bank/ai_questions.dart';
import '../../bank/bank_models.dart';
import '../../core/doc_text.dart';
import '../../core/pro.dart';
import '../../l10n/l10n.dart';
import '../../main.dart';
import '../pro_screen.dart';
import '../service_cards.dart';
import '../theme.dart';
import '../widgets.dart';
import 'bank_widgets.dart';
import 'image_tools.dart';

bool get _mobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

class _Item {
  final ExtractedQuestion e;
  bool selected;
  bool added = false;
  _Item(this.e) : selected = e.source != AnswerSource.unknown || !e.q.type.optical;
}

class ExtractQuestionsScreen extends StatefulWidget {
  /// Önizleme ve testler için hazır sonuç.
  final List<ExtractedQuestion> initial;
  final String initialName;
  const ExtractQuestionsScreen({super.key, this.initial = const [], this.initialName = ''});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ExtractQuestionsScreen()));

  @override
  State<ExtractQuestionsScreen> createState() => _ExtractQuestionsScreenState();
}

class _ExtractQuestionsScreenState extends State<ExtractQuestionsScreen> {
  final _subject = TextEditingController();
  final _grade = TextEditingController();
  late String _name = widget.initialName;
  String _text = '';
  List<Uint8List> _pages = const [];
  bool _solve = true;
  bool _keyLast = false;
  bool _loading = false;
  bool _busy = false;
  int _done = 0;
  int _total = 0;
  String? _error;
  final _problems = <String>[];
  late final List<_Item> _items = widget.initial.map(_Item.new).toList();
  final _usage = AiUsage.instance;

  bool get _hasSource => _text.trim().isNotEmpty || _pages.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _usage.load();
  }

  @override
  void dispose() {
    _subject.dispose();
    _grade.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: tr('Soru bankası belgesi'),
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'txt', 'md', 'png', 'jpg', 'jpeg', 'webp'],
    );
    if (files.isEmpty || !mounted) return;
    setState(() => _loading = true);
    try {
      final f = files.first;
      final bytes = await f.readAsBytes();
      final name = f.name.toLowerCase();
      var text = '';
      var pages = <Uint8List>[];
      if (name.endsWith('.txt') || name.endsWith('.md')) {
        text = utf8.decode(bytes, allowMalformed: true);
      } else if (name.endsWith('.pdf') || name.endsWith('.docx')) {
        text = await compute((List<Object> a) => documentText(a[0] as Uint8List, a[1] as String), [bytes, name]);
        // Taranmış PDF: yazı yok, sayfalar görsel olarak gönderilir.
        if (name.endsWith('.pdf') && text.trim().length < 200) {
          text = '';
          await for (final r in Printing.raster(bytes, dpi: 150)) {
            pages.add(await r.toPng());
            if (pages.length >= extractMaxPages + 1) break;
          }
        }
      } else {
        pages = [await cropBytes(bytes, null, maxW: 2000)];
      }
      if (!mounted) return;
      setState(() {
        _name = f.name.replaceAll(RegExp(r'\.[^.]+$'), '').replaceAll('_', ' ');
        _text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
        _pages = pages;
        _keyLast = false;
      });
      if (!_hasSource) toast(context, tr('Belgeden yazı okunamadı.'));
    } catch (e) {
      if (mounted) toast(context, tr('Okunamadı: {0}', [e]));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickPhotos({bool camera = false}) async {
    final picker = ImagePicker();
    final files = camera
        ? [await picker.pickImage(source: ImageSource.camera, requestFullMetadata: false)].whereType<XFile>().toList()
        : await picker.pickMultiImage(requestFullMetadata: false);
    if (files.isEmpty || !mounted) return;
    setState(() => _loading = true);
    try {
      final pages = [for (final f in files) await cropBytes(await f.readAsBytes(), null, maxW: 2000)];
      if (!mounted) return;
      setState(() {
        _pages = camera ? [..._pages, ...pages] : pages;
        _text = '';
        _name = tr('Fotoğraflar');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _askConsent() async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.cloud_upload_outlined),
        title: Text(tr('Belge internet üzerinden gönderilecek')),
        content: Text(tr('Soruları ayıklamak için belgenin metni ya da sayfa görüntüleri Netice\'nin soru sunucusu üzerinden yapay zekâ hizmetine (Anthropic Claude) gönderilir. Netice belgeyi saklamaz; Anthropic de bu içeriği yapay zekâ eğitiminde kullanmaz.\n\nYalnız kullanma hakkınız olan belgeleri gönderin; öğrenci adı ya da numarası gibi kişisel bilgi içeren belgeleri göndermeyin.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Vazgeç'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Anladım, devam et'))),
        ],
      ),
    );
    return r ?? false;
  }

  Future<void> _run() async {
    if (_busy || !_hasSource) return;
    final store = StoreScope.of(context);
    final tier = AiUsage.tierOf(store);
    if (_usage.remaining(tier) <= 0) {
      toast(context, quotaMessage(tier));
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const ProScreen(feature: ProFeature.aiQuestions), fullscreenDialog: true));
      return;
    }
    if (!_usage.consent) {
      if (!await _askConsent()) return;
      _usage.giveConsent();
    }
    final chunks = extractChunks(text: _text, pages: _pages, keyLastPage: _keyLast);
    setState(() {
      _busy = true;
      _error = null;
      _problems.clear();
      _done = 0;
      _total = chunks.length;
    });
    try {
      for (final c in chunks) {
        final r = await extractQuestions(c,
            usage: _usage, tier: tier, subject: _subject.text.trim(), grade: _grade.text.trim(), sourceName: _name, solve: _solve);
        if (!mounted) return;
        setState(() {
          _items.addAll(r.questions.map(_Item.new));
          _done++;
          if (r.problem.isNotEmpty) _problems.add(r.problem);
        });
      }
      if (_items.isEmpty && mounted) setState(() => _error = tr('Bu belgede soru bulunamadı.'));
    } on AiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addSelected() async {
    final list = [for (final it in _items) if (it.selected && !it.added) it];
    if (list.isEmpty) return;
    final qs = <BankQuestion>[];
    for (final it in list) {
      var q = it.e.q.copyWith(updated: DateTime.now());
      // Şekle dayanan soruya sayfanın görüntüsü eklenir (sonra kırpılabilir).
      if (it.e.needsFigure && it.e.page != null && q.imageId == null) {
        q = q.copyWith(imageId: await bank.saveImage(it.e.page!));
      }
      qs.add(q);
    }
    bank.addQuestions(qs);
    if (!mounted) return;
    setState(() {
      for (final it in list) {
        it.added = true;
      }
    });
    final missing = list.where((it) => it.e.source == AnswerSource.unknown && it.e.q.type.optical).length;
    toast(
        context,
        missing > 0
            ? tr('{0} soru bankaya eklendi. Cevabı olmayan {1} soru listede "eksik" görünür.', [list.length, missing])
            : tr('{0} soru bankaya eklendi.', [list.length]));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurfaceVariant;
    final selected = _items.where((i) => i.selected && !i.added).length;
    final fromDoc = _items.where((i) => i.e.source == AnswerSource.document).length;
    final solved = _items.where((i) => i.e.source == AnswerSource.solved).length;
    final unknown = _items.where((i) => i.e.source == AnswerSource.unknown).length;

    final intro = RoundedPanel(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const IconBadge(Icons.document_scanner_rounded, color: Color(0xFF7C5CE0)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Hazır sorular, bankanıza tek seferde'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                  tr('Test kitabı, yaprak test, çıkmış sınav ya da soru bankası belgenizi seçin. Yapay zekâ soruları kökü, şıkları, cevabı ve konusuyla aynen ayıklar; cevap anahtarını belgenin sonunda bile bulur. Siz kontrol edip seçtiklerinizi eklersiniz.'),
                  style: TextStyle(color: muted, height: 1.4)),
            ]),
          ),
        ]),
      ),
    );

    final sourceButtons = Wrap(spacing: 10, runSpacing: 10, children: [
      FilledButton.icon(
          onPressed: _loading || _busy ? null : _pickFile,
          icon: const Icon(Icons.upload_file_rounded),
          label: Text(_hasSource ? tr('Başka belge seç') : tr('PDF, Word ya da görsel seç'))),
      if (_mobile) ...[
        OutlinedButton.icon(
            onPressed: _loading || _busy ? null : () => _pickPhotos(camera: true),
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(_pages.isNotEmpty ? tr('Bir sayfa daha çek') : tr('Sayfanın fotoğrafını çek'))),
        OutlinedButton.icon(
            onPressed: _loading || _busy ? null : _pickPhotos,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(tr('Galeriden fotoğraflar'))),
      ],
    ]);

    final words = _text.isEmpty ? 0 : _text.split(RegExp(r'\s+')).length;
    final setup = !_hasSource
        ? const SizedBox.shrink()
        : RoundedPanel(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(_pages.isNotEmpty ? Icons.image_outlined : Icons.description_outlined, color: muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        [
                          _name,
                          if (_pages.isNotEmpty) tr('{0} sayfa', [_pages.length]),
                          if (words > 0) tr('{0} kelime', [words]),
                        ].where((s) => s.isNotEmpty).join(' · '),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: _subject,
                          decoration: InputDecoration(labelText: tr('Ders (isteğe bağlı)'), hintText: tr('ör. Matematik')))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: TextField(
                          controller: _grade,
                          decoration: InputDecoration(labelText: tr('Sınıf / düzey (isteğe bağlı)'), hintText: tr('ör. 8, TYT, KPSS')))),
                ]),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _solve,
                  onChanged: _busy ? null : (v) => setState(() => _solve = v),
                  title: Text(tr('Cevabı olmayan soruları yapay zekâ çözsün')),
                  subtitle: Text(tr('Bu sorular "kontrol edin" diye işaretlenir.')),
                ),
                if (_pages.length > 1)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _keyLast,
                    onChanged: _busy ? null : (v) => setState(() => _keyLast = v),
                    title: Text(tr('Son sayfa cevap anahtarı')),
                    subtitle: Text(tr('Cevaplar her sayfadaki sorularla eşleştirilir.')),
                  ),
                const SizedBox(height: 8),
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 14, runSpacing: 8, children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _run,
                    icon: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.auto_awesome_rounded),
                    label: Text(_busy ? tr('Ayıklanıyor… {0}/{1}', [_done, _total]) : tr('Soruları ayıkla')),
                  ),
                  Text(tr('5 soru = 1 soru hakkı'), style: TextStyle(color: muted, fontSize: 12.5)),
                ]),
                if (_busy && _total > 1) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: _done / _total, borderRadius: BorderRadius.circular(4)),
                ],
              ]),
            ),
          );

    final summary = _items.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 4),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              _Chip(tr('{0} soru bulundu', [_items.length]), NColors.ink),
              if (fromDoc > 0) _Chip(tr('{0} cevap belgeden', [fromDoc]), NColors.deepEmerald),
              if (solved > 0) _Chip(tr('{0} cevabı yapay zekâ buldu', [solved]), const Color(0xFFB7791F)),
              if (unknown > 0) _Chip(tr('{0} cevapsız', [unknown]), NColors.coral),
            ]),
          );

    return Scaffold(
      appBar: AppBar(title: Text(tr('Belgeden soruları ayıkla'))),
      bottomNavigationBar: selected == 0
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _addSelected,
                  icon: const Icon(Icons.library_add_rounded),
                  label: Text(tr('Seçilen {0} soruyu bankaya ekle', [selected])),
                ),
              ),
            ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              intro,
              const SizedBox(height: 14),
              if (_loading) const LinearProgressIndicator() else sourceButtons,
              const SizedBox(height: 14),
              setup,
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: NColors.coral, fontWeight: FontWeight.w600)),
              ],
              for (final p in _problems.toSet()) ...[
                const SizedBox(height: 8),
                Text(p, style: TextStyle(color: muted)),
              ],
              if (_items.isNotEmpty) ...[
                SectionTitle(tr('Bulunan sorular')),
                summary,
                for (final it in _items)
                  _QuestionCard(
                    it,
                    onToggle: it.added ? null : (v) => setState(() => it.selected = v),
                  ),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  const _Chip(this.text, this.color);
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? Color.lerp(color, Colors.white, 0.55)! : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: dark ? 0.25 : 0.1), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12.5)),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  final _Item it;
  final ValueChanged<bool>? onToggle;
  const _QuestionCard(this.it, {this.onToggle});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final q = it.e.q;
    final muted = t.colorScheme.onSurfaceVariant;
    final ok = dark ? NColors.emerald : NColors.deepEmerald;
    final srcColor = switch (it.e.source) {
      AnswerSource.document => NColors.deepEmerald,
      AnswerSource.solved => const Color(0xFFB7791F),
      AnswerSource.unknown => NColors.coral,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: RoundedPanel(
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onToggle == null ? null : () => onToggle!(!it.selected),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 16, 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Checkbox(value: it.added || it.selected, onChanged: onToggle == null ? null : (v) => onToggle!(v ?? false)),
              const SizedBox(width: 4),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    if (it.e.number.isNotEmpty)
                      Text(tr('Soru {0}', [it.e.number]), style: const TextStyle(fontWeight: FontWeight.w800)),
                    _Chip(it.e.source.label, srcColor),
                    if (it.e.needsFigure) _Chip(tr('Şekilli soru'), const Color(0xFF4F46E5)),
                    if (q.topic.isNotEmpty) Text(q.topic, style: TextStyle(color: muted, fontSize: 12.5)),
                    if (it.added) _Chip(tr('Eklendi'), NColors.deepEmerald),
                  ]),
                  const SizedBox(height: 8),
                  Text(q.text, maxLines: 6, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.35)),
                  if (q.choices.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    for (var i = 0; i < q.choices.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('${String.fromCharCode(65 + i)}) ${q.choices[i]}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: q.correct.contains(i)
                                ? TextStyle(color: ok, fontWeight: FontWeight.w800)
                                : TextStyle(color: t.colorScheme.onSurface)),
                      ),
                  ],
                  if (q.type == QuestionType.trueFalse && q.correct.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(q.correct.first == 0 ? tr('Doğru') : tr('Yanlış'),
                          style: TextStyle(color: ok, fontWeight: FontWeight.w800)),
                    ),
                  if (q.answerText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(q.answerText, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: ok, fontWeight: FontWeight.w700)),
                    ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
