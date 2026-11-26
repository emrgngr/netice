import 'dart:convert';
import 'dart:io';

import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'ads.dart';

/// Reklam yönetimi (yalnızca uygulama sahibinin cihazında).
///
/// Taslak liste ve GitHub yayın anahtarı yalnızca bu cihazda, yedeğe
/// girmeyen ayrı bir dosyada saklanır. "Yayınla" görselleri/videoları ve
/// listeyi depodaki `reklamlar` dalına yükler; tüm kullanıcıların
/// uygulaması listeyi oradan okur.
class AdAdmin extends ChangeNotifier {
  AdAdmin._();
  static final instance = AdAdmin._();

  /// Yönetici PIN'i: yalnızca tuzlanmış özeti bu cihazda saklanır, kodda yoktur.
  String _pinHash = '';
  String _pinSalt = '';
  int _failed = 0;
  DateTime? _lockedUntil;

  bool get hasPin => _pinHash.isNotEmpty;
  String token = '';
  List<Ad> drafts = [];
  AdSettings settings = const AdSettings();
  bool dirty = false;
  DateTime? lastPublish;
  bool _loaded = false;

  static const maxImageBytes = 5 * 1024 * 1024;
  static const maxVideoBytes = 40 * 1024 * 1024;

  Future<File> _file() async {
    final d = await getApplicationSupportDirectory();
    return File('${d.path}${Platform.pathSeparator}reklam_yonetici.json');
  }

  Future<Directory> mediaDir() async {
    final d = Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}reklam_taslak');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        _pinHash = '${j['pin'] ?? ''}';
        _pinSalt = '${j['tuz'] ?? ''}';
        _failed = (j['hata'] as num? ?? 0).toInt();
        _lockedUntil = DateTime.tryParse('${j['kilit'] ?? ''}');
        token = '${j['anahtar'] ?? ''}';
        drafts = Ad.listFromJson(j['taslak']);
        settings = AdSettings.fromJson(j['ayarlar']);
        dirty = j['degisti'] == true;
        lastPublish = DateTime.tryParse('${j['yayin'] ?? ''}');
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> save() async {
    try {
      await (await _file()).writeAsString(
        jsonEncode({
          'ayarlar': settings.toJson(),
          'pin': _pinHash,
          'tuz': _pinSalt,
          'hata': _failed,
          if (_lockedUntil != null) 'kilit': _lockedUntil!.toIso8601String(),
          'anahtar': token,
          'taslak': [for (final a in drafts) a.toJson()],
          'degisti': dirty,
          if (lastPublish != null) 'yayin': lastPublish!.toIso8601String(),
        }),
      );
    } catch (_) {}
    notifyListeners();
  }

  static String _hash(String pin, String salt) {
    List<int> h = utf8.encode('$salt:$pin');
    for (var i = 0; i < 20000; i++) {
      h = sha256.convert([...h, ...utf8.encode(salt)]).bytes;
    }
    return base64Encode(h);
  }

  static bool validPin(String pin) => RegExp(r'^\d{6,12}$').hasMatch(pin);

  Future<void> setPin(String pin) async {
    await load();
    final r = Random.secure();
    _pinSalt = base64Encode(List.generate(16, (_) => r.nextInt(256)));
    _pinHash = await compute((List<String> a) => _hash(a[0], a[1]), [pin, _pinSalt]);
    _failed = 0;
    _lockedUntil = null;
    await save();
  }

  /// Kaç saniye kilitli (yanlış denemelerden sonra)?
  int get lockSeconds {
    final l = _lockedUntil;
    if (l == null) return 0;
    final s = l.difference(DateTime.now()).inSeconds;
    return s > 0 ? s + 1 : 0;
  }

  /// PIN doğru mu? 5 yanlıştan sonra giderek uzayan bekleme süresi.
  Future<bool> checkPin(String pin) async {
    await load();
    if (!hasPin || lockSeconds > 0) return false;
    final h = await compute((List<String> a) => _hash(a[0], a[1]), [pin, _pinSalt]);
    if (h == _pinHash) {
      _failed = 0;
      _lockedUntil = null;
      await save();
      return true;
    }
    _failed++;
    if (_failed >= 5) {
      _lockedUntil = DateTime.now().add(Duration(minutes: 1 << (_failed - 5).clamp(0, 6)));
    }
    await save();
    return false;
  }

