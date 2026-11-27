import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Netice'nin kendi reklamları (reklam ağı yok, kullanıcı izlenmez).
///
/// Reklam listesi depodaki `reklamlar` dalında `reklam/reklamlar.json`
/// dosyasındadır. Uygulama saatte en çok bir kez bu herkese açık listeyi ve
/// içindeki görsel/videoları indirir, cihazda saklar; internet yokken son
/// indirilenler gösterilir. Liste uygulamadaki "Reklam yönetimi" ekranından
/// düzenlenip yayınlanır (bkz. AdAdmin).
/// Sabit görsel, slider (birden çok görsel sırayla değişir) ya da video.
enum AdType { image, slider, video }

/// Slider geçiş çeşitleri.
enum SlideStyle {
  slide('kaydir', 'Kaydırma', 'Görseller sağdan sola kayar'),
  fade('sol', 'Yumuşak geçiş', 'Görsel solarak yenisine dönüşür'),
  zoom('yakinlas', 'Yakınlaşma', 'Hafif yakınlaşarak yenisi belirir'),
  flip('cevir', 'Kart çevirme', 'Görsel kart gibi dönerek değişir'),
  vertical('dikey', 'Dikey kayma', 'Görseller aşağıdan yukarı kayar');

  final String key;
  final String label;
  final String detail;
  const SlideStyle(this.key, this.label, this.detail);

  static SlideStyle byKey(String? k) => values.where((v) => v.key == k).firstOrNull ?? SlideStyle.slide;
}

/// Şerit: sayfanın altında ince bant (önerilen 1200×240).
/// Kart: sayfa içinde büyük kutu (önerilen 1280×720).
enum AdFormat { banner, card }

/// Reklam gösterilebilen sayfalar. Okuma (kamera, kâğıt kontrolü) ekranları
/// bilerek reklamsızdır.
enum AdPage {
  home('ana_sayfa', 'Ana sayfa'),
  classes('siniflar', 'Sınıflar'),
  exam('sinav', 'Sınav sonuçları'),
  student('ogrenci', 'Öğrenci ayrıntısı'),
  term('donem', 'Dönem sonu raporu'),
  compare('karsilastirma', 'Şube karşılaştırması'),
  help('yardim', 'Yardım'),
  profile('profil', 'Profil'),
  settings('ayarlar', 'Ayarlar');

  final String key;
  final String label;
  const AdPage(this.key, this.label);

  static AdPage? byKey(String k) => values.where((p) => p.key == k).firstOrNull;
}

/// Reklamın kime ve ne zaman gösterileceği.
class AdAudience {
  /// Uygulama dili (tr, en…).
  final String lang;

  /// Cihazın ülke kodu (TR, DE…), bilinmiyorsa boş.
  final String country;

  /// Kurum türü (InstitutionType.name).
  final String institution;
  final DateTime now;
  const AdAudience({this.lang = '', this.country = '', this.institution = '', required this.now});
}

class Ad {
  final String id;

  /// Yalnızca yönetim ekranında görünen ad.
  final String name;
  final AdType type;

  /// Görsel/video adresi (https) ya da henüz yayınlanmamış taslakta cihazdaki dosya yolu.
  final String media;

  /// Dokununca açılacak adres (boş olabilir).
  final String link;
  final AdFormat format;

  /// Boşsa tüm sayfalarda gösterilir.
  final List<AdPage> pages;
  final bool active;
  final DateTime? start;
  final DateTime? end;

  /// Görselin ekranda kalma süresi (saniye); birden çok reklam dönüşümlü gösterilir.
  /// Slider'da her görselin süresidir (varsayılan 3 sn).
  final int seconds;

  /// Slider görselleri (sırayla). Diğer türlerde boştur.
  final List<String> slides;
  final SlideStyle style;

  /// Görselin üstündeki düğme yazısı (boşsa düğme yok) ve kopyalanan indirim kodu.
  final String cta;
  final String code;

  /// Bitiş tarihi yaklaşınca köşede "Son 2 gün" rozeti.
  final bool countdown;

  /// Gece modunda gösterilecek görsel (yalnız sabit görsel; boş olabilir).
  final String mediaDark;

  /// A/B: ikinci görsel (yalnız sabit görsel; boşsa yarıştırma yok).
  final String mediaB;

  /// Hedefleme: boş liste herkes demektir.
  final List<String> languages;
  final List<String> countries;
  final List<String> institutions;

  /// Aynı cihazda günde en çok kaç kez gösterilsin (0: sınırsız).
  final int dailyCap;

  /// Öncelik 1–5: büyük olan daha sık gösterilir.
  final int weight;

  /// Gösterim saatleri [hourFrom, hourTo) ve haftanın günleri (1 Pzt … 7 Paz; boş: her gün).
  final int hourFrom;
  final int hourTo;
  final List<int> weekdays;

  /// Taslak: yalnız yöneticinin cihazında kalır, yayınlanmaz.
  final bool draft;

