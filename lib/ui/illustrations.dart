import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// Uygulamanın kendi çizimleri (vektör, her boyutta net). Boş ekranlarda,
/// tanıtımda ve yardımda kullanılır; tek renk ailesi: lacivert, zümrüt,
/// kehribar ve kâğıt beyazı.
enum IllustrationKind { welcome, school, students, exams, scan, results, guide, backup, term, empty }

class Illustration extends StatelessWidget {
  final IllustrationKind kind;
  final double size;

  /// Koyu zemin üzerinde mi (tanıtım ekranı, kahraman paneller)?
  final bool onDark;

  const Illustration({super.key, required this.kind, this.size = 160, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final dark = onDark || Theme.of(context).brightness == Brightness.dark;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _IllustrationPainter(kind, dark)),
    );
  }
}

/// Küçük, yuvarlatılmış kare içinde çizim (liste başlıkları, kartlar).
class IllustrationBadge extends StatelessWidget {
  final IllustrationKind kind;
  final double size;
  const IllustrationBadge({super.key, required this.kind, this.size = 64});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(size * 0.3),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Illustration(kind: kind, size: size, onDark: true),
      );
}

/// Boş durum: çizim, başlık, açıklama ve isteğe bağlı eylem.
class EmptyState extends StatelessWidget {
  final IllustrationKind kind;
  final String title;
  final String message;
  final Widget? action;
  final double size;
  const EmptyState(
      {super.key, required this.kind, required this.title, required this.message, this.action, this.size = 150});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Illustration(kind: kind, size: size),
        const SizedBox(height: 14),
        Text(title,
            textAlign: TextAlign.center,
            style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2)),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: t.colorScheme.onSurface.withValues(alpha: 0.62), height: 1.45)),
        ),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ]),
    );
  }
}

class _IllustrationPainter extends CustomPainter {
  final IllustrationKind kind;
  final bool dark;
  _IllustrationPainter(this.kind, this.dark);

  // Renkler
  static const _paper = Color(0xFFFFFFFF);
  static const _paperShade = Color(0xFFEDE9DF);
  Color get _ink => dark ? const Color(0xFFDCE3F5) : NColors.ink;
  Color get _inkSoft => dark ? const Color(0xFF3A4A7D) : const Color(0xFFCBD2E3);
  /// Büyük koyu gövdeler: koyu zeminde kaybolmasın diye biraz açılır.
  Color get _deep => dark ? const Color(0xFF2E4185) : NColors.ink;
  Color get _blob => NColors.emerald.withValues(alpha: dark ? 0.16 : 0.12);

  late Canvas _c;
  late double _u;

