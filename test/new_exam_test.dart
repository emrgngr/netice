import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/store.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/new_exam_screen.dart';

void main() {
  testWidgets('iki kitapçık ayrı anahtarla, tüm sınıflar için ortak sınav', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = AppStore();
    store.students.addAll([
      for (final c in ['9-A', '9-B', '10-A'])
        Student(id: 's$c', firstName: 'Ali', lastName: 'Veli', number: '1', className: c),
    ]);
    await tester.pumpWidget(StoreScope(store: store, child: const MaterialApp(home: NewExamScreen())));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Sınav adı'), 'Fizik Quiz');
    await tester.tap(find.text('Tüm sınıflar'));
    await tester.pump();
    expect(find.textContaining('ortak raporda'), findsOneWidget);

    // 5 soru, 2 kitapçık.
    for (var i = 0; i < 15; i++) {
      await tester.tap(find.byIcon(Icons.remove_rounded).first);
      await tester.pump();
    }
    await tester.tap(find.text('Tek kitapçık'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 kitapçık (A, B)').last);
    await tester.pumpAndSettle();
    expect(find.text('A kitapçığı · 0/5'), findsOneWidget);

    Future<void> type(String keys) async {
      for (final k in keys.split('')) {
        await tester.tap(find.widgetWithText(OutlinedButton, k));
        await tester.pump();
      }
    }

    await type('ABCDE');
    // B eksikken kaydedilmez.
    await tester.tap(find.text('Sınavı kaydet'));
    await tester.pump();
    expect(store.exams, isEmpty);
    expect(find.text('B kitapçığı · 0/5'), findsOneWidget);
    await type('EDCBA');
    await tester.tap(find.text('Sınavı kaydet'));
    await tester.pump();

    expect(store.exams.map((e) => e.className).toSet(), {'9-A', '9-B', '10-A'});
    final e = store.exams.first;
    expect(store.exams.map((x) => x.commonId).toSet().length, 1);
    expect(e.commonId, isNotNull);
    expect(e.questions.map((q) => q.correct.first), [0, 1, 2, 3, 4]);
    expect(e.bookletCount, 2);
    expect(e.questionsOf(1).map((q) => q.correct.first), [4, 3, 2, 1, 0]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('kayıtlı sınıf yokken virgülle birden çok sınıf yazılır', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = AppStore();
    await tester.pumpWidget(StoreScope(store: store, child: const MaterialApp(home: NewExamScreen())));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Sınav adı'), 'Yazışma');
    await tester.enterText(find.widgetWithText(TextField, 'Sınıf / şube'), 'A, B');
    await tester.pump();
    expect(find.widgetWithText(FilterChip, 'A'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Başka sınıf / şube ekle'), 'C');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('Tüm sınıflar'), findsOneWidget);
    expect(find.textContaining('ortak raporda'), findsOneWidget);

    for (var i = 0; i < 15; i++) {
      await tester.tap(find.byIcon(Icons.remove_rounded).first);
      await tester.pump();
    }
    for (final k in 'ABCDE'.split('')) {
      await tester.tap(find.widgetWithText(OutlinedButton, k));
      await tester.pump();
    }
    await tester.tap(find.text('Sınavı kaydet'));
    await tester.pump();
    expect(store.exams.map((e) => e.className).toSet(), {'A', 'B', 'C'});
    expect(store.exams.map((x) => x.commonId).toSet().length, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
