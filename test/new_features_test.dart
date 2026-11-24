import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netice/bank/bank_models.dart';
import 'package:netice/bank/bank_store.dart';
import 'package:netice/bank/booklet_builder.dart';
import 'package:netice/bank/personal_review.dart';
import 'package:netice/core/common_exam.dart';
import 'package:netice/core/import_export.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/scoring.dart';
import 'package:netice/core/store.dart';
import 'package:netice/core/term.dart';
import 'package:netice/reports/pdf_documents.dart';
import 'package:netice/reports/booklet_docx.dart';
import 'package:netice/reports/review_pdf.dart';
import 'package:netice/ui/parent_send_screen.dart' show whatsappNumber;

BankQuestion q(String id, {String topic = 'Kuvvet', Difficulty d = Difficulty.medium, int correct = 0, QuestionType type = QuestionType.multiple, String? imageId}) =>
    BankQuestion(
      id: id,
      subject: 'Fizik',
      topic: topic,
      difficulty: d,
      type: type,
      text: 'Soru $id: <a> & "b" hangisi?',
      choices: type == QuestionType.multiple ? ['Bir $id', 'İki', 'Üç', 'Dört'] : const [],
      correct: type.optical ? {correct} : const {},
      answerText: type.optical ? '' : 'Beklenen',
      imageId: imageId,
      created: DateTime(2026),
      updated: DateTime(2026),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('kişiye özel tekrar testi yalnız kaçırılan konulardan, sınavda olmayan sorular seçer', () async {
    final b = BankStore.forTest();
    final inExam = [q('k1', topic: 'Kuvvet'), q('k2', topic: 'Kuvvet'), q('e1', topic: 'Enerji'), q('e2', topic: 'Enerji')];
    final extra = [
      for (var i = 0; i < 5; i++) q('kx$i', topic: 'Kuvvet', d: i < 2 ? Difficulty.easy : Difficulty.hard),
      for (var i = 0; i < 5; i++) q('ex$i', topic: 'Enerji'),
      q('ox', topic: 'Optik'),
    ];
    b.addQuestions([...inExam, ...extra]);
    b.addNotes([
      BankNote(id: 'n1', kind: NoteKind.tip, subject: 'Fizik', topic: 'Kuvvet', title: 'Newton', body: 'F = m·a',
          created: DateTime(2026), updated: DateTime(2026)),
    ]);
    final exam = BookletPlan.build(inExam, const BookletOptions()).toExam(id: 'e', name: 'Sınav', className: '9-A');
    final students = {
      for (var i = 0; i < 3; i++) 's$i': Student(id: 's$i', firstName: 'Öğr', lastName: '$i', number: '$i', className: '9-A')
    };
    // s0: Kuvvet'in ikisi yanlış; s1: hepsi doğru; s2: Enerji'den biri boş.
    List<Answer> ans(List<int> picks) => [for (final p in picks) p < 0 ? const Answer.blank() : Answer.choice(p)];
    final results = [
      Scorer.score(exam, Sheet(examId: 'e', studentId: 's0', answers: ans([1, 1, 0, 0]))),
      Scorer.score(exam, Sheet(examId: 'e', studentId: 's1', answers: ans([0, 0, 0, 0]))),
      Scorer.score(exam, Sheet(examId: 'e', studentId: 's2', answers: ans([0, 0, 0, -1]))),
    ];
    expect(PersonalReview.coverableTopics(exam, b), 2);
    final r = PersonalReview.build(exam, results, students, b, o: const ReviewOptions(perStudent: 10, perTopic: 3));
    expect(r.map((x) => x.student.id), ['s0', 's2']);
    final s0 = r.first;
    expect(s0.topics, ['Kuvvet']);
    expect(s0.missed, [1, 2]);
    expect(s0.questions.length, 3);
    expect(s0.questions.every((x) => x.topic == 'Kuvvet' && x.id.startsWith('kx')), isTrue);
    // Kaçırılan orta zorlukta: önce kolay/orta sorular.
    expect(s0.questions.first.difficulty, Difficulty.easy);
    final s2 = r.last;
    expect(s2.topics, ['Enerji']);
    expect(s2.questions.length, 2);
    expect(s2.questions.every((x) => x.id.startsWith('ex')), isTrue);
    // Tek öğrenci
    expect(PersonalReview.build(exam, results, students, b, only: {'s2'}).single.student.id, 's2');

    final pdf = await buildPersonalReviewPdf(r,
        exam: exam, school: const SchoolInfo(), image: (_) => null, tipsFor: (t) => b.notesFor(t));
    expect(utf8.decode(pdf.sublist(0, 5), allowMalformed: true), '%PDF-');
    expect(pdf.length, greaterThan(3000));
  });

  test('kitapçık Word (.docx) dosyası geçerli bir belge olarak açılır', () async {
    final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFklEQVR4nGP8z8DAwMDAxMDAwMDAAAANHQEDasKb6QAAAABJRU5ErkJggg==');
    final qs = [
      q('a', imageId: 'img1'),
      q('b', correct: 2),
      q('c', type: QuestionType.trueFalse, correct: 1),
      q('d', type: QuestionType.open),
    ];
    final plan = BookletPlan.build(
        qs, const BookletOptions(title: 'Deneme & sınav', bookletCount: 2, shuffleQuestions: true, columns: 2, studentBox: true));
    final bytes = buildBookletDocx(plan,
        school: const SchoolInfo(name: 'Atatürk Lisesi'), image: (id) => id == 'img1' ? Uint8List.fromList(png) : null);
    final zip = ZipDecoder().decodeBytes(bytes);
    final names = zip.files.map((f) => f.name).toSet();
    expect(names, containsAll(['[Content_Types].xml', '_rels/.rels', 'word/document.xml', 'word/styles.xml', 'word/media/image1.png']));
    final doc = utf8.decode(zip.files.firstWhere((f) => f.name == 'word/document.xml').content as List<int>);
    expect(doc, contains('Deneme &amp; sınav'));
    expect(doc, contains('&lt;a&gt;'));
    expect(doc, contains('w:num="2"'));
    // Geçerli XML mi? (Python varsa python-docx ile açılır.)
    final dir = Directory.systemTemp.createTempSync('docx');
    final f = File('${dir.path}/k.docx')..writeAsBytesSync(bytes);
    if (Platform.environment['DOCX_OUT'] != null) f.copySync(Platform.environment['DOCX_OUT']!);
    final py = await Process.run('python3', [
      '-c',
      'import sys,docx; d=docx.Document(sys.argv[1]); print(len(d.paragraphs)); print(len(d.inline_shapes))',
      f.path
    ]).catchError((_) => ProcessResult(0, 0, 'skip', ''));
    if ('${py.stdout}'.contains('skip') || '${py.stderr}'.contains('No module')) return;
    expect(py.exitCode, 0, reason: '${py.stderr}');
    final lines = '${py.stdout}'.trim().split('\n');
    expect(int.parse(lines[0]), greaterThan(20));
    expect(int.parse(lines[1]), 2); // A ve B kitapçığında birer görsel
  });

  test('veli telefonu: Excel sütunu, WhatsApp biçimi ve ortak sınav dosyasına yazılmaması', () {
    final rows = [
      ['Okul No', 'Adı', 'Soyadı', 'Sınıf', 'Veli Telefonu'],
      ['12', 'Ali', 'Kaya', '9-A', '0532 111 22 33'],
    ];
    final list = StudentImport.parseRows(rows);
    expect(list.single.parentPhone, '0532 111 22 33');
    expect(whatsappNumber('0532 111 22 33'), '905321112233');
    expect(whatsappNumber('532 111 22 33'), '905321112233');
    expect(whatsappNumber('+49 151 2345678', country: 'de'), '491512345678');
    expect(whatsappNumber('12'), isNull);
    final st = list.single;
    expect(Student.fromJson(st.toJson()).parentPhone, '0532 111 22 33');
    expect(st.copyWith(parentPhone: '').toJson().containsKey('parentPhone'), isFalse);
    expect(exportCommonResults, isNotNull);
  });

  test('kazanım takip çizelgesi sınav sınav kazanım başarısını ve eğilimi çıkarır', () async {
    final store = AppStore();
    final st = [for (var i = 0; i < 4; i++) Student(id: 's$i', firstName: 'Ö', lastName: '$i', number: '${i + 1}', className: '9-A')];
    store.students.addAll(st);
    Exam ex(String id, DateTime d) => Exam(id: id, name: 'Sınav $id', className: '9-A', date: d, choiceCount: 4, questions: [
          Question(no: 1, correct: {0}, outcomeCode: 'Kuvvet'),
          Question(no: 2, correct: {0}, outcomeCode: 'Kuvvet'),
          Question(no: 3, correct: {0}, outcomeCode: id == 'e1' ? 'Enerji' : 'Optik'),
        ]);
    final e1 = ex('e1', DateTime(2026, 10, 1)), e2 = ex('e2', DateTime(2026, 11, 1));
    store.exams.addAll([e1, e2]);
    for (var i = 0; i < 4; i++) {
      // 1. sınavda Kuvvet'i yalnız s0 bilir; 2. sınavda herkes.
      store.sheets.add(Sheet(examId: 'e1', studentId: 's$i', answers: [Answer.choice(i == 0 ? 0 : 1), Answer.choice(i == 0 ? 0 : 1), Answer.choice(0)]));
      store.sheets.add(Sheet(examId: 'e2', studentId: 's$i', answers: [Answer.choice(0), Answer.choice(0), Answer.choice(1)]));
    }
    final t = TermReport.build(store, '9-A', Term('1. dönem', DateTime(2026, 9), DateTime(2027, 2)), [e1, e2]);
    final track = OutcomeTrack.build(t);
    expect(track.codes, ['Kuvvet', 'Enerji', 'Optik']);
    expect(track.byExam[0], [0.25, 1.0]);
    expect(track.byExam[1], [1.0, null]);
    expect(track.trend(0), 75);
    expect(track.trend(1), isNull);
    expect(track.masteredOf('s0'), (2, 3));
    final pdf = await buildOutcomeTrackingPdf(t);
    if (Platform.environment['TRACK_OUT'] != null) File(Platform.environment['TRACK_OUT']!).writeAsBytesSync(pdf);
    expect(pdf.length, greaterThan(3000));
  });
}
