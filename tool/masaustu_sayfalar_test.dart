// Masaüstü: yan menüdeki bütün sayfaların geniş pencere görüntüleri.
//   flutter test tool/masaustu_sayfalar_test.dart
// Çıktılar build/screenshots/sayfalar/<tema>_<no>_<sayfa>.png (uzun sayfalar kaydırılarak da çekilir).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/store.dart';
import 'package:netice/l10n/l10n.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/section_icons.dart';

import 'screenshots_test.dart' show loadFonts, shot;

void main() {
  testWidgets('masaüstü sayfaları', timeout: const Timeout(Duration(minutes: 10)), (tester) async {
    const themes = String.fromEnvironment('THEMES', defaultValue: 'light');
    debugDisableShadows = false;
    await tester.runAsync(loadFonts);
    L10n.use('tr');
    Directory('build/screenshots/sayfalar').createSync(recursive: true);
    final store = AppStore();
    final dir = Directory.systemTemp.createTempSync('sayfalar');
    await tester.runAsync(() => store.load(dir: dir));
    store.onboardingDone = true;
    store.ratePrompted = true;
    store.hidePromo(const Duration(days: 3650));
    AppStore.showDemoNotice = false;
    const size = Size(1440, 900);
    final pages = [
      Section.dashboard, Section.exams, Section.classes, Section.stats, Section.compare,
      Section.library, Section.profile, Section.settings, Section.help, Section.why,
    ];
    final problems = <String>[];
    for (final theme in themes.split(',')) {
      store.setThemeMode(theme);
      for (final (i, sec) in pages.indexed) {
        for (final scroll in [0.0, 800.0, 1600.0]) {
          final name = 'sayfalar/${theme}_${i.toString().padLeft(2, '0')}_${sec.name}${scroll == 0 ? '' : '_${scroll.toInt()}'}';
          final old = FlutterError.onError;
          FlutterError.onError = (d) => problems.add('$name: ${d.exceptionAsString().split('\n').first}');
          var canScroll = true;
          try {
            await shot(tester, NeticeApp(store: store, splash: false), size, name, then: () async {
              if (sec != Section.dashboard) {
                await tester.tap(find.text(sec.label).first);
                await tester.pumpAndSettle();
              }
              if (scroll > 0) {
                final s = find.byType(Scrollable);
                ScrollableState? best;
                for (final e in s.evaluate()) {
                  final st = (e as StatefulElement).state as ScrollableState;
                  if (st.position.axis != Axis.vertical) continue;
                  if (best == null || st.position.maxScrollExtent > best.position.maxScrollExtent) best = st;
                }
                if (best == null || best.position.maxScrollExtent < scroll - 400) {
                  canScroll = false;
                  return;
                }
                best.position.jumpTo(scroll.clamp(0, best.position.maxScrollExtent));
              }
            });
          } catch (e) {
            problems.add('$name: ${'$e'.split('\n').first}');
          } finally {
            FlutterError.onError = old;
          }
          if (!canScroll) {
            File('build/screenshots/$name.png').deleteSync();
            break;
          }
        }
      }
    }
    AppStore.showDemoNotice = true;
    debugDisableShadows = true;
    // ignore: avoid_print
    print('SORUNLAR ${problems.length}\n${problems.join('\n')}');
  });
}
