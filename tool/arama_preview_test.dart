// Uygulama içi arama önizlemesi: flutter test tool/arama_preview_test.dart
// Görüntüler build/screenshots/arama_*.png olarak yazılır.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/ads.dart';
import 'package:netice/core/store.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/ad_slot.dart';
import 'package:netice/ui/search_ui.dart';

import 'screenshots_test.dart' show loadFonts, shot;

void main() {
  testWidgets('arama önizlemesi', (tester) async {
    debugDisableShadows = false;
    AdSlot.debugNoVideo = true;
    await tester.runAsync(loadFonts);
    final store = AppStore();
    await tester.runAsync(() => store.load(dir: Directory.systemTemp.createTempSync('arama')));
    store.onboardingDone = true;
    store.ratePrompted = true;
    AdService.instance.debugSet(const [], const {}, settings: const AdSettings(promoCard: false));
    final first = store.students.first.firstName;

    Future<void> open() async {
      await tester.tap(find.byType(SearchBox).first);
      await tester.pumpAndSettle();
    }

    for (final dark in [false, true]) {
      store.themeMode = dark ? 'dark' : 'light';
      final n = dark ? '_gece' : '';
      // Telefon: ana sayfa, boş arama, sonuçlar.
      await shot(tester, NeticeApp(store: store, splash: false), const Size(390, 844), 'arama_1_telefon_ana$n');
      SearchPanel.debugQuery = null;
      await shot(tester, NeticeApp(store: store, splash: false), const Size(390, 844), 'arama_2_telefon_bos$n', then: open);
      SearchPanel.debugQuery = 'rapor';
      await shot(tester, NeticeApp(store: store, splash: false), const Size(390, 844), 'arama_3_telefon_rapor$n', then: open);
      SearchPanel.debugQuery = first.substring(0, 3).toLowerCase();
      await shot(tester, NeticeApp(store: store, splash: false), const Size(390, 844), 'arama_4_telefon_ogrenci$n', then: open);
      // Bilgisayar: ana sayfa ve açılan pencere.
      SearchPanel.debugQuery = null;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await shot(tester, NeticeApp(store: store, splash: false), const Size(1440, 900), 'arama_5_masaustu_ana$n');
      await shot(tester, NeticeApp(store: store, splash: false), const Size(1440, 900), 'arama_6_masaustu_bos$n', then: open);
      SearchPanel.debugQuery = 'karne';
      await shot(tester, NeticeApp(store: store, splash: false), const Size(1440, 900), 'arama_7_masaustu_karne$n', then: open);
      debugDefaultTargetPlatformOverride = null;
    }
    SearchPanel.debugQuery = null;
    store.themeMode = 'light';
    AdService.instance.debugSet(const [], const {});
    debugDisableShadows = true;
  });
}
