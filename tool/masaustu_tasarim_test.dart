// Masaüstü arayüz önizlemesi: geniş yan menü, pano ve Sınavlar çalışma alanı.
//   flutter test tool/masaustu_tasarim_test.dart --dart-define=LANG_SHOT=tr
// Çıktılar build/screenshots/masaustu/<dil>/<pencere>_<tema>_<ekran>.png.
// Taşma vb. hatalar "SORUNLAR" satırında listelenir (boşsa sorun yok).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/store.dart';
import 'package:netice/l10n/l10n.dart';
import 'package:netice/main.dart';

import 'screenshots_test.dart' show loadFonts, shot;

void main() {
  testWidgets('masaüstü tasarımı', timeout: const Timeout(Duration(minutes: 10)), (tester) async {
    const lang = String.fromEnvironment('LANG_SHOT', defaultValue: 'tr');
    debugDisableShadows = false;
    await tester.runAsync(loadFonts);
    L10n.use(lang);
    Directory('build/screenshots/masaustu/$lang').createSync(recursive: true);
    final store = AppStore();
    final dir = Directory.systemTemp.createTempSync('masaustu');
    await tester.runAsync(() => store.load(dir: dir));
    store.onboardingDone = true;
    store.ratePrompted = true;
    store.hidePromo(const Duration(days: 3650));
    AppStore.showDemoNotice = false;

    const sizes = {'genis': Size(1440, 900), 'dar': Size(1100, 760)};
    final problems = <String>[];
    for (final theme in ['light', 'dark']) {
      store.setThemeMode(theme);
      for (final MapEntry(key: sz, value: size) in sizes.entries) {
        Future<void> s(String name, {Future<void> Function()? then}) async {
          final errors = <String>[];
          final old = FlutterError.onError;
          FlutterError.onError = (d) => errors.add(d.exceptionAsString().split('\n').first);
          try {
            await shot(tester, NeticeApp(store: store, splash: false), size, 'masaustu/$lang/${sz}_${theme}_$name',
                then: then);
          } catch (e) {
            errors.add('$e'.split('\n').first);
          } finally {
            FlutterError.onError = old;
          }
          for (final e in errors) {
            problems.add('$sz $theme $name: $e');
          }
        }

        await s('pano');
        await s('sinavlar', then: () async => tester.tap(find.text(tr('Sınavlar')).first));
        await s('siniflar', then: () async => tester.tap(find.text(tr('Sınıflar ve öğrenciler')).first));
      }
    }
    L10n.use('tr');
    AppStore.showDemoNotice = true;
    debugDisableShadows = true;
    // ignore: avoid_print
    print('SORUNLAR ${problems.length}\n${problems.join('\n')}');
  });
}