  /// PIN unutulursa: kayıtlı GitHub yayın anahtarının aynısı girilirse sıfırlanır.
  /// Bu cihazda yayın anahtarı yoksa buradan hiçbir şey yayınlanamaz; kod anahtarsız sıfırlanabilir.
  Future<bool> resetPinWithToken(String t) async {
    await load();
    if (token.isNotEmpty && t.trim() != token) return false;
    _pinHash = '';
    _pinSalt = '';
    _failed = 0;
    _lockedUntil = null;
    await save();
    return true;
  }

  Future<void> setToken(String t) async {
    token = t.trim();
    await save();
  }

  void upsert(Ad ad) {
    final i = drafts.indexWhere((a) => a.id == ad.id);
    if (i < 0) {
      drafts = [...drafts, ad];
    } else {
      drafts = [...drafts]..[i] = ad;
    }
    dirty = true;
    save();
  }

  void setSettings(AdSettings s) {
    settings = s;
    dirty = true;
    save();
  }

  /// Seçilenleri tek seferde açar/kapatır.
  void setActiveMany(Set<String> ids, bool active) {
    drafts = [for (final a in drafts) ids.contains(a.id) ? a.copyWith(active: active) : a];
    dirty = true;
    save();
  }

  void removeMany(Set<String> ids) {
    drafts = drafts.where((a) => !ids.contains(a.id)).toList();
    dirty = true;
    save();
  }

  /// Reklamı kopyalar (taslak olarak, hemen arkasına).
  Ad duplicate(Ad a) {
    final copy = a.copyWith(id: newId(), name: '${a.name} (kopya)', draft: true);
    final i = drafts.indexWhere((d) => d.id == a.id);
    drafts = [...drafts]..insert(i < 0 ? drafts.length : i + 1, copy);
    dirty = true;
    save();
    return copy;
  }

  void remove(String id) {
    drafts = drafts.where((a) => a.id != id).toList();
    dirty = true;
    save();
  }

  void move(int from, int to) {
    final l = [...drafts];
    final a = l.removeAt(from);
    l.insert(to.clamp(0, l.length), a);
    drafts = l;
    dirty = true;
    save();
  }

  static String newId() => 'r${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

  /// Seçilen dosyayı taslak klasörüne yazar.
  Future<String> importBytes(List<int> bytes, String name, String id) async {
    final ext = name.contains('.') ? name.substring(name.lastIndexOf('.')).toLowerCase() : '';
    final dest = File(
      '${(await mediaDir()).path}${Platform.pathSeparator}${id}_${DateTime.now().millisecondsSinceEpoch}$ext',
    );
    await dest.writeAsBytes(bytes, flush: true);
    return dest.path;
  }

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $token',
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  static const _api = 'https://api.github.com/repos/${AdService.owner}/${AdService.repo}';

  /// Yayındaki son listeyi doğrudan depodan okur (önbelleksiz).
  Future<(List<Ad>, AdSettings)?> fetchPublishedFull() async {
    try {
      final r = await http
          .get(
            Uri.parse('$_api/contents/${AdService.feedPath}?ref=${AdService.branch}'),
            headers: token.isEmpty
                ? {'Accept': 'application/vnd.github.raw+json'}
                : {..._headers, 'Accept': 'application/vnd.github.raw+json'},
          )
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 404) return (const <Ad>[], const AdSettings());
      if (r.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      return (Ad.listFromJson(j), AdSettings.fromJson(j is Map ? j['ayarlar'] : null));
    } catch (_) {
      return null;
    }
  }

