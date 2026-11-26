import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'google_auth.dart';
import 'store.dart';
import 'sync_merge.dart';
import '../l10n/l10n.dart';

/// Google Drive yedeği ve cihazlar arası eşitleme.
///
/// Yedek ve eşitleme dosyası, öğretmenin kendi Drive hesabında yalnızca bu
/// uygulamanın görebildiği gizli "uygulama verisi" klasörüne yazılır
/// (drive.appdata izni). Netice'nin sunucusu yoktur; veri hiçbir yere
/// aktarılmaz.
class CloudConfig {
  static bool get platformSupported => GoogleConfig.platformSupported;
  static bool get configured => GoogleConfig.configured;
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

  static const _scopes = [GoogleScopes.driveAppData];
  static const _fileName = 'netice_yedek.json';
  static const _syncName = 'netice_esitleme.json';

  GoogleAuth get _auth => GoogleAuth.instance;

  /// Uygulama açılırken sessizce oturumu geri yükler, günlük yedeği bağlar
  /// ve eşitleme açıksa öteki cihazlardaki değişiklikleri alır.
  Future<void> attach(AppStore store) async {
    if (!CloudConfig.configured) return;
    store.onDailyBackup = () async {
      if (store.googleEmail != null && store.cloudAuto && store.isPro) await backup(store, interactive: false);
    };
    store.onSyncDue = () {
      if (store.googleEmail != null && store.syncEnabled && store.isPro) {
        sync(store, interactive: false).catchError((_) => null);
      }
    };
    // Uygulamaya dönünce (ör. bilgisayarda açılan sınav telefona) güncelle.
    _life ??= AppLifecycleListener(onResume: () => store.onSyncDue?.call());
    if (store.googleEmail == null) return;
    await _auth.restore();
    if (store.syncEnabled && store.isPro) {
      try {
        await sync(store, interactive: false);
      } catch (_) {}
    }
  }

  /// Google hesabıyla giriş yapar; başarılıysa hesap bilgisini kaydeder.
  Future<void> signIn(AppStore store, {List<String> scopes = _scopes}) async {
    final u = await _auth.signIn(scopes);
    store.setGoogleAccount(u.email, u.name);
  }

  Future<void> signOut(AppStore store) async {
    try {
      await _auth.signOut();
    } catch (_) {}
    store.setGoogleAccount(null, null);
    store.setSyncEnabled(false);
  }

  Future<Map<String, String>> _headers({required bool interactive}) =>
      _auth.headers(_scopes, interactive: interactive);

  /// Uygulama klasöründeki [name] dosyası (yoksa null).
  Future<CloudBackupInfo?> _find(String name, Map<String, String> h) async {
    final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
      'spaces': 'appDataFolder',
      'q': "name = '$name' and trashed = false",
      'fields': 'files(id,modifiedTime,size)',
      'orderBy': 'modifiedTime desc',
    });
    final r = await http.get(uri, headers: h);
    if (r.statusCode != 200) throw HttpException(tr('Drive listesi alınamadı ({0})', [r.statusCode]));
    final files = (jsonDecode(r.body)['files'] as List).cast<Map<String, dynamic>>();
    if (files.isEmpty) return null;
    final f = files.first;
    return CloudBackupInfo(
        f['id'] as String, DateTime.tryParse(f['modifiedTime'] as String? ?? ''), int.tryParse('${f['size']}') ?? 0);
  }

  /// [name] dosyasını yazar (varsa üzerine).
  Future<void> _write(String name, List<int> body, Map<String, String> h, CloudBackupInfo? existing) async {
    http.Response r;
    if (existing == null) {
      const boundary = 'netice_yedek_sinir';
      final meta = jsonEncode({
        'name': name,
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
    if (r.statusCode != 200) throw HttpException(tr('Drive\'a yazılamadı ({0})', [r.statusCode]));
  }

  Future<String> _read(String id, Map<String, String> h) async {
    final r = await http.get(Uri.parse('https://www.googleapis.com/drive/v3/files/$id?alt=media'), headers: h);
    if (r.statusCode != 200) throw HttpException(tr('Drive yedeği indirilemedi ({0})', [r.statusCode]));
    return utf8.decode(r.bodyBytes);
  }

  bool _syncing = false;
  AppLifecycleListener? _life;

  /// Cihazlar arası eşitleme: Drive'daki ortak dosyayı indirir, bu cihazdaki
  /// veriyle birleştirir (bkz. sync_merge.dart), sonucu hem buraya hem
  /// Drive'a yazar. Aynı Google hesabıyla giriş yapılan tüm telefon, tablet
  /// ve bilgisayarlar aynı dosyayı paylaşır.
  Future<SyncMergeResult?> sync(AppStore store, {bool interactive = true}) async {
    if (_syncing) return null;
    _syncing = true;
    try {
      final h = await _headers(interactive: interactive);
      final info = await _find(_syncName, h);
      final remote = info == null ? null : jsonDecode(await _read(info.id, h)) as Map<String, dynamic>;
      final res = syncMerge(store.syncPayload(), remote, store.syncBase);
      if (res.incoming > 0) await store.applySync(res.merged);
      if (res.outgoing > 0 || info == null) {
        final body = utf8.encode(jsonEncode({
          'app': 'netice',
          'kind': 'sync',
          'version': 1,
          'savedAt': DateTime.now().toIso8601String(),
          ...res.merged,
        }));
        await _write(_syncName, body, h, info);
      }
      store.markSynced(syncFingerprints(res.merged), DateTime.now());
      return res;
    } finally {
      _syncing = false;
    }
  }

  /// Eşitleme dosyasını Drive'dan siler (eşitleme kapatılınca isteğe bağlı).
  Future<void> deleteSyncFile(AppStore store) async {
    final h = await _headers(interactive: true);
    final info = await _find(_syncName, h);
    if (info != null) {
      await http.delete(Uri.parse('https://www.googleapis.com/drive/v3/files/${info.id}'), headers: h);
    }
    store.markSynced(const {}, null);
  }

  Future<CloudBackupInfo?> latest({bool interactive = true}) async =>
      _find(_fileName, await _headers(interactive: interactive));

  /// Tüm veriyi Drive'daki tek yedek dosyasına yazar (varsa üzerine).
  Future<void> backup(AppStore store, {bool interactive = true}) async {
    final h = await _headers(interactive: interactive);
    final existing = await _find(_fileName, h);
    await _write(_fileName, utf8.encode(store.exportBackup()), h, existing);
    store.markCloudBackup(DateTime.now());
  }

  /// Drive'daki yedeği indirir ve geri yükler.
  Future<BackupSummary?> restore(AppStore store) async {
    final info = await latest();
    if (info == null) return null;
    final h = await _headers(interactive: true);
    return store.restoreBackup(await _read(info.id, h));
  }

  /// Drive'daki Netice yedeğini kalıcı olarak siler.
  Future<bool> deleteBackup(AppStore store) async {
    final info = await latest();
    if (info == null) return false;
    final h = await _headers(interactive: true);
    final r = await http.delete(Uri.parse('https://www.googleapis.com/drive/v3/files/${info.id}'), headers: h);
    if (r.statusCode != 204 && r.statusCode != 200) throw HttpException(tr('Drive yedeği silinemedi ({0})', [r.statusCode]));
    store.markCloudBackup(null);
    return true;
  }
}
