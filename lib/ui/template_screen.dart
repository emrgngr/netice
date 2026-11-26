import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../main.dart';
import '../omr/form_layout.dart' show Pt;
import '../omr/grid_detect.dart';
import '../omr/omr_reader.dart';
import '../omr/template.dart';
import 'common_exam_ui.dart' show shareOrSaveFile;
import 'theme.dart';
import 'widgets.dart';
import '../l10n/l10n.dart';

/// Başka firma formları için şablon listesi.
class TemplatesScreen extends StatelessWidget {
  const TemplatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Başka firma formları')), actions: [
        IconButton(
          tooltip: tr('Şablon dosyası aç'),
          onPressed: () => importTemplateFile(context),
          icon: const Icon(Icons.file_open_outlined),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TemplateEditorScreen())),
        icon: const Icon(Icons.add_rounded),
        label: Text(tr('Yeni şablon')),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 100), children: [
        Text(
          tr('Okulunuzda yayınevi ya da başka bir firmanın optik formu kullanılıyorsa, boş (veya dolu) bir formun fotoğrafını ya da taramasını seçin. Netice formdaki cevap dairelerini, öğrenci numarasını ve kitapçık türünü kendisi bulur; siz yalnızca kontrol edersiniz. Sonra Sınav ayarları > Form türü bölümünden bu şablonu seçin.'),
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 8),
        Text(
          tr('Bir öğretmenin hazırladığı şablonu dosya olarak diğer öğretmenlere gönderebilirsiniz; aynı formu bir daha tanıtmak gerekmez.'),
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 16),
        if (store.templates.isEmpty)
          EmptyNote(icon: Icons.grid_on_rounded, text: tr('Henüz şablon yok.'))
        else
          for (final t in store.templates)
            Card(
              child: ListTile(
                leading: const Icon(Icons.grid_on_rounded, color: NColors.emerald),
                title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(tr('{0} soru · {1} şık{2}', [t.questionCount, t.choiceCount, t.number == null ? tr(' · numara bloğu yok') : tr(' · {0} haneli numara', [t.number!.digits])]) +
                    (t.booklet == null ? '' : tr(' · {0} kitapçık', [t.booklet!.count]))),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => TemplateEditorScreen(template: t))),
              ),
            ),
      ]),
    );
  }
}

/// Başka öğretmenden gelen şablon dosyasını açar ve kaydeder.
Future<void> importTemplateFile(BuildContext context) async {
  final store = StoreScope.of(context);
  Uint8List? bytes;
  try {
    final files = await FilePicker.pickFiles(dialogTitle: tr('Şablon dosyasını seçin'), type: FileType.any);
    if (files.isNotEmpty) bytes = await files.first.readAsBytes();
  } catch (_) {}
  if (bytes == null || !context.mounted) return;
  FormTemplate? t;
  try {
    t = FormTemplate.fromShareJson(jsonDecode(utf8.decode(bytes)));
  } catch (_) {}
  if (t == null) return toast(context, tr('Bu dosya bir Netice şablonu değil.'));
  store.saveTemplate(t);
  toast(context, tr('"{0}" şablonu eklendi.', [t.name]));
}

/// Basit boş durum notu.
class EmptyNote extends StatelessWidget {
  final IconData icon;
  final String text;
  const EmptyNote({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(children: [
          Icon(icon, size: 56, color: NColors.emerald.withValues(alpha: 0.6)),
          const SizedBox(height: 8),
          Text(text),
        ]),
      );
}

enum _Tap { none, blockFirst, blockLast, numberFirst, numberLast, bookletFirst, bookletLast }

/// Şablon düzenleyici: formun fotoğrafı düzleştirilir, öğretmen her bloğun
/// ilk ve son dairesine dokunur; aradaki daireler hesaplanır ve üstüne çizilir.
class TemplateEditorScreen extends StatefulWidget {
  final FormTemplate? template;

  /// Önizleme/test için hazır fotoğraf (prepareTemplatePhoto sonucu) ve deneme okuması.
  final (GrayImage, List<Pt>, Uint8List, bool)? preview;
  final OmrResult? previewTest;
  const TemplateEditorScreen({super.key, this.template, this.preview, this.previewTest});

