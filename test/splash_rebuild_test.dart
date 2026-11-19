import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/store.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/home_screen.dart';
import 'package:netice/ui/splash_screen.dart';

/// Veri değişip uygulama yeniden çizilse de açılış animasyonu yarıda kesilmez.
void main() {
  testWidgets('açılış animasyonu veri değişince kesilmez', (tester) async {
    final store = AppStore();
    await tester.runAsync(() => store.load(dir: Directory.systemTemp.createTempSync('splash')));
    store.onboardingDone = true;
    store.ratePrompted = true;
    await tester.pumpWidget(NeticeApp(store: store));
    await tester.pump(const Duration(milliseconds: 300));
    store.setCloudAuto(!store.cloudAuto); // yeniden çizimi tetikler
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(SplashScreen.played, isTrue);
  });
}
