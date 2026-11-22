// Netice Pro ekranı önizlemesi: flutter test tool/pro_preview_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/pro.dart';
import 'package:netice/core/store.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/pro_screen.dart';
import 'package:netice/ui/theme.dart';

import 'screenshots_test.dart' show loadFonts, shot;

void main() {
  testWidgets('pro ekranı', (tester) async {
    await tester.runAsync(loadFonts);
    AppStore.proFreeOnThisPlatform = false;
    final store = AppStore();
    Widget app(Widget home) => StoreScope(
        store: store,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: NTheme.light(), home: home));
    await shot(tester, app(const ProScreen(feature: ProFeature.termReport)), const Size(390, 1240), 'pro_ekrani');
    await shot(
        tester,
        app(const Scaffold(body: Padding(padding: EdgeInsets.all(16), child: Column(children: [ProLocked(ProFeature.advancedCharts)])))),
        const Size(390, 140),
        'pro_kilitli_kart');
  });
}
