import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/store.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/exam_screen.dart';

void main() {
  testWidgets('Form yazdır: seçenek seçilir, "Tamam" ile devam edilir', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = AppStore();
    store.exams.add(Exam(
      id: 'e1',
      name: 'Deneme',
      className: '9-A',
      date: DateTime(2026, 11, 22),
      questions: [for (var i = 0; i < 5; i++) Question(no: i + 1, correct: {0})],
      choiceCount: 5,
    ));
    await tester.pumpWidget(StoreScope(store: store, child: const MaterialApp(home: ExamScreen(examId: 'e1'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Form yazdır').first);
    await tester.pumpAndSettle();
    expect(find.text('Tamam, önizle'), findsOneWidget);
    // Adet seçmek sayfayı kapatmaz; boş form seçili hâle gelir.
    await tester.tap(find.text('20 adet'));
    await tester.pumpAndSettle();
    expect(find.text('Tamam, önizle'), findsOneWidget);
    final tile = tester.widget<ListTile>(find.widgetWithText(ListTile, 'Boş öğrenci formu'));
    expect(tile.selected, isTrue);
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(find.text('Tamam, önizle'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
