// Marka dosyaları: flutter test tool/brand_test.dart
// build/marka/ altına logo varyantları, açılış logosu ve mağaza kapak görseli üretir.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/ui/illustrations.dart';
import 'package:netice/ui/logo.dart';
import 'package:netice/ui/theme.dart';

import 'screenshots_test.dart' show loadFonts;

Future<void> render(WidgetTester tester, Widget w, Size size, String name, {double ratio = 2}) async {
  tester.view.physicalSize = size * ratio;
  tester.view.devicePixelRatio = ratio;
  tester.view.padding = FakeViewPadding.zero;
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: NTheme.light(),
    home: Material(
      type: MaterialType.transparency,
      child: Center(child: RepaintBoundary(key: const ValueKey('b'), child: SizedBox.fromSize(size: size, child: w))),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('b')));
    final img = await b.toImage(pixelRatio: ratio);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/marka').createSync(recursive: true);
    File('build/marka/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Widget lockup({required Color ink, Color? bg, double h = 120, bool slogan = false}) => Container(
      color: bg,
      alignment: Alignment.center,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        NeticeMark(size: h, ink: ink),
        SizedBox(width: h * 0.32),
        Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Netice',
              style: TextStyle(
                  fontFamily: 'PlusJakartaSans', fontSize: h * 0.78, height: 1, fontWeight: FontWeight.w800, letterSpacing: -2, color: ink)),
          if (slogan)
            Padding(
              padding: EdgeInsets.only(top: h * 0.08, left: 4),
              child: Text('Kâğıttan sonuca, saniyeler içinde.',
                  style: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: h * 0.17, fontWeight: FontWeight.w600, color: ink.withValues(alpha: 0.7))),
            ),
        ]),
      ]),
    );

void main() {
  testWidgets('marka dosyaları', (tester) async {
    debugDisableShadows = false;
    await tester.runAsync(loadFonts);

    await render(tester, lockup(ink: NColors.ink, bg: NColors.ivory, slogan: true), const Size(900, 300), 'netice_logo_yatay_acik');
    await render(tester, lockup(ink: Colors.white, bg: NColors.ink, slogan: true), const Size(900, 300), 'netice_logo_yatay_koyu');
    await render(tester, lockup(ink: NColors.ink), const Size(760, 220), 'netice_logo_yatay_seffaf');
    await render(tester, lockup(ink: Colors.white), const Size(760, 220), 'netice_logo_yatay_beyaz_seffaf');
    await render(tester, const Center(child: NeticeMark(size: 400, ink: NColors.ink)), const Size(512, 512), 'netice_isaret_lacivert');
    await render(tester, const Center(child: NeticeMark(size: 400, ink: Colors.white)), const Size(512, 512), 'netice_isaret_beyaz');
    await render(tester, const Center(child: NeticeMark(size: 400, ink: NColors.ink, outline: true)), const Size(512, 512),
        'netice_isaret_cizgi');
    // Dikey (kare) logo
    await render(
        tester,
        Container(
          decoration: const BoxDecoration(gradient: inkGradient),
          child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            NeticeMark(size: 220, ink: Colors.white),
            SizedBox(height: 36),
            Text('Netice',
                style: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 96, fontWeight: FontWeight.w800, letterSpacing: -2, color: Colors.white)),
            SizedBox(height: 8),
            Text('Kâğıttan sonuca, saniyeler içinde.',
                style: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 26, fontWeight: FontWeight.w600, color: Colors.white70)),
          ]),
        ),
        const Size(720, 720),
        'netice_logo_dikey_koyu');
    // Android açılış ekranı logosu (şeffaf, koyu zemin için)
    await render(tester, const Center(child: NeticeMark(size: 200, ink: Colors.white)), const Size(288, 288), 'splash_logo', ratio: 1);
    // Google Play kapak görseli 1024×500
    await render(
        tester,
        Container(
          decoration: const BoxDecoration(gradient: inkGradient),
          padding: const EdgeInsets.symmetric(horizontal: 64),
          child: Row(children: [
            const Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  NeticeMark(size: 64, ink: Colors.white),
                  SizedBox(width: 18),
                  Text('Netice',
                      style: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 56, fontWeight: FontWeight.w800, letterSpacing: -1.5, color: Colors.white)),
                ]),
                SizedBox(height: 28),
                Text('Optik kâğıtları telefonla okutun.',
                    style: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 34, height: 1.15, fontWeight: FontWeight.w800, color: Colors.white)),
                SizedBox(height: 6),
                Text('Puan, analiz ve karne saniyeler içinde.',
                    style: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 34, height: 1.15, fontWeight: FontWeight.w800, color: NColors.emerald)),
                SizedBox(height: 22),
                Text('İnternetsiz · KVKK uyumlu · e-Okul listesi',
                    style: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white70)),
              ]),
            ),
            const Illustration(kind: IllustrationKind.welcome, size: 380, onDark: true),
          ]),
        ),
        const Size(1024, 500),
        'google_play_kapak_1024x500',
        ratio: 1);
    debugDisableShadows = true;
  });
}
