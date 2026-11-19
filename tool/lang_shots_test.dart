// Dil ekran görüntüleri: flutter test tool/lang_shots_test.dart
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/store.dart';
import 'package:netice/l10n/l10n.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/exam_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/ui/theme.dart';

import 'screenshots_test.dart' show loadFonts, shot;

/// Test ortamında sistem yedek yazı tipi yok; Latin dışı dillerde uygulama
/// yazı tipinin yerine o dilin Noto yazı tipi yüklenir (telefonda sistem
/// yazı tipi devreye girer).
Future<void> _loadLangFont(String lang) async {
  final file = switch (lang) {
    'ar' => 'NotoSansArabic-Regular',
    'zh' => 'NotoSansSC-Regular',
    'ja' => 'NotoSansJP-Regular',
    'ru' => 'NotoSans-Regular',
    _ => null,
  };
  if (file == null) return loadFonts();
  final l = FontLoader('PlusJakartaSans')
    ..addFont(Future.value(ByteData.sublistView(File('assets/pdf_fonts/$file.ttf').readAsBytesSync())));
  await l.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(
        File('/opt/sdk/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytesSync())));
  await icons.load();
}

void main() {
  testWidgets('dil ekran görüntüleri', (tester) async {
    debugDisableShadows = false;
    const lang = String.fromEnvironment('LANG_SHOT', defaultValue: 'en');
    await tester.runAsync(() => _loadLangFont(lang));
    {
      L10n.use(lang);
      final store = AppStore();
      await tester.runAsync(() => store.load(dir: Directory.systemTemp.createTempSync('shots')));
      store.onboardingDone = true;
      store.ratePrompted = true;
      await shot(tester, NeticeApp(store: store, splash: false), const Size(390, 1500), 'dil_${lang}_ana_sayfa');
      for (final (tab, name) in [(tr('Profil'), 'profil'), (tr('Ayarlar'), 'ayarlar'), (tr('Yardım'), 'yardim'), (tr('Sınıflar'), 'siniflar')]) {
        await shot(tester, NeticeApp(store: store, splash: false), const Size(390, 844), 'dil_${lang}_$name',
            then: () async => tester.tap(find.byTooltip(tab).last));
      }
      await shot(
          tester,
          StoreScope(
              store: store,
              child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: NTheme.light(),
                  locale: L10n.locale,
                  supportedLocales: [for (final l in AppLanguage.all) Locale(l.code)],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  home: const ExamScreen(examId: 'demo_exam'))),
          const Size(390, 1400),
          'dil_${lang}_sinav');
    }
    L10n.use('tr');
    debugDisableShadows = true;
  });
}
