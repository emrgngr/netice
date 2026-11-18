
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/models.dart';
import '../core/scoring.dart';
import '../main.dart';
import '../omr/form_layout.dart';
import '../omr/omr_reader.dart';
import '../omr/serial_scanner.dart';
import 'exam_screen.dart';
import 'scan_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Kamerayla seri okuma: deklanşör yok. Kâğıt çerçeveye girince dört köşe
/// işareti bulunur, iki ardışık karede aynı okunursa kaydedilir; titreşim
/// ve ses verilir. Öğretmen bir sonraki kâğıdı koyar.
class CameraScanScreen extends StatefulWidget {
  final String examId;
  const CameraScanScreen({super.key, required this.examId});

  @override
  State<CameraScanScreen> createState() => _CameraScanScreenState();
}

class _CameraScanScreenState extends State<CameraScanScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  String? _error;
  bool _busy = false;
  bool _torch = false;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  final _scanner = SerialScanner();
  Sheet? _lastSheet;
  String _hint = 'Kâğıdı dört köşesi görünecek şekilde çerçeveye alın';
  int _sessionCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _start();
    }
  }

  Future<void> _start() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() => _error = 'Bu cihazda kamera bulunamadı.');
        return;
      }
      final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      final c = CameraController(
        back,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420,
      );
      await c.initialize();
      try {
        await c.setFocusMode(FocusMode.auto);
      } catch (_) {}
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _controller = c;
        _error = null;
      });
      await c.startImageStream(_onFrame);
    } on CameraException catch (e) {
      setState(() => _error = e.code.contains('Denied')
          ? 'Kamera izni verilmedi. Telefonun Ayarlar > Uygulamalar > Netice > İzinler bölümünden kameraya izin verin.'
          : 'Kamera açılamadı: ${e.description ?? e.code}');
    }
  }

  void _onFrame(CameraImage frame) {
    final now = DateTime.now();
    if (_busy || now.difference(_lastFrame).inMilliseconds < 250) return;
    _busy = true;
    _lastFrame = now;
    final exam = StoreScope.of(context).examById(widget.examId)!;
    final p = frame.planes.first;
    final job = _FrameJob(
      bytes: Uint8List.fromList(p.bytes),
      width: frame.width,
      height: frame.height,
      bytesPerRow: p.bytesPerRow,
      bgra: frame.format.group == ImageFormatGroup.bgra8888,
      quarterTurns: (_controller?.description.sensorOrientation ?? 90) ~/ 90,
      questions: exam.questionCount,
      choices: exam.choiceCount,
    );
    compute(_readFrame, job).then((r) {
      if (!mounted) return;
      final accepted = _scanner.feed(r);
      if (accepted != null) {
        _accept(exam, accepted);
      } else {
        setState(() => _hint = _scanner.formVisible
            ? 'Form algılandı · okunuyor'
            : 'Kâğıdı dört köşesi görünecek şekilde çerçeveye alın');
      }
    }).whenComplete(() => _busy = false);
  }

  void _accept(Exam exam, OmrResult r) {
    final sheet = StoreScope.of(context).addScan(exam, r);
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);
    setState(() {
      _lastSheet = sheet;
      _sessionCount++;
      _hint = 'Okundu · sıradaki kâğıdı koyun';
    });
  }

  Future<void> _toggleTorch() async {
    final c = _controller;
    if (c == null) return;
    try {
      await c.setFlashMode(_torch ? FlashMode.off : FlashMode.torch);
      setState(() => _torch = !_torch);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final exam = store.examById(widget.examId)!;
    final read = store.sheetsOf(exam.id).length;
    final total = store.studentsOf(exam.className).length;
    final review = store.sheetsOf(exam.id).where((s) => s.needsReview).length;
    final c = _controller;

    return Scaffold(
      backgroundColor: NColors.darkBg,
      body: SafeArea(
        child: Column(children: [
          // Üst çubuk
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
              Expanded(
                child: Column(children: [
                  Text('${exam.className} · ${exam.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                  Text('${exam.questionCount} soru · ${exam.choiceCount} şık',
                      style: const TextStyle(color: Colors.white60, fontSize: 12)),
                ]),
              ),
              IconButton(
                tooltip: 'Fener',
                onPressed: _toggleTorch,
                icon: Icon(_torch ? Icons.flashlight_on : Icons.flashlight_off_outlined, color: Colors.white),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _Pill(
                icon: Icons.circle,
                iconColor: NColors.emerald,
                text: 'Seri mod açık',
              ),
              const SizedBox(width: 8),
              _Pill(text: '$read${total > 0 ? ' / $total' : ''} okundu'),
            ]),
          ),
          // Kamera
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Container(
                  color: NColors.darkSurface,
                  child: _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, height: 1.5)),
                          ),
                        )
                      : (c == null || !c.value.isInitialized)
                          ? const Center(child: CircularProgressIndicator(color: NColors.emerald))
                          : Stack(fit: StackFit.expand, children: [
                              FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: c.value.previewSize?.height ?? 1080,
                                  height: c.value.previewSize?.width ?? 1920,
                                  child: CameraPreview(c),
                                ),
                              ),
                              IgnorePointer(child: CustomPaint(painter: _GuidePainter(active: _scanner.formVisible))),
                              Positioned(
                                top: 14,
                                left: 0,
                                right: 0,
                                child: Center(
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    child: _Pill(key: ValueKey(_hint), text: _hint, dark: true),
                                  ),
                                ),
                              ),
                            ]),
                ),
              ),
            ),
          ),
          // Son okunan
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, a) => SlideTransition(
                position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(a),
                child: FadeTransition(opacity: a, child: child),
              ),
              child: _lastSheet == null
                  ? const SizedBox(height: 76, key: ValueKey('empty'))
                  : _LastCard(key: ValueKey(_sessionCount), exam: exam, sheet: _lastSheet!),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: review > 0 ? NColors.amber : Colors.white,
                    side: BorderSide(color: review > 0 ? NColors.amber.withValues(alpha: 0.6) : Colors.white24),
                    backgroundColor: Colors.white.withValues(alpha: 0.04),
                    minimumSize: const Size(0, 54),
                  ),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ScanScreen(examId: exam.id))),
                  icon: Icon(review > 0 ? Icons.priority_high_rounded : Icons.photo_library_outlined),
                  label: Text(review > 0 ? 'Kontrol ($review)' : 'Galeriden'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: GlowButton(
                  height: 54,
                  label: 'Bitir ve sonuçlar',
                  icon: Icons.check_rounded,
                  onPressed: () => Navigator.of(context)
                      .pushReplacement(MaterialPageRoute(builder: (_) => ExamScreen(examId: exam.id))),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color? iconColor;
  final bool dark;
  const _Pill({super.key, required this.text, this.icon, this.iconColor, this.dark = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: dark ? Colors.black.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 9, color: iconColor), const SizedBox(width: 6)],
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, fontFeatures: tabular)),
        ]),
      );
}

