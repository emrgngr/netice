// İsim/logo fikirleri önizlemesi: flutter test tool/name_ideas_test.dart
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/ui/logo.dart';
import 'package:netice/ui/theme.dart';

import 'screenshots_test.dart' show loadFonts, shot;

typedef Painter = void Function(Canvas c, double s, Color ink, bool onDark);

Paint _f(Color c) => Paint()..color = c;
Paint _st(Color c, double w) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

void _check(Canvas c, Offset o, double r, Color fg, {double w = 0.28}) => c.drawPath(
    Path()
      ..moveTo(o.dx - r * 0.45, o.dy + r * 0.02)
      ..lineTo(o.dx - r * 0.1, o.dy + r * 0.38)
      ..lineTo(o.dx + r * 0.5, o.dy - r * 0.32),
    _st(fg, r * w));

// 1. NetOku: dairelerden N + tarama köşeleri
void netoku(Canvas c, double s, Color ink, bool d) {
  final cell = s * 0.62 / 4, o = s * 0.19, r = cell * 0.36;
  const g = [
    [1, 0, 0, 1],
    [1, 1, 0, 1],
    [1, 0, 1, 1],
    [1, 0, 0, 2],
  ];
  for (var y = 0; y < 4; y++) {
    for (var x = 0; x < 4; x++) {
      final p = Offset(o + cell * (x + 0.5), o + cell * (y + 0.5));
      if (g[y][x] == 1) c.drawCircle(p, r, _f(ink));
      if (g[y][x] == 2) c.drawCircle(p, r, _f(NColors.emerald));
      if (g[y][x] == 0) c.drawCircle(p, r * 0.9, _st(ink.withValues(alpha: 0.25), cell * 0.06));
    }
  }
  final L = s * 0.16, w = s * 0.045, m = s * 0.06;
  final p = _st(NColors.emerald, w);
  for (final (x, y, dx, dy) in [(m, m, 1.0, 1.0), (s - m, m, -1.0, 1.0), (m, s - m, 1.0, -1.0), (s - m, s - m, -1.0, -1.0)]) {
    c.drawLine(Offset(x, y), Offset(x + L * dx, y), p);
    c.drawLine(Offset(x, y), Offset(x, y + L * dy), p);
  }
}

// 2. Okutan: vizör + göz bebeği daire + onay
void okutan(Canvas c, double s, Color ink, bool d) {
  final L = s * 0.24, w = s * 0.07, m = s * 0.08;
  final p = _st(ink, w);
  for (final (x, y, dx, dy) in [(m, m, 1.0, 1.0), (s - m, m, -1.0, 1.0), (m, s - m, 1.0, -1.0), (s - m, s - m, -1.0, -1.0)]) {
    c.drawPath(
        Path()
          ..moveTo(x, y + L * dy)
          ..lineTo(x, y + s * 0.06 * dy)
          ..quadraticBezierTo(x, y, x + s * 0.06 * dx, y)
          ..lineTo(x + L * dx, y),
        p);
  }
  final ctr = Offset(s / 2, s / 2);
  c.drawCircle(ctr, s * 0.25, _st(ink.withValues(alpha: 0.25), s * 0.03));
  c.drawCircle(ctr, s * 0.18, _f(NColors.emerald));
  _check(c, ctr, s * 0.18, Colors.white);
}

// 3. Mühür: yuvarlak mühür, kenarda optik daireler
void muhur(Canvas c, double s, Color ink, bool d) {
  final ctr = Offset(s / 2, s / 2);
  c.drawCircle(ctr, s * 0.46, _st(ink, s * 0.045));
  c.drawCircle(ctr, s * 0.30, _st(ink, s * 0.02));
  const n = 16;
  for (var i = 0; i < n; i++) {
    final a = -math.pi / 2 + i * 2 * math.pi / n;
    final p = ctr + Offset(math.cos(a), math.sin(a)) * s * 0.38;
    final filled = i % 4 == 0 || i == 6 || i == 11;
    if (filled) {
      c.drawCircle(p, s * 0.034, _f(i == 0 ? NColors.emerald : ink));
    } else {
      c.drawCircle(p, s * 0.03, _st(ink.withValues(alpha: 0.4), s * 0.012));
    }
  }
  c.drawCircle(ctr, s * 0.2, _f(ink));
  _check(c, ctr, s * 0.2, NColors.emerald, w: 0.3);
}

// 4. Kazanım: yükselen üç daire
void kazanim(Canvas c, double s, Color ink, bool d) {
  final r = s * 0.13;
  final pts = [Offset(s * 0.22, s * 0.74), Offset(s * 0.5, s * 0.52), Offset(s * 0.78, s * 0.28)];
  c.drawPath(
      Path()
        ..moveTo(pts[0].dx, pts[0].dy)
        ..lineTo(pts[1].dx, pts[1].dy)
        ..lineTo(pts[2].dx, pts[2].dy),
      _st(ink.withValues(alpha: 0.25), s * 0.05));
  c.drawCircle(pts[0], r, _f(ink.withValues(alpha: 0.45)));
  c.drawCircle(pts[1], r, _f(ink));
  c.drawCircle(pts[2], r * 1.15, _f(NColors.emerald));
  _check(c, pts[2], r * 1.15, Colors.white);
  c.drawLine(Offset(s * 0.1, s * 0.9), Offset(s * 0.9, s * 0.9), _st(ink.withValues(alpha: 0.25), s * 0.03));
}