  @override
  State<TemplateEditorScreen> createState() => _TemplateEditorScreenState();
}

class _TemplateEditorScreenState extends State<TemplateEditorScreen> {
  late FormTemplate _t = widget.template ??
      FormTemplate(id: 'tpl_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}', name: '');
  late final _name = TextEditingController(text: _t.name);
  Uint8List? _page; // düzleştirilmiş sayfa (PNG)
  GrayImage? _gray;
  List<Pt>? _corners;
  bool _busy = false;

  _Tap _tap = _Tap.none;
  ({int start, int count, int choices, bool rows})? _pendingBlock;
  int? _replaceIndex;
  int _pendingDigits = 6;
  int _pendingBooklets = 2;
  Pt? _firstTap;
  OmrResult? _test;

  static bool get _mobile => defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    final p = widget.preview;
    if (p != null) {
      _gray = p.$1;
      _corners = p.$2;
      _page = p.$3;
      _test = widget.previewTest;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickImage({bool camera = false}) async {
    Uint8List? bytes;
    try {
      if (_mobile) {
        final f = await ImagePicker().pickImage(source: camera ? ImageSource.camera : ImageSource.gallery, requestFullMetadata: false);
        bytes = await f?.readAsBytes();
      } else {
        final files = await FilePicker.pickFiles(dialogTitle: tr('Formun fotoğrafını seçin'), type: FileType.image);
        if (files.isNotEmpty) bytes = await files.first.readAsBytes();
      }
    } catch (e) {
      if (mounted) toast(context, tr('Görüntü açılamadı: {0}', [e]));
      return;
    }
    if (bytes == null) return;
    setState(() => _busy = true);
    final out = await compute(prepareTemplatePhoto, (bytes, _t.aspect));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _test = null;
      if (out == null) {
        toast(context, tr('Görüntü açılamadı.'));
        return;
      }
      _gray = out.$1;
      _corners = out.$2;
      _page = out.$3;
      if (!out.$4) {
        toast(context, tr('Kâğıdın kenarları bulunamadı; görüntünün tamamı sayfa sayıldı. En iyi sonuç için kâğıdı koyu bir zemine koyup tamamı görünecek şekilde çekin.'));
      }
    });
    // Yeni şablonda daireleri hemen kendisi bulsun.
    if (_t.blocks.isEmpty && _gray != null) await _autoDetect();
  }