class _LastCard extends StatelessWidget {
  final Exam exam;
  final Sheet sheet;
  const _LastCard({super.key, required this.exam, required this.sheet});

  @override
  Widget build(BuildContext context) {
    final st = StoreScope.of(context).studentById[sheet.studentId];
    final r = Scorer.score(exam, sheet);
    final warn = sheet.needsReview;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 18, 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: warn ? null : emeraldGradient,
            color: warn ? NColors.amber.withValues(alpha: 0.2) : null,
            shape: BoxShape.circle,
          ),
          child: Icon(warn ? Icons.priority_high_rounded : Icons.check_rounded, color: warn ? NColors.amber : Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(st == null ? 'Öğrenci eşleşmedi' : '${st.fullName} · ${st.number}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: NColors.ink, fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 2),
            warn
                ? const Text('Kontrol gerekiyor', style: TextStyle(color: Color(0xFFB7791F), fontWeight: FontWeight.w600))
                : Theme(data: NTheme.light(), child: DybText(r.correct, r.wrong, r.blank)),
          ]),
        ),
        Text(fmt1(r.score),
            style: const TextStyle(color: NColors.ink, fontSize: 30, fontWeight: FontWeight.w800, fontFeatures: tabular)),
      ]),
    );
  }
}

/// Köşe kılavuzları; form algılanınca zümrüt yeşiline döner.
class _GuidePainter extends CustomPainter {
  final bool active;
  _GuidePainter({required this.active});

  @override
  void paint(Canvas canvas, Size s) {
    const ratio = FormLayout.pageWidth / FormLayout.pageHeight;
    var h = s.height * 0.86, w = h * ratio;
    if (w > s.width * 0.9) {
      w = s.width * 0.9;
      h = w / ratio;
    }
    final r = Rect.fromCenter(center: s.center(Offset.zero), width: w, height: h);
    final p = Paint()
      ..color = active ? NColors.emerald : Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const l = 34.0;
    for (final (c, dx, dy) in [
      (r.topLeft, 1.0, 1.0),
      (r.topRight, -1.0, 1.0),
      (r.bottomRight, -1.0, -1.0),
      (r.bottomLeft, 1.0, -1.0),
    ]) {
      canvas.drawLine(c, c + Offset(l * dx, 0), p);
      canvas.drawLine(c, c + Offset(0, l * dy), p);
    }
  }

  @override
  bool shouldRepaint(_GuidePainter o) => o.active != active;
}

class _FrameJob {
  final Uint8List bytes;
  final int width, height, bytesPerRow, quarterTurns, questions, choices;
  final bool bgra;
  _FrameJob({
    required this.bytes,
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.bgra,
    required this.quarterTurns,
    required this.questions,
    required this.choices,
  });
}

OmrResult? _readFrame(_FrameJob j) {
  try {
    final g = j.bgra
        ? GrayImage.fromBgra(j.bytes, j.width, j.height, j.bytesPerRow)
        : GrayImage.fromLumaPlane(j.bytes, j.width, j.height, j.bytesPerRow);
    final r = OmrReader(FormLayout(questionCount: j.questions, choiceCount: j.choices)).read(g.rotate(j.quarterTurns));
    // Hiçbir şey okunmadıysa (yanlış eşleşme) kabul etme.
    if (r.studentNumber == null && r.questions.every((q) => q.answer.state == MarkState.blank)) return null;
    return r;
  } catch (_) {
    return null;
  }
}

/// Telefonda kamera, masaüstünde dosya/PDF okuma ekranı.
Route<void> scanRoute(String examId) => MaterialPageRoute(
      builder: (_) => (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)
          ? CameraScanScreen(examId: examId)
          : ScanScreen(examId: examId),
    );

/// Kullanılmayan değişken uyarısını önlemek için zamanlayıcı türü dışa açılır.
