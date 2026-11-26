// Google ile giriş ve izin (erişim anahtarı) alma.
//
// Telefon ve tablette google_sign_in kullanılır. Windows ve Mac'te Google'ın
// "masaüstü uygulaması" akışı kullanılır: tarayıcı açılır, öğretmen Google'da
// izin verir, Google bu bilgisayardaki geçici bir adrese (127.0.0.1) döner.
// Hiçbir veri Netice'ye ait bir sunucudan geçmez.
//
// İzinler gerektikçe istenir: Drive yedeği yalnızca kendi gizli klasörünü,
// Classroom aktarımı yalnızca derslerinizi ve ödev notlarını ister.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';

class GoogleConfig {
  /// Google Cloud Console'da oluşturulan "Web uygulaması" türündeki OAuth
  /// istemci kimliği (Android'de giriş için gereklidir).
  static const serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID',
      defaultValue: '1093981917860-mn8966rkp1ttq34fag13b8o8qtc0mbhp.apps.googleusercontent.com');

  /// iOS istemci kimliği (iOS için).
  static const iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  /// Windows ve Mac için "Masaüstü uygulaması" türündeki OAuth istemcisi.
  /// Google'a göre masaüstü istemcinin parolası gizli sayılmaz; yine de
  /// koda yazılmaz, derlemede GitHub gizlilerinden verilir. Boşsa
  /// bilgisayarda Google girişi kapalıdır.
  static const desktopClientId = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_ID');
  static const desktopClientSecret = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_SECRET');

  static bool get mobile => Platform.isAndroid || Platform.isIOS;
  static bool get desktop => Platform.isWindows || Platform.isMacOS;

  /// Bu cihazda Google girişi mümkün mü?
  static bool get platformSupported => mobile || (desktop && desktopClientId.isNotEmpty);

  /// Giriş için gereken kimlikler derlemeye verilmiş mi?
  static bool get configured => mobile
      ? (Platform.isIOS ? iosClientId.isNotEmpty : serverClientId.isNotEmpty)
      : desktop && desktopClientId.isNotEmpty;
}

/// İzin kapsamları.
class GoogleScopes {
  static const driveAppData = 'https://www.googleapis.com/auth/drive.appdata';
  static const classroom = [
    'https://www.googleapis.com/auth/classroom.courses.readonly',
    'https://www.googleapis.com/auth/classroom.rosters.readonly',
    'https://www.googleapis.com/auth/classroom.profile.emails',
    'https://www.googleapis.com/auth/classroom.coursework.students',
  ];
}

class GoogleUser {
  final String email;
  final String? name;
  const GoogleUser(this.email, this.name);
}

abstract class GoogleAuth {
  static GoogleAuth? _instance;
  static GoogleAuth get instance => _instance ??= GoogleConfig.mobile ? _MobileAuth() : _DesktopAuth();

  /// Kayıtlı oturumu sessizce geri yükler (uygulama açılırken).
  Future<void> restore();

  /// Hesap seçtirir ve [scopes] iznini ister.
  Future<GoogleUser> signIn(List<String> scopes);

  Future<void> signOut();

  /// [scopes] için "Authorization" başlığı. [interactive] false ise ekran
  /// açılmaz; izin yoksa hata atar.
  Future<Map<String, String>> headers(List<String> scopes, {required bool interactive});
}

class _MobileAuth extends GoogleAuth {
  bool _init = false;
  GoogleSignInAccount? _account;

  Future<void> _ensureInit() async {
    if (_init) return;
    await GoogleSignIn.instance.initialize(
      clientId: Platform.isIOS && GoogleConfig.iosClientId.isNotEmpty ? GoogleConfig.iosClientId : null,
      serverClientId: GoogleConfig.serverClientId.isEmpty ? null : GoogleConfig.serverClientId,
    );
    _init = true;
  }

  @override
  Future<void> restore() async {
    try {
      await _ensureInit();
      _account = await GoogleSignIn.instance.attemptLightweightAuthentication();
    } catch (_) {}
  }

  @override
  Future<GoogleUser> signIn(List<String> scopes) async {
    await _ensureInit();
    final acc = await GoogleSignIn.instance.authenticate(scopeHint: scopes);
    _account = acc;
    return GoogleUser(acc.email, acc.displayName);
  }

  @override
  Future<void> signOut() async {
    try {
      await _ensureInit();
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    _account = null;
  }

  @override
  Future<Map<String, String>> headers(List<String> scopes, {required bool interactive}) async {
    await _ensureInit();
    _account ??= await GoogleSignIn.instance.attemptLightweightAuthentication();
    if (_account == null) {
      if (!interactive) throw StateError(tr('Google oturumu yok'));
      _account = await GoogleSignIn.instance.authenticate(scopeHint: scopes);
    }
    final client = _account!.authorizationClient;
    final auth = await client.authorizationForScopes(scopes) ??
        (interactive ? await client.authorizeScopes(scopes) : throw StateError(tr('Google izni yok')));
    return {'Authorization': 'Bearer ${auth.accessToken}'};
  }
}

/// Windows ve Mac: tarayıcıda izin + 127.0.0.1'e dönüş (PKCE ile).
class _DesktopAuth extends GoogleAuth {
  String? _refresh;
  String? _access;
  DateTime? _expires;
  final Set<String> _granted = {};

  static const _base = ['openid', 'email', 'profile'];

  /// Yenileme anahtarı veri dosyasından ayrı tutulur; yedeklere ve
  /// eşitlemeye hiç girmez.
  Future<File> _file() async {
    final d = await getApplicationSupportDirectory();
    return File('${d.path}${Platform.pathSeparator}google_oturum.json');
  }

