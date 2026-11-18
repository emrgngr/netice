import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/legal.dart';
import '../main.dart';
import 'theme.dart';
import 'widgets.dart';

/// Uygulamayı meslektaşlara önerme: telefonun paylaşım menüsü açılır.
Future<void> shareApp(BuildContext context) async {
  try {
    await SharePlus.instance.share(ShareParams(text: shareText, subject: 'Netice: optik okuma ve sınav analizi'));
  } catch (_) {
    if (context.mounted) toast(context, 'Paylaşım açılamadı.');
  }
}

/// Yıldız verme penceresi. 4-5 yıldız mağaza sayfasına yönlendirir,
/// daha düşük puanlarda neyin eksik olduğu sorulur.
/// [onFeedback] düşük puanda geri bildirim ekranını açar.
Future<void> showRateDialog(BuildContext context, {VoidCallback? onFeedback}) async {
  final store = StoreScope.of(context);
  final stars = await showDialog<int>(
    context: context,
    builder: (ctx) => _RateDialog(initial: store.rating),
  );
  if (stars == null) {
    store.markRatePrompted();
    return;
  }
  store.setRating(stars);
  if (!context.mounted) return;
  if (stars >= 4) {
    if (storePublished) {
      final ok = await launchUrl(Uri.parse(playStoreUrl), mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) toast(context, 'Mağaza açılamadı.');
    } else {
      toast(context, 'Teşekkürler! Netice mağazaya çıkınca bu düğme sizi doğrudan yorum sayfasına götürecek.');
    }
  } else {
    toast(context, 'Teşekkürler. Neyi daha iyi yapabileceğimizi yazar mısınız?');
    onFeedback?.call();
  }
}

class _RateDialog extends StatefulWidget {
  final int initial;
  const _RateDialog({required this.initial});
  @override
  State<_RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends State<_RateDialog> {
  late int _s = widget.initial;

  static const _labels = ['', 'Hiç beğenmedim', 'Geliştirilmeli', 'İdare eder', 'Beğendim', 'Harika!'];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: NColors.amber.withValues(alpha: 0.18), shape: BoxShape.circle),
          child: const Icon(Icons.star_rounded, color: NColors.amber, size: 40),
        ),
        const SizedBox(height: 14),
        Text('Netice işinizi kolaylaştırdı mı?',
            textAlign: TextAlign.center, style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('Yıldızınız, başka öğretmenlerin Netice\'yi bulmasına yardım eder.',
            textAlign: TextAlign.center, style: TextStyle(color: t.colorScheme.onSurface.withValues(alpha: 0.65))),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 1; i <= 5; i++)
            IconButton(
              tooltip: '$i yıldız',
              iconSize: 38,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              constraints: const BoxConstraints(),
              onPressed: () => setState(() => _s = i),
              icon: AnimatedScale(
                scale: i <= _s ? 1.12 : 1,
                duration: const Duration(milliseconds: 150),
                child: Icon(i <= _s ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: i <= _s ? NColors.amber : t.colorScheme.outline),
              ),
            ),
        ]),
        SizedBox(
          height: 26,
          child: Center(
            child: Text(_labels[_s], style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Daha sonra')),
        FilledButton(
          onPressed: _s == 0 ? null : () => Navigator.pop(context, _s),
          child: Text(_s >= 4 ? 'Mağazada değerlendir' : 'Gönder'),
        ),
      ],
    );
  }
}
