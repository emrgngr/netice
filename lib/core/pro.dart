import 'dart:async';
import 'dart:io';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';

import '../bank/ai_questions.dart';
import 'campaigns.dart';
import 'price_increase.dart';
import 'referral.dart';
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
  aiQuestions('Nottan soru üretme', 'Yapay zekâ ders notunuzdan soru önerir · Pro\'da ayda 50, Pro + Yapay Zekâ\'da ayda 300 soru'),
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
/// * [proAiYearlyId]: "Pro + Yapay Zekâ" yıllık abonelik (ayda 300 soru).
/// * [aiPackId]: 200 soruluk ek soru paketi; tüketilebilir, süresi dolmaz.
/// * [proMonthlyId]: eski aylık abonelik; artık satılmaz, yalnızca daha önce
///   alanlar için tanınır.
const proMonthlyId = 'netice_pro_aylik';
const proYearlyId = 'netice_pro_yillik';
const proAiYearlyId = AppStore.aiYearlyProductId;
const proTermPassId = 'netice_donem_3ay';
const aiPackId = 'netice_yz_200';
const aiPackSize = 200;
const proSubscriptionIds = {proMonthlyId, proYearlyId, proAiYearlyId};
const proYearlyIds = {proYearlyId, proAiYearlyId};
const proProductIds = {proMonthlyId, proYearlyId, proAiYearlyId, proTermPassId, aiPackId};

/// Sınav dönemi paketinin süresi.
const termPassLength = Duration(days: 90);

class ProPlan {
  final String id;
  final String title;
  final String price;
  final String note;
  final ProductDetails? details;

  /// Davet indiriminde üstü çizili gösterilen normal fiyat.
  final String? oldPrice;
  const ProPlan(this.id, this.title, this.price, this.note, [this.details, this.oldPrice]);
}