  @override
  Future<void> restore() async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _refresh = j['refresh'] as String?;
      _granted
        ..clear()
        ..addAll([for (final s in (j['scopes'] as List? ?? const [])) '$s']);
    } catch (_) {}
  }

  Future<void> _persist() async {
    final f = await _file();
    if (_refresh == null) {
      if (await f.exists()) await f.delete();
      return;
    }
    await f.writeAsString(jsonEncode({'refresh': _refresh, 'scopes': _granted.toList()}));
  }

  static String _random(int n) {
    final r = math.Random.secure();
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    return List.generate(n, (_) => chars[r.nextInt(chars.length)]).join();
  }

  @override
  Future<GoogleUser> signIn(List<String> scopes) async {
    final want = {..._base, ..._granted, ...scopes};
    final verifier = _random(64);
    final challenge = base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
    final state = _random(24);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirect = 'http://127.0.0.1:${server.port}';
    try {
      final url = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': GoogleConfig.desktopClientId,
        'redirect_uri': redirect,
        'response_type': 'code',
        'scope': want.join(' '),
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'access_type': 'offline',
        'prompt': 'consent',
        'state': state,
      });
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw StateError(tr('Tarayıcı açılamadı.'));
      }
      String? code;
      String? error;
      await for (final req in server.timeout(const Duration(minutes: 5))) {
        final q = req.uri.queryParameters;
        if (q['state'] != state) {
          req.response.statusCode = 404;
          await req.response.close();
          continue;
        }
        code = q['code'];
        error = q['error'];
        req.response.headers.contentType = ContentType.html;
        req.response.write('<!doctype html><meta charset="utf-8"><body style="font-family:sans-serif;'
            'background:#0F1B3D;color:#fff;display:grid;place-items:center;height:90vh;text-align:center">'
            '<div><h2>Netice</h2><p>${code != null ? tr('Giriş tamamlandı. Netice\'ye dönebilirsiniz.') : tr('Giriş iptal edildi.')}</p></div>');
        await req.response.close();
        break;
      }
      if (code == null) throw StateError(error == 'access_denied' ? tr('giriş iptal edildi.') : (error ?? tr('giriş iptal edildi.')));
      final r = await http.post(Uri.parse('https://oauth2.googleapis.com/token'), body: {
        'client_id': GoogleConfig.desktopClientId,
        if (GoogleConfig.desktopClientSecret.isNotEmpty) 'client_secret': GoogleConfig.desktopClientSecret,
        'code': code,
        'code_verifier': verifier,
        'grant_type': 'authorization_code',
        'redirect_uri': redirect,
      });
      if (r.statusCode != 200) throw HttpException(tr('Google girişi tamamlanamadı ({0})', [r.statusCode]));
      _take(jsonDecode(r.body) as Map<String, dynamic>);
      await _persist();
      final u = await http.get(Uri.parse('https://openidconnect.googleapis.com/v1/userinfo'),
          headers: {'Authorization': 'Bearer $_access'});
      final j = u.statusCode == 200 ? jsonDecode(u.body) as Map<String, dynamic> : const <String, dynamic>{};
      return GoogleUser(j['email'] as String? ?? '', j['name'] as String?);
    } on TimeoutException {
      throw StateError(tr('giriş iptal edildi.'));
    } finally {
      await server.close(force: true);
    }
  }

  void _take(Map<String, dynamic> j) {
    _access = j['access_token'] as String?;
    _expires = DateTime.now().add(Duration(seconds: ((j['expires_in'] as num?) ?? 3600).toInt() - 60));
    if (j['refresh_token'] is String) _refresh = j['refresh_token'] as String;
    if (j['scope'] is String) _granted.addAll((j['scope'] as String).split(' ').where((s) => s.isNotEmpty));
  }

  @override
  Future<void> signOut() async {
    final t = _refresh;
    _refresh = _access = null;
    _granted.clear();
    await _persist();
    if (t != null) {
      try {
        await http.post(Uri.parse('https://oauth2.googleapis.com/revoke'), body: {'token': t});
      } catch (_) {}
    }
  }

  @override
  Future<Map<String, String>> headers(List<String> scopes, {required bool interactive}) async {
    final missing = scopes.where((s) => !_granted.contains(s)).isNotEmpty;
    if (_refresh == null || missing) {
      if (!interactive) throw StateError(missing ? tr('Google izni yok') : tr('Google oturumu yok'));
      await signIn(scopes);
    }
    if (_access == null || _expires == null || DateTime.now().isAfter(_expires!)) {
      final r = await http.post(Uri.parse('https://oauth2.googleapis.com/token'), body: {
        'client_id': GoogleConfig.desktopClientId,
        if (GoogleConfig.desktopClientSecret.isNotEmpty) 'client_secret': GoogleConfig.desktopClientSecret,
        'refresh_token': _refresh!,
        'grant_type': 'refresh_token',
      });
      if (r.statusCode != 200) {
        // İzin geri alınmış olabilir: oturumu kapat, öğretmen yeniden girsin.
        if (r.statusCode == 400 || r.statusCode == 401) {
          _refresh = null;
          await _persist();
        }
        throw HttpException(tr('Google oturumu yenilenemedi ({0})', [r.statusCode]));
      }
      _take(jsonDecode(r.body) as Map<String, dynamic>);
      await _persist();
    }
    return {'Authorization': 'Bearer $_access'};
  }
}
