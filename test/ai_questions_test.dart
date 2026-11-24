import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:netice/bank/ai_questions.dart';
import 'package:netice/bank/bank_models.dart';
import 'package:netice/bank/bank_store.dart';

BankNote note({String body = 'Hücre zarı seçici geçirgendir; bazı maddeleri geçirir, bazılarını geçirmez. Difüzyon ve osmoz pasif taşımadır.'}) {
  final t = DateTime(2026, 11, 24);
  return BankNote(
    id: 'n1',
    subject: 'Biyoloji',
    grade: '9',
    topic: 'Hücre zarı',
    title: 'Madde geçişleri',
    body: body,
    tags: const ['tekrar'],
    created: t,
    updated: t,
  );
}

Map<String, dynamic> okBody(int n) => {
      'questions': [
        for (var i = 0; i < n; i++)
          {
            'text': 'Soru metni $i',
            'choices': ['a', 'b', 'c', 'd', 'e'],
            'correct': i % 5,
            'difficulty': i.isEven ? 'easy' : 'hard',
            'solution': 'Çünkü $i',
          },
      ],
      'problem': '',
      'used': n,
      'limit': 300,
    };

void main() {
  late Directory dir;
  late AiUsage usage;
  late BankStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ai_test');
    usage = AiUsage.forTest();
    await usage.load(dir: dir);
    store = BankStore.forTest();
  });
  tearDown(() => dir.delete(recursive: true));

  test('cihaz kimliği üretilir ve kalıcıdır', () async {
    expect(usage.device, matches(RegExp(r'^[a-z0-9]{24}$')));
    final again = AiUsage.forTest();
    await again.load(dir: dir);
    expect(again.device, usage.device);
  });

  test('deneme ve aylık kota', () {
    final nov = DateTime(2026, 11, 10);
    expect(usage.remaining(false, nov), AiUsage.trialLimit);
    usage.record(15, false, nov);
    expect(usage.remaining(false, nov), 5);
    expect(usage.remaining(true, nov), AiUsage.monthlyLimit - 15);
    usage.record(100, true, nov);
    expect(usage.remaining(true, nov), AiUsage.monthlyLimit - 115);
    expect(usage.trialUsed, 15, reason: 'Pro kullanımı deneme hakkından düşmez');
    // Ay değişince aylık sayaç sıfırlanır, deneme hakkı sıfırlanmaz.
    final dec = DateTime(2026, 12, 1);
    expect(usage.remaining(true, dec), AiUsage.monthlyLimit);
    expect(usage.remaining(false, dec), 5);
  });

  test('yanıt bankaya uygun taslak sorulara çevrilir', () {
    final r = parseAiResponse({
      ...okBody(2),
      'questions': [
        ...okBody(2)['questions'] as List,
        {'text': '', 'choices': ['a', 'b'], 'correct': 0},
        {'text': 'x', 'choices': ['a', 'b'], 'correct': 5},
      ],
    }, note(), store);
    expect(r.questions, hasLength(2));
    final q = r.questions.first;
    expect(q.subject, 'Biyoloji');
    expect(q.topic, 'Hücre zarı');
    expect(q.type, QuestionType.multiple);
    expect(q.correct, {0});
    expect(q.difficulty, Difficulty.easy);
    expect(q.tags, containsAll(['tekrar', 'yapay zekâ']));
    expect(q.source, 'Madde geçişleri');
    expect(q.complete, isTrue);
    expect(r.questions[1].difficulty, Difficulty.hard);
  });

  test('istek gövdesi notu ve seçenekleri taşır', () {
    final b = aiRequestBody(note(), const AiOptions(count: 10, choices: 4, difficulty: AiDifficulty.hard), images: ['QUJD']);
    expect(b['count'], 10);
    expect(b['choices'], 4);
    expect(b['difficulty'], 'hard');
    expect((b['note'] as Map)['topic'], 'Hücre zarı');
    expect(((b['note'] as Map)['images'] as List).single, {'type': 'image/jpeg', 'data': 'QUJD'});
  });

  test('sunucuyla soru üretimi ve sayaç', () async {
    late http.Request sent;
    final client = MockClient((req) async {
      sent = req;
      return http.Response.bytes(utf8.encode(jsonEncode(okBody(5))), 200);
    });
    final r = await generateAiQuestions(note(), const AiOptions(count: 5),
        store: store, usage: usage, paid: false, client: client, url: 'https://ornek.workers.dev/');
    expect(r.questions, hasLength(5));
    expect(sent.url.toString(), 'https://ornek.workers.dev/uret');
    expect(sent.headers['x-netice-device'], usage.device);
    expect(sent.headers['x-netice-app'], isNotEmpty);
    expect(usage.trialUsed, 5);
    expect(usage.remaining(false), AiUsage.trialLimit - 5);
  });

  test('kota dolunca sunucuya gidilmez', () async {
    usage.record(AiUsage.trialLimit, false);
    var called = false;
    final client = MockClient((_) async {
      called = true;
      return http.Response('{}', 200);
    });
    await expectLater(
      generateAiQuestions(note(), const AiOptions(count: 5), store: store, usage: usage, paid: false, client: client, url: 'https://x.dev'),
      throwsA(isA<AiException>().having((e) => e.quota, 'quota', isTrue)),
    );
    expect(called, isFalse);
  });

  test('sunucu hataları anlaşılır mesaja çevrilir', () async {
    final client = MockClient((_) async => http.Response.bytes(utf8.encode(jsonEncode({'error': 'quota', 'used': 300})), 429));
    await expectLater(
      generateAiQuestions(note(), const AiOptions(count: 5), store: store, usage: usage, paid: true, client: client, url: 'https://x.dev'),
      throwsA(isA<AiException>().having((e) => e.quota, 'quota', isTrue)),
    );
    expect(usage.remaining(true), 0, reason: 'sunucunun bildirdiği kullanım cihaza yazılır');
  });

  test('kısa not ve adres yoksa hata', () async {
    await expectLater(
      generateAiQuestions(note(body: 'kısa'), const AiOptions(), store: store, usage: usage, paid: true, url: 'https://x.dev'),
      throwsA(isA<AiException>()),
    );
    await expectLater(
      generateAiQuestions(note(), const AiOptions(), store: store, usage: usage, paid: true, url: ''),
      throwsA(isA<AiException>()),
    );
  });
}
