// Açılış animasyonu kareleri: flutter test tool/splash_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/ui/splash_screen.dart';
import 'package:netice/ui/theme.dart';

import 'screenshots_test.dart' show loadFonts, shot;

void main() {
  testWidgets('açılış kareleri', (tester) async {
    debugDisableShadows = false;
    await tester.runAsync(loadFonts);
    for (final night in [false, true]) {
      for (final f in [0.1, 0.3, 0.5, 0.62, 0.85]) {
        await shot(
            tester,
            MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: NTheme.light(),
                home: SplashScreen(next: const SizedBox(), night: night, freezeAt: f)),
            const Size(390, 844),
            'acilis_${night ? 'gece' : 'gunduz'}_${(f * 100).round()}');
      }
    }
    debugDisableShadows = true;
  });
}
