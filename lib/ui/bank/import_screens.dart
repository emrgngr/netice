import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import '../../bank/bank_excel.dart';
import '../../bank/bank_models.dart';
import '../../core/doc_text.dart';
import '../../l10n/l10n.dart';
import '../key_import_ui.dart' show ocrSupported;
import '../theme.dart';
import '../widgets.dart';
import 'bank_widgets.dart';
import 'image_tools.dart';
import 'note_screens.dart';

bool get _mobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

// ———————————————————————————— Excel

Future<void> importBankExcel(BuildContext context) async {
  try {
    final files = await FilePicker.pickFiles(
      dialogTitle: tr('Excel dosyası seçin'),
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'csv', 'txt'],
    );
    if (files.isEmpty || !context.mounted) return;
    final f = files.first;
    final bytes = await f.readAsBytes();
    final r = f.name.toLowerCase().endsWith('.xlsx') ? BankExcel.parseXlsx(bytes) : BankExcel.parseCsv(utf8.decode(bytes, allowMalformed: true));
    if (!context.mounted) return;
    if (r.isEmpty) {
      toast(context, tr('Dosyada soru ya da not bulunamadı. Şablonu indirip sütun başlıklarını aynı yazın.'));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.table_view_rounded, color: NColors.emerald, size: 36),
        title: Text(tr('Excel\'den aktar')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _countRow(Icons.quiz_outlined, tr('Soru'), r.questions.length),
          _countRow(Icons.sticky_note_2_outlined, tr('Not / hap bilgi'), r.notes.length),
          if (r.skipped.isNotEmpty) ...[
            _countRow(Icons.warning_amber_rounded, tr('Atlanan satır'), r.skipped.length, color: NColors.amber),
            const SizedBox(height: 6),
            for (final (sheet, row, why) in r.skipped.take(5))
              Text('• $sheet, ${tr('satır {0}', [row])}: $why', style: const TextStyle(fontSize: 12.5)),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Vazgeç'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Bankaya ekle'))),
        ],
      ),
    );
    if (ok != true) return;
    bank
      ..addQuestions(r.questions)
      ..addNotes(r.notes);
    if (context.mounted) toast(context, tr('{0} soru ve {1} not eklendi.', [r.questions.length, r.notes.length]));
  } catch (e) {
    if (context.mounted) toast(context, tr('Okunamadı: {0}', [e]));
  }
}

Widget _countRow(IconData icon, String label, int n, {Color color = NColors.emerald}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
        Text('$n', style: const TextStyle(fontWeight: FontWeight.w800, fontFeatures: tabular)),
      ]),
    );

Future<void> saveBankTemplate(BuildContext context) =>
    shareOrSaveBytes(context, bytes: BankExcel.template(), fileName: 'netice_soru_bankasi_sablon.xlsx', mime: _xlsxMime);

Future<void> exportBankExcel(BuildContext context, {Iterable<String>? questionIds}) {
  final qs = questionIds == null ? bank.questions : [for (final id in questionIds) ?bank.questionById(id)];
  return shareOrSaveBytes(context,
      bytes: BankExcel.export(qs, questionIds == null ? bank.notes : const []), fileName: 'netice_soru_bankasi.xlsx', mime: _xlsxMime);
}

const _xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

// ———————————————————————————— Paket (.netbank)

Future<void> exportBankPack(BuildContext context, {Iterable<String>? questionIds, Iterable<String>? noteIds}) {
  final d = DateTime.now();
  return shareOrSaveBytes(
    context,
    bytes: bank.exportPack(questionIds: questionIds, noteIds: noteIds),
    fileName: 'netice_banka_${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}.netbank',
    mime: 'application/zip',
    message: tr('Netice soru bankası paketi. Netice\'de Kütüphane › İçe aktar ile açın.'),
  );
}

Future<void> importBankPack(BuildContext context) async {
  try {
    final files = await FilePicker.pickFiles(dialogTitle: tr('Banka paketi seçin (.netbank)'), type: FileType.any);
    if (files.isEmpty) return;
    final (q, n, b) = await bank.importPack(await files.first.readAsBytes());
    if (context.mounted) toast(context, tr('{0} soru, {1} not, {2} kitapçık eklendi.', [q, n, b]));
  } catch (e) {
    if (context.mounted) toast(context, tr('Bu dosya bir Netice banka paketi değil.'));
  }
}

