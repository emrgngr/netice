import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/scoring.dart';

Answer a(String l) => Answer.choice(l.codeUnitAt(0) - 65);

void main() {
  // A: A B C D, B kitapçığının kendi anahtarı: D C B A (soru sırası bilinmiyor).
  final exam = Exam(
    id: 'e1',
    name: 'Quiz',
    className: '9-A',
    date: DateTime(2026, 11, 22),
    choiceCount: 5,
    questions: [for (var i = 0; i < 4; i++) Question(no: i + 1, correct: {i})],
    bookletOrders: const [
      [0, 1, 2, 3]
    ],
    bookletKeys: const [
      [
        {3},
        {2},
        {1},
        {0}
      ]
    ],
  );

  test('her kitapçık kendi anahtarıyla puanlanır', () {
    final aSheet = Sheet(examId: 'e1', answers: [a('A'), a('B'), a('C'), a('A')]);
    final bSheet = Sheet(examId: 'e1', booklet: 1, answers: [a('D'), a('C'), a('B'), a('D')]);
    final ra = Scorer.score(exam, aSheet), rb = Scorer.score(exam, bSheet);
    expect([ra.correct, ra.wrong], [3, 1]);
    expect([rb.correct, rb.wrong], [3, 1]);
    expect(exam.questionsOf(1).map((q) => q.correct.first), [3, 2, 1, 0]);
    expect(exam.questionAt(0, 0).correct, {0});
  });

  test('kitapçık anahtarları kaydedilip geri okunur', () {
    final back = Exam.fromJson(exam.toJson());
    expect(back.hasOwnKey(1), isTrue);
    expect(back.bookletKeys.first.map((k) => k.first), [3, 2, 1, 0]);
    // Eski kayıtlar (anahtarsız) sıra eşlemesiyle çalışmaya devam eder.
    final old = Exam.fromJson(exam.toJson()..remove('bookletKeys'));
    expect(old.hasOwnKey(1), isFalse);
  });
}