  /// Formdaki daire ızgaralarını kendiliğinden bulur ve şablona yazar.
  Future<void> _autoDetect() async {
    final g = _gray, c = _corners;
    if (g == null || c == null) return;
    setState(() => _busy = true);
    final d = await compute(_detect, (g, c, _t.aspect));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _tap = _Tap.none;
      _test = null;
      if (!d.isEmpty) _t = d.applyTo(_t);
    });
    if (d.blocks.isEmpty) {
      toast(context, tr('Cevap daireleri kendiliğinden bulunamadı. Daha net, düz bir fotoğraf deneyin ya da blokları elle işaretleyin.'));
      return;
    }
    final parts = [
      tr('{0} soru ({1} blok)', [d.questionCount, d.blocks.length]),
      if (d.number != null) tr('{0} haneli numara', [d.number!.digits]),
      if (d.booklet != null) tr('{0} kitapçık türü', [d.booklet!.count]),
    ];
    toast(context, tr('Bulundu: {0}. Renkli halkaların dairelerin üstünde olduğunu kontrol edin.', [parts.join(', ')]));
  }

  Future<void> _editStart(int i) async {
    final b = _t.blocks[i];
    final start = TextEditingController(text: '${b.start}');
    var choices = b.choices;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('Bloğu düzenle')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(tr('Formda bu bloğun ilk sorusunun numarası kaç?')),
            const SizedBox(height: 12),
            TextField(
              controller: start,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: tr('İlk soru no')),
            ),
            const SizedBox(height: 12),
            Text(tr('{0} soru · {1} şık', [b.count, choices])),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Vazgeç'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Kaydet'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final s = int.tryParse(start.text);
    if (s == null || s < 1) return toast(context, tr('Soru numaralarını kontrol edin.'));
    final blocks = [..._t.blocks];
    blocks[i] = TemplateBlock(start: s, count: b.count, choices: b.choices, first: b.first, last: b.last, rows: b.rows);
    blocks.sort((a, b) => a.start.compareTo(b.start));
    setState(() {
      _t = _t.copyWith(blocks: blocks);
      _test = null;
    });
  }

  Future<void> _addBooklet() async {
    var count = _t.booklet?.count ?? 2;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('Kitapçık türü alanı')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(tr('Formda kaç kitapçık dairesi var (A, B, C…)?')),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: [for (final n in const [2, 3, 4, 5, 6]) ButtonSegment(value: n, label: Text('$n'))],
              selected: {count},
              onSelectionChanged: (v) => set(() => count = v.first),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Vazgeç'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Daireleri işaretle'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _pendingBooklets = count;
      _tap = _Tap.bookletFirst;
      _firstTap = null;
    });
  }

  Future<void> _share() async {
    final name = _name.text.trim().isEmpty ? _t.name : _name.text.trim();
    final file = name.replaceAll(RegExp(r'[^\wğüşıöçĞÜŞİÖÇ -]'), '').trim().replaceAll(' ', '_');
    await shareOrSaveFile(context,
        fileName: '${file.isEmpty ? 'sablon' : file}.netice-sablon.json',
        text: jsonEncode(_t.copyWith(name: name).toShareJson()),
        message: tr('Netice optik form şablonu: {0}. Netice\'de Ayarlar > Başka firma formları > Şablon dosyası aç ile ekleyin.', [name]));
  }

  Future<void> _addBlock({int? replace}) async {
    final old = replace == null ? null : _t.blocks[replace];
    final nextStart = _t.blocks.isEmpty ? 1 : _t.questionCount + 1;
    final start = TextEditingController(text: '${old?.start ?? nextStart}');
    final count = TextEditingController(text: '${old?.count ?? 20}');
    var choices = old?.choices ?? 5;
    var rows = old?.rows ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(replace == null ? tr('Cevap bloğu ekle') : tr('Bloğu yeniden işaretle')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(tr('Formdaki bir sütun (ya da blok) soruyu tanımlayın.')),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                      controller: start,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: tr('İlk soru no'))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                      controller: count,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: tr('Soru sayısı'))),
                ),
              ]),
              const SizedBox(height: 12),
              SegmentedButton<int>(
                segments: [
                  ButtonSegment(value: 4, label: Text(tr('4 şık'))),
                  ButtonSegment(value: 5, label: Text(tr('5 şık'))),
                ],
                selected: {choices},
                onSelectionChanged: (v) => set(() => choices = v.first),
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: true, label: Text(tr('Şıklar yan yana'))),
                  ButtonSegment(value: false, label: Text(tr('Şıklar alt alta'))),
                ],
                selected: {rows},
                onSelectionChanged: (v) => set(() => rows = v.first),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Vazgeç'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Daireleri işaretle'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final s = int.tryParse(start.text), c = int.tryParse(count.text);
    if (s == null || s < 1 || c == null || c < 1 || c > 200) return toast(context, tr('Soru numaralarını kontrol edin.'));
    setState(() {
      _pendingBlock = (start: s, count: c, choices: choices, rows: rows);
      _replaceIndex = replace;
      _tap = _Tap.blockFirst;
      _firstTap = null;
    });
  }

  Future<void> _addNumber() async {
    final digits = TextEditingController(text: '${_t.number?.digits ?? 6}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Öğrenci numarası bloğu')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr('Her sütun bir basamak, 0–9 yukarıdan aşağıya olmalı.')),
          const SizedBox(height: 12),
          TextField(
              controller: digits,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: tr('Basamak (sütun) sayısı'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Vazgeç'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Daireleri işaretle'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final d = int.tryParse(digits.text);
    if (d == null || d < 1 || d > 12) return toast(context, tr('Basamak sayısı 1–12 olmalı.'));
    setState(() {
      _pendingDigits = d;
      _tap = _Tap.numberFirst;
      _firstTap = null;
    });
  }

  void _onTap(Pt p) {
    switch (_tap) {
      case _Tap.blockFirst:
      case _Tap.numberFirst:
      case _Tap.bookletFirst:
        setState(() {
          _firstTap = p;
          _tap = switch (_tap) {
            _Tap.blockFirst => _Tap.blockLast,
            _Tap.numberFirst => _Tap.numberLast,
            _ => _Tap.bookletLast,
          };
        });
      case _Tap.bookletLast:
        setState(() {
          _t = _t.copyWith(booklet: BookletBlock(count: _pendingBooklets, first: _firstTap!, last: p));
          _tap = _Tap.none;
          _test = null;
        });
      case _Tap.blockLast:
        final b = _pendingBlock!;
        final block = TemplateBlock(start: b.start, count: b.count, choices: b.choices, first: _firstTap!, last: p, rows: b.rows);
        final blocks = [..._t.blocks];
        if (_replaceIndex != null) {
          blocks[_replaceIndex!] = block;
        } else {
          blocks.add(block);
        }
        blocks.sort((a, b) => a.start.compareTo(b.start));
        setState(() {
          _t = _t.copyWith(blocks: blocks);
          _tap = _Tap.none;
          _test = null;
        });
      case _Tap.numberLast:
        setState(() {
          _t = _t.copyWith(number: NumberBlock(digits: _pendingDigits, first: _firstTap!, last: p));
          _tap = _Tap.none;
          _test = null;
        });
      case _Tap.none:
        break;
    }
  }

  String get _prompt => switch (_tap) {
        _Tap.blockFirst => _pendingBlock!.rows
            ? tr('{0}. sorunun A şıkkının ortasına dokunun', [_pendingBlock!.start])
            : tr('{0}. sorunun A şıkkının ortasına dokunun (en üstteki)', [_pendingBlock!.start]),
        _Tap.blockLast =>
          tr('{0}. sorunun {1} şıkkının ortasına dokunun', [_pendingBlock!.start + _pendingBlock!.count - 1, String.fromCharCode(64 + _pendingBlock!.choices)]),
        _Tap.numberFirst => tr('Numaranın ilk basamağındaki 0 dairesine dokunun'),
        _Tap.numberLast => tr('Numaranın son basamağındaki 9 dairesine dokunun'),
        _Tap.bookletFirst => tr('Kitapçık türü A dairesine dokunun'),
        _Tap.bookletLast => tr('Son kitapçık dairesine ({0}) dokunun', [String.fromCharCode(64 + _pendingBooklets)]),
        _Tap.none => '',
      };

  Future<void> _tryRead() async {
    final g = _gray, c = _corners;
    if (g == null || c == null) return;
    setState(() => _busy = true);
    final r = await compute(_testRead, (g, c, _t));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _test = r;
    });
    final marked = r.questions.where((q) => q.answer.marked.isNotEmpty).length;
    toast(context, tr('{0} soruda işaret bulundu{1}.', [
      marked,
      (r.studentNumber == null ? '' : ' · numara ${int.parse(r.studentNumber!)}') +
          (r.booklet == null ? '' : ' · ${tr('kitapçık')} ${String.fromCharCode(65 + r.booklet!)}')
    ]));
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return toast(context, tr('Şablona bir ad verin (örn. "X Yayınları 40 soruluk").'));
    if (_t.blocks.isEmpty) return toast(context, tr('En az bir cevap bloğu ekleyin.'));
    StoreScope.of(context).saveTemplate(_t.copyWith(name: name));
    toast(context, tr('Şablon kaydedildi. Sınav ayarlarında "Form türü"nden seçebilirsiniz.'));
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Şablon silinsin mi?')),
        content: Text(tr('Bu şablonu kullanan sınavlar Netice formuna döner. Okunmuş kâğıtlar silinmez.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Vazgeç'))),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: NColors.coral),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Sil'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    StoreScope.of(context).deleteTemplate(_t.id);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    final editing = widget.template != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? tr('Şablonu düzenle') : tr('Yeni şablon')),
        actions: [
          if (_t.blocks.isNotEmpty)
            IconButton(tooltip: tr('Diğer öğretmenlere gönder'), onPressed: _share, icon: const Icon(Icons.ios_share_rounded)),
          if (editing) IconButton(tooltip: tr('Sil'), onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded)),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(onPressed: _save, child: Text(tr('Kaydet'))),
          ),
        ],
      ),
      body: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 900;
        final controls = ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), shrinkWrap: !wide, physics: wide ? null : const NeverScrollableScrollPhysics(), children: [
          TextField(
            controller: _name,
            decoration: InputDecoration(labelText: tr('Şablon adı'), hintText: tr('Örn. X Yayınları 40 soruluk form')),
          ),
          const SizedBox(height: 12),
          Text(tr('1. Formun fotoğrafını ya da taramasını seçin. Kâğıdı koyu bir zemine koyun, dört kenarı görünsün. 2. Netice cevap dairelerini, numarayı ve kitapçık türünü kendisi bulur; renkli halkalar dairelerin üstünde mi bakın. Yanlış bulunan bloğu kaldırıp elle işaretleyebilirsiniz. 3. Dolu bir formla "Dene"ye basıp sonucu kontrol edin.'),
              style: TextStyle(color: muted)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(
              onPressed: _busy ? null : () => _pickImage(),
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(_page == null ? tr('Form fotoğrafı seç') : tr('Başka fotoğraf')),
            ),
            if (_mobile)
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _pickImage(camera: true),
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(tr('Fotoğraf çek')),
              ),
            if (_page != null)
              OutlinedButton.icon(
                onPressed: _busy ? null : _autoDetect,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: Text(tr('Daireleri otomatik bul')),
              ),
          ]),
          SectionTitle(tr('Cevap blokları')),
          if (_t.blocks.isEmpty) Text(tr('Henüz blok yok.'), style: TextStyle(color: muted)),
          for (final (i, b) in _t.blocks.indexed)
            Card(
              child: ListTile(
                dense: true,
                leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: _blockColor(i).withValues(alpha: 0.2),
                    child: Text('${i + 1}', style: TextStyle(color: _blockColor(i), fontWeight: FontWeight.w800))),
                title: Text(tr('Soru {0}–{1}', [b.start, b.start + b.count - 1])),
                subtitle: Text(tr('{0} şık · {1}', [b.choices, b.rows ? tr('yan yana') : tr('alt alta')])),
                onTap: () => _editStart(i),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: tr('Yeniden işaretle'),
                    onPressed: _page == null ? null : () => _addBlock(replace: i),
                    icon: const Icon(Icons.edit_location_alt_outlined),
                  ),
                  IconButton(
                    tooltip: tr('Kaldır'),
                    onPressed: () => setState(() => _t = _t.copyWith(blocks: [..._t.blocks]..removeAt(i))),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ]),
              ),
            ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: _page == null || _busy ? null : () => _addBlock(),
            icon: const Icon(Icons.add_rounded),
            label: Text(tr('Cevap bloğu ekle')),
          ),
          SectionTitle(tr('Öğrenci numarası')),
          if (_t.number != null)
            Card(
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.pin_outlined, color: NColors.amber),
                title: Text(tr('{0} haneli numara', [_t.number!.digits])),
                trailing: IconButton(
                  tooltip: tr('Kaldır'),
                  onPressed: () => setState(() => _t = _t.copyWith(clearNumber: true)),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            )
          else
            Text(tr('Numara bloğu yoksa kâğıtlar "Kontrol" ekranında öğrenciye elle atanır.'), style: TextStyle(color: muted)),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: _page == null || _busy ? null : _addNumber,
            icon: const Icon(Icons.pin_outlined),
            label: Text(_t.number == null ? tr('Numara bloğu ekle') : tr('Numara bloğunu yeniden işaretle')),
          ),
          SectionTitle(tr('Kitapçık türü')),
          if (_t.booklet != null)
            Card(
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.menu_book_outlined, color: Color(0xFFA855F7)),
                title: Text(tr('{0} kitapçık türü (A–{1})', [_t.booklet!.count, String.fromCharCode(64 + _t.booklet!.count)])),
                trailing: IconButton(
                  tooltip: tr('Kaldır'),
                  onPressed: () => setState(() => _t = _t.copyWith(clearBooklet: true)),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            )
          else
            Text(tr('Formda kitapçık türü (A/B) daireleri varsa ekleyin; öğrencinin işaretlediği kitapçık kendiliğinden okunur.'), style: TextStyle(color: muted)),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: _page == null || _busy ? null : _addBooklet,
            icon: const Icon(Icons.menu_book_outlined),
            label: Text(_t.booklet == null ? tr('Kitapçık alanı ekle') : tr('Kitapçık alanını yeniden işaretle')),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _page == null || _t.blocks.isEmpty || _busy ? null : _tryRead,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(tr('Bu fotoğrafla dene')),
          ),
          if (_test != null) ...[
            const SizedBox(height: 8),
            Text(
              tr('Yeşil dolu daireler okunan işaretlerdir. Doğru yerlerdeyse şablon hazır; kayıksa ilgili bloğu yeniden işaretleyin.'),
              style: TextStyle(color: muted),
            ),
          ],
        ]);
        final viewer = _page == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    editing ? tr('Şablonu değiştirmek için formun fotoğrafını yeniden seçin.') : tr('Formun fotoğrafı burada görünecek.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted),
                  ),
                ),
              )
            : _PageView(
                png: _page!,
                template: _t,
                test: _test,
                pendingFirst: _firstTap,
                onTap: _tap == _Tap.none ? null : _onTap,
              );
        final prompt = _tap == _Tap.none
            ? null
            : Material(
                color: NColors.ink,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    const Icon(Icons.touch_app_rounded, color: NColors.amber),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_prompt, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                    TextButton(
                      onPressed: () => setState(() => _tap = _Tap.none),
                      child: Text(tr('Vazgeç'), style: TextStyle(color: Colors.white70)),
                    ),
                  ]),
                ),
              );
        if (wide) {
          return Row(children: [
            SizedBox(width: 380, child: controls),
            const VerticalDivider(width: 1),
            Expanded(child: Column(children: [?prompt, Expanded(child: viewer)])),
          ]);
        }
        return Column(children: [
          ?prompt,
          if (_page != null) SizedBox(height: box.maxHeight * (_tap == _Tap.none ? 0.5 : 0.8), child: viewer),
          if (_busy) const LinearProgressIndicator(),
          if (_tap == _Tap.none) Expanded(child: SingleChildScrollView(child: controls)),
        ]);
      }),
    );
  }
}

