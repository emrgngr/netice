// Sınıf sınıf analiz ve genel istatistik önizlemesi:
// flutter test tool/stats_preview_test.dart [--dart-define=LANG_SHOT=en]
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/store.dart';
import 'package:netice/l10n/l10n.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/compare_screen.dart';
import 'package:netice/ui/general_stats_screen.dart';
import 'package:netice/ui/theme.dart';

import 'screenshots_test.dart' show loadFonts, shot;

void main() {
  testWidgets('istatistik ekranları', timeout: const Timeout(Duration(minutes: 10)), (tester) async {
    const lang = String.fromEnvironment('LANG_SHOT', defaultValue: 'tr');
    await tester.runAsync(loadFonts);
    L10n.use(lang);
    final problems = <String>[];
    final old = FlutterError.onError;
    FlutterError.onError = (d) => problems.add(d.exceptionAsString().split('\n').first);
    for (final pro in [true, false]) {
      AppStore.proFreeOnThisPlatform = pro;
      final store = AppStore()
        ..seedDemo()
        ..onboardingDone = true;
      Widget app(Widget home) => StoreScope(
          store: store,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: NTheme.light(),
            locale: L10n.locale,
            supportedLocales: [for (final l in AppLanguage.all) Locale(l.code)],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: home,
          ));
      final s = pro ? 'pro' : 'ucretsiz';
      await shot(tester, app(const CompareScreen()), Size(390, pro ? 5600 : 3600), '${lang}_sinif_analizi_$s');
      await shot(tester, app(const GeneralStatsScreen()), Size(390, pro ? 7600 : 3400), '${lang}_genel_istatistik_$s');
    }
    FlutterError.onError = old;
    L10n.use('tr');
    // ignore: avoid_print
    print('SORUNLAR ${problems.length}\n${problems.toSet().join('\n')}');
  });
}
