import 'dart:io';

import 'package:flutter/services.dart';

/// Microsoft Store'daki bir Pro eklentisi.
class MsProduct {
  /// Partner Center'da verilen ürün kimliği (ör. netice_pro_yillik).
  final String token;

  /// Store kimliği (9N…); satın alma bununla başlatılır.
  final String storeId;
  final String title;
  final String price;
  final bool subscription;
  const MsProduct(this.token, this.storeId, this.title, this.price, this.subscription);
}

/// Bu kullanıcının bir eklenti lisansı.
class MsLicense {
  final String token;
  final String storeId;
  final bool active;
  final DateTime? expires;
  const MsLicense(this.token, this.storeId, this.active, this.expires);
}

/// Windows'ta Microsoft Store satın alma köprüsü (windows/msstore).
///
/// Yalnız program Microsoft Store'dan kurulduğunda (MSIX paketi) çalışır;
/// kurulum programıyla kurulan sürümde [packaged] false döner ve Pro kurum
/// lisans koduyla açılır.
class MsStore {
  static const _ch = MethodChannel('netice/msstore');
  static bool? _packaged;

  static Future<bool> packaged() async {
    if (!Platform.isWindows) return false;
    if (_packaged != null) return _packaged!;
    try {
      _packaged = await _ch.invokeMethod<bool>('isPackaged') ?? false;
    } catch (_) {
      _packaged = false;
    }
    return _packaged!;
  }

  static Future<List<MsProduct>> products() async {
    final r = await _ch.invokeMapMethod<String, Object?>('products');
    final items = (r?['items'] as List?) ?? const [];
    return [
      for (final m in items.whereType<Map>())
        MsProduct('${m['token'] ?? ''}', '${m['storeId'] ?? ''}', '${m['title'] ?? ''}', '${m['price'] ?? ''}',
            m['subscription'] == true),
    ];
  }

  static Future<List<MsLicense>> licenses() async {
    final r = await _ch.invokeMapMethod<String, Object?>('licenses');
    final items = (r?['items'] as List?) ?? const [];
    return [
      for (final m in items.whereType<Map>())
        MsLicense('${m['token'] ?? ''}', '${m['storeId'] ?? ''}', m['active'] == true, _date(m['expiresMs'])),
    ];
  }

  /// Sonuç: Succeeded, AlreadyPurchased, NotPurchased, NetworkError,
  /// ServerError ya da "Error: …".
  static Future<String> purchase(String storeId) async =>
      await _ch.invokeMethod<String>('purchase', {'storeId': storeId}) ?? 'Error';

  /// Tüketilebilir ürünü (dönem paketi, soru paketi) teslim edildi bildirir.
  static Future<String> fulfill(String storeId) async =>
      await _ch.invokeMethod<String>('fulfill', {'storeId': storeId}) ?? 'Error';

  static DateTime? _date(Object? ms) {
    if (ms is! int || ms <= 0) return null;
    // Süresiz lisanslarda Store çok uzak bir tarih verir.
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return d.year > 9000 ? null : d;
  }
}
