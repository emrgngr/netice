// Takvime bağlı kampanyalar: okul başı, Öğretmenler Günü, karne ve sınav
// dönemleri. Sunucu gerekmez; tarih cihazdan okunur. İndirimli kampanyalar
// mağazada yıllık aboneliklere eklenen tekliflerle (Google Play geliştirici
// teklifi, App Store teklif kodu) satılır.
import '../l10n/l10n.dart';

class Campaign {
  final String id;
  final String titleText;
  final String detailText;

  /// Başlangıç ve bitiş (ay, gün), ikisi de dahil.
  final (int, int) from;
  final (int, int) to;

  /// Yıllık planlarda ilk yıl indirimi (0 ise indirim yok).
  final double discount;

  /// Kampanya döneminde ilk kez kurulan uygulamaya verilen deneme süresi.
  final int trialDays;

  /// Sınav dönemi paketi öne çıkarılsın mı?
  final bool highlightTermPass;

  /// Google Play'de yıllık aboneliklerin temel planına eklenen teklifin kimliği.
  final String playOfferId;

  /// App Store Connect'te tanımlanan teklif kodu.
  final String appStoreOfferCode;

  const Campaign({
    required this.id,
    required this.titleText,
    required this.detailText,
    required this.from,
    required this.to,
    this.discount = 0,
    this.trialDays = 0,
    this.highlightTermPass = false,
    this.playOfferId = '',
    this.appStoreOfferCode = '',
  });

  String get title => tr(titleText);
  String get detail => tr(detailText);

  bool get hasDiscount => discount > 0 && playOfferId.isNotEmpty;

  static int _key(int m, int d) => m * 100 + d;

  bool activeOn(DateTime t) {
    final k = _key(t.month, t.day);
    final a = _key(from.$1, from.$2), b = _key(to.$1, to.$2);
    return a <= b ? k >= a && k <= b : k >= a || k <= b;
  }

  /// Kampanyanın [t] gününü içeren dönemdeki son günü.
  DateTime endFor(DateTime t) {
    var y = t.year;
    if (_key(from.$1, from.$2) > _key(to.$1, to.$2) && _key(t.month, t.day) >= _key(from.$1, from.$2)) y++;
    return DateTime(y, to.$1, to.$2);
  }

  /// [t] gününden kampanyanın son gününe kadar kalan gün (son gün dahil).
  int daysLeft(DateTime t) => endFor(t).difference(DateTime(t.year, t.month, t.day)).inDays + 1;

  static const all = <Campaign>[
    Campaign(
      id: 'okula-donus',
      titleText: 'Okula dönüş kampanyası',
      detailText: 'Yıllık planlarda ilk yıl %20 indirim · yeni kullanıcılara 30 gün ücretsiz deneme',
      from: (9, 1),
      to: (9, 30),
      discount: 0.20,
      trialDays: 30,
      playOfferId: 'okula-donus',
      appStoreOfferCode: 'OKUL20',
    ),
    Campaign(
      id: 'ogretmenler-gunu',
      titleText: 'Öğretmenler Günü\'ne özel',
      detailText: 'Yıllık planlarda ilk yıl %25 indirim',
      from: (11, 20),
      to: (11, 30),
      discount: 0.25,
      playOfferId: 'ogretmenler-gunu',
      appStoreOfferCode: 'OGRETMEN25',
    ),
    Campaign(
      id: 'karne-ocak',
      titleText: 'Karne dönemi kampanyası',
      detailText: 'Yıllık planlarda ilk yıl %20 indirim',
      from: (1, 5),
      to: (1, 31),
      discount: 0.20,
      playOfferId: 'karne-donemi',
      appStoreOfferCode: 'KARNE20',
    ),
    Campaign(
      id: 'sinav-donemi',
      titleText: 'Sınav dönemi',
      detailText: 'Yalnız sınav aylarında mı lazım? 3 aylık paketle o kadar ödeyin.',
      from: (3, 15),
      to: (5, 20),
      highlightTermPass: true,
    ),
    Campaign(
      id: 'karne-haziran',
      titleText: 'Karne dönemi kampanyası',
      detailText: 'Yıllık planlarda ilk yıl %20 indirim',
      from: (5, 21),
      to: (6, 30),
      discount: 0.20,
      playOfferId: 'karne-donemi',
      appStoreOfferCode: 'KARNE20',
    ),
  ];

  /// Bugün geçerli kampanya (yoksa null).
  static Campaign? current([DateTime? now]) {
    final t = now ?? DateTime.now();
    for (final c in all) {
      if (c.activeOn(t)) return c;
    }
    return null;
  }

  /// Uygulama [installed] gününde kurulduysa ücretsiz deneme süresi.
  static Duration trialFor(DateTime? installed, {Duration normal = const Duration(days: 14)}) {
    if (installed == null) return normal;
    final c = current(installed);
    return c != null && c.trialDays > normal.inDays ? Duration(days: c.trialDays) : normal;
  }
}
