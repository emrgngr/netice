import 'dart:convert';

import 'package:cryptography/dart.dart';
import 'package:cryptography/cryptography.dart';

/// Kurum lisansı: okul, dershane, POMEM, akademi veya fakülte için bir kod.
///
/// Kod internetsiz doğrulanır. Netice yönetimi kodu kendi gizli anahtarıyla
/// imzalar (bkz. `tool/kurum_lisans.dart` ve `.github/workflows/kurum-lisansi.yml`);
/// uygulamada yalnızca açık anahtar bulunur, bu yüzden kod taklit edilemez.
///
/// Biçim: `NTC1.<veri>.<imza>` (base64url). Veri JSON'dur:
/// `{"k": kurum adı, "i": kurum kimliği, "r": "o" öğretmen | "y" yönetici,
///   "u": "YYYY-MM-DD" bitiş, "n": öğretmen sayısı}`.
class InstitutionLicense {
  final String institution;
  final String id;
  final bool admin;
  final DateTime until;
  final int seats;
  final String code;

  const InstitutionLicense({
    required this.institution,
    required this.id,
    required this.admin,
    required this.until,
    required this.seats,
    required this.code,
  });

  /// Bitiş gününün sonuna kadar geçerli.
  bool activeAt(DateTime now) => now.isBefore(DateTime(until.year, until.month, until.day + 1));

  int daysLeft(DateTime now) {
    final end = DateTime(until.year, until.month, until.day + 1);
    return now.isAfter(end) ? 0 : (end.difference(now).inHours / 24).ceil();
  }

  static const prefix = 'NTC1';

  /// Netice kurum lisansı açık anahtarı (Ed25519). Gizli anahtar depoda
  /// değildir; GitHub'da KURUM_LISANS_ANAHTARI olarak saklanır.
  static const publicKeyB64 = 'OiHGCN0BL1UYgKxMmdr3xn-9qAKAGs6SqSc7QFms67A';

  /// Testlerde başka bir açık anahtar kullanmak için.
  static String? publicKeyOverride;

  static List<int> _b64(String s) => base64Url.decode(base64Url.normalize(s));

  /// Kodu çözer ve imzayı doğrular. Geçersizse null.
  static Future<InstitutionLicense?> verify(String raw) async {
    final code = raw.replaceAll(RegExp(r'\s'), '');
    final parts = code.split('.');
    if (parts.length != 3 || parts[0] != prefix) return null;
    try {
      final data = _b64(parts[1]);
      final sig = _b64(parts[2]);
      final pub = SimplePublicKey(_b64(publicKeyOverride ?? publicKeyB64), type: KeyPairType.ed25519);
      final ok = await DartEd25519().verify(data, signature: Signature(sig, publicKey: pub));
      if (!ok) return null;
      final j = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      final until = DateTime.tryParse('${j['u']}');
      final name = '${j['k'] ?? ''}'.trim();
      if (until == null || name.isEmpty) return null;
      return InstitutionLicense(
        institution: name,
        id: '${j['i'] ?? ''}',
        admin: j['r'] == 'y',
        until: until,
        seats: (j['n'] as num?)?.toInt() ?? 0,
        code: code,
      );
    } catch (_) {
      return null;
    }
  }

  /// Kodu imzalar (yalnızca Netice yönetiminin aracı ve testler kullanır).
  static Future<String> sign({
    required List<int> privateSeed,
    required String institution,
    required String id,
    required bool admin,
    required DateTime until,
    int seats = 0,
  }) async {
    final data = utf8.encode(jsonEncode({
      'k': institution,
      'i': id,
      'r': admin ? 'y' : 'o',
      'u': '${until.year.toString().padLeft(4, '0')}-${until.month.toString().padLeft(2, '0')}-${until.day.toString().padLeft(2, '0')}',
      'n': seats,
    }));
    final algo = DartEd25519();
    final kp = await algo.newKeyPairFromSeed(privateSeed);
    final sig = await algo.sign(data, keyPair: kp);
    String enc(List<int> b) => base64Url.encode(b).replaceAll('=', '');
    return '$prefix.${enc(data)}.${enc(sig.bytes)}';
  }

  /// Gizli tohumdan açık anahtarı üretir (anahtar kurulumu için).
  static Future<String> publicKeyOf(List<int> privateSeed) async {
    final kp = await DartEd25519().newKeyPairFromSeed(privateSeed);
    final pub = await kp.extractPublicKey();
    return base64Url.encode(pub.bytes).replaceAll('=', '');
  }
}
