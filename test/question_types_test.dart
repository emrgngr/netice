// Yeni soru türleri: eşleştirme, doğru/yanlış tablosu, kelime havuzu, sıralama.
// Önizleme PDF'leri: SORU_TURU_ONIZLEME=1 ile build/soru_turleri/ altına yazılır.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netice/bank/bank_models.dart';
import 'package:netice/bank/booklet_builder.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/scoring.dart';
import 'package:netice/reports/booklet_pdf.dart';

final _t = DateTime(2026, 11, 26);

BankQuestion _q(String id, QuestionType type,
        {String text = '', List<String> choices = const [], List<String> items = const [], List<int> keys = const [], Set<int> correct = const {}, int choiceCount = 4}) =>
    BankQuestion(
      id: id,
      subject: 'Fen',
      topic: 'Bitkiler',
      type: type,
      text: text,
      choices: choices,
      choiceCount: choiceCount,
      items: items,
      itemKeys: keys,
      correct: correct,
      created: _t,
      updated: _t,
    );

List<BankQuestion> sample({bool kids = false}) => [
      _q('m1', QuestionType.multiple, text: 'Bitkiler besinini nerede üretir?', choices: ['Kök', 'Yaprak', 'Gövde'], correct: {1}),
      _q('eş', QuestionType.matching,
          text: 'Bitkinin bölümlerini görevleriyle eşleştiriniz.',
          items: ['Kök', 'Yaprak', 'Çiçek'],
          choices: ['Besin üretir', 'Topraktan su alır', 'Tohum oluşturur'],
          keys: [1, 0, 2]),
      _q('dy', QuestionType.trueFalseTable,
          text: 'Aşağıdaki ifadeler doğru mu, yanlış mı?',
          items: ['Bitkiler güneş ışığına ihtiyaç duyar.', 'Tohum çimlenmek için suya ihtiyaç duymaz.', 'Yapraklar genellikle yeşildir.'],
          keys: [0, 1, 0]),
      _q('kh', QuestionType.wordBank,
          items: ['Bitki suyu ____ ile alır.', 'Tohum toprakta ____.', 'Arılar çiçeklerden ____ toplar.'],
          choices: ['kök', 'çimlenir', 'nektar', 'taş'],
          keys: [0, 1, 2]),
      _q('sr', QuestionType.ordering,
          text: 'Bir bitkinin büyüme adımlarının doğru sıralaması hangisidir?',
          items: ['Tohum toprağa ekilir.', 'Tohum çimlenir.', 'Fide büyür.', 'Bitki çiçek açar.'],
          choiceCount: kids ? 3 : 4),
      _q('ön', QuestionType.multiple,
          text: 'Hangileri canlıdır?',
          items: ['Ağaç', 'Kelebek', 'Taş'],
          choices: ['Yalnız I', 'I ve II', 'II ve III', 'I, II ve III'],
          correct: {1}),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('kayıt: madde ve anahtarlar korunur, eksik soru yakalanır', () {
    for (final q in sample()) {
      final back = BankQuestion.fromJson(q.toJson());
      expect(back.items, q.items);
      expect(back.itemKeys, q.itemKeys);
      expect(back.type, q.type);
      expect(back.complete, isTrue, reason: q.id);
    }
    expect(_q('x', QuestionType.matching, items: ['a', 'b'], choices: ['x', 'y'], keys: [0]).complete, isFalse);
    expect(_q('x', QuestionType.ordering, items: ['a', 'b']).complete, isFalse);
    expect(sample()[1].answerLabel, '1-B 2-A 3-C');
    expect(sample()[2].opticalRows, 3);
  });

  test('sıralama şıkları: biri doğru dizi, hepsi farklı', () {
    final q = sample()[4].expanded().single;
    expect(q.choices.length, 4);
    expect(q.choices.toSet().length, 4);
    // Doğru şık, karışık basılan adımları doğru sıraya dizer.
    final right = q.choices[q.correct.single].split(' – ');
    final ordered = [for (final r in right) q.items[['I', 'II', 'III', 'IV'].indexOf(r)]];
    expect(ordered, sample()[4].items);
    expect(q.items, isNot(sample()[4].items), reason: 'adımlar karışık basılır');
    final kid = sample(kids: true)[4].expanded(kids: true).single;
    expect(kid.choices.length, 3);
    expect(kid.choices.first, matches(RegExp(r'^\d( – \d)+$')));
  });

  test('kitapçık: gruplar optik satırlara açılır, B kitapçığında birlikte kalır', () {
    final plan = BookletPlan.build(
        sample(), const BookletOptions(bookletCount: 2, shuffleQuestions: true, shuffleChoices: true, seed: 3));
    // 1 + 3 + 3 + 3 + 1 + 1 satır
    expect(plan.testMaster.length, 12);
    final exam = plan.toExam(id: 'e', name: 'Fen', className: '5-A');
    expect(exam.questions.length, 12);
    expect(exam.questions.where((q) => q.bankId == 'eş').length, 3);
    expect(exam.questions.map((q) => q.correct.single).toList().sublist(1, 7), [1, 0, 2, 0, 1, 0]);
    final b = plan.variants[1];
    for (final g in ['eş', 'dy', 'kh']) {
      final at = [for (var i = 0; i < b.test.length; i++) if (b.test[i].question.parent?.id == g) i];
      expect(at.length, 3);
      expect(at.last - at.first, 2, reason: '$g maddeleri bitişik');
      expect([for (final i in at) b.test[i].question.text], sample().firstWhere((q) => q.id == g).items, reason: 'madde sırası korunur');
    }
    // B kitapçığının anahtarı basılı doğru şıklarla aynıdır.
    expect([for (final q in exam.questionsOf(1)) q.correct], [for (final p in b.test) p.printedCorrect]);
    final sheet = Sheet(examId: 'e', answers: [for (final q in exam.questions) Answer.choice(q.correct.single)]);
    expect(Scorer.score(exam, sheet).correct, 12);
  });

  test('PDF: klasik ve çocuk kitapçığı, çözümlü anahtar', () async {
    for (final kids in [false, true]) {
      final o = BookletOptions(
        title: 'Bitkiler',
        style: kids ? BookletStyle.kids : BookletStyle.classic,
        fontSize: kids ? 14 : 11,
        bookletCount: kids ? 1 : 2,
        shuffleQuestions: true,
        officialHeader: !kids,
        solutionsBooklet: true,
      );
      final plan = BookletPlan.build(sample(kids: kids), o);
      final pdf = await buildBookletPdf(plan,
          school: const SchoolInfo(), image: (_) => null, parts: const BookletPdfParts(answerKey: true, solutions: true));
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
      if (Platform.environment['SORU_TURU_ONIZLEME'] == '1') {
        Directory('build/soru_turleri').createSync(recursive: true);
        File('build/soru_turleri/${kids ? 'cocuk' : 'klasik'}.pdf').writeAsBytesSync(pdf);
      }
    }
  });
}