  const Ad({
    required this.id,
    this.name = '',
    required this.type,
    required this.media,
    this.link = '',
    this.format = AdFormat.card,
    this.pages = const [],
    this.active = true,
    this.start,
    this.end,
    this.seconds = 8,
    this.slides = const [],
    this.style = SlideStyle.slide,
    this.cta = '',
    this.code = '',
    this.countdown = false,
    this.mediaDark = '',
    this.mediaB = '',
    this.languages = const [],
    this.countries = const [],
    this.institutions = const [],
    this.dailyCap = 0,
    this.weight = 1,
    this.hourFrom = 0,
    this.hourTo = 24,
    this.weekdays = const [],
    this.draft = false,
  });

  static bool isLocalPath(String s) => !s.startsWith('https://');

  /// Ana görseller (slider'da tüm görseller).
  List<String> get mainSources => type == AdType.slider && slides.isNotEmpty ? slides : [media];

  /// İndirilmesi gereken tüm dosyalar (gece ve B görseli dahil).
  List<String> get sources => [
    ...mainSources,
    if (type == AdType.image && mediaDark.isNotEmpty) mediaDark,
    if (type == AdType.image && mediaB.isNotEmpty) mediaB,
  ];
  bool get isLocal => sources.any(isLocalPath);
  bool get allPages => pages.isEmpty;
  bool get hasAB => type == AdType.image && mediaB.isNotEmpty;
  bool get targeted => languages.isNotEmpty || countries.isNotEmpty || institutions.isNotEmpty;
  bool get timeLimited => hourFrom > 0 || hourTo < 24 || weekdays.isNotEmpty;

  bool showsOn(AdPage p) => pages.isEmpty || pages.contains(p);

  /// Bitişe kalan süre (bitiş günü sonuna kadar).
  Duration? remaining(DateTime now) {
    final e = end;
    if (e == null) return null;
    return DateTime(e.year, e.month, e.day + 1).difference(now);
  }

  bool runningAt(DateTime now) {
    if (!active || draft) return false;
    final day = DateTime(now.year, now.month, now.day);
    if (start != null && day.isBefore(start!)) return false;
    if (end != null && day.isAfter(end!)) return false;
    if (weekdays.isNotEmpty && !weekdays.contains(now.weekday)) return false;
    if (hourFrom > 0 || hourTo < 24) {
      final h = now.hour;
      final inside = hourFrom <= hourTo ? (h >= hourFrom && h < hourTo) : (h >= hourFrom || h < hourTo);
      if (!inside) return false;
    }
    return true;
  }

  bool matches(AdAudience a) {
    if (!runningAt(a.now)) return false;
    if (languages.isNotEmpty && !languages.contains(a.lang)) return false;
    if (countries.isNotEmpty && !countries.contains(a.country.toUpperCase())) return false;
    if (institutions.isNotEmpty && !institutions.contains(a.institution)) return false;
    return true;
  }

  Ad copyWith({
    String? id,
    String? name,
    AdType? type,
    String? media,
    String? link,
    AdFormat? format,
    List<AdPage>? pages,
    bool? active,
    DateTime? start,
    DateTime? end,
    bool clearStart = false,
    bool clearEnd = false,
    int? seconds,
    List<String>? slides,
    SlideStyle? style,
    String? cta,
    String? code,
    bool? countdown,
    String? mediaDark,
    String? mediaB,
    List<String>? languages,
    List<String>? countries,
    List<String>? institutions,
    int? dailyCap,
    int? weight,
    int? hourFrom,
    int? hourTo,
    List<int>? weekdays,
    bool? draft,
  }) => Ad(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    media: media ?? this.media,
    link: link ?? this.link,
    format: format ?? this.format,
    pages: pages ?? this.pages,
    active: active ?? this.active,
    start: clearStart ? null : (start ?? this.start),
    end: clearEnd ? null : (end ?? this.end),
    seconds: seconds ?? this.seconds,
    slides: slides ?? this.slides,
    style: style ?? this.style,
    cta: cta ?? this.cta,
    code: code ?? this.code,
    countdown: countdown ?? this.countdown,
    mediaDark: mediaDark ?? this.mediaDark,
    mediaB: mediaB ?? this.mediaB,
    languages: languages ?? this.languages,
    countries: countries ?? this.countries,
    institutions: institutions ?? this.institutions,
    dailyCap: dailyCap ?? this.dailyCap,
    weight: weight ?? this.weight,
    hourFrom: hourFrom ?? this.hourFrom,
    hourTo: hourTo ?? this.hourTo,
    weekdays: weekdays ?? this.weekdays,
    draft: draft ?? this.draft,
  );

