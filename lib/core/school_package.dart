// Okul / zümre paketi: aynı okuldan birden çok öğretmen birlikte alırsa
// öğretmen başına indirim. Satış kurum lisansıyla yapılır (lisans kodu
// Actions'taki "Kurum lisansı üret" göreviyle üretilir); uygulama fiyatı
// hesaplar ve teklif isteğini e-postayla gönderir.
import 'legal.dart';
import 'price_increase.dart';

class SchoolTier {
  final int minTeachers;
  final double discount;
  const SchoolTier(this.minTeachers, this.discount);
}

class SchoolPackage {
  SchoolPackage._();

  /// En az bu kadar öğretmenle paket başlar.
  static const minTeachers = 5;

  /// Bu sayıdan sonrası için özel teklif verilir.
  static const customFrom = 50;

  static const tiers = [
    SchoolTier(5, 0.25),
    SchoolTier(10, 0.35),
    SchoolTier(25, 0.45),
  ];

  /// Öğretmen sayısına göre indirim (pakete girmiyorsa 0).
  static double discountFor(int teachers) {
    var d = 0.0;
    for (final t in tiers) {
      if (teachers >= t.minTeachers) d = t.discount;
    }
    return d;
  }

  /// Öğretmen başına yıllık fiyat yazısı (ör. "299 TL / yıl").
  static String perTeacherText(String yearlyPriceText, int teachers) =>
      discountPriceText(yearlyPriceText, discountFor(teachers));

  /// Toplam yıllık tutar yazısı ("/ yıl" eki atılır).
  static String totalText(String yearlyPriceText, int teachers) =>
      multiplyPriceText(perTeacherText(yearlyPriceText, teachers), teachers.toDouble()).replaceFirst(RegExp(r'\s*/.*$'), '');

  /// Teklif isteği e-postası.
  static Uri offerMail({
    required String subject,
    required String body,
  }) =>
      Uri(scheme: 'mailto', path: contactEmail, query: _q({'subject': subject, 'body': body}));

  static String _q(Map<String, String> m) =>
      m.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&');
}
