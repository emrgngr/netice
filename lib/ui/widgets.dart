import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import 'theme.dart';
import '../l10n/l10n.dart';

/// Rakam önde: büyük, tabular rakamlı istatistik kartı.
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;
  final Color? accent;
  final IconData? icon;

  const StatCard({super.key, required this.label, required this.value, this.hint, this.accent, this.icon});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = accent ?? NColors.emerald;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              if (icon != null) ...[IconBadge(icon!, color: c, size: 30), const SizedBox(width: 10)],
              Expanded(
                // Uzun etiketler kesilmek yerine biraz küçülür.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(label,
                      maxLines: 1,
                      style: t.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600, color: t.colorScheme.onSurface.withValues(alpha: 0.6))),
                ),
              ),
            ]),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: t.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800, letterSpacing: -0.5, fontFeatures: tabular, color: t.colorScheme.onSurface)),
            ),
            if (hint != null) ...[
              const SizedBox(height: 2),
              Text(hint!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.bodySmall?.copyWith(
                      color: accent ?? t.colorScheme.onSurface.withValues(alpha: 0.55))),
            ],
          ],
        ),
      ),
    );
  }
}

/// D/Y/B rozeti: renk körlüğü için her renk bir simgeyle desteklenir.
class DybText extends StatelessWidget {
  final int correct, wrong, blank;
  const DybText(this.correct, this.wrong, this.blank, {super.key});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).textTheme.bodyMedium!.copyWith(fontFeatures: tabular, fontWeight: FontWeight.w600);
    Widget part(IconData icon, String text, Color color) => Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 2),
          Text(text, style: s.copyWith(color: color)),
        ]);
    return Wrap(spacing: 12, children: [
      part(Icons.check, '$correct ${tr('D')}', NColors.emerald),
      part(Icons.close, '$wrong ${tr('Y')}', NColors.coral),
      part(Icons.remove, '$blank ${tr('B')}', NColors.gray),
    ]);
  }
}

String letter(int i) => String.fromCharCode(65 + i);

String answerText(Answer a) => a.marked.isEmpty ? '–' : a.marked.map(letter).join('/');

String fmt1(double v) => v.toStringAsFixed(1).replaceAll('.', L10n.decimal);
String fmt2(double v) => v.toStringAsFixed(2).replaceAll('.', L10n.decimal);

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
        child: Row(children: [
          Expanded(
            child: Text(text,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          ?trailing,
        ]),
      );
}

/// Uygulama simgesiyle aynı premium logo (görüntü).
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.225),
          boxShadow: [BoxShadow(color: NColors.ink.withValues(alpha: 0.25), blurRadius: size * 0.3, offset: Offset(0, size * 0.08))],
        ),
        child: Image.asset('assets/icon/netice_icon_rounded_1024.png', width: size, height: size, filterQuality: FilterQuality.high),
      );
}

/// Lacivert gradyanlı, hafif dokulu "kahraman" panel.
class HeroPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const HeroPanel({super.key, required this.child, this.padding = const EdgeInsets.all(22)});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          gradient: inkGradient,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [BoxShadow(color: NColors.ink.withValues(alpha: 0.28), blurRadius: 28, offset: const Offset(0, 14))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(children: [
            // Simgedeki optik dairelerden esinlenen silik desen.
            Positioned(right: -40, top: -40, child: Opacity(opacity: 0.05, child: _DotPattern(size: 150))),
            Padding(padding: padding, child: child),
          ]),
        ),
      );
}

class _DotPattern extends StatelessWidget {
  final double size;
  const _DotPattern({required this.size});
  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _DotPainter()),
      );
}

class _DotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final cell = s.width / 5;
    final p = Paint()..color = Colors.white;
    final ring = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var y = 0; y < 5; y++) {
      for (var x = 0; x < 5; x++) {
        final c = Offset(cell * (x + 0.5), cell * (y + 0.5));
        if ((x + y * 2) % 3 == 0) {
          canvas.drawCircle(c, cell * 0.34, p);
        } else {
          canvas.drawCircle(c, cell * 0.30, ring);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Zümrüt gradyanlı, parıltılı birincil eylem düğmesi.
class GlowButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final double height;
  const GlowButton({super.key, required this.label, required this.icon, required this.onPressed, this.height = 64});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: emeraldGradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: NColors.emerald.withValues(alpha: 0.45), blurRadius: 22, offset: const Offset(0, 8))],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onPressed,
            child: SizedBox(
              height: height,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, color: NColors.ink, size: 26),
                const SizedBox(width: 10),
                Text(label, style: const TextStyle(color: NColors.ink, fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
              ]),
            ),
          ),
        ),
      );
}

