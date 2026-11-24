import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'theme.dart';
import '../l10n/l10n.dart';

/// Pasta / halka grafik dilimi.
class Slice {
  final String label;
  final double value;
  final Color color;
  final String? detail;
  const Slice(this.label, this.value, this.color, {this.detail});
}

/// Dokunmatik halka (donut) veya pasta grafik: dilime dokununca öne çıkar,
/// ortada o dilimin sayısı ve yüzdesi görünür; yanında açıklama listesi.
class DonutChart extends StatefulWidget {
  final List<Slice> slices;
  final String centerLabel;
  final String? unit;
  final bool pie;
  final double size;
  const DonutChart(
      {super.key, required this.slices, required this.centerLabel, this.unit, this.pie = false, this.size = 170});

  @override
  State<DonutChart> createState() => _DonutChartState();
}

class _DonutChartState extends State<DonutChart> with SingleTickerProviderStateMixin {
  int? _sel;
  late final AnimationController _a =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  double get _total => widget.slices.fold(0.0, (a, s) => a + s.value);

  int? _hit(Offset p, Size size) {
    final c = size.center(Offset.zero);
    final v = p - c;
    final r = v.distance;
    final outer = size.shortestSide / 2;
    if (r > outer || (!widget.pie && r < outer * 0.58) || _total == 0) return null;
    var ang = math.atan2(v.dy, v.dx) + math.pi / 2;
    if (ang < 0) ang += 2 * math.pi;
    var acc = 0.0;
    for (var i = 0; i < widget.slices.length; i++) {
      acc += widget.slices[i].value / _total * 2 * math.pi;
      if (ang <= acc) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final total = _total;
    final sel = _sel;
    String pct(double v) => total == 0 ? L10n.percent(0) : L10n.percent((v / total * 100).round());
    final chart = SizedBox.square(
      dimension: widget.size,
      child: GestureDetector(
        onTapDown: (d) => setState(() {
          final h = _hit(d.localPosition, Size.square(widget.size));
          _sel = h == _sel ? null : h;
        }),
        child: AnimatedBuilder(
          animation: _a,
          builder: (_, _) => CustomPaint(
            painter: _DonutPainter(widget.slices, Curves.easeOutCubic.transform(_a.value), sel, widget.pie,
                t.colorScheme.surfaceContainerHighest),
            child: widget.pie
                ? null
                : Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                        sel == null ? '${total.round()}' : '${widget.slices[sel].value.round()}',
                        style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabular),
                      ),
                      Text(
                        sel == null ? widget.centerLabel : '${widget.slices[sel].label} · ${pct(widget.slices[sel].value)}',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: t.colorScheme.onSurface.withValues(alpha: 0.6)),
                      ),
                    ]),
                  ),
          ),
        ),
      ),
    );
    final legend = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < widget.slices.length; i++)
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _sel = _sel == i ? null : i),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: sel == null || sel == i ? 1 : 0.4,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(color: widget.slices[i].color, borderRadius: BorderRadius.circular(4))),
                const SizedBox(width: 8),
                Flexible(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: widget.slices[i].label, style: const TextStyle(fontWeight: FontWeight.w600)),
                    TextSpan(
                        text: '  ${widget.slices[i].value.round()}${widget.unit ?? ''} · ${pct(widget.slices[i].value)}',
                        style: TextStyle(color: t.colorScheme.onSurface.withValues(alpha: 0.6), fontFeatures: tabular)),
                  ])),
                ),
              ]),
            ),
          ),
        ),
      if (sel != null && widget.slices[sel].detail != null)
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text(widget.slices[sel].detail!,
              style: TextStyle(fontSize: 12, color: t.colorScheme.onSurface.withValues(alpha: 0.7))),
        ),
    ]);
    return LayoutBuilder(
      builder: (_, c) => c.maxWidth >= widget.size + 160
          ? Row(children: [chart, const SizedBox(width: 18), Expanded(child: legend)])
          : Column(children: [chart, const SizedBox(height: 12), legend]),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<Slice> slices;
  final double progress;
  final int? sel;
  final bool pie;
  final Color track;
  _DonutPainter(this.slices, this.progress, this.sel, this.pie, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold(0.0, (a, s) => a + s.value);
    final c = size.center(Offset.zero);
    final outer = size.shortestSide / 2 - 6;
    final width = pie ? outer : outer * 0.36;
    final r = pie ? outer / 2 : outer - width / 2;
    if (total == 0) {
      canvas.drawCircle(c, r, Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = width);
      return;
    }
    var start = -math.pi / 2;
    final gap = slices.where((s) => s.value > 0).length > 1 ? 0.025 : 0.0;
    for (var i = 0; i < slices.length; i++) {
      final sweep = slices[i].value / total * 2 * math.pi * progress;
      if (sweep <= 0) continue;
      final mid = start + sweep / 2;
      final pop = i == sel ? Offset(math.cos(mid), math.sin(mid)) * 6 : Offset.zero;
      final paint = Paint()
        ..color = slices[i].color.withValues(alpha: sel == null || sel == i ? 1 : 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = i == sel ? width + 4 : width;
      canvas.drawArc(Rect.fromCircle(center: c + pop, radius: r), start + gap / 2, math.max(0, sweep - gap), false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter o) => o.progress != progress || o.sel != sel;
}

/// Madde haritası: her soru bir nokta (x: güçlük p, y: ayırt edicilik d).
/// Bölgeler: sağ üst iyi soru, alt bölge gözden geçirilmeli.
class ItemMap extends StatefulWidget {
  final List<(int no, double p, double d)> items;
  const ItemMap({super.key, required this.items});
  @override
  State<ItemMap> createState() => _ItemMapState();
}

class _ItemMapState extends State<ItemMap> {
  int? _sel;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    final sel = _sel == null ? null : widget.items.where((e) => e.$1 == _sel).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AspectRatio(
        aspectRatio: 1.5,
        child: LayoutBuilder(builder: (_, c) {
          final size = Size(c.maxWidth, c.maxHeight);
          Offset pos(double p, double d) => Offset(28 + p * (size.width - 36), 8 + (1 - (d + 0.2) / 1.2) * (size.height - 30));
          return GestureDetector(
            onTapDown: (e) {
              (int, double, double)? best;
              var bd = 24.0;
              for (final it in widget.items) {
                final dd = (pos(it.$2, it.$3.clamp(-0.15, 1.0)) - e.localPosition).distance;
                if (dd < bd) {
                  bd = dd;
                  best = it;
                }
              }
              setState(() => _sel = best?.$1);
            },
            child: CustomPaint(
              size: size,
              painter: _ItemMapPainter(widget.items, pos, _sel, t.colorScheme.onSurface, t.colorScheme.outlineVariant),
            ),
          );
        }),
      ),
      const SizedBox(height: 6),
      Text(
        sel == null
            ? tr('Bir noktaya dokunun. Sağ üst: iyi soru · alt şerit (D < 0,20): gözden geçirin.')
            : tr('Soru {0}: doğru oranı %{1}, ayırt edicilik {2}{3}', [sel.$1, (sel.$2 * 100).round(), sel.$3.toStringAsFixed(2).replaceAll('.', L10n.decimal), sel.$3 < 0.2 ? tr(' · gözden geçirilmeli') : sel.$3 >= 0.4 ? tr(' · çok iyi ayırt ediyor') : '']),
        style: TextStyle(fontSize: 12, color: sel == null ? muted : null, fontWeight: sel == null ? null : FontWeight.w600),
      ),
    ]);
  }
}

