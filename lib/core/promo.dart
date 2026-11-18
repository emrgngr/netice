import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Ana sayfadaki "Önerilen" kartı: geliştiricinin kendi mağazasından ürünler.
///
/// Reklam ağı kullanılmaz, kullanıcı izlenmez. İnternet varsa günde en çok
/// bir kez yalnızca herkese açık ürün listesi indirilir (istekte kullanıcıya
/// ait hiçbir bilgi yoktur); yoksa son indirilen liste ya da varsayılan
/// mağaza kartı gösterilir.
class PromoItem {
  final String title;
  final String subtitle;
  final String price;
  final String url;
  final String? image;
  const PromoItem({required this.title, this.subtitle = '', this.price = '', required this.url, this.image});

  factory PromoItem.fromJson(Map<String, dynamic> j) => PromoItem(
        title: '${j['title'] ?? ''}',
        subtitle: '${j['subtitle'] ?? ''}',
        price: '${j['price'] ?? ''}',
        url: '${j['url'] ?? ''}',
        image: (j['image'] as String?)?.isEmpty ?? true ? null : j['image'] as String,
      );
}

class PromoFeed {
  final String store;
  final String url;
  final List<PromoItem> items;
  const PromoFeed({required this.store, required this.url, this.items = const []});

  static const fallback = PromoFeed(store: 'SepetMix', url: 'https://www.sepetmix.com');

  factory PromoFeed.fromJson(Map<String, dynamic> j) => PromoFeed(
        store: '${j['store'] ?? fallback.store}',
        url: '${j['url'] ?? fallback.url}',
        items: [
          for (final e in (j['items'] as List? ?? const []))
            if (e is Map) PromoItem.fromJson(e.cast<String, dynamic>()),
        ].where((i) => i.title.isNotEmpty && i.url.startsWith('https://')).toList(),
      );

  /// Mağazaya giden bağlantıya kaynak etiketi ekler (kişisel bilgi içermez).
  static Uri tagged(String url) {
    final u = Uri.parse(url);
    return u.replace(queryParameters: {...u.queryParameters, 'utm_source': 'netice', 'utm_medium': 'app'});
  }
}

class PromoService {
  PromoService._();
  static final instance = PromoService._();

  /// Ürün listesi depoda tutulur; değiştirmek için promo/oneriler.json
  /// güncellenip ana dala alınır.
  static const feedUrl = 'https://raw.githubusercontent.com/emrgngr/netice/main/promo/oneriler.json';

  PromoFeed feed = PromoFeed.fallback;
  bool _started = false;

  Future<File> _cache() async {
    final d = await getApplicationSupportDirectory();
    return File('${d.path}${Platform.pathSeparator}oneriler.json');
  }

  /// Önbellekteki listeyi yükler, gerekiyorsa arka planda tazeler.
  Future<PromoFeed> load({void Function(PromoFeed)? onUpdate}) async {
    try {
      final f = await _cache();
      if (await f.exists()) {
        feed = PromoFeed.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
        final fresh = DateTime.now().difference(await f.lastModified()) < const Duration(hours: 20);
        if (fresh || _started) return feed;
      }
      if (_started) return feed;
      _started = true;
      final r = await http.get(Uri.parse(feedUrl)).timeout(const Duration(seconds: 6));
      if (r.statusCode == 200) {
        final next = PromoFeed.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
        await f.writeAsString(utf8.decode(r.bodyBytes));
        feed = next;
        onUpdate?.call(next);
      }
    } catch (_) {
      // Çevrimdışı ya da liste bozuk: elimizdekini göster.
    }
    return feed;
  }
}
