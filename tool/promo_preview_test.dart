// Öneri kartı önizlemesi: flutter test tool/promo_preview_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/promo.dart';
import 'package:netice/core/store.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/promo_card.dart';
import 'package:netice/ui/theme.dart';

import 'screenshots_test.dart' show loadFonts, shot;

void main() {
  testWidgets('öneri kartı', (tester) async {
    await tester.runAsync(loadFonts);
    final store = AppStore();
    final feed = PromoFeed.fromJson(jsonDecode(File('promo/oneriler.json').readAsStringSync()) as Map<String, dynamic>);
    for (final (name, f) in [('oneri_karti_urun', feed), ('oneri_karti_magaza', PromoFeed.fallback)]) {
      PromoService.instance.feed = f;
      await shot(
          tester,
          StoreScope(
            store: store,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: NTheme.light(),
              home: const Scaffold(body: Padding(padding: EdgeInsets.all(16), child: Align(alignment: Alignment.topCenter, child: PromoCard()))),
            ),
          ),
          Size(390, name.endsWith('urun') ? 300 : 190),
          name);
    }
  });
}