// 5. Tik: karartılmış daireden çıkan kalın onay
void tik(Canvas c, double s, Color ink, bool d) {
  final ctr = Offset(s * 0.4, s * 0.58);
  final rnd = math.Random(3);
  for (var i = 0; i < 70; i++) {
    final a = rnd.nextDouble() * math.pi * 2, rr = rnd.nextDouble() * s * 0.26;
    final p = ctr + Offset(math.cos(a), math.sin(a)) * rr;
    c.drawLine(p, p + Offset(s * 0.06, -s * 0.03), _st(ink.withValues(alpha: 0.55), s * 0.025));
  }
  c.drawCircle(ctr, s * 0.3, _st(ink, s * 0.035));
  c.drawPath(
      Path()
        ..moveTo(s * 0.22, s * 0.56)
        ..lineTo(s * 0.4, s * 0.74)
        ..lineTo(s * 0.88, s * 0.18),
      _st(NColors.emerald, s * 0.12));
}

class _P extends CustomPainter {
  final Painter p;
  final Color ink;
  final bool dark;
  _P(this.p, this.ink, this.dark);
  @override
  void paint(Canvas c, Size s) => p(c, s.width, ink, dark);
  @override
  bool shouldRepaint(covariant CustomPainter o) => false;
}

Widget mark(Painter? p, double size, Color ink, bool dark) => p == null
    ? NeticeMark(size: size, ink: ink)
    : SizedBox.square(dimension: size, child: CustomPaint(painter: _P(p, ink, dark)));

Widget card(int no, String name, String note, Painter? p) {
  const font = 'PlusJakartaSans';
  return Container(
    width: 560,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [
      BoxShadow(color: NColors.ink.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8)),
    ]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: NColors.emerald.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
          child: Text(no == 0 ? 'MEVCUT' : 'FİKİR $no',
              style: const TextStyle(fontFamily: font, fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF047857))),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(note, style: const TextStyle(fontFamily: font, fontSize: 13, color: Color(0xFF6B7280)))),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        // Uygulama simgesi
        Container(
          width: 128,
          height: 128,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(gradient: inkGradient, borderRadius: BorderRadius.circular(30), boxShadow: [
            BoxShadow(color: NColors.ink.withValues(alpha: 0.3), blurRadius: 14, offset: const Offset(0, 6)),
          ]),
          child: mark(p, 84, Colors.white, true),
        ),
        const SizedBox(width: 20),
        // Açık zemin yazılı logo
        Expanded(
          child: Container(
            height: 128,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(color: NColors.ivory, borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              mark(p, 60, NColors.ink, false),
              const SizedBox(width: 14),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(name,
                      style: const TextStyle(
                          fontFamily: font, fontSize: 44, fontWeight: FontWeight.w800, letterSpacing: -1.2, color: NColors.ink)),
                ),
              ),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: 14),
      // Koyu zemin + küçük boy
      Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(color: NColors.ink, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          mark(p, 34, Colors.white, true),
          const SizedBox(width: 10),
          Text(name, style: const TextStyle(fontFamily: font, fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
          const Spacer(),
          mark(p, 22, Colors.white, true),
          const SizedBox(width: 10),
          mark(p, 16, Colors.white, true),
          const SizedBox(width: 6),
          const Text('küçük boy', style: TextStyle(fontFamily: font, fontSize: 12, color: Colors.white54)),
        ]),
      ),
    ]),
  );
}

void main() {
  testWidgets('isim ve logo fikirleri', (tester) async {
    debugDisableShadows = false;
    await tester.runAsync(loadFonts);
    final page = MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFEFEBE2),
        body: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Uygulama adı ve logo fikirleri',
                style: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 30, fontWeight: FontWeight.w800, color: NColors.ink)),
            const SizedBox(height: 4),
            const Text('Her kartta: uygulama simgesi · açık zeminde logo · koyu zeminde ve küçük boyda görünüm',
                style: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 15, color: Color(0xFF6B7280))),
            const SizedBox(height: 22),
            Wrap(spacing: 24, runSpacing: 24, children: [
              card(0, 'Netice', 'Optik daireler N harfini çizer, köşede onay', null),
              card(1, 'NetOku', 'Dairelerden N + kamera tarama köşeleri', netoku),
              card(2, 'Okutan', 'Kamera vizörü, ortada işaretli daire', okutan),
              card(3, 'Mühür', 'Resmi mühür, kenarında optik daireler', muhur),
              card(4, 'Kazanım', 'Yükselen üç daire: öğrencinin gelişimi', kazanim),
              card(5, 'Tik', 'Karartılmış daireden çıkan onay işareti', tik),
            ]),
          ]),
        ),
      ),
    );
    await shot(tester, page, const Size(1800, 830), 'isim_logo_fikirleri');
    debugDisableShadows = true;
  });
}
