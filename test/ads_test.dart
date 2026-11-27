import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/ad_admin.dart';
import 'package:netice/core/ads.dart';
import 'package:netice/core/store.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/ad_admin_screen.dart';
import 'package:netice/ui/ad_slot.dart';
import 'package:netice/ui/logo.dart';
import 'package:netice/ui/settings_screen.dart';

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

  test('slider reklam: görseller, geçiş ve eski sürüm uyumu', () {
    const urls = ['https://x/1.jpg', 'https://x/2.jpg', 'https://x/3.jpg'];
    const ad = Ad(
      id: 's',
      type: AdType.slider,
      media: 'https://x/1.jpg',
      slides: urls,
      style: SlideStyle.flip,
      seconds: 3,
    );
    final j = ad.toJson();
    expect(j['tur'], 'slider');
    expect(j['dosya'], urls.first); // eski sürümler ilk görseli sabit gösterir
    final back = Ad.fromJson(jsonDecode(jsonEncode(j)) as Map<String, dynamic>)!;
    expect(back.type, AdType.slider);
    expect(back.slides, urls);
    expect(back.style, SlideStyle.flip);
    expect(back.seconds, 3);
    expect(back.sources, urls);
    // Tek görselli slider sabit görsele döner; bilinmeyen geçiş kaydırmaya.
    final one = Ad.fromJson({
      'id': 'a',
      'tur': 'slider',
      'dosya': 'https://x/1.jpg',
      'gorseller': ['https://x/1.jpg'],
      'gecis': '?',
    })!;
    expect(one.type, AdType.image);
    expect(SlideStyle.byKey('?'), SlideStyle.slide);
    expect(SlideStyle.values.length, 5);
  });

  test('tarih ve açık/kapalı süzgeci', () {
    final a = Ad(
      id: 'a',
      type: AdType.image,
      media: 'https://x/a.jpg',
      start: DateTime(2026, 11, 10),
      end: DateTime(2026, 11, 20),
    );
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
        {
          'id': 'y',
          'dosya': 'https://a/b.png',
          'sayfalar': ['hepsi', 'olmayan', 'sinav'],
        },
        'metin',
      ],
    });
    expect(l.single.id, 'y');
    expect(l.single.pages, [AdPage.exam]);
  });

  test('yeni alanlar: düğme, kod, hedef, saat, sıklık, taslak JSON', () {
    final a = Ad(
      id: 'n',
      type: AdType.image,
      media: 'https://x/a.jpg',
      cta: 'Hemen al',
      code: 'NETICE15',
      countdown: true,
      end: DateTime(2026, 12, 5),
      mediaDark: 'https://x/a_gece.jpg',
      mediaB: 'https://x/a_b.jpg',
      languages: const ['tr', 'az'],
      countries: const ['TR'],
      institutions: const ['police'],
      dailyCap: 3,
      weight: 4,
      hourFrom: 8,
      hourTo: 17,
      weekdays: const [1, 2, 3, 4, 5],
      draft: true,
    );
    final json = Ad.listToJson([a], settings: const AdSettings(emptySlotCard: true));
    final back = Ad.listFromJson(jsonDecode(json)).single;
    expect(back.cta, 'Hemen al');
    expect(back.code, 'NETICE15');
    expect(back.countdown, isTrue);
    expect(back.sources, ['https://x/a.jpg', 'https://x/a_gece.jpg', 'https://x/a_b.jpg']);
    expect(back.hasAB, isTrue);
    expect(back.languages, ['tr', 'az']);
    expect(back.countries, ['TR']);
    expect(back.institutions, ['police']);
    expect((back.dailyCap, back.weight, back.hourFrom, back.hourTo), (3, 4, 8, 17));
    expect(back.weekdays, [1, 2, 3, 4, 5]);
    expect(back.draft, isTrue);
    expect(AdSettings.fromJson((jsonDecode(json) as Map)['ayarlar']).emptySlotCard, isTrue);

    // Eski kayıtlar varsayılanlarla açılır.
    final old = Ad.listFromJson({
      'reklamlar': [
        {'id': 'o', 'dosya': 'https://x/o.jpg'},
      ],
    }).single;
    expect((old.weight, old.dailyCap, old.hourFrom, old.hourTo, old.draft), (1, 0, 0, 24, false));
    expect(AdSettings.fromJson(null).emptySlotCard, isFalse);
  });

  test('hedef kitle, saat aralığı, gün ve taslak süzgeci', () {
    const base = Ad(id: 'h', type: AdType.image, media: 'https://x/a.jpg');
    final mon10 = DateTime(2026, 11, 23, 10); // Pazartesi
    final sat10 = DateTime(2026, 11, 28, 10);
    expect(base.matches(AdAudience(lang: 'de', now: mon10)), isTrue);

    final t = base.copyWith(languages: ['tr'], countries: ['TR', 'AZ'], institutions: ['school']);
    expect(t.matches(AdAudience(lang: 'tr', country: 'tr', institution: 'school', now: mon10)), isTrue);
    expect(t.matches(AdAudience(lang: 'en', country: 'TR', institution: 'school', now: mon10)), isFalse);
    expect(t.matches(AdAudience(lang: 'tr', country: 'DE', institution: 'school', now: mon10)), isFalse);
    expect(t.matches(AdAudience(lang: 'tr', country: 'AZ', institution: 'police', now: mon10)), isFalse);

    final work = base.copyWith(hourFrom: 8, hourTo: 17, weekdays: [1, 2, 3, 4, 5]);
    expect(work.runningAt(mon10), isTrue);
    expect(work.runningAt(sat10), isFalse);
    expect(work.runningAt(DateTime(2026, 11, 23, 17)), isFalse);
    final night = base.copyWith(hourFrom: 22, hourTo: 6);
    expect(night.runningAt(DateTime(2026, 11, 23, 23)), isTrue);
    expect(night.runningAt(DateTime(2026, 11, 23, 3)), isTrue);
    expect(night.runningAt(mon10), isFalse);
    expect(base.copyWith(draft: true).runningAt(mon10), isFalse);
  });

  test('öncelik sırası ve geri sayım metni', () {
    const a = Ad(id: 'a', type: AdType.image, media: 'x', weight: 3);
    const b = Ad(id: 'b', type: AdType.image, media: 'x', weight: 2);
    const c = Ad(id: 'c', type: AdType.image, media: 'x');
    expect(weightedRotation([a, b, c]).map((e) => e.id).join(), 'abcaba');
    expect(weightedRotation([c]).length, 1);

    final ad = Ad(id: 'g', type: AdType.image, media: 'x', countdown: true, end: DateTime(2026, 11, 30));
    expect(adCountdownText(ad, DateTime(2026, 11, 20)), isNull); // 7 günden fazla
    expect(adCountdownText(ad, DateTime(2026, 11, 28, 0)), 'Bitmesine 3 gün');
    expect(adCountdownText(ad, DateTime(2026, 11, 30, 19)), 'Bitmesine 5 saat');
    expect(adCountdownText(ad, DateTime(2026, 12, 1, 1)), isNull);
    expect(adCountdownText(ad.copyWith(countdown: false), DateTime(2026, 11, 30)), isNull);
  });

  testWidgets('günlük sınır, düğme, kod ve boş alan kartı', (tester) async {
    final file = File('test/fixtures/ads/kart.jpg');
    AdService.instance.debugSet(
      [
        const Ad(
          id: 's',
          type: AdType.image,
          media: 'https://x/kart.jpg',
          cta: 'Hemen al',
          code: 'NETICE15',
          dailyCap: 1,
        ),
      ],
      {'https://x/kart.jpg': file},
      settings: const AdSettings(emptySlotCard: true),
    );
    final store = AppStore();
    Widget app(AdPage p) => StoreScope(
      store: store,
      child: MaterialApp(
        home: Scaffold(body: AdSlot.card(p, key: ValueKey(p))),
      ),
    );
    await tester.pumpWidget(app(AdPage.home));
    expect(find.text('Hemen al'), findsOneWidget);
    expect(find.text('NETICE15'), findsOneWidget);
    expect(AdService.instance.seenToday('s'), 1);

    // Günde 1 kez sınırı doldu: başka sayfada artık davet kartı çıkar.
    await tester.pumpWidget(app(AdPage.exam));
    expect(find.text('Hemen al'), findsNothing);
    expect(find.text('Burada reklamınız olsun'), findsOneWidget);

    store.proConfirmedAt = DateTime.now();
    await tester.pumpWidget(app(AdPage.student));
    expect(find.text('Burada reklamınız olsun'), findsNothing);
    AdService.instance.debugSet(const [], const {});
  });

  test('A/B sonucu ve sayaç özeti', () {
    expect(abVerdict(const AdCounts(50, 5), const AdCounts(500, 50)), AbVerdict.needMoreData);
    expect(abVerdict(const AdCounts(1000, 20), const AdCounts(1000, 22)), AbVerdict.noDifference);
    expect(abVerdict(const AdCounts(1000, 20), const AdCounts(1000, 45)), AbVerdict.bWins);
    expect(abVerdict(const AdCounts(1000, 45), const AdCounts(1000, 20)), AbVerdict.aWins);
    final m = AdStats.mapFromJson({
      'gun': 30,
      'reklamlar': {
        'r1': {
          'a': {'g': 10, 't': 1},
          'b': {'g': 30, 't': 3},
          'gunluk': {
            '2026-11-26': {'g': 40, 't': 4},
          },
        },
      },
    });
    expect(m['r1']!.total.views, 40);
    expect(m['r1']!.total.rate, closeTo(0.1, 1e-9));
    expect(m['r1']!.daily['2026-11-26']!.clicks, 4);
    expect(AdStats.mapFromJson(null), isEmpty);
  });

  test('sayaç: yalnız yayındaki reklamlar, önizleme ve kapalı ayar sayılmaz', () {
    final s = AdService.instance;
    const ad = Ad(id: 'p1', type: AdType.image, media: 'https://x/a.jpg', mediaB: 'https://x/b.jpg');
    s.debugSet(const [ad], const {});
    s.recordImpression(ad);
    s.recordImpression(ad, variantB: true);
    s.recordClick(ad, variantB: true);
    final day = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    expect(s.pendingStats, {'$day|p1|a|g': 1, '$day|p1|b|g': 1, '$day|p1|b|t': 1});
    // Cihaza eklenmiş (yayınlanmamış) reklam sayılmaz.
    s.recordImpression(const Ad(id: 'yerel', type: AdType.image, media: '/tmp/a.jpg'));
    expect(s.pendingStats.length, 3);
    // Yönetici önizlemesi sayılmaz.
    s.setPreview(const [ad]);
    s.recordClick(ad);
    expect(s.pendingStats.length, 3);
    s.setPreview(null);
    // Sayaç kapalıysa sayılmaz.
    s.debugSet(const [ad], const {}, settings: const AdSettings(stats: false));
    s.recordImpression(ad);
    expect(s.pendingStats, isEmpty);
    expect(const AdSettings().toJson()['istatistik'], isTrue);
    expect(AdSettings.fromJson({'istatistik': false}).stats, isFalse);
    s.debugSet(const [], const {});
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
    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: const MaterialApp(home: Scaffold(body: AdSlot.banner(AdPage.home))),
      ),
    );
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
    // Yayın anahtarı yoksa bu cihazdan bir şey yayınlanamaz: kod anahtarsız sıfırlanır.
    a.token = '';
    await a.setPin('482913');
    expect(await a.resetPinWithToken(''), isTrue);
    expect(a.hasPin, isFalse);
  });

  testWidgets('gizli alan göz düğmesiyle gösterilir', (tester) async {
    final c = TextEditingController(text: '482913');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SecretField(controller: c, label: 'Kod', number: true),
        ),
      ),
    );
    bool obscured() => tester.widget<TextField>(find.byType(TextField)).obscureText;
    expect(obscured(), isTrue);
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    expect(obscured(), isFalse);
  });

  testWidgets('gizli hareket: logoya 4 sn içinde 5 dokunuş kod ekranını açar', (tester) async {
    await tester.pumpWidget(
      StoreScope(
        store: AppStore(),
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();
    final logo = find.byType(NeticeMark);
    await tester.scrollUntilVisible(logo, 400, scrollable: find.byType(Scrollable).first);
    await tester.pump();
    Future<void> taps(int n) => tester.runAsync(() async {
      for (var i = 0; i < n; i++) {
        await tester.tap(logo);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    await taps(4);
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    // 4 saniyeden uzun ara verilirse sayım baştan başlar.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 4200)));
    await taps(1);
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    await taps(4);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pump();
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  test('reklam ayarları: sıklık, WhatsApp ve öneri kartı JSON', () {
    const s = AdSettings(emptySlotCard: true, emptyEvery: 3, whatsapp: '905321112233', promoCard: false);
    final back = AdSettings.fromJson(jsonDecode(jsonEncode(s.toJson())));
    expect(back.emptyEvery, 3);
    expect(back.whatsapp, '905321112233');
    expect(back.promoCard, isFalse);
    // Eski yayınlarda alan yoksa öneri kartı açık, sıklık her seferinde.
    final old = AdSettings.fromJson({'bosAlanKarti': true});
    expect(old.promoCard, isTrue);
    expect(old.emptyEvery, 1);
    expect(AdSettings.fromJson({'bosAlanSiklik': 99, 'whatsapp': '+90 (532) 111'}).emptyEvery, 5);
    expect(AdSettings.fromJson({'whatsapp': '+90 (532) 111'}).whatsapp, '90532111');
  });

  test('reklam alanları: numaralar ve anahtarlar benzersiz', () {
    final keys = AdPlacement.all.map((p) => p.key).toSet();
    expect(keys.length, AdPlacement.all.length);
    expect(AdPlacement.all.map((p) => p.no).toList(), List.generate(AdPlacement.all.length, (i) => i + 1));
    expect(AdPlacement.byKey('ana_sayfa/card')?.no, 1);
  });

  test('başvuru JSON gidiş-dönüş', () {
    const a = AdApplication(
      name: 'Ayşe',
      company: 'Kırtasiye',
      phone: '05321112233',
      email: 'a@b.co',
      message: 'Merhaba',
      slot: 'ana_sayfa/card',
    );
    final back = AdApplication.fromJson({...a.toJson(), 'id': 'ba_x', 'zaman': '2026-11-27T10:00:00Z'});
    expect(back.name, 'Ayşe');
    expect(back.company, 'Kırtasiye');
    expect(back.slot, 'ana_sayfa/card');
    expect(back.time, isNotNull);
  });

  testWidgets('boş alan kartı sıklığı ve "Sayfada göster" çerçevesi', (tester) async {
    AdService.instance.debugSet([], {}, settings: const AdSettings(emptySlotCard: true, emptyEvery: 2));
    final store = AppStore();
    Widget app(int n) => StoreScope(
      store: store,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(children: [for (var i = 0; i < n; i++) AdSlot.card(AdPage.term, key: ValueKey(i))]),
          ),
        ),
      ),
    );
    await tester.pumpWidget(app(4));
    // 4 boş gösterimin 2'sinde davet kartı çıkar.
    expect(find.byType(AdEmptyCard), findsNWidgets(2));

    // Vurgulanan alan, reklam ve davet kartı kapalı olsa da pembe kutuyla görünür.
    AdService.instance.debugSet([], {}, settings: const AdSettings());
    AdService.instance.highlight(AdPlacement.byKey('donem/card')!);
    await tester.pumpWidget(app(1));
    expect(find.textContaining('REKLAM ALANI'), findsWidgets);
    AdService.instance.clearHighlight();
  });

  testWidgets('masaüstü: logoya 5 tıklama kod ekranını açar', (tester) async {
    await tester.pumpWidget(
      StoreScope(
        store: AppStore(),
        child: const MaterialApp(
          home: Scaffold(body: Center(child: SecretAdminTap(child: SizedBox.square(dimension: 40)))),
        ),
      ),
    );
    await tester.runAsync(() async {
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byType(SecretAdminTap));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
