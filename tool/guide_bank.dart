// Kılavuz PDF'i ve videoları için dile göre örnek soru bankası
// (tool/kilavuz/ornek_banka.json).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:netice/bank/bank_models.dart';
import 'package:netice/bank/bank_store.dart';

Uint8List guideDiagram() {
  final im = img.Image(width: 640, height: 300)..clear(img.ColorRgb8(255, 255, 255));
  final ink = img.ColorRgb8(15, 27, 61);
  final coral = img.ColorRgb8(232, 97, 60);
  img.drawLine(im, x1: 40, y1: 250, x2: 600, y2: 250, color: ink, thickness: 3);
  img.fillRect(im, x1: 120, y1: 170, x2: 220, y2: 250, color: img.ColorRgb8(16, 185, 129));
  img.drawLine(im, x1: 220, y1: 210, x2: 360, y2: 210, color: ink, thickness: 3);
  img.drawLine(im, x1: 340, y1: 195, x2: 360, y2: 210, color: ink, thickness: 3);
  img.drawLine(im, x1: 340, y1: 225, x2: 360, y2: 210, color: ink, thickness: 3);
  img.drawLine(im, x1: 120, y1: 210, x2: 20, y2: 210, color: coral, thickness: 3);
  img.drawLine(im, x1: 40, y1: 195, x2: 20, y2: 210, color: coral, thickness: 3);
  img.drawLine(im, x1: 40, y1: 225, x2: 20, y2: 210, color: coral, thickness: 3);
  return Uint8List.fromList(img.encodePng(im));
}

/// Bir test sayfası görüntüsü: üstte iki soru, ortada şekil.
Uint8List guidePage(Map<String, dynamic> d) {
  final im = img.Image(width: 900, height: 1270)..clear(img.ColorRgb8(255, 255, 255));
  final ink = img.ColorRgb8(15, 27, 61);
  final gray = img.ColorRgb8(150, 158, 175);
  img.fillRect(im, x1: 0, y1: 0, x2: 900, y2: 70, color: img.ColorRgb8(15, 27, 61));
  // Satır çizgileri yazı yerine geçer.
  void lines(int y, int n) {
    for (var i = 0; i < n; i++) {
      img.fillRect(im, x1: 70, y1: y + i * 34, x2: i == n - 1 ? 520 : 830, y2: y + i * 34 + 12, color: gray);
    }
  }

  void choices(int y) {
    for (var i = 0; i < 4; i++) {
      img.drawCircle(im, x: 88, y: y + i * 40 + 6, radius: 12, color: ink);
      img.fillRect(im, x1: 120, y1: y + i * 40, x2: 300 + (i * 53) % 140, y2: y + i * 40 + 12, color: gray);
    }
  }

  img.fillRect(im, x1: 40, y1: 120, x2: 62, y2: 142, color: img.ColorRgb8(16, 185, 129));
  lines(124, 3);
  choices(240);
  img.fillRect(im, x1: 40, y1: 450, x2: 62, y2: 472, color: img.ColorRgb8(16, 185, 129));
  lines(454, 2);
  final dia = img.decodePng(guideDiagram())!;
  img.compositeImage(im, dia, dstX: 130, dstY: 540);
  choices(880);
  img.fillRect(im, x1: 40, y1: 1080, x2: 62, y2: 1102, color: img.ColorRgb8(16, 185, 129));
  lines(1084, 3);
  return Uint8List.fromList(img.encodePng(im));
}

Map<String, dynamic> guideBankData(String lang) {
  final all = jsonDecode(File('tool/kilavuz/ornek_banka.json').readAsStringSync()) as Map<String, dynamic>;
  return (all[lang] ?? all['en']) as Map<String, dynamic>;
}

Future<void> seedGuideBank(BankStore b, String lang) async {
  final d = guideBankData(lang);
  final now = DateTime.now();
  final subject = d['ders'] as String;
  final grade = d['sinif'] as String;
  final topics = (d['konular'] as List).cast<String>();
  final pic = await b.saveImage(guideDiagram());
  var n = 0;
  final qs = <BankQuestion>[];
  for (final q in d['sorular'] as List) {
    final i = n++;
    final ch = (q[3] as List).cast<String>();
    qs.add(BankQuestion(
      id: 'bq$i',
      subject: subject,
      grade: grade,
      topic: topics[q[0] as int],
      difficulty: Difficulty.values[q[1] as int],
      text: q[2] as String,
      choices: ch,
      choiceCount: ch.length,
      correct: {q[4] as int},
      solution: q[5] as String,
      imageId: i == 2 ? pic : null,
      tags: i % 3 == 0 ? const ['quiz'] : const [],
      favorite: i == 3,
      created: now.subtract(Duration(hours: i)),
      updated: now,
    ));
  }
  b.addQuestions(qs);
  final open = d['acik'] as List;
  b.upsertQuestion(BankQuestion(
    id: 'bq_open',
    subject: subject,
    grade: grade,
    topic: topics[2],
    type: QuestionType.open,
    text: open[0] as String,
    answerText: open[1] as String,
    answerLines: 5,
    points: 10,
    created: now.subtract(const Duration(hours: 20)),
    updated: now,
  ));
  var k = 0;
  b.addNotes([
    for (final nt in d['notlar'] as List)
      BankNote(
        id: 'n${++k}',
        kind: nt[0] == 'summary' ? NoteKind.summary : NoteKind.tip,
        subject: subject,
        grade: grade,
        topic: topics[nt[1] as int],
        title: nt[2] as String,
        body: nt[3] as String,
        created: now.subtract(Duration(hours: k)),
        updated: now,
      ),
  ]);
  final bk = d['kitapcik'] as List;
  b.upsertBooklet(Booklet(
    id: 'k1',
    name: bk[0] as String,
    questionIds: [for (var i = 0; i < qs.length; i++) 'bq$i', 'bq_open'],
    options: BookletOptions(title: bk[1] as String, bookletCount: 2, shuffleChoices: true),
    created: now,
    updated: now,
  ));
}
