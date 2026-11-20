import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/ad_admin.dart';
import 'package:netice/core/ads.dart';
import 'package:netice/core/store.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/ad_slot.dart';

void main() {
  test('reklam listesi JSON gidiş-dönüş', () {
    final ads = [
      Ad(
        id: 'r1',
        name: 'Kampanya',
        type: AdType.video,
        media: 'https://raw.githubusercontent.com/emrgngr/netice/reklamlar/reklam/medya/r1.mp4',
        link: 'https://ornek.com',
        format: AdFormat.banner,
        pages: const [AdPage.home, AdPage.exam],
        start: DateTime(2026, 11, 1),
        end: DateTime(2026, 12, 31),
        seconds: 12,
      ),
      const Ad(id: 'r2', type: AdType.image, media: 'https://x.com/a.jpg'),
    ];
    final back = Ad.listFromJson(jsonDecode(Ad.listToJson(ads)));
    expect(back.length, 2);
    expect(back[0].type, AdType.video);
    expect(back[0].format, AdFormat.banner);
    expect(back[0].pages, [AdPage.home, AdPage.exam]);
    expect(back[0].end, DateTime(2026, 12, 31));
    expect(back[0].seconds, 12);
    expect(back[1].allPages, isTrue);
    expect(back[1].showsOn(AdPage.term), isTrue);
    expect(back[0].showsOn(AdPage.term), isFalse);
  });

  test('tarih ve açık/kapalı süzgeci', () {
    final a = Ad(id: 'a', type: AdType.image, media: 'https://x/a.jpg', start: DateTime(2026, 11, 10), end: DateTime(2026, 11, 20));
    expect(a.runningAt(DateTime(2026, 11, 9, 23)), isFalse);
    expect(a.runningAt(DateTime(2026, 11, 10, 8)), isTrue);
    expect(a.runningAt(DateTime(2026, 11, 20, 23, 59)), isTrue);
    expect(a.runningAt(DateTime(2026, 11, 21)), isFalse);
    expect(a.copyWith(active: false).runningAt(DateTime(2026, 11, 15)), isFalse);
  });

  test('bozuk kayıtlar atlanır', () {
    final l = Ad.listFromJson({
      'reklamlar': [
        {'id': 'x'},
        {'id': 'y', 'dosya': 'https://a/b.png', 'sayfalar': ['hepsi', 'olmayan', 'sinav']},
        'metin',
      ]
    });
    expect(l.single.id, 'y');
    expect(l.single.pages, [AdPage.exam]);
  });

  testWidgets('Pro abonesine reklam gösterilmez', (tester) async {
    final file = File('test/fixtures/ads/kart.jpg');
    AdService.instance.debugSet(
      [const Ad(id: 'k', type: AdType.image, media: 'https://x/kart.jpg')],
      {'https://x/kart.jpg': file},
    );
    final store = AppStore();
    Widget app() => StoreScope(
          store: store,
          child: const MaterialApp(home: Scaffold(body: AdSlot.card(AdPage.home))),
        );
    await tester.pumpWidget(app());
    expect(find.text('Reklam'), findsOneWidget);
    expect(find.byType(AdSlot), findsOneWidget);

    // Başka sayfaya ayrılmış reklam burada görünmez.
    await tester.pumpWidget(StoreScope(
      store: store,
      child: const MaterialApp(home: Scaffold(body: AdSlot.banner(AdPage.home))),
    ));
    expect(find.text('Reklam'), findsNothing);

    store.proConfirmedAt = DateTime.now();
    await tester.pumpWidget(app());
    expect(find.text('Reklam'), findsNothing);
    AdService.instance.debugSet(const [], const {});
  });

  test('yönetici kodu: kod düz metin saklanmaz, yanlışlar kilitler', () async {
    final a = AdAdmin.instance;
    expect(AdAdmin.validPin('12345'), isFalse);
    expect(AdAdmin.validPin('123456'), isTrue);
    expect(AdAdmin.validPin('12a456'), isFalse);
    await a.setPin('482913');
    expect(a.hasPin, isTrue);
    expect(await a.checkPin('482913'), isTrue);
    for (var i = 0; i < 5; i++) {
      expect(await a.checkPin('000000'), isFalse);
    }
    expect(a.lockSeconds, greaterThan(0));
    // Kilitliyken doğru kod da kabul edilmez.
    expect(await a.checkPin('482913'), isFalse);
    a.token = 'github_pat_ornek';
    expect(await a.resetPinWithToken('yanlis'), isFalse);
    expect(await a.resetPinWithToken('github_pat_ornek'), isTrue);
    expect(a.hasPin, isFalse);
  });
}
