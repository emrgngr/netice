// Kurum başlığı önizlemeleri: flutter test tool/letterhead_preview_test.dart
// build/letterhead/ altına Kurum bilgileri ekranı görüntüleri ve her kurum
// türü için sınav raporu PDF'i yazar.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/store.dart';
import 'package:netice/main.dart';
import 'package:netice/reports/pdf_documents.dart';
import 'package:netice/ui/school_screen.dart';
import 'package:netice/ui/theme.dart';

Future<void> _fonts() async {
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await l.load();
  }

  await load('PlusJakartaSans',
      [for (final w in ['400Regular', '500Medium', '600SemiBold', '700Bold', '800ExtraBold']) 'assets/fonts/PlusJakartaSans_$w.ttf']);
  await load('ReportSerif', ['assets/pdf_fonts/LiberationSerif-Regular.ttf', 'assets/pdf_fonts/LiberationSerif-Bold.ttf']);
  await load('MaterialIcons',
      ['${Platform.environment['FLUTTER_ROOT'] ?? '/opt/sdk/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
}

const _base = SchoolInfo(
    principal: 'Ayşe Demir', teacher: 'Emine Yılmaz', subject: 'Matematik', fontFamily: 'times', headerSize: 12, turkishFormat: true);

final configs = <String, SchoolInfo>{
  '1_okul_il_merkezi': SchoolInfo.fromJson({
    ..._base.toJson(),
    'province': 'Ankara',
    'district': 'Merkez',
    'name': 'Atatürk Anadolu Lisesi',
  }),
  '2_okul_ilce': SchoolInfo.fromJson({
    ..._base.toJson(),
    'province': 'Ankara',
    'district': 'Çankaya',
    'name': 'Atatürk Anadolu Lisesi',
  }),
  '3_pomem': SchoolInfo.fromJson({
    ..._base.toJson(),
    'type': 'police',
    'parent': 'Polis Akademisi Başkanlığı',
    'name': 'Ankara Polis Meslek Eğitim Merkezi Müdürlüğü',
    'principal': 'Emniyet Müdürü Ali Kaya',
  }),
  '4_harp_okulu': SchoolInfo.fromJson({
    ..._base.toJson(),
    'type': 'military',
    'parent': 'Millî Savunma Üniversitesi Rektörlüğü',
    'name': 'Kara Harp Okulu Dekanlığı',
    'principal': 'Tuğgeneral Mehmet Aydın',
  }),
  '5_universite': SchoolInfo.fromJson({
    ..._base.toJson(),
    'type': 'university',
    'parent': 'Hacettepe Üniversitesi Rektörlüğü',
    'units': ['Edebiyat Fakültesi Dekanlığı'],
    'name': 'Tarih Bölüm Başkanlığı',
    'principal': 'Prof. Dr. Zeynep Er',
  }),
  '6_il_emniyet': SchoolInfo.fromJson({
    ..._base.toJson(),
    'type': 'police',
    'province': 'Erzurum',
    'localHeader': true,
    'localUnit': 'Emniyet Müdürlüğü',
    'name': 'Eğitim Şube Müdürlüğü',
  }),
};

void main() {
  testWidgets('kurum başlıkları', (tester) async {
    debugDisableShadows = false;
    await tester.runAsync(_fonts);
    final store = AppStore();
    await tester.runAsync(() => store.load(dir: Directory.systemTemp.createTempSync('lh')));
    store.onboardingDone = true;
    store.confirmPro('onizleme');
    final out = Directory('build/letterhead')..createSync(recursive: true);
    final exam = store.exams.first;
    for (final e in configs.entries) {
      final bytes = await tester.runAsync(() => buildResultsPdf(
          exam: exam, results: store.resultsOf(exam), students: store.studentById, school: e.value));
      File('${out.path}/${e.key}.pdf').writeAsBytesSync(bytes!);
    }
    for (final k in ['1_okul_il_merkezi', '3_pomem']) {
      store.school = configs[k]!;
      tester.view.physicalSize = const Size(390, 1900) * 2;
      tester.view.devicePixelRatio = 2;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(RepaintBoundary(
          key: const ValueKey('shot'),
          child: StoreScope(
              store: store,
              child: MaterialApp(debugShowCheckedModeBanner: false, theme: NTheme.light(), home: const SchoolScreen()))));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
        final img = await b.toImage(pixelRatio: 2);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        File('${out.path}/ekran_$k.png').writeAsBytesSync(data!.buffer.asUint8List());
      });
    }
    debugDisableShadows = true;
  });
}
