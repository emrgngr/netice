import 'dart:async';
import 'dart:io';

import 'package:in_app_purchase/in_app_purchase.dart';

import 'price_increase.dart';
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
  commonExam('Ortak sınav', 'Tüm şubeler aynı sınavı okur, sonuçlar tek raporda birleşir'),
  adminPanel('Kurum yönetici paneli', 'Tüm şubeler, sınavlar ve risk altındaki öğrenciler tek ekranda'),
  bookletVariants('A–H kitapçık türleri', 'Soruları ve şıkları karıştırılmış sekize kadar kitapçık, hap bilgi eki'),
  studyTips('Zayıf konu föyü', 'Zayıf konuların hap bilgileri karnede ve çalışma föyünde'),
  aiQuestions('Nottan soru üretme', 'Yapay zekâ ders notunuzdan çoktan seçmeli soru önerir · ayda 300 soru'),
  noAds('Reklamsız kullanım', 'Hiçbir sayfada reklam gösterilmez');

  final String _title;
  final String _detail;
  const ProFeature(this._title, this._detail);

  String get title => tr(_title);
  String get detail => tr(_detail);
}

/// Mağazada tanımlanacak ürün kimlikleri.
///
/// * [proYearlyId]: yıllık abonelik (Google Play Console > Para kazanma >
///   Abonelikler).
/// * [proTermPassId]: 3 aylık "sınav dönemi paketi"; tek seferlik ürün,
///   kendiliğinden yenilenmez (Para kazanma > Uygulama içi ürünler, tüketilebilir).
/// * [proMonthlyId]: eski aylık abonelik; artık satılmaz, yalnızca daha önce
///   alanlar için tanınır.
const proMonthlyId = 'netice_pro_aylik';
const proYearlyId = 'netice_pro_yillik';
const proTermPassId = 'netice_donem_3ay';
const proSubscriptionIds = {proMonthlyId, proYearlyId};
const proProductIds = {proMonthlyId, proYearlyId, proTermPassId};

/// Sınav dönemi paketinin süresi.
const termPassLength = Duration(days: 90);

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

  /// Mağaza fiyatı okunamazsa gösterilecek önerilen fiyatlar. Başlangıç
  /// fiyatları her yıl %30 artırılarak gösterilir (bkz. price_increase.dart).
  static List<ProPlan> get fallbackPlans => plansFor(DateTime.now());

  static List<ProPlan> plansFor(DateTime now) {
    final years = priceIncreaseYears(now);
    final yearly = tr('299 TL / yıl');
    return [
      ProPlan(proYearlyId, tr('Yıllık'), increasePriceText(yearly, years),
          monthlyNoteText(tr('Ayda yaklaşık 25 TL · en avantajlı'), yearly, years)),
      ProPlan(proTermPassId, tr('Sınav dönemi paketi'), increasePriceText(tr('119 TL / 3 ay'), years),
          tr('Tek seferlik ödeme · kendiliğinden yenilenmez')),
    ];
  }

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
            ProPlan(f.id, f.title, '${byId[f.id]!.price} / ${f.id == proYearlyId ? tr('yıl') : tr('3 ay')}', f.note, byId[f.id])
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
      final param = PurchaseParam(productDetails: d);
      if (d.id == proTermPassId) {
        // Dönem paketi tekrar tekrar alınabilir; her alımda süre 90 gün uzar.
        await InAppPurchase.instance.buyConsumable(purchaseParam: param);
      } else {
        await InAppPurchase.instance.buyNonConsumable(purchaseParam: param);
      }
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
        case PurchaseStatus.purchased when p.productID == proTermPassId:
          _store?.addTermPass(DateTime.now());
          _events.add(tr('Sınav dönemi paketi etkinleştirildi. Teşekkürler!'));
        case PurchaseStatus.restored when p.productID == proTermPassId:
          break; // Tek seferlik paket geri yüklenmez; süresi cihazda tutulur.
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
