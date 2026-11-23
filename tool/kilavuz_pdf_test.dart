// Kullanım kılavuzu PDF'i için ekran görüntüleri ve işaretlenecek düğmelerin
// konumları. flutter test tool/kilavuz_pdf_test.dart
// Çıktı: build/kilavuz/frames/<sahne>.png ve hedefler.json
// (hedefler 360x760 mantıksal koordinatta: {sahne: {ad: [x, y, gen, yük]}}).
// PDF: python3 tool/kilavuz/kilavuz_pdf.py
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/store.dart';
import 'package:netice/l10n/l10n.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/exam_screen.dart';
import 'package:netice/ui/exam_settings_screen.dart';
import 'package:netice/ui/help_screen.dart';
import 'package:netice/ui/home_screen.dart';
import 'package:netice/ui/new_exam_screen.dart';
import 'package:netice/ui/onboarding_screen.dart';
import 'package:netice/ui/profile_screen.dart';
import 'package:netice/ui/scan_screen.dart';
import 'package:netice/ui/school_screen.dart';
import 'package:netice/ui/settings_screen.dart';
import 'package:netice/ui/student_detail_screen.dart';
import 'package:netice/ui/students_screen.dart';
import 'package:netice/ui/term_screen.dart';
import 'package:netice/ui/theme.dart';
import 'package:netice/ui/widgets.dart';

