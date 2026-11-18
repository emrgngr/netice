// Ekran görüntüsü üretir: flutter test tool/screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/store.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/exam_screen.dart';
import 'package:netice/ui/new_exam_screen.dart';
import 'package:netice/ui/student_detail_screen.dart';
import 'package:netice/ui/compare_screen.dart';
import 'package:netice/ui/school_screen.dart';
import 'package:netice/core/models.dart';
import 'package:netice/ui/exam_settings_screen.dart';
import 'package:netice/ui/theme.dart';

Future<void> loadFonts() async {
  final loader = FontLoader('PlusJakartaSans');
  for (final w in ['400Regular', '500Medium', '600SemiBold', '700Bold', '800ExtraBold']) {
    loader.addFont(Future.value(ByteData.sublistView(File('assets/fonts/PlusJakartaSans_$w.ttf').readAsBytesSync())));
  }
  await loader.load();
  final icons = FontLoader('MaterialIcons');
  final iconFile = File('${Platform.environment['FLUTTER_ROOT'] ?? '/opt/sdk/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (iconFile.existsSync()) {
    icons.addFont(Future.value(ByteData.sublistView(iconFile.readAsBytesSync())));
    await icons.load();
  }
}

Future<void> shot(WidgetTester tester, Widget app, Size size, String name, {Future<void> Function()? then}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  // Android'in alt gezinme çubuğu gibi bir sistem boşluğu.
  tester.view.padding = size.width < 600 ? const FakeViewPadding(top: 48, bottom: 96) : FakeViewPadding.zero;
  tester.view.viewPadding = tester.view.padding;
  // Önceki ekrandan kalan açık pencereler (alt sayfa vb.) temizlensin.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(RepaintBoundary(key: const ValueKey('shot'), child: app));
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await tester.pumpAndSettle();
  if (then != null) {
    await then();
    await tester.pumpAndSettle();
  }
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/screenshots').createSync(recursive: true);
    File('build/screenshots/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('ekran görüntüleri', (tester) async {
    debugDisableShadows = false;
    await tester.runAsync(loadFonts);
    final store = AppStore();
    await tester.runAsync(() => store.load(dir: Directory.systemTemp.createTempSync('shots')));
    final app = NeticeApp(store: store);

    await shot(tester, app, const Size(390, 844), 'mobil_ana_sayfa');
    await shot(tester, app, const Size(1366, 820), 'masaustu_pano');
    await shot(tester, StoreScope(store: store, child: _themed(const ExamScreen(examId: 'demo_exam'))), const Size(390, 844), 'mobil_sinav_sonuclari');
    await shot(tester, StoreScope(store: store, child: _themed(const ExamScreen(examId: 'demo_exam'))), const Size(1366, 820), 'masaustu_madde_analizi',
        then: () async => tester.tap(find.text('Analiz')));
    await shot(tester, StoreScope(store: store, child: _themed(const ExamScreen(examId: 'demo_exam'))), const Size(390, 3400), 'mobil_analiz',
        then: () async => tester.tap(find.text('Analiz')));
    await shot(tester, StoreScope(store: store, child: _themed(const NewExamScreen())), const Size(412, 915), 'mobil_yeni_sinav');
    await shot(tester, StoreScope(store: store, child: _themed(const StudentDetailScreen(studentId: 'demo_5'))),
        const Size(390, 1500), 'mobil_ogrenci_gecmisi');
    await shot(tester, StoreScope(store: store, child: _themed(const CompareScreen())), const Size(390, 1600),
        'mobil_sube_karsilastirmasi');
    await shot(tester, StoreScope(store: store, child: _themed(const ExamSettingsScreen(examId: 'demo_exam'))),
        const Size(390, 1100), 'mobil_sinav_ayarlari');
    await shot(tester, app, const Size(390, 1500), 'mobil_ana_sayfa_uzun');
    await shot(tester, app, const Size(412, 915), 'mobil_siniflar', then: () async => tester.tap(find.text('Sınıflar')));
    store.school = const SchoolInfo(
        province: 'Ankara',
        district: 'Çankaya',
        name: 'Atatürk Anadolu Lisesi',
        principal: 'Ayşe Demir',
        teacher: 'Emine Yılmaz',
        subject: 'Fizik');
    await shot(tester, StoreScope(store: store, child: _themed(const SchoolScreen())), const Size(390, 1500),
        'mobil_okul_bilgileri');
    await shot(tester, StoreScope(store: store, child: _themed(const ExamScreen(examId: 'demo_exam'))), const Size(390, 844),
        'mobil_form_yazdir', then: () async {
          await tester.tap(find.byIcon(Icons.more_vert).first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Form yazdır').last);
        });
    debugDisableShadows = true;
  });
}

Widget _themed(Widget home) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: NTheme.light(),
      home: home,
    );
