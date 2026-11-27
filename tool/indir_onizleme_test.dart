// "Netice'yi indirin" bölümünün önizlemesi (Profil: geniş, telefon, gece).
//   flutter test tool/indir_onizleme_test.dart
// Çıktılar build/screenshots/indir_*.png.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/store.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/download_links.dart';
import 'package:netice/ui/profile_screen.dart';
import 'package:netice/ui/theme.dart';

import 'screenshots_test.dart' show loadFonts, shot;

void main() {
  testWidgets('indirme bölümü', timeout: const Timeout(Duration(minutes: 3)), (tester) async {
    await tester.runAsync(loadFonts);
    final store = AppStore();
    await tester.runAsync(() => store.load(dir: Directory.systemTemp.createTempSync('indir')));
    AppStore.showDemoNotice = false;
    Widget themed(Widget home, {bool dark = false}) => StoreScope(
        store: store,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: dark ? NTheme.dark() : NTheme.light(), home: home));
    // Rozet görselleri yüklensin diye önce gerçek zamanda bir kez çizilir.
    await shot(tester, themed(const DownloadScreen()), const Size(1280, 720), 'indir_ekrani');
    await shot(tester, themed(const ProfileScreen()), const Size(1440, 1500), 'indir_profil_genis');
    await shot(tester, themed(const DownloadScreen()), const Size(390, 900), 'indir_telefon');
    await shot(tester, themed(const DownloadScreen(), dark: true), const Size(1280, 720), 'indir_ekrani_gece');
    AppStore.showDemoNotice = true;
  });
}
