// Bölüm simgelerini (lib/ui/section_icons.dart) PNG olarak dışa aktarır:
// videolar, kılavuz ve web sitesi aynı seti kullanır.
//   flutter test tool/bolum_simgeleri_test.dart
// Çıktılar build/bolum-simgeleri/<bolum>.png (512 px, şeffaf zemin)
// ve tumu_gunduz.png / tumu_gece.png (adlarıyla bir arada).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/l10n/l10n.dart';
import 'package:netice/ui/section_icons.dart';
import 'package:netice/ui/theme.dart';

import 'screenshots_test.dart' show loadFonts;

Future<void> _save(WidgetTester tester, Widget w, Size size, String path, {double ratio = 2}) async {
  tester.view.physicalSize = size * ratio;
  tester.view.devicePixelRatio = ratio;
  await tester.pumpWidget(Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: RepaintBoundary(key: const ValueKey('s'), child: w)),
  ));
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('s')));
    final img = await b.toImage(pixelRatio: ratio);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    File(path).writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('bölüm simgeleri', (tester) async {
    debugDisableShadows = false;
    await tester.runAsync(loadFonts);
    L10n.use('tr');
    Directory('build/bolum-simgeleri').createSync(recursive: true);
    for (final s in Section.values) {
      // Gölge sığsın diye simgenin çevresinde boşluk bırakılır.
      await _save(tester, Padding(padding: const EdgeInsets.all(16), child: SectionIcon(s, size: 224)),
          const Size(256, 256), 'build/bolum-simgeleri/${s.name}.png');
    }
    for (final dark in [false, true]) {
      final theme = dark ? NTheme.dark() : NTheme.light();
      await _save(
        tester,
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(32),
              child: Wrap(spacing: 18, runSpacing: 26, children: [
                for (final s in Section.values)
                  SizedBox(
                    width: 120,
                    child: Column(children: [
                      SectionIcon(s, size: 72),
                      const SizedBox(height: 10),
                      Text(s.label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      Text(s.name, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
                    ]),
                  ),
              ]),
            ),
          ),
        ),
        const Size(1140, 560),
        'build/bolum-simgeleri/tumu_${dark ? 'gece' : 'gunduz'}.png',
      );
    }
    debugDisableShadows = true;
  });
}