  static String _d(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
    'id': id,
    'ad': name,
    'tur': switch (type) {
      AdType.video => 'video',
      AdType.slider => 'slider',
      AdType.image => 'gorsel',
    },
    // Eski sürümler slider'ı ilk görseliyle sabit reklam olarak gösterir.
    'dosya': type == AdType.slider && slides.isNotEmpty ? slides.first : media,
    if (type == AdType.slider) 'gorseller': slides,
    if (type == AdType.slider) 'gecis': style.key,
    'baglanti': link,
    'bicim': format == AdFormat.banner ? 'serit' : 'kart',
    'sayfalar': pages.isEmpty ? ['hepsi'] : [for (final p in pages) p.key],
    'aktif': active,
    'baslangic': ?(start == null ? null : _d(start!)),
    'bitis': ?(end == null ? null : _d(end!)),
    'sure': seconds,
    if (cta.isNotEmpty) 'dugme': cta,
    if (code.isNotEmpty) 'kod': code,
    if (countdown) 'geriSayim': true,
    if (mediaDark.isNotEmpty) 'geceDosya': mediaDark,
    if (mediaB.isNotEmpty) 'dosyaB': mediaB,
    if (languages.isNotEmpty) 'diller': languages,
    if (countries.isNotEmpty) 'ulkeler': countries,
    if (institutions.isNotEmpty) 'kurumlar': institutions,
    if (dailyCap > 0) 'gunlukSinir': dailyCap,
    if (weight != 1) 'oncelik': weight,
    if (hourFrom > 0 || hourTo < 24) 'saat': [hourFrom, hourTo],
    if (weekdays.isNotEmpty) 'gunler': weekdays,
    if (draft) 'taslak': true,
  };

  static Ad? fromJson(Map<String, dynamic> j) {
    final media = '${j['dosya'] ?? ''}'.trim();
    final id = '${j['id'] ?? ''}'.trim();
    if (media.isEmpty || id.isEmpty) return null;
    final pages = <AdPage>[for (final k in (j['sayfalar'] as List? ?? const [])) ?AdPage.byKey('$k')];
    DateTime? date(Object? v) => v == null ? null : DateTime.tryParse('$v');
    List<String> strs(Object? v) => [
      for (final e in (v is List ? v : const []))
        if ('$e'.trim().isNotEmpty) '$e'.trim(),
    ];
    final slides = strs(j['gorseller']);
    final type = switch ('${j['tur']}') {
      'video' => AdType.video,
      'slider' when slides.length > 1 => AdType.slider,
      _ => AdType.image,
    };
    final hours = j['saat'] is List && (j['saat'] as List).length == 2 ? j['saat'] as List : const [0, 24];
    int n(Object? v, int def) => v is num ? v.toInt() : def;
    return Ad(
      id: id,
      name: '${j['ad'] ?? ''}',
      type: type,
      media: media,
      link: '${j['baglanti'] ?? ''}'.trim(),
      format: '${j['bicim']}' == 'serit' ? AdFormat.banner : AdFormat.card,
      pages: pages,
      active: j['aktif'] != false,
      start: date(j['baslangic']),
      end: date(j['bitis']),
      seconds: ((j['sure'] as num?) ?? (type == AdType.slider ? 3 : 8)).toInt().clamp(2, 60),
      slides: type == AdType.slider ? slides : const [],
      style: SlideStyle.byKey(j['gecis'] as String?),
      cta: '${j['dugme'] ?? ''}'.trim(),
      code: '${j['kod'] ?? ''}'.trim(),
      countdown: j['geriSayim'] == true,
      mediaDark: type == AdType.image ? '${j['geceDosya'] ?? ''}'.trim() : '',
      mediaB: type == AdType.image ? '${j['dosyaB'] ?? ''}'.trim() : '',
      languages: strs(j['diller']),
      countries: [for (final c in strs(j['ulkeler'])) c.toUpperCase()],
      institutions: strs(j['kurumlar']),
      dailyCap: n(j['gunlukSinir'], 0).clamp(0, 100),
      weight: n(j['oncelik'], 1).clamp(1, 5),
      hourFrom: n(hours[0], 0).clamp(0, 23),
      hourTo: n(hours[1], 24).clamp(1, 24),
      weekdays: [
        for (final d in (j['gunler'] is List ? j['gunler'] as List : const []))
          if (d is num && d >= 1 && d <= 7) d.toInt(),
      ],
      draft: j['taslak'] == true,
    );
  }

  static List<Ad> listFromJson(Object? data) {
    final list = data is Map ? data['reklamlar'] : data;
    return [
      for (final e in (list is List ? list : const []))
        if (e is Map) ?Ad.fromJson(e.cast<String, dynamic>()),
    ];
  }

  static String listToJson(List<Ad> ads, {AdSettings settings = const AdSettings()}) =>
      const JsonEncoder.withIndent('  ').convert({
        'surum': 2,
        'guncelleme': DateTime.now().toUtc().toIso8601String(),
        'ayarlar': settings.toJson(),
        'reklamlar': [for (final a in ads) a.toJson()],
      });

  static bool isVideoPath(String p) {
    final l = p.toLowerCase().split('?').first;
    return l.endsWith('.mp4') || l.endsWith('.mov') || l.endsWith('.m4v') || l.endsWith('.webm');
  }
}

/// Tüm reklam alanları için ayarlar (listeyle birlikte yayınlanır).
class AdSettings {
  /// Boş kalan alanlarda "Burada reklamınız olsun" kartı.
  final bool emptySlotCard;

  /// O kartta açılacak iletişim e-postası.
  final String contactEmail;