/// Ortalama puanı gösteren halka.
class ScoreRing extends StatelessWidget {
  final double value; // 0..100
  final double size;
  final Color? track;
  final TextStyle? style;
  const ScoreRing({super.key, required this.value, this.size = 56, this.track, this.style});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return SizedBox.square(
      dimension: size,
      child: Stack(alignment: Alignment.center, children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: (value / 100).clamp(0, 1)),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          builder: (_, v, _) => CustomPaint(
            size: Size.square(size),
            painter: _RingPainter(v, track ?? t.colorScheme.outlineVariant, size * 0.09),
          ),
        ),
        Text(fmt1(value),
            style: style ??
                t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, fontFeatures: tabular, fontSize: size * 0.26)),
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double v;
  final Color track;
  final double w;
  _RingPainter(this.v, this.track, this.w);

  @override
  void paint(Canvas canvas, Size s) {
    final rect = Offset(w / 2, w / 2) & Size(s.width - w, s.height - w);
    canvas.drawArc(rect, 0, 6.2832, false, Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = w);
    canvas.drawArc(rect, -1.5708, 6.2832 * v, false, Paint()
      ..shader = const SweepGradient(colors: [Color(0xFF34D399), Color(0xFF059669), Color(0xFF34D399)]).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.track != track;
}

/// Renkli zeminli küçük simge rozeti.
class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const IconBadge(this.icon, {super.key, this.color = NColors.emerald, this.size = 36});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(size * 0.32)),
        child: Icon(icon, size: size * 0.55, color: color),
      );
}

