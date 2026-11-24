import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

/// "Arkadaşını davet et" kampanyası. Sunucu ve hesap gerektirmez.
///
/// * Her cihaz bir kez rastgele bir **davet kodu** üretir (ör. `K7QM-3XRA`).
///   Son harf bir sağlama harfidir; yanlış yazılan kod hemen yakalanır.
/// * Arkadaş, Pro ekranında bu kodu girerse yıllık abonelik **%15 indirimli**
///   teklifle açılır (Google Play'de "davet-indirimi" geliştirici teklifi,
///   App Store'da teklif kodu).
/// * Arkadaş indirimli aboneliği aldığında uygulaması bir **teşekkür kodu**
///   üretir (ör. `TSK-…`). Arkadaş bunu davet edene WhatsApp vb. ile gönderir;
///   davet eden kodu girince **1 ay ek Pro** kazanır. Teşekkür kodu yalnızca
///   o davet koduna aittir ve aynı arkadaştan bir kez kullanılabilir.
///
/// Teşekkür kodu uygulamaya gömülü bir anahtarla imzalanır (HMAC). Sunucu
/// olmadığı için bu tam bir güvenlik değil, sıradan taklide karşı bir
/// korumadır; kazanılabilecek ek süre de [maxRewards] ile sınırlıdır.
class Referral {
  Referral._();

  /// Arkadaşa verilen indirim (%15).
  static const discount = 0.15;

  /// Davet edenin her başarılı davet için kazandığı ek Pro süresi.
  static const rewardLength = Duration(days: 30);

  /// En fazla kaç davet ödülü alınabilir (12 ay).
  static const maxRewards = 12;

  /// Google Play'deki indirimli teklifin kimliği (yıllık aboneliğin temel
  /// planına eklenen geliştirici teklifi).
  static const playOfferId = 'davet-indirimi';

  /// App Store Connect'te tanımlanacak özel teklif kodu.
  static const appStoreOfferCode = 'NETICEDAVET';

  // Karışmasın diye 0/O, 1/I/L ve U çıkarıldı (30 harf).
  static const _alphabet = '23456789ABCDEFGHJKMNPQRSTVWXYZ';

  static int _val(String c) => _alphabet.indexOf(c);

  static String _check(String body) {
    var sum = 0;
    for (var i = 0; i < body.length; i++) {
      sum += (_val(body[i]) + 1) * (i + 3);
    }
    return _alphabet[sum % _alphabet.length];
  }

  /// Rastgele, 7 harf + 1 sağlama harfi.
  static String newInviteCode([math.Random? rnd]) {
    final r = rnd ?? math.Random.secure();
    final body = List.generate(7, (_) => _alphabet[r.nextInt(_alphabet.length)]).join();
    return format(body + _check(body));
  }

  /// Boşlukları ve tireleri atar, büyük harfe çevirir.
  static String normalize(String raw) => raw.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');

  /// `ABCD-EFGH` biçimi.
  static String format(String code) {
    final c = normalize(code);
    return c.length == 8 ? '${c.substring(0, 4)}-${c.substring(4)}' : c;
  }

  /// Davet kodu biçimce doğru mu (8 harf, sağlama harfi tutuyor)?
  static bool isValidInvite(String raw) {
    final c = normalize(raw);
    if (c.length != 8) return false;
    for (final ch in c.split('')) {
      if (_val(ch) < 0) return false;
    }
    return _check(c.substring(0, 7)) == c[7];
  }

  static const _thanksPrefix = 'TSK';
  static final _key = utf8.encode('netice-davet-2026|7f3a9c51e2');

  static String _mac(String invite, String friend) {
    final d = Hmac(sha256, _key).convert(utf8.encode('${normalize(invite)}|${normalize(friend)}')).bytes;
    final b = StringBuffer();
    for (var i = 0; i < 8; i++) {
      b.write(_alphabet[d[i] % _alphabet.length]);
    }
    return b.toString();
  }

  /// Arkadaşın (indirimli aboneliği alan) cihazında üretilir: davet edenin
  /// kodu [invite], arkadaşın kendi davet kodu [friend] (arkadaşı tanımlar).
  static String thanksCode({required String invite, required String friend}) {
    final f = normalize(friend);
    final m = _mac(invite, f);
    return '$_thanksPrefix-${f.substring(0, 4)}-${f.substring(4)}-${m.substring(0, 4)}-${m.substring(4)}';
  }

  /// Davet edenin cihazında doğrulanır. Geçerliyse arkadaşın kimliğini
  /// (tekrar kullanımı önlemek için) döndürür, değilse null.
  static String? verifyThanks(String raw, {required String myInvite}) {
    final c = normalize(raw);
    if (!c.startsWith(_thanksPrefix) || c.length != _thanksPrefix.length + 16) return null;
    final friend = c.substring(3, 11);
    final mac = c.substring(11);
    if (!isValidInvite(friend) || normalize(friend) == normalize(myInvite)) return null;
    return _mac(myInvite, friend) == mac ? friend : null;
  }
}
