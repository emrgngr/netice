// Okuma parçası grupları, görselli şıklar ve çok doğrulu sorular.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:netice/bank/bank_models.dart';
import 'package:netice/bank/bank_store.dart';
import 'package:netice/bank/booklet_builder.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/scoring.dart';
import 'package:netice/reports/booklet_pdf.dart';

BankQuestion q(String id, {String? passage, Set<int> correct = const {0}, bool multi = false, List<String?> imgs = const [], List<String>? choices}) =>
    BankQuestion(
      id: id,
      subject: 'Türkçe',
      topic: 'Okuma',
      type: QuestionType.multiple,
      text: 'Soru $id: Aşağıdakilerden hangisi doğrudur?',
      choices: choices ?? ['Birinci şık', 'İkinci şık', 'Üçüncü şık', 'Dördüncü şık'],
      choiceCount: 4,
      correct: correct,
      passageId: passage,
      multiSelect: multi,
      choiceImages: imgs,
      created: DateTime(2026),
      updated: DateTime(2026),
    );

final _passage = BankPassage(
  id: 'p1',
  title: 'Yağmur ormanları',
  text: 'Yağmur ormanları yeryüzünün yalnızca küçük bir bölümünü kaplar, ama canlı türlerinin yarısından fazlası burada yaşar.\n'
      'Ağaçlar büyük miktarda karbondioksit tutar ve yağış düzenini etkiler. Bu yüzden ormanların korunması bütün dünyayı ilgilendirir.',
  subject: 'Türkçe',
  created: DateTime(2026),
  updated: DateTime(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('çok doğrulu soru: hepsi ve yalnız onlar işaretlenirse doğru', () {
    final base = Exam.fromKeyString(id: 'e', name: 'T', className: '9-A', key: 'AA', choiceCount: 4);
    final exam = base.copyWith(questions: [base.questions[0].copyWith(correct: {0, 2}, multiSelect: true), base.questions[1]]);
    Outcome o(Set<int> m) => Scorer.outcomeFor(exam.questions[0], Answer(MarkState.filled, m));
    expect(o({0, 2}), Outcome.correct);
    expect(o({0}), Outcome.wrong);
    expect(o({0, 1, 2}), Outcome.wrong);
    // Tek doğrulu soruda çift işaret hâlâ yanlış.
    expect(Scorer.outcomeFor(exam.questions[1], Answer(MarkState.filled, {0, 1})), Outcome.wrong);
    // JSON'da korunur.
    expect(Question.fromJson(exam.questions[0].toJson()).multiSelect, isTrue);
  });

  test('parça ve yeni alanlar JSON ile korunur', () {
    final p = BankPassage.fromJson(_passage.toJson());
    expect(p.title, _passage.title);
    expect(p.text, _passage.text);
    expect(p.label, 'Yağmur ormanları');
    final x = BankQuestion.fromJson(q('a', passage: 'p1', multi: true, correct: {1, 3}, imgs: [null, 'img2']).toJson());
    expect(x.passageId, 'p1');
    expect(x.multiSelect, isTrue);
    expect(x.correct, {1, 3});
    expect(x.choiceImage(1), 'img2');
    expect(x.choiceImage(0), isNull);
    expect(x.hasChoiceImages, isTrue);
  });

  test('parçaya bağlı sorular birlikte kalır, karışık kitapçıkta da ayrılmaz', () {
    final list = [q('a'), q('b', passage: 'p1'), q('c'), q('d', passage: 'p1'), q('e', passage: 'p1'), q('f')];
    expect(BookletPlan.groupByPassage(list).map((x) => x.id), ['a', 'b', 'd', 'e', 'c', 'f']);
    final plan = BookletPlan.build(list, const BookletOptions(bookletCount: 4, shuffleQuestions: true, order: QuestionOrder.manual));
    for (final v in plan.variants) {
      final ids = v.test.map((p) => p.question.id).toList();
      final s = ids.indexOf('b');
      expect(ids.sublist(s, s + 3), ['b', 'd', 'e'], reason: 'kitapçık ${v.letter}: $ids');
    }
  });

  test('sınava çok doğrulu soru olarak geçer', () {
    final exam = BookletPlan.build([q('a', multi: true, correct: {0, 2}), q('b', multi: true)], const BookletOptions())
        .toExam(id: 'e', name: 'S', className: '9-A');
    expect(exam.questions[0].multiSelect, isTrue);
    // Tek doğrusu olan soru "çok doğrulu" işaretli olsa da normal kalır.
    expect(exam.questions[1].multiSelect, isFalse);
  });

  testWidgets('parçalı, görselli şıklı ve çok doğrulu kitapçık PDF', (t) async {
    await t.runAsync(() async {
      final store = BankStore.forTest()..passages.add(_passage);
      final prev = BankStore.instance;
      BankStore.instance = store;
      addTearDown(() => BankStore.instance = prev);
      // Şık görselleri: dört basit şekil.
      final shapes = <String, List<int>>{};
      for (final (i, name) in ['daire', 'kare', 'ucgen', 'yildiz'].indexed) {
        final im = img.Image(width: 160, height: 120)..clear(img.ColorRgb8(255, 255, 255));
        final c = img.ColorRgb8(40, 90 + i * 30, 200 - i * 40);
        switch (i) {
          case 0:
            img.fillCircle(im, x: 80, y: 60, radius: 44, color: c);
          case 1:
            img.fillRect(im, x1: 36, y1: 16, x2: 124, y2: 104, color: c);
          case 2:
            img.fillPolygon(im, vertices: [img.Point(80, 12), img.Point(132, 108), img.Point(28, 108)], color: c);
          default:
            img.fillRect(im, x1: 20, y1: 50, x2: 140, y2: 70, color: c);
            img.fillRect(im, x1: 70, y1: 10, x2: 90, y2: 110, color: c);
        }
        shapes[name] = img.encodePng(im);
      }
      final qs = [
        q('1', passage: 'p1', choices: ['Ormanların az yer kapladığı', 'Türlerin yarısından fazlasının ormanda yaşadığı', 'Ormanların çöl olduğu', 'Yağış olmadığı'], correct: {1}),
        q('2', passage: 'p1', choices: ['Karbondioksit tutar', 'Yağışı etkiler', 'Kumu artırır', 'Hiç ağaç yoktur'], correct: {0, 1}, multi: true),
        q('3', choices: const ['', '', '', ''], imgs: const ['daire', 'kare', 'ucgen', 'yildiz'], correct: {2})
            .copyWith(text: 'Aşağıdakilerden hangisi üçgendir?'),
        q('4', choices: ['2', '3', '4', '9'], correct: {0, 1}, multi: true).copyWith(text: 'Aşağıdakilerden hangileri asal sayıdır?'),
      ];
      final plan = BookletPlan.build(qs, const BookletOptions(title: 'Okuma parçası örneği', order: QuestionOrder.manual));
      expect(plan.passages.keys, ['p1']);
      final pdf = await buildBookletPdf(plan, school: const SchoolInfo(), image: (id) => shapes[id] == null ? null : Uint8List.fromList(shapes[id]!));
      expect(pdf.length, greaterThan(5000));
      Directory('build/bank').createSync(recursive: true);
      File('build/bank/parca_kitapcik.pdf').writeAsBytesSync(pdf);
    });
  });
}
