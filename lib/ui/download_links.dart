// "Netice'yi indirin" bölümü: resmî mağaza rozetleri (Google Play, App Store,
// Mac App Store, Microsoft Store) ve indirme sayfasına giden karekod.
// Rozetler assets/badges/ altındadır (resmî kaynaktan, değiştirilmeden;
// .github/workflows/magaza-rozetleri.yml indirir ve PNG kopyasını üretir).
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/legal.dart';
import '../l10n/l10n.dart';
import 'ad_slot.dart' show AdQr;
import 'rate_share.dart';
import 'service_cards.dart';
import 'theme.dart';
import 'widgets.dart';

class _Store {
  final String badge; // assets/badges/<badge>_<dil>.png
  final String name;
  final String url;
  final bool live;
  const _Store(this.badge, this.name, this.url, this.live);
}

List<_Store> get _stores => [
      _Store('google_play', 'Google Play', playStoreUrl, true),
      _Store('app_store', 'App Store', appStoreLive ? appStoreLink : downloadPageUrl, appStoreLive),
      _Store('mac_app_store', 'Mac App Store', appStoreLive ? appStoreLink : downloadPageUrl, appStoreLive),
      _Store('microsoft', 'Microsoft Store', msStoreUrl.isNotEmpty ? msStoreUrl : downloadPageUrl, msStoreUrl.isNotEmpty),
    ];

Future<void> _open(BuildContext context, String url) async {
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok && context.mounted) toast(context, tr('Bağlantı açılamadı.'));
}

/// Tek bir resmî rozet. Dilin rozeti yoksa İngilizcesi, o da yoksa mağaza adı.
class StoreBadge extends StatelessWidget {
  final String kind;
  final String name;
  final double height;
  const StoreBadge({super.key, required this.kind, required this.name, this.height = 48});

  @override
  Widget build(BuildContext context) {
    Widget fallback() => Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(height * 0.2)),
          child: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        );
    // Google Play'in resmî PNG'sinde üstte ve altta saydam boşluk var
    // (250 px'in 192'si rozet); diğerleriyle aynı boyda görünsün diye büyütülüp
    // boşluk kırpılır, rozetin kendisi değişmez.
    final h = kind == 'google_play' ? height * 250 / 192 : height;
    final img = Image.asset(
      'assets/badges/${kind}_${L10n.code}.png',
      height: h,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => Image.asset('assets/badges/${kind}_en.png',
          height: h, filterQuality: FilterQuality.medium, errorBuilder: (_, _, _) => fallback()),
    );
    if (h == height) return img;
    return SizedBox(
        height: height, width: h * 646 / 250, child: ClipRect(child: OverflowBox(maxHeight: h, child: img)));
  }
}

/// Rozetler ve karekod. Profil, Ayarlar ve "Netice'yi indirin" ekranında.
class DownloadLinksPanel extends StatelessWidget {
  const DownloadLinksPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget badge(_Store s, double h) => Semantics(
          button: true,
          label: s.live ? s.name : '${s.name} · ${tr('Yakında')}',
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _open(context, s.url),
            child: Opacity(opacity: s.live ? 1 : 0.5, child: StoreBadge(kind: s.badge, name: s.name, height: h)),
          ),
        );
    final soon = _stores.where((s) => !s.live).map((s) => s.name).toList();
    final soonNote = soon.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(tr('Yakında: {0}', [soon.join(', ')]),
                style: TextStyle(fontSize: 12.5, color: muted, fontWeight: FontWeight.w600)),
          );
    Widget qrBox(double size) => Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // Karekod her temada beyaz zeminde kalır; okutulabilmesi için.
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: dark ? Colors.white24 : NColors.ink.withValues(alpha: 0.08)),
      ),
      child: AdQr(downloadPageUrl),
    );
    final qr = qrBox(148);
    final qrText = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(tr('Karekodu okutun'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text(tr('Telefonunuzun kamerasını tutun; cihazınıza uygun mağaza açılır.'), style: TextStyle(color: muted, height: 1.35)),
      const SizedBox(height: 8),
      Text(websiteUrl.replaceFirst(RegExp(r'^https?://(www\.)?'), ''),
          style: TextStyle(fontWeight: FontWeight.w700, color: dark ? NColors.emerald : NColors.deepEmerald)),
    ]);
    final actions = Wrap(spacing: 10, runSpacing: 10, children: [
      FilledButton.icon(
        onPressed: () => shareApp(context),
        icon: const Icon(Icons.ios_share_rounded),
        label: Text(tr('Bağlantıyı paylaş')),
      ),
      OutlinedButton.icon(
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: downloadPageUrl));
          if (context.mounted) toast(context, tr('Bağlantı kopyalandı.'));
        },
        icon: const Icon(Icons.link_rounded),
        label: Text(tr('Bağlantıyı kopyala')),
      ),
    ]);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 620;
        if (wide) {
          return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            qr,
            const SizedBox(width: 24),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                qrText,
                const SizedBox(height: 16),
                Wrap(spacing: 12, runSpacing: 12, children: [for (final s in _stores) badge(s, 40)]),
                soonNote,
                const SizedBox(height: 16),
                actions,
              ]),
            ),
          ]);
        }
        // Telefonda rozetler iki sütunda, sütuna sığacak boyda.
        Widget cell(_Store s) => Expanded(
            child: Align(alignment: AlignmentDirectional.centerStart, child: FittedBox(fit: BoxFit.scaleDown, child: badge(s, 42))));
        final st = _stores;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [qrBox(124), const SizedBox(width: 16), Expanded(child: qrText)]),
          const SizedBox(height: 18),
          for (var i = 0; i < st.length; i += 2) ...[
            if (i > 0) const SizedBox(height: 10),
            Row(children: [cell(st[i]), const SizedBox(width: 10), if (i + 1 < st.length) cell(st[i + 1]) else const Spacer()]),
          ],
          soonNote,
          const SizedBox(height: 16),
          actions,
        ]);
      }),
    );
  }
}

/// Tam sayfa "Netice'yi indirin".
class DownloadScreen extends StatelessWidget {
  const DownloadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Netice\'yi indirin'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
                child: Text(
                    tr('Netice telefonda, tablette ve bilgisayarda çalışır. Meslektaşlarınız karekodu okutarak ya da mağaza rozetine dokunarak indirebilir.'),
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.4)),
              ),
              const RoundedPanel(child: DownloadLinksPanel()),
            ]),
          ),
        ),
      ]),
    );
  }
}
