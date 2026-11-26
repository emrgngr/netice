// Slider reklam önizlemesi: flutter test tool/ads_slider_preview_test.dart
// Görüntüler build/screenshots/slider_*.png olarak yazılır.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/ads.dart';
import 'package:netice/core/store.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/ad_admin_screen.dart';
import 'package:netice/ui/ad_slot.dart';
import 'package:netice/ui/theme.dart';

import 'screenshots_test.dart' show loadFonts, shot;

Widget _themed(AppStore store, Widget home) => StoreScope(
      store: store,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: NTheme.light(), home: home),
    );

void main() {
  testWidgets('slider önizlemesi', (tester) async {
    debugDisableShadows = false;
    AdSlot.debugNoVideo = true;
    await tester.runAsync(loadFonts);
    final store = AppStore();
    await tester.runAsync(() => store.load(dir: Directory.systemTemp.createTempSync('slider')));
    store.onboardingDone = true;
    store.ratePrompted = true;

    final files = [for (var i = 1; i <= 3; i++) File('test/fixtures/ads/slider$i.jpg')];
    await tester.runAsync(() async {
      for (final f in [...files, File('test/fixtures/ads/serit.jpg')]) {
        final done = Completer<void>();
        FileImage(f).resolve(ImageConfiguration.empty).addListener(
            ImageStreamListener((_, _) => done.complete(), onError: (e, _) => done.completeError(e)));
        await done.future;
      }
    });

    // 1) Beş geçiş çeşidi, geçişin ortasında.
    final gallery = _themed(
      store,
      Scaffold(
        appBar: AppBar(title: const Text('5 slider çeşidi (3 sn)')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          for (final st in SlideStyle.values) ...[
            Text('${st.label} · ${st.detail}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(aspectRatio: 16 / 9, child: AdSlider.files(files, style: st, seconds: 3)),
            ),
            const SizedBox(height: 16),
          ],
        ]),
      ),
    );
    await shot(tester, gallery, const Size(390, 1250), 'slider_1_bes_cesit');
    // Geçişin tam ortası (3. saniyeden 0,3 sn sonra).
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() async {
      final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
      final img = await b.toImage(pixelRatio: 2);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      File('build/screenshots/slider_1_bes_cesit_gecis.png').writeAsBytesSync(data!.buffer.asUint8List());
    });

    // 2) Ana sayfada slider kart reklam.
    const urls = [
      'https://raw.githubusercontent.com/emrgngr/netice/reklamlar/reklam/medya/s1.jpg',
      'https://raw.githubusercontent.com/emrgngr/netice/reklamlar/reklam/medya/s2.jpg',
      'https://raw.githubusercontent.com/emrgngr/netice/reklamlar/reklam/medya/s3.jpg',
    ];
    const serit = 'https://raw.githubusercontent.com/emrgngr/netice/reklamlar/reklam/medya/serit.jpg';
    AdService.instance.debugSet([
      Ad(id: 's', name: 'Mağaza slider', type: AdType.slider, media: urls.first, slides: urls, style: SlideStyle.slide, seconds: 3),
      const Ad(id: 'b', name: 'Şerit', type: AdType.image, media: serit, format: AdFormat.banner),
    ], {
      for (var i = 0; i < 3; i++) urls[i]: files[i],
      serit: File('test/fixtures/ads/serit.jpg'),
    });
    await shot(tester, NeticeApp(store: store, splash: false), const Size(390, 1500), 'slider_2_ana_sayfa');

    // 3) Reklam ekleme ekranında slider.
    await shot(
        tester,
        _themed(
            store,
            AdEditScreen(
                ad: Ad(
                    id: 'yeni',
                    name: 'Kış kampanyası',
                    type: AdType.slider,
                    media: files.first.path,
                    slides: [for (final f in files) f.path],
                    style: SlideStyle.flip,
                    seconds: 3,
                    link: 'https://www.sepetmix.com/'))),
        const Size(390, 1700),
        'slider_3_reklam_ekle');

    await tester.pumpWidget(const SizedBox());
    AdService.instance.debugSet(const [], const {});
    debugDisableShadows = true;
  });
}
