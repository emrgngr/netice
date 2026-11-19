import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../core/models.dart';
import '../core/scoring.dart';
import '../main.dart';
import '../omr/form_layout.dart';
import '../omr/form_raster.dart';
import '../omr/omr_reader.dart';
import '../omr/rectify.dart';
import 'review_screen.dart' show unmatchedLabel;
import 'theme.dart';
import 'widgets.dart';

/// Okuma ekranı. İlk sürüm: fotoğraf/tarama dosyaları ve çok sayfalı PDF
/// toplu okuma. Kamerayla seri mod bir sonraki adımda eklenecek.
class ScanScreen extends StatefulWidget {
  final String examId;
  const ScanScreen({super.key, required this.examId});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanEntry {
  final String source;
  final Sheet? sheet;
  final String? error;
  _ScanEntry(this.source, {this.sheet, this.error});
}

class _ScanScreenState extends State<ScanScreen> {
  final List<_ScanEntry> _entries = [];
  bool _busy = false;
  String _status = '';

  Exam get _exam => StoreScope.of(context).examById(widget.examId)!;

  Future<void> _readGray(String source, GrayImage gray) async {
    final exam = _exam;
    try {
      final (r, jpeg) = await compute(_readJob, _Job(gray, exam.questionCount, exam.choiceCount, exam.hasBooklets));
      if (!mounted) return;
      final store = StoreScope.of(context);
      final sheet = store.addScan(exam, r);
      if (jpeg != null) store.attachSheetImage(sheet, jpeg);
      if (sheet.examId != exam.id) {
        toast(context, 'Bu kâğıt "${store.examById(sheet.examId)?.name}" sınavına ait; oraya kaydedildi.');
      }
      HapticFeedback.lightImpact();
      SystemSound.play(SystemSoundType.click);
      setState(() => _entries.insert(0, _ScanEntry(source, sheet: sheet)));
    } on OmrException catch (e) {
      setState(() => _entries.insert(0, _ScanEntry(source, error: e.message)));
    } catch (e) {
      setState(() => _entries.insert(0, _ScanEntry(source, error: 'Okunamadı: $e')));
    }
  }

  Future<void> _pickFiles() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Cevap kâğıtlarını seçin',
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (files.isEmpty) return;
    setState(() => _busy = true);
    var n = 0;
    for (final f in files) {
      final bytes = await f.readAsBytes();
      if (f.name.toLowerCase().endsWith('.pdf')) {
        var page = 0;
        await for (final raster in Printing.raster(bytes, dpi: 150)) {
          page++;
          setState(() => _status = '${f.name} · sayfa $page okunuyor');
          await _readGray('${f.name} · s.$page', _rgbaToGray(raster.pixels, raster.width, raster.height));
          n++;
        }
      } else {
        setState(() => _status = '${f.name} okunuyor');
        final gray = await compute(_decodeJob, bytes);
        if (gray == null) {
          setState(() => _entries.insert(0, _ScanEntry(f.name, error: 'Görüntü açılamadı.')));
        } else {
          await _readGray(f.name, gray);
        }
        n++;
      }
    }
    setState(() {
      _busy = false;
      _status = '$n kâğıt işlendi';
    });
  }

