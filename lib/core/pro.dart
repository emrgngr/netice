import 'dart:async';
import 'dart:io';

import 'package:in_app_purchase/in_app_purchase.dart';

import 'store.dart';
import '../l10n/l10n.dart';

/// Netice Pro: okuma ve temel sonuçlar ücretsizdir; aşağıdaki özellikler
/// Pro aboneliği ister.
enum ProFeature {
  termReport('Dönem raporu', 'Dönem sonu notu, ağırlıklı ortalama ve Excel'),
  studentCards('Öğrenci ve kazanım karnesi', 'Her öğrenci için ayrıntılı PDF karne'),
  parentShare('Karneyi veliye gönder', 'WhatsApp veya e-postayla tek dokunuşla'),
  cloudBackup('Google Drive yedeği', 'Kendi hesabınıza her gün otomatik yedek'),
  advancedCharts('Gelişmiş grafikler', 'Pasta, madde haritası, puan yayılımı, kazanım radarı'),
  officialHeader('Resmi yazı başlığı', 'Kurumunuzun resmi başlığı ve imza alanı'),
  noAds('Reklamsız kullanım', 'Hiçbir sayfada reklam gösterilmez');

  final String _title;
  final String _detail;
  const ProFeature(this._title, this._detail);

  String get title => tr(_title);
  String get detail => tr(_detail);
}

/// Mağazada tanımlanacak abonelik kimlikleri (Google Play Console >
/// Para kazanma > Abonelikler).
const proMonthlyId = 'netice_pro_aylik';
const proYearlyId = 'netice_pro_yillik';
const proProductIds = {proMonthlyId, proYearlyId};

class ProPlan {
  final String id;
  final String title;
  final String price;
  final String note;
  final ProductDetails? details;
  const ProPlan(this.id, this.title, this.price, this.note, [this.details]);
}

/// Satın alma ve abonelik doğrulaması. Doğrulama telefonda Google Play
/// üzerinden yapılır; internet olmadığında son doğrulama 40 gün geçerlidir,
/// böylece çevrimdışı kullanım kesilmez.
class ProService {
  ProService._();
  static final instance = ProService._();

  /// Mağaza fiyatı okunamazsa gösterilecek önerilen fiyatlar.
  static List<ProPlan> get fallbackPlans => [
    ProPlan(proYearlyId, tr('Yıllık'), tr('799 TL / yıl'), tr('Ayda yaklaşık 67 TL · en avantajlı')),
    ProPlan(proMonthlyId, tr('Aylık'), tr('99 TL / ay'), tr('İstediğiniz zaman iptal')),
  ];

  /// Abonelik yalnızca mağaza olan platformlarda satılır. Bilgisayar
  /// sürümünde Pro özellikleri şimdilik açıktır.
  static bool get storeSupported => Platform.isAndroid || Platform.isIOS;

  AppStore? _store;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  final _events = StreamController<String>.broadcast();

  /// Arayüze kısa bilgi mesajları ("Pro etkinleştirildi" vb.).
  Stream<String> get events => _events.stream;

  Future<void> attach(AppStore store) async {
    _store = store;
    if (!storeSupported) return;
    try {
      final iap = InAppPurchase.instance;
      if (!await iap.isAvailable()) return;
      _sub ??= iap.purchaseStream.listen(_onPurchases, onError: (_) {});
      // Açılışta sessizce yenile; aktif abonelik varsa süre uzar.
      await iap.restorePurchases();
    } catch (_) {
      // Çevrimdışı: son doğrulama geçerli kalır.
    }
  }

  Future<List<ProPlan>> plans() async {
    if (!storeSupported) return fallbackPlans;
    try {
      final iap = InAppPurchase.instance;
      if (!await iap.isAvailable()) return fallbackPlans;
      final r = await iap.queryProductDetails(proProductIds).timeout(const Duration(seconds: 8));
      if (r.productDetails.isEmpty) return fallbackPlans;
      final byId = <String, ProductDetails>{};
      for (final d in r.productDetails) {
        byId.putIfAbsent(d.id, () => d);
      }
      return [
        for (final f in fallbackPlans)
          if (byId[f.id] != null)
            ProPlan(f.id, f.title, '${byId[f.id]!.price} / ${f.id == proYearlyId ? tr('yıl') : tr('ay')}', f.note, byId[f.id])
          else
            f,
      ];
    } catch (_) {
      return fallbackPlans;
    }
  }

  /// Satın almayı başlatır. Sonuç [events] ve mağaza durumuyla gelir.
  Future<String?> buy(ProPlan plan) async {
    if (!storeSupported) return tr('Abonelik telefondaki Google Play üzerinden alınır.');
    final d = plan.details;
    if (d == null) {
      return tr('Abonelik henüz mağazada açılmadı. Uygulama Google Play\'de yayımlanınca satın alınabilecek.');
    }
    try {
      await InAppPurchase.instance.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: d));
      return null;
    } catch (e) {
      return tr('Satın alma başlatılamadı: {0}', [e]);
    }
  }

  Future<String?> restore() async {
    if (!storeSupported) return tr('Geri yükleme telefonda yapılır.');
    try {
      await InAppPurchase.instance.restorePurchases();
      return null;
    } catch (e) {
      return tr('Geri yüklenemedi: {0}', [e]);
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      if (!proProductIds.contains(p.productID)) continue;
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _store?.confirmPro(p.productID);
          if (p.status == PurchaseStatus.purchased) _events.add(tr('Netice Pro etkinleştirildi. Teşekkürler!'));
        case PurchaseStatus.error:
          _events.add(tr('Satın alma tamamlanamadı.'));
        case PurchaseStatus.canceled:
        case PurchaseStatus.pending:
          break;
      }
      if (p.pendingCompletePurchase) {
        try {
          await InAppPurchase.instance.completePurchase(p);
        } catch (_) {}
      }
    }
  }
}
