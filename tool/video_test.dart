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
import 'package:netice/bank/bank_models.dart';
import 'package:netice/bank/bank_store.dart';
import 'package:netice/core/campaigns.dart';
import 'package:netice/core/pro.dart';
import 'package:netice/core/store.dart';
import 'package:netice/l10n/l10n.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/bank/ai_questions_screen.dart';
import 'package:netice/ui/bank/booklet_wizard_screen.dart';
import 'package:netice/ui/bank/image_tools.dart';
import 'package:netice/ui/bank/import_screens.dart';
import 'package:netice/ui/bank/library_screen.dart';
import 'package:netice/ui/bank/question_editor_screen.dart';
import 'package:netice/ui/exam_screen.dart';
import 'package:netice/ui/exam_settings_screen.dart';
import 'package:netice/ui/compare_screen.dart';
import 'package:netice/ui/general_stats_screen.dart';
import 'package:netice/ui/grade_scale_screen.dart';
import 'package:netice/ui/pro_screen.dart';
import 'package:netice/ui/school_offer_screen.dart';
import 'package:netice/ui/help_screen.dart';
import 'package:netice/ui/home_screen.dart';
import 'package:netice/ui/new_exam_screen.dart';
import 'package:netice/ui/onboarding_screen.dart';
import 'package:netice/core/models.dart';
import 'package:netice/ui/scan_screen.dart';
import 'package:netice/ui/school_screen.dart';
import 'package:netice/ui/settings_screen.dart';
import 'package:netice/ui/widgets.dart';
import 'package:netice/ui/splash_screen.dart';
import 'package:netice/ui/student_detail_screen.dart';
import 'package:netice/ui/term_screen.dart';
import 'package:netice/ui/students_screen.dart';
import 'package:netice/ui/theme.dart';

import 'guide_bank.dart';

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
    'hi' => 'assets/pdf_fonts/NotoSansDevanagari-Regular.ttf',
    'ko' => 'assets/pdf_fonts/NotoSansKR-Regular.ttf',
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
  // Not sistemi ekranındaki ülke adları için yedek yazı tipleri.
  for (final f in [
    ('FbNoto', 'NotoSans-Regular'),
    ('FbArabic', 'NotoSansArabic-Regular'),
    ('FbHI', 'NotoSansDevanagari-Regular'),
    ('FbKR', 'NotoSansKR-Regular'),
    ('FbJP', 'NotoSansJP-Regular'),
    ('FbSC', 'NotoSansSC-Regular'),
  ]) {
    await load(f.$1, ['assets/pdf_fonts/${f.$2}.ttf']);
  }
  await load('ReportSerif', ['assets/pdf_fonts/LiberationSerif-Regular.ttf', 'assets/pdf_fonts/LiberationSerif-Bold.ttf']);
  await load('MaterialIcons', [
    const String.fromEnvironment(
      'ICON_FONT',
      defaultValue: '/opt/sdk/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ),
  ]);
}

const _fallback = ['FbNoto', 'FbArabic', 'FbHI', 'FbKR', 'FbJP', 'FbSC'];

ThemeData _withFallback(ThemeData t) => t.copyWith(
      textTheme: t.textTheme.apply(fontFamilyFallback: _fallback),
      chipTheme: t.chipTheme.copyWith(
        labelStyle: (t.chipTheme.labelStyle ?? const TextStyle()).copyWith(fontFamilyFallback: _fallback),
      ),
    );

