import 'dart:async';
import 'dart:io';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';

import '../bank/ai_questions.dart';
import 'campaigns.dart';
import 'price_increase.dart';
import 'legal.dart';
import 'ms_store.dart';
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
  deviceSync('Cihazlar arası eşitleme', 'Telefon, tablet ve bilgisayarınızda aynı sınıflar ve sınavlar'),
  gradeExport('Classroom ve Moodle\'a not aktarma', 'Notlar tek dokunuşla Google Classroom\'a ya da Moodle not defterine'),
  advancedCharts('Gelişmiş grafikler', 'Pasta, madde haritası, puan yayılımı, kazanım radarı'),
  detailedStats('Ayrıntılı sınıf istatistikleri', 'Sınıf sınıf yayılım ve düzeyler, gelişim çizgileri, öğrenci sıralamaları'),
  officialHeader('Resmi yazı başlığı', 'Kurumunuzun resmi başlığı ve imza alanı'),
  commonExam('Ortak sınav', 'Tüm şubeler aynı sınavı okur, sonuçlar tek raporda birleşir'),
  adminPanel('Kurum yönetici paneli', 'Tüm şubeler, sınavlar ve risk altındaki öğrenciler tek ekranda'),
  bookletVariants('A–H kitapçık türleri', 'Soruları ve şıkları karıştırılmış sekize kadar kitapçık, hap bilgi eki'),
  studyTips('Zayıf konu föyü', 'Zayıf konuların hap bilgileri karnede ve çalışma föyünde'),
  personalReview('Kişiye özel tekrar testi', 'Her öğrenciye kendi yanlışlarının benzer soruları, soru bankasından'),
  outcomeTracking('Kazanım takip çizelgesi', 'Dönem boyunca her kazanımın sınıf ve öğrenci bazında gelişimi'),
  wordExport('Word\'e aktarma', 'Kitapçığı düzenlenebilir Word (.docx) belgesi olarak kaydedin'),
  lanSync('Wi-Fi ile eşitleme', 'Aynı ağdaki öğretmenlerle internetsiz, dosyasız sonuç toplama'),
  bulkParent('Velilere toplu gönderim', 'Bütün sınıfın karnelerini sırayla, hazır mesajla gönderin'),
  aiQuestions('Nottan soru üretme', 'Yapay zekâ ders notunuzdan soru önerir · Pro\'da ayda 50, Pro + Yapay Zekâ\'da ayda 300 soru'),
  noAds('Pro\'da hiç reklam yok', 'Kendi tanıtımlarımız da gösterilmez. Ücretsiz sürümde de üçüncü taraf reklam yok.');

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

  /// Abonelik mağazası olan platformlar (Mac App Store dahil). Windows'ta
  /// Pro, program Microsoft Store'dan kurulduysa Store'dan satın alınır;
  /// kurulum programıyla kurulan sürümde kurum lisans koduyla açılır.
  static bool get storeSupported =>
      !salesDisabled && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || _msStore);

  /// Windows'ta program Microsoft Store paketinden mi çalışıyor ([attach] belirler).
  static bool _msStore = false;
  static bool get msStore => _msStore;

  /// Microsoft Store'da ürün kimliği → Store kimliği (9N…).
  final _msIds = <String, String>{};

  /// Mağaza satışı geçici olarak kapalı derleme (`--dart-define=SATIS_KAPALI=true`).
  /// App Store'un ücretli uygulama anlaşması onaylanana kadar iPhone sürümü
  /// satın alma bölümleri olmadan gönderilir: Pro ekranı özellikleri tanıtır,
  /// fiyat, satın alma, davet indirimi ve okul paketi teklifi gösterilmez.
  /// Deneme ve kurum lisansı (kuruma doğrudan satılan lisans) çalışmaya devam eder.
  static const bool salesDisabled = bool.fromEnvironment('SATIS_KAPALI');

  AppStore? _store;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  final _events = StreamController<String>.broadcast();

  /// Arayüze kısa bilgi mesajları ("Pro etkinleştirildi" vb.).
  Stream<String> get events => _events.stream;

  Future<void> attach(AppStore store) async {
    _store = store;
    if (Platform.isWindows && !salesDisabled) {
      _msStore = await MsStore.packaged();
      if (_msStore) await _syncMsLicenses();
      return;
    }
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
    if (_msStore) return _msPlans(normal);
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
    if (_msStore) {
      await _msLoad();
      final p = _msProducts[aiPackId];
      return p == null ? f : ProPlan(aiPackId, f.title, p.price, f.note, _msDetails(p));
    }
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
    if (salesDisabled) return tr('Pro aboneliği yakında App Store\'da.');
    if (!storeSupported) {
      return tr('Windows\'ta Pro, Microsoft Store\'dan kurulan Netice\'den satın alınır. Kurum lisans kodunuz varsa Profil > Kurum lisansı bölümüne girin. Sorularınız için: {0}', [contactEmail]);
    }
    if (_msStore) return _msBuy(plan);
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
    if (_msStore) {
      final err = await _syncMsLicenses();
      return err;
    }
    try {
      await InAppPurchase.instance.restorePurchases();
      return null;
    } catch (e) {
      return tr('Geri yüklenemedi: {0}', [e]);
    }
  }

  // ---------------------------------------------------------------------
  // Microsoft Store (Windows)
  // ---------------------------------------------------------------------

  final _msProducts = <String, MsProduct>{};

  Future<void> _msLoad() async {
    if (_msProducts.isNotEmpty) return;
    try {
      for (final p in await MsStore.products().timeout(const Duration(seconds: 12))) {
        if (!proProductIds.contains(p.token)) continue;
        _msProducts[p.token] = p;
        _msIds[p.token] = p.storeId;
      }
    } catch (_) {}
  }

  /// Satın alma düğmesinin taşıdığı ürün bilgisi (fiyat Store'dan).
  ProductDetails _msDetails(MsProduct p) =>
      ProductDetails(id: p.token, title: p.title, description: '', price: p.price, rawPrice: 0, currencyCode: '');

  Future<List<ProPlan>> _msPlans(List<ProPlan> normal) async {
    await _msLoad();
    String per(String id) => proYearlyIds.contains(id) ? tr('yıl') : tr('3 ay');
    return [
      for (final f in normal)
        if (_msProducts[f.id] != null)
          ProPlan(f.id, f.title, '${_msProducts[f.id]!.price} / ${per(f.id)}', f.note, _msDetails(_msProducts[f.id]!))
        else
          f,
    ];
  }

  Future<String?> _msBuy(ProPlan plan) async {
    await _msLoad();
    final id = _msIds[plan.id];
    if (id == null) return tr('Bu ürün Microsoft Store\'da henüz açılmadı.');
    try {
      final r = await MsStore.purchase(id);
      switch (r) {
        case 'Succeeded':
        case 'AlreadyPurchased':
          // Tüketilebilir ürün (dönem/soru paketi) hemen verilir ve Store'a
          // teslim edildi bildirilir; abonelik lisanstan doğrulanır.
          if (plan.id == proTermPassId || plan.id == aiPackId) {
            await _msGrant(plan.id, id);
          } else {
            await _syncMsLicenses(purchased: true);
          }
          return null;
        case 'NotPurchased':
          return null; // Kullanıcı vazgeçti.
        case 'NetworkError':
          return tr('İnternet bağlantısı yok. Bağlanıp tekrar deneyin.');
        default:
          return tr('Satın alma tamamlanamadı.');
      }
    } catch (e) {
      return tr('Satın alma başlatılamadı: {0}', [e]);
    }
  }

  /// Tüketilebilir paketi Store'a teslim edildi bildirir ve verir. Bildirim
  /// başarısızsa verilmez; bir sonraki açılışta ya da satın almada yeniden denenir.
  Future<void> _msGrant(String token, String storeId) async {
    final r = await MsStore.fulfill(storeId);
    if (r != 'Succeeded') return;
    if (token == proTermPassId) {
      _store?.addTermPass(DateTime.now());
      _events.add(tr('Sınav dönemi paketi etkinleştirildi. Teşekkürler!'));
    } else {
      await AiUsage.instance.load();
      AiUsage.instance.addCredits(aiPackSize);
      _events.add(tr('{0} soruluk ek paket eklendi. Teşekkürler!', [aiPackSize]));
    }
  }

  /// Store lisanslarını okur: etkin abonelik Pro'yu doğrular; teslim
  /// edilmemiş tüketilebilir ürünler (dönem paketi, soru paketi) burada
  /// verilir ve Store'a teslim edildi bildirilir. Hata olursa metni döner.
  Future<String?> _syncMsLicenses({bool purchased = false}) async {
    try {
      final list = await MsStore.licenses().timeout(const Duration(seconds: 12));
      var pro = false;
      for (final l in list) {
        if (!l.active || !proProductIds.contains(l.token)) continue;
        _msIds[l.token] = l.storeId;
        if (l.token == proTermPassId || l.token == aiPackId) {
          // Teslim edilmemiş kalmış paket (ör. program satın alma sırasında kapandı).
          await _msGrant(l.token, l.storeId);
        } else {
          _store?.confirmPro(l.token);
          pro = true;
        }
      }
      if (pro && purchased) _events.add(tr('Netice Pro etkinleştirildi. Teşekkürler!'));
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
