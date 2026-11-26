import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/ui/swipe_back.dart';

Widget _app(TargetPlatform platform) => MaterialApp(
  theme: ThemeData(
    platform: platform,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: SwipeBackPageTransitionsBuilder(),
      TargetPlatform.iOS: SwipeBackPageTransitionsBuilder(),
    }),
  ),
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('İkinci')),
                body: Column(
                  children: [
                    const Expanded(child: Center(child: Text('Sayfa içeriği'))),
                    SizedBox(
                      height: 80,
                      child: ListView(
                        key: const Key('yatay'),
                        scrollDirection: Axis.horizontal,
                        children: [for (var i = 0; i < 30; i++) SizedBox(width: 80, child: Text('$i'))],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          child: const Text('Aç'),
        ),
      ),
    ),
  ),
);

Future<void> _open(WidgetTester t) async {
  await t.tap(find.text('Aç'));
  await t.pumpAndSettle();
  expect(find.text('İkinci'), findsOneWidget);
}

void main() {
  for (final p in [TargetPlatform.android, TargetPlatform.iOS]) {
    group(p.name, () {
      testWidgets('ekranın ortasından sağa kaydırınca önceki sayfaya döner', (t) async {
        await t.pumpWidget(_app(p));
        await _open(t);
        await t.dragFrom(t.getCenter(find.text('Sayfa içeriği')) - const Offset(100, 0), const Offset(400, 0));
        await t.pumpAndSettle();
        expect(find.text('İkinci'), findsNothing);
        expect(find.text('Aç'), findsOneWidget);
      });

      testWidgets('kısa ve yavaş kaydırmada sayfa yerine döner', (t) async {
        await t.pumpWidget(_app(p));
        await _open(t);
        final g = await t.startGesture(t.getCenter(find.text('Sayfa içeriği')));
        for (var i = 0; i < 6; i++) {
          await g.moveBy(const Offset(10, 0));
          await t.pump(const Duration(milliseconds: 100));
        }
        await g.up();
        await t.pumpAndSettle();
        expect(find.text('İkinci'), findsOneWidget);
      });

      testWidgets('sola kaydırmak bir şey yapmaz', (t) async {
        await t.pumpWidget(_app(p));
        await _open(t);
        await t.dragFrom(t.getCenter(find.text('Sayfa içeriği')), const Offset(-300, 0));
        await t.pumpAndSettle();
        expect(find.text('İkinci'), findsOneWidget);
      });

      testWidgets('yatay kayan listede kaydırma listeyi kaydırır, sayfayı kapatmaz', (t) async {
        await t.pumpWidget(_app(p));
        await _open(t);
        await t.drag(find.byKey(const Key('yatay')), const Offset(-400, 0));
        await t.pumpAndSettle();
        await t.drag(find.byKey(const Key('yatay')), const Offset(200, 0));
        await t.pumpAndSettle();
        expect(find.text('İkinci'), findsOneWidget);
      });

      testWidgets('ilk sayfada kaydırma bir şey yapmaz', (t) async {
        await t.pumpWidget(_app(p));
        await t.dragFrom(const Offset(100, 300), const Offset(300, 0));
        await t.pumpAndSettle();
        expect(find.text('Aç'), findsOneWidget);
      });
    });
  }
}
