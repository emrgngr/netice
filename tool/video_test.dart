// Rehber videosu için ekran görüntüleri ve işaret konumları.
// flutter test tool/video_test.dart --dart-define=LANG_SHOT=tr
// Çıktı: build/video/frames/<dil>/<sahne>.png ve hedefler.json
// (hedefler 360x760 mantıksal koordinatta: x, y, genişlik, yükseklik).
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/store.dart';
import 'package:netice/l10n/l10n.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/exam_screen.dart';
import 'package:netice/ui/help_screen.dart';
import 'package:netice/ui/home_screen.dart';
import 'package:netice/ui/new_exam_screen.dart';
import 'package:netice/ui/onboarding_screen.dart';
import 'package:netice/core/models.dart';
import 'package:netice/ui/scan_screen.dart';
import 'package:netice/ui/school_screen.dart';
import 'package:netice/ui/settings_screen.dart';
import 'package:netice/ui/splash_screen.dart';
import 'package:netice/ui/student_detail_screen.dart';
import 'package:netice/ui/students_screen.dart';
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
  await load(
    'PlusJakartaSans',
    special != null
        ? [special]
        : [
            for (final w in ['400Regular', '500Medium', '600SemiBold', '700Bold', '800ExtraBold'])
              'assets/fonts/PlusJakartaSans_$w.ttf',
          ],
  );
  await load('ReportSerif', ['assets/pdf_fonts/LiberationSerif-Regular.ttf', 'assets/pdf_fonts/LiberationSerif-Bold.ttf']);
  await load('MaterialIcons', [
    const String.fromEnvironment(
      'ICON_FONT',
      defaultValue: '/opt/sdk/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ),
  ]);
}

