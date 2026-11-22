import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/ui/widgets.dart';

void main() {
  Future<List<int>> pump(WidgetTester tester, {int start = 20}) async {
    final values = <int>[];
    var value = start;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (ctx, set) => NumberStepper(
            value: value,
            min: 5,
            max: 100,
            onChanged: (v) => set(() {
              value = v;
              values.add(v);
            }),
          ),
        ),
      ),
    ));
    return values;
  }

  String box(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField)).controller!.text;

  testWidgets('+ ve − düğmeleri bir artırır/azaltır', (tester) async {
    final v = await pump(tester);
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    expect(v.last, 21);
    expect(box(tester), '21');
    await tester.tap(find.byIcon(Icons.remove_rounded));
    await tester.tap(find.byIcon(Icons.remove_rounded));
    await tester.pump();
    expect(v.last, 19);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 19);
  });

  testWidgets('sınırda düğme pasif', (tester) async {
    final v = await pump(tester, start: 100);
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    expect(v, isEmpty);
  });

  testWidgets('elle yazılan sayı uygulanır, aralık dışı düzeltilir', (tester) async {
    final v = await pump(tester);
    await tester.enterText(find.byType(TextField), '45');
    await tester.pump();
    expect(v.last, 45);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 45);

    await tester.enterText(find.byType(TextField), '3');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(v.last, 5);
    expect(box(tester), '5');

    await tester.enterText(find.byType(TextField), '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(box(tester), '5');
  });

  testWidgets('basılı tutunca hızlanarak artar', (tester) async {
    final v = await pump(tester);
    final g = await tester.startGesture(tester.getCenter(find.byIcon(Icons.add_rounded)));
    await tester.pump(const Duration(milliseconds: 600)); // uzun basma
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 90));
    }
    await g.up();
    await tester.pump();
    expect(v.last, greaterThan(40));
    expect(v.last, lessThanOrEqualTo(100));
  });
}
