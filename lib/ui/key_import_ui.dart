import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

import '../core/doc_text.dart';
import '../core/key_import.dart';
import '../l10n/l10n.dart';
import '../omr/form_layout.dart';
import '../omr/omr_reader.dart';
import 'widgets.dart';

/// Yazı tanıma (fotoğraftaki yazıyı okuma) yalnız telefonda var.
bool get ocrSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

enum KeySource { document, gallery, camera, neticeForm }

/// "Görselden veya belgeden oku" seçenekleri.
Future<KeySource?> pickKeySource(BuildContext context) => showModalBottomSheet<KeySource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(tr('Belge yükle')),
            subtitle: Text(tr('PDF, Word, Excel ya da metin. Tüm kitapçıkların cevapları ve konu dağılımı okunur.')),
            onTap: () => Navigator.pop(ctx, KeySource.document),
          ),
          if (ocrSupported) ...[
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text(tr('Görselden oku')),
              subtitle: Text(tr('Cevap anahtarının fotoğrafı ya da ekran görüntüsü')),
              onTap: () => Navigator.pop(ctx, KeySource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(tr('Fotoğrafını çek')),
              subtitle: Text(tr('Basılı cevap anahtarını kamerayla çekin')),
              onTap: () => Navigator.pop(ctx, KeySource.camera),
            ),
          ],
          ListTile(
            leading: const Icon(Icons.grid_on_rounded),
            title: Text(tr('Netice cevap formundan oku')),
            subtitle: Text(tr('Doğru cevaplarla doldurduğunuz formların fotoğrafları (her kitapçık için bir form)')),
            onTap: () => Navigator.pop(ctx, KeySource.neticeForm),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );

/// Seçilen kaynaktan cevap anahtarlarını okur. İptal ya da hata olursa null.
Future<KeyImport?> importKey(BuildContext context, KeySource src,
    {required int questions, required int choices, required int booklets}) async {
  try {
    switch (src) {
      case KeySource.document:
        return await _fromDocument(context, choices: choices);
      case KeySource.gallery || KeySource.camera:
        final f = await ImagePicker().pickImage(
            source: src == KeySource.camera ? ImageSource.camera : ImageSource.gallery, requestFullMetadata: false);
        if (f == null) return null;
        final text = await _ocr(f.path);
        if (!context.mounted) return null;
        return _check(context, parseKeyText(text, questions: 100, choices: choices));
      case KeySource.neticeForm:
        return await _fromNeticeForms(context, questions: questions, choices: choices, booklets: booklets);
    }
  } catch (e) {
    if (context.mounted) toast(context, tr('Okunamadı: {0}', [e]));
    return null;
  }
}

KeyImport? _check(BuildContext context, KeyImport r) {
  if (r.keys.isEmpty && r.topics.isEmpty) {
    if (context.mounted) {
      toast(context, tr('Belgede cevap anahtarı bulunamadı. Cevaplar "1-A 2-C…" ya da tablo hâlinde yazılmış olmalı.'));
    }
    return null;
  }
  return r;
}

Future<KeyImport?> _fromDocument(BuildContext context, {required int choices}) async {
  final files = await FilePicker.pickFiles(
    dialogTitle: tr('Cevap anahtarı belgesi'),
    type: FileType.custom,
    allowedExtensions: ['pdf', 'docx', 'xlsx', 'txt', 'csv'],
  );
  if (files.isEmpty || !context.mounted) return null;
  final f = files.first;
  final bytes = await f.readAsBytes();
  final name = f.name.toLowerCase();
  var text = await compute((List<Object> a) => documentText(a[0] as Uint8List, a[1] as String), [bytes, name]);
  // Taranmış PDF'te yazı yoktur: telefonda sayfaları görüntüye çevirip yazı tanıma ile okur.
  if (name.endsWith('.pdf') && !RegExp(r'[A-Za-z]{2,}').hasMatch(text) && ocrSupported) {
    final dir = await getTemporaryDirectory();
    final b = StringBuffer();
    var page = 0;
    await for (final r in Printing.raster(bytes, dpi: 200)) {
      final file = File('${dir.path}/anahtar_${page++}.png');
      await file.writeAsBytes(await r.toPng());
      b.writeln(await _ocr(file.path));
      if (page >= 6) break;
    }
    text = b.toString();
  }
  if (!context.mounted) return null;
  if (text.trim().isEmpty) {
    toast(context, tr('Belgeden yazı okunamadı. Eski .doc/.xls dosyalarını .docx/.xlsx olarak kaydedip deneyin.'));
    return null;
  }
  return _check(context, parseKeyText(text, questions: 100, choices: choices));
}

Future<String> _ocr(String path) async {
  final rec = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final r = await rec.processImage(InputImage.fromFilePath(path));
    return rowsFromBoxes([
      for (final b in r.blocks)
        for (final l in b.lines) (l.boundingBox.left, l.boundingBox.top, l.boundingBox.right, l.boundingBox.bottom, l.text),
    ]);
  } finally {
    await rec.close();
  }
}

/// Netice cevap formlarının fotoğrafları: her formdaki kitapçık işareti
/// hangi kitapçığın anahtarı olduğunu söyler (işaret yoksa sıradaki kitapçık).
Future<KeyImport?> _fromNeticeForms(BuildContext context,
    {required int questions, required int choices, required int booklets}) async {
  final files = await FilePicker.pickFiles(dialogTitle: tr('Cevap anahtarı formunun fotoğrafı'), type: FileType.image);
  if (files.isEmpty || !context.mounted) return null;
  final keys = <int, List<int?>>{};
  var nextBooklet = 0;
  for (final f in files) {
    final bytes = await f.readAsBytes();
    final r = await compute(_readForm, _FormJob(bytes, questions, choices, booklets));
    if (r == null) continue;
    var b = r.$2 ?? nextBooklet;
    if (b >= FormLayout.maxBooklets) b = nextBooklet;
    keys[b] = [for (final s in r.$1) s.isEmpty ? null : s.first];
    nextBooklet = b + 1;
  }
  if (!context.mounted) return null;
  if (keys.isEmpty) {
    toast(context, tr('Form okunamadı. Dört köşe karesi görünecek şekilde yeniden çekin.'));
    return null;
  }
  return KeyImport(keys, const {});
}

class _FormJob {
  final Uint8List bytes;
  final int questions, choices, booklets;
  _FormJob(this.bytes, this.questions, this.choices, this.booklets);
}

(List<Set<int>>, int?)? _readForm(_FormJob j) {
  try {
    final gray = GrayImage.decode(j.bytes);
    if (gray == null) return null;
    final r = OmrReader(FormLayout(questionCount: j.questions, choiceCount: j.choices, booklets: j.booklets)).read(gray);
    return ([for (final q in r.questions) q.answer.marked.toSet()], r.booklet);
  } catch (_) {
    return null;
  }
}