  Offset _p(double x, double y) => Offset(x * _u, y * _u);
  Rect _r(double x, double y, double w, double h) => Rect.fromLTWH(x * _u, y * _u, w * _u, h * _u);
  RRect _rr(double x, double y, double w, double h, double r) =>
      RRect.fromRectAndRadius(_r(x, y, w, h), Radius.circular(r * _u));
  Paint _fill(Color c) => Paint()..color = c;
  Paint _stroke(Color c, double w) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w * _u
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  void _shadow(RRect r, {double blur = 6, double dy = 3}) {
    _c.drawRRect(
      r.shift(Offset(0, dy * _u)),
      Paint()
        ..color = NColors.ink.withValues(alpha: dark ? 0.45 : 0.14)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur * _u * 0.5),
    );
  }

  void _check(Offset c, double r, {Color bg = NColors.emerald, Color fg = Colors.white}) {
    _c.drawCircle(c, r, _fill(bg));
    _c.drawPath(
      Path()
        ..moveTo(c.dx - r * 0.45, c.dy + r * 0.02)
        ..lineTo(c.dx - r * 0.1, c.dy + r * 0.38)
        ..lineTo(c.dx + r * 0.5, c.dy - r * 0.32),
      Paint()
        ..color = fg
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.28
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _sparkle(double x, double y, double s, Color c) {
    final o = _p(x, y);
    final r = s * _u;
    final path = Path()
      ..moveTo(o.dx, o.dy - r)
      ..quadraticBezierTo(o.dx, o.dy, o.dx + r, o.dy)
      ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy + r)
      ..quadraticBezierTo(o.dx, o.dy, o.dx - r, o.dy)
      ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy - r);
    _c.drawPath(path, _fill(c));
  }

  void _background() {
    _c.drawCircle(_p(50, 52), 40 * _u, _fill(_blob));
    _c.drawCircle(_p(84, 20), 3 * _u, _fill(NColors.amber.withValues(alpha: 0.8)));
    _c.drawCircle(_p(13, 74), 2.2 * _u, _fill(NColors.emerald.withValues(alpha: 0.7)));
    _sparkle(18, 22, 4, NColors.emerald);
    _sparkle(88, 70, 3, _ink.withValues(alpha: 0.5));
  }

  /// Optik kâğıt: [x,y] sol üst, satır sayısı kadar 4 şıklı daire.
  void _sheet(double x, double y, double w, double h, {int rows = 5, double angle = 0, List<int>? marks}) {
    _c.save();
    final center = _p(x + w / 2, y + h / 2);
    _c.translate(center.dx, center.dy);
    _c.rotate(angle);
    _c.translate(-center.dx, -center.dy);
    final rr = _rr(x, y, w, h, 3);
    _shadow(rr);
    _c.drawRRect(rr, _fill(_paper));
    // köşe işaretleri
    final m = w * 0.07;
    for (final o in [_p(x + 3, y + 3), _p(x + w - 3 - m, y + 3), _p(x + 3, y + h - 3 - m), _p(x + w - 3 - m, y + h - 3 - m)]) {
      _c.drawRect(Rect.fromLTWH(o.dx, o.dy, m * _u, m * _u), _fill(NColors.ink));
    }
    // başlık çizgileri
    _c.drawRRect(_rr(x + w * 0.22, y + 4, w * 0.5, 2.2, 1.1), _fill(NColors.ink.withValues(alpha: 0.85)));
    _c.drawRRect(_rr(x + w * 0.22, y + 8, w * 0.32, 1.6, 0.8), _fill(_paperShade));
    // daireler
    final top = y + h * 0.3;
    final pitch = (h * 0.62) / rows;
    final br = math.min(pitch * 0.32, w * 0.06);
    for (var r = 0; r < rows; r++) {
      final cy = top + pitch * (r + 0.5);
      _c.drawRRect(_rr(x + w * 0.12, cy - 0.8, w * 0.08, 1.6, 0.8), _fill(_paperShade));
      for (var k = 0; k < 4; k++) {
        final cx = x + w * (0.34 + k * 0.17);
        final filled = (marks ?? const [1, 3, 0, 2, 1, 0, 3, 2])[r % 8] == k;
        if (filled) {
          _c.drawCircle(_p(cx, cy), br * _u, _fill(r == 2 ? NColors.emerald : NColors.ink));
        } else {
          _c.drawCircle(_p(cx, cy), br * _u * 0.92, _stroke(const Color(0xFFB9B3A6), 0.5));
        }
      }
    }
    _c.restore();
  }

  void _person(double cx, double cy, double s, Color body, Color head) {
    _c.drawCircle(_p(cx, cy - s * 0.55), s * 0.32 * _u, _fill(head));
    final shoulders = Path()
      ..moveTo((cx - s * 0.62) * _u, (cy + s * 0.55) * _u)
      ..quadraticBezierTo((cx - s * 0.6) * _u, (cy - s * 0.08) * _u, cx * _u, (cy - s * 0.1) * _u)
      ..quadraticBezierTo((cx + s * 0.6) * _u, (cy - s * 0.08) * _u, (cx + s * 0.62) * _u, (cy + s * 0.55) * _u)
      ..close();
    _c.drawPath(shoulders, _fill(body));
  }

  void _pencil(double x, double y, double len, double angle) {
    _c.save();
    _c.translate(x * _u, y * _u);
    _c.rotate(angle);
    final w = 4.2;
    _c.drawRRect(_rr(0, -w / 2, len * 0.78, w, 0.8), _fill(NColors.amber));
    _c.drawRect(_r(0, -w / 2, len * 0.12, w), _fill(const Color(0xFFE8613C)));
    _c.drawRect(_r(len * 0.12, -w / 2, len * 0.05, w), _fill(const Color(0xFFB9B3A6)));
    final tip = Path()
      ..moveTo(len * 0.78 * _u, -w / 2 * _u)
      ..lineTo(len * _u, 0)
      ..lineTo(len * 0.78 * _u, w / 2 * _u)
      ..close();
    _c.drawPath(tip, _fill(const Color(0xFFF3D9A4)));
    _c.drawCircle(Offset(len * 0.97 * _u, 0), 0.9 * _u, _fill(NColors.ink));
    _c.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    _c = canvas;
    _u = size.width / 100;
    _background();
    switch (kind) {
      case IllustrationKind.welcome:
        _sheet(18, 22, 40, 54, angle: -0.12);
        // telefon
        final phone = _rr(50, 26, 32, 54, 6);
        _shadow(phone, blur: 10, dy: 4);
        _c.drawRRect(phone, _fill(_deep));
        _c.drawRRect(_rr(53, 32, 26, 42, 3), _fill(const Color(0xFF1E2E60)));
        _c.drawRRect(_rr(62, 28.4, 8, 1.6, 0.8), _fill(Colors.white24));
        // ekranda skor halkası
        _c.drawCircle(_p(66, 48), 8 * _u, _stroke(Colors.white24, 2.4));
        _c.drawArc(Rect.fromCircle(center: _p(66, 48), radius: 8 * _u), -math.pi / 2, math.pi * 1.6, false,
            _stroke(NColors.emerald, 2.4));
        _c.drawRRect(_rr(58, 62, 16, 2, 1), _fill(Colors.white38));
        _c.drawRRect(_rr(60, 66, 12, 2, 1), _fill(Colors.white24));
        _check(_p(80, 28), 6 * _u);
        _sparkle(46, 18, 3.4, NColors.amber);
      case IllustrationKind.school:
        // okul binası
        final base = _rr(20, 42, 60, 36, 3);
        _shadow(base);
        _c.drawRRect(base, _fill(_paper));
        final roof = Path()
          ..moveTo(16 * _u, 44 * _u)
          ..lineTo(50 * _u, 24 * _u)
          ..lineTo(84 * _u, 44 * _u)
          ..close();
        _c.drawPath(roof, _fill(_deep));
        _c.drawCircle(_p(50, 36), 4.2 * _u, _fill(NColors.emerald));
        for (final x in [27.0, 39.0, 57.0, 69.0]) {
          _c.drawRRect(_rr(x, 50, 6, 8, 1), _fill(_inkSoft));
        }
        _c.drawRRect(_rr(45, 60, 10, 18, 1.5), _fill(NColors.ink));
        _c.drawRRect(_rr(16, 77, 68, 3, 1.5), _fill(_paperShade));
        // bayrak
        _c.drawLine(_p(50, 24), _p(50, 12), _stroke(_ink, 1));
        _c.drawRRect(_rr(50, 12, 10, 6, 1), _fill(const Color(0xFFE8613C)));
      case IllustrationKind.students:
        _person(30, 56, 20, _inkSoft, _ink.withValues(alpha: 0.75));
        _person(70, 56, 20, NColors.amber.withValues(alpha: 0.9), _ink.withValues(alpha: 0.75));
        _person(50, 60, 26, _deep, _deep);
        _c.drawCircle(_p(50, 46), 26 * 0.32 * _u, _fill(dark ? const Color(0xFF3A50A0) : const Color(0xFF1E2E60)));
        _check(_p(64, 44), 5.5 * _u);
        // tablo kartı
        final card = _rr(24, 74, 52, 12, 3);
        _shadow(card, blur: 4, dy: 2);
        _c.drawRRect(card, _fill(_paper));
        _c.drawRRect(_rr(28, 78, 10, 2, 1), _fill(NColors.ink));
        _c.drawRRect(_rr(41, 78, 22, 2, 1), _fill(_paperShade));
        _c.drawRRect(_rr(28, 82, 8, 1.6, 0.8), _fill(_paperShade));
        _c.drawRRect(_rr(41, 82, 28, 1.6, 0.8), _fill(_paperShade));
      case IllustrationKind.exams:
        _sheet(24, 16, 44, 62, rows: 6);
        _sheet(34, 22, 44, 62, rows: 6, marks: const [2, 0, 1, 3, 2, 1]);
        _pencil(14, 84, 40, -0.62);
      case IllustrationKind.scan:
        _sheet(26, 20, 48, 64, rows: 6);
        // tarama çerçevesi
        final g = _stroke(NColors.emerald, 2.4);
        const L = 9.0;
        for (final (x, y, dx, dy) in [(20.0, 14.0, 1.0, 1.0), (80.0, 14.0, -1.0, 1.0), (20.0, 90.0, 1.0, -1.0), (80.0, 90.0, -1.0, -1.0)]) {
          _c.drawLine(_p(x, y), _p(x + L * dx, y), g);
          _c.drawLine(_p(x, y), _p(x, y + L * dy), g);
        }
        final line = _r(22, 52, 56, 1.4);
        _c.drawRect(
          line.inflate(3 * _u),
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [NColors.emerald.withValues(alpha: 0), NColors.emerald.withValues(alpha: 0.35), NColors.emerald.withValues(alpha: 0)],
            ).createShader(line.inflate(3 * _u)),
        );
        _c.drawRect(line, _fill(NColors.emerald));
        _check(_p(78, 20), 6.5 * _u);
      case IllustrationKind.results:
        final card = _rr(16, 24, 68, 56, 6);
        _shadow(card, blur: 10, dy: 4);
        _c.drawRRect(card, _fill(_paper));
        final hs = [16.0, 26.0, 20.0, 34.0, 40.0];
        for (var i = 0; i < hs.length; i++) {
          final x = 24 + i * 9.5;
          _c.drawRRect(_rr(x, 72 - hs[i], 6, hs[i], 1.6), _fill(i == hs.length - 1 ? NColors.emerald : (i.isEven ? NColors.ink : _inkSoft)));
        }
        _c.drawRRect(_rr(22, 73, 56, 1, 0.5), _fill(_paperShade));
        // trend
        final trend = Path()
          ..moveTo(26 * _u, 50 * _u)
          ..cubicTo(36 * _u, 46 * _u, 46 * _u, 44 * _u, 52 * _u, 38 * _u)
          ..cubicTo(60 * _u, 32 * _u, 66 * _u, 30 * _u, 74 * _u, 28 * _u);
        _c.drawPath(trend, _stroke(NColors.amber, 1.6));
        _c.drawCircle(_p(74, 28), 2.4 * _u, _fill(NColors.amber));
        // halka
        _c.drawCircle(_p(80, 22), 10 * _u, _fill(_deep));
        _c.drawArc(Rect.fromCircle(center: _p(80, 22), radius: 6.5 * _u), -math.pi / 2, math.pi * 1.5, false,
            _stroke(NColors.emerald, 2.4));
      case IllustrationKind.guide:
        // açık kitap
        final left = Path()
          ..moveTo(50 * _u, 32 * _u)
          ..quadraticBezierTo(36 * _u, 24 * _u, 18 * _u, 28 * _u)
          ..lineTo(18 * _u, 74 * _u)
          ..quadraticBezierTo(36 * _u, 70 * _u, 50 * _u, 78 * _u)
          ..close();
        final right = Path()
          ..moveTo(50 * _u, 32 * _u)
          ..quadraticBezierTo(64 * _u, 24 * _u, 82 * _u, 28 * _u)
          ..lineTo(82 * _u, 74 * _u)
          ..quadraticBezierTo(64 * _u, 70 * _u, 50 * _u, 78 * _u)
          ..close();
        _c.drawPath(left.shift(Offset(0, 3 * _u)), Paint()
          ..color = NColors.ink.withValues(alpha: dark ? 0.4 : 0.12)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * _u));
        _c.drawPath(right.shift(Offset(0, 3 * _u)), Paint()
          ..color = NColors.ink.withValues(alpha: dark ? 0.4 : 0.12)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * _u));
        _c.drawPath(left, _fill(_paper));
        _c.drawPath(right, _fill(const Color(0xFFFBF9F4)));
        _c.drawLine(_p(50, 32), _p(50, 78), _stroke(_paperShade, 1));
        for (var i = 0; i < 5; i++) {
          _c.drawRRect(_rr(23, 38 + i * 6.5, i == 0 ? 14 : 22, 1.8, 0.9), _fill(i == 0 ? NColors.ink : _paperShade));
        }
        for (var i = 0; i < 3; i++) {
          _c.drawCircle(_p(58, 40 + i * 9), 2.2 * _u, i == 1 ? _fill(NColors.emerald) : _stroke(const Color(0xFFB9B3A6), 0.6));
          _c.drawRRect(_rr(63, 39.2 + i * 9, 14, 1.6, 0.8), _fill(_paperShade));
        }
        // soru balonu
        final bubble = _rr(62, 12, 24, 16, 6);
        _c.drawRRect(bubble, _fill(NColors.emerald));
        final tail = Path()
          ..moveTo(66 * _u, 27 * _u)
          ..lineTo(64 * _u, 33 * _u)
          ..lineTo(71 * _u, 27 * _u)
          ..close();
        _c.drawPath(tail, _fill(NColors.emerald));
        final tp = TextPainter(
          text: TextSpan(text: '?', style: TextStyle(fontFamily: 'PlusJakartaSans', color: Colors.white, fontSize: 12 * _u, fontWeight: FontWeight.w800)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(_c, _p(74, 20) - Offset(tp.width / 2, tp.height / 2));
      case IllustrationKind.backup:
        // kalkan
        final shield = Path()
          ..moveTo(50 * _u, 16 * _u)
          ..lineTo(76 * _u, 26 * _u)
          ..quadraticBezierTo(76 * _u, 62 * _u, 50 * _u, 84 * _u)
          ..quadraticBezierTo(24 * _u, 62 * _u, 24 * _u, 26 * _u)
          ..close();
        _c.drawPath(shield.shift(Offset(0, 3 * _u)), Paint()
          ..color = NColors.ink.withValues(alpha: dark ? 0.45 : 0.16)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * _u));
        _c.drawPath(shield, _fill(_deep));
        final inner = Path()
          ..moveTo(50 * _u, 23 * _u)
          ..lineTo(69 * _u, 30.5 * _u)
          ..quadraticBezierTo(69 * _u, 58 * _u, 50 * _u, 75 * _u)
          ..quadraticBezierTo(31 * _u, 58 * _u, 31 * _u, 30.5 * _u)
          ..close();
        _c.drawPath(inner, _fill(dark ? const Color(0xFF3A50A0) : const Color(0xFF1E2E60)));
        _check(_p(50, 48), 11 * _u);
        // dönen ok
        _c.drawArc(Rect.fromCircle(center: _p(50, 50), radius: 36 * _u), -2.6, 1.2, false, _stroke(NColors.amber, 2));
        _c.drawCircle(_p(50 + 36 * math.cos(-1.4), 50 + 36 * math.sin(-1.4)), 2.2 * _u, _fill(NColors.amber));
      case IllustrationKind.term:
        final cal = _rr(20, 22, 54, 56, 6);
        _shadow(cal, blur: 10, dy: 4);
        _c.drawRRect(cal, _fill(_paper));
        _c.drawRRect(_rr(20, 22, 54, 14, 6), _fill(_deep));
        _c.drawRect(_r(20, 30, 54, 6), _fill(_deep));
        for (final x in [31.0, 63.0]) {
          _c.drawRRect(_rr(x, 17, 3, 9, 1.5), _fill(_ink));
        }
        for (var r = 0; r < 3; r++) {
          for (var k = 0; k < 5; k++) {
            final on = (r * 5 + k) % 4 == 1;
            _c.drawRRect(_rr(25 + k * 9.4, 41 + r * 11, 6.5, 7, 1.5),
                _fill(on ? NColors.emerald.withValues(alpha: 0.85) : _paperShade));
          }
        }
        // madalya
        _c.drawPath(
            Path()
              ..moveTo(70 * _u, 62 * _u)
              ..lineTo(66 * _u, 84 * _u)
              ..lineTo(72 * _u, 80 * _u)
              ..lineTo(76 * _u, 86 * _u)
              ..lineTo(78 * _u, 64 * _u)
              ..close(),
            _fill(const Color(0xFFE8613C)));
        _c.drawCircle(_p(74, 62), 11 * _u, _fill(NColors.amber));
        _c.drawCircle(_p(74, 62), 7.5 * _u, _stroke(Colors.white, 1.2));
        _sparkle(74, 62, 4, Colors.white);
      case IllustrationKind.empty:
        final box = _rr(26, 40, 48, 36, 5);
        _shadow(box);
        _c.drawRRect(box, _fill(_paper));
        _c.drawRRect(_rr(26, 40, 48, 10, 5), _fill(_paperShade));
        _c.drawRRect(_rr(42, 56, 16, 3, 1.5), _fill(_inkSoft));
        _sheet(36, 18, 28, 30, rows: 3);
    }
  }

  @override
  bool shouldRepaint(_IllustrationPainter old) => old.kind != kind || old.dark != dark;
}
