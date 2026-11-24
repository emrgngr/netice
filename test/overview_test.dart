import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/overview.dart';
import 'package:netice/core/store.dart';
import 'package:netice/reports/pdf_documents.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Dist: ortalama, medyan, çeyrekler', () {
    final d = Dist.of([10, 20, 30, 40, 50]);
    expect(d.n, 5);
    expect(d.mean, 30);
    expect(d.median, 30);
    expect(d.q1, 20);
    expect(d.q3, 40);
    expect(d.min, 10);
    expect(d.max, 50);
    expect(Dist.of(const []).n, 0);
  });

  test('genel istatistik: tüm sınıflar ve öğrenciler', () {
    final store = AppStore()..seedDemo();
    final ov = Overview.build(store);
    expect(ov.exams.length, 3);
    final sheets = store.exams.fold<int>(0, (a, e) => a + store.resultsOf(e).length);
    expect(ov.sheets, sheets);
    expect(ov.classes.map((c) => c.name).toSet(), {'9-A', '9-B'});
    // Sınıflar ortalamaya göre sıralı.
    expect(ov.classes.first.dist.mean >= ov.classes.last.dist.mean, isTrue);
    expect(ov.participants, store.students.length);
    expect(ov.participation, closeTo(1, 1e-9));
    expect(ov.histogram10.reduce((a, b) => a + b), sheets);
    expect(ov.levelCounts.reduce((a, b) => a + b), sheets);
    expect(ov.correctRate + ov.wrongRate + ov.blankRate, closeTo(1, 1e-9));
    expect(ov.timeline.length, 3);
    expect(ov.top.first.average >= ov.top.last.average, isTrue);
    // 9-A öğrencileri iki sınava girdi: gelişen/düşen listeleri dolu olabilir.
    expect(ov.students.where((s) => s.count == 2).length, 24);
    expect(ov.improved.length + ov.declined.length, greaterThan(0));
    expect(ov.outcomes.map((o) => o.code), contains('Hareket'));
    expect(ov.comments, isNotEmpty);
    expect(ov.classes.firstWhere((c) => c.name == '9-A').trend, isNotNull);
  });

  test('genel istatistik: sınıf ve dönem süzgeci', () {
    final store = AppStore()..seedDemo();
    final b = Overview.build(store, classes: {'9-B'});
    expect(b.classes.single.name, '9-B');
    expect(b.exams.length, 1);
    expect(b.registered, store.studentsOf('9-B').length);
    final recent = Overview.build(store, period: OverviewPeriod.last30, now: DateTime.now().add(const Duration(days: 20)));
    // 16 gün önceki Quiz 1 son 30 günün dışında kalır.
    expect(recent.exams.length, 2);
    final none = Overview.build(store, classes: {'yok'});
    expect(none.isEmpty, isTrue);
    expect(none.comments, isEmpty);
  });

  test('etki büyüklüğü ve PDF', () async {
    expect(cohenD(Dist.of([50, 60, 70]), Dist.of([50, 60, 70])), 0);
    expect(cohenD(Dist.of([80, 90, 100]), Dist.of([10, 20, 30])) > 0.8, isTrue);
    final store = AppStore()..seedDemo();
    final pdf = await buildOverviewPdf(Overview.build(store), filter: 'Tümü');
    expect(pdf.length, greaterThan(2000));
  });
}
