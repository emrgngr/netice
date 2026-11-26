// Okuma onayı önizlemesi: tarama ekranı üstünde yeşil parlama kareleri.
//   flutter test tool/okuma_onizleme_test.dart
// Kareler build/okuma/kare_XX.png; ffmpeg ile okundu.mp3 sesiyle videoya çevrilir.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/store.dart';
import 'package:netice/l10n/l10n.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/scan_feedback.dart';
import 'package:netice/ui/scan_screen.dart';
import 'package:netice/ui/theme.dart';

import 'screenshots_test.dart' show loadFonts;

void main() {
  testWidgets('okuma onayı', (tester) async {
    await tester.runAsync(loadFonts);
    L10n.use('tr');
    final store = AppStore();
    await tester.runAsync(() => store.load(dir: Directory.systemTemp.createTempSync('okuma')));
    store.onboardingDone = true;
    final pulse = ValueNotifier<int>(0);
    tester.view.physicalSize = const Size(390, 844) * 2;
    tester.view.devicePixelRatio = 2;
    await tester.pumpWidget(RepaintBoundary(
      key: const ValueKey('k'),
      child: StoreScope(
        store: store,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: NTheme.light(),
          home: SuccessFlash(pulse: pulse, child: const ScanScreen(examId: 'demo_exam')),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    Directory('build/okuma').createSync(recursive: true);
    Future<void> kare(int i) async {
      await tester.runAsync(() async {
        final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('k')));
        final img = await b.toImage(pixelRatio: 2);
        final d = await img.toByteData(format: ui.ImageByteFormat.png);
        File('build/okuma/kare_${i.toString().padLeft(2, '0')}.png').writeAsBytesSync(d!.buffer.asUint8List());
      });
    }

    var i = 0;
    for (; i < 6; i++) {
      await kare(i);
    }
    pulse.value++;
    await tester.pump();
    for (var t = 0; t < 22; t++, i++) {
      await kare(i);
      await tester.pump(const Duration(milliseconds: 40));
    }
    for (var t = 0; t < 8; t++, i++) {
      await kare(i);
    }
  });
}
