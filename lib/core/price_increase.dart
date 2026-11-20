/// Netice Pro fiyatı her yıl %30 artar.
///
/// Gerçek abonelik fiyatı Google Play / App Store'da durur ve her yıl
/// `.github/workflows/fiyat-artisi.yml` görevi tarafından mağazada artırılır.
/// Bu dosya yalnızca mağaza fiyatı okunamadığında uygulamada gösterilen
/// önerilen fiyatı aynı kurala göre günceller.
library;

/// Fiyatların ilk belirlendiği gün (99 TL/ay, 799 TL/yıl). Her yıl bu
/// günün yıl dönümünde fiyat %30 artar. Mağaza görevi de aynı günü kullanır.
final proPriceBaseDate = DateTime(2026, 11, 19);

/// Yıllık artış oranı (%30).
const proYearlyIncrease = 0.30;

/// [now] tarihine kadar dolan tam yıl sayısı.
int priceIncreaseYears(DateTime now, {DateTime? base}) {
  final b = base ?? proPriceBaseDate;
  if (now.isBefore(b)) return 0;
  var years = now.year - b.year;
  if (now.month < b.month || (now.month == b.month && now.day < b.day)) years--;
  return years < 0 ? 0 : years;
}

/// Bir fiyat sayısını (ör. 799) [years] yıl %30 artırıp, aslına benzer
/// biçimde yuvarlar: 799 → 1039, 79,99 → 103,99, 7 990 → 10 390, 1,200 → 1,600.
double increasedAmount(double base, int years, {required bool cents}) {
  if (years <= 0) return base;
  var x = base;
  for (var i = 0; i < years; i++) {
    x *= 1 + proYearlyIncrease;
  }
  if (cents) {
    // ,99 ile biten fiyatlar: tam sayıya yuvarla, 0,01 düş.
    final whole = x.round();
    final frac = ((base - base.truncate()) * 100).round();
    return frac == 99 ? whole - 0.01 : (x * 100).round() / 100;
  }
  final n = base.round();
  var zeros = 0;
  var m = n;
  while (m > 0 && m % 10 == 0) {
    zeros++;
    m ~/= 10;
  }
  var step = 1;
  for (var i = 0; i < zeros; i++) {
    step *= 10;
  }
  // 799 gibi 9'la bitenlerde sonuç da 9'la bitsin.
  if (m % 10 == 9) step *= 10;
  final rest = n % step;
  final r = ((x - rest) / step).round() * step + rest;
  return r.toDouble();
}

final _number = RegExp(r'\d[\d.,  ]*\d|\d');

class _Num {
  final Match match;
  final double value;
  final int decimals;
  final String? decSep;
  final String? group;
  _Num(this.match, this.value, this.decimals, this.decSep, this.group);

  static _Num? parse(String text) {
    final match = _number.firstMatch(text);
    if (match == null) return null;
    final raw = match.group(0)!;
    // Ondalık ayraç: sonda 1–2 basamaklı , ya da . varsa (9,800 binlik sayılır).
    final dec = RegExp(r'[.,](\d{1,2})$').firstMatch(raw);
    final intPart = dec == null ? raw : raw.substring(0, dec.start);
    final digits = intPart.replaceAll(RegExp(r'[^\d]'), '');
    final decimals = dec?.group(1)!.length ?? 0;
    final value = double.parse(decimals == 0 ? digits : '$digits.${dec!.group(1)}');
    return _Num(match, value, decimals, dec == null ? null : raw[dec.start],
        RegExp(r'[.,  ]').firstMatch(intPart)?.group(0));
  }

  /// Yeni tutarı aynı yazım biçimiyle yerine koyar.
  String replace(String text, double amount) {
    final parts = amount.toStringAsFixed(decimals).split('.');
    var whole = parts[0];
    if (group != null && whole.length > 3) {
      final b = StringBuffer();
      for (var i = 0; i < whole.length; i++) {
        if (i > 0 && (whole.length - i) % 3 == 0) b.write(group);
        b.write(whole[i]);
      }
      whole = b.toString();
    }
    final out = decimals > 0 ? '$whole${decSep ?? '.'}${parts[1]}' : whole;
    return text.replaceRange(match.start, match.end, out);
  }
}

/// Çevrilmiş bir fiyat yazısındaki ilk sayıyı artırır; para birimi, ayraçlar
/// ve diğer yazılar aynen kalır. "799 TL / yıl" → "1039 TL / yıl".
String increasePriceText(String text, int years) {
  if (years <= 0) return text;
  final n = _Num.parse(text);
  if (n == null) return text;
  return n.replace(text, increasedAmount(n.value, years, cents: n.decimals > 0));
}

/// "Ayda yaklaşık 67 TL" notunu artırılmış yıllık fiyata göre yeniden yazar.
String monthlyNoteText(String note, String yearlyText, int years) {
  if (years <= 0) return note;
  final y = _Num.parse(yearlyText);
  final n = _Num.parse(note);
  if (y == null || n == null) return note;
  final yearly = increasedAmount(y.value, years, cents: y.decimals > 0);
  return n.replace(note, yearly / 12);
}