  /// Kimliksiz görülme/tıklama sayacı açık mı (gizlilik politikasında yazılı).
  final bool stats;

  /// Davet kartı her kaç boş gösterimde bir çıksın (1 = her seferinde).
  final int emptyEvery;

  /// İsteğe bağlı WhatsApp numarası (ülke koduyla, yalnız rakam).
  final String whatsapp;

  /// Ana sayfadaki ürün öneri kartı (mağaza ürünleri) gösterilsin mi.
  final bool promoCard;

  const AdSettings({
    this.emptySlotCard = false,
    this.contactEmail = 'info@neticeoptik.com',
    this.stats = true,
    this.emptyEvery = 1,
    this.whatsapp = '',
    this.promoCard = true,
  });

  AdSettings copyWith({
    bool? emptySlotCard,
    String? contactEmail,
    bool? stats,
    int? emptyEvery,
    String? whatsapp,
    bool? promoCard,
  }) => AdSettings(
    emptySlotCard: emptySlotCard ?? this.emptySlotCard,
    contactEmail: contactEmail ?? this.contactEmail,
    stats: stats ?? this.stats,
    emptyEvery: emptyEvery ?? this.emptyEvery,
    whatsapp: whatsapp ?? this.whatsapp,
    promoCard: promoCard ?? this.promoCard,
  );

  Map<String, dynamic> toJson() => {
    'bosAlanKarti': emptySlotCard,
    'iletisim': contactEmail,
    'istatistik': stats,
    'bosAlanSiklik': emptyEvery,
    if (whatsapp.isNotEmpty) 'whatsapp': whatsapp,
    'oneriKarti': promoCard,
  };

  factory AdSettings.fromJson(Object? j) {
    if (j is! Map) return const AdSettings();
    final mail = '${j['iletisim'] ?? ''}'.trim();
    final every = int.tryParse('${j['bosAlanSiklik'] ?? 1}') ?? 1;
    return AdSettings(
      emptySlotCard: j['bosAlanKarti'] == true,
      contactEmail: mail.contains('@') ? mail : 'info@neticeoptik.com',
      stats: j['istatistik'] != false,
      emptyEvery: every.clamp(1, 5),
      whatsapp: '${j['whatsapp'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), ''),
      promoCard: j['oneriKarti'] != false,
    );
  }
}

/// Uygulamadaki numaralı reklam alanları: sayfa + biçim + yer tarifi.
/// Yönetim ekranındaki "Alanlar" listesi ve "Sayfada göster" bunu kullanır.
class AdPlacement {
  final int no;
  final AdPage page;
  final AdFormat format;
  final String title;
  final String where;

  /// Telefon çiziminde alanın dikey konumu (0 üst, 1 alt).
  final double position;
  const AdPlacement(this.no, this.page, this.format, this.title, this.where, this.position);

  String get key => '${page.key}/${format.name}';
  bool get banner => format == AdFormat.banner;

  static AdPlacement? byKey(String k) => all.where((p) => p.key == k).firstOrNull;

  static const all = [
    AdPlacement(
      1,
      AdPage.home,
      AdFormat.card,
      'Ana sayfa · kart',
      'Ana sayfada özet kutularının altında büyük kart. Uygulamanın en çok görülen alanı.',
      0.55,
    ),
    AdPlacement(
      2,
      AdPage.home,
      AdFormat.banner,
      'Ana sayfa · şerit',
      'Ana sayfanın en altında, menünün üstünde ince şerit.',
      0.92,
    ),
    AdPlacement(
      3,
      AdPage.exam,
      AdFormat.card,
      'Sınav sonuçları · kart',
      'Sınav sonuçlarında öğrenci listesinin en altında.',
      0.45,
    ),
    AdPlacement(
      4,
      AdPage.exam,
      AdFormat.banner,
      'Sınav sonuçları · şerit',
      'Sınav sonuçları sayfasının en altında ince şerit.',
      0.92,
    ),
    AdPlacement(
      5,
      AdPage.classes,
      AdFormat.card,
      'Sınıflar · kart',
      'Sınıflar sayfasında Excel açıklamasının altında, sınıf düğmelerinin üstünde.',
      0.35,
    ),
    AdPlacement(
      6,
      AdPage.classes,
      AdFormat.banner,
      'Sınıflar · şerit',
      'Sınıflar ve öğrenciler sayfasının en altında.',
      0.92,
    ),
    AdPlacement(
      7,
      AdPage.student,
      AdFormat.banner,
      'Öğrenci ayrıntısı · şerit',
      'Bir öğrencinin gelişim sayfasının en altında.',
      0.92,
    ),
    AdPlacement(
      8,
      AdPage.term,
      AdFormat.card,
      'Dönem sonu raporu · kart',
      'Dönem sonu raporunda açıklamanın altında, sınıf seçiminin üstünde.',
      0.5,
    ),
    AdPlacement(
      9,
      AdPage.term,
      AdFormat.banner,
      'Dönem sonu raporu · şerit',
      'Dönem sonu raporu sayfasının en altında.',
      0.92,
    ),
    AdPlacement(
      10,
      AdPage.compare,
      AdFormat.card,
      'Şube karşılaştırması · kart',
      'Şube karşılaştırması ve Genel analiz sayfalarında grafiklerin arasında.',
      0.5,
    ),
    AdPlacement(
      11,
      AdPage.compare,
      AdFormat.banner,
      'Şube karşılaştırması · şerit',
      'Şube karşılaştırması ve Genel analiz sayfalarının en altında.',
      0.92,
    ),
    AdPlacement(
      12,
      AdPage.help,
      AdFormat.card,
      'Yardım · kart',
      'Yardım sayfasında video rehber ve örnek raporların altında.',
      0.4,
    ),
    AdPlacement(
      13,
      AdPage.help,
      AdFormat.banner,
      'Kütüphane · şerit',
      'Kütüphane (soru bankası) sayfasının en altında.',
      0.92,
    ),
    AdPlacement(
      14,
      AdPage.profile,
      AdFormat.card,
      'Profil · kart',
      'Profil sayfasında üstteki öğretmen kartının hemen altında.',
      0.3,
    ),
    AdPlacement(15, AdPage.profile, AdFormat.banner, 'Profil · şerit', 'Profil sayfasının en altında.', 0.92),
    AdPlacement(
      16,
      AdPage.settings,
      AdFormat.card,
      'Ayarlar · kart',
      'Ayarlar sayfasında "Yardım ve gizlilik" bölümünün üstünde.',
      0.7,
    ),
    AdPlacement(17, AdPage.settings, AdFormat.banner, 'Ayarlar · şerit', 'Ayarlar sayfasının en altında.', 0.92),
  ];
}

