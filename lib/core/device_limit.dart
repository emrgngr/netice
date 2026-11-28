import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../bank/ai_questions.dart';
import '../l10n/l10n.dart';

/// Cihaz sınırı sunucusu (sunucu/lisans-cihaz).
const deviceLimitUrl = String.fromEnvironment('LISANS_SERVIS_URL', defaultValue: 'https://netice-lisans.bilgi-7ff.workers.dev');

/// "Bir öğretmen, bir lisans": Pro aboneliği aynı anda en fazla 1 telefon
/// ya da tablet ve 1 bilgisayarda açık olur.
///
/// Hesap yoktur. Mağaza fişinin (Google Play satın alma jetonu, App Store ilk
/// işlem numarası, Microsoft Store lisansı) cihazda alınan özeti ve isimsiz
/// cihaz kodu sunucuda eşleştirilir. Sunucuya ulaşılamazsa (çevrimdışı) Pro
/// olduğu gibi kalır; yalnız sunucu "başka cihazda açık" derse kilitlenir.
class DeviceLimit extends ChangeNotifier {
  DeviceLimit._();
  static DeviceLimit instance = DeviceLimit._();

  @visibleForTesting
  factory DeviceLimit.forTest() => DeviceLimit._();

  /// Aynı lisansın öbür cihazı çıkarıp bu cihaza alınma hakkı (30 günde).
  static const transferLimit = 3;

  /// Son kontrol edilen lisansın özeti.
  String? key;

  /// Pro bu cihazda kapalı: lisans başka bir cihazda açık ya da kullanıcı
  /// bu cihazdan çıkış yaptı.
  bool blocked = false;

  /// Kullanıcı "Bu cihazdan çıkış" dedi; açılışta yer kendiliğinden alınmaz.
  bool released = false;

  /// Lisansı kullanan öbür cihazın türü (android, iphone, windows, mac) ve son görülmesi.
  String? otherKind;
  DateTime? otherSeen;
  int transfersLeft = transferLimit;
  DateTime? nextTransfer;

  /// Son başarılı kontrol.
  DateTime? lastCheck;

  File? _file;
  bool loaded = false;

  /// Bu cihazın yeri: telefon/tablet ya da bilgisayar.
  static String get kind => Platform.isAndroid || Platform.isIOS ? 'telefon' : 'bilgisayar';

  /// Sunucuya gönderilen cihaz türü (ad değil).
  static String get label => Platform.isAndroid
      ? 'android'
      : Platform.isIOS
          ? 'iphone'
          : Platform.isWindows
              ? 'windows'
              : Platform.isMacOS
                  ? 'mac'
                  : 'diger';

  /// Cihaz türünün okunur adı.
  static String kindName(String? k) => switch (k) {
        'android' => tr('Android telefon ya da tablet'),
        'iphone' || 'ipad' => tr('iPhone ya da iPad'),
        'windows' => tr('Windows bilgisayar'),
        'mac' => tr('Mac bilgisayar'),
        _ => tr('başka bir cihaz'),
      };

  /// Mağaza fişinden lisans anahtarı (fişin kendisi gönderilmez).
  static String keyFor(String receipt) => sha256.convert(utf8.encode('netice-lisans|$receipt')).toString();

  Future<void> load({Directory? dir}) async {
    if (loaded && dir == null) return;
    try {
      final base = dir ?? await getApplicationSupportDirectory();
      _file = File('${base.path}${Platform.pathSeparator}cihaz_siniri.json');
      if (await _file!.exists()) {
        final j = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
        key = j['key'] as String?;
        blocked = j['blocked'] as bool? ?? false;
        released = j['released'] as bool? ?? false;
        otherKind = j['otherKind'] as String?;
        otherSeen = DateTime.tryParse('${j['otherSeen'] ?? ''}');
        transfersLeft = (j['transfersLeft'] as num?)?.toInt() ?? transferLimit;
        nextTransfer = DateTime.tryParse('${j['nextTransfer'] ?? ''}');
        lastCheck = DateTime.tryParse('${j['lastCheck'] ?? ''}');
      }
    } catch (_) {}
    loaded = true;
  }

