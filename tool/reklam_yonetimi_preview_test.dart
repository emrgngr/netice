// Yeni Reklam yönetimi (sekmeli) önizlemesi:
//   flutter test tool/reklam_yonetimi_preview_test.dart
// Görüntüler build/screenshots/ry_*.png olarak yazılır.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/ad_admin.dart';
import 'package:netice/core/ads.dart';
import 'package:netice/core/store.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/ad_admin_screen.dart';
import 'package:netice/ui/ad_slot.dart';
import 'package:netice/ui/theme.dart';

import 'screenshots_test.dart' show loadFonts, shot;

Widget _themed(AppStore store, Widget home, {bool dark = false}) => StoreScope(
  store: store,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: NTheme.light(),
    darkTheme: NTheme.dark(),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    home: home,
  ),
);

const _base = 'https://raw.githubusercontent.com/emrgngr/netice/reklamlar/reklam/medya';

void main() {
  testWidgets('reklam yönetimi önizlemesi', (tester) async {
    debugDisableShadows = false;
    AdSlot.debugNoVideo = true;
    AdSlot.debugCountry = 'TR';
    AdSlot.debugDesktop = false;
    await tester.runAsync(loadFonts);
    final store = AppStore();
    await tester.runAsync(() => store.load(dir: Directory.systemTemp.createTempSync('ry')));
    store.onboardingDone = true;
    store.ratePrompted = true;

    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final ads = [
      Ad(
        id: 'k',
        name: 'Sepetmix kırtasiye',
        type: AdType.slider,
        media: '$_base/k1.jpg',
        slides: const ['$_base/k1.jpg', '$_base/k2.jpg', '$_base/k3.jpg'],
        seconds: 4,
        link: 'https://www.sepetmix.com/kirtasiye',
        cta: 'Hemen al',
        code: 'NETICE15',
        countdown: true,
        start: day.subtract(const Duration(days: 6)),
        end: day.add(const Duration(days: 1, hours: 23)),
        mediaDark: '$_base/k_gece.jpg',
      ),
      Ad(
        id: 's',
        name: 'Cook Tatlı Hayat şerit',
        type: AdType.image,
        media: '$_base/serit.jpg',
        format: AdFormat.banner,
        pages: const [AdPage.home, AdPage.exam],
        link: 'https://www.cooktatlihayat.com/',
      ),
      Ad(
        id: 'a',
        name: 'Amare yeni yıl',
        type: AdType.image,
        media: '$_base/amare.jpg',
        mediaB: '$_base/amare_b.jpg',
        pages: const [AdPage.exam, AdPage.term],
        link: 'https://www.amare.com/',
        start: day.add(const Duration(days: 4)),
      ),
      Ad(
        id: 'p',
        name: 'Yaz kampanyası',
        type: AdType.image,
        media: '$_base/yaz.jpg',
        pages: const [AdPage.profile],
        active: false,
      ),
    ];
    await tester.runAsync(AdAdmin.instance.load);
    AdAdmin.instance.drafts = ads;
    AdAdmin.instance.settings = const AdSettings(emptySlotCard: true, emptyEvery: 3, whatsapp: '905321112233');
    AdAdmin.instance.dirty = true;
    AdAdmin.instance.newApplications = 1;
    File fx(String n) => File('test/fixtures/ads/$n');
    final files = {
      '$_base/k1.jpg': fx('slider1.jpg'),
      '$_base/k2.jpg': fx('slider2.jpg'),
      '$_base/k3.jpg': fx('slider3.jpg'),
      '$_base/k_gece.jpg': fx('kampanya_gece.jpg'),
      '$_base/serit.jpg': fx('serit_temiz.jpg'),
      '$_base/amare.jpg': fx('kampanya.jpg'),
      '$_base/amare_b.jpg': fx('kampanya_b.jpg'),
      '$_base/yaz.jpg': fx('kart.jpg'),
    };
    AdService.instance.debugSet(const [], files, settings: AdAdmin.instance.settings);
    // Görseller önceden çözülür (yoksa ekran görüntüsü beklerken takılır).
    await tester.runAsync(() async {
      for (final f in files.values.toSet()) {
        final done = Completer<void>();
        FileImage(f)
            .resolve(ImageConfiguration.empty)
            .addListener(ImageStreamListener((_, _) => done.complete(), onError: (e, _) => done.completeError(e)));
        await done.future;
      }
    });

    final apps = [
      AdApplication(
        id: 'ba_1',
        time: now.subtract(const Duration(hours: 2)),
        name: 'Ayşe Yılmaz',
        company: 'Yıldız Kırtasiye',
        phone: '0532 111 22 33',
        email: 'ayse@ornek.com',
        message: 'Merhaba, okulların açılış haftası için 2 haftalık slider reklam düşünüyoruz. Fiyat bilgisi alabilir miyim?',
        slot: 'ana_sayfa/card',
        country: 'TR',
      ),
      AdApplication(
        id: 'ba_2',
        time: now.subtract(const Duration(days: 5)),
        name: 'Mehmet Kaya',
        company: 'Kaya Yayınları',
        email: 'mehmet@ornek.com',
        message: 'Deneme sınavı kitaplarımızı sınav sonuçları sayfasında tanıtmak istiyoruz.',
        slot: 'sinav/card',
        country: 'TR',
      ),
    ];
    final today = now.toUtc();
    String d(int i) => today.subtract(Duration(days: i)).toIso8601String().substring(0, 10);
    final stats = {
      'k': AdStats(
        a: const AdCounts(4120, 74),
        b: const AdCounts(4088, 131),
        daily: {for (var i = 0; i < 7; i++) d(i): AdCounts(1400 + (i * 137) % 600, 20 + i % 5)},
      ),
      's': AdStats(a: const AdCounts(3650, 58), daily: {for (var i = 0; i < 7; i++) d(i): AdCounts(500 + i * 20, 2)}),
    };

    Widget admin(int tab, {bool dark = false}) => _themed(
      store,
      AdAdminScreen(initialTab: tab, previewApplications: apps, previewSeen: const {'ba_2'}, previewStats: stats),
      dark: dark,
    );
    await shot(tester, admin(0), const Size(390, 1900), 'ry_1_reklamlar');
    await shot(tester, admin(1), const Size(390, 2600), 'ry_2_alanlar');
    await shot(tester, admin(2), const Size(390, 1500), 'ry_3_istatistik');
    await shot(tester, admin(3), const Size(390, 900), 'ry_4_basvurular');
    await shot(tester, admin(4), const Size(390, 2000), 'ry_5_ayarlar');
    await shot(tester, admin(0, dark: true), const Size(390, 1900), 'ry_6_reklamlar_gece');
    await shot(tester, admin(1), const Size(1280, 900), 'ry_7_bilgisayar_alanlar');

    // "Sayfada göster": Alanlar'dan Ayarlar kartı alanına git.
    await shot(
      tester,
      admin(1),
      const Size(390, 900),
      'ry_8_sayfada_goster',
      then: () async {
        final target = find.text('AYARLAR · KART');
        await tester.scrollUntilVisible(target, 300, scrollable: find.byType(Scrollable).at(1));
        await tester.pumpAndSettle();
        final btn = find.descendant(
          of: find.ancestor(of: target, matching: find.byType(Card)),
          matching: find.text('Sayfada göster'),
        );
        await tester.tap(btn);
        await tester.pumpAndSettle();
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
      },
    );

    // Kullanıcının gördüğü boş alan kartı ve başvuru formu.
    await shot(
      tester,
      _themed(
        store,
        Scaffold(
          appBar: AppBar(title: const Text('Ana sayfa')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: const AdEmptyCard(email: 'info@neticeoptik.com', whatsapp: '905321112233'),
              ),
            ],
          ),
        ),
      ),
      const Size(390, 900),
      'ry_9_basvuru_formu',
      then: () async {
        await tester.tap(find.text('Reklam ver'));
        await tester.pumpAndSettle();
      },
    );

    await tester.pumpWidget(const SizedBox());
    AdService.instance.clearHighlight();
    AdService.instance.debugSet(const [], const {});
    AdSlot.debugCountry = null;
    AdSlot.debugDesktop = null;
    debugDisableShadows = true;
  });
}