class AdService extends ChangeNotifier {
  AdService._();
  static final instance = AdService._();

  static const owner = 'emrgngr';
  static const repo = 'netice';
  static const branch = 'reklamlar';
  static const feedPath = 'reklam/reklamlar.json';
  static const mediaDir = 'reklam/medya';
  static String rawUrl(String path) => 'https://raw.githubusercontent.com/$owner/$repo/$branch/$path';
  static final feedUrl = rawUrl(feedPath);

  /// Yayındaki reklamlar ve ayarlar.
  List<Ad> ads = const [];
  AdSettings settings = const AdSettings();

  /// Önizleme açıkken yönetim ekranındaki ayarlar.
  AdSettings? previewSettings;

  AdSettings get activeSettings => preview != null ? (previewSettings ?? settings) : settings;

  /// Yönetim ekranında "bu cihazda önizle" açıkken yayındakiler yerine bunlar gösterilir.
  List<Ad>? preview;

  /// İndirilmiş medya: adres → cihazdaki dosya.
  final Map<String, File> _files = {};

  /// Testler ve ekran görüntüleri için: dosya indirmeden gösterilecek reklamlar.
  void debugSet(List<Ad> list, Map<String, File> files, {AdSettings settings = const AdSettings()}) {
    ads = list;
    this.settings = settings;
    _seen.clear();
    _pending.clear();
    _files
      ..clear()
      ..addAll(files);
    _loaded = true;
    _debug = true;
    notifyListeners();
  }

  bool _debug = false;
  bool _loaded = false;
  bool _busy = false;
  DateTime? _lastFetch;

  /// Kapatılan reklam alanları (uygulama yeniden açılana kadar).
  final Set<String> dismissed = {};

  void setPreview(List<Ad>? list, [AdSettings? settings]) {
    preview = list;
    previewSettings = settings;
    if (list != null) dismissed.clear();
    notifyListeners();
  }

  // ---- "Sayfada göster": yönetim ekranından seçilen alan bir dakika
  // boyunca pembe kesik çerçeveyle işaretlenir (yalnız bu cihazda). ----
  String? highlightKey;
  Timer? _highlightTimer;

  /// Vurgulanan alan sayfada çizildi mi ("Sayfada göster" kaydırması için).
  bool highlightShown = false;

  void highlight(AdPlacement p, {Duration d = const Duration(minutes: 1)}) {
    highlightKey = p.key;
    highlightShown = false;
    _highlightTimer?.cancel();
    _highlightTimer = Timer(d, () {
      highlightKey = null;
      notifyListeners();
    });
    dismissed.remove(p.key);
    notifyListeners();
  }

  void clearHighlight() {
    _highlightTimer?.cancel();
    highlightKey = null;
    notifyListeners();
  }

  bool isHighlighted(AdPage page, AdFormat f) => highlightKey == '${page.key}/${f.name}';

  // Boş alan davet kartı sıklığı: her alan için kaç kez boş gösterildiği (oturumluk).
  final Map<String, int> _emptyShown = {};

  /// Boş alanda davet kartı bu sefer çıksın mı (ayardaki "N gösterimde 1").
  bool emptyCardTurn(AdPage page, AdFormat f, Object owner) {
    final every = activeSettings.emptyEvery;
    if (every <= 1) return true;
    final k = '${page.key}/${f.name}/${identityHashCode(owner)}';
    final n = _emptyShown.putIfAbsent(k, () => _emptyShown.length);
    return n % every == 0;
  }

