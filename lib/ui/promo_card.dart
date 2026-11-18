import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/promo.dart';
import '../main.dart';
import 'theme.dart';
import 'widgets.dart';

/// Ana sayfanın altındaki sade, kapatılabilir öneri kartı.
class PromoCard extends StatefulWidget {
  const PromoCard({super.key});

  @override
  State<PromoCard> createState() => _PromoCardState();
}

class _PromoCardState extends State<PromoCard> {
  PromoFeed _feed = PromoService.instance.feed;

  @override
  void initState() {
    super.initState();
    PromoService.instance.load(onUpdate: (f) {
      if (mounted) setState(() => _feed = f);
    }).then((f) {
      if (mounted) setState(() => _feed = f);
    });
  }

  Future<void> _open(String url) async {
    try {
      final ok = await launchUrl(PromoFeed.tagged(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) toast(context, 'Bağlantı açılamadı.');
    } catch (_) {
      if (mounted) toast(context, 'Bağlantı açılamadı.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.55);
    final items = _feed.items;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 6, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: muted.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('Önerilen', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: muted)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_feed.store, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
            IconButton(
              tooltip: 'Bir hafta gösterme',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded, size: 18, color: muted),
              onPressed: () {
                StoreScope.of(context).hidePromo();
                toast(context, 'Öneriler bir hafta gösterilmeyecek.');
              },
            ),
          ]),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 10, top: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _open(_feed.url),
                child: Ink(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(colors: [
                      NColors.emerald.withValues(alpha: 0.12),
                      const Color(0xFFF6E3C2).withValues(alpha: 0.5),
                    ]),
                  ),
                  child: Row(children: [
                    const IconBadge(Icons.shopping_bag_outlined, color: NColors.emerald),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${_feed.store} mağazasını keşfedin',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text('Netice\'yi ücretsiz sunmamıza destek olan mağazamız',
                            style: TextStyle(color: muted, fontSize: 12.5)),
                      ]),
                    ),
                    const Icon(Icons.open_in_new_rounded, size: 18),
                  ]),
                ),
              ),
            )
          else if (items.length == 1)
            Padding(
              padding: const EdgeInsets.only(right: 10, top: 4),
              child: _WideProduct(items.first, onTap: () => _open(items.first.url)),
            )
          else
            SizedBox(
              height: 200,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(right: 10, top: 4),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _Product(items[i], onTap: () => _open(items[i].url)),
              ),
            ),
        ]),
      ),
    );
  }
}

class _Product extends StatelessWidget {
  final PromoItem item;
  final VoidCallback onTap;
  const _Product(this.item, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    Widget placeholder() => Container(
          color: NColors.emerald.withValues(alpha: 0.08),
          child: const Center(child: Icon(Icons.shopping_bag_outlined, color: NColors.emerald)),
        );
    return SizedBox(
      width: 140,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 112,
              width: 140,
              child: item.image == null
                  ? placeholder()
                  : Image.network(item.image!, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder()),
            ),
          ),
          const SizedBox(height: 8),
          Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          if (item.price.isNotEmpty)
            Text(item.price,
                style: t.textTheme.bodyMedium?.copyWith(color: NColors.emerald, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }
}

Widget _promoPlaceholder() => Container(
      color: NColors.emerald.withValues(alpha: 0.08),
      child: const Center(child: Icon(Icons.shopping_bag_outlined, color: NColors.emerald)),
    );

class _WideProduct extends StatelessWidget {
  final PromoItem item;
  final VoidCallback onTap;
  const _WideProduct(this.item, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox.square(
            dimension: 84,
            child: item.image == null
                ? _promoPlaceholder()
                : Image.network(item.image!, fit: BoxFit.cover, errorBuilder: (_, _, _) => _promoPlaceholder()),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
            if (item.subtitle.isNotEmpty)
              Text(item.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted, fontSize: 12.5)),
            const SizedBox(height: 6),
            Row(children: [
              if (item.price.isNotEmpty)
                Text(item.price, style: const TextStyle(color: NColors.emerald, fontWeight: FontWeight.w800, fontSize: 15)),
              const Spacer(),
              FilledButton.tonal(
                onPressed: onTap,
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                child: const Text('İncele'),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}