class _ItemMapPainter extends CustomPainter {
  final List<(int, double, double)> items;
  final Offset Function(double, double) pos;
  final int? sel;
  final Color ink, line;
  _ItemMapPainter(this.items, this.pos, this.sel, this.ink, this.line);

  @override
  void paint(Canvas canvas, Size size) {
    // Bölgeler
    final bad = Rect.fromPoints(pos(0, 0.2), pos(1, -0.2));
    canvas.drawRect(bad, Paint()..color = NColors.coral.withValues(alpha: 0.08));
    final good = Rect.fromPoints(pos(0.3, 1), pos(0.8, 0.4));
    canvas.drawRRect(RRect.fromRectAndRadius(good, const Radius.circular(8)),
        Paint()..color = NColors.emerald.withValues(alpha: 0.10));
    final lp = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (final d in [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]) {
      canvas.drawLine(pos(0, d), pos(1, d), lp);
      _text(canvas, d.toStringAsFixed(1).replaceAll('.', L10n.decimal), pos(0, d) - const Offset(26, 6), 9);
    }
    for (final p in [0.0, 0.25, 0.5, 0.75, 1.0]) {
      _text(canvas, L10n.percent((p * 100).round()), pos(p, -0.2) + const Offset(-8, 4), 9);
    }
    for (final it in items) {
      final c = pos(it.$2, it.$3.clamp(-0.15, 1.0));
      final color = it.$3 < 0.2 ? NColors.coral : (it.$3 >= 0.4 ? NColors.emerald : NColors.ink.withValues(alpha: 0.85));
      final isSel = it.$1 == sel;
      canvas.drawCircle(c, isSel ? 11 : 8, Paint()..color = color.withValues(alpha: isSel ? 1 : 0.85));
      _text(canvas, '${it.$1}', c - Offset(it.$1 >= 10 ? 5.5 : 3, 5.5), 8.5, color: Colors.white, bold: true);
    }
  }

