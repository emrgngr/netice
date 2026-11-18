import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../omr/form_layout.dart';
import '../omr/omr_reader.dart';
import 'widgets.dart';

/// Öğretmenin doğru cevaplarla doldurduğu optik formun fotoğrafından
/// cevap anahtarını okur. Her soru için işaretli şıkları döndürür
/// (boş bırakılan sorular boş küme). İptal edilirse veya okunamazsa null.
Future<List<Set<int>>?> readKeyFromPhoto(BuildContext context, {required int questions, required int choices}) async {
  final files = await FilePicker.pickFiles(dialogTitle: 'Cevap anahtarı formunun fotoğrafı', type: FileType.image);
  if (files.isEmpty || !context.mounted) return null;
  final bytes = await files.first.readAsBytes();
  if (!context.mounted) return null;
  try {
    final r = await compute(_readKey, _KeyJob(bytes, questions, choices));
    if (!context.mounted) return null;
    if (r == null) {
      toast(context, 'Fotoğraf çözülemedi. Başka bir fotoğraf deneyin.');
      return null;
    }
    final filled = r.where((s) => s.isNotEmpty).length;
    toast(context, '$filled / $questions sorunun cevabı okundu. Lütfen kontrol edin.');
    return r;
  } on OmrException catch (e) {
    if (context.mounted) toast(context, e.message);
    return null;
  } catch (_) {
    if (context.mounted) toast(context, 'Form okunamadı. Dört köşe karesi görünecek şekilde yeniden çekin.');
    return null;
  }
}

class _KeyJob {
  final Uint8List bytes;
  final int questions, choices;
  _KeyJob(this.bytes, this.questions, this.choices);
}

List<Set<int>>? _readKey(_KeyJob j) => keyFromImageBytes(j.bytes, j.questions, j.choices);

/// Fotoğraf baytlarından cevap anahtarı (test edilebilir, saf fonksiyon).
List<Set<int>>? keyFromImageBytes(Uint8List bytes, int questions, int choices) {
  final gray = GrayImage.decode(bytes);
  if (gray == null) return null;
  final r = OmrReader(FormLayout(questionCount: questions, choiceCount: choices)).read(gray);
  return [for (final q in r.questions) q.answer.marked.toSet()];
}
