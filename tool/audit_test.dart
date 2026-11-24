// Ekran denetimi: her ekranı küçük telefon boyutunda açar, sonuna kadar
// kaydırır, taşmaları kaydeder ve görüntü alır.
// flutter test tool/audit_test.dart --dart-define=LANG_SHOT=de
import 'dart:io';
import 'dart:math' as math;
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
  testWidgets('ekran denetimi', timeout: const Timeout(Duration(minutes: 40)), (tester) async {
    const lang = String.fromEnvironment('LANG_SHOT', defaultValue: 'tr');
    // --dart-define=DARK_SHOT=true: gece (koyu) modunda çizer.
    const dark = bool.fromEnvironment('DARK_SHOT');
    const outDir = dark ? 'build/audit/$lang-gece' : 'build/audit/$lang';
    debugDisableShadows = false;
    await tester.runAsync(() => _fonts(lang));
    L10n.use(lang);
    final store = AppStore();
    await tester.runAsync(() => store.load(dir: Directory.systemTemp.createTempSync('audit')));
    store.onboardingDone = true;
    store.ratePrompted = true;

    final problems = <String>[];
    final lowContrast = <String>{};
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
    Directory(outDir).createSync(recursive: true);

    Future<void> capture(String name) async {
      await tester.runAsync(() async {
        final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
        final img = await b.toImage(pixelRatio: 1);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$outDir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
        final raw = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        _contrast(b, raw!, img.width, img.height, name, lowContrast);
        File('$outDir/okunurluk.txt').writeAsStringSync(lowContrast.join('\n'));
      });
    }

    // --dart-define=ONLY=14,18: yalnız bu numaralı ekranlar.
    const only = String.fromEnvironment('ONLY');
    Future<void> screen(String name, Widget w, {Future<void> Function()? then}) async {
      if (only.isNotEmpty && !only.split(',').any((p) => name.startsWith(p))) return;
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
            darkTheme: NTheme.dark(),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
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
    File('$outDir/sorunlar.txt').writeAsStringSync(problems.toSet().join('\n'));
    File('$outDir/okunurluk.txt').writeAsStringSync(lowContrast.join('\n'));
    // ignore: avoid_print
    print('OKUNURLUK ${lowContrast.length}');
    // ignore: avoid_print
    print('SORUNLAR ${problems.toSet().length}\n${problems.toSet().join('\n')}');
    L10n.use('tr');
    debugDisableShadows = true;
  });
}


double _lum(int r, int g, int b) {
  double ch(int v) {
    final c = v / 255;
    return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b);
}

double _ratio(double a, double b) => (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);

/// Her yazının rengini, hemen çevresindeki zemin pikselleriyle karşılaştırır;
/// kontrast oranı 3'ün altındaysa (okunması zor) kaydeder.
void _contrast(RenderRepaintBoundary root, ByteData raw, int w, int h, String name, Set<String> out) {
  void visit(RenderObject o) {
    if (o is RenderParagraph && o.attached && o.hasSize && o.size.width > 4) {
      final style = (o.text is TextSpan) ? (o.text as TextSpan).style : null;
      Color? c = style?.color;
      if (c == null && o.text is TextSpan) {
        (o.text as TextSpan).visitChildren((s) {
          c ??= s.style?.color;
          return c == null;
        });
      }
      final text = o.text.toPlainText().trim();
      if (c != null && text.isNotEmpty && c!.a > 0.3) {
        final r = MatrixUtils.transformRect(o.getTransformTo(root), Offset.zero & o.size);
        if (r.top >= 0 && r.left >= 0 && r.bottom < h && r.right < w) {
          // Zemin: yazı kutusunun hemen dışındaki iki satır pikselin en sık rengi.
          final counts = <int, int>{};
          void px(int x, int y) {
            if (x < 0 || y < 0 || x >= w || y >= h) return;
            final i = (y * w + x) * 4;
            final v = (raw.getUint8(i) >> 3) << 10 | (raw.getUint8(i + 1) >> 3) << 5 | (raw.getUint8(i + 2) >> 3);
            counts[v] = (counts[v] ?? 0) + 1;
          }
          for (var x = r.left.floor(); x < r.right.ceil(); x += 2) {
            px(x, r.top.floor() - 2);
            px(x, r.bottom.ceil() + 1);
          }
          if (counts.isNotEmpty) {
            final bg = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
            final br = ((bg >> 10) & 31) << 3, bgG = ((bg >> 5) & 31) << 3, bb = (bg & 31) << 3;
            // Yazı rengini zemine karıştır (saydamlık).
            final a = c!.a;
            int mix(double f, int b) => ((f * 255) * a + b * (1 - a)).round();
            final tr = mix(c!.r, br), tg = mix(c!.g, bgG), tb = mix(c!.b, bb);
            final k = _ratio(_lum(tr, tg, tb), _lum(br, bgG, bb));
            if (k < 3) {
              final short = text.length > 40 ? '${text.substring(0, 40)}…' : text;
              out.add('$name  oran ${k.toStringAsFixed(1)}  "$short"  yazı #${tr.toRadixString(16).padLeft(2, '0')}${tg.toRadixString(16).padLeft(2, '0')}${tb.toRadixString(16).padLeft(2, '0')} zemin #${br.toRadixString(16).padLeft(2, '0')}${bgG.toRadixString(16).padLeft(2, '0')}${bb.toRadixString(16).padLeft(2, '0')}');
            }
          }
        }
      }
    }
    o.visitChildren(visit);
  }

  visit(root);
}