void main() {
  testWidgets('rehber videosu kareleri', timeout: const Timeout(Duration(minutes: 20)), (tester) async {
    const lang = String.fromEnvironment('LANG_SHOT', defaultValue: 'tr');
    debugDisableShadows = false;
    await tester.runAsync(() => _fonts(lang));
    L10n.use(lang);
    final store = AppStore();
    final dir = Directory.systemTemp.createTempSync('video');
    await tester.runAsync(() => store.load(dir: dir));
    final bank = BankStore.instance;
    await tester.runAsync(() async {
      await bank.load(dir: dir);
      await seedGuideBank(bank, lang);
    });
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
              theme: _withFallback(NTheme.light()),
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
      ]..removeWhere((r) => r[1] < 40 || r[1] + r[3] > 740);
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
    await scene('02_ana', const HomeScreen(), () => [tip(tr('Yeni sınav')), text(tr('Okut')), text(tr('Örnekleri sil'))]);
    await scene(
      '03_siniflar',
      const Scaffold(body: StudentsScreen(embedded: true)),
      () => [text(tr('Excel / PDF aktar')), text(tr('Öğrenci ekle'))],
    );
    await scene(
      '04_yeni_sinav',
      const NewExamScreen(),
      () => [find.byType(NumberStepper), find.text(tr('Sınavı kaydet'))],
    );
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
    // Kütüphane: soru bankası, notlar ve kitapçık (bölüm videosu "library").
    Finder fab() => find.byType(FloatingActionButton);
    await scene('12_kutuphane', const LibraryScreen(),
        () => [find.textContaining(tr('Kolay')).first, fab()]);
    await scene('k_soru_kes', CropImportScreen(pages: [DocPage(guidePage(guideBankData(lang)), 900, 1270)]),
        () => [find.byType(RectSelector), text(tr('Doğru cevap'))], then: () async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
        await settle();
      }
      final r = tester.getRect(find.descendant(of: find.byType(RectSelector), matching: find.byType(Image)).first);
      final from = Offset(r.left + r.width * 0.03, r.top + r.height * 0.075);
      final to = Offset(r.left + r.width * 0.96, r.top + r.height * 0.34);
      final g = await tester.startGesture(from);
      for (var i = 1; i <= 8; i++) {
        await g.moveTo(Offset.lerp(from, to, i / 8)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
    });
    await scene('k_soru_yaz', QuestionEditorScreen(question: bank.questionById('bq3')),
        () => [text(tr('Çoktan seçmeli')), text(tr('Görsel ekle')), text(tr('Şıklar'))]);
    await scene('k_notlar', const LibraryScreen(initialTab: 1),
        () => [find.byType(ChoiceChip).at(1), fab()]);
    await scene('k_sihirbaz', BookletWizardScreen(booklet: bank.bookletById('k1')),
        () => [text(tr('Bankadan seç')), text(tr('Otomatik seç'))]);
    await scene('k_kitapcik_turu', BookletWizardScreen(booklet: bank.bookletById('k1')),
        () => [text(tr('Kitapçık sayısı')), text(tr('Şıkları karıştır'))], then: () async {
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text(tr('İleri')).last);
        await settle();
      }
    });
    await scene('k_banka_analiz', const LibraryScreen(initialTab: 3),
        () => [text(tr('Zorluk dağılımı')), text(tr('Konu kapsamı'))]);
    // Kılavuz bölüm videoları için ek sahneler (tool/video/kilavuz.json).
    Future<void> reveal(Finder f, {double dy = -160, bool lazy = false}) async {
      // lazy: hedef henüz çizilmemiş olabilir (uzun liste), yine de kaydır.
      if (!lazy && f.evaluate().isEmpty) return;
      try {
        await tester.dragUntilVisible(f, find.byType(Scrollable).first, Offset(0, dy));
        await settle();
        // Hedefi ekranın ortasına doğru getir.
        final y = tester.getRect(f.first).top;
        if (y > 380) await tester.drag(find.byType(Scrollable).first, Offset(0, -(y - 300)));
      } catch (_) {}
    }

    await scene(
      'k_sinav_ayar',
      const ExamSettingsScreen(examId: 'demo_exam'),
      () => [text(tr('Tam puan')), text(tr('Kitapçık türü')), text(tr('Klasik (yazılı) sorular'))],
      then: () async => tester.drag(find.byType(Scrollable).first, const Offset(0, -200)),
    );
    await scene(
      'k_sablon',
      const SettingsScreen(),
      () => [text(tr('Başka firma formları'))],
      then: () => reveal(text(tr('Başka firma formları'))),
    );
    await scene('k_donem', const TermScreen(), () => [find.byType(Checkbox), find.byType(FilledButton)]);
    await scene(
      'k_yedek',
      const SettingsScreen(),
      () => [text(tr('Yedeği dosyaya kaydet')), text(tr('Yedekten geri yükle'))],
      then: () => reveal(text(tr('Yedeği dosyaya kaydet'))),
    );
    // Nottan soru üretme ve çocuk kitapçığı (bölüm videosu "library").
    final drafts = [for (final id in ['bq5', 'bq6', 'bq7']) bank.questionById(id)].whereType<BankQuestion>().toList();
    await scene('k_yz_soru', AiQuestionsScreen(noteId: 'n3', initialDrafts: drafts),
        () => [text(tr('Çocuklar için (ilkokul)')), find.byType(FilledButton).first, text(tr('Öneriler'))],
        then: () => reveal(text(tr('Çocuklar için (ilkokul)')), dy: -200));
    await scene('k_cocuk', BookletWizardScreen(booklet: bank.bookletById('k1')), () => [text(tr('Çocuk / İlkokul'))],
        then: () async {
      await tester.tap(find.text(tr('İleri')).last);
      await settle();
      await tester.tap(find.text(tr('Çocuk / İlkokul')).last);
    });
    // Sınıf sınıf analiz ve genel istatistik (bölüm videosu "report").
    await scene('k_sinif_analiz', const CompareScreen(),
        () => [find.byType(FilterChip), text(tr('Öne çıkanlar')), tip(tr('PDF rapor'))],
        then: () async {
          await reveal(find.text(tr('Öne çıkanlar')), lazy: true);
          // Sınav seçimi de görünsün: biraz geri kaydır.
          await tester.drag(find.byType(Scrollable).first, const Offset(0, 220));
        });
    await scene('k_genel_istatistik', const GeneralStatsScreen(),
        () => [find.byType(ChoiceChip), find.textContaining(tr('GENEL BAŞARI')), tip(tr('PDF rapor'))]);
    // Not sistemi (bölüm videosu "report").
    await scene('k_not_sistemi', const GradeScaleScreen(),
        () => [text(tr('Hazır sistemler')), text(tr('Kendim yazacağım')), text(tr('Düzeyler'))],
        then: () => reveal(text(tr('Kendim yazacağım'))));
    // Netice Pro (bölüm videosu "pro"): kampanyasız bir gün, deneme bitmiş.
    Campaign.debugNow = DateTime(2026, 10, 15);
    AppStore.proFreeOnThisPlatform = false;
    store.trialStart = DateTime.now().subtract(const Duration(days: 40));
    await tester.runAsync(() => ProService.instance.attach(store));
    Finder plan(String s) => find.ancestor(of: find.text(s), matching: find.byType(InkWell));
    await scene('k_pro', const ProScreen(),
        () => [plan(tr('Pro · yıllık')), plan(tr('Pro + Yapay Zekâ · yıllık')), plan(tr('Sınav dönemi paketi'))],
        then: () => reveal(find.text(tr('Pro · yıllık')), lazy: true));
    await scene('k_pro_alt', const ProScreen(),
        () => [find.textContaining(tr('Ek soru paketi · {0} soru', [200])), text(tr('Okul / zümre paketi'))],
        then: () => reveal(find.text(tr('Okul / zümre paketi')), dy: -300, lazy: true));
    await scene('k_okul', const SchoolOfferScreen(), () => [find.byType(Card).first, find.byType(FilledButton).last]);
    AppStore.proFreeOnThisPlatform = true;
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
  'pt': 'Escola Estadual Monteiro Lobato',
  'hi': 'केंद्रीय विद्यालय, लखनऊ',
  'id': 'SMA Negeri 8 Jakarta',
  'ko': '한빛고등학교',
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
  'pt': 'São Paulo',
  'hi': 'लखनऊ',
  'id': 'Jakarta',
  'ko': '서울',
};
