import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
enum AdType { image, video }

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
  term('donem', 'Dönem raporu'),
  compare('karsilastirma', 'Şube karşılaştırması'),
  help('yardim', 'Yardım'),
  profile('profil', 'Profil'),
  settings('ayarlar', 'Ayarlar');

  final String key;
  final String label;
  const AdPage(this.key, this.label);

  static AdPage? byKey(String k) => values.where((p) => p.key == k).firstOrNull;
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
  final int seconds;

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
  });

  bool get isLocal => !media.startsWith('https://');
  bool get allPages => pages.isEmpty;

  bool showsOn(AdPage p) => pages.isEmpty || pages.contains(p);

  bool runningAt(DateTime now) {
    if (!active) return false;
    final day = DateTime(now.year, now.month, now.day);
    if (start != null && day.isBefore(start!)) return false;
    if (end != null && day.isAfter(end!)) return false;
    return true;
  }

  Ad copyWith({
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
  }) =>
      Ad(
        id: id,
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
      );

  static String _d(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'ad': name,
        'tur': type == AdType.video ? 'video' : 'gorsel',
        'dosya': media,
        'baglanti': link,
        'bicim': format == AdFormat.banner ? 'serit' : 'kart',
        'sayfalar': pages.isEmpty ? ['hepsi'] : [for (final p in pages) p.key],
        'aktif': active,
        'baslangic': ?(start == null ? null : _d(start!)),
        'bitis': ?(end == null ? null : _d(end!)),
        'sure': seconds,
      };

  static Ad? fromJson(Map<String, dynamic> j) {
    final media = '${j['dosya'] ?? ''}'.trim();
    final id = '${j['id'] ?? ''}'.trim();
    if (media.isEmpty || id.isEmpty) return null;
    final pages = <AdPage>[
      for (final k in (j['sayfalar'] as List? ?? const [])) ?AdPage.byKey('$k'),
    ];
    DateTime? date(Object? v) => v == null ? null : DateTime.tryParse('$v');
    return Ad(
      id: id,
      name: '${j['ad'] ?? ''}',
      type: '${j['tur']}' == 'video' ? AdType.video : AdType.image,
      media: media,
      link: '${j['baglanti'] ?? ''}'.trim(),
      format: '${j['bicim']}' == 'serit' ? AdFormat.banner : AdFormat.card,
      pages: pages,
      active: j['aktif'] != false,
      start: date(j['baslangic']),
      end: date(j['bitis']),
      seconds: ((j['sure'] as num?) ?? 8).toInt().clamp(3, 60),
    );
  }

  static List<Ad> listFromJson(Object? data) {
    final list = data is Map ? data['reklamlar'] : data;
    return [
      for (final e in (list is List ? list : const []))
        if (e is Map) ?Ad.fromJson(e.cast<String, dynamic>()),
    ];
  }

  static String listToJson(List<Ad> ads) => const JsonEncoder.withIndent('  ').convert({
        'surum': 1,
        'guncelleme': DateTime.now().toUtc().toIso8601String(),
        'reklamlar': [for (final a in ads) a.toJson()],
      });

  static bool isVideoPath(String p) {
    final l = p.toLowerCase().split('?').first;
    return l.endsWith('.mp4') || l.endsWith('.mov') || l.endsWith('.m4v') || l.endsWith('.webm');
  }
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

  /// Yayındaki reklamlar.
  List<Ad> ads = const [];

  /// Yönetim ekranında "bu cihazda önizle" açıkken yayındakiler yerine bunlar gösterilir.
  List<Ad>? preview;

  /// İndirilmiş medya: adres → cihazdaki dosya.
  final Map<String, File> _files = {};

  /// Testler ve ekran görüntüleri için: dosya indirmeden gösterilecek reklamlar.
  void debugSet(List<Ad> list, Map<String, File> files) {
    ads = list;
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

  void setPreview(List<Ad>? list) {
    preview = list;
    if (list != null) dismissed.clear();
    notifyListeners();
  }

  void dismiss(AdPage page, AdFormat f) {
    dismissed.add('${page.key}/${f.name}');
    notifyListeners();
  }

  bool isDismissed(AdPage page, AdFormat f) => dismissed.contains('${page.key}/${f.name}');

  File? fileFor(Ad ad) => ad.isLocal ? File(ad.media) : _files[ad.media];

  /// Sayfada şimdi gösterilecek reklamlar (dosyası hazır olanlar).
  List<Ad> adsFor(AdPage page, AdFormat format) {
    final now = DateTime.now();
    return [
      for (final a in preview ?? ads)
        if (a.format == format && a.showsOn(page) && a.runningAt(now) && (fileFor(a)?.existsSync() ?? false)) a,
    ];
  }

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
    if (_busy || _debug) return;
    _busy = true;
    try {
      final dir = await _dir();
      final cache = File('${dir.path}${Platform.pathSeparator}reklamlar.json');
      if (!_loaded && await cache.exists()) {
        try {
          ads = Ad.listFromJson(jsonDecode(await cache.readAsString()));
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
        ads = Ad.listFromJson(jsonDecode(body));
        await cache.writeAsString(body);
      } else if (r.statusCode == 404) {
        ads = const [];
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
      ads = Ad.listFromJson(jsonDecode(json));
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
      if (a.isLocal) continue;
      final f = File('${media.path}${Platform.pathSeparator}${_fileName(a.media)}');
      wanted.add(f.path);
      if (await f.exists()) {
        if (_files[a.media]?.path != f.path) {
          _files[a.media] = f;
          notifyListeners();
        }
        continue;
      }
      if (!download || !a.runningAt(DateTime.now())) continue;
      try {
        final r = await http.get(Uri.parse(a.media)).timeout(const Duration(minutes: 3));
        if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
          final tmp = File('${f.path}.part');
          await tmp.writeAsBytes(r.bodyBytes, flush: true);
          await tmp.rename(f.path);
          _files[a.media] = f;
          notifyListeners();
        }
      } catch (_) {}
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
