import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// Konsept A, "Optik N": 4×4 optik daireden dolu olanlar N harfini çizer,
/// köşedeki son daire onay işaretine dönüşür.
class NeticeMark extends StatelessWidget {
  final double size;
  final Color? ink;

  /// Küçük boyutlarda boş daireler kaldırılır.
  final bool showEmpty;

  /// Filigran için yalnızca çizgilerle (halka) çizer.
  final bool outline;

  const NeticeMark({super.key, this.size = 40, this.ink, this.showEmpty = true, this.outline = false});

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _MarkPainter(
            ink: ink ?? Theme.of(context).colorScheme.onSurface,
            showEmpty: showEmpty && size >= 32,
            outline: outline,
          ),
        ),
      );
}

class _MarkPainter extends CustomPainter {
  final Color ink;
  final bool showEmpty;
  final bool outline;
  _MarkPainter({required this.ink, required this.showEmpty, this.outline = false});

  // 1 = dolu, 0 = boş, 2 = onay.
  static const grid = [
    [1, 0, 0, 2],
    [1, 1, 0, 1],
    [1, 0, 1, 1],
    [1, 0, 0, 1],
  ];

  void _paintOutline(Canvas canvas, Size s) {
    final cell = s.width / 4;
    final r = cell * 0.36;
    final ring = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell * 0.06;
    final dot = Paint()..color = ink;
    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 4; x++) {
        final c = Offset(cell * (x + 0.5), cell * (y + 0.5));
        switch (grid[y][x]) {
          case 1:
            canvas.drawCircle(c, r, ring);
            canvas.drawCircle(c, r * 0.55, dot);
          case 0:
            canvas.drawCircle(c, r * 0.12, dot);
          case 2:
            canvas.drawCircle(c, r, ring);
            canvas.drawPath(
              Path()
                ..moveTo(c.dx - r * 0.45, c.dy + r * 0.02)
                ..lineTo(c.dx - r * 0.1, c.dy + r * 0.38)
                ..lineTo(c.dx + r * 0.5, c.dy - r * 0.32),
              Paint()
                ..color = ink
                ..style = PaintingStyle.stroke
                ..strokeWidth = cell * 0.08
                ..strokeCap = StrokeCap.round
                ..strokeJoin = StrokeJoin.round,
            );
        }
      }
    }
  }

  @override
  void paint(Canvas canvas, Size s) {
    if (outline) return _paintOutline(canvas, s);
    final cell = s.width / 4;
    final r = cell * 0.36;
    final fill = Paint()..color = ink;
    final empty = Paint()
      ..color = ink.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell * 0.07;
    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 4; x++) {
        final c = Offset(cell * (x + 0.5), cell * (y + 0.5));
        switch (grid[y][x]) {
          case 1:
            canvas.drawCircle(c, r, fill);
          case 0:
            if (showEmpty) canvas.drawCircle(c, r * 0.92, empty);
          case 2:
            canvas.drawCircle(c, r, Paint()..color = NColors.emerald);
            final check = Path()
              ..moveTo(c.dx - r * 0.45, c.dy + r * 0.02)
              ..lineTo(c.dx - r * 0.1, c.dy + r * 0.38)
              ..lineTo(c.dx + r * 0.5, c.dy - r * 0.32);
            canvas.drawPath(
              check,
              Paint()
                ..color = Colors.white
                ..style = PaintingStyle.stroke
                ..strokeWidth = r * 0.26
                ..strokeCap = StrokeCap.round
                ..strokeJoin = StrokeJoin.round,
            );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.ink != ink || old.showEmpty != showEmpty || old.outline != outline;
}

/// Logo + "Netice" kelimesi.
class NeticeWordmark extends StatelessWidget {
  final double height;
  const NeticeWordmark({super.key, this.height = 28});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          NeticeMark(size: height, showEmpty: false),
          SizedBox(width: height * 0.35),
          Text('Netice',
              style: TextStyle(
                fontSize: height * 0.85,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: Theme.of(context).colorScheme.onSurface,
              )),
        ],
      );
}
