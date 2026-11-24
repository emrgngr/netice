import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/grade_scale.dart';
import 'package:netice/core/report.dart';
import 'package:netice/core/store.dart';

void main() {
  tearDown(() => Level.useScale(null));

  test('hazır sistemler geçerli ve en alttaki düzey 0', () {
    for (final p in GradeScale.presets) {
      expect(GradeScale.validate(p.bands), isNull, reason: p.id);
      expect(p.bands.last.minPct, 0, reason: p.id);
    }
  });

  test('hatalı düzeyler reddedilir', () {
    expect(GradeScale.validate(const [GradeBand('A', 0)]), 'few');
    expect(GradeScale.validate(const [GradeBand('', 50), GradeBand('F', 0)]), 'label');
    expect(GradeScale.validate(const [GradeBand('A', 50), GradeBand('B', 60), GradeBand('F', 0)]), 'order');
    expect(GradeScale.validate(const [GradeBand('A', 120), GradeBand('F', 0)]), 'order');
  });

  test('özel sistem düzeyleri belirler ve kaydedilip geri okunur', () {
    final s = AppStore();
    const scale = GradeScale(id: 'custom', name: 'Özel', bands: [GradeBand('Geçti', 45), GradeBand('Kaldı', 0)]);
    s.setGradeScale(scale);
    expect(Level.all.map((l) => l.name), ['Geçti', 'Kaldı']);
    expect(Level.of(44.9).name, 'Kaldı');
    expect(Level.of(45).name, 'Geçti');

    final back = GradeScale.fromJson(s.toJsonMap()['gradeScale']);
    expect(back!.bands.map((b) => b.label), ['Geçti', 'Kaldı']);
    expect(back.bands.first.minPct, 45);

    s.setGradeScale(null);
    expect(Level.all, same(Level.languageDefault));
    expect(s.toJsonMap().containsKey('gradeScale'), isFalse);
  });

  test('bozuk kayıt sıralanır ya da yok sayılır', () {
    final g = GradeScale.fromJson({
      'id': 'custom',
      'name': 'x',
      'bands': [
        {'label': 'Düşük', 'min': 20},
        {'label': 'Yüksek', 'min': 80},
      ],
    })!;
    expect(g.bands.map((b) => b.label), ['Yüksek', 'Düşük']);
    expect(g.bands.last.minPct, 0);
    expect(GradeScale.fromJson({'bands': []}), isNull);
    expect(GradeScale.fromJson('?'), isNull);
  });
}
