import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/scoring.dart';

void main() {
  test('klasik sorular: test kısmı kalan puana ölçeklenir, klasik puan eklenir', () {
    final exam = Exam.fromKeyString(id: 'k', name: 'Yazılı', className: '9-A', key: 'ABCDE ABCDE').copyWith(
      openQuestions: const [OpenQuestion(label: 'K1', maxPoints: 20), OpenQuestion(label: 'K2', maxPoints: 20)],
    );
    expect(exam.testMax, 60);
    final sheet = Sheet(
      examId: 'k',
      answers: [for (var i = 0; i < 10; i++) i < 5 ? Answer.choice(i % 5) : const Answer.blank()],
    );
    var r = Scorer.score(exam, sheet);
    expect(r.testScore, 30);
    expect(r.openMissing, isTrue);
    expect(r.score, 30);

    r = Scorer.score(exam, sheet.copyWith(openScores: [15, 25])); // 25 → en çok 20
    expect(r.openMissing, isFalse);
    expect(r.openScore, 35);
    expect(r.score, 65);

    // JSON'dan geri gelir.
    final back = Exam.fromJson(jsonDecode(jsonEncode(exam.toJson())) as Map<String, dynamic>);
    expect(back.openQuestions.length, 2);
    final s2 = Sheet.fromJson(jsonDecode(jsonEncode(sheet.copyWith(openScores: [15, null]).toJson())) as Map<String, dynamic>);
    expect(s2.openScores, [15, null]);
  });
}
