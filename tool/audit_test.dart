// Ekran denetimi: her ekranı küçük telefon boyutunda açar, sonuna kadar
// kaydırır, taşmaları kaydeder ve görüntü alır.
// flutter test tool/audit_test.dart --dart-define=LANG_SHOT=de
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/store.dart';
import 'package:netice/l10n/l10n.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/admin_panel_screen.dart';
import 'package:netice/ui/compare_screen.dart';
import 'package:netice/ui/exam_screen.dart';
import 'package:netice/ui/general_stats_screen.dart';
import 'package:netice/ui/exam_settings_screen.dart';
import 'package:netice/ui/help_screen.dart';
import 'package:netice/ui/home_screen.dart';
import 'package:netice/ui/new_exam_screen.dart';
import 'package:netice/ui/onboarding_screen.dart';
import 'package:netice/ui/open_scores_screen.dart';
import 'package:netice/ui/license_screen.dart';
import 'package:netice/ui/pro_screen.dart';
import 'package:netice/ui/profile_screen.dart';
import 'package:netice/ui/scan_screen.dart';
import 'package:netice/ui/school_screen.dart';
import 'package:netice/ui/settings_screen.dart';
import 'package:netice/ui/student_detail_screen.dart';
import 'package:netice/ui/students_screen.dart';
import 'package:netice/ui/template_screen.dart';
import 'package:netice/ui/term_screen.dart';
import 'package:netice/ui/theme.dart';

Future<void> _fonts(String lang) async {
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await l.load();
  }

  final special = switch (lang) {
    'ar' => 'assets/pdf_fonts/NotoSansArabic-Regular.ttf',
    'zh' => 'assets/pdf_fonts/NotoSansSC-Regular.ttf',
    'ja' => 'assets/pdf_fonts/NotoSansJP-Regular.ttf',
    'ru' => 'assets/pdf_fonts/NotoSans-Regular.ttf',
    _ => null,
  };
  await load('PlusJakartaSans', special != null
      ? [special]
      : [for (final w in ['400Regular', '500Medium', '600SemiBold', '700Bold', '800ExtraBold']) 'assets/fonts/PlusJakartaSans_$w.ttf']);
  await load('MaterialIcons', ['/opt/sdk/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
}

void main() {
  testWidgets('ekran denetimi', timeout: const Timeout(Duration(minutes: 20)), (tester) async {
    const lang = String.fromEnvironment('LANG_SHOT', defaultValue: 'tr');
    debugDisableShadows = false;
    await tester.runAsync(() => _fonts(lang));
    L10n.use(lang);
    final store = AppStore();
    await tester.runAsync(() => store.load(dir: Directory.systemTemp.createTempSync('audit')));
    store.onboardingDone = true;
    store.ratePrompted = true;

    final problems = <String>[];
    var current = '';
    final old = FlutterError.onError;
    FlutterError.onError = (d) {
      final m = d.exceptionAsString().split('\n').first;
      final where = d.toString().split('\n').where((l) => l.contains('lib/ui/')).take(1).join();
      problems.add('$current: $m $where');
    };

    const size = Size(360, 760);
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    tester.view.padding = const FakeViewPadding(top: 48, bottom: 48);
    tester.view.viewPadding = tester.view.padding;
    Directory('build/audit/$lang').createSync(recursive: true);

    Future<void> capture(String name) async {
      await tester.runAsync(() async {
        final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
        final img = await b.toImage(pixelRatio: 1);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        File('build/audit/$lang/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    Future<void> screen(String name, Widget w, {Future<void> Function()? then}) async {
      current = name;
      // ignore: avoid_print
      print('EKRAN $name');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(RepaintBoundary(
        key: const ValueKey('shot'),
        child: StoreScope(
          store: store,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: NTheme.light(),
            locale: L10n.locale,
            supportedLocales: [for (final l in AppLanguage.all) Locale(l.code)],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: w,
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      if (then != null) {
        await then();
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
      await capture('${name}_1');
      // Sonuna kadar kaydır.
      final scrollables = find.byType(Scrollable);
      if (scrollables.evaluate().isNotEmpty) {
        Finder? target;
        for (final e in scrollables.evaluate()) {
          final s = e.widget as Scrollable;
          if (s.axisDirection == AxisDirection.down) {
            target = find.byWidget(s);
          }
        }
        if (target != null) {
          for (var i = 0; i < 12; i++) {
            await tester.drag(target.first, const Offset(0, -600), warnIfMissed: false);
            await tester.pump(const Duration(milliseconds: 50));
          }
          await tester.pump(const Duration(milliseconds: 600));
          await capture('${name}_2');
        }
      }
    }

    await screen('01_ana', const HomeScreen());
    await screen('02_siniflar', const Scaffold(body: StudentsScreen(embedded: true)));
    await screen('03_yardim', const HelpScreen());
    await screen('04_sss', const HelpScreen(initialTab: 1));
    await screen('05_profil', const ProfileScreen());
    await screen('06_ayarlar', const SettingsScreen());
    await screen('07_sinav', const ExamScreen(examId: 'demo_exam'));
    await screen('08_analiz', const ExamScreen(examId: 'demo_exam'),
        then: () async => tester.tap(find.descendant(of: find.byType(TabBar), matching: find.textContaining(tr('Analiz')))));
    await screen('09_kontrol', const ExamScreen(examId: 'demo_exam'),
        then: () async => tester.tap(find.descendant(of: find.byType(TabBar), matching: find.textContaining(tr('Kontrol')))));
    await screen('10_yeni_sinav', const NewExamScreen());
    await screen('11_sinav_ayarlari', const ExamSettingsScreen(examId: 'demo_exam'));
    await screen('12_ogrenci', const StudentDetailScreen(studentId: 'demo_5'));
    await screen('13_karsilastirma', const CompareScreen());
    await screen('14_okul', const SchoolScreen());
    await screen('15_rehber', const OnboardingScreen());
    await screen('16_donem', const TermScreen());
    await screen('17_klasik', const OpenScoresScreen(examId: 'demo_exam'));
    await screen('18_pro', const ProScreen());
    await screen('19_okut', const ScanScreen(examId: 'demo_exam'));
    await screen('20_sablonlar', const TemplatesScreen());
    await screen('21_kurum_lisansi', const LicenseScreen());
    await screen('22_yonetici_paneli', const AdminPanelScreen());
    await screen('23_genel_istatistik', const GeneralStatsScreen());

    FlutterError.onError = old;
    File('build/audit/$lang/sorunlar.txt').writeAsStringSync(problems.toSet().join('\n'));
    // ignore: avoid_print
    print('SORUNLAR ${problems.toSet().length}\n${problems.toSet().join('\n')}');
    L10n.use('tr');
  });
}