  void _text(Canvas c, String s, Offset o, double size, {Color? color, bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              fontSize: size,
              fontFamily: 'PlusJakartaSans',
              color: color ?? ink.withValues(alpha: 0.5),
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, o);
  }

  @override
  bool shouldRepaint(_ItemMapPainter o) => o.sel != sel || o.items != items;
}

/// Kutu grafiği: en düşük, 1. çeyrek, medyan, 3. çeyrek, en yüksek ve ortalama.
class BoxPlot extends StatelessWidget {
  final double min, q1, median, q3, max, mean, scaleMax;
  const BoxPlot(
      {super.key,
      required this.min,
      required this.q1,
      required this.median,
      required this.q3,
      required this.max,
      required this.mean,
      required this.scaleMax});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    String f(double v) => v.toStringAsFixed(1).replaceAll('.', L10n.decimal);
    return Column(children: [
      SizedBox(
        height: 64,
        child: CustomPaint(
          size: const Size(double.infinity, 64),
          painter: _BoxPainter(min / scaleMax, q1 / scaleMax, median / scaleMax, q3 / scaleMax, max / scaleMax,
              mean / scaleMax, t.colorScheme.onSurface, t.colorScheme.outlineVariant),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 14, runSpacing: 4, alignment: WrapAlignment.center, children: [
        for (final (l, v) in [(tr('En düşük'), min), (tr('1. çeyrek'), q1), (tr('Medyan'), median), (tr('3. çeyrek'), q3), (tr('En yüksek'), max)])
          Text.rich(TextSpan(children: [
            TextSpan(text: '$l ', style: TextStyle(color: t.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12)),
            TextSpan(text: f(v), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, fontFeatures: tabular)),
          ])),
        Text.rich(TextSpan(children: [
          TextSpan(text: '◆ ${tr('Ortalama')} ', style: const TextStyle(color: NColors.amber, fontSize: 12, fontWeight: FontWeight.w700)),
          TextSpan(text: f(mean), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
        ])),
      ]),
    ]);
  }
}

class _BoxPainter extends CustomPainter {
  final double mn, q1, md, q3, mx, mean;
  final Color ink, line;
  _BoxPainter(this.mn, this.q1, this.md, this.q3, this.mx, this.mean, this.ink, this.line);

  @override
  void paint(Canvas canvas, Size s) {
    double x(double v) => 8 + v.clamp(0, 1) * (s.width - 16);
    final cy = s.height / 2 - 6;
    final axis = Paint()
      ..color = line
      ..strokeWidth = 1;
    canvas.drawLine(Offset(x(0), s.height - 4), Offset(x(1), s.height - 4), axis);
    for (var i = 0; i <= 10; i++) {
      canvas.drawLine(Offset(x(i / 10), s.height - 8), Offset(x(i / 10), s.height - 2), axis);
    }
    final w = Paint()
      ..color = ink.withValues(alpha: 0.6)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(x(mn), cy), Offset(x(q1), cy), w);
    canvas.drawLine(Offset(x(q3), cy), Offset(x(mx), cy), w);
    canvas.drawLine(Offset(x(mn), cy - 8), Offset(x(mn), cy + 8), w);
    canvas.drawLine(Offset(x(mx), cy - 8), Offset(x(mx), cy + 8), w);
    final box = RRect.fromRectAndRadius(Rect.fromLTRB(x(q1), cy - 16, x(q3), cy + 16), const Radius.circular(6));
    canvas.drawRRect(box, Paint()..shader = inkGradient.createShader(box.outerRect));
    canvas.drawLine(Offset(x(md), cy - 16), Offset(x(md), cy + 16), Paint()
      ..color = NColors.emerald
      ..strokeWidth = 3);
    final m = Offset(x(mean), cy);
    canvas.drawPath(
        Path()
          ..moveTo(m.dx, m.dy - 7)
          ..lineTo(m.dx + 7, m.dy)
          ..lineTo(m.dx, m.dy + 7)
          ..lineTo(m.dx - 7, m.dy)
          ..close(),
        Paint()..color = NColors.amber);
  }

  @override
  bool shouldRepaint(_BoxPainter o) => false;
}

