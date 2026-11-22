// Başka firma formu şablon ekranı önizlemesi: flutter test tool/template_preview_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/store.dart';
import 'package:netice/main.dart';
import 'package:netice/omr/template.dart';
import 'package:netice/ui/template_screen.dart';
import 'package:netice/ui/theme.dart';

import '../test/template_test.dart' show template, renderPage, photo;
import 'screenshots_test.dart' show loadFonts, shot;
import 'package:netice/omr/form_layout.dart' show Pt;

void main() {
  testWidgets('şablon ekranı', (tester) async {
    await tester.runAsync(loadFonts);
    final store = AppStore();
    await tester.runAsync(() => store.load(dir: Directory.systemTemp.createTempSync('tpl')));
    final page = renderPage({for (var q = 0; q < 40; q++) if (q % 7 != 3) q: (q * 3) % 5}, '004217');
    final im = photo(page, [Pt(230, 160), Pt(1290, 230), Pt(1360, 1840), Pt(150, 1760)], blur: 1);
    final bytes = Uint8List.fromList(img.encodeJpg(im, quality: 85));
    final prep = prepareTemplatePhoto((bytes, template.aspect))!;
    final test = TemplateReader(template, questionCount: 40, choiceCount: 5).read(prep.$1, corners: prep.$2);
    File('build/screenshots/sablon_fotograf.jpg')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    final t = template.copyWith(name: 'X Yayınları 40 soruluk');
    for (final (name, size) in [('sablon_mobil', const Size(390, 844)), ('sablon_masaustu', const Size(1366, 860))]) {
      await shot(
          tester,
          StoreScope(
            store: store,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: NTheme.light(),
              home: TemplateEditorScreen(template: t, preview: prep, previewTest: test),
            ),
          ),
          size,
          name);
    }
  });
}