/// Ekranların arka planı: içeriğin arkasında, iki köşede çok yumuşak renk
/// ışıması. Desen ya da logo yok; kartların üzerine hiçbir şey binmez.
class Watermark extends StatelessWidget {
  final Widget child;
  const Watermark({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(children: [
      Positioned.fill(
        child: IgnorePointer(
          child: RepaintBoundary(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(1.1, -1.05),
                  radius: 1.25,
                  colors: [NColors.emerald.withValues(alpha: dark ? 0.10 : 0.07), NColors.emerald.withValues(alpha: 0)],
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-1.2, 1.1),
                    radius: 1.1,
                    colors: [
                      (dark ? const Color(0xFF6D7FD8) : NColors.ink).withValues(alpha: dark ? 0.08 : 0.04),
                      (dark ? const Color(0xFF6D7FD8) : NColors.ink).withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      child,
    ]);
  }
}

List<String> get _months => [tr('Ocak'), tr('Şubat'), tr('Mart'), tr('Nisan'), tr('Mayıs'), tr('Haziran'), tr('Temmuz'), tr('Ağustos'), tr('Eylül'), tr('Ekim'), tr('Kasım'), tr('Aralık')];
List<String> get _days => [tr('Pazartesi'), tr('Salı'), tr('Çarşamba'), tr('Perşembe'), tr('Cuma'), tr('Cumartesi'), tr('Pazar')];
String _two(int v) => v.toString().padLeft(2, '0');

/// 18.11.2026
String dmy(DateTime d) => L10n.date(d);

/// 10:04
String hm(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// 18 Kasım 2026, Çarşamba
/// Uzun tarih; sıralama dile göre çeviride ayarlanır (ör. Japonca: 2026年11月19日).
String longDate(DateTime d) => tr('{0} {1} {2}, {3}', [d.day, _months[d.month - 1], d.year, _days[d.weekday - 1]]);

/// Dakikada bir yenilenen tarih ve saat göstergesi.
class LiveClock extends StatefulWidget {
  /// Koyu (lacivert) zemin üzerinde mi?
  final bool onDark;
  const LiveClock({super.key, this.onDark = false});

  @override
  State<LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<LiveClock> {
  DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    final n = DateTime.now();
    final next = DateTime(n.year, n.month, n.day, n.hour, n.minute + 1);
    _timer = Timer(next.difference(n), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final fg = widget.onDark ? Colors.white : t.colorScheme.onSurface;
    final sub = widget.onDark ? Colors.white70 : t.colorScheme.onSurface.withValues(alpha: 0.6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: widget.onDark ? Colors.white.withValues(alpha: 0.08) : t.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.onDark ? Colors.white.withValues(alpha: 0.12) : t.colorScheme.outlineVariant),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.calendar_today_rounded, size: 16, color: NColors.emerald),
        const SizedBox(width: 8),
        Flexible(
          // Uzun tarih sığmazsa kısa biçime geçilir (küçük telefonlar, uzun gün adları).
          child: LayoutBuilder(builder: (context, c) {
            final style = TextStyle(color: sub, fontSize: 13, fontWeight: FontWeight.w600);
            final long = longDate(_now);
            final tp = TextPainter(text: TextSpan(text: long, style: style), textDirection: Directionality.of(context), maxLines: 1)
              ..layout();
            final text = tp.width <= c.maxWidth ? long : dmy(_now);
            tp.dispose();
            return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
          }),
        ),
        const SizedBox(width: 12),
        Icon(Icons.schedule_rounded, size: 16, color: NColors.emerald),
        const SizedBox(width: 6),
        Text(hm(_now),
            style: TextStyle(color: fg, fontSize: 15, fontWeight: FontWeight.w800, fontFeatures: tabular)),
      ]),
    );
  }
}

/// Sayı seçici: kaydırma çubuğu + "−" / "+" düğmeleri + elle yazılabilen kutu.
/// Üçü birbirine bağlıdır; değer her zaman [min]–[max] aralığında tutulur.
/// Düğmeye basılı tutunca değer hızlanarak artar/azalır.
class NumberStepper extends StatefulWidget {
  const NumberStepper({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.semanticLabel,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final String? semanticLabel;

  @override
  State<NumberStepper> createState() => _NumberStepperState();
}

class _NumberStepperState extends State<NumberStepper> {
  late final TextEditingController _text = TextEditingController(text: '${widget.value}');
  final _focus = FocusNode();
  Timer? _repeat;
  // Son bildirilen değer: aynı karede art arda basışlar eski değeri kullanmasın.
  late int _current = widget.value;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(NumberStepper old) {
    super.didUpdateWidget(old);
    _current = widget.value;
    // Dışarıdan (çubuk ya da düğme) gelen değişikliği kutuya yansıt;
    // kullanıcı yazarken yarım kalan sayıyı ezme.
    if (!_focus.hasFocus && _text.text != '${widget.value}') _text.text = '${widget.value}';
  }

  @override
  void dispose() {
    _repeat?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  int _clamp(int v) => v.clamp(widget.min, widget.max);

  void _emit(int v) {
    v = _clamp(v);
    if (v != _current) {
      _current = v;
      widget.onChanged(v);
    }
    if (_text.text != '$v') {
      _text.value = TextEditingValue(text: '$v', selection: TextSelection.collapsed(offset: '$v'.length));
    }
  }

  void _commit() {
    final v = int.tryParse(_text.text.trim());
    _emit(v ?? _current);
  }

  void _typing(String s) {
    final v = int.tryParse(s.trim());
    // Aralıktaysa hemen uygula; değilse (ör. "1" yazıp "10"a gidiyor) bitince düzelt.
    if (v != null && v >= widget.min && v <= widget.max && v != _current) {
      _current = v;
      widget.onChanged(v);
    }
  }

  void _step(int d) {
    if (_focus.hasFocus) _focus.unfocus();
    _emit(_current + d);
  }

  void _startRepeat(int d) {
    var ticks = 0;
    _repeat?.cancel();
    _repeat = Timer.periodic(const Duration(milliseconds: 90), (_) {
      ticks++;
      _step(ticks > 15 ? d * 5 : d);
    });
  }

  void _stopRepeat() {
    _repeat?.cancel();
    _repeat = null;
  }

  Widget _button(IconData icon, int d, String tooltip) {
    final enabled = d < 0 ? widget.value > widget.min : widget.value < widget.max;
    // İpucu (tooltip) uzun basmayı yakaladığı için kullanılmıyor; ekran okuyucu
    // için etiket Semantics ile veriliyor.
    return Semantics(
      label: tooltip,
      button: true,
      child: GestureDetector(
        onLongPressStart: enabled ? (_) => _startRepeat(d) : null,
        onLongPressEnd: (_) => _stopRepeat(),
        onLongPressCancel: _stopRepeat,
        child: IconButton.filledTonal(
          onPressed: enabled ? () => _step(d) : null,
          icon: Icon(icon),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Slider(
        value: widget.value.clamp(widget.min, widget.max).toDouble(),
        min: widget.min.toDouble(),
        max: widget.max.toDouble(),
        divisions: widget.max - widget.min,
        label: '${widget.value}',
        semanticFormatterCallback: (v) => '${widget.semanticLabel ?? ''} ${v.round()}'.trim(),
        onChanged: (v) {
          if (_focus.hasFocus) _focus.unfocus();
          _emit(v.round());
        },
      ),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _button(Icons.remove_rounded, -1, tr('Azalt')),
        const SizedBox(width: 12),
        SizedBox(
          width: 88,
          child: TextField(
            controller: _text,
            focusNode: _focus,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter('${widget.max}'.length)],
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontFeatures: tabular),
            decoration: InputDecoration(isDense: true, semanticCounterText: '${widget.min}–${widget.max}'),
            onChanged: _typing,
            onSubmitted: (_) => _commit(),
          ),
        ),
        const SizedBox(width: 12),
        _button(Icons.add_rounded, 1, tr('Artır')),
      ]),
    ]);
  }
}
