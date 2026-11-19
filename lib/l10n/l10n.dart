import 'dart:ui' show Locale, PlatformDispatcher, TextDirection;

import 'strings.g.dart';

/// Uygulamanın dilleri. Kaynak dil Türkçedir: çeviri tabloları Türkçe metni
/// anahtar olarak kullanır; çevirisi olmayan metin Türkçe kalır.
class AppLanguage {
  final String code;
  final String name; // kendi dilinde
  final String flag;
  const AppLanguage(this.code, this.name, this.flag);

  static const all = [
    AppLanguage('tr', 'Türkçe', '🇹🇷'),
    AppLanguage('en', 'English', '🇬🇧'),
    AppLanguage('az', 'Azərbaycan', '🇦🇿'),
    AppLanguage('de', 'Deutsch', '🇩🇪'),
    AppLanguage('ar', 'العربية', '🇸🇦'),
    AppLanguage('es', 'Español', '🇪🇸'),
    AppLanguage('ru', 'Русский', '🇷🇺'),
    AppLanguage('it', 'Italiano', '🇮🇹'),
    AppLanguage('fr', 'Français', '🇫🇷'),
    AppLanguage('zh', '中文', '🇨🇳'),
    AppLanguage('ja', '日本語', '🇯🇵'),
  ];

  static AppLanguage byCode(String c) => all.firstWhere((l) => l.code == c, orElse: () => all.first);
}

class L10n {
  static String _code = 'tr';
  static Map<String, String> _map = const {};

  /// Etkin dil kodu.
  static String get code => _code;
  static Locale get locale => Locale(_code);
  static bool get rtl => _code == 'ar';
  static TextDirection get direction => rtl ? TextDirection.rtl : TextDirection.ltr;

  /// [code] null ise cihazın dili (desteklenmiyorsa İngilizce, Türkçe cihazda Türkçe).
  static void use(String? code) {
    final c = code ?? deviceLanguage();
    _code = AppLanguage.all.any((l) => l.code == c) ? c : 'en';
    _map = translations[_code] ?? const {};
  }

  static String deviceLanguage() {
    final c = PlatformDispatcher.instance.locale.languageCode;
    return AppLanguage.all.any((l) => l.code == c) ? c : 'en';
  }

  static String lookup(String source) => _map[source] ?? source;

  /// Ondalık ayırıcı: virgül kullanan diller ve nokta kullananlar.
  static String get decimal => const {'en', 'zh', 'ja', 'ar'}.contains(_code) ? '.' : ',';

  /// Ülkenin alışık olduğu tarih biçimi.
  static String date(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return switch (_code) {
      'zh' || 'ja' => '${d.year}/${two(d.month)}/${two(d.day)}',
      'en' || 'fr' || 'es' || 'it' || 'ar' => '${two(d.day)}/${two(d.month)}/${d.year}',
      _ => '${two(d.day)}.${two(d.month)}.${d.year}',
    };
  }
}

/// Metni etkin dile çevirir. Yer tutucular {0}, {1}… [args] ile doldurulur.
String tr(String source, [List<Object?> args = const []]) {
  var s = L10n.lookup(source);
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', '${args[i]}');
  }
  return s;
}
