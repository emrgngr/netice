// Açılış animasyonu video kareleri: flutter test tool/splash_video_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/ui/splash_screen.dart';
import 'package:netice/ui/theme.dart';

import 'screenshots_test.dart' show loadFonts, shot;

void main() {
  testWidgets('açılış video kareleri', (tester) async {
    await tester.runAsync(loadFonts);
    for (final night in [false, true]) {
      for (var i = 0; i <= 79; i++) {
        await shot(
            tester,
            MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: NTheme.light(),
                home: SplashScreen(next: const SizedBox(), night: night, freezeAt: i / 79)),
            const Size(390, 844),
            'splash_${night ? 'gece' : 'gunduz'}/f_${i.toString().padLeft(3, '0')}');
      }
    }
  });
}