Color _blockColor(int i) => const [NColors.emerald, Color(0xFF3B82F6), Color(0xFFA855F7), Color(0xFFF97316), Color(0xFF0EA5E9)][i % 5];

class _PageView extends StatelessWidget {
  final Uint8List png;
  final FormTemplate template;
  final OmrResult? test;
  final Pt? pendingFirst;
  final void Function(Pt)? onTap;
  const _PageView({required this.png, required this.template, this.test, this.pendingFirst, this.onTap});

  @override
  Widget build(BuildContext context) => InteractiveViewer(
        maxScale: 8,
        child: Center(
          child: AspectRatio(
            aspectRatio: 1 / template.aspect,
            child: LayoutBuilder(
              builder: (context, box) => GestureDetector(
                onTapUp: onTap == null
                    ? null
                    : (d) => onTap!(Pt(d.localPosition.dx / box.maxWidth * FormTemplate.width,
                        d.localPosition.dy / box.maxWidth * FormTemplate.width)),
                child: Stack(fit: StackFit.expand, children: [
                  Image.memory(png, fit: BoxFit.fill, gaplessPlayback: true),
                  CustomPaint(painter: _TemplatePainter(template, test, pendingFirst)),
                ]),
              ),
            ),
          ),
        ),
      );
}

class _TemplatePainter extends CustomPainter {
  final FormTemplate t;
  final OmrResult? test;
  final Pt? pending;
  _TemplatePainter(this.t, this.test, this.pending);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / FormTemplate.width;
    Offset at(Pt p) => Offset(p.x * k, p.y * k);
    for (final (i, b) in t.blocks.indexed) {
      final color = _blockColor(i);
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = color.withValues(alpha: 0.9);
      final fill = Paint()..color = NColors.emerald.withValues(alpha: 0.55);
      for (var q = 0; q < b.count; q++) {
        final idx = b.start - 1 + q;
        final marked = test != null && idx < test!.questions.length ? test!.questions[idx].answer.marked : const <int>{};
        for (var c = 0; c < b.choices; c++) {
          final p = at(b.bubble(q, c));
          canvas.drawCircle(p, b.radius * k, ring);
          if (marked.contains(c)) canvas.drawCircle(p, b.radius * k * 0.8, fill);
        }
      }
    }
    final nb = t.number;
    if (nb != null) {
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = NColors.amber;
      final digits = test?.numberPattern;
      for (var d = 0; d < nb.digits; d++) {
        for (var v = 0; v < 10; v++) {
          final p = at(nb.bubble(d, v));
          canvas.drawCircle(p, nb.radius * k, ring);
        }
      }
      if (digits != null) {
        // Okunan rakamları işaretle (sağa yaslı numara).
        final tail = digits.length > nb.digits ? digits.substring(digits.length - nb.digits) : digits.padLeft(nb.digits, '?');
        for (var d = 0; d < nb.digits; d++) {
          final v = int.tryParse(tail[d]);
          if (v != null) canvas.drawCircle(at(nb.bubble(d, v)), nb.radius * k * 0.8, Paint()..color = NColors.emerald.withValues(alpha: 0.55));
        }
      }
    }
    final bb = t.booklet;
    if (bb != null) {
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = const Color(0xFFA855F7);
      for (var i = 0; i < bb.count; i++) {
        final p = at(bb.bubble(i));
        canvas.drawCircle(p, bb.radius * k, ring);
        if (test?.booklet == i) canvas.drawCircle(p, bb.radius * k * 0.8, Paint()..color = NColors.emerald.withValues(alpha: 0.55));
      }
    }
    if (pending != null) {
      final p = at(pending!);
      final paint = Paint()
        ..color = NColors.coral
        ..strokeWidth = 2;
      canvas.drawLine(p - const Offset(10, 0), p + const Offset(10, 0), paint);
      canvas.drawLine(p - const Offset(0, 10), p + const Offset(0, 10), paint);
    }
  }

  @override
  bool shouldRepaint(_TemplatePainter o) => true;
}

/// Görüntüyü çözer, sayfayı bulur ve düzleştirir: (gri, köşeler, PNG, sayfa bulundu mu).
(GrayImage, List<Pt>, Uint8List, bool)? prepareTemplatePhoto((Uint8List, double) input) {
  final (bytes, aspect) = input;
  final g = GrayImage.decode(bytes);
  if (g == null) return null;
  List<Pt> corners;
  var found = true;
  try {
    corners = PageFinder.find(g, aspect: aspect);
  } catch (_) {
    found = false;
    corners = [Pt(0, 0), Pt(g.width - 1.0, 0), Pt(g.width - 1.0, g.height - 1.0), Pt(0, g.height - 1.0)];
  }
  final page = rectifyPage(g, corners, aspect: aspect, width: 1000);
  return (g, corners, Uint8List.fromList(img.encodePng(page)), found);
}

DetectedForm _detect((GrayImage, List<Pt>, double) input) {
  final (g, c, aspect) = input;
  return detectFormGrids(g, c, aspect: aspect);
}

OmrResult _testRead((GrayImage, List<Pt>, FormTemplate) input) {
  final (g, c, t) = input;
  return TemplateReader(t, questionCount: t.questionCount, choiceCount: t.choiceCount).read(g, corners: c);
}