// ———————————————————————————— Notlar: belge ve fotoğraf

/// Fotoğraftaki yazıyı okur (yalnız telefonda).
Future<String> ocrImageBytes(Uint8List bytes) async {
  if (!ocrSupported) return '';
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/not_${DateTime.now().millisecondsSinceEpoch}.jpg');
  await f.writeAsBytes(bytes);
  final rec = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final r = await rec.processImage(InputImage.fromFilePath(f.path));
    return r.blocks.map((b) => b.lines.map((l) => l.text).join(' ')).join('\n\n');
  } finally {
    await rec.close();
    f.delete().ignore();
  }
}

/// PDF / Word / metin belgesinden not: metin çıkarılır, düzenleyici açılır.
Future<void> noteFromDocument(BuildContext context, {NoteKind kind = NoteKind.summary}) async {
  try {
    final files = await FilePicker.pickFiles(
      dialogTitle: tr('Ders notu belgesi'),
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'txt', 'md'],
    );
    if (files.isEmpty || !context.mounted) return;
    final f = files.first;
    final bytes = await f.readAsBytes();
    final name = f.name.toLowerCase();
    var text = name.endsWith('.txt') || name.endsWith('.md')
        ? utf8.decode(bytes, allowMalformed: true)
        : await compute((List<Object> a) => documentText(a[0] as Uint8List, a[1] as String), [bytes, name]);
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    if (!context.mounted) return;
    if (text.isEmpty) {
      toast(context, tr('Belgeden yazı okunamadı (taranmış PDF olabilir). "PDF\'ten kes" ile sayfaları görsel olarak ekleyin.'));
      return;
    }
    final title = f.name.replaceAll(RegExp(r'\.[^.]+$'), '').replaceAll('_', ' ');
    await NoteEditorScreen.open(context,
        bank.newNote(kind: kind).copyWith(title: title, body: text, source: f.name));
  } catch (e) {
    if (context.mounted) toast(context, tr('Okunamadı: {0}', [e]));
  }
}

/// Fotoğraftan not: görsel eklenir, telefonda yazısı da okunur.
Future<void> noteFromPhoto(BuildContext context, {NoteKind kind = NoteKind.summary, bool camera = false}) async {
  try {
    Uint8List? bytes;
    if (_mobile) {
      final f = await ImagePicker().pickImage(source: camera ? ImageSource.camera : ImageSource.gallery, requestFullMetadata: false);
      if (f == null || !context.mounted) return;
      bytes = await cropBytes(await f.readAsBytes(), null);
    } else {
      bytes = await pickBankImage(context);
    }
    if (bytes == null || !context.mounted) return;
    final id = await bank.saveImage(bytes);
    var text = '';
    if (ocrSupported) {
      text = await ocrImageBytes(bytes);
    }
    if (!context.mounted) return;
    await NoteEditorScreen.open(context, bank.newNote(kind: kind).copyWith(body: text, imageIds: [id]));
  } catch (e) {
    if (context.mounted) toast(context, tr('Açılamadı: {0}', [e]));
  }
}

// ———————————————————————————— PDF / fotoğraftan toplu kesme

enum CropTarget { questions, note }

/// Kitap, deneme ya da ders notu sayfalarından bölge seçip hızlıca soru ya
/// da not oluşturma.
class CropImportScreen extends StatefulWidget {
  final List<DocPage> pages;
  final CropTarget target;
  const CropImportScreen({super.key, required this.pages, this.target = CropTarget.questions});

