import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// Açılış animasyonu. Gündüz (07:00–19:00) sıcak kâğıt tonlarında güneş
/// ışıltısı, gece lacivert gökyüzünde yıldızlar ve hilal. Logo daireleri
/// optik formdaki gibi tek tek dolar, köşedeki daire onay işaretine dönüşür.
class SplashScreen extends StatefulWidget {
  final Widget next;

  /// null: saate göre; true/false: zorla gece/gündüz (önizleme için).
  final bool? night;

  /// Önizleme için animasyonu belirli bir anda dondurur (0..1).
  final double? freezeAt;

  const SplashScreen({super.key, required this.next, this.night, this.freezeAt});

  static bool isNightNow([DateTime? now]) {
    final h = (now ?? DateTime.now()).hour;
    return h < 7 || h >= 19;
  }

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  static const total = Duration(milliseconds: 2600);
  late final AnimationController _c = AnimationController(vsync: this, duration: total);
  late final bool _night = widget.night ?? SplashScreen.isNightNow();

  @override
  void initState() {
    super.initState();
    if (widget.freezeAt != null) {
      _c.value = widget.freezeAt!;
      return;
    }
    _c.forward().whenComplete(() {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, _, _) => widget.next,
        transitionsBuilder: (_, a, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
          child: ScaleTransition(scale: Tween(begin: 1.03, end: 1.0).animate(a), child: child),
        ),
      ));
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = _night ? Colors.white : NColors.ink;
    return Scaffold(
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          double seg(double a, double b, [Curve c = Curves.easeOutCubic]) => c.transform(((t - a) / (b - a)).clamp(0, 1));
          final word = seg(0.50, 0.72);
          final slogan = seg(0.62, 0.82);
          return Stack(fit: StackFit.expand, children: [
            CustomPaint(painter: _SkyPainter(_night, t)),
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox.square(dimension: 128, child: CustomPaint(painter: _AnimatedMark(t, ink, _night))),
                const SizedBox(height: 26),
                Opacity(
                  opacity: word,
                  child: Transform.translate(
                    offset: Offset(0, 14 * (1 - word)),
                    child: Text('Netice',
                        style: TextStyle(
                            fontFamily: 'PlusJakartaSans',
                            fontSize: 44,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.2 + 4 * (1 - word),
                            color: ink)),
                  ),
                ),
                const SizedBox(height: 6),
                Opacity(
                  opacity: slogan,
                  child: Text('Kâğıttan sonuca, saniyeler içinde.',
                      style: TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: ink.withValues(alpha: 0.65))),
                ),
              ]),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 48,
              child: Opacity(
                opacity: seg(0.7, 0.9) * (1 - seg(0.94, 1.0)),
                child: Center(
                  child: SizedBox(
                    width: 120,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: seg(0.7, 1.0, Curves.easeInOut),
                        minHeight: 3,
                        color: NColors.emerald,
                        backgroundColor: ink.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _SkyPainter extends CustomPainter {
  final bool night;
  final double t;
  _SkyPainter(this.night, this.t);

  @override
  void paint(Canvas canvas, Size s) {
    final rect = Offset.zero & s;
    if (night) {
      canvas.drawRect(
          rect,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF050A1C), Color(0xFF0F1B3D), Color(0xFF1A2B5E)],
            ).createShader(rect));
      // Yıldızlar: sabit tohumla, her biri kendi hızında yanıp söner.
      final rnd = math.Random(7);
      for (var i = 0; i < 90; i++) {
        final p = Offset(rnd.nextDouble() * s.width, rnd.nextDouble() * s.height * 0.75);
        final r = 0.6 + rnd.nextDouble() * 1.4;
        final phase = rnd.nextDouble() * math.pi * 2;
        final tw = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(phase + t * 9));
        final appear = ((t * 3) - rnd.nextDouble()).clamp(0.0, 1.0);
        canvas.drawCircle(p, r, Paint()..color = Colors.white.withValues(alpha: tw * appear * 0.9));
      }
      // Hilal
      final moon = Offset(s.width * 0.8, s.height * 0.14);
      final mr = 26.0;
      final up = Curves.easeOutCubic.transform((t / 0.5).clamp(0, 1));
      final mc = moon + Offset(0, 30 * (1 - up));
      canvas.drawCircle(mc, mr * 2.6, Paint()
        ..color = const Color(0xFFFFE9B0).withValues(alpha: 0.10 * up)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30));
      canvas.saveLayer(Rect.fromCircle(center: mc, radius: mr + 2), Paint());
      canvas.drawCircle(mc, mr, Paint()..color = const Color(0xFFFFE9B0).withValues(alpha: up));
      canvas.drawCircle(mc + const Offset(11, -7), mr * 0.92, Paint()..blendMode = BlendMode.clear);
      canvas.restore();
      // Alt tarafta zümrüt ışık
      canvas.drawCircle(Offset(s.width / 2, s.height * 1.05), s.width * 0.8, Paint()
        ..color = NColors.emerald.withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80));
    } else {
      canvas.drawRect(
          rect,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFF6E3), Color(0xFFF6F3EC), Color(0xFFEFF7F2)],
            ).createShader(rect));
      // Güneş ışıltısı ve dönen ışınlar
      final sun = Offset(s.width * 0.82, s.height * 0.12);
      final up = Curves.easeOutCubic.transform((t / 0.5).clamp(0, 1));
      canvas.drawCircle(sun, 160, Paint()
        ..color = const Color(0xFFFFC857).withValues(alpha: 0.28 * up)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60));
      canvas.save();
      canvas.translate(sun.dx, sun.dy);
      canvas.rotate(t * 0.6);
      final ray = Paint()..color = const Color(0xFFFFC857).withValues(alpha: 0.12 * up);
      for (var i = 0; i < 12; i++) {
        canvas.rotate(math.pi / 6);
        canvas.drawPath(
            Path()
              ..moveTo(0, -6)
              ..lineTo(s.width * 0.9, -26)
              ..lineTo(s.width * 0.9, 26)
              ..lineTo(0, 6)
              ..close(),
            ray);
      }
      canvas.restore();
      canvas.drawCircle(sun, 30 * up, Paint()..color = const Color(0xFFFFC857).withValues(alpha: 0.9));
      // Alt tarafta zümrüt ışık
      canvas.drawCircle(Offset(s.width * 0.1, s.height * 1.0), s.width * 0.7, Paint()
        ..color = NColors.emerald.withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80));
    }
    // Hafif optik daire deseni
    final dot = Paint()
      ..color = (night ? Colors.white : NColors.ink).withValues(alpha: 0.035)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var y = 0; y < 6; y++) {
      for (var x = 0; x < 5; x++) {
        canvas.drawCircle(Offset(24 + x * 22.0, s.height - 160 + y * 22.0), 7, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_SkyPainter o) => o.t != t || o.night != night;
}

/// Logo daireleri sırayla dolar; son daire zümrüt olur ve onay çizilir.
class _AnimatedMark extends CustomPainter {
  final double t;
  final Color ink;
  final bool night;
  _AnimatedMark(this.t, this.ink, this.night);

  // N harfinin çizim sırası (sol sütun aşağı, çapraz, sağ sütun yukarı).
  static const order = [(0, 0), (0, 1), (0, 2), (0, 3), (1, 1), (2, 2), (3, 3), (3, 2), (3, 1)];

  @override
  void paint(Canvas canvas, Size s) {
    final cell = s.width / 4;
    final r = cell * 0.36;
    // Boş daire halkaları önce belirir.
    final ringA = Curves.easeOut.transform((t / 0.15).clamp(0, 1));
    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 4; x++) {
        canvas.drawCircle(
            Offset(cell * (x + 0.5), cell * (y + 0.5)),
            r * 0.92,
            Paint()
              ..color = ink.withValues(alpha: 0.25 * ringA)
              ..style = PaintingStyle.stroke
              ..strokeWidth = cell * 0.06);
      }
    }
    // Dolu daireler sırayla "kurşun kalemle" dolar.
    for (var i = 0; i < order.length; i++) {
      final (x, y) = order[i];
      final start = 0.12 + i * 0.035;
      final k = Curves.easeOutBack.transform(((t - start) / 0.10).clamp(0, 1));
      if (k <= 0) continue;
      canvas.drawCircle(Offset(cell * (x + 0.5), cell * (y + 0.5)), r * k, Paint()..color = ink);
    }
    // Onay dairesi
    final c = Offset(cell * 3.5, cell * 0.5);
    final g = Curves.elasticOut.transform(((t - 0.44) / 0.22).clamp(0, 1));
    if (g > 0) {
      final glow = ((t - 0.44) / 0.3).clamp(0.0, 1.0);
      canvas.drawCircle(c, r * (1.2 + glow * 1.4), Paint()
        ..color = NColors.emerald.withValues(alpha: 0.35 * (1 - glow))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawCircle(c, r * g, Paint()..color = NColors.emerald);
      final p = ((t - 0.5) / 0.12).clamp(0.0, 1.0);
      if (p > 0) {
        final path = Path()
          ..moveTo(c.dx - r * 0.45, c.dy + r * 0.02)
          ..lineTo(c.dx - r * 0.1, c.dy + r * 0.38)
          ..lineTo(c.dx + r * 0.5, c.dy - r * 0.32);
        final metric = path.computeMetrics().first;
        canvas.drawPath(
            metric.extractPath(0, metric.length * p),
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = r * 0.26
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round);
      }
    }
  }

  @override
  bool shouldRepaint(_AnimatedMark o) => o.t != t || o.ink != ink;
}
