import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/legal.dart';
import '../core/store.dart';
import '../core/updates.dart';
import '../l10n/l10n.dart';
import '../main.dart';
import 'theme.dart';

/// Yeni sürüm ilk açıldığında yenilikleri bir kez gösterir. İlk kurulumda
/// (daha önce görülen sürüm yoksa) yalnızca sürümü kaydeder. Gösterildiyse true.
Future<bool> maybeShowWhatsNew(BuildContext context, AppStore store, {List<ReleaseNote>? notes, String? current}) async {
  final now = current ?? appVersion;
  final seen = store.lastSeenVersion;
  if (seen == null) {
    store.markVersionSeen(now);
    return false;
  }
  if (compareVersions(now, seen) <= 0) return false;
  final items = notesBetween(seen, now, notes);
  store.markVersionSeen(now);
  if (items.isEmpty || !context.mounted) return false;
  await showDialog<void>(context: context, builder: (_) => WhatsNewDialog(version: now, items: items));
  return true;
}

class WhatsNewDialog extends StatelessWidget {
  final String version;
  final List<ReleaseItem> items;
  const WhatsNewDialog({super.key, required this.version, required this.items});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AlertDialog(
      icon: const Icon(Icons.auto_awesome_rounded, color: NColors.emerald, size: 32),
      title: Text(tr('Bu sürümde yenilikler'), textAlign: TextAlign.center),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
              child: Text(tr('Sürüm {0}', [version]),
                  style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.onSurface.withValues(alpha: 0.6))),
            ),
            const SizedBox(height: 14),
            for (final i in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.check_circle_rounded, color: NColors.emerald, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(i.text, style: const TextStyle(height: 1.4))),
                ]),
              ),
          ]),
        ),
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Harika'))),
      ],
    );
  }
}

/// Ana sayfada "Yeni sürüm hazır" kartı. Mağazada daha yeni sürüm yoksa ya da
/// kullanıcı bu sürüm için kapattıysa hiç yer kaplamaz.
class UpdateBanner extends StatelessWidget {
  final EdgeInsets padding;
  const UpdateBanner({super.key, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: UpdateService.instance,
        builder: (context, _) {
          final u = UpdateService.instance;
          final store = StoreScope.of(context);
          if (!u.updateAvailable || store.dismissedUpdate == u.latest) return const SizedBox.shrink();
          final desktop = currentPlatform == 'windows' || currentPlatform == 'macos';
          return Padding(
            padding: padding,
            child: Card(
              color: NColors.emerald.withValues(alpha: 0.12),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.system_update_rounded, color: NColors.emerald),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr('Yeni sürüm hazır: {0}', [u.latest!]), style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        desktop
                            ? tr('Sitemizden yeni kurulum dosyasını indirin. Verileriniz olduğu gibi kalır.')
                            : tr('Mağazadan güncelleyin. Verileriniz olduğu gibi kalır.'),
                        style: const TextStyle(fontSize: 13, height: 1.35),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: () => launchUrl(Uri.parse(UpdateService.updateUrl), mode: LaunchMode.externalApplication),
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: Text(tr('Güncelle')),
                      ),
                    ]),
                  ),
                  IconButton(
                    tooltip: tr('Kapat'),
                    onPressed: () => store.dismissUpdate(u.latest!),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ]),
              ),
            ),
          );
        },
      );
}
