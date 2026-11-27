// Panodaki hizmet kartlarının önizlemesi (gündüz, gece, telefon) ve web
// sitesinin ana görseli (web-sitesi/img/pc_ana_sayfa.jpg, 1600x1000).
//   flutter test tool/hizmet_kartlari_test.dart
// Çıktılar build/screenshots/hizmet_*.png.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/campaigns.dart';
import 'package:netice/core/store.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/pro_screen.dart';
import 'package:netice/ui/theme.dart';

import 'screenshots_test.dart' show loadFonts, shot;

void main() {
  testWidgets('hizmet kartları', timeout: const Timeout(Duration(minutes: 5)), (tester) async {
    debugDisableShadows = false;
    await tester.runAsync(loadFonts);
    final store = AppStore();
    await tester.runAsync(() => store.load(dir: Directory.systemTemp.createTempSync('hizmet')));
    store.onboardingDone = true;
    store.ratePrompted = true;
    store.hidePromo(const Duration(days: 3650));
    AppStore.showDemoNotice = false;
    Widget app() => NeticeApp(store: store, splash: false);

    // Pro ekranı: kullanıcının gönderdiği görüntüdeki gibi deneme + Öğretmenler Günü kampanyası.
    Campaign.debugNow = DateTime(2026, 11, 27);
    AppStore.proFreeOnThisPlatform = false;
    Widget pro() => StoreScope(
      store: store,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: NTheme.light(), home: const ProScreen()),
    );
    await shot(tester, pro(), const Size(1910, 2300), 'hizmet_pro_masaustu');
    await shot(tester, pro(), const Size(1280, 2600), 'hizmet_pro_dar_masaustu');
    await shot(tester, pro(), const Size(390, 4200), 'hizmet_pro_telefon');
    Campaign.debugNow = null;

    store.themeMode = 'light';
    await shot(tester, app(), const Size(1600, 1000), 'hizmet_site_pc_ana_sayfa');
    await shot(tester, app(), const Size(1440, 1500), 'hizmet_masaustu_gunduz');
    await shot(tester, app(), const Size(390, 2200), 'hizmet_telefon_gunduz');
    store.themeMode = 'dark';
    await shot(tester, app(), const Size(1440, 1500), 'hizmet_masaustu_gece');
    await shot(tester, app(), const Size(390, 2200), 'hizmet_telefon_gece');
    AppStore.showDemoNotice = true;
    debugDisableShadows = true;
  });
}
