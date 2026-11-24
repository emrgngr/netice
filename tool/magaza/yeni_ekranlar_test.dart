// Mağaza için yeni özellik ekranları: flutter test tool/magaza/yeni_ekranlar_test.dart
// Çıktılar build/screenshots/ içine yazılır; tool/magaza/gorseller.py kullanır.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/bank/bank_store.dart';
import 'package:netice/core/store.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/bank/booklet_wizard_screen.dart';
import 'package:netice/ui/bank/library_screen.dart';
import 'package:netice/ui/lan_sync_screen.dart';
import 'package:netice/ui/parent_send_screen.dart';
import 'package:netice/ui/theme.dart';

import '../bank_preview_test.dart' show seedBank;
import '../screenshots_test.dart' show loadFonts, shot;

Widget _themed(Widget home, AppStore store) => StoreScope(
      store: store,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: NTheme.light(), home: home),
    );

void main() {
  testWidgets('mağaza: yeni özellik ekranları', (tester) async {
    debugDisableShadows = false;
    await tester.runAsync(loadFonts);
    final store = AppStore();
    final dir = Directory.systemTemp.createTempSync('magaza');
    await tester.runAsync(() => store.load(dir: dir));
    store.onboardingDone = true;
    store.ratePrompted = true;
    final b = BankStore.instance;
    await tester.runAsync(() async {
      await b.load(dir: dir);
      await seedBank(b);
    });
    // Velilere toplu gönderim: telefonlar ve birkaç gönderilmiş işaret.
    for (var i = 0; i < store.students.length; i++) {
      store.students[i] = store.students[i].copyWith(parentPhone: '+90 532 000 ${(1000 + i).toString()}');
    }
    final exam = store.examById('demo_exam')!;
    final names = [
      for (final r in store.resultsOf(exam)) ?store.studentById[r.sheet.studentId],
    ]..sort((a, b) => a.fullName.compareTo(b.fullName));
    for (final st in names.take(9)) {
      store.markParentSent(exam.id, st.id);
    }

    const phone = Size(390, 844);
    await shot(tester, _themed(const LibraryScreen(), store), phone, 'magaza_banka');
    await shot(tester, _themed(BookletWizardScreen(booklet: b.bookletById('k1')), store), phone, 'magaza_kitapcik',
        then: () async {
      await tester.tap(find.text('Kitapçık'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A–D').first);
    });
    await shot(tester, _themed(const ParentSendScreen(examId: 'demo_exam'), store), phone, 'magaza_veli');
    await shot(tester, _themed(const LanSyncScreen(examId: 'demo_exam'), store), phone, 'magaza_wifi');
    await shot(tester, NeticeApp(store: store, splash: false), phone, 'magaza_kutuphane_sekme',
        then: () async => tester.tap(find.text('Kütüphane')));
    debugDisableShadows = true;
  });
}