/// Google Play abonelik teklifinin kimliği (temel plan için null).
String? playOfferId(ProductDetails d) {
  if (d is! GooglePlayProductDetails) return null;
  final i = d.subscriptionIndex;
  final offers = d.productDetails.subscriptionOfferDetails;
  if (i == null || offers == null || i >= offers.length) return null;
  return offers[i].offerId;
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

  /// [campaign] indirimliyse yıllık planlar onunla, değilse davet koduyla
  /// (yalnız Pro yıllık, %15) indirimli gösterilir.
  static List<ProPlan> plansFor(DateTime now, {bool invite = false, Campaign? campaign}) {
    final years = priceIncreaseYears(now);
    final yearly = tr('399 TL / yıl');
    final aiYearly = tr('699 TL / yıl');
    final yearlyNow = increasePriceText(yearly, years);
    final aiNow = increasePriceText(aiYearly, years);
    final c = campaign != null && campaign.hasDiscount ? campaign : null;
    ProPlan plan(String id, String title, String priceNow, String note) {
      if (c != null) {
        // Kampanya şeritte anlatılır; notta planın soru hakkı kalır.
        return ProPlan(id, title, discountPriceText(priceNow, c.discount), note, null, priceNow);
      }
      if (invite && id == proYearlyId) {
        return ProPlan(id, title, discountPriceText(priceNow, Referral.discount), tr('Davet indirimi %15 · ilk yıl'), null, priceNow);
      }
      return ProPlan(id, title, priceNow, note);
    }

    return [
      plan(proYearlyId, tr('Pro · yıllık'), yearlyNow,
          tr('Ayda yaklaşık {0} · ayda {1} yapay zekâ sorusu', [_monthly(yearlyNow), AiUsage.proMonthlyLimit])),
      plan(proAiYearlyId, tr('Pro + Yapay Zekâ · yıllık'), aiNow,
          tr('Ayda yaklaşık {0} · ayda {1} yapay zekâ sorusu', [_monthly(aiNow), AiUsage.aiMonthlyLimit])),
      ProPlan(proTermPassId, tr('Sınav dönemi paketi'), increasePriceText(tr('119 TL / 3 ay'), years),
          tr('Tek seferlik ödeme · kendiliğinden yenilenmez')),
    ];
  }

  /// "399 TL / yıl" → "33 TL" (aylık karşılığı, para birimiyle).
  static String _monthly(String yearlyText) {
    final noPeriod = yearlyText.replaceFirst(RegExp(r'\s*/.*$'), '');
    return multiplyPriceText(noPeriod, 1 / 12);
  }

  /// Bugünkü Pro yıllık önerilen fiyatı (okul paketi hesabı için).
  static String yearlyPriceText([DateTime? now]) => increasePriceText(tr('399 TL / yıl'), priceIncreaseYears(now ?? DateTime.now()));

  /// Ek soru paketinin önerilen fiyatı.
  static ProPlan aiPackFallback() => ProPlan(aiPackId, tr('Ek soru paketi'), tr('79 TL'),
      tr('{0} yapay zekâ sorusu · tek seferlik · süresi dolmaz', [aiPackSize]));

  /// Bugünkü kampanya (indirimli olsun olmasın).
  static Campaign? get campaign => Campaign.current();

  /// Arkadaşın davet kodu girilmiş mi (yıllık abonelikte %15 indirim)?
  bool get inviteApplied => _store?.appliedInvite != null && _store?.hasSubscription != true;

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
    final invite = inviteApplied;
    final camp = campaign;
    final fallback = plansFor(DateTime.now(), invite: invite, campaign: camp);
    final normal = plansFor(DateTime.now());
    if (!storeSupported) return fallback;
    try {
      final iap = InAppPurchase.instance;
      if (!await iap.isAvailable()) return fallback;
      final r = await iap.queryProductDetails(proProductIds).timeout(const Duration(seconds: 8));
      if (r.productDetails.isEmpty) return fallback;
      // Google Play her abonelik teklifini ayrı satır olarak verir: temel plan
      // (teklifsiz) normal fiyattır; kampanya ve davet teklifleri indirimlidir.
      final base = <String, ProductDetails>{};
      final offers = <(String, String), ProductDetails>{};
      for (final d in r.productDetails) {
        final offer = playOfferId(d);
        if (offer == null) {
          base.putIfAbsent(d.id, () => d);
        } else {
          offers[(d.id, offer)] = d;
        }
      }
      _aiPack = base[aiPackId];
      String per(String id) => proYearlyIds.contains(id) ? tr('yıl') : tr('3 ay');
      ProductDetails? offerFor(String id) {
        if (camp != null && camp.hasDiscount && offers[(id, camp.playOfferId)] != null) return offers[(id, camp.playOfferId)];
        if (invite && id == proYearlyId) return offers[(id, Referral.playOfferId)];
        return null;
      }

      return [
        for (final f in fallback)
          if (base[f.id] != null && offerFor(f.id) != null)
            ProPlan(f.id, f.title, '${offerFor(f.id)!.price} / ${per(f.id)}', f.note, offerFor(f.id),
                '${base[f.id]!.price} / ${per(f.id)}')
          else if (base[f.id] != null)
            // Teklif mağazada yoksa normal fiyat ve normal not gösterilir.
            ProPlan(f.id, f.title, '${base[f.id]!.price} / ${per(f.id)}', normal.firstWhere((n) => n.id == f.id).note, base[f.id])
          else
            f,
      ];
    } catch (_) {
      return fallback;
    }
  }

  ProductDetails? _aiPack;

  /// Ek soru paketi (mağaza fiyatıyla; okunamazsa önerilen fiyat).
  Future<ProPlan> aiPack() async {
    final f = aiPackFallback();
    if (!storeSupported) return f;
    if (_aiPack == null) {
      try {
        final iap = InAppPurchase.instance;
        if (await iap.isAvailable()) {
          final r = await iap.queryProductDetails({aiPackId}).timeout(const Duration(seconds: 8));
          _aiPack = r.productDetails.where((d) => d.id == aiPackId).firstOrNull;
        }
      } catch (_) {}
    }
    final d = _aiPack;
    return d == null ? f : ProPlan(aiPackId, f.title, d.price, f.note, d);
  }

  /// App Store'da kampanya indirimi teklif koduyla alınır.
  Future<void> redeemOfferCodeOnAppStore() => redeemInviteOnAppStore();

  /// App Store'da davet indirimi teklif koduyla alınır: kod panoya
  /// kopyalanır ve Apple'ın kod girme penceresi açılır.
  Future<void> redeemInviteOnAppStore() async {
    if (!Platform.isIOS) return;
    try {
      await InAppPurchase.instance
          .getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>()
          .presentCodeRedemptionSheet();
    } catch (_) {}
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
      if (d.id == proTermPassId || d.id == aiPackId) {
        // Dönem paketi ve ek soru paketi tekrar tekrar alınabilir.
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
        case PurchaseStatus.purchased when p.productID == aiPackId:
          await AiUsage.instance.load();
          AiUsage.instance.addCredits(aiPackSize);
          _events.add(tr('{0} soruluk ek paket eklendi. Teşekkürler!', [aiPackSize]));
        case PurchaseStatus.restored when p.productID == aiPackId:
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _store?.confirmPro(p.productID);
          // Davet koduyla alındıysa davet edene gönderilecek teşekkür kodu.
          if (p.status == PurchaseStatus.purchased && proYearlyIds.contains(p.productID)) _store?.onInvitePurchase();
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
