// Masaüstü: iç sayfaların (formlar, ayrıntılar) geniş pencere görüntüleri.
//   flutter test tool/masaustu_ic_sayfalar_test.dart [--dart-define=THEMES=light,dark]
// Çıktılar build/screenshots/ic/<tema>_<sayfa>[_kaydırma].png
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/store.dart';
import 'package:netice/l10n/l10n.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/admin_panel_screen.dart';
import 'package:netice/ui/exam_settings_screen.dart';
import 'package:netice/ui/grade_scale_screen.dart';
import 'package:netice/ui/invite_screen.dart';
import 'package:netice/ui/license_screen.dart';
import 'package:netice/ui/mastery_screen.dart';
import 'package:netice/ui/new_exam_screen.dart';
import 'package:netice/ui/school_offer_screen.dart';
import 'package:netice/ui/school_screen.dart';
import 'package:netice/ui/student_detail_screen.dart';
import 'package:netice/ui/template_screen.dart';
import 'package:netice/ui/term_screen.dart';
import 'package:netice/ui/why_screen.dart';

import 'screenshots_test.dart' show loadFonts, shot;

void main() {
  testWidgets('masaüstü iç sayfalar', timeout: const Timeout(Duration(minutes: 10)), (tester) async {
    const themes = String.fromEnvironment('THEMES', defaultValue: 'light');
    const only = String.fromEnvironment('ONLY');
    debugDisableShadows = false;
    await tester.runAsync(loadFonts);
    L10n.use('tr');
    Directory('build/screenshots/ic').createSync(recursive: true);
    final store = AppStore();
    final dir = Directory.systemTemp.createTempSync('ic');
    await tester.runAsync(() => store.load(dir: dir));
    store.onboardingDone = true;
    store.ratePrompted = true;
    store.hidePromo(const Duration(days: 3650));
    AppStore.showDemoNotice = false;
    final exam = store.exams.first;
    final student = store.students.first;
    final pages = <String, Widget Function()>{
      'kurum': () => const SchoolScreen(),
      'yeni_sinav': () => const NewExamScreen(),
      'sinav_ayarlari': () => ExamSettingsScreen(examId: exam.id),
      'ogrenci': () => StudentDetailScreen(studentId: student.id),
      'davet': () => const InviteScreen(),
      'lisans': () => const LicenseScreen(),
      'donem': () => const TermScreen(),
      'not_sistemi': () => const GradeScaleScreen(),
      'formlar': () => const TemplatesScreen(),
      'okul_teklif': () => const SchoolOfferScreen(),
      'kazanim': () => MasteryScreen(className: exam.className),
      'yonetici': () => const AdminPanelScreen(),
      'neden': () => const WhyNeticeScreen(),
    };
    final problems = <String>[];
    for (final theme in themes.split(',')) {
      store.setThemeMode(theme);
      for (final MapEntry(key: key, value: page) in pages.entries) {
        if (only.isNotEmpty && !only.split(',').contains(key)) continue;
        for (final scroll in [0.0, 800.0]) {
          final name = 'ic/${theme}_$key${scroll == 0 ? '' : '_${scroll.toInt()}'}';
          final old = FlutterError.onError;
          FlutterError.onError = (d) => problems.add('$name: ${d.exceptionAsString().split('\n').first}');
          var canScroll = true;
          try {
            await shot(tester, NeticeApp(store: store, splash: false), const Size(1440, 900), name, then: () async {
              tester.state<NavigatorState>(find.byType(Navigator).first).push(MaterialPageRoute(builder: (_) => page()));
              await tester.pumpAndSettle();
              if (scroll > 0) {
                ScrollableState? best;
                for (final e in find.byType(Scrollable).evaluate()) {
                  final st = (e as StatefulElement).state as ScrollableState;
                  if (st.position.axis != Axis.vertical) continue;
                  if (best == null || st.position.maxScrollExtent > best.position.maxScrollExtent) best = st;
                }
                if (best == null || best.position.maxScrollExtent < 300) {
                  canScroll = false;
                  return;
                }
                best.position.jumpTo(scroll.clamp(0, best.position.maxScrollExtent));
              }
            });
          } catch (e) {
            problems.add('$name: ${'$e'.split('\n').first}');
          } finally {
            FlutterError.onError = old;
          }
          if (!canScroll) {
            File('build/screenshots/$name.png').deleteSync();
            break;
          }
        }
      }
    }
    AppStore.showDemoNotice = true;
    debugDisableShadows = true;
    // ignore: avoid_print
    print('SORUNLAR ${problems.length}\n${problems.join('\n')}');
  });
}
