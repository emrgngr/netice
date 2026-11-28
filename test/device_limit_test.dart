import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netice/bank/ai_questions.dart';
import 'package:netice/core/device_limit.dart';
import 'package:netice/core/pro.dart';
import 'package:netice/core/store.dart';

/// "Bir öğretmen, bir lisans": sunucu yerine sahte yanıtlar.
void main() {
  late Directory dir;
  late DeviceLimit d;
  final sent = <(String, Map<String, dynamic>)>[];
  Map<String, dynamic>? Function(String, Map<String, dynamic>) answer = (_, _) => {'durum': 'tamam', 'devirKalan': 3};

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cihaz_test');
    await AiUsage.instance.load(dir: dir);
    d = DeviceLimit.forTest();
    await d.load(dir: dir);
    d.send = (path, body) async {
      sent.add((path, body));
      return answer(path, body);
    };
    DeviceLimit.instance = d;
    sent.clear();
    answer = (_, _) => {'durum': 'tamam', 'devirKalan': 3};
  });

  tearDown(() async {
    DeviceLimit.instance = DeviceLimit.forTest();
    await dir.delete(recursive: true);
  });

  test('fişin kendisi gönderilmez, yalnız özeti', () async {
    expect(await d.check('play:gizli-jeton'), isTrue);
    final body = sent.single.$2;
    expect(body['anahtar'], DeviceLimit.keyFor('play:gizli-jeton'));
    expect(body['anahtar'], hasLength(64));
    expect(body.toString(), isNot(contains('gizli-jeton')));
    expect(body['cihaz'], AiUsage.instance.device);
    expect(body.containsKey('devret'), isFalse);
  });

  test('başka cihazda açıksa abonelik bu cihazda sayılmaz', () async {
    final s = AppStore()..confirmPro(proYearlyId);
    expect(s.hasSubscription, isTrue);
    answer = (_, _) => {
          'durum': 'dolu',
          'diger': {'ad': 'iphone', 'son': '2026-11-26T09:00:00.000Z'},
          'devirKalan': 2,
        };
    expect(await d.check('apple:1000'), isFalse);
    expect(s.hasSubscription, isFalse);
    expect(s.subscriptionOnOtherDevice, isTrue);
    expect(d.otherKind, 'iphone');
    expect(d.transfersLeft, 2);

    // Durum dosyaya yazılır, yeniden açılışta korunur.
    final again = DeviceLimit.forTest();
    await again.load(dir: dir);
    expect(again.blocked, isTrue);

    // Çevrimdışı: son durum geçerli kalır.
    answer = (_, _) => null;
    expect(await d.check('apple:1000'), isFalse);

    // "Bu cihazda kullan": devret ile istenir.
    answer = (_, _) => {'durum': 'tamam', 'devredildi': true, 'devirKalan': 1};
    expect(await d.useHere(), isNull);
    expect(sent.last.$2['devret'], isTrue);
    expect(s.hasSubscription, isTrue);
    expect(s.subscriptionOnOtherDevice, isFalse);
  });

  test('sunucuya ulaşılamazsa Pro açık kalır', () async {
    answer = (_, _) => null;
    final s = AppStore()..confirmPro(proYearlyId);
    expect(await d.check('play:x'), isTrue);
    expect(s.hasSubscription, isTrue);
  });

  test('bu cihazdan çıkış: açılışta yer kendiliğinden alınmaz', () async {
    await d.check('play:x');
    expect(await d.signOut(), isNull);
    expect(sent.last.$1, 'birak');
    expect(d.blocked, isTrue);
    sent.clear();
    expect(await d.check('play:x'), isFalse);
    expect(sent, isEmpty);
    // Yeni bir satın alma (başka fiş) çıkışı sıfırlar.
    expect(await d.check('play:yeni'), isTrue);
    expect(d.released, isFalse);
  });

  test('devir hakkı dolunca tarih bildirilir', () async {
    answer = (_, _) => {'durum': 'dolu', 'diger': {'ad': 'android', 'son': '2026-11-27T09:00:00Z'}, 'devirKalan': 0, 'sonrakiDevir': '2026-12-20T09:00:00Z'};
    await d.check('play:x');
    final err = await d.useHere();
    expect(err, isNotNull);
    expect(d.nextTransfer, DateTime.parse('2026-12-20T09:00:00Z'));
  });
}
