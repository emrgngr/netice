// Kullanım kılavuzu PDF'i için ekran görüntüleri ve işaretlenecek düğmelerin
// konumları. flutter test tool/kilavuz_pdf_test.dart --dart-define=KILAVUZ_DIL=tr
// Çıktı: build/kilavuz/<dil>/frames/<sahne>.png ve hedefler.json
// (hedefler 360x760 mantıksal koordinatta: {sahne: {ad: [x, y, gen, yük]}}).
// PDF: python3 tool/kilavuz/kilavuz_pdf.py <dil>
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
import 'package:netice/core/models.dart';
import 'package:netice/core/store.dart';
import 'package:netice/l10n/l10n.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/exam_screen.dart';
import 'package:netice/ui/bank/ai_questions_screen.dart';
import 'package:netice/ui/bank/booklet_wizard_screen.dart';
import 'package:netice/ui/bank/image_tools.dart';
import 'package:netice/ui/bank/import_screens.dart';
import 'package:netice/ui/bank/library_screen.dart';
import 'package:netice/ui/bank/note_screens.dart';
import 'package:netice/ui/bank/question_editor_screen.dart';
import 'package:netice/ui/exam_settings_screen.dart';
import 'package:netice/ui/grade_scale_screen.dart';
import 'package:netice/ui/help_screen.dart';
import 'package:netice/ui/home_screen.dart';
import 'package:netice/ui/new_exam_screen.dart';
import 'package:netice/ui/onboarding_screen.dart';
import 'package:netice/ui/pro_screen.dart';
import 'package:netice/ui/profile_screen.dart';
import 'package:netice/ui/scan_screen.dart';
import 'package:netice/ui/school_offer_screen.dart';
import 'package:netice/ui/school_screen.dart';
import 'package:netice/ui/settings_screen.dart';
import 'package:netice/ui/student_detail_screen.dart';
import 'package:netice/ui/students_screen.dart';
import 'package:netice/ui/term_screen.dart';
import 'package:netice/ui/theme.dart';
import 'package:netice/ui/widgets.dart';

import 'guide_bank.dart';