/// Kazanım radar grafiği (3 ve daha fazla kazanım için): sınıf ve hedef çizgisi.
class RadarChart extends StatelessWidget {
  final List<(String label, double value)> axes; // 0..1
  final double target;
  const RadarChart({super.key, required this.axes, this.target = 0.7});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AspectRatio(
      aspectRatio: 1.25,
      child: CustomPaint(painter: _RadarPainter(axes, target, t.colorScheme.onSurface, t.colorScheme.outlineVariant)),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final List<(String, double)> axes;
  final double target;
  final Color ink, line;
  _RadarPainter(this.axes, this.target, this.ink, this.line);

  @override
  void paint(Canvas canvas, Size s) {
    final n = axes.length;
    final c = s.center(Offset.zero);
    final r = math.min(s.width, s.height) / 2 - 34;
    Offset at(int i, double v) {
      final a = -math.pi / 2 + i * 2 * math.pi / n;
      return c + Offset(math.cos(a), math.sin(a)) * r * v;
    }

    final grid = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final g in [0.25, 0.5, 0.75, 1.0]) {
      canvas.drawPath(Path()..addPolygon([for (var i = 0; i < n; i++) at(i, g)], true), grid);
    }
    for (var i = 0; i < n; i++) {
      canvas.drawLine(c, at(i, 1), grid);
    }
    canvas.drawPath(
        Path()..addPolygon([for (var i = 0; i < n; i++) at(i, target)], true),
        Paint()
          ..color = NColors.amber
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    final poly = Path()..addPolygon([for (var i = 0; i < n; i++) at(i, axes[i].$2.clamp(0, 1))], true);
    canvas.drawPath(poly, Paint()..color = NColors.emerald.withValues(alpha: 0.25));
    canvas.drawPath(
        poly,
        Paint()
          ..color = NColors.emerald
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round);
    for (var i = 0; i < n; i++) {
      final v = axes[i].$2;
      canvas.drawCircle(at(i, v.clamp(0, 1)), 4, Paint()..color = v >= target ? NColors.emerald : NColors.coral);
      final label = axes[i].$1.length > 16 ? '${axes[i].$1.substring(0, 15)}…' : axes[i].$1;
      final tp = TextPainter(
        text: TextSpan(children: [
          TextSpan(
              text: '$label\n',
              style: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 10, color: ink.withValues(alpha: 0.7))),
          TextSpan(
              text: L10n.percent((v * 100).round()),
              style: TextStyle(
                  fontFamily: 'PlusJakartaSans',
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: v >= target ? NColors.emerald : NColors.coral)),
        ]),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 90);
      final p = at(i, 1.18);
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_RadarPainter o) => false;
}

/// Yatay yığılmış çubuk: parçalar oranlarına göre yan yana dizilir
/// (başarı düzeyleri, doğru/yanlış/boş gibi).
class StackedBar extends StatelessWidget {
  final List<(double value, Color color)> parts;
  final double height;
  final bool showPercent;
  const StackedBar({super.key, required this.parts, this.height = 22, this.showPercent = true});

  @override
  Widget build(BuildContext context) {
    final total = parts.fold<double>(0, (a, p) => a + p.$1);
    final t = Theme.of(context);
    if (total <= 0) {
      return Container(
        height: height,
        decoration: BoxDecoration(color: t.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(6)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: height,
        child: Row(children: [
          for (final p in parts)
            if (p.$1 > 0)
              Expanded(
                flex: math.max(1, (p.$1 / total * 1000).round()),
                child: Container(
                  color: p.$2,
                  alignment: Alignment.center,
                  child: showPercent && p.$1 / total >= 0.09
                      ? Text('${(p.$1 / total * 100).round()}',
                          maxLines: 1,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, fontFeatures: tabular))
                      : null,
                ),
              ),
        ]),
      ),
    );
  }
}

/// Grafik açıklaması: renkli kare ve etiket.
class ChartLegend extends StatelessWidget {
  final List<(String label, Color color)> items;
  const ChartLegend(this.items, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Wrap(spacing: 12, runSpacing: 6, children: [
      for (final (l, c) in items)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 5),
          Text(l, style: t.textTheme.bodySmall),
        ]),
    ]);
  }
}

