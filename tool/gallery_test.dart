// Çizim galerisi: flutter test tool/gallery_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/ui/illustrations.dart';
import 'package:netice/ui/theme.dart';

import 'screenshots_test.dart' show loadFonts, shot;

void main() {
  testWidgets('çizim galerisi', (tester) async {
    debugDisableShadows = false;
    await tester.runAsync(loadFonts);
    Widget grid(bool dark) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? NTheme.dark() : NTheme.light(),
          home: Scaffold(
            backgroundColor: dark ? NColors.ink : NColors.ivory,
            body: Wrap(children: [
              for (final k in IllustrationKind.values)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(children: [
                    Illustration(kind: k, size: 170, onDark: dark),
                    Text(k.name, style: TextStyle(color: dark ? Colors.white : NColors.ink)),
                  ]),
                ),
            ]),
          ),
        );
    await shot(tester, grid(false), const Size(940, 420), 'cizimler_acik');
    await shot(tester, grid(true), const Size(940, 420), 'cizimler_koyu');
    debugDisableShadows = true;
  });
}
