import 'dart:convert';
import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'store.dart';

/// Google ile giriş ve Google Drive yedeği.
///
/// Yedek, öğretmenin kendi Drive hesabında yalnızca bu uygulamanın
/// görebildiği gizli "uygulama verisi" klasörüne yazılır (drive.appdata
/// izni). Netice'nin sunucusu yoktur; veri hiçbir yere aktarılmaz.
class CloudConfig {
  /// Google Cloud Console'da oluşturulan "Web uygulaması" türündeki OAuth
  /// istemci kimliği (Android'de giriş için gereklidir). Boşsa Google girişi
  /// kapalıdır ve ayarlarda kurulum bekleniyor yazar.
  static const serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  /// iOS istemci kimliği (iOS için).
  static const iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  static bool get platformSupported => Platform.isAndroid || Platform.isIOS;
  static bool get configured =>
      platformSupported && (Platform.isIOS ? iosClientId.isNotEmpty : serverClientId.isNotEmpty);
}

class CloudBackupInfo {
  final String id;
  final DateTime? modified;
  final int size;
  const CloudBackupInfo(this.id, this.modified, this.size);
}

class CloudService {
  CloudService._();
  static final instance = CloudService._();

  static const _scopes = ['https://www.googleapis.com/auth/drive.appdata'];
  static const _fileName = 'netice_yedek.json';

  bool _init = false;
  GoogleSignInAccount? _account;

  Future<void> _ensureInit() async {
    if (_init) return;
    await GoogleSignIn.instance.initialize(
      clientId: Platform.isIOS && CloudConfig.iosClientId.isNotEmpty ? CloudConfig.iosClientId : null,
      serverClientId: CloudConfig.serverClientId.isEmpty ? null : CloudConfig.serverClientId,
    );
    _init = true;
  }

  /// Uygulama açılırken sessizce oturumu geri yükler ve günlük yedeği bağlar.
  Future<void> attach(AppStore store) async {
    if (!CloudConfig.configured) return;
    store.onDailyBackup = () async {
      if (store.googleEmail != null && store.cloudAuto) await backup(store, interactive: false);
    };
    if (store.googleEmail == null) return;
    try {
      await _ensureInit();
      _account = await GoogleSignIn.instance.attemptLightweightAuthentication();
    } catch (_) {}
  }

  /// Google hesabıyla giriş yapar; başarılıysa hesap bilgisini kaydeder.
  Future<void> signIn(AppStore store) async {
    await _ensureInit();
    final acc = await GoogleSignIn.instance.authenticate(scopeHint: _scopes);
    _account = acc;
    store.setGoogleAccount(acc.email, acc.displayName);
  }

  Future<void> signOut(AppStore store) async {
    try {
      await _ensureInit();
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    _account = null;
    store.setGoogleAccount(null, null);
  }

  Future<Map<String, String>> _headers({required bool interactive}) async {
    await _ensureInit();
    _account ??= await GoogleSignIn.instance.attemptLightweightAuthentication();
    if (_account == null) {
      if (!interactive) throw StateError('Google oturumu yok');
      _account = await GoogleSignIn.instance.authenticate(scopeHint: _scopes);
    }
    final client = _account!.authorizationClient;
    final auth = await client.authorizationForScopes(_scopes) ??
        (interactive ? await client.authorizeScopes(_scopes) : throw StateError('Drive izni yok'));
    return {'Authorization': 'Bearer ${auth.accessToken}'};
  }

  Future<CloudBackupInfo?> latest({bool interactive = true}) async {
    final h = await _headers(interactive: interactive);
    final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
      'spaces': 'appDataFolder',
      'q': "name = '$_fileName' and trashed = false",
      'fields': 'files(id,modifiedTime,size)',
    });
    final r = await http.get(uri, headers: h);
    if (r.statusCode != 200) throw HttpException('Drive listesi alınamadı (${r.statusCode})');
    final files = (jsonDecode(r.body)['files'] as List).cast<Map<String, dynamic>>();
    if (files.isEmpty) return null;
    final f = files.first;
    return CloudBackupInfo(
        f['id'] as String, DateTime.tryParse(f['modifiedTime'] as String? ?? ''), int.tryParse('${f['size']}') ?? 0);
  }

  /// Tüm veriyi Drive'daki tek yedek dosyasına yazar (varsa üzerine).
  Future<void> backup(AppStore store, {bool interactive = true}) async {
    final h = await _headers(interactive: interactive);
    final body = utf8.encode(store.exportBackup());
    final existing = await latest(interactive: interactive);
    http.Response r;
    if (existing == null) {
      const boundary = 'netice_yedek_sinir';
      final meta = jsonEncode({
        'name': _fileName,
        'parents': ['appDataFolder'],
        'mimeType': 'application/json',
      });
      final multipart = <int>[
        ...utf8.encode('--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$meta\r\n'),
        ...utf8.encode('--$boundary\r\nContent-Type: application/json\r\n\r\n'),
        ...body,
        ...utf8.encode('\r\n--$boundary--'),
      ];
      r = await http.post(Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart'),
          headers: {...h, 'Content-Type': 'multipart/related; boundary=$boundary'}, body: multipart);
    } else {
      r = await http.patch(
          Uri.parse('https://www.googleapis.com/upload/drive/v3/files/${existing.id}?uploadType=media'),
          headers: {...h, 'Content-Type': 'application/json'},
          body: body);
    }
    if (r.statusCode != 200) throw HttpException('Drive yedeği yazılamadı (${r.statusCode})');
    store.markCloudBackup(DateTime.now());
  }

  /// Drive'daki yedeği indirir ve geri yükler.
  Future<BackupSummary?> restore(AppStore store) async {
    final info = await latest();
    if (info == null) return null;
    final h = await _headers(interactive: true);
    final r = await http.get(Uri.parse('https://www.googleapis.com/drive/v3/files/${info.id}?alt=media'), headers: h);
    if (r.statusCode != 200) throw HttpException('Drive yedeği indirilemedi (${r.statusCode})');
    return store.restoreBackup(utf8.decode(r.bodyBytes));
  }

  /// Drive'daki Netice yedeğini kalıcı olarak siler.
  Future<bool> deleteBackup(AppStore store) async {
    final info = await latest();
    if (info == null) return false;
    final h = await _headers(interactive: true);
    final r = await http.delete(Uri.parse('https://www.googleapis.com/drive/v3/files/${info.id}'), headers: h);
    if (r.statusCode != 204 && r.statusCode != 200) throw HttpException('Drive yedeği silinemedi (${r.statusCode})');
    store.markCloudBackup(null);
    return true;
  }
}
