// App Store, iPad, Mac ve Microsoft Store için ekran görüntüleri.
//   flutter test tool/magaza/genis_ekranlar_test.dart --dart-define=LANG_SHOT=tr
// Çıktılar build/screenshots/<dil>/<boyut>_<ekran>.png; boyutlar:
//   telefon 430x932 (iPhone 6.9"), tablet 1032x1376 (iPad 13"),
//   masaustu 1440x900 (Mac 2880x1800, Windows).
// tool/magaza/paketler.py bunları başlıklı mağaza görsellerine dönüştürür.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/bank/bank_store.dart';
import 'package:netice/core/store.dart';
import 'package:netice/l10n/l10n.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/bank/booklet_wizard_screen.dart';
import 'package:netice/ui/exam_screen.dart';
import 'package:netice/ui/general_stats_screen.dart';
import 'package:netice/ui/parent_send_screen.dart';
import 'package:netice/ui/term_screen.dart';
import 'package:netice/ui/theme.dart';

import '../bank_preview_test.dart' show seedBank;
import '../screenshots_test.dart' show loadFonts, shot;

void main() {
  testWidgets('mağaza: telefon, tablet ve masaüstü ekranları', timeout: const Timeout(Duration(minutes: 15)),
      (tester) async {
    const lang = String.fromEnvironment('LANG_SHOT', defaultValue: 'tr');
    debugDisableShadows = false;
    await tester.runAsync(() => loadFonts(lang));
    L10n.use(lang);
    Directory('build/screenshots/$lang').createSync(recursive: true);
    AppStore.proFreeOnThisPlatform = true;
    final store = AppStore();
    final dir = Directory.systemTemp.createTempSync('genis');
    await tester.runAsync(() => store.load(dir: dir));
    store.onboardingDone = true;
    store.ratePrompted = true;
    store.hidePromo(const Duration(days: 3650));
    AppStore.showDemoNotice = false;
    final b = BankStore.instance;
    await tester.runAsync(() async {
      await b.load(dir: dir);
      await seedBank(b);
    });
    for (var i = 0; i < store.students.length; i++) {
      store.students[i] = store.students[i].copyWith(parentPhone: '+90 532 000 ${(1000 + i).toString()}');
    }
    final exam = store.examById('demo_exam')!;
    final names = [
      for (final r in store.resultsOf(exam)) ?store.studentById[r.sheet.studentId],
    ]..sort((a, b) => a.fullName.compareTo(b.fullName));
    for (final st in names.take(9)) {
      store.markParentSent(exam.id, st.id);
    }

    Widget themed(Widget home) => StoreScope(
          store: store,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: NTheme.light(),
            locale: L10n.locale,
            supportedLocales: [for (final l in AppLanguage.all) Locale(l.code)],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: home,
          ),
        );
    Widget app() => NeticeApp(store: store, splash: false);

    const sizes = {
      'telefon': Size(430, 932),
      'tablet': Size(1032, 1376),
      'masaustu': Size(1440, 900),
    };
    final problems = <String>[];
    for (final MapEntry(key: sz, value: size) in sizes.entries) {
      Future<void> s(String name, Widget w, {Future<void> Function()? then}) async {
        try {
          await shot(tester, w, size, '$lang/${sz}_$name', then: then);
        } catch (e) {
          problems.add('$sz $name: $e'.split('\n').first);
        }
      }

      await s('ana_sayfa', app());
      await s('sonuclar', themed(const ExamScreen(examId: 'demo_exam')));
      await s('analiz', themed(const ExamScreen(examId: 'demo_exam')),
          then: () async => tester.tap(find.text(tr('Analiz')).first));
      await s('kutuphane', app(), then: () async => tester.tap(find.text(tr('Kütüphane')).last));
      await s('kitapcik', themed(BookletWizardScreen(booklet: b.bookletById('k1'))), then: () async {
        await tester.tap(find.text(tr('Kitapçık')).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('A–D').first);
      });
      await s('veli', themed(const ParentSendScreen(examId: 'demo_exam')));
      await s('istatistik', themed(const GeneralStatsScreen()));
      await s('donem', themed(const TermScreen()));
    }
    L10n.use('tr');
    AppStore.showDemoNotice = true;
    debugDisableShadows = true;
    // ignore: avoid_print
    print('SORUNLAR ${problems.length}\n${problems.join('\n')}');
  });
}