  /// Kaynağı sorup ekranı açar.
  static Future<void> start(BuildContext context, {CropTarget target = CropTarget.questions}) async {
    final src = _mobile
        ? await showModalBottomSheet<String>(
            context: context,
            showDragHandle: true,
            builder: (ctx) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(leading: const Icon(Icons.picture_as_pdf_outlined), title: Text(tr('PDF ya da görsel dosyası')), onTap: () => Navigator.pop(ctx, 'file')),
                ListTile(leading: const Icon(Icons.photo_library_outlined), title: Text(tr('Galeriden fotoğraflar')), onTap: () => Navigator.pop(ctx, 'gallery')),
                ListTile(leading: const Icon(Icons.photo_camera_outlined), title: Text(tr('Sayfanın fotoğrafını çek')), onTap: () => Navigator.pop(ctx, 'camera')),
                const SizedBox(height: 8),
              ]),
            ),
          )
        : 'file';
    if (src == null || !context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    var opened = true;
    try {
      final pages = await pickDocumentPages(context, camera: src == 'camera', gallery: src == 'gallery');
      if (context.mounted) {
        Navigator.pop(context);
        opened = false;
      }
      if (pages.isEmpty || !context.mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CropImportScreen(pages: pages, target: target)));
    } catch (e) {
      if (context.mounted) {
        if (opened) Navigator.pop(context);
        toast(context, tr('Açılamadı: {0}', [e]));
      }
    }
  }

  @override
  State<CropImportScreen> createState() => _CropImportScreenState();
}

class _CropImportScreenState extends State<CropImportScreen> {
  int _page = 0;
  Rect? _rect;
  bool _busy = false;
  final Map<int, List<Rect>> _done = {};
  int _added = 0;

  // Toplu etiketler.
  late final _subject = TextEditingController(text: bank.lastSubject);
  late final _grade = TextEditingController(text: bank.lastGrade);
  late final _topic = TextEditingController(text: bank.lastTopic);
  Difficulty _difficulty = Difficulty.medium;
  QuestionType _type = QuestionType.multiple;
  int _choiceCount = 4;
  int? _answer;

  // Not modu: kesilen görseller tek nota eklenir.
  final List<String> _noteImages = [];

  bool get _questions => widget.target == CropTarget.questions;

