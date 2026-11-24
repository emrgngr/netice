// Fiyat seviyeleri ve kampanya önizlemesi: flutter test tool/fiyat_preview_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/pro.dart';
import 'package:netice/core/store.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/pro_screen.dart';
import 'package:netice/ui/school_offer_screen.dart';
import 'package:netice/ui/theme.dart';

import 'screenshots_test.dart' show loadFonts, shot;

void main() {
  testWidgets('fiyat ekranları', (tester) async {
    await tester.runAsync(loadFonts);
    AppStore.proFreeOnThisPlatform = false;
    final store = AppStore()
      ..trialStart = DateTime.now().subtract(const Duration(days: 30))
      ..school = const SchoolInfo(name: 'Örnek Anadolu Lisesi', province: 'Ankara', district: 'Çankaya', teacher: 'Ayşe Yılmaz');
    await ProService.instance.attach(store);
    Widget app(Widget home) => StoreScope(
        store: store,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: NTheme.light(), home: home));
    await shot(tester, app(const ProScreen()), const Size(390, 2050), 'fiyat_1_pro_ekrani');
    await shot(tester, app(const SchoolOfferScreen()), const Size(390, 1250), 'fiyat_2_okul_paketi');
  });
}
