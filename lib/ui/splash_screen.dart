import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:material_ui/material_ui.dart';

import '../main.dart';

import 'theme.dart';
import '../l10n/l10n.dart';

/// Açılış animasyonu. Gündüz (07:00–19:00) inci beyazı zeminde nane ve
/// şampanya tonlu yumuşak ışık; gece derin lacivertte zümrüt ve çivit ışık.
/// Logo cam bir karo içinde belirir, daireler optik formdaki gibi sırayla
/// dolar, köşedeki daire onaya dönüşür, karonun üstünden ışık geçer; ardından
/// "Netice" yazısı soldan sağa açılır.
class SplashScreen extends StatefulWidget {
  /// Animasyon bir kez sonuna kadar oynadı mı (uygulama açık kaldıkça tekrar oynamaz).
  static bool played = false;

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

class _Palette {
  final List<Color> bg;
  final List<Color> lights;
  final Color ink;
  final Color tileEdge;
  final Color ring;
  const _Palette(this.bg, this.lights, this.ink, this.tileEdge, this.ring);

  static const day = _Palette(
    [Color(0xFFFBFAF6), Color(0xFFF4F1EA), Color(0xFFEEF3EE)],
    [Color(0xFFBFEBD6), Color(0xFFF6E3C2), Color(0xFFD5DDF5)],
    NColors.ink,
    Color(0x1A0F1B3D),
    Color(0x330F1B3D),
  );

  static const night = _Palette(
    [Color(0xFF040817), Color(0xFF0A1330), Color(0xFF0D1A3F)],
    [Color(0xFF0E7C5A), Color(0xFF2B3A8C), Color(0xFF0B5E66)],
    Colors.white,
    Color(0x40FFFFFF),
    Color(0x38FFFFFF),
  );
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  static const total = Duration(milliseconds: 3200);
  late final AnimationController _c = AnimationController(vsync: this, duration: total);
  late final bool _night = widget.night ?? SplashScreen.isNightNow();

  @override
  void initState() {
    super.initState();
    if (widget.freezeAt != null) {
      _c.value = widget.freezeAt!;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _playSound());
    _c.forward().whenComplete(() {
      if (!mounted) return;
      SplashScreen.played = true;
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (_, _, _) => widget.next,
        transitionsBuilder: (_, a, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
          child: ScaleTransition(
              scale: Tween(begin: 1.04, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
              child: child),
        ),
      ));
    });
  }

