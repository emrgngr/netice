
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/models.dart';
import '../core/scoring.dart';
import '../core/store.dart' show ScanStatus, specFor;
import '../main.dart';
import '../omr/form_layout.dart';
import '../omr/frame_quality.dart';
import '../omr/omr_reader.dart';
import '../omr/sheet_reader.dart';
import '../omr/kid_layout.dart';
import '../omr/serial_scanner.dart';
import 'exam_screen.dart';
import 'review_screen.dart' show unmatchedLabel;
import 'scan_screen.dart';
import 'theme.dart';
import 'widgets.dart';
import '../l10n/l10n.dart';

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
  _FrameJob? _lastJob;
  bool _torch = false;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  /// Çocuk sınavı: köşedeki küçük cevap kutusu okunur.
  late final bool _kid = StoreScope.of(context).examById(widget.examId)?.kidForm ?? false;
  late final _scanner = SerialScanner(releaseAfter: _kid ? 3 : 0);
  Sheet? _lastSheet;
  String get _frameHint => _kid
      ? tr('Köşedeki cevap kutusunu dört siyah karesi görünecek şekilde çerçeveye alın')
      : tr('Kâğıdı dört köşesi görünecek şekilde çerçeveye alın');
  late String _hint = _frameHint;
  bool _warn = false;
  FrameAdvice? _pendingAdvice;
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
        setState(() => _error = tr('Bu cihazda kamera bulunamadı.'));
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
          ? tr('Kamera izni verilmedi. Telefonun Ayarlar > Uygulamalar > Netice > İzinler bölümünden kameraya izin verin.')
          : tr('Kamera açılamadı: {0}', [e.description ?? e.code]));
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
      spec: specFor(StoreScope.of(context), exam),
    );
    compute(_readFrame, job).then((out) {
      if (!mounted) return;
      final (r, advice) = out;
      if (r != null) _lastJob = job;
      final accepted = _scanner.feed(r);
      if (accepted != null) {
        _accept(exam, accepted);
      } else {
        _showAdvice(r != null ? FrameAdvice.ok : advice);
      }
    }).whenComplete(() => _busy = false);
  }

  /// Canlı ipucu: aynı sorun iki ardışık karede görülürse gösterilir (titreşmesin diye).
  void _showAdvice(FrameAdvice a) {
    final confirmed = a == FrameAdvice.ok || a == _pendingAdvice;
    _pendingAdvice = a;
    if (!confirmed) return;
    final text = switch (a) {
      FrameAdvice.tooDark => _torch ? tr('Ortam karanlık · daha aydınlık bir yere geçin') : tr('Ortam karanlık · feneri açın'),
      FrameAdvice.glare => tr('Işık yansıyor · telefonu biraz eğin'),
      FrameAdvice.blurry => tr('Görüntü bulanık · telefonu sabit tutun'),
      FrameAdvice.tooFar => tr('Biraz yaklaşın'),
      FrameAdvice.tilted => tr('Telefonu kâğıda paralel tutun'),
      FrameAdvice.edge => tr('Köşeler sığmıyor · biraz uzaklaşın'),
      FrameAdvice.ok => _scanner.formVisible ? tr('Form algılandı · okunuyor') : _frameHint,
    };
    if (text == _hint) return;
    setState(() {
      _hint = text;
      _warn = a != FrameAdvice.ok;
    });
  }

  void _accept(Exam exam, OmrResult r) {
    final store = StoreScope.of(context);
    final sheet = store.addScan(exam, r);
    final status = store.lastScanStatus;
    if (status == ScanStatus.duplicate) {
      HapticFeedback.lightImpact();
      setState(() {
        _hint = tr('Bu kâğıt zaten okunmuştu · sıradakini koyun');
        _warn = true;
      });
      return;
    }
    // İşaretli kâğıt görüntüsü arka planda hazırlanıp kâğıda bağlanır.
    final job = _lastJob;
    if (job != null) {
      compute(_rectifyFrame, job).then((jpeg) {
        if (jpeg != null) store.attachSheetImage(sheet, jpeg);
      });
    }
    if (sheet.examId != exam.id) {
      toast(context, tr('Bu kâğıt "{0}" sınavına ait; oraya kaydedildi.', [store.examById(sheet.examId)?.name]));
    }
    if (status == ScanStatus.conflict) {
      toast(context, tr('Bu numarayla farklı cevaplı bir kâğıt zaten okunmuştu. Yeni kâğıt "Kontrol" listesine alındı; kimin olduğunu oradan seçin.'));
    }
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);
    setState(() {
      _lastSheet = sheet;
      _sessionCount++;
      _hint = status == ScanStatus.replaced ? tr('Yeniden okundu · önceki okumanın yerine geçti') : tr('Okundu · sıradaki kâğıdı koyun');
      _warn = false;
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
                  Text(tr('{0} soru · {1} şık', [exam.questionCount, exam.choiceCount]),
                      style: const TextStyle(color: Colors.white60, fontSize: 12)),
                ]),
              ),
              IconButton(
                tooltip: tr('Fener'),
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
                text: tr('Seri mod açık'),
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
                              IgnorePointer(child: CustomPaint(painter: _GuidePainter(active: _scanner.formVisible, ratio: _kid ? 1 / kidLayoutFor(StoreScope.of(context).examById(widget.examId)!)!.aspect : null))),
                              Positioned(
                                top: 14,
                                left: 0,
                                right: 0,
                                child: Center(
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    child: _Pill(
                                        key: ValueKey(_hint),
                                        text: _hint,
                                        dark: true,
                                        icon: _warn ? Icons.lightbulb_outline_rounded : null,
                                        iconColor: NColors.amber),
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
                  label: Text(review > 0 ? 'Kontrol ($review)' : tr('Galeriden')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: GlowButton(
                  height: 54,
                  label: tr('Bitir ve sonuçlar'),
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
          if (icon != null) ...[Icon(icon, size: icon == Icons.circle ? 9 : 15, color: iconColor), const SizedBox(width: 6)],
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
            Text(st == null ? unmatchedLabel(sheet) : '${st.fullName} · ${st.number}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: NColors.ink, fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 2),
            warn
                ? Text(tr('Kontrol gerekiyor'), style: TextStyle(color: Color(0xFFB7791F), fontWeight: FontWeight.w600))
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
  /// Genişlik / yükseklik; null = A4 form.
  final double? boxRatio;
  _GuidePainter({required this.active, double? ratio}) : boxRatio = ratio;

  @override
  void paint(Canvas canvas, Size s) {
    final ratio = boxRatio ?? FormLayout.pageWidth / FormLayout.pageHeight;
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
  bool shouldRepaint(_GuidePainter o) => o.active != active || o.boxRatio != boxRatio;
}

class _FrameJob {
  final Uint8List bytes;
  final int width, height, bytesPerRow, quarterTurns;
  final bool bgra;
  final ReadSpec spec;
  _FrameJob({
    required this.bytes,
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.bgra,
    required this.quarterTurns,
    required this.spec,
  });
}

/// Karedeki formu yeniden bulup düzleştirilmiş JPEG üretir.
Uint8List? _rectifyFrame(_FrameJob j) {
  try {
    final g = (j.bgra
            ? GrayImage.fromBgra(j.bytes, j.width, j.height, j.bytesPerRow)
            : GrayImage.fromLumaPlane(j.bytes, j.width, j.height, j.bytesPerRow))
        .rotate(j.quarterTurns);
    return sheetJpeg(g, readSheet(g, j.spec), j.spec);
  } catch (_) {
    return null;
  }
}

/// Kareyi okur ve canlı ipucunu hesaplar.
(OmrResult?, FrameAdvice) _readFrame(_FrameJob j) {
  try {
    final g = (j.bgra
            ? GrayImage.fromBgra(j.bytes, j.width, j.height, j.bytesPerRow)
            : GrayImage.fromLumaPlane(j.bytes, j.width, j.height, j.bytesPerRow))
        .rotate(j.quarterTurns);
    OmrResult? r;
    try {
      r = readSheet(g, j.spec);
    } catch (_) {}
    final advice = FrameQuality.assess(g, markers: r?.markers);
    // Hiçbir şey okunmadıysa (yanlış eşleşme) kabul etme.
    if (r != null && r.studentNumber == null && r.questions.every((q) => q.answer.state == MarkState.blank)) r = null;
    return (r, advice);
  } catch (_) {
    return (null, FrameAdvice.ok);
  }
}

/// Telefonda kamera, masaüstünde dosya/PDF okuma ekranı.
Route<void> scanRoute(String examId) => MaterialPageRoute(
      builder: (_) => (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)
          ? CameraScanScreen(examId: examId)
          : ScanScreen(examId: examId),
    );

/// Kullanılmayan değişken uyarısını önlemek için zamanlayıcı türü dışa açılır.