  Future<void> _save() async {
    notifyListeners();
    try {
      await _file?.parent.create(recursive: true);
      await _file?.writeAsString(jsonEncode({
        if (key != null) 'key': key,
        'blocked': blocked,
        'released': released,
        if (otherKind != null) 'otherKind': otherKind,
        if (otherSeen != null) 'otherSeen': otherSeen!.toIso8601String(),
        'transfersLeft': transfersLeft,
        if (nextTransfer != null) 'nextTransfer': nextTransfer!.toIso8601String(),
        if (lastCheck != null) 'lastCheck': lastCheck!.toIso8601String(),
      }));
    } catch (_) {}
  }

  /// Sunucuya istek (test için değiştirilebilir). Ulaşılamazsa null.
  @visibleForTesting
  Future<Map<String, dynamic>?> Function(String path, Map<String, dynamic> body) send = _post;

  static Future<Map<String, dynamic>?> _post(String path, Map<String, dynamic> body) async {
    try {
      final r = await http
          .post(Uri.parse('$deviceLimitUrl/$path'),
              headers: {'content-type': 'application/json', 'x-netice-app': 'netice-app-1'}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return null;
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _body(String k, {bool transfer = false}) async {
    await AiUsage.instance.load();
    return {'anahtar': k, 'cihaz': AiUsage.instance.device, 'tur': kind, 'ad': label, if (transfer) 'devret': true};
  }

  /// Etkin aboneliğin mağaza fişiyle bu cihazı kaydeder. Açılışta ve satın
  /// almada çağrılır. Sonuç: true = Pro bu cihazda açık, false = başka cihazda.
  /// Sunucuya ulaşılamazsa son durum geçerli kalır.
  Future<bool> check(String receipt) async {
    await load();
    final k = keyFor(receipt);
    if (k != key) {
      // Yeni lisans (yeni satın alma ya da yenilenen Windows lisansı).
      key = k;
      released = false;
    }
    if (released) {
      blocked = true;
      await _save();
      return false;
    }
    return _apply(await send('kayit', await _body(k)));
  }

  /// "Bu cihazda kullan": öbür cihaz çıkar, Pro burada açılır. Hata varsa metni döner.
  Future<String?> useHere() async {
    await load();
    final k = key;
    if (k == null) return tr('Önce "Satın alımları geri yükle" düğmesine dokunun.');
    released = false;
    final r = await send('kayit', await _body(k, transfer: true));
    if (r == null) return tr('İnternet bağlantısı yok. Bağlanıp tekrar deneyin.');
    if (!await _apply(r)) {
      return nextTransfer == null
          ? tr('Pro\'nuz şu an başka bir cihazda açık.')
          : tr('Bu ay cihaz değiştirme hakkınız doldu. {0} tarihinden sonra yeniden deneyebilirsiniz.', [L10n.date(nextTransfer!)]);
    }
    return null;
  }

  /// "Bu cihazdan çıkış": yer boşalır, Pro öbür cihazda açılabilir. Hata varsa metni döner.
  Future<String?> signOut() async {
    await load();
    final k = key;
    if (k == null) return null;
    final r = await send('birak', await _body(k));
    if (r == null) return tr('İnternet bağlantısı yok. Bağlanıp tekrar deneyin.');
    released = true;
    blocked = true;
    otherKind = null;
    otherSeen = null;
    await _save();
    return null;
  }

  Future<bool> _apply(Map<String, dynamic>? r) async {
    if (r == null) return !blocked; // çevrimdışı: son durum
    lastCheck = DateTime.now();
    transfersLeft = (r['devirKalan'] as num?)?.toInt() ?? transfersLeft;
    nextTransfer = DateTime.tryParse('${r['sonrakiDevir'] ?? ''}');
    if (r['durum'] == 'tamam') {
      blocked = false;
      otherKind = null;
      otherSeen = null;
    } else if (r['durum'] == 'dolu') {
      blocked = true;
      final o = r['diger'];
      otherKind = o is Map ? '${o['ad'] ?? ''}' : null;
      otherSeen = o is Map ? DateTime.tryParse('${o['son'] ?? ''}')?.toLocal() : null;
    }
    await _save();
    return !blocked;
  }

  /// Abonelik bittiğinde ya da testlerde sıfırlar.
  @visibleForTesting
  void reset() {
    key = null;
    blocked = false;
    released = false;
    otherKind = null;
    otherSeen = null;
    transfersLeft = transferLimit;
    nextTransfer = null;
    lastCheck = null;
  }
}