  void dismiss(AdPage page, AdFormat f) {
    dismissed.add('${page.key}/${f.name}');
    notifyListeners();
  }

  bool isDismissed(AdPage page, AdFormat f) => dismissed.contains('${page.key}/${f.name}');

  File? fileFor(Ad ad) => fileOf(ad.mainSources.first);

  File? fileOf(String src) => Ad.isLocalPath(src) ? File(src) : _files[src];

  /// Reklamın tüm dosyaları hazırsa listesi, değilse null.
  List<File>? filesFor(Ad ad) {
    final out = <File>[];
    for (final s in ad.mainSources) {
      final f = fileOf(s);
      if (f == null || !f.existsSync()) return null;
      out.add(f);
    }
    return out;
  }

  /// Hazırsa ek dosya (gece / B görseli), değilse null.
  File? optionalFile(String src) {
    if (src.isEmpty) return null;
    final f = fileOf(src);
    return f != null && f.existsSync() ? f : null;
  }

  /// Sayfada şimdi gösterilecek reklamlar (dosyası hazır, hedefe uyan,
  /// günlük sınırı dolmamış olanlar).
  List<Ad> adsFor(AdPage page, AdFormat format, [AdAudience? audience]) {
    final aud = audience ?? AdAudience(now: DateTime.now());
    final targeted = audience != null;
    return [
      for (final a in preview ?? ads)
        if (a.format == format &&
            a.showsOn(page) &&
            (targeted ? a.matches(aud) : a.runningAt(aud.now)) &&
            (a.dailyCap == 0 || seenToday(a.id) < a.dailyCap) &&
            filesFor(a) != null)
          a,
    ];
  }

  // ---- Bu cihazdaki gösterim sayacı (yalnız sıklık sınırı ve A/B sırası
  // için; hiçbir yere gönderilmez). ----
  final Map<String, int> _seen = {};
  Timer? _saveSeen;

  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  int seenToday(String id) => _seen['${_today()}/$id'] ?? 0;

  /// Toplam gösterim (A/B sırası için).
  int seenTotal(String id) => _seen['toplam/$id'] ?? 0;

  // ---- Kimliksiz sayaç: yalnız (gün, reklam, A/B, tür, adet) toplamları,
  // birkaç dakikada bir toplu gönderilir. Cihaz kimliği gönderilmez. ----

  /// Sayaç sunucusu (sunucu/reklam-sayac).
  static const statsUrl = String.fromEnvironment(
    'REKLAM_SAYAC_URL',
    defaultValue: 'https://netice-reklam-sayac.bilgi-7ff.workers.dev',
  );

  final Map<String, int> _pending = {};
  Timer? _flushTimer;

  /// Testler için: gönderilmeyi bekleyen sayılar.
  @visibleForTesting
  Map<String, int> get pendingStats => Map.unmodifiable(_pending);

  static String _utcDay() => DateTime.now().toUtc().toIso8601String().substring(0, 10);

  void _count(Ad ad, bool b, String kind) {
    // Yönetici önizlemesi ve yayınlanmamış reklamlar sayılmaz.
    if (preview != null || ad.isLocal || !settings.stats) return;
    final k = '${_utcDay()}|${ad.id}|${b ? 'b' : 'a'}|$kind';
    if (_pending.length >= 400 && !_pending.containsKey(k)) return;
    _pending[k] = (_pending[k] ?? 0) + 1;
    if (_debug) return;
    if (_pending.values.fold(0, (a, n) => a + n) >= 50) {
      flushStats();
    } else {
      _flushTimer ??= Timer(const Duration(minutes: 3), flushStats);
    }
  }

  /// "Burada reklamınız olsun" formundan reklam başvurusu gönderir.
  /// Başarılıysa null, değilse kullanıcıya gösterilecek kısa hata.
  Future<String?> sendApplication(AdApplication a) async {
    try {
      final r = await http
          .post(
            Uri.parse('$statsUrl/basvuru'),
            headers: {'content-type': 'application/json', 'x-netice-app': 'netice-app-1'},
            body: jsonEncode(a.toJson()),
          )
          .timeout(const Duration(seconds: 20));
      if (r.statusCode == 200) return null;
      if (r.statusCode == 429) return 'limit';
      return 'server';
    } catch (_) {
      return 'offline';
    }
  }

  /// Tıklama (bağlantı açıldı).
  void recordClick(Ad ad, {bool variantB = false}) => _count(ad, variantB, 't');

  bool _flushing = false;

