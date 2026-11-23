// Alt menü ve gece/gündüz önizlemesi: flutter test tool/preview_dock_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/store.dart';
import 'package:netice/main.dart';

import 'screenshots_test.dart' show loadFonts, shot;

void main() {
  testWidgets('alt menü önizlemesi', (tester) async {
    debugDisableShadows = false;
    await tester.runAsync(loadFonts);
    final store = AppStore();
    await tester.runAsync(() => store.load(dir: Directory.systemTemp.createTempSync('dock')));
    store.onboardingDone = true;
    store.ratePrompted = true;
    final app = NeticeApp(store: store, splash: false);
    for (final mode in ['light', 'dark']) {
      store.themeMode = mode;
      await shot(tester, app, const Size(390, 844), 'dock_${mode}_ana');
      await shot(tester, app, const Size(390, 844), 'dock_${mode}_ayarlar', then: () async {
        await tester.tap(find.byIcon(Icons.settings_outlined).last);
        await tester.pumpAndSettle();
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -110));
      });
    }
    debugDisableShadows = true;
  });
}
