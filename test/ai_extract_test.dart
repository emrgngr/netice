import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:netice/bank/ai_extract.dart';
import 'package:netice/bank/bank_models.dart';

void main() {
  test('uzun metin soru başlarından bölünür, cevap anahtarı her parçaya eklenir', () {
    final b = StringBuffer();
    for (var i = 1; i <= 120; i++) {
      b.write('\n$i) ${'Bu bir deneme sorusunun kökü olup yeterince uzundur. ' * 3}\nA) bir B) iki C) üç D) dört\n');
    }
    b.write('\nCevap Anahtarı\n${[for (var i = 1; i <= 120; i++) '$i-A'].join(' ')}');
    final text = b.toString();
    final parts = splitForExtract(text);
    expect(parts.length, greaterThan(1));
    for (final p in parts.take(parts.length - 1)) {
      expect(p.length, lessThanOrEqualTo(extractChunkChars));
    }
    // Her parça (ilki hariç) bir soru başıyla başlar.
    for (final p in parts.skip(1)) {
      expect(RegExp(r'^\d{1,3}\)').hasMatch(p), isTrue, reason: p.substring(0, 20));
    }
    final chunks = extractChunks(text: text);
    expect(chunks.first.text, contains('120-A'));
  });

  test('sayfalar üçerli gruplanır, son sayfa anahtar olarak her gruba eklenir', () {
    final pages = [for (var i = 0; i < 8; i++) Uint8List.fromList([i])];
    final c = extractChunks(pages: pages, keyLastPage: true);
    expect(c.length, 3); // 7 soru sayfası → 3 + 3 + 1
    expect(c.every((x) => x.keyPage![0] == 7), isTrue);
    expect(c.last.pages.single[0], 6);
  });

  test('yanıt taslak sorulara çevrilir', () {
    final r = parseExtractResponse({
      'questions': [
        {'type': 'multiple', 'number': '3', 'text': '2+2 kaçtır?', 'topic': 'Toplama', 'choices': ['3', '4', '5', '6'], 'correct': 1, 'answer': '', 'answer_source': 'document', 'needs_figure': false, 'difficulty': 'easy', 'solution': ''},
        {'type': 'multiple', 'number': '4', 'text': 'Şekle göre?', 'topic': '', 'choices': ['a', 'b'], 'correct': -1, 'answer': '', 'answer_source': 'unknown', 'needs_figure': true, 'difficulty': 'hard', 'solution': ''},
        {'type': 'multiple', 'number': '5', 'text': 'Bozuk', 'choices': ['tek'], 'correct': 0},
        {'type': 'open', 'number': '6', 'text': 'Açıklayınız.', 'answer': 'Çünkü…', 'answer_source': 'solved'},
      ],
      'problem': '',
      'cost': 1,
    }, subject: 'Matematik', sourceName: 'Deneme 1', page: Uint8List.fromList([9]));
    expect(r.questions.length, 3);
    final a = r.questions[0];
    expect(a.q.correct, {1});
    expect(a.q.choiceCount, 4);
    expect(a.q.subject, 'Matematik');
    expect(a.q.source, contains('Deneme 1'));
    expect(a.source, AnswerSource.document);
    expect(r.questions[1].source, AnswerSource.unknown);
    expect(r.questions[1].q.correct, isEmpty);
    expect(r.questions[1].page, isNotNull);
    expect(r.questions[2].q.type, QuestionType.open);
    expect(r.questions[2].source, AnswerSource.solved);
    expect(r.cost, 1);
  });
}
