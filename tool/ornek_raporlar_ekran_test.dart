// "Örnek raporlar" ekranının görüntüleri (telefon ve masaüstü, gündüz ve gece):
//   flutter test tool/ornek_raporlar_test.dart && tool/site/ornek_raporlar.sh kucuk
//   flutter test tool/ornek_raporlar_ekran_test.dart
// Küçük görüntüler build/ornek-raporlar/kucuk/tr/<ad>.png dosyalarından gelir
// (testte PDF çizici olmadığından). Çıktı: build/screenshots/ornek_raporlar_*.png
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/store.dart';
import 'package:netice/l10n/l10n.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/sample_reports.dart';
import 'package:netice/ui/sample_reports_screen.dart';
import 'package:netice/ui/theme.dart';

import 'screenshots_test.dart' show loadFonts, shot;

void main() {
  testWidgets('örnek raporlar ekranı', timeout: const Timeout(Duration(minutes: 10)), (tester) async {
    debugDisableShadows = false;
    await tester.runAsync(loadFonts);
    const lang = String.fromEnvironment('LANG_SHOT', defaultValue: 'tr');
    L10n.use(lang);
    final store = AppStore();
    await tester.runAsync(() => store.load(dir: Directory.systemTemp.createTempSync('ornek')));
    store.onboardingDone = true;
    final thumbs = <String, List<int>>{};
    for (final f in Directory('build/ornek-raporlar/kucuk/$lang').listSync().whereType<File>()) {
      thumbs[f.uri.pathSegments.last.replaceAll('.png', '')] = f.readAsBytesSync();
    }
    SampleReportsScreen.thumbOverride = (r) async {
      final b = thumbs[r.slug];
      return b == null ? null : Uint8List.fromList(b);
    };
    Future<void> precache() => tester.runAsync(() async {
          for (final e in find.byType(Image).evaluate()) {
            await precacheImage((e.widget as Image).image, e);
          }
        });
    for (final dark in [false, true]) {
      final app = StoreScope(
        store: store,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? NTheme.dark() : NTheme.light(),
          home: const SampleReportsScreen(),
        ),
      );
      final th = dark ? 'gece' : 'gunduz';
      await shot(tester, app, const Size(1440, 1000), 'ornek_raporlar_masaustu_$th', then: precache);
      await shot(tester, app, const Size(390, 844), 'ornek_raporlar_telefon_$th', then: precache);
      await shot(tester, app, const Size(390, 844), 'ornek_raporlar_telefon_${th}_2', then: () async {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
        await tester.pumpAndSettle();
        await precache();
      });
    }
    SampleReportsScreen.thumbOverride = null;
    debugDisableShadows = true;
  });
}