Future<void> _fonts(String lang) async {
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await l.load();
  }

  // Test ortamında sistem yedek yazı tipi yok; Latin dışı dillerde o dilin
  // Noto yazı tipi yüklenir.
  final special = switch (lang) {
    'ar' => 'assets/pdf_fonts/NotoSansArabic-Regular.ttf',
    'zh' => 'assets/pdf_fonts/NotoSansSC-Regular.ttf',
    'ja' => 'assets/pdf_fonts/NotoSansJP-Regular.ttf',
    'ru' => 'assets/pdf_fonts/NotoSans-Regular.ttf',
    'hi' => 'assets/pdf_fonts/NotoSansDevanagari-Regular.ttf',
    'ko' => 'assets/pdf_fonts/NotoSansKR-Regular.ttf',
    _ => null,
  };
  await load('PlusJakartaSans', [
    if (special != null)
      special
    else
      for (final w in ['400Regular', '500Medium', '600SemiBold', '700Bold', '800ExtraBold'])
        'assets/fonts/PlusJakartaSans_$w.ttf',
  ]);
  // Not sistemi ekranındaki ülke adları için yedek yazı tipleri.
  await load('FbArabic', ['assets/pdf_fonts/NotoSansArabic-Regular.ttf']);
  await load('FbNoto', ['assets/pdf_fonts/NotoSans-Regular.ttf']);
  await load('FbSC', ['assets/pdf_fonts/NotoSansSC-Regular.ttf']);
  await load('FbJP', ['assets/pdf_fonts/NotoSansJP-Regular.ttf']);
  await load('FbKR', ['assets/pdf_fonts/NotoSansKR-Regular.ttf']);
  await load('FbHI', ['assets/pdf_fonts/NotoSansDevanagari-Regular.ttf']);
  await load('ReportSerif', ['assets/pdf_fonts/LiberationSerif-Regular.ttf', 'assets/pdf_fonts/LiberationSerif-Bold.ttf']);
  await load('MaterialIcons', [
    '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/sdk/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
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
  testWidgets('kılavuz görüntüleri', timeout: const Timeout(Duration(minutes: 20)), (tester) async {
    debugDisableShadows = false;
    const lang = String.fromEnvironment('KILAVUZ_DIL', defaultValue: 'tr');
    await tester.runAsync(() => _fonts(lang));
    L10n.use(lang);
    final store = AppStore();
    final dir = Directory.systemTemp.createTempSync('kilavuz');
    await tester.runAsync(() => store.load(dir: dir));
    store.onboardingDone = true;
    store.ratePrompted = true;
    final bank = BankStore.instance;
    await tester.runAsync(() async {
      await bank.load(dir: dir);
      await seedGuideBank(bank, lang);
    });

    const size = Size(360, 760);
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 72, bottom: 48);
    tester.view.viewPadding = tester.view.padding;
    final out = Directory('build/kilavuz/$lang/frames')..createSync(recursive: true);
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
              theme: _withFallback(NTheme.light()),
              darkTheme: _withFallback(NTheme.dark()),
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
    await scene('01_tanitim', const OnboardingScreen(), () => {'devam': find.textContaining(tr('Devam')).first});
    await scene('02_ana', const HomeScreen(), () => {
          'tema': tip(tr('Gece moduna geç')),
          'yeni': tip(tr('Yeni sınav')),
          'okut': find.text(tr('Okut')).first,
          'ornek': find.text(tr('Örnekleri sil')).first,
        });
    await scene('03_menu', const HomeScreen(), () => {
          'ana': text(tr('Ana sayfa')),
          'siniflar': text(tr('Sınıflar')),
          'kutuphane': text(tr('Kütüphane')),
          'profil': text(tr('Profil')),
          'ayarlar': text(tr('Ayarlar')),
        });
    await scene('04_siniflar', const Scaffold(body: StudentsScreen(embedded: true)), () => {
          'aktar': find.text(tr('Excel / PDF aktar')).first,
          'ekle': find.text(tr('Öğrenci ekle')).first,
        });
    await scene('05_profil', const Scaffold(body: ProfileScreen()), () => {'kurum': find.text(tr('Kurum bilgileri')).first},
        then: () => scrollTo(find.text(tr('Kurum bilgileri')).first));
    // Türkçede resmî başlık sırası, diğer dillerde o ülkenin biçimi.
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
    await scene('06_kurum', const SchoolScreen(), () => {
          if (lang == 'tr') ...{
            'il': find.text('Ankara').first,
            'ad': find.text(tr('Okul adı')).first,
            'baslik': find.text('ANKARA VALİLİĞİ').first,
          } else ...{
            'il': find.text(tr('Kurum türü')).first,
            'ad': find.text(_schoolName[lang] ?? '').first,
          },
        }, then: () async {
          if (lang == 'tr') await tester.drag(find.byType(Scrollable).first, const Offset(0, -330));
        });

    // 2. Sınav hazırlama
    await scene('07_yeni_sinav', const NewExamScreen(), () => {
          'soru': find.byType(NumberStepper).first,
          'kaydet': find.text(tr('Sınavı kaydet')).first,
        });
    await scene('08_sinav_ayar', const ExamSettingsScreen(examId: 'demo_exam'), () => {
          'tam': find.text(tr('Tam puan')).first,
          'yanlis': find.text(tr('Yanlış götürme')).first,
          'form': find.text(tr('Netice formu (önerilen)')).first,
        }, then: () async => tester.drag(find.byType(Scrollable).first, const Offset(0, -200)));

    // 3. Form yazdırma
    await scene('09_form_yazdir', const ExamScreen(examId: 'demo_exam'), () => {'form': find.text(tr('Form yazdır')).last},
        then: () async => tester.tap(find.byIcon(Icons.more_vert).first));
    await scene('10_sablon', const SettingsScreen(), () => {'sablon': find.text(tr('Başka firma formları')).first},
        then: () => scrollTo(find.text(tr('Başka firma formları')).first));

    // 4. Kâğıt okutma
    await scene('11_okut', const ExamScreen(examId: 'demo_exam'), () => {'okut': find.byType(FloatingActionButton).first});
    await scene('12_okut_ekrani', const ScanScreen(examId: 'demo_exam'), () => {
          'sec': find.byType(FilledButton).first,
          'ornek': find.text(tr('Örnek form')).first,
        });

    // 5. Sonuçlar ve raporlar
    await scene('13_sonuclar', const ExamScreen(examId: 'demo_exam'), () => {
          'sekme': find.text(tr('Sonuçlar')).first,
          'ogrenci': find.byType(ListTile).last,
        }, then: () => scrollTo(find.text(tr('Öğrenciler')).first, center: 260));
    await scene('14_detay', const ExamScreen(examId: 'demo_exam'), () => {
          'gecmis': find.text(tr('Öğrenci geçmişi ve gelişimi')).first,
          'karne': find.text(tr('Karneyi veliye gönder')).first,
          'sil': find.text(tr('Bu okumayı sil')).first,
        }, then: () async {
          await scrollTo(find.text(tr('Öğrenciler')).first, center: 260);
          await tester.tap(find.byType(ListTile).at(2));
        });
    await scene('15_analiz', const ExamScreen(examId: 'demo_exam'), () => {
          'sekme': find.text(tr('Analiz')).first,
          'rapor': find.text(tr('Sınav raporu')).first,
          'karne': find.text(tr('Öğrenci karnesi')).first,
        }, then: () async => tester.tap(find.descendant(of: find.byType(TabBar), matching: find.text(tr('Analiz')))));
    await scene('16_ogrenci', const StudentDetailScreen(studentId: 'demo_5'), () => {
          'uyari': find.textContaining(tr('Destek gerekebilir')).first,
        });
    await scene('17_donem', const TermScreen(), () => {
          'sec': find.byType(Checkbox).first,
          'olustur': find.byType(FilledButton).first,
        });

    // 7. Soru bankası ve kitapçık
    final d = guideBankData(lang);
    Finder fab() => find.byType(FloatingActionButton).first;
    await scene('24_kutuphane', const LibraryScreen(), () => {
          'sekme': find.text(tr('Sorular')).first,
          'ara': find.text(tr('Soru, konu, etiket ara')).first,
          'zorluk': find.textContaining(tr('Kolay')).first,
          'ekle': fab(),
        });
    await scene('25_soru_ekle', const LibraryScreen(), () => {
          'yaz': text(tr('Soru yaz')),
          'kes': text(tr('PDF ya da fotoğraftan kes')),
          'excel': text(tr("Excel'den aktar")),
        }, then: () async => tester.tap(fab()));
    final page = DocPage(guidePage(d), 900, 1270);
    await scene('26_kes', CropImportScreen(pages: [page]), () => {
          'secim': find.byType(RectSelector).first,
          'cevap': text(tr('Doğru cevap')),
          'ekle': text(tr('Soru olarak ekle')),
        }, then: () async {
          // Sayfa görüntüsünün çözülmesini bekle.
          for (var i = 0; i < 5; i++) {
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
            await settle();
          }
          final r = tester.getRect(find.descendant(of: find.byType(RectSelector).first, matching: find.byType(Image)).first);
          // Sayfanın üstündeki ilk soruyu seç.
          final from = Offset(r.left + r.width * 0.03, r.top + r.height * 0.075);
          final to = Offset(r.left + r.width * 0.96, r.top + r.height * 0.34);
          final g = await tester.startGesture(from);
          for (var i = 1; i <= 8; i++) {
            await g.moveTo(Offset.lerp(from, to, i / 8)!);
            await tester.pump(const Duration(milliseconds: 16));
          }
          await g.up();
          await settle();
          final c = find.text('C');
          if (c.evaluate().isNotEmpty) await tester.tap(c.last);
        });
    await scene('27_soru_yaz', QuestionEditorScreen(question: bank.questionById('bq3')), () => {
          'tur': text(tr('Çoktan seçmeli')),
          'gorsel': text(tr('Görsel ekle')),
          'siklar': text(tr('Şıklar')),
          'kaydet': find.text(tr('Kaydet')).last,
        });
    await scene('28_soru_zorluk', QuestionEditorScreen(question: bank.questionById('bq3')), () => {
          'zorluk': text(tr('Orta')),
          'konu': text(tr('Ders ve konu')),
        }, then: () => scrollTo(find.text(tr('Zorluk')).first, center: 200));
    await scene('29_notlar', const LibraryScreen(initialTab: 1), () => {
          'tur': find.byType(ChoiceChip).at(1),
          'kart': find.text((d['notlar'] as List)[2][2] as String).first,
          'foy': tip(tr('Listedekilerden çalışma föyü (PDF)')),
          'ekle': fab(),
        });
    await scene('30_not', const NoteViewScreen(noteId: 'n3'), () => {
          'pdf': tip(tr('PDF olarak yazdır / paylaş')),
          'duzenle': tip(tr('Düzenle')),
          'uret': find.text(tr('Bu nottan soru üret')).first,
        });
    await scene('31_kitapciklar', const LibraryScreen(initialTab: 2), () => {
          'kart': find.text((d['kitapcik'] as List)[0] as String).first,
          'yeni': fab(),
        });
    await scene('32_sihirbaz', BookletWizardScreen(booklet: bank.bookletById('k1')), () => {
          'adim': find.text(tr('Görünüm')).first,
          'banka': text(tr('Bankadan seç')),
          'otomatik': text(tr('Otomatik seç')),
          'diz': text(tr('Konuya göre diz')),
        });
    await scene('33_otomatik', const Scaffold(body: AutoPickSheet(used: {})), () => {
          'sayi': text(tr('Soru sayısı')),
          'konular': text(tr('Konular (boşsa hepsi)')),
          'sec': find.byType(FilledButton).last,
        });
    await scene('34_kitapcik_turu', BookletWizardScreen(booklet: bank.bookletById('k1')), () => {
          'sayi': text(tr('Kitapçık sayısı')),
          'karistir': text(tr('Şıkları karıştır')),
          'ileri': text(tr('İleri')),
        }, then: () async {
          for (var i = 0; i < 2; i++) {
            await tester.tap(find.text(tr('İleri')).last);
            await settle();
          }
        });
    await scene('35_banka_analiz', const LibraryScreen(initialTab: 3), () => {
          'zorluk': text(tr('Zorluk dağılımı')),
          'kapsam': text(tr('Konu kapsamı')),
        });

    // Nottan soru üretme (öneriler hazır gösterilir; internet gerekmez).
    final drafts = [for (final id in ['bq5', 'bq6', 'bq7']) bank.questionById(id)].whereType<BankQuestion>().toList();
    await scene('36_yz_soru', AiQuestionsScreen(noteId: 'n3', initialDrafts: drafts), () => {
          'sayi': text(tr('Soru sayısı')),
          'tur': text(tr('Soru türleri')),
          'zorluk': text(tr('Zorluk')),
        });
    await scene('37_yz_oneri', AiQuestionsScreen(noteId: 'n3', initialDrafts: drafts), () => {
          'cocuk': text(tr('Çocuklar için (ilkokul)')),
          'uret': find.byType(FilledButton).first,
          'oneri': text(tr('Öneriler')),
        }, then: () => scrollTo(find.text(tr('Çocuklar için (ilkokul)')).first, center: 150));
    await scene('38_cocuk', BookletWizardScreen(booklet: bank.bookletById('k1')), () => {
          'sablon': text(tr('Çocuk / İlkokul')),
          'aciklama': find.textContaining(tr('Cevaplar ilk sayfanın köşesindeki küçük kutudan telefonla okunur. İsimli cevap kartlarını sınav ekranındaki "Form yazdır" ile basabilirsiniz.').split(' ').take(4).join(' ')).first,
        }, then: () async {
          await tester.tap(find.text(tr('İleri')).last);
          await settle();
          await tester.tap(find.text(tr('Çocuk / İlkokul')).last);
        });

    // 8. Silme
    await scene('18_sec_sil', const HomeScreen(), () => {
          'sec': find.text(tr('Seç ve sil')).first,
        }, then: () async {
          for (var i = 0; i < 8 && find.text(tr('Seç ve sil')).evaluate().isEmpty; i++) {
            await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -250));
            await settle();
          }
          // ignore: avoid_print
          print('  seç ve sil: ${find.text(tr('Seç ve sil')).evaluate().length}, scrollables: ${find.byType(Scrollable).evaluate().length}');
          await scrollTo(find.text(tr('Seç ve sil')).first, center: 300);
        });
    await scene('19_secildi', const HomeScreen(), () => {
          'kart': find.byIcon(Icons.check_rounded).first,
          'tumu': find.text(tr('Tümünü seç')).first,
          'sil': tip(tr('Seçilenleri sil')),
          'vazgec': tip(tr('Vazgeç')),
        }, then: () async {
          for (var i = 0; i < 8 && find.text(tr('Seç ve sil')).evaluate().isEmpty; i++) {
            await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -250));
            await settle();
          }
          await scrollTo(find.text(tr('Seç ve sil')).first, center: 300);
          await tester.tap(find.text(tr('Seç ve sil')).first);
          await settle();
          await tester.tap(find.text(tr('Fizik Quiz 1 (örnek)')).first);
        });

    // 9. Ayarlar ve verileriniz
    await scene('20_gorunum', const SettingsScreen(), () => {
          'dil': find.text(tr('Uygulama dili')).first,
          'otomatik': find.text(tr('Otomatik')).first,
          'gunduz': find.text(tr('Gündüz')).first,
          'gece': find.text(tr('Gece')).first,
        });
    store.themeMode = 'dark';
    await scene('21_gece', const HomeScreen(), () => {'tema': tip(tr('Gündüz moduna geç'))});
    store.themeMode = 'light';
    await scene('22_yedek', const SettingsScreen(), () => {
          'kaydet': find.text(tr('Yedeği dosyaya kaydet')).first,
          'yukle': find.text(tr('Yedekten geri yükle')).first,
        }, then: () => scrollTo(find.text(tr('Yedeği dosyaya kaydet')).first));
    await scene('39_not_sistemi', const GradeScaleScreen(), () => {
          'kendim': text(tr('Kendim yazacağım')),
          'duzey': text(tr('Düzeyler')),
          'kaydet': find.text(tr('Kaydet')).last,
        }, then: () => scrollTo(find.text(tr('Kendim yazacağım')).first, center: 260));
    await scene('23_yardim', const HelpScreen(), () => {
          'kilavuz': find.text(tr('Kılavuz')).first,
          'sss': find.textContaining(tr('Sık sorulanlar')).first,
        });

    // 10. Netice Pro
    // Netice Pro ekranı: kampanyasız bir gün, deneme bitmiş.
    Campaign.debugNow = DateTime(2026, 10, 15);
    AppStore.proFreeOnThisPlatform = false;
    store.trialStart = DateTime.now().subtract(const Duration(days: 40));
    await tester.runAsync(() => ProService.instance.attach(store));
    Finder plan(String s) => find.ancestor(of: find.text(s), matching: find.byType(InkWell)).first;
    await scene('40_pro', const ProScreen(), () => {
          'pro': plan(tr('Pro · yıllık')),
          'yz': plan(tr('Pro + Yapay Zekâ · yıllık')),
          'donem': plan(tr('Sınav dönemi paketi')),
        }, then: () => scrollTo(find.text(tr('Pro · yıllık')).first, center: 220));
    await scene('41_pro_alt', const ProScreen(), () => {
          'ekpaket': find.textContaining(tr('Ek soru paketi · {0} soru', [200])).first,
          'okul': text(tr('Okul / zümre paketi')),
        }, then: () => scrollTo(find.text(tr('Okul / zümre paketi')).first, center: 420));
    await scene('42_okul', const SchoolOfferScreen(), () => {
          'fiyat': find.byType(Card).first,
          'sayi': find.byType(Slider).first,
          'teklif': find.byType(FilledButton).last,
        });

    File('${out.path}/hedefler.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(targets));
    // Ağacı test bitmeden kaldır; kapanıştaki yeniden yerleşim sahte taşma uyarısı vermesin.
    await tester.pumpWidget(const SizedBox());
    debugDisableShadows = true;
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
