// Yayınevi formunda daireleri otomatik bulma önizlemesi:
// flutter test tool/sablon_otomatik_preview_test.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/store.dart';
import 'package:netice/main.dart';
import 'package:netice/omr/form_layout.dart' show Pt;
import 'package:netice/omr/grid_detect.dart';
import 'package:netice/omr/template.dart';
import 'package:netice/ui/template_screen.dart';
import 'package:netice/ui/theme.dart';

import '../test/grid_detect_test.dart' show FakeForm, photo;
import 'screenshots_test.dart' show loadFonts, shot;

void main() {
  testWidgets('otomatik şablon ekranı', (tester) async {
    await tester.runAsync(loadFonts);
    final store = AppStore();
    await tester.runAsync(() => store.load(dir: Directory.systemTemp.createTempSync('tpl')));
    final form = FakeForm();
    final rnd = math.Random(5);
    final key = {for (var q = 0; q < form.questions; q++) if (q % 9 != 4) q: rnd.nextInt(5)};
    final page = form.render(marks: key, number: '0000004217', bookletMark: 1);
    final im = photo(page, [Pt(210, 150), Pt(1300, 210), Pt(1350, 1830), Pt(160, 1770)], blur: 1);
    final bytes = Uint8List.fromList(img.encodeJpg(im, quality: 85));
    final prep = prepareTemplatePhoto((bytes, 297 / 210))!;
    final d = detectFormGrids(prep.$1, prep.$2);
    final t = d.applyTo(const FormTemplate(id: 'onizleme', name: 'Yayınevi deneme formu'));
    final test = TemplateReader(t, questionCount: t.questionCount, choiceCount: 5).read(prep.$1, corners: prep.$2);
    for (final (name, size) in [('sablon_otomatik_mobil', const Size(390, 844)), ('sablon_otomatik_masaustu', const Size(1366, 900))]) {
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
