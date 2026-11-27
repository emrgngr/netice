import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/deneme.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/scoring.dart';

Sheet _sheet(String id, String marks) => Sheet(
      examId: 'e',
      studentId: id,
      answers: [
        for (final ch in marks.split(''))
          ch == '-' ? const Answer.blank() : Answer(MarkState.filled, {ch.codeUnitAt(0) - 65})
      ],
    );

void main() {
  final base = Exam.fromKeyString(id: 'e', name: 'Deneme', className: '12-A', key: 'AAAA' 'BBBB', choiceCount: 4,
      rule: const ScoringRule(wrongsPerCorrect: 4));
  final exam = base.copyWith(
    sections: ExamSection.fromCounts([('Türkçe', 4, 3.0), ('Matematik', 4, 4.0)]),
    baseScore: 100,
  );

  test('bölümler doğrulanır ve JSON ile korunur', () {
    expect(ExamSection.validate(exam.sections, 8), isNull);
    expect(ExamSection.validate(ExamSection.fromCounts([('A', 3, 0), ('B', 4, 0)]), 8), isNotNull);
    final back = Exam.fromJson(exam.toJson());
    expect(back.sections.map((s) => '${s.name}:${s.start}:${s.count}:${s.weight}').join(','),
        'Türkçe:0:4:3.0,Matematik:4:4:4.0');
    expect(back.baseScore, 100);
    expect(back.isMultiSubject, isTrue);
    expect(Exam.fromJson(base.toJson()).sections, isEmpty);
  });

  test('ders ders net, ağırlıklı puan ve sıra', () {
    final results = Scorer.scoreAll(exam, [
      _sheet('s1', 'AAAABBBB'), // 4 + 4 net
      _sheet('s2', 'AAABBB--'), // Türkçe 3D 1Y = 2,75; Mat 2D = 2
      _sheet('s3', 'AAAABBBB'), // s1 ile eşit
    ]);
    final rep = DenemeReport.build(exam, results);
    expect(rep.rows.first.weighted, 100 + 4 * 3 + 4 * 4);
    expect(rep.rows[0].rank, 1);
    expect(rep.rows[1].rank, 1); // eşit puan aynı sırayı alır
    final s2 = rep.rowOf('s2')!;
    expect(s2.rank, 3);
    expect(s2.sections[0].net, 2.75);
    expect(s2.sections[1].net, 2);
    expect(s2.sections[1].blank, 2);
    expect(s2.totalNet, 4.75);
    expect(s2.weighted, 100 + 2.75 * 3 + 2 * 4);
    expect(rep.ranked.first.section.name, 'Türkçe');
  });
}