  /// Sayaç sunucusundan son [days] günün özeti. Yalnız sahibin yayın
  /// anahtarıyla okunur. Hata varsa (null, açıklama).
  Future<(Map<String, AdStats>?, String?)> fetchStats(int days) async {
    if (token.isEmpty) return (null, 'Önce yayın anahtarını girin.');
    try {
      final r = await http
          .get(Uri.parse('${AdService.statsUrl}/ozet?gun=$days'), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 20));
      if (r.statusCode == 200) return (AdStats.mapFromJson(jsonDecode(utf8.decode(r.bodyBytes))), null);
      if (r.statusCode == 403) return (null, 'Yayın anahtarı kabul edilmedi. Anahtarın süresi dolmuş olabilir.');
      if (r.statusCode == 404) return (null, 'Sayaç sunucusu henüz kurulmamış (birkaç dakika sonra deneyin).');
      return (null, 'Sayaç sunucusu yanıt vermedi (${r.statusCode}).');
    } catch (_) {
      return (null, 'İnternete bağlanılamadı.');
    }
  }

  Future<List<Ad>?> fetchPublished() async {
    try {
      final r = await http
          .get(
            Uri.parse('$_api/contents/${AdService.feedPath}?ref=${AdService.branch}'),
            headers: token.isEmpty
                ? {'Accept': 'application/vnd.github.raw+json'}
                : {..._headers, 'Accept': 'application/vnd.github.raw+json'},
          )
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 404) return const [];
      if (r.statusCode != 200) return null;
      return Ad.listFromJson(jsonDecode(utf8.decode(r.bodyBytes)));
    } catch (_) {
      return null;
    }
  }

  /// Yayındaki listeyi taslağa alır (taslakta yayınlanmamış değişiklik yoksa).
  Future<bool> syncFromPublished({bool overwrite = false}) async {
    await load();
    if (dirty && !overwrite) return false;
    final full = await fetchPublishedFull();
    if (full == null) return false;
    final (pub, set) = full;
    // Yayınlanmamış taslaklar korunur.
    final ids = {for (final a in pub) a.id};
    drafts = [
      ...pub,
      for (final a in drafts)
        if (a.draft && !ids.contains(a.id)) a,
    ];
    settings = set;
    dirty = false;
    await save();
    return true;
  }

  /// Anahtarı dener: depoya yazma izni var mı?
  Future<String?> checkToken() async {
    if (token.isEmpty) return 'Önce yayın anahtarını girin.';
    try {
      final r = await http.get(Uri.parse(_api), headers: _headers).timeout(const Duration(seconds: 15));
      if (r.statusCode == 401) return 'Anahtar geçersiz ya da süresi dolmuş.';
      if (r.statusCode != 200) return 'GitHub cevap vermedi (${r.statusCode}).';
      final perm = (jsonDecode(r.body) as Map)['permissions'];
      if (perm is Map && perm['push'] != true) {
        return 'Anahtarın depoya yazma izni yok (Contents: Read and write seçilmeli).';
      }
      return null;
    } catch (_) {
      return 'İnternet bağlantısı yok.';
    }
  }

  Future<void> _ensureBranch() async {
    final r = await http.get(Uri.parse('$_api/branches/${AdService.branch}'), headers: _headers);
    if (r.statusCode == 200) return;
    if (r.statusCode != 404) throw 'Dal okunamadı (${r.statusCode}).';
    final repo = jsonDecode((await http.get(Uri.parse(_api), headers: _headers)).body) as Map;
    final base = '${repo['default_branch'] ?? 'main'}';
    final ref = await http.get(Uri.parse('$_api/git/ref/heads/$base'), headers: _headers);
    if (ref.statusCode != 200) throw 'Ana dal bulunamadı (${ref.statusCode}).';
    final sha = ((jsonDecode(ref.body) as Map)['object'] as Map)['sha'];
    final c = await http.post(
      Uri.parse('$_api/git/refs'),
      headers: _headers,
      body: jsonEncode({'ref': 'refs/heads/${AdService.branch}', 'sha': sha}),
    );
    if (c.statusCode != 201) throw 'Reklam dalı oluşturulamadı (${c.statusCode}).';
  }

  Future<String?> _sha(String path) async {
    final r = await http.get(Uri.parse('$_api/contents/$path?ref=${AdService.branch}'), headers: _headers);
    if (r.statusCode != 200) return null;
    final j = jsonDecode(r.body);
    return j is Map ? j['sha'] as String? : null;
  }

  Future<void> _put(String path, List<int> bytes, String message) async {
    final sha = await _sha(path);
    final r = await http
        .put(
          Uri.parse('$_api/contents/$path'),
          headers: _headers,
          body: jsonEncode({
            'message': message,
            'content': base64Encode(bytes),
            'branch': AdService.branch,
            'sha': ?sha,
          }),
        )
        .timeout(const Duration(minutes: 5));
    if (r.statusCode != 200 && r.statusCode != 201) {
      throw 'Yüklenemedi: $path (${r.statusCode}).';
    }
  }

  /// Taslağı yayınlar. [progress] adım adım bilgi verir.
  Future<String?> publish({void Function(String)? progress}) async {
    final err = await checkToken();
    if (err != null) return err;
    try {
      progress?.call('Hazırlanıyor…');
      await _ensureBranch();
      final out = <Ad>[];
      final live = [
        for (final a in drafts)
          if (!a.draft) a,
      ];
      for (final (i, a) in live.indexed) {
        if (!a.isLocal) {
          out.add(a);
          continue;
        }
        progress?.call('Yükleniyor ${i + 1}/${live.length}: ${a.name}');
        Future<String> upload(String src, String n) async {
          if (src.isEmpty || !Ad.isLocalPath(src)) return src;
          final f = File(src);
          if (!await f.exists()) throw '"${a.name}" reklamının dosyası bulunamadı.';
          final ext = src.contains('.') ? src.substring(src.lastIndexOf('.')).toLowerCase() : '';
          final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
          final path = '${AdService.mediaDir}/${a.id}_${n}_$stamp$ext';
          await _put(path, await f.readAsBytes(), 'Reklam dosyası: ${a.name}');
          return AdService.rawUrl(path);
        }

        var up = a.copyWith(mediaDark: await upload(a.mediaDark, 'gece'), mediaB: await upload(a.mediaB, 'b'));
        if (a.type == AdType.slider) {
          final urls = <String>[];
          for (final (n, src) in a.slides.indexed) {
            urls.add(await upload(src, '$n'));
          }
          up = up.copyWith(slides: urls, media: urls.first);
        } else {
          up = up.copyWith(media: await upload(a.media, '0'));
        }
        out.add(up);
      }
      progress?.call('Liste yayınlanıyor…');
      final json = Ad.listToJson(out, settings: settings);
      await _put(AdService.feedPath, utf8.encode(json), 'Reklam listesi güncellendi');

      // Artık kullanılmayan dosyaları depodan sil.
      progress?.call('Eski dosyalar temizleniyor…');
      final used = {for (final a in out) ...a.sources, for (final a in out) a.media};
      final l = await http.get(
        Uri.parse('$_api/contents/${AdService.mediaDir}?ref=${AdService.branch}'),
        headers: _headers,
      );
      if (l.statusCode == 200) {
        for (final e in (jsonDecode(l.body) as List)) {
          final path = '${(e as Map)['path']}';
          if (used.contains(AdService.rawUrl(path))) continue;
          await http.delete(
            Uri.parse('$_api/contents/$path'),
            headers: _headers,
            body: jsonEncode({'message': 'Eski reklam dosyası silindi', 'sha': e['sha'], 'branch': AdService.branch}),
          );
        }
      }

      // Yerel kopyaları yayın adresiyle eşle ki tekrar indirilmesin.
      final byId = {for (final a in out) a.id: a};
      for (final a in live) {
        for (final src in {...a.sources, a.media}) {
          if (!Ad.isLocalPath(src)) continue;
          try {
            await File(src).delete();
          } catch (_) {}
        }
      }
      drafts = [for (final a in drafts) a.draft ? a : (byId[a.id] ?? a)];
      dirty = false;
      lastPublish = DateTime.now();
      await save();
      AdService.instance.preview = null;
      await AdService.instance.adopt(json);
      return null;
    } catch (e) {
      return e is String ? e : 'Yayınlanamadı: $e';
    }
  }
}