/// Dikey sütun grafiği (dağılım, aylık ortalama vb.). Değerlerin üstünde
/// sayılar, altında etiketler yazar.
class ColumnChart extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final List<Color>? colors;
  final double height;
  final String Function(double)? format;
  const ColumnChart(
      {super.key, required this.values, required this.labels, this.colors, this.height = 160, this.format});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final max = values.isEmpty ? 1.0 : math.max(1e-9, values.reduce(math.max));
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    return SizedBox(
      height: height,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(format?.call(values[i]) ?? '${values[i].round()}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, fontFeatures: tabular)),
                ),
                const SizedBox(height: 2),
                Container(
                  height: math.max(2, (height - 40) * values[i] / max),
                  decoration: BoxDecoration(
                    color: colors == null ? NColors.emerald : colors![i % colors!.length],
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 14,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(labels[i], style: TextStyle(fontSize: 10, color: muted)),
                  ),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Birden çok seri için çizgi grafiği (0–100 ölçeği): sınıfların zaman
/// içindeki ortalamaları gibi.
class LineSeriesChart extends StatelessWidget {
  final List<(String label, Color color, List<double?> values)> series;
  final List<String> xLabels;
  final double height;
  final double? target;
  const LineSeriesChart(
      {super.key, required this.series, required this.xLabels, this.height = 190, this.target});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: height,
        child: CustomPaint(
          size: Size.infinite,
          painter: _LinePainter(
            series: series,
            xLabels: xLabels,
            target: target,
            grid: t.colorScheme.outlineVariant,
            text: t.colorScheme.onSurface.withValues(alpha: 0.6),
            font: t.textTheme.bodySmall?.fontFamily,
          ),
        ),
      ),
      if (series.length > 1) ...[
        const SizedBox(height: 8),
        ChartLegend([for (final s in series) (s.$1, s.$2)]),
      ],
    ]);
  }
}

class _LinePainter extends CustomPainter {
  final List<(String, Color, List<double?>)> series;
  final List<String> xLabels;
  final double? target;
  final Color grid, text;
  final String? font;
  _LinePainter(
      {required this.series, required this.xLabels, required this.target, required this.grid, required this.text, this.font});

  @override
  void paint(Canvas canvas, Size size) {
    const left = 30.0, bottom = 22.0, top = 8.0;
    final w = size.width - left - 10, h = size.height - bottom - top;
    final n = xLabels.length;
    void label(String s, Offset o, {bool center = false}) {
      final tp = TextPainter(
          text: TextSpan(text: s, style: TextStyle(color: text, fontSize: 10, fontFamily: font)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, center ? o - Offset(tp.width / 2, 0) : o - Offset(tp.width, tp.height / 2));
    }

    final g = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final v in [0, 25, 50, 75, 100]) {
      final y = top + h * (1 - v / 100);
      canvas.drawLine(Offset(left, y), Offset(left + w, y), g);
      label('$v', Offset(left - 6, y));
    }
    if (target != null) {
      final y = top + h * (1 - target!.clamp(0, 100) / 100);
      final p = Paint()
        ..color = NColors.amber
        ..strokeWidth = 1.5;
      for (var x = left; x < left + w; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, left + w), y), p);
      }
    }
    Offset pt(int i, double v) => Offset(left + (n <= 1 ? w / 2 : w * i / (n - 1)), top + h * (1 - v.clamp(0, 100) / 100));
    for (final (_, color, values) in series) {
      final path = Path();
      var started = false;
      for (var i = 0; i < values.length && i < n; i++) {
        final v = values[i];
        if (v == null) continue;
        final o = pt(i, v);
        started ? path.lineTo(o.dx, o.dy) : path.moveTo(o.dx, o.dy);
        started = true;
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round);
      for (var i = 0; i < values.length && i < n; i++) {
        final v = values[i];
        if (v != null) canvas.drawCircle(pt(i, v), 3.5, Paint()..color = color);
      }
    }
    // Etiketler çok sıkışırsa bazılarını atla.
    final step = math.max(1, (n * 46 / math.max(1, w)).ceil());
    for (var i = 0; i < n; i += step) {
      label(xLabels[i], Offset(pt(i, 0).dx, size.height - bottom + 6), center: true);
    }
  }

  @override
  bool shouldRepaint(_LinePainter o) => true;
}

/// Sınıflar için tutarlı renkler.
const seriesColors = [
  NColors.emerald,
  Color(0xFF6C7FD8),
  NColors.coral,
  NColors.amber,
  Color(0xFF14B8A6),
  Color(0xFFA855F7),
  Color(0xFF0EA5E9),
  Color(0xFFEC4899),
];

/// Başarı düzeyleri için renkler (en yüksekten en düşüğe).
const levelPalette = [NColors.emerald, Color(0xFF34D399), NColors.amber, Color(0xFFF59E0B), NColors.coral];
