// "Neden Netice?" ekranının tam boy önizlemesi (telefon ve masaüstü, gündüz ve gece).
//   flutter test tool/neden_netice_test.dart --dart-define=LANG_SHOT=tr
// Çıktılar build/screenshots/neden/<dil>/<pencere>_<tema>.png; taşma vb.
// hatalar "SORUNLAR" satırında listelenir (boşsa sorun yok).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/l10n/l10n.dart';
import 'package:netice/ui/theme.dart';
import 'package:netice/ui/why_screen.dart';

import 'screenshots_test.dart' show loadFonts, shot;

void main() {
  testWidgets('neden netice', (tester) async {
    const lang = String.fromEnvironment('LANG_SHOT', defaultValue: 'tr');
    debugDisableShadows = false;
    await tester.runAsync(loadFonts);
    L10n.use(lang);
    Directory('build/screenshots/neden/$lang').createSync(recursive: true);
    const sizes = {'telefon': Size(390, 3420), 'masaustu': Size(1280, 2300)};
    final problems = <String>[];
    for (final dark in [false, true]) {
      for (final MapEntry(key: sz, value: size) in sizes.entries) {
        final errors = <String>[];
        final old = FlutterError.onError;
        FlutterError.onError = (d) => errors.add(d.exceptionAsString().split('\n').first);
        try {
          await shot(
            tester,
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: dark ? NTheme.dark() : NTheme.light(),
              home: Directionality(
                textDirection: L10n.rtl ? TextDirection.rtl : TextDirection.ltr,
                child: const WhyNeticeScreen(),
              ),
            ),
            size,
            'neden/$lang/${sz}_${dark ? 'gece' : 'gunduz'}',
          );
        } finally {
          FlutterError.onError = old;
        }
        problems.addAll(errors.map((e) => '$sz ${dark ? 'gece' : 'gunduz'}: $e'));
      }
    }
    debugDisableShadows = true;
    // ignore: avoid_print
    print('SORUNLAR: ${problems.join(' | ')}');
  });
}