  /// Bekleyen sayıları gönderir; başarısızsa sonra yeniden denenir.
  Future<void> flushStats() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_flushing || _pending.isEmpty || _debug) return;
    _flushing = true;
    final batch = Map.of(_pending);
    try {
      final body = jsonEncode({
        'olaylar': [
          for (final e in batch.entries.take(200))
            () {
              final p = e.key.split('|');
              return {'gun': p[0], 'reklam': p[1], 'surum': p[2], 'tur': p[3], 'n': e.value};
            }(),
        ],
      });
      final r = await http
          .post(
            Uri.parse('$statsUrl/olay'),
            headers: {'content-type': 'application/json', 'x-netice-app': 'netice-app-1'},
            body: body,
          )
          .timeout(const Duration(seconds: 20));
      if (r.statusCode == 200 || r.statusCode == 400) {
        for (final e in batch.entries.take(200)) {
          final left = (_pending[e.key] ?? 0) - e.value;
          left > 0 ? _pending[e.key] = left : _pending.remove(e.key);
        }
      }
    } catch (_) {
      // İnternet yoksa sonra.
    } finally {
      _flushing = false;
      if (_pending.isNotEmpty) _flushTimer ??= Timer(const Duration(minutes: 10), flushStats);
    }
  }

  void recordImpression(Ad ad, {bool variantB = false}) {
    _count(ad, variantB, 'g');
    final k = '${_today()}/${ad.id}';
    _seen[k] = (_seen[k] ?? 0) + 1;
    _seen['toplam/${ad.id}'] = seenTotal(ad.id) + 1;
    if (_debug) return;
    _saveSeen?.cancel();
    _saveSeen = Timer(const Duration(seconds: 5), () async {
      try {
        final today = _today();
        _seen.removeWhere((k, _) => !k.startsWith('$today/') && !k.startsWith('toplam/'));
        await File('${(await _dir()).path}${Platform.pathSeparator}gosterim.json').writeAsString(jsonEncode(_seen));
      } catch (_) {}
    });
  }

  Future<void> _loadSeen(Directory dir) async {
    if (_seen.isNotEmpty) return;
    try {
      final f = File('${dir.path}${Platform.pathSeparator}gosterim.json');
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString());
        if (j is Map) {
          for (final e in j.entries) {
            if (e.value is num) _seen['${e.key}'] = (e.value as num).toInt();
          }
        }
      }
    } catch (_) {}
  }

  /// A/B: gösterimlere göre sırayla A ve B görseli.
  bool useVariantB(Ad ad) => ad.hasAB && seenTotal(ad.id).isOdd;

  Future<Directory> _dir() async {
    final d = Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}reklam');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static String _fileName(String url) {
    final last = Uri.parse(url).pathSegments.lastOrNull ?? 'medya';
    final ext = last.contains('.') ? last.substring(last.lastIndexOf('.')) : '';
    return '${url.hashCode.toUnsigned(32).toRadixString(16)}${ext.length <= 6 ? ext : ''}';
  }

  /// Önbellekteki listeyi açar; bir saatten eskiyse internetten tazeler.
  Future<void> refresh({bool force = false}) async {
    if (_pending.isNotEmpty) unawaited(flushStats());
    if (_busy || _debug) return;
    _busy = true;
    try {
      final dir = await _dir();
      await _loadSeen(dir);
      final cache = File('${dir.path}${Platform.pathSeparator}reklamlar.json');
      if (!_loaded && await cache.exists()) {
        try {
          final j = jsonDecode(await cache.readAsString());
          ads = Ad.listFromJson(j);
          settings = AdSettings.fromJson(j is Map ? j['ayarlar'] : null);
          await _attach(dir, download: false);
          _loaded = true;
          notifyListeners();
        } catch (_) {}
      }
      final age = await cache.exists() ? DateTime.now().difference(await cache.lastModified()) : null;
      final recent = _lastFetch != null && DateTime.now().difference(_lastFetch!) < const Duration(minutes: 10);
      if (!force && (recent || (age != null && age < const Duration(hours: 1)))) {
        await _attach(dir, download: true);
        return;
      }
      _lastFetch = DateTime.now();
      final r = await http
          .get(Uri.parse('$feedUrl?t=${DateTime.now().millisecondsSinceEpoch ~/ 300000}'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final body = utf8.decode(r.bodyBytes);
        final j = jsonDecode(body);
        ads = Ad.listFromJson(j);
        settings = AdSettings.fromJson(j is Map ? j['ayarlar'] : null);
        await cache.writeAsString(body);
      } else if (r.statusCode == 404) {
        ads = const [];
        settings = const AdSettings();
        if (await cache.exists()) await cache.delete();
      }
      _loaded = true;
      notifyListeners();
      await _attach(dir, download: true);
    } catch (_) {
      // Çevrimdışı: elimizdekiyle devam.
    } finally {
      _busy = false;
    }
  }

  /// Yönetim ekranından yeni yayınlanan listeyi hemen uygular (GitHub'ın
  /// birkaç dakikalık önbelleğini beklemeden).
  Future<void> adopt(String json) async {
    try {
      final dir = await _dir();
      await File('${dir.path}${Platform.pathSeparator}reklamlar.json').writeAsString(json);
      final j = jsonDecode(json);
      ads = Ad.listFromJson(j);
      settings = AdSettings.fromJson(j is Map ? j['ayarlar'] : null);
      _loaded = true;
      _lastFetch = DateTime.now();
      notifyListeners();
      await _attach(dir, download: true);
    } catch (_) {}
  }

  /// Listede adı geçen dosyaları bağlar, eksikleri indirir, artıkları siler.
  Future<void> _attach(Directory dir, {required bool download}) async {
    final media = Directory('${dir.path}${Platform.pathSeparator}medya');
    if (!await media.exists()) await media.create();
    final wanted = <String>{};
    for (final a in ads) {
      for (final src in a.sources) {
        if (Ad.isLocalPath(src)) continue;
        final f = File('${media.path}${Platform.pathSeparator}${_fileName(src)}');
        wanted.add(f.path);
        if (await f.exists()) {
          if (_files[src]?.path != f.path) {
            _files[src] = f;
            notifyListeners();
          }
          continue;
        }
        if (!download || !a.runningAt(DateTime.now())) continue;
        try {
          final r = await http.get(Uri.parse(src)).timeout(const Duration(minutes: 3));
          if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
            final tmp = File('${f.path}.part');
            await tmp.writeAsBytes(r.bodyBytes, flush: true);
            await tmp.rename(f.path);
            _files[src] = f;
            notifyListeners();
          }
        } catch (_) {}
      }
    }
    if (download) {
      await for (final e in media.list()) {
        if (e is File && !wanted.contains(e.path)) {
          try {
            await e.delete();
          } catch (_) {}
        }
      }
    }
  }
}

