import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netice/bank/bank_models.dart';
import 'package:netice/bank/bank_store.dart';
import 'package:netice/bank/blueprint.dart';
import 'package:netice/bank/booklet_builder.dart';
import 'package:netice/bank/makeup.dart';
import 'package:netice/core/import_export.dart';
import 'package:netice/core/mastery.dart';
import 'package:netice/core/misconceptions.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/scoring.dart';
import 'package:netice/core/store.dart';
import 'package:netice/core/teaching.dart';
import 'package:netice/l10n/l10n.dart';
import 'package:netice/reports/pdf_documents.dart';
import 'package:netice/ui/transfer_ui.dart';

BankQuestion bq(String id,
        {String topic = 'Kesirler',
        Difficulty d = Difficulty.medium,
        int correct = 0,
        CognitiveLevel level = CognitiveLevel.none,
        List<String>? choices,
        String? text,
        List<String> mis = const []}) =>
    BankQuestion(
      id: id,
      subject: 'Matematik',
      topic: topic,
      difficulty: d,
      cognitive: level,
      text: text ?? 'Soru $id: hangisi doğrudur?',
      choices: choices ?? ['a$id', 'b$id', 'c$id', 'd$id'],
      correct: {correct},
      misconceptions: mis,
      created: DateTime(2026),
      updated: DateTime(2026),
    );