  /// Ekranda örnek bir doldurulmuş form üretip okur: öğretmen sistemi
  /// kâğıt basmadan deneyebilir.
  Future<void> _trySample() async {
    final exam = _exam;
    final store = StoreScope.of(context);
    final students = store.studentsOf(exam.className);
    final rnd = math.Random();
    final st = students.isEmpty ? null : students[rnd.nextInt(students.length)];
    final answers = <int, List<int>>{
      for (var q = 0; q < exam.questionCount; q++)
        if (rnd.nextDouble() > 0.08)
          q: [rnd.nextDouble() < 0.7 ? exam.questions[q].correct.first : rnd.nextInt(exam.choiceCount)]
    };
    final number = st == null ? null : (int.tryParse(st.number) ?? 0).toString().padLeft(FormLayout.studentDigits, '0');
    setState(() => _busy = true);
    final gray = await compute(_sampleJob, _Sample(exam.questionCount, exam.choiceCount, answers, number));
    await _readGray('Örnek form${st == null ? '' : ' · ${st.fullName}'}', gray);
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final exam = _exam;
    final store = StoreScope.of(context);
    final students = store.studentById;
    final read = store.sheetsOf(exam.id).length;
    final total = store.studentsOf(exam.className).length;
    final t = Theme.of(context);

    return Scaffold(
      backgroundColor: NColors.darkBg,
      appBar: AppBar(
        backgroundColor: NColors.darkBg,
        foregroundColor: Colors.white,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${exam.className} · ${exam.name}', style: const TextStyle(color: Colors.white)),
          Text('${exam.questionCount} soru · ${exam.choiceCount} şık',
              style: t.textTheme.bodySmall?.copyWith(color: Colors.white70)),
        ]),
      ),
      body: Watermark(child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Chip(
                    backgroundColor: NColors.darkSurface,
                    side: BorderSide.none,
                    label: Text('$read${total > 0 ? ' / $total' : ''} okundu',
                        style: const TextStyle(color: Colors.white, fontFeatures: tabular)),
                  ),
                  const Spacer(),
                  if (_busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                ]),
              ),
              if (_status.isNotEmpty)
                Text(_status, style: const TextStyle(color: Colors.white70)),
              Expanded(
                child: _entries.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.document_scanner_outlined, size: 72, color: NColors.emerald),
                          const SizedBox(height: 16),
                          const Text(
                            'Cevap kâğıtlarının fotoğraflarını ya da tarayıcıdan çıkan çok sayfalı PDF\'i seçin. '
                            'Kâğıdın dört köşesindeki siyah kareler görünür olmalı.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white70, height: 1.5),
                          ),
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: _busy ? null : _trySample,
                            child: const Text('Kâğıt basmadan örnek formla dene', style: TextStyle(color: NColors.emerald)),
                          ),
                        ]),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _entries.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final e = _entries[i];
                          if (e.sheet == null) {
                            return Card(
                              color: NColors.darkSurface,
                              child: ListTile(
                                leading: const Icon(Icons.error_outline, color: NColors.coral),
                                title: Text(e.source, style: const TextStyle(color: Colors.white)),
                                subtitle: Text(e.error ?? '', style: const TextStyle(color: Colors.white70)),
                              ),
                            );
                          }
                          final r = Scorer.score(exam, e.sheet!);
                          final st = students[e.sheet!.studentId];
                          final reviewN = e.sheet!.answers.where((a) => a.needsReview).length;
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: (e.sheet!.needsReview ? NColors.amber : NColors.emerald).withValues(alpha: 0.18),
                                child: Icon(e.sheet!.needsReview ? Icons.priority_high : Icons.check,
                                    color: e.sheet!.needsReview ? NColors.amber : NColors.emerald),
                              ),
                              title: Text(st == null ? unmatchedLabel(e.sheet!) : '${st.fullName} · ${st.number}',
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: reviewN > 0
                                  ? Text('$reviewN işaret kontrol bekliyor', style: const TextStyle(color: NColors.amber))
                                  : DybText(r.correct, r.wrong, r.blank),
                              trailing: Text(fmt1(r.score),
                                  style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabular)),
                            ),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24)),
                      onPressed: _busy ? null : _trySample,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Örnek form'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _pickFiles,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Fotoğraf / PDF seç'),
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Bitir ve sonuçlar', style: TextStyle(color: Colors.white)),
                ),
              ),
            ]),
          ),
        ),
      )),
    );
  }
}

GrayImage _rgbaToGray(Uint8List rgba, int w, int h) {
  final out = Uint8List(w * h);
  for (var i = 0, j = 0; i < out.length; i++, j += 4) {
    out[i] = ((rgba[j] * 299 + rgba[j + 1] * 587 + rgba[j + 2] * 114) ~/ 1000);
  }
  return GrayImage(w, h, out);
}

class _Job {
  final GrayImage image;
  final int questions;
  final int choices;
  final bool booklets;
  _Job(this.image, this.questions, this.choices, this.booklets);
}

(OmrResult, Uint8List?) _readJob(_Job j) {
  final r = OmrReader(FormLayout(questionCount: j.questions, choiceCount: j.choices, booklets: j.booklets)).read(j.image);
  Uint8List? jpeg;
  try {
    jpeg = rectifiedJpeg(j.image, r.markers);
  } catch (_) {}
  return (r, jpeg);
}

GrayImage? _decodeJob(Uint8List bytes) => GrayImage.decode(bytes);

class _Sample {
  final int questions, choices;
  final Map<int, List<int>> answers;
  final String? number;
  _Sample(this.questions, this.choices, this.answers, this.number);
}

GrayImage _sampleJob(_Sample s) {
  final raster = FormRaster(FormLayout(questionCount: s.questions, choiceCount: s.choices));
  return GrayImage.fromImage(raster.render(answers: s.answers, studentNumber: s.number));
}