/// Bir görselin (A ya da B) görülme ve tıklama toplamı.
/// Reklam vermek isteyen firmanın formdan bıraktığı başvuru.
class AdApplication {
  final String id;
  final DateTime? time;
  final String name;
  final String company;
  final String phone;
  final String email;
  final String message;

  /// Başvurunun yapıldığı alan (ör. ana_sayfa/card), boş olabilir.
  final String slot;
  final String lang;
  final String country;

  const AdApplication({
    this.id = '',
    this.time,
    required this.name,
    this.company = '',
    this.phone = '',
    this.email = '',
    required this.message,
    this.slot = '',
    this.lang = '',
    this.country = '',
  });

  Map<String, dynamic> toJson() => {
    'ad': name,
    'firma': company,
    'telefon': phone,
    'eposta': email,
    'mesaj': message,
    'alan': slot,
    'dil': lang,
    'ulke': country,
  };

  factory AdApplication.fromJson(Map j) => AdApplication(
    id: '${j['id'] ?? ''}',
    time: DateTime.tryParse('${j['zaman'] ?? ''}')?.toLocal(),
    name: '${j['ad'] ?? ''}',
    company: '${j['firma'] ?? ''}',
    phone: '${j['telefon'] ?? ''}',
    email: '${j['eposta'] ?? ''}',
    message: '${j['mesaj'] ?? ''}',
    slot: '${j['alan'] ?? ''}',
    lang: '${j['dil'] ?? ''}',
    country: '${j['ulke'] ?? ''}',
  );
}

class AdCounts {
  final int views;
  final int clicks;
  const AdCounts([this.views = 0, this.clicks = 0]);

  /// Tıklama oranı (0–1).
  double get rate => views == 0 ? 0 : clicks / views;
  AdCounts operator +(AdCounts o) => AdCounts(views + o.views, clicks + o.clicks);

  factory AdCounts.fromJson(Object? j) =>
      j is Map ? AdCounts((j['g'] as num?)?.toInt() ?? 0, (j['t'] as num?)?.toInt() ?? 0) : const AdCounts();
}

/// Sayaç sunucusundan gelen bir reklamın özeti.
class AdStats {
  final AdCounts a;
  final AdCounts b;

  /// Gün (YYYY-MM-DD) → toplam.
  final Map<String, AdCounts> daily;
  const AdStats({this.a = const AdCounts(), this.b = const AdCounts(), this.daily = const {}});

  AdCounts get total => a + b;

  factory AdStats.fromJson(Object? j) {
    if (j is! Map) return const AdStats();
    final d = j['gunluk'];
    return AdStats(
      a: AdCounts.fromJson(j['a']),
      b: AdCounts.fromJson(j['b']),
      daily: {
        if (d is Map)
          for (final e in d.entries) '${e.key}': AdCounts.fromJson(e.value),
      },
    );
  }

  static Map<String, AdStats> mapFromJson(Object? j) {
    final r = j is Map ? j['reklamlar'] : null;
    if (r is! Map) return const {};
    return {for (final e in r.entries) '${e.key}': AdStats.fromJson(e.value)};
  }
}

/// A/B testi sonucu.
enum AbVerdict { needMoreData, noDifference, aWins, bWins }

/// Her görsel en az [minViews] kez görüldüyse iki oran z-testiyle (%95)
/// kazananı bulur.
AbVerdict abVerdict(AdCounts a, AdCounts b, {int minViews = 100}) {
  if (a.views < minViews || b.views < minViews) return AbVerdict.needMoreData;
  final p = (a.clicks + b.clicks) / (a.views + b.views);
  if (p <= 0 || p >= 1) return AbVerdict.noDifference;
  final se = math.sqrt(p * (1 - p) * (1 / a.views + 1 / b.views));
  final z = (b.rate - a.rate) / se;
  if (z >= 1.96) return AbVerdict.bWins;
  if (z <= -1.96) return AbVerdict.aWins;
  return AbVerdict.noDifference;
}
