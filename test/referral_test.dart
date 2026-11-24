import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/price_increase.dart';
import 'package:netice/core/pro.dart';
import 'package:netice/core/referral.dart';
import 'package:netice/core/store.dart';

Future<AppStore> _store(String name) async {
  final s = AppStore();
  await s.load(dir: Directory.systemTemp.createTempSync(name));
  s.trialStart = DateTime.now().subtract(const Duration(days: 30)); // deneme bitti
  return s;
}

void main() {
  setUp(() => AppStore.proFreeOnThisPlatform = false);

  test('davet kodu biçimi ve sağlama harfi', () {
    final r = math.Random(7);
    for (var i = 0; i < 200; i++) {
      final c = Referral.newInviteCode(r);
      expect(c, matches(RegExp(r'^[0-9A-Z]{4}-[0-9A-Z]{4}$')));
      expect(Referral.isValidInvite(c), isTrue);
      expect(Referral.isValidInvite(c.toLowerCase().replaceAll('-', ' ')), isTrue);
    }
    final c = Referral.newInviteCode(r);
    // Tek harf yanlış yazılırsa yakalanır.
    final wrong = '${c.substring(0, 2)}${c[2] == 'A' ? 'B' : 'A'}${c.substring(3)}';
    expect(Referral.isValidInvite(wrong), isFalse);
    expect(Referral.isValidInvite('ABC'), isFalse);
    expect(Referral.isValidInvite('0000-0000'), isFalse); // 0 alfabede yok
  });

  test('indirimli fiyat: 399 → 339, 29,99 → 25,49', () {
    expect(discountPriceText('399 TL / yıl', 0.15), '339 TL / yıl');
    expect(discountPriceText('\$29.99 / year', 0.15), '\$25.49 / year');
    final plans = ProService.plansFor(DateTime(2026, 11, 24), invite: true);
    expect(plans.first.price, '339 TL / yıl');
    expect(plans.first.oldPrice, '399 TL / yıl');
    // Ertesi yıl indirim artırılmış fiyata uygulanır.
    expect(ProService.plansFor(DateTime(2027, 11, 20), invite: true).first.price, '441 TL / yıl');
  });

  test('davet kodu uygulanır; kendi kodu ve hatalı kod reddedilir', () async {
    final a = await _store('davetA');
    final b = await _store('davetB');
    expect(b.applyInvite('yanlış'), isNotNull);
    expect(b.applyInvite(b.myInviteCode), isNotNull);
    expect(b.applyInvite(a.myInviteCode.toLowerCase()), isNull);
    expect(b.appliedInvite, a.myInviteCode);
  });

  test('teşekkür kodu davet edene 1 ay Pro verir, bir kez kullanılır', () async {
    final a = await _store('tskA');
    final b = await _store('tskB');
    final c = await _store('tskC');
    expect(a.isPro, isFalse);

    // Teşekkür kodu yalnızca davet koduyla alımdan sonra üretilir.
    b.onInvitePurchase();
    expect(b.thanksCode, isNull);
    b.applyInvite(a.myInviteCode);
    b.onInvitePurchase();
    final thanks = b.thanksCode!;
    expect(thanks, startsWith('TSK-'));

    // Başkasının (C) cihazında geçersiz.
    expect(c.redeemThanks(thanks), isNotNull);
    expect(c.isPro, isFalse);

    final now = DateTime.now();
    expect(a.redeemThanks(thanks.toLowerCase(), now: now), isNull);
    expect(a.isPro, isTrue);
    expect(a.bonusProUntil!.difference(now).inDays, 30);
    // Aynı kod ikinci kez işe yaramaz.
    expect(a.redeemThanks(thanks, now: now), isNotNull);
    expect(a.bonusProUntil!.difference(now).inDays, 30);

    // İkinci arkadaş: süre üzerine eklenir.
    c.applyInvite(a.myInviteCode);
    c.onInvitePurchase();
    expect(a.redeemThanks(c.thanksCode!, now: now), isNull);
    expect(a.bonusProUntil!.difference(now).inDays, 60);

    // Kurcalanmış kod reddedilir.
    final t = thanks.substring(0, thanks.length - 1) + (thanks.endsWith('A') ? 'B' : 'A');
    expect(Referral.verifyThanks(t, myInvite: a.myInviteCode), isNull);
  });

  test('davet bilgileri cihaz kaydına yazılır', () async {
    final dir = Directory.systemTemp.createTempSync('davetKayit');
    final a = AppStore();
    await a.load(dir: dir);
    final code = a.myInviteCode;
    a.applyInvite(Referral.newInviteCode());
    final j = a.toJsonMap();
    expect(j['inviteCode'], code);
    expect(j['appliedInvite'], isNotNull);
  });
}
