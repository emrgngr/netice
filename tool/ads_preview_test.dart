// Reklam alanları önizlemesi: flutter test tool/ads_preview_test.dart
// Görüntüler build/screenshots/reklam_*.png olarak yazılır.
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
import 'package:netice/ui/exam_screen.dart';
import 'package:netice/ui/settings_screen.dart';
import 'package:netice/ui/theme.dart';

import 'screenshots_test.dart' show loadFonts, shot;

Widget _themed(AppStore store, Widget home) => StoreScope(
      store: store,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: NTheme.light(), home: home),
    );

void main() {
  testWidgets('reklam önizlemesi', (tester) async {
    debugDisableShadows = false;
    AdSlot.debugNoVideo = true;
    await tester.runAsync(loadFonts);
    final store = AppStore();
    await tester.runAsync(() => store.load(dir: Directory.systemTemp.createTempSync('reklam')));
    store.onboardingDone = true;
    store.ratePrompted = true;

    const kart = 'https://raw.githubusercontent.com/emrgngr/netice/reklamlar/reklam/medya/kart.jpg';
    const serit = 'https://raw.githubusercontent.com/emrgngr/netice/reklamlar/reklam/medya/serit.jpg';
    final ads = [
      const Ad(id: 'r1', name: 'LGS deneme seti kampanyası', type: AdType.image, media: kart, link: 'https://ornek.com', format: AdFormat.card),
      const Ad(id: 'r2', name: 'Kırtasiye şeridi', type: AdType.image, media: serit, link: 'https://ornek.com', format: AdFormat.banner),
    ];
    AdService.instance.debugSet(ads, {
      kart: File('test/fixtures/ads/kart.jpg'),
      serit: File('test/fixtures/ads/serit.jpg'),
    });

    // Görseller önceden (gerçek zamanlı) yüklenir; yoksa sahte saat içinde bekler.
    await tester.runAsync(() async {
      for (final f in ['kart', 'serit']) {
        final done = Completer<void>();
        final stream = FileImage(File('test/fixtures/ads/$f.jpg')).resolve(ImageConfiguration.empty);
        final l = ImageStreamListener((_, _) => done.complete(), onError: (e, _) => done.completeError(e));
        stream.addListener(l);
        await done.future;
      }
    });

    final app = NeticeApp(store: store, splash: false);
    await shot(tester, app, const Size(390, 844), 'reklam_1_ana_sayfa_serit');
    await shot(tester, app, const Size(390, 1500), 'reklam_2_ana_sayfa_kart');
    await shot(tester, _themed(store, const ExamScreen(examId: 'demo_exam')), const Size(390, 844), 'reklam_3_sinav_sonuclari');
    await shot(tester, app, const Size(1366, 900), 'reklam_4_masaustu');

    await tester.runAsync(AdAdmin.instance.load);
    AdAdmin.instance
      ..unlocked = true
      ..dirty = true
      ..drafts = [
        ...ads,
        Ad(
          id: 'r3',
          name: 'Yaz okulu tanıtım videosu',
          type: AdType.video,
          media: 'https://raw.githubusercontent.com/emrgngr/netice/reklamlar/reklam/medya/r3.mp4',
          pages: const [AdPage.home, AdPage.exam],
          start: DateTime(2026, 12, 1),
          end: DateTime(2026, 12, 31),
        ),
      ];
    await shot(tester, _themed(store, const AdAdminScreen()), const Size(390, 900), 'reklam_5_yonetim');
    await shot(tester, _themed(store, AdEditScreen(ad: ads.first)), const Size(390, 1500), 'reklam_6_reklam_ekle');
    await shot(tester, _themed(store, const SettingsScreen()), const Size(390, 900), 'reklam_7_ayarlar_yonetici',
        then: () async {
      await tester.scrollUntilVisible(find.text('Reklam yönetimi'), 300, scrollable: find.byType(Scrollable).first);
    });

    store.proConfirmedAt = DateTime.now();
    await shot(tester, app, const Size(390, 844), 'reklam_8_pro_reklamsiz');
    AdService.instance.debugSet(const [], const {});
    debugDisableShadows = true;
  });
}
