// Not sistemi ekran görüntüleri: flutter test tool/grade_scale_preview_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/grade_scale.dart';
import 'package:netice/core/store.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/grade_scale_screen.dart';
import 'package:netice/ui/theme.dart';

import 'screenshots_test.dart' show loadFonts, shot;

Widget _themed(Widget home, AppStore store) => StoreScope(
      store: store,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: NTheme.light(), home: home),
    );

void main() {
  testWidgets('not sistemi', (tester) async {
    debugDisableShadows = false;
    await tester.runAsync(loadFonts);
    final store = AppStore();
    final dir = Directory.systemTemp.createTempSync('gradeshots');
    await tester.runAsync(() => store.load(dir: dir));
    const phone = Size(390, 1500);
    await shot(tester, _themed(const GradeScaleScreen(), store), phone, 'not_1_varsayilan');
    store.setGradeScale(GradeScale.presets.firstWhere((p) => p.id == 'de'));
    await shot(tester, _themed(const GradeScaleScreen(), store), phone, 'not_2_almanya');
    store.setGradeScale(null);
    debugDisableShadows = true;
  });
}
