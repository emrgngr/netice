// Reklam yönetimi yeni araçları önizlemesi: flutter test tool/ads_tools_preview_test.dart
// Görüntüler build/screenshots/arac_*.png olarak yazılır.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/ad_admin.dart';
import 'package:netice/core/ads.dart';
import 'package:netice/core/store.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/ad_admin_screen.dart';
import 'package:netice/ui/ad_device_preview.dart';
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
  testWidgets('reklam araçları önizlemesi', (tester) async {
    debugDisableShadows = false;
    AdSlot.debugNoVideo = true;
    AdSlot.debugCountry = 'TR';
    AdSlot.debugDesktop = false;
    await tester.runAsync(loadFonts);
    final store = AppStore();
    await tester.runAsync(() => store.load(dir: Directory.systemTemp.createTempSync('arac')));
    store.onboardingDone = true;
    store.ratePrompted = true;

    File fx(String n) => File('test/fixtures/ads/$n');
    final day = fx('kampanya.jpg'), night = fx('kampanya_gece.jpg'), b = fx('kampanya_b.jpg');
    await tester.runAsync(() async {
      for (final f in [day, night, b, fx('serit_temiz.jpg')]) {
        final done = Completer<void>();
        FileImage(f)
            .resolve(ImageConfiguration.empty)
            .addListener(ImageStreamListener((_, _) => done.complete(), onError: (e, _) => done.completeError(e)));
        await done.future;
      }
    });

    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day + 2);
    final ad = Ad(
      id: 'k',
      name: 'Sepetmix kırtasiye',
      type: AdType.image,
      media: '$_base/k.jpg',
      mediaDark: '$_base/k_gece.jpg',
      mediaB: '$_base/k_b.jpg',
      link: 'https://www.sepetmix.com/kirtasiye',
      cta: 'Hemen al',
      code: 'NETICE15',
      countdown: true,
      end: end,
      weight: 3,
      dailyCap: 5,
      hourFrom: 8,
      hourTo: 18,
      languages: const ['tr', 'az'],
      institutions: const ['school', 'course'],
    );
    final files = {
      '$_base/k.jpg': day,
      '$_base/k_gece.jpg': night,
      '$_base/k_b.jpg': b,
      '$_base/serit.jpg': fx('serit_temiz.jpg'),
    };
    final banner = Ad(
      id: 's',
      name: 'Şerit',
      type: AdType.image,
      media: '$_base/serit.jpg',
      format: AdFormat.banner,
      link: 'https://www.cooktatlihayat.com/',
      cta: 'İncele',
    );

    // 1) Görsel üstü öğeler: düğme, kod, geri sayım; gece ve B görseli; boş alan kartı.
    AdService.instance.debugSet([ad, banner], files);
    Widget label(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 6),
      child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
    Widget clip(Widget w, {double r = 18}) => ClipRRect(borderRadius: BorderRadius.circular(r), child: w);
    await shot(
      tester,
      _themed(
        store,
        Scaffold(
          appBar: AppBar(title: const Text('Reklamın üstündeki yeni öğeler')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              label('Düğme + indirim kodu + geri sayım'),
              clip(AdView(ad: ad, files: [day], onClose: () {})),
              label('Gece modunda kendi görseli'),
              clip(AdView(ad: ad, files: [night], onClose: () {})),
              label('A/B testi: B görseli'),
              clip(AdView(ad: ad, files: [b], onClose: () {})),
              label('Şerit reklamda düğme'),
              clip(AdView(ad: banner, files: [fx('serit_temiz.jpg')], banner: true, onClose: () {}), r: 10),
              label('Boş alanda "Burada reklamınız olsun"'),
              clip(AdEmptyCard(email: 'bilgi@neticeoptik.com', onClose: () {})),
            ],
          ),
        ),
      ),
      const Size(390, 1480),
      'arac_1_gorsel_ustu',
    );

    // 2) Ana sayfada (gündüz ve gece).
    await shot(tester, NeticeApp(store: store, splash: false), const Size(390, 1700), 'arac_2_ana_sayfa');
    store.themeMode = 'dark';
    await shot(tester, NeticeApp(store: store, splash: false), const Size(390, 1700), 'arac_3_ana_sayfa_gece');
    store.themeMode = 'light';

    // 3) Cihaz önizlemesi: telefon ve bilgisayar (QR).
    await shot(tester, _themed(store, AdDevicePreviewScreen(ad: ad)), const Size(390, 860), 'arac_4_onizle_telefon');
    await shot(
      tester,
      _themed(store, AdDevicePreviewScreen(ad: ad, initial: PreviewDevice.desktop)),
      const Size(1000, 720),
      'arac_5_onizle_bilgisayar',
    );
    await shot(
      tester,
      _themed(store, AdDevicePreviewScreen(ad: ad, initial: PreviewDevice.tablet, initialDark: true)),
      const Size(390, 860),
      'arac_6_onizle_tablet_gece',
    );

    // 4) Düzenleme ekranı (yeni bölümler).
    final local = ad.copyWith(media: day.path, mediaDark: night.path, mediaB: b.path);
    await shot(tester, _themed(store, AdEditScreen(ad: local)), const Size(390, 4300), 'arac_7_duzenle');

    // 5) Liste: toplu seçim, taslak etiketi, boş alan ayarı.
    await tester.runAsync(AdAdmin.instance.load);
    AdAdmin.instance.drafts = [
      ad,
      banner,
      ad.copyWith(id: 'k2', name: 'Sepetmix kırtasiye (kopya)', draft: true),
      Ad(id: 'c', name: 'Cooktatlihayat yılbaşı', type: AdType.image, media: '$_base/k_b.jpg', weekdays: const [6, 7]),
    ];
    AdAdmin.instance.settings = const AdSettings(emptySlotCard: true);
    AdAdmin.instance.dirty = true;
    await shot(tester, _themed(store, const AdAdminScreen()), const Size(390, 1250), 'arac_8_liste');
    await shot(
      tester,
      _themed(store, const AdAdminScreen()),
      const Size(390, 1250),
      'arac_9_toplu_secim',
      then: () async {
        await tester.longPress(find.text('Sepetmix kırtasiye'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cooktatlihayat yılbaşı'));
      },
    );

    await tester.pumpWidget(const SizedBox());
    AdService.instance.debugSet(const [], const {});
    AdSlot.debugCountry = null;
    AdSlot.debugDesktop = null;
    debugDisableShadows = true;
  });
}