void main() {
  testWidgets('rehber videosu kareleri', timeout: const Timeout(Duration(minutes: 20)), (tester) async {
    const lang = String.fromEnvironment('LANG_SHOT', defaultValue: 'tr');
    debugDisableShadows = false;
    await tester.runAsync(() => _fonts(lang));
    L10n.use(lang);
    final store = AppStore();
    await tester.runAsync(() => store.load(dir: Directory.systemTemp.createTempSync('video')));
    store.onboardingDone = true;
    store.ratePrompted = true;

    const size = Size(360, 760);
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 72, bottom: 72);
    tester.view.viewPadding = tester.view.padding;
    final out = Directory('build/video/frames/$lang')..createSync(recursive: true);
    final targets = <String, List<List<double>>>{};

    Future<void> capture(String name) async {
      await tester.runAsync(() async {
        final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
        final img = await b.toImage(pixelRatio: 3);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        File('${out.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    Future<void> mount(Widget w) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        RepaintBoundary(
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
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    void mark(String name, List<Finder> finders) {
      targets[name] = [
        for (final f in finders)
          if (f.evaluate().isNotEmpty)
            (() {
              final r = tester.getRect(f.first);
              return [r.left, r.top, r.width, r.height];
            })(),
      ];
    }

    Future<void> scene(String name, Widget w, List<Finder> Function() finders, {Future<void> Function()? then}) async {
      // ignore: avoid_print
      print('SAHNE $name');
      await mount(w);
      if (then != null) {
        await then();
        await settle();
      }
      mark(name, finders());
      await capture(name);
    }

    // Açılış animasyonu: 24 kare.
    for (var i = 0; i < 24; i++) {
      await mount(SplashScreen(next: const SizedBox(), night: false, freezeAt: i / 23));
      await capture('00_acilis_${i.toString().padLeft(2, '0')}');
    }

    Finder text(String s) => find.text(s);
    Finder tip(String s) => find.byTooltip(s);

    await scene('01_tanitim', const OnboardingScreen(), () => [find.textContaining(tr('Devam'))]);
    await scene('02_ana', const HomeScreen(), () => [tip(tr('Yeni sınav')), text(tr('Okut'))]);
    await scene(
      '03_siniflar',
      const Scaffold(body: StudentsScreen(embedded: true)),
      () => [text(tr('Excel aktar')), text(tr('Öğrenci ekle'))],
    );
    await scene('04_yeni_sinav', const NewExamScreen(), () => [find.byType(Slider), find.text(tr('Sınavı kaydet'))]);
    await scene(
      '05_form_yazdir',
      const ExamScreen(examId: 'demo_exam'),
      () => [text(tr('Form yazdır'))],
      then: () async => tester.tap(
        find.byType(PopupMenuButton<Object>).evaluate().isNotEmpty
            ? find.byType(PopupMenuButton<Object>)
            : find.byIcon(Icons.more_vert).first,
      ),
    );
    await scene('06_okut', const ExamScreen(examId: 'demo_exam'), () => [find.byType(FloatingActionButton)]);
    await scene('07_okut_ekrani', const ScanScreen(examId: 'demo_exam'), () => [find.byType(FilledButton)]);
    await scene('08_sonuclar', const ExamScreen(examId: 'demo_exam'), () => [find.byType(ListTile)]);
    await scene(
      '09_analiz',
      const ExamScreen(examId: 'demo_exam'),
      () => [text(tr('Sınav raporu')), text(tr('Öğrenci karnesi'))],
      then: () async =>
          tester.tap(find.descendant(of: find.byType(TabBar), matching: find.textContaining(tr('Analiz')))),
    );
    await scene(
      '10_ogrenci',
      const StudentDetailScreen(studentId: 'demo_5'),
      () => [find.textContaining(tr('Destek gerekebilir'))],
    );
    // Kurum bilgileri: Türkçede resmi başlık sırası (Valilik > Millî Eğitim >
    // okul), diğer dillerde o ülkenin biçimi.
    store.school = lang == 'tr'
        ? const SchoolInfo(
            type: InstitutionType.school,
            province: 'Ankara',
            district: 'Merkez',
            name: 'Atatürk Anadolu Lisesi',
            principal: 'Ayşe Demir',
            teacher: 'Emine Yılmaz',
            subject: 'Matematik',
            turkishFormat: true,
            fontFamily: 'times',
          )
        : SchoolInfo(
            name: _schoolName[lang] ?? 'Riverside High School',
            province: _city[lang] ?? 'London',
            principal: 'A. Smith',
            teacher: 'E. Brown',
            turkishFormat: false,
            fontFamily: 'times',
          );
    await scene(
      '11_kurum',
      const SchoolScreen(),
      () => [
        if (lang == 'tr') ...[
          text(tr('Okul adı')),
          text('ANKARA VALİLİĞİ'),
        ] else ...[
          text(tr('Kurum türü')),
          text(_schoolName[lang] ?? 'Riverside High School'),
        ],
      ],
      then: () async {
        if (lang == 'tr') await tester.drag(find.byType(Scrollable).first, const Offset(0, -330));
      },
    );
    await scene(
      '12_ayarlar',
      const SettingsScreen(),
      () => [text(tr('Uygulama dili')), text(tr('Yedeği dosyaya kaydet'))],
    );
    await scene('13_yardim', const HelpScreen(), () => [find.textContaining(tr('Sık sorulanlar'))]);

    File('${out.path}/hedefler.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(targets));
    L10n.use('tr');
  });
}

const _schoolName = {
  'en': 'Riverside High School',
  'az': 'Bakı 6 nömrəli tam orta məktəb',
  'de': 'Goethe-Gymnasium',
  'ar': 'مدرسة النور الثانوية',
  'es': 'IES Miguel de Cervantes',
  'ru': 'Школа № 57',
  'it': 'Liceo Galileo Galilei',
  'fr': 'Lycée Victor Hugo',
  'zh': '北京市第四中学',
  'ja': '桜ヶ丘高等学校',
};

const _city = {
  'en': 'London',
  'az': 'Bakı',
  'de': 'Berlin',
  'ar': 'القاهرة',
  'es': 'Madrid',
  'ru': 'Москва',
  'it': 'Bologna',
  'fr': 'Paris',
  'zh': '北京',
  'ja': '東京',
};
