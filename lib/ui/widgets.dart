import 'package:material_ui/material_ui.dart';

import '../core/models.dart';
import 'theme.dart';

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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label.toUpperCase(),
                style: t.textTheme.labelSmall?.copyWith(
                    letterSpacing: 0.8, color: t.colorScheme.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 6),
            Text(value,
                style: t.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800, fontFeatures: tabular, color: t.colorScheme.onSurface)),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Row(children: [
                if (icon != null) ...[Icon(icon, size: 14, color: accent), const SizedBox(width: 4)],
                Flexible(
                  child: Text(hint!,
                      style: t.textTheme.bodySmall?.copyWith(
                          color: accent ?? t.colorScheme.onSurface.withValues(alpha: 0.6))),
                ),
              ]),
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
      part(Icons.check, '$correct D', NColors.emerald),
      part(Icons.close, '$wrong Y', NColors.coral),
      part(Icons.remove, '$blank B', NColors.gray),
    ]);
  }
}

String letter(int i) => String.fromCharCode(65 + i);

String answerText(Answer a) => a.marked.isEmpty ? '–' : a.marked.map(letter).join('/');

String fmt1(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
String fmt2(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

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