Sheet sheet(String student, List<int?> marks, {int booklet = 0}) => Sheet(
      examId: 'e',
      studentId: student,
      answers: [for (final m in marks) m == null ? const Answer.blank() : Answer.choice(m)],
      booklet: booklet,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('düşünme düzeyi JSON ve Excel ayrıştırma', () {
    final q = bq('1', level: CognitiveLevel.analyze, mis: ['', 'Paydaları topluyor', '', '']);
    final back = BankQuestion.fromJson(q.toJson());
    expect(back.cognitive, CognitiveLevel.analyze);
    expect(back.misconceptionOf(1), 'Paydaları topluyor');
    expect(back.misconceptionOf(0), '', reason: 'doğru şıkta yanılgı olmaz');
    expect(CognitiveLevel.parse('Uygulama'), CognitiveLevel.apply);
    expect(CognitiveLevel.parse('remember'), CognitiveLevel.remember);
    expect(CognitiveLevel.parse('5'), CognitiveLevel.evaluate);
    expect(CognitiveLevel.parse(''), CognitiveLevel.none);
  });

  test('belirtke tablosu ve yorumları', () {
    final qs = [
      for (var i = 0; i < 7; i++) bq('r$i', level: CognitiveLevel.remember),
      bq('u', level: CognitiveLevel.understand, topic: 'Ondalık'),
      bq('n', topic: 'Oran'),
    ];
    final bp = Blueprint.of(qs);
    expect(bp.topics, ['Kesirler', 'Ondalık', 'Oran']);
    expect(bp.levelTotal(CognitiveLevel.remember), 7);
    expect(bp.tagged, 8);
    expect(bp.remarks.join(' '), contains('ezber'));
    expect(bp.remarks.join(' '), contains('Analiz'));
  });

  test('soru kontrolü: cevap dağılımı, art arda aynı cevap, olumsuz kök, en uzun şık', () {
    final qs = [
      for (var i = 0; i < 10; i++)
        bq('$i',
            correct: i < 6 ? 2 : i % 4,
            choices: ['kısa', 'kısa', 'çok daha uzun doğru cevap metni', 'kısa'],
            text: i == 0 ? 'Aşağıdakilerden hangisi doğru değildir?' : 'Soru $i nedir?'),
    ];
    final plan = BookletPlan.build(qs, const BookletOptions(title: 'T', bookletCount: 1));
    final issues = QualityCheck.run(plan);
    final titles = issues.map((i) => i.title).join(' | ');
    expect(titles, contains('C şıkkı'));
    expect(titles, contains('hep C'));
    expect(titles, contains('Olumsuz'));
    expect(titles, contains('en uzun'));
    // Büyük harfle yazılmış olumsuz kök uyarı vermez.
    final ok = QualityCheck.run(BookletPlan.build(
        [for (var i = 0; i < 4; i++) bq('$i', correct: i % 4, text: 'Hangisi DEĞİLDİR?')], const BookletOptions(title: 'T')));
    expect(ok.where((i) => i.title.contains('Olumsuz')), isEmpty);
  });

  test('kavram yanılgısı: kitapçığa ve şık karışımına rağmen doğru öğrenciler bulunur', () {
    final qs = [
      bq('1', correct: 0, mis: ['', 'Paydaları topluyor', '', 'Payı ve paydayı karıştırıyor']),
      bq('2', correct: 1, mis: ['Paydaları topluyor', '', '', '']),
      bq('3', correct: 2),
    ];
    final plan = BookletPlan.build(qs, const BookletOptions(title: 'T', bookletCount: 2, shuffleQuestions: true, shuffleChoices: true, seed: 7));
    final exam = plan.toExam(id: 'e', name: 'Kesir', className: '5-A');
    expect(exam.questions[0].misconceptions, {1: 'Paydaları topluyor', 3: 'Payı ve paydayı karıştırıyor'});
    expect(Exam.fromJson(exam.toJson()).questions[1].misconceptions, {0: 'Paydaları topluyor'});

    // B kitapçığındaki öğrenci A'nın 2. sorusunda A'daki 0. şıkkı (yanılgı) işaretlesin.
    final b = plan.variants[1];
    final printed = List<int?>.filled(3, null);
    for (var i = 0; i < b.test.length; i++) {
      final master = plan.testMaster.indexOf(b.test[i].question);
      if (master == 1) printed[i] = b.test[i].choiceOrder.indexOf(0);
      if (master == 0) printed[i] = b.test[i].choiceOrder.indexOf(0); // doğru
    }
    final raw = sheet('s2', printed, booklet: 1);
    final s2 = raw.copyWith(answers: exam.toMasterOrder(1, raw.answers));
    final s1 = sheet('s1', [1, 0, 2]);
    final f = Misconceptions.of(exam, [s1, s2]);
    expect(f.first.text, 'Paydaları topluyor');
    expect(f.first.students, {'s1', 's2'});
    expect(Misconceptions.ofSheet(exam, s1), ['Paydaları topluyor']);
  });

  test('çalışma grupları ve benzer yanlış uyarısı', () {
    final key = [for (var i = 0; i < 12; i++) i % 4];
    final exam = Exam(
      id: 'e',
      name: 'S',
      className: '7-A',
      date: DateTime(2026, 3),
      choiceCount: 4,
      questions: [for (var i = 0; i < 12; i++) Question(no: i + 1, correct: {key[i]}, outcomeCode: i < 6 ? 'Kesir' : 'Oran')],
      rule: const ScoringRule(maxScore: 100),
    );
    List<int?> answers(int correctCount, {int wrong = 0}) =>
        [for (var i = 0; i < 12; i++) i < correctCount ? key[i] : (key[i] + 1 + wrong) % 4];
    final sheets = [
      sheet('a', answers(12)),
      sheet('b', answers(11)),
      sheet('c', answers(8)),
      sheet('d', answers(7)),
      // İki öğrenci aynı 8 yanlışı yapıyor.
      sheet('e', answers(4)),
      sheet('f', answers(4)),
      sheet('g', answers(3, wrong: 1)),
      sheet('h', answers(5, wrong: 2)),
    ];
    final results = Scorer.scoreAll(exam, sheets);
    final groups = StudyGroups.of(exam, results);
    expect(groups.map((g) => g.tier), [StudyTier.support, StudyTier.reinforce, StudyTier.enrich]);
    expect(groups.first.members.map((r) => r.sheet.studentId).toSet(), {'e', 'f', 'g', 'h'});
    expect(groups.first.weakOutcomes.first.$1, 'Oran');
    final pairs = SimilarAnswers.of(exam, results);
    expect(pairs, isNotEmpty);
    expect({pairs.first.a.sheet.studentId, pairs.first.b.sheet.studentId}, {'e', 'f'});
    expect(pairs.first.sameWrong.length, 8);
  });

  test('ustalık: iki sınavda %80 öğrenildi; 3 hafta sorulmayan hatırlatılır', () {
    expect(Mastery.statusOf([0.9, 0.85]), MasteryStatus.mastered);
    expect(Mastery.statusOf([0.9, 0.6]), MasteryStatus.developing);
    expect(Mastery.statusOf([0.3]), MasteryStatus.notYet);
    final store = AppStore()..seedDemo();
    final exam = store.exams.first;
    final outcomes = Mastery.of(store, exam.className);
    expect(outcomes, isNotEmpty);
    final due = Mastery.dueForReview(outcomes, DateTime.now().add(const Duration(days: 60)));
    expect(due.every((o) => o.status != MasteryStatus.notYet || o.slipping), isTrue);
  });

  test('eşdeğer telafi sınavı aynı konu ve zorlukta başka soru seçer', () {
    final b = BankStore.forTest();
    final source = [bq('a', topic: 'Kesirler', d: Difficulty.easy), bq('b', topic: 'Oran', d: Difficulty.hard), bq('c', topic: 'Yalnız')];
    for (final q in [...source, bq('a2', topic: 'Kesirler', d: Difficulty.easy), bq('b2', topic: 'Oran', d: Difficulty.medium)]) {
      b.questions.add(q);
    }
    final exam = BookletPlan.build(source, const BookletOptions(title: 'T')).toExam(id: 'e', name: 'S', className: '5-A');
    final plan = Makeup.build(exam, b);
    expect(plan.questions.map((q) => q.id).toList(), ['a2', 'b2', 'c']);
    expect(plan.kept, 1);
    expect(plan.relaxed, 1);
  });

  test('ölçütlü puanlama, öğrenci alanları ve dil kodu', () {
    const c = RubricCriterion(name: 'Çözüm yolu', maxPoints: 4, descriptors: ['a', 'b', 'c', 'd']);
    expect([for (var l = -1; l < 4; l++) c.pointsAt(l)], [0, 1, 2, 3, 4]);
    final oq = OpenQuestion(label: 'K1', maxPoints: 4, rubric: [c]);
    expect(OpenQuestion.fromJson(oq.toJson()).rubric.single.descriptor(2), 'c');
    final sh = const Sheet(examId: 'e', answers: [], openScores: [3], rubricLevels: {0: [2]});
    expect(Sheet.fromJson(sh.toJson()).rubricLevels, {0: [2]});

    const st = Student(id: 's', firstName: 'A', lastName: 'B', number: '1', className: '5-A', parentLanguage: 'ar', goal: 75);
    final back = Student.fromJson(st.toJson());
    expect(back.parentLanguage, 'ar');
    expect(back.goal, 75);
    expect(back.copyWith(clearGoal: true).goal, isNull);
    expect(StudentImport.languageCodeOf('Arapça'), 'ar');
    expect(StudentImport.languageCodeOf('Deutsch'), 'de');
    expect(StudentImport.languageCodeOf('ko'), 'ko');
  });

  test('kazanım listesi metinden ve tablodan okunur', () {
    final items = OutcomeList.parseLines('M.5.1.1.1. Milyonlu sayıları okur.\nF.9.2.1 Net kuvveti açıklar\nKodsuz kazanım');
    expect(items[0], ('M.5.1.1.1', 'Milyonlu sayıları okur.'));
    expect(items[1].$1, 'F.9.2.1');
    expect(items[2], ('', 'Kodsuz kazanım'));
    final rows = OutcomeList.parseRows([
      ['Kod', 'Kazanım'],
      ['T.1.1', 'Okur'],
      ['T.1.2', 'Yazar'],
    ]);
    expect(rows, [('T.1.1', 'Okur'), ('T.1.2', 'Yazar')]);
  });

  test('velinin dilinde karne: dil geri alınır ve PDF üretilir', () async {
    L10n.use('tr');
    final store = AppStore()..seedDemo();
    final exam = store.examById('demo_exam')!;
    final results = store.resultsOf(exam);
    final id = results.first.sheet.studentId!;
    final bytes = await inLanguage('de', () async {
      expect(tr('Öğrenci karnesi'), isNot('Öğrenci karnesi'));
      return buildStudentCardsPdf(exam: exam, results: results, students: store.studentById, onlyStudentId: id);
    });
    expect(L10n.code, 'tr');
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('gruplar, değerlendirme kâğıdı ve devir dosyası PDF olarak üretilir', () async {
    final store = AppStore()..seedDemo();
    final exam = store.examById('demo_exam')!;
    final results = store.resultsOf(exam);
    final groups = await buildStudyGroupsPdf(exam: exam, groups: StudyGroups.of(exam, results), students: store.studentById);
    final wrapper = await buildReflectionPdf(exam: exam, results: results, students: store.studentById);
    final mastery = Mastery.of(store, exam.className);
    final transfer = await buildTransferPdf(entries: [
      for (final s in store.studentsOf(exam.className).take(3)) transferEntryOf(store, s, mastery),
    ]);
    final out = Directory('build/test_output')..createSync(recursive: true);
    for (final (name, b) in [('calisma_gruplari', groups), ('degerlendirme_kagidi', wrapper), ('devir_dosyasi', transfer)]) {
      expect(String.fromCharCodes(b.take(5)), '%PDF-');
      File('${out.path}/$name.pdf').writeAsBytesSync(b);
    }
  });
}