  /// Açılış melodisi (Ayarlar'dan kapatılabilir). Ses dosyası yoksa ya da
  /// çalınamazsa sessizce geçer.
  Future<void> _playSound() async {
    if (!mounted) return;
    final store = StoreScope.of(context);
    for (var i = 0; i < 10 && !store.loaded; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!mounted || !store.splashSound) return;
    try {
      // Melodi ana sayfaya geçince de bitene kadar çalar, sonra oynatıcı bırakılır.
      final p = AudioPlayer();
      p.onPlayerComplete.first.then((_) => p.dispose()).catchError((_) {});
      await p.setReleaseMode(ReleaseMode.release);
      await p.setVolume(0.8);
      await p.play(AssetSource('sounds/acilis.mp3'), mode: PlayerMode.lowLatency);
    } catch (_) {}
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _night ? _Palette.night : _Palette.day;
    final ink = p.ink;
    return Scaffold(
      backgroundColor: p.bg.first,
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          double seg(double a, double b, [Curve c = Curves.easeOutCubic]) =>
              c.transform(((t - a) / (b - a)).clamp(0.0, 1.0));
          final tileIn = seg(0.04, 0.30, Curves.easeOutBack);
          final word = seg(0.52, 0.74, Curves.easeInOutCubic);
          final slogan = seg(0.66, 0.84);
          final line = seg(0.70, 0.90, Curves.easeInOutCubic);
          final out = seg(0.95, 1.0);
          return Stack(fit: StackFit.expand, children: [
            CustomPaint(painter: _AuroraPainter(p, t, _night)),
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Opacity(
                  opacity: seg(0.04, 0.22),
                  child: Transform.scale(
                    scale: 0.86 + 0.14 * tileIn,
                    child: SizedBox.square(
                      dimension: 168,
                      child: CustomPaint(painter: _TileMark(t, p, _night)),
                    ),
                  ),
                ),
                const SizedBox(height: 34),
                // Kelime soldan sağa yumuşak bir maskeyle açılır.
                Transform.translate(
                  offset: Offset(0, 10 * (1 - word)),
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (r) {
                      final x = -0.25 + word * 1.5;
                      return LinearGradient(
                        colors: const [Colors.white, Colors.white, Colors.transparent],
                        stops: [0, (x - 0.12).clamp(0.0, 1.0), x.clamp(0.0, 1.0)],
                      ).createShader(r);
                    },
                    child: Text(tr('Netice'),
                        style: TextStyle(
                            fontFamily: 'PlusJakartaSans',
                            fontSize: 46,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.4,
                            height: 1.0,
                            color: ink)),
                  ),
                ),
                const SizedBox(height: 16),
                // İnce zümrüt çizgi ortadan iki yana açılır.
                Container(
                  width: 72 * line,
                  height: 2,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(1),
                    gradient: LinearGradient(colors: [
                      NColors.emerald.withValues(alpha: 0),
                      NColors.emerald,
                      NColors.emerald.withValues(alpha: 0),
                    ]),
                  ),
                ),
                const SizedBox(height: 14),
                Opacity(
                  opacity: slogan,
                  child: Text(tr('KÂĞITTAN SONUCA, SANİYELER İÇİNDE'),
                      style: TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.4 + 2 * (1 - slogan),
                          color: ink.withValues(alpha: 0.6))),
                ),
              ]),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 64,
              child: Opacity(
                opacity: seg(0.74, 0.92) * (1 - out),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.lock_outline_rounded, size: 13, color: ink.withValues(alpha: 0.5)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(tr('Çevrimdışı çalışır · Verileriniz bu cihazda kalır') + '\n' + tr('Üçüncü taraf reklam yok · Sizi izleyen reklam ağı yok'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontFamily: 'PlusJakartaSans',
                            fontSize: 12,
                            height: 1.5,
                            fontWeight: FontWeight.w600,
                            color: ink.withValues(alpha: 0.5))),
                  ),
                ]),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 46,
              child: Opacity(
                opacity: seg(0.74, 0.9) * (1 - out),
                child: Center(
                  child: SizedBox(
                    width: 96,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: seg(0.74, 1.0, Curves.easeInOut),
                        minHeight: 2,
                        color: NColors.emerald,
                        backgroundColor: ink.withValues(alpha: 0.1),
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

/// Yavaşça süzülen yumuşak ışık lekeleri (aurora) ve kenar gölgesi.
class _AuroraPainter extends CustomPainter {
  final _Palette p;
  final double t;
  final bool night;
  _AuroraPainter(this.p, this.t, this.night);

  @override
  void paint(Canvas canvas, Size s) {
    final rect = Offset.zero & s;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: p.bg,
          ).createShader(rect));

    final appear = Curves.easeOut.transform((t / 0.35).clamp(0.0, 1.0));
    final w = s.width, h = s.height;
    final a = t * math.pi * 2 * 0.35;
    final blobs = [
      (Offset(w * (0.12 + 0.08 * math.sin(a)), h * (0.20 + 0.04 * math.cos(a * 1.3))), w * 0.85, p.lights[0]),
      (Offset(w * (0.92 - 0.06 * math.cos(a * 0.8)), h * (0.46 + 0.05 * math.sin(a))), w * 0.7, p.lights[1]),
      (Offset(w * (0.36 + 0.08 * math.sin(a * 1.1)), h * (0.90 - 0.03 * math.cos(a))), w * 0.85, p.lights[2]),
    ];
    for (final (c, r, color) in blobs) {
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..shader = RadialGradient(colors: [
              color.withValues(alpha: (night ? 0.55 : 0.8) * appear),
              color.withValues(alpha: 0),
            ]).createShader(Rect.fromCircle(center: c, radius: r)));
    }

    // Logonun arkasında hafif bir hale.
    final center = Offset(w / 2, h * 0.40);
    final halo = Curves.easeOut.transform(((t - 0.05) / 0.4).clamp(0.0, 1.0));
    final hc = night ? NColors.emerald : Colors.white;
    canvas.drawCircle(
        center,
        w * 0.55,
        Paint()
          ..shader = RadialGradient(colors: [
            hc.withValues(alpha: (night ? 0.16 : 0.7) * halo),
            hc.withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(center: center, radius: w * 0.55)));

    // Gece: çok ince, yavaşça yükselen ışık tozları.
    if (night) {
      final rnd = math.Random(11);
      for (var i = 0; i < 46; i++) {
        final x = rnd.nextDouble() * w;
        final y0 = rnd.nextDouble() * h;
        final speed = 20 + rnd.nextDouble() * 40;
        final y = (y0 - t * speed) % h;
        final r = 0.5 + rnd.nextDouble() * 1.1;
        final tw = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(rnd.nextDouble() * 6.28 + t * 7));
        canvas.drawCircle(Offset(x, y), r, Paint()..color = Colors.white.withValues(alpha: 0.5 * tw * appear));
      }
    }

    // Kenar gölgesi (vinyet).
    canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            radius: 1.0,
            colors: [Colors.transparent, (night ? Colors.black : NColors.ink).withValues(alpha: night ? 0.45 : 0.05)],
            stops: const [0.6, 1.0],
          ).createShader(rect));
  }

  @override
  bool shouldRepaint(_AuroraPainter o) => o.t != t || o.night != night;
}

