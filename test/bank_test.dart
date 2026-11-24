import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:netice/bank/bank_analysis.dart';
import 'package:netice/bank/bank_models.dart';
import 'package:netice/bank/bank_store.dart';
import 'package:netice/bank/booklet_builder.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/scoring.dart';
import 'package:netice/reports/booklet_pdf.dart';

BankQuestion q(String id, {String subject = 'Fizik', String topic = 'Kuvvet', Difficulty d = Difficulty.medium, int correct = 0, List<String>? choices, QuestionType type = QuestionType.multiple}) =>
    BankQuestion(
      id: id,
      subject: subject,
      topic: topic,
      difficulty: d,
      type: type,
      text: 'Soru $id: Aşağıdakilerden hangisi doğrudur?',
      choices: choices ?? ['Birinci şık $id', 'İkinci', 'Üçüncü', 'Dördüncü', 'Yukarıdakilerin hepsi'],
      correct: type.optical ? {correct} : const {},
      answerText: type.optical ? '' : 'Beklenen cevap',
      created: DateTime(2026),
      updated: DateTime(2026),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('banka kaydedilir ve yeniden yüklenir', () async {
    final dir = await Directory.systemTemp.createTemp('bank');
    final b = BankStore.forTest();
    await b.load(dir: dir);
    final img = await b.saveImage(Uint8List.fromList([0xFF, 0xD8, 1, 2, 3]));
    b.upsertQuestion(q('a').copyWith(imageId: img));
    b.upsertNote(b.newNote(kind: NoteKind.tip).copyWith(topic: 'Kuvvet', body: 'F = m·a'));
    await b.save();
    final c = BankStore.forTest();
    await c.load(dir: dir);
    expect(c.questions.single.imageId, img);
    expect(c.imageBytes(img), isNotNull);
    expect(c.notesFor('kuvvet').single.body, 'F = m·a');
    // Kütüphane dipnotu: kapladığı yer en az görsel + banka dosyası kadar.
    expect(await c.diskUsage(), greaterThan(5));
    expect(await BankStore.forTest().diskUsage(), 0);
    final pack = c.exportPack();
    final d = BankStore.forTest();
    await d.load(dir: await Directory.systemTemp.createTemp('bank2'));
    final (nq, nn, _) = await d.importPack(pack);
    expect((nq, nn), (1, 1));
    expect(d.imageBytes(d.questions.single.imageId), isNotNull);
  });

  test('otomatik seçim zorluk oranına ve konulara uyar', () {
    final pool = [
      for (var i = 0; i < 30; i++)
        q('e$i', d: Difficulty.easy, topic: 'T${i % 3}'),
      for (var i = 0; i < 30; i++)
        q('m$i', d: Difficulty.medium, topic: 'T${i % 3}'),
      for (var i = 0; i < 30; i++)
        q('h$i', d: Difficulty.hard, topic: 'T${i % 3}'),
    ];
    final r = BankStore.autoPick(pool, const AutoPick(count: 20, easyPct: 30, mediumPct: 50, hardPct: 20));
    expect(r.length, 20);
    expect(r.where((x) => x.difficulty == Difficulty.easy).length, 6);
    expect(r.where((x) => x.difficulty == Difficulty.medium).length, 10);
    expect(r.where((x) => x.difficulty == Difficulty.hard).length, 4);
    final perTopic = {for (final t in ['T0', 'T1', 'T2']) t: r.where((x) => x.topic == t).length};
    expect(perTopic.values.every((v) => v >= 6), isTrue, reason: '$perTopic');
  });

  test('karışık şıklı kitapçık okununca A anahtarıyla doğru puanlanır', () {
    final qs = [for (var i = 0; i < 12; i++) q('q$i', correct: i % 4, subject: i < 6 ? 'Fizik' : 'Kimya')];
    final plan = BookletPlan.build(qs, const BookletOptions(bookletCount: 4, shuffleQuestions: true, shuffleChoices: true));
    final exam = plan.toExam(id: 'e', name: 'Deneme', className: '9-A');
    expect(exam.bookletCount, 4);
    expect(exam.bookletChoiceOrders, isNotEmpty);
    for (final v in plan.variants) {
      // "Hepsi" şıkkı hep sonda.
      for (final p in v.test) {
        expect(p.choiceOrder.last, 4);
      }
      // Öğrenci kendi kitapçığında hep doğru şıkkı işaretlesin.
      final printed = [for (final p in v.test) Answer.choice(p.printedCorrect.first)];
      expect(exam.questionsOf(v.index).map((x) => x.correct.first).toList(), [for (final p in v.test) p.printedCorrect.first]);
      final sheet = Sheet(examId: 'e', studentId: 's', answers: exam.toMasterOrder(v.index, printed), booklet: v.index);
      final r = Scorer.score(exam, sheet);
      expect(r.correct, 12, reason: 'kitapçık ${v.letter}');
      expect(r.score, 100);
    }
    final rt = Exam.fromJson(exam.toJson());
    expect(rt.bookletChoiceOrders.length, 3);
    expect(rt.questions.first.bankId, isNotNull);
  });

  test('klasik sorular sınava klasik olarak geçer ve puan toplamı korunur', () {
    final qs = [
      for (var i = 0; i < 9; i++) q('t$i'),
      q('o1', type: QuestionType.open),
      q('o2', type: QuestionType.fill),
    ];
    final plan = BookletPlan.build(qs, const BookletOptions(totalScore: 100));
    final exam = plan.toExam(id: 'e', name: 'x', className: 'y');
    expect(exam.questions.length, 9);
    expect(exam.openQuestions.length, 2);
    expect(exam.rule.maxScore, closeTo(100, 0.001));
  });

  testWidgets('kitapçık PDF üretilir', (t) async {
    await t.runAsync(() async {
      final qs = [
        for (var i = 0; i < 30; i++) q('q$i', subject: i < 15 ? 'Fizik' : 'Kimya'),
        q('o', type: QuestionType.open),
      ];
      final plan = BookletPlan.build(qs, const BookletOptions(title: 'Deneme', bookletCount: 2, shuffleChoices: true));
      final pdf = await buildBookletPdf(plan,
          school: const SchoolInfo(), image: (_) => null, parts: const BookletPdfParts(answerKey: true, solutions: true));
      expect(pdf.length, greaterThan(5000));
      Directory('build/bank').createSync(recursive: true);
      File('build/bank/kitapcik.pdf').writeAsBytesSync(pdf);
    });
  });

  test('sonuçlardan gerçek zorluk, zayıf konu ve karne önerisi', () {
    final b = BankStore.forTest();
    final qs = [for (var i = 0; i < 4; i++) q('q$i', topic: i < 2 ? 'Kuvvet' : 'Enerji', d: Difficulty.easy)];
    b.addQuestions(qs);
    b.addNotes([
      BankNote(id: 'n1', kind: NoteKind.tip, subject: 'Fizik', topic: 'Enerji', title: 'Korunum', body: 'Enerji korunur.',
          created: DateTime(2026), updated: DateTime(2026)),
    ]);
    final exam = BookletPlan.build(qs, const BookletOptions()).toExam(id: 'e', name: 'S', className: '9-A');
    // 10 öğrenci: Kuvvet hep doğru, Enerji hep yanlış.
    final results = [
      for (var s = 0; s < 10; s++)
        Scorer.score(exam, Sheet(examId: 'e', studentId: 's$s', answers: [for (var i = 0; i < 4; i++) Answer.choice(i < 2 ? 0 : 1)])),
    ];
    final stats = BankAnalysis.itemStats([(exam, results)]);
    expect(stats['q0']!.p, 1.0);
    expect(stats['q2']!.p, 0.0);
    final mis = BankAnalysis.mislabeled(b.questions, stats);
    expect(mis.map((m) => m.$1.id).toSet(), {'q2', 'q3'});
    expect(mis.first.$2.measured, Difficulty.hard);
    final weak = BankAnalysis.weakTopics(exam, results, b);
    expect(weak.single.topic, 'Enerji');
    expect(weak.single.notes.single.id, 'n1');
    final study = BankAnalysis.studyTopics(exam, results, b, only: ['s3']);
    expect(study.keys, ['s3']);
    expect(study['s3']!.single.$3.single, 'Korunum: Enerji korunur.');
    final cover = BankAnalysis.coverage(b, stats: stats);
    expect(cover.firstWhere((c) => c.topic == 'Enerji').tips, 1);
    expect(cover.firstWhere((c) => c.topic == 'Kuvvet').p, 1.0);
  });
}
