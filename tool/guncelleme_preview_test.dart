// Güncelleme duyurusu önizlemesi: flutter test tool/guncelleme_preview_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/store.dart';
import 'package:netice/core/updates.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/home_screen.dart';
import 'package:netice/ui/theme.dart';
import 'package:netice/ui/update_ui.dart';

import 'screenshots_test.dart' show loadFonts, shot;

void main() {
  testWidgets('güncelleme ekranları', (tester) async {
    await tester.runAsync(loadFonts);
    final store = AppStore()
      ..onboardingDone = true
      ..loaded = true
      ..ratePrompted = true;
    store.seedDemo();
    store.lastSeenVersion = '99.0.0'; // önizlemede yenilik penceresi kendiliğinden açılmasın
    UpdateService.instance.debugSetLatest('1.0.1');
    Widget app(Widget home) => StoreScope(
        store: store,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: NTheme.light(), home: home));
    await shot(tester, app(const HomeScreen()), const Size(390, 900), 'guncelleme_1_yeni_surum_karti');
    await shot(
        tester,
        app(Scaffold(
          backgroundColor: Colors.black54,
          body: Center(
            child: WhatsNewDialog(version: '1.0.1', items: [for (final n in releaseNotes()) ...n.items]),
          ),
        )),
        const Size(390, 760),
        'guncelleme_2_yenilikler');
  });
}
