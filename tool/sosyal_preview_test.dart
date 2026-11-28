// Sosyal medya bağlantıları önizlemesi: flutter test tool/sosyal_preview_test.dart
// Görüntüler build/screenshots/sosyal_*.png olarak yazılır.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/ads.dart';
import 'package:netice/core/store.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/ad_slot.dart';
import 'package:netice/ui/home_screen.dart';
import 'package:netice/ui/theme.dart';

import 'screenshots_test.dart' show loadFonts, shot;

void main() {
  testWidgets('sosyal medya bağlantıları', (tester) async {
    AdSlot.debugNoVideo = true;
    await tester.runAsync(loadFonts);
    final store = AppStore();
    await tester.runAsync(() => store.load(dir: Directory.systemTemp.createTempSync('sosyal')));
    store.onboardingDone = true;
    store.ratePrompted = true;
    AdService.instance.debugSet(const [], const {},
        settings: const AdSettings(promoCard: false, social: {
          'instagram': 'https://www.instagram.com/neticeoptik',
          'facebook': 'https://www.facebook.com/neticeoptik',
          'youtube': 'https://www.youtube.com/@neticeoptik',
          'x': 'https://x.com/neticeoptik',
        }));
    for (final dark in [false, true]) {
      
      final n = dark ? '_gece' : '';
      await shot(tester, StoreScope(
            store: store,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: NTheme.light(),
              darkTheme: NTheme.dark(),
              themeMode: dark ? ThemeMode.dark : ThemeMode.light,
              home: const HomeScreen(previewTab: 4),
            )), const Size(390, 900), 'sosyal_ayarlar$n',
          then: () async {
        await tester.scrollUntilVisible(find.text('Bizi takip edin'), 300, scrollable: find.byType(Scrollable).first);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
        await tester.pumpAndSettle();
      });
    }
    await shot(tester, NeticeApp(store: store, splash: false), const Size(1440, 900), 'sosyal_masaustu');
    AdService.instance.debugSet(const [], const {});
  });
}
