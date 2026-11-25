import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../l10n/l10n.dart';
import 'legal.dart';

/// Güncellemeleri kullanıcıya duyurma:
/// * "Bu sürümde yenilikler" penceresi: yeni sürüm ilk açıldığında [releaseNotes]
///   listesindeki maddeler bir kez gösterilir.
/// * "Yeni sürüm hazır" uyarısı: mağazada daha yeni sürüm varsa ana sayfada
///   kart çıkar. Son sürüm bilgisi `reklamlar` dalındaki surum/surum.json
///   dosyasından okunur (reklam akışıyla aynı yer, internet yoksa sessizce atlanır).
///   Dosyayı "Yeni sürümü duyur" iş akışı yazar; mağaza onayından SONRA çalıştırılır.

/// Bir sürümün yenilik maddesi. [platforms] boşsa her yerde gösterilir;
/// doluysa yalnız o platformlarda (android, ios, windows, macos).
class ReleaseItem {
  final String text;
  final Set<String> platforms;
  const ReleaseItem(this.text, [this.platforms = const {}]);
  bool get forThisPlatform => platforms.isEmpty || platforms.contains(currentPlatform);
}

class ReleaseNote {
  final String version;
  final List<ReleaseItem> items;
  const ReleaseNote(this.version, this.items);
}

String get currentPlatform => Platform.isAndroid
    ? 'android'
    : Platform.isIOS
        ? 'ios'
        : Platform.isMacOS
            ? 'macos'
            : Platform.isWindows
                ? 'windows'
                : 'linux';

/// Yeni sürüm çıkarken buraya en üste bir giriş eklenir ve [appVersion]
/// (legal.dart) ile pubspec.yaml'daki sürüm birlikte artırılır.
/// Metinler Türkçe yazılır, tr() ile çevrilir (l10n akışı).
List<ReleaseNote> releaseNotes() => [
      ReleaseNote('1.0.1', [
        ReleaseItem(tr('Netice Pro artık App Store\'da: yıllık abonelik, sınav dönemi paketi ve ek soru paketi uygulama içinden alınabilir.'), {'ios'}),
        ReleaseItem(tr('Uygulama yeni sürüm çıktığında size haber verir; yenilikleri bu pencerede görürsünüz.')),
        ReleaseItem(tr('Küçük düzeltmeler ve hız iyileştirmeleri.')),
      ]),
    ];

/// "1.2.10" > "1.2.9" karşılaştırması (sayı sayı).
int compareVersions(String a, String b) {
  List<int> parts(String v) => [for (final p in v.split('+').first.split('.')) int.tryParse(p.trim()) ?? 0];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

/// [from] sürümünden sonra gelen ve [to] dahil sürümlerin bu platforma ait maddeleri.
List<ReleaseItem> notesBetween(String from, String to, [List<ReleaseNote>? notes]) => [
      for (final n in notes ?? releaseNotes())
        if (compareVersions(n.version, from) > 0 && compareVersions(n.version, to) <= 0)
          for (final i in n.items)
            if (i.forThisPlatform) i,
    ];

class UpdateService extends ChangeNotifier {
  UpdateService._();
  static final instance = UpdateService._();

  static const feedUrl = 'https://raw.githubusercontent.com/emrgngr/netice/reklamlar/surum/surum.json';

  /// Mağazadaki en yeni sürüm (bu platform için); bilinmiyorsa null.
  String? latest;

  /// Testler ve önizleme için.
  void debugSetLatest(String? v) {
    latest = v;
    notifyListeners();
  }

  bool get updateAvailable => latest != null && compareVersions(latest!, appVersion) > 0;

  /// Güncellemenin yapılacağı yer: mağaza sayfası, bilgisayarda indirme sayfası.
  static String get updateUrl => switch (currentPlatform) {
        'android' => playStoreUrl,
        'ios' => appStoreUrl.isNotEmpty ? appStoreUrl : 'https://apps.apple.com/app/id6838423827',
        _ => '${websiteUrl.isNotEmpty ? websiteUrl : 'https://neticeoptik.pages.dev'}/indir.html',
      };

  DateTime? _lastCheck;

  Future<void> check() async {
    if (_lastCheck != null && DateTime.now().difference(_lastCheck!) < const Duration(hours: 6)) return;
    _lastCheck = DateTime.now();
    try {
      final r = await http
          .get(Uri.parse('$feedUrl?t=${DateTime.now().millisecondsSinceEpoch ~/ 3600000}'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is! Map) return;
      final v = j[currentPlatform] ?? j['hepsi'];
      latest = v is String && v.isNotEmpty ? v : null;
      notifyListeners();
    } catch (_) {
      // İnternet yok: uyarı gösterilmez.
    }
  }
}
