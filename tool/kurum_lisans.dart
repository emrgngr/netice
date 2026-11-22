// Kurum lisans kodu üretir.
//
// Kullanım (gizli anahtar ortam değişkeninde):
//   KURUM_LISANS_ANAHTARI=... dart run tool/kurum_lisans.dart \
//       --kurum "Atatürk Anadolu Lisesi" --bitis 2027-09-30 --ogretmen 40 [--yonetici]
//
// Yeni anahtar çifti üretmek için (yalnız bir kez):
//   dart run tool/kurum_lisans.dart --yeni-anahtar
//
// Gizli anahtar asla depoya konmaz; GitHub'da KURUM_LISANS_ANAHTARI secret'ı
// olarak durur. Açık anahtar lib/core/license.dart içindedir.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:netice/core/license.dart';

Future<void> main(List<String> args) async {
  String? arg(String name) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  if (args.contains('--yeni-anahtar')) {
    final r = Random.secure();
    final seed = List<int>.generate(32, (_) => r.nextInt(256));
    stdout.writeln('Gizli anahtar (KURUM_LISANS_ANAHTARI): ${base64Url.encode(seed).replaceAll('=', '')}');
    stdout.writeln('Açık anahtar (license.dart publicKeyB64): ${await InstitutionLicense.publicKeyOf(seed)}');
    return;
  }

  final secret = Platform.environment['KURUM_LISANS_ANAHTARI']?.trim() ?? '';
  final kurum = arg('--kurum')?.trim() ?? '';
  final bitis = DateTime.tryParse(arg('--bitis') ?? '');
  if (secret.isEmpty || kurum.isEmpty || bitis == null) {
    stderr.writeln('Eksik bilgi: KURUM_LISANS_ANAHTARI, --kurum ve --bitis (YYYY-AA-GG) gerekli.');
    exit(2);
  }
  final seed = base64Url.decode(base64Url.normalize(secret));
  final id = arg('--kimlik') ??
      kurum.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
  final admin = args.contains('--yonetici');
  final seats = int.tryParse(arg('--ogretmen') ?? '') ?? 0;
  final code = await InstitutionLicense.sign(
      privateSeed: seed, institution: kurum, id: id, admin: admin, until: bitis, seats: seats);
  final check = await InstitutionLicense.verify(code);
  if (check == null) {
    stderr.writeln('Uyarı: kod uygulamadaki açık anahtarla doğrulanamadı. Gizli anahtar doğru mu?');
    exit(1);
  }
  stdout.writeln(code);
}
