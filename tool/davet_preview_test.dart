// Davet kampanyası önizlemesi: flutter test tool/davet_preview_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/pro.dart';
import 'package:netice/core/referral.dart';
import 'package:netice/core/store.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/invite_screen.dart';
import 'package:netice/ui/pro_screen.dart';
import 'package:netice/ui/theme.dart';

import 'screenshots_test.dart' show loadFonts, shot;

void main() {
  testWidgets('davet ekranları', (tester) async {
    await tester.runAsync(loadFonts);
    AppStore.proFreeOnThisPlatform = false;
    final store = AppStore()
      ..inviteCode = 'K7QM-3XRA'
      ..trialStart = DateTime.now().subtract(const Duration(days: 30));
    await ProService.instance.attach(store);
    Widget app(Widget home) => StoreScope(
        store: store,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: NTheme.light(), home: home));
    await shot(tester, app(const ProScreen()), const Size(390, 1500), 'davet_1_pro_normal');
    await shot(tester, app(const InviteScreen()), const Size(390, 1200), 'davet_2_davet_ekrani');
    store.applyInvite(Referral.newInviteCode());
    await shot(tester, app(const ProScreen()), const Size(390, 1500), 'davet_3_pro_indirimli');
  });
}
