import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../core/models.dart';
import '../core/scoring.dart';
import '../core/store.dart' show ScanStatus, specFor;
import '../main.dart';
import '../omr/form_layout.dart';
import '../omr/form_raster.dart';
import '../omr/omr_reader.dart';
import '../omr/sheet_reader.dart';
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

  /// Aynı kâğıt zaten okunmuştu (hata değil, bilgi).
  final bool duplicate;
  _ScanEntry(this.source, {this.sheet, this.error, this.duplicate = false});
}

/// Toplu okumada sırayla işlenecek bir dosya.
class _Input {
  final String name;
  final Future<Uint8List> Function() bytes;
  _Input(this.name, this.bytes);
}

class _ScanScreenState extends State<ScanScreen> {
  final List<_ScanEntry> _entries = [];
  bool _busy = false;
  String _status = '';
  int _batchTotal = 0, _batchDone = 0;
  bool _cancel = false;
  bool _onlyProblems = false;

  static bool get _mobile => defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

  Exam get _exam => StoreScope.of(context).examById(widget.examId)!;

  Future<void> _readGray(String source, GrayImage gray) async {
    final exam = _exam;
    try {
      final (r, jpeg) = await compute(_readJob, _Job(gray, specFor(StoreScope.of(context), exam)));
      if (!mounted) return;
      final store = StoreScope.of(context);
      final sheet = store.addScan(exam, r);
      final status = store.lastScanStatus;
      if (jpeg != null && status != ScanStatus.duplicate) store.attachSheetImage(sheet, jpeg);
      if (status == ScanStatus.duplicate) {
        setState(() => _entries.insert(0, _ScanEntry(source, sheet: sheet, duplicate: true)));
        return;
      }
      if (status == ScanStatus.conflict) {
        toast(context, 'Bu numarayla farklı cevaplı bir kâğıt zaten var. Kâğıt "Kontrol" listesine alındı.');
      }
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
    await _processAll([for (final f in files) _Input(f.name, f.readAsBytes)]);
  }

  /// Telefonun galerisinden birden çok fotoğraf seçip sırayla okur.
  Future<void> _pickGallery() async {
    List<XFile> files;
    try {
      files = await ImagePicker().pickMultiImage(requestFullMetadata: false);
    } catch (e) {
      if (mounted) toast(context, 'Galeri açılamadı: $e');
      return;
    }
    if (files.isEmpty) return;
    await _processAll([for (final f in files) _Input(f.name, f.readAsBytes)]);
  }

  Future<void> _processAll(List<_Input> inputs) async {
    final startEntries = _entries.length;
    setState(() {
      _busy = true;
      _cancel = false;
      _batchTotal = inputs.length;
      _batchDone = 0;
    });
    for (final f in inputs) {
      if (_cancel || !mounted) break;
      final bytes = await f.bytes();
      if (f.name.toLowerCase().endsWith('.pdf')) {
        var page = 0;
        await for (final raster in Printing.raster(bytes, dpi: 150)) {
          if (_cancel || !mounted) break;
          page++;
          setState(() => _status = '${f.name} · sayfa $page okunuyor');
          await _readGray('${f.name} · s.$page', _rgbaToGray(raster.pixels, raster.width, raster.height));
        }
      } else {
        setState(() => _status = '${f.name} okunuyor');
        final gray = await compute(_decodeJob, bytes);
        if (!mounted) return;
        if (gray == null) {
          setState(() => _entries.insert(0, _ScanEntry(f.name, error: 'Görüntü açılamadı.')));
        } else {
          await _readGray(f.name, gray);
        }
      }
      if (mounted) setState(() => _batchDone++);
    }
    if (!mounted) return;
    final batch = _entries.sublist(0, _entries.length - startEntries);
    final ok = batch.where((e) => e.sheet != null && !e.duplicate && !e.sheet!.needsReview).length;
    final review = batch.where((e) => e.sheet != null && !e.duplicate && e.sheet!.needsReview).length;
    final dup = batch.where((e) => e.duplicate).length;
    final err = batch.where((e) => e.sheet == null).length;
    setState(() {
      _busy = false;
      _batchTotal = 0;
      _status = [
        if (_cancel) 'Durduruldu',
        '$ok okundu',
        if (review > 0) '$review kontrol bekliyor',
        if (dup > 0) '$dup zaten okunmuştu',
        if (err > 0) '$err okunamadı',
      ].join(' · ');
      _onlyProblems = false;
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
    final shown = _onlyProblems
        ? _entries.where((e) => e.sheet == null || e.duplicate || e.sheet!.needsReview).toList()
        : _entries;

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
              if (_batchTotal > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: _batchDone / _batchTotal,
                          minHeight: 8,
                          color: NColors.emerald,
                          backgroundColor: Colors.white12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('$_batchDone / $_batchTotal', style: const TextStyle(color: Colors.white, fontFeatures: tabular)),
                    TextButton(
                      onPressed: _cancel ? null : () => setState(() => _cancel = true),
                      child: const Text('Durdur', style: TextStyle(color: NColors.coral)),
                    ),
                  ]),
                ),
              if (_status.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    Expanded(child: Text(_status, style: const TextStyle(color: Colors.white70))),
                    if (!_busy && _entries.any((e) => e.sheet == null || e.duplicate || e.sheet!.needsReview))
                      FilterChip(
                        label: const Text('Yalnızca sorunlular'),
                        selected: _onlyProblems,
                        onSelected: (v) => setState(() => _onlyProblems = v),
                      ),
                  ]),
                ),
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
                        itemCount: shown.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final e = shown[i];
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
                          if (e.duplicate) {
                            final who = students[e.sheet!.studentId];
                            return Card(
                              color: NColors.darkSurface,
                              child: ListTile(
                                leading: const Icon(Icons.content_copy_rounded, color: Colors.white54),
                                title: Text(e.source, style: const TextStyle(color: Colors.white)),
                                subtitle: Text(
                                    'Bu kâğıt zaten okunmuştu${who == null ? '' : ' (${who.fullName})'}; tekrar eklenmedi.',
                                    style: const TextStyle(color: Colors.white70)),
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
                  if (_mobile) ...[
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _pickGallery,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Galeriden seç'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      tooltip: 'Dosya veya PDF seç',
                      style: IconButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24)),
                      onPressed: _busy ? null : _pickFiles,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                    ),
                  ] else
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
  final ReadSpec spec;
  _Job(this.image, this.spec);
}

(OmrResult, Uint8List?) _readJob(_Job j) {
  final r = readSheet(j.image, j.spec);
  Uint8List? jpeg;
  try {
    jpeg = sheetJpeg(j.image, r, j.spec);
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