  @override
  void dispose() {
    _subject.dispose();
    _grade.dispose();
    _topic.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final r = _rect;
    if (r == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await cropBytes(widget.pages[_page].bytes, r);
      final id = await bank.saveImage(bytes);
      if (_questions) {
        final q = bank.newQuestion().copyWith(
              subject: _subject.text.trim(),
              grade: _grade.text.trim(),
              topic: _topic.text.trim(),
              difficulty: _difficulty,
              type: _type,
              imageId: id,
              choiceCount: _type == QuestionType.trueFalse ? 2 : _choiceCount,
              correct: _answer == null ? const {} : {_answer!},
            );
        bank.upsertQuestion(q);
      } else {
        _noteImages.add(id);
      }
      setState(() {
        _done.putIfAbsent(_page, () => []).add(r);
        _rect = null;
        _answer = null;
        _added++;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    if (!_questions && _noteImages.isNotEmpty) {
      final n = bank.newNote().copyWith(
            subject: _subject.text.trim(),
            grade: _grade.text.trim(),
            topic: _topic.text.trim(),
            imageIds: _noteImages,
          );
      Navigator.pop(context);
      await NoteEditorScreen.open(context, n);
      return;
    }
    Navigator.pop(context);
    if (_added > 0) {
      toast(context, tr('{0} soru eklendi. Cevabı boş kalanlar listede "eksik" olarak görünür.', [_added]));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final panel = _panel(t);
    final viewer = Column(children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: RectSelector(
            key: ValueKey(_page),
            page: widget.pages[_page],
            rect: _rect,
            done: _done[_page] ?? const [],
            onChanged: (r) => setState(() => _rect = r),
          ),
        ),
      ),
      if (widget.pages.length > 1)
        PageStrip(
          pages: widget.pages,
          index: _page,
          badges: {for (final e in _done.entries) e.key: e.value.length},
          onSelect: (i) => setState(() {
            _page = i;
            _rect = null;
          }),
        ),
    ]);
    return Scaffold(
      appBar: AppBar(
        title: Text(_questions ? tr('Sayfadan soru kes') : tr('Sayfadan not oluştur')),
        actions: [
          if (_added > 0)
            Center(child: Padding(padding: const EdgeInsets.only(right: 6), child: Pill(tr('{0} eklendi', [_added]), icon: Icons.check_rounded))),
          Padding(
            padding: const EdgeInsets.only(right: 10, left: 4),
            child: FilledButton(onPressed: _finish, child: Text(_questions ? tr('Bitti') : tr('Notu oluştur'))),
          ),
        ],
      ),
      body: SafeArea(
        child: wide
            ? Row(children: [
                Expanded(child: viewer),
                SizedBox(width: 360, child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: panel)),
              ])
            : Column(children: [
                Expanded(child: viewer),
                Material(
                  elevation: 8,
                  color: t.colorScheme.surface,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.42),
                    child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(14, 10, 14, 12), child: panel),
                  ),
                ),
              ]),
      ),
    );
  }

  Widget _panel(ThemeData t) {
    final hint = TextStyle(color: t.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12.5);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(
        _questions
            ? tr('Sorunun çevresine dikdörtgen çizin, doğru cevabı seçip "Soru olarak ekle"ye basın. Sonra sıradaki soruya geçin.')
            : tr('Nota eklemek istediğiniz bölgeleri sırayla seçip ekleyin. Hepsi tek bir notta toplanır.'),
        style: hint,
      ),
      const SizedBox(height: 10),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        leading: const Icon(Icons.account_tree_outlined),
        title: Text(tr('Ders ve konu'), style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text([_subject.text, _grade.text, _topic.text].where((s) => s.trim().isNotEmpty).join(' · ').ifEmpty(tr('Tüm kesimlere uygulanır')),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        children: [
          SuggestField(controller: _subject, label: tr('Ders'), options: () => bank.subjects, onChanged: (_) => setState(() {})),
          const SizedBox(height: 8),
          SuggestField(controller: _grade, label: tr('Sınıf / düzey'), options: () => bank.grades, onChanged: (_) => setState(() {})),
          const SizedBox(height: 8),
          SuggestField(controller: _topic, label: tr('Konu / ünite'), options: () => bank.topicsOf(_subject.text.trim()), onChanged: (_) => setState(() {})),
        ],
      ),
      if (_questions) ...[
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final ty in QuestionType.values)
            ChoiceChip(
              label: Text(ty.label),
              selected: _type == ty,
              onSelected: (_) => setState(() {
                _type = ty;
                _answer = null;
              }),
            ),
        ]),
        if (_type.optical) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Text(tr('Doğru cevap'), style: const TextStyle(fontWeight: FontWeight.w700))),
            if (_type == QuestionType.multiple)
              SegmentedButton<int>(
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                showSelectedIcon: false,
                segments: [for (final n in [4, 5]) ButtonSegment(value: n, label: Text(tr('{0} şık', [n])))],
                selected: {_choiceCount},
                onSelectionChanged: (s) => setState(() {
                  _choiceCount = s.first;
                  if ((_answer ?? 0) >= _choiceCount) _answer = null;
                }),
              ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (var i = 0; i < (_type == QuestionType.trueFalse ? 2 : _choiceCount); i++)
              ChoiceChip(
                label: Text(_type == QuestionType.trueFalse ? (i == 0 ? tr('Doğru') : tr('Yanlış')) : letter(i),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                selected: _answer == i,
                selectedColor: NColors.emerald.withValues(alpha: 0.25),
                onSelected: (on) => setState(() => _answer = on ? i : null),
              ),
          ]),
        ],
        const SizedBox(height: 10),
        SegmentedButton<Difficulty>(
          showSelectedIcon: false,
          segments: [
            for (final d in Difficulty.values)
              ButtonSegment(value: d, label: Text(d.label), icon: Icon(Icons.circle, size: 10, color: difficultyColor(d))),
          ],
          selected: {_difficulty},
          onSelectionChanged: (s) => setState(() => _difficulty = s.first),
        ),
      ],
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _rect == null || _busy ? null : _add,
        icon: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.add_rounded),
        label: Text(_questions ? tr('Soru olarak ekle') : tr('Nota ekle')),
      ),
    ]);
  }
}

extension on String {
  String ifEmpty(String other) => trim().isEmpty ? other : this;
}