/// Cam karo içinde logo: daireler sırayla dolar, köşedeki onaya dönüşür,
/// dalga halkaları yayılır ve karonun üzerinden ışık geçer.
class _TileMark extends CustomPainter {
  final double t;
  final _Palette p;
  final bool night;
  _TileMark(this.t, this.p, this.night);

  // N harfinin çizim sırası (sol sütun aşağı, çapraz, sağ sütun yukarı).
  static const order = [(0, 0), (0, 1), (0, 2), (0, 3), (1, 1), (2, 2), (3, 3), (3, 2), (3, 1)];

  double _seg(double a, double b, [Curve c = Curves.easeOutCubic]) => c.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size s) {
    final tile = RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(s.width * 0.26));
    final g = s.width * 0.58;
    final origin = Offset((s.width - g) / 2, (s.height - g) / 2);
    final cell = g / 4;
    final r = cell * 0.36;
    final checkC = origin + Offset(cell * 3.5, cell * 0.5);

    // Onay anında yayılan halkalar (karonun dışına taşar).
    for (var k = 0; k < 2; k++) {
      final w = _seg(0.47 + k * 0.08, 0.82 + k * 0.08);
      if (w <= 0 || w >= 1) continue;
      canvas.drawCircle(
          checkC,
          s.width * (0.08 + 0.8 * w),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = NColors.emerald.withValues(alpha: 0.5 * (1 - w)));
    }

    // Karo gölgesi ve gövdesi.
    canvas.drawRRect(
        tile.shift(const Offset(0, 16)),
        Paint()
          ..color = (night ? Colors.black : NColors.ink).withValues(alpha: night ? 0.5 : 0.12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24));
    canvas.drawRRect(
        tile,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: night ? const [Color(0xFF1B2B60), Color(0xFF0B1433)] : const [Colors.white, Color(0xFFF2F4F1)],
          ).createShader(tile.outerRect));
    canvas.drawRRect(
        tile.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [p.tileEdge, p.tileEdge.withValues(alpha: 0)],
          ).createShader(tile.outerRect));

    // Logo ızgarası
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    final ringA = _seg(0.12, 0.28);
    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 4; x++) {
        canvas.drawCircle(
            Offset(cell * (x + 0.5), cell * (y + 0.5)),
            r * 0.92,
            Paint()
              ..color = p.ring.withValues(alpha: p.ring.a * ringA)
              ..style = PaintingStyle.stroke
              ..strokeWidth = cell * 0.06);
      }
    }
    for (var i = 0; i < order.length; i++) {
      final (x, y) = order[i];
      final start = 0.20 + i * 0.026;
      final k = Curves.easeOutBack.transform(((t - start) / 0.09).clamp(0.0, 1.0));
      if (k <= 0) continue;
      canvas.drawCircle(Offset(cell * (x + 0.5), cell * (y + 0.5)), r * k, Paint()..color = p.ink);
    }
    final c = Offset(cell * 3.5, cell * 0.5);
    final gk = Curves.elasticOut.transform(((t - 0.44) / 0.24).clamp(0.0, 1.0));
    if (gk > 0) {
      canvas.drawCircle(
          c,
          r * 1.9,
          Paint()
            ..color = NColors.emerald.withValues(alpha: 0.35 * _seg(0.44, 0.55) * (1 - 0.6 * _seg(0.6, 0.9)))
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      canvas.drawCircle(c, r * gk, Paint()..color = NColors.emerald);
      final pr = ((t - 0.49) / 0.12).clamp(0.0, 1.0);
      if (pr > 0) {
        final path = Path()
          ..moveTo(c.dx - r * 0.45, c.dy + r * 0.02)
          ..lineTo(c.dx - r * 0.1, c.dy + r * 0.38)
          ..lineTo(c.dx + r * 0.5, c.dy - r * 0.32);
        final m = path.computeMetrics().first;
        canvas.drawPath(
            m.extractPath(0, m.length * pr),
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = r * 0.26
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round);
      }
    }
    canvas.restore();

    // Karonun üzerinden geçen ışık şeridi.
    final sw = _seg(0.58, 0.82, Curves.easeInOutCubic);
    if (sw > 0 && sw < 1) {
      canvas.save();
      canvas.clipRRect(tile);
      canvas.translate(-s.width * 0.7 + sw * s.width * 2.2, 0);
      canvas.skew(-0.45, 0);
      final band = Rect.fromLTWH(0, -s.height * 0.2, s.width * 0.32, s.height * 1.4);
      canvas.drawRect(
          band,
          Paint()
            ..shader = LinearGradient(colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: night ? 0.22 : 0.7),
              Colors.white.withValues(alpha: 0),
            ]).createShader(band));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_TileMark o) => o.t != t || o.night != night;
}
