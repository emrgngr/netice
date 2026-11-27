import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/analysis.dart';
import 'package:netice/core/bloom.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/scoring.dart';

Sheet _s(String id, String marks) => Sheet(examId: 'e', studentId: id, answers: [
      for (final ch in marks.split('')) ch == '-' ? const Answer.blank() : Answer(MarkState.filled, {ch.codeUnitAt(0) - 65})
    ]);

void main() {
  final base = Exam.fromKeyString(id: 'e', name: 'T', className: '9-A', key: 'AAAA', choiceCount: 4);
  final exam = base.copyWith(questions: [
    base.questions[0].copyWith(cognitive: 'remember'),
    base.questions[1].copyWith(cognitive: 'remember'),
    base.questions[2].copyWith(cognitive: 'analyze'),
    base.questions[3],
  ]);
  // Güçlü öğrenciler 1–3'ü bilir; 4. soruyu yalnız zayıflar bilir (ters çalışan soru).
  final results = Scorer.scoreAll(exam, [
    _s('a', 'AAAB'),
    _s('b', 'AAAB'),
    _s('c', 'AABB'),
    _s('d', 'ABBA'),
    _s('e', 'BBBA'),
  ]);

  test('madde-toplam korelasyonu: ters çalışan soru eksi çıkar', () {
    final items = Analysis.itemStats(exam, results);
    expect(items[3].rpb, isNotNull);
    expect(items[3].rpb!, lessThan(0));
    expect(items[1].rpb!, closeTo(1 / 6, 1e-9)); // elle hesaplandı
    expect(items[3].rpbLabel, 'Ters çalışıyor');
  });

  test('Bloom düzeyleri: oranlar ve alt/üst düzey', () {
    final b = BloomReport.build(exam, results);
    expect(b.rows.map((r) => r.level), ['remember', 'analyze']);
    expect(b.rows.first.rate, closeTo(7 / 10, 1e-9));
    expect(b.rows.last.rate, closeTo(2 / 5, 1e-9));
    expect(b.lower, closeTo(0.7, 1e-9));
    expect(b.higher, closeTo(0.4, 1e-9));
    expect(b.tagged, 3);
    expect(b.total, 4);
    expect(Exam.fromJson(exam.toJson()).questions[2].cognitive, 'analyze');
  });
}