Future<void> _fonts() async {
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await l.load();
  }

  await load('PlusJakartaSans', [
    for (final w in ['400Regular', '500Medium', '600SemiBold', '700Bold', '800ExtraBold'])
      'assets/fonts/PlusJakartaSans_$w.ttf',
  ]);
  await load('ReportSerif', ['assets/pdf_fonts/LiberationSerif-Regular.ttf', 'assets/pdf_fonts/LiberationSerif-Bold.ttf']);
  await load('MaterialIcons', [
    '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/sdk/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
}

void main() {
  testWidgets('kılavuz görüntüleri', timeout: const Timeout(Duration(minutes: 20)), (tester) async {
    debugDisableShadows = false;
    await tester.runAsync(_fonts);
    L10n.use('tr');
    final store = AppStore();
    await tester.runAsync(() => store.load(dir: Directory.systemTemp.createTempSync('kilavuz')));
    store.onboardingDone = true;
    store.ratePrompted = true;

    const size = Size(360, 760);
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 72, bottom: 48);
    tester.view.viewPadding = tester.view.padding;
    final out = Directory('build/kilavuz/frames')..createSync(recursive: true);
    final targets = <String, Map<String, List<double>>>{};

    Future<void> capture(String name) async {
      await tester.runAsync(() async {
        final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
        final img = await b.toImage(pixelRatio: 3);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        File('${out.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
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
              darkTheme: NTheme.dark(),
              themeMode: store.themeMode == 'dark' ? ThemeMode.dark : ThemeMode.light,
              locale: L10n.locale,
              supportedLocales: [for (final l in AppLanguage.all) Locale(l.code)],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: w,
            ),
          ),
        ),
      );
      await settle();
    }

    Future<void> scene(String name, Widget w, Map<String, Finder> Function() finders,
        {Future<void> Function()? then}) async {
      // ignore: avoid_print
      print('SAHNE $name');
      await mount(w);
      if (then != null) {
        await then();
        await settle();
      }
      final m = <String, List<double>>{};
      for (final e in finders().entries) {
        var none = true;
        try {
          none = e.value.evaluate().isEmpty;
        } catch (_) {}
        if (none) {
          // ignore: avoid_print
          print('  bulunamadı: ${e.key}');
          continue;
        }
        final r = tester.getRect(e.value);
        if (r.bottom < 0 || r.top > size.height) continue;
        m[e.key] = [r.left, r.top, r.width, r.height];
      }
      targets[name] = m;
      await capture(name);
    }

    Finder text(String s) => find.text(s).last;
    Finder tip(String s) => find.byTooltip(s).first;
    Future<void> scrollTo(Finder f, {double center = 330}) async {
      final sc = find.byType(Scrollable).first;
      for (var i = 0; i < 12; i++) {
        var seen = false;
        try {
          seen = f.evaluate().isNotEmpty && tester.getRect(f).top < 640;
        } catch (_) {}
        if (seen) break;
        await tester.drag(sc, const Offset(0, -200));
        await settle();
      }
      try {
        final y = tester.getRect(f).top;
        if (y > center + 50) await tester.drag(sc, Offset(0, -(y - center)));
        await settle();
      } catch (_) {}
    }

    // 1. Başlarken
    await scene('01_tanitim', const OnboardingScreen(), () => {'devam': find.textContaining('Devam').first});
    await scene('02_ana', const HomeScreen(), () => {
          'tema': tip('Gece moduna geç'),
          'yeni': tip('Yeni sınav'),
          'okut': find.text('Okut').first,
          'ornek': find.text('Örnekleri sil').first,
        });
    await scene('03_menu', const HomeScreen(), () => {
          'ana': text('Ana sayfa'),
          'siniflar': text('Sınıflar'),
          'yardim': text('Yardım'),
          'profil': text('Profil'),
          'ayarlar': text('Ayarlar'),
        });
    await scene('04_siniflar', const Scaffold(body: StudentsScreen(embedded: true)), () => {
          'aktar': find.text('Excel / PDF aktar').first,
          'ekle': find.text('Öğrenci ekle').first,
        });
    await scene('05_profil', const Scaffold(body: ProfileScreen()), () => {'kurum': find.text('Kurum bilgileri').first},
        then: () => scrollTo(find.text('Kurum bilgileri').first));
    store.school = const SchoolInfo(
      type: InstitutionType.school,
      province: 'Ankara',
      district: 'Merkez',
      name: 'Atatürk Anadolu Lisesi',
      principal: 'Ayşe Demir',
      teacher: 'Emine Yılmaz',
      subject: 'Matematik',
      turkishFormat: true,
      fontFamily: 'times',
    );
    await scene('06_kurum', const SchoolScreen(), () => {
          'il': find.text('Ankara').first,
          'ad': find.text('Okul adı').first,
          'baslik': find.text('ANKARA VALİLİĞİ').first,
        }, then: () async => tester.drag(find.byType(Scrollable).first, const Offset(0, -330)));

    // 2. Sınav hazırlama
    await scene('07_yeni_sinav', const NewExamScreen(), () => {
          'soru': find.byType(NumberStepper).first,
          'kaydet': find.text('Sınavı kaydet').first,
        });
    await scene('08_sinav_ayar', const ExamSettingsScreen(examId: 'demo_exam'), () => {
          'tam': find.text('Tam puan').first,
          'yanlis': find.text('Yanlış götürme').first,
          'form': find.text('Netice formu (önerilen)').first,
        }, then: () async => tester.drag(find.byType(Scrollable).first, const Offset(0, -200)));

    // 3. Form yazdırma
    await scene('09_form_yazdir', const ExamScreen(examId: 'demo_exam'), () => {'form': find.text('Form yazdır').last},
        then: () async => tester.tap(find.byIcon(Icons.more_vert).first));
    await scene('10_sablon', const SettingsScreen(), () => {'sablon': find.text('Başka firma formları').first},
        then: () => scrollTo(find.text('Başka firma formları').first));

    // 4. Kâğıt okutma
    await scene('11_okut', const ExamScreen(examId: 'demo_exam'), () => {'okut': find.byType(FloatingActionButton).first});
    await scene('12_okut_ekrani', const ScanScreen(examId: 'demo_exam'), () => {
          'sec': find.byType(FilledButton).first,
          'ornek': find.text('Örnek form').first,
        });

    // 5. Sonuçlar ve raporlar
    await scene('13_sonuclar', const ExamScreen(examId: 'demo_exam'), () => {
          'sekme': find.text('Sonuçlar').first,
          'ogrenci': find.byType(ListTile).last,
        }, then: () => scrollTo(find.text('Öğrenciler').first, center: 260));
    await scene('14_detay', const ExamScreen(examId: 'demo_exam'), () => {
          'gecmis': find.text('Öğrenci geçmişi ve gelişimi').first,
          'karne': find.text('Karneyi veliye gönder').first,
          'sil': find.text('Bu okumayı sil').first,
        }, then: () async {
          await scrollTo(find.text('Öğrenciler').first, center: 260);
          await tester.tap(find.byType(ListTile).at(2));
        });
    await scene('15_analiz', const ExamScreen(examId: 'demo_exam'), () => {
          'sekme': find.text('Analiz').first,
          'rapor': find.text('Sınav raporu').first,
          'karne': find.text('Öğrenci karnesi').first,
        }, then: () async => tester.tap(find.descendant(of: find.byType(TabBar), matching: find.text('Analiz'))));
    await scene('16_ogrenci', const StudentDetailScreen(studentId: 'demo_5'), () => {
          'uyari': find.textContaining('Destek gerekebilir').first,
        });
    await scene('17_donem', const TermScreen(), () => {
          'sec': find.byType(Checkbox).first,
          'olustur': find.byType(FilledButton).first,
        });

    // 6. Silme
    await scene('18_sec_sil', const HomeScreen(), () => {
          'sec': find.text('Seç ve sil').first,
        }, then: () async {
          for (var i = 0; i < 8 && find.text('Seç ve sil').evaluate().isEmpty; i++) {
            await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -250));
            await settle();
          }
          // ignore: avoid_print
          print('  seç ve sil: ${find.text('Seç ve sil').evaluate().length}, scrollables: ${find.byType(Scrollable).evaluate().length}');
          await scrollTo(find.text('Seç ve sil').first, center: 300);
        });
    await scene('19_secildi', const HomeScreen(), () => {
          'kart': find.byIcon(Icons.check_rounded).first,
          'tumu': find.text('Tümünü seç').first,
          'sil': tip('Seçilenleri sil'),
          'vazgec': tip('Vazgeç'),
        }, then: () async {
          for (var i = 0; i < 8 && find.text('Seç ve sil').evaluate().isEmpty; i++) {
            await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -250));
            await settle();
          }
          await scrollTo(find.text('Seç ve sil').first, center: 300);
          await tester.tap(find.text('Seç ve sil').first);
          await settle();
          await tester.tap(find.text('Fizik Quiz 1 (örnek)').first);
        });

    // 7. Ayarlar ve verileriniz
    await scene('20_gorunum', const SettingsScreen(), () => {
          'dil': find.text('Uygulama dili').first,
          'otomatik': find.text('Otomatik').first,
          'gunduz': find.text('Gündüz').first,
          'gece': find.text('Gece').first,
        });
    store.themeMode = 'dark';
    await scene('21_gece', const HomeScreen(), () => {'tema': tip('Gündüz moduna geç')});
    store.themeMode = 'light';
    await scene('22_yedek', const SettingsScreen(), () => {
          'kaydet': find.text('Yedeği dosyaya kaydet').first,
          'yukle': find.text('Yedekten geri yükle').first,
        }, then: () => scrollTo(find.text('Yedeği dosyaya kaydet').first));
    await scene('23_yardim', const HelpScreen(), () => {
          'kilavuz': find.text('Kılavuz').first,
          'sss': find.textContaining('Sık sorulanlar').first,
        });

    File('${out.path}/hedefler.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(targets));
    debugDisableShadows = true;
  });
}
