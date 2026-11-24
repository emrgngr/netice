import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:netice/core/models.dart';
import 'package:netice/core/store.dart';
import 'package:netice/omr/form_code.dart';
import 'package:netice/omr/form_layout.dart';
import 'package:netice/omr/form_raster.dart';
import 'package:netice/omr/omr_reader.dart';
import 'package:netice/omr/sheet_reader.dart';
import 'package:netice/reports/pdf_documents.dart';

Exam _exam(int n, {int digits = 6}) => Exam(
      id: 'quiz_mini_1',
      name: 'Kısa quiz',
      className: '9-A',
      date: DateTime(2026, 11, 24),
      choiceCount: 5,
      numberDigits: digits,
      questions: [for (var i = 0; i < n; i++) Question(no: i + 1, correct: {i % 5})],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('kısa quiz formu daire yerleşimi alanın içinde ve çakışmasız', () {
    for (final digits in [6, 10]) {
      final l = MiniFormLayout(questionCount: MiniFormLayout.maxQuestionsFor(digits), choiceCount: 5, digits: digits);
      for (var q = 0; q < l.questionCount; q++) {
        for (var c = 0; c < 5; c++) {
          final p = l.answerBubble(q, c);
          expect(p.x > 22 && p.x < 188, isTrue, reason: '$p');
          expect(p.y > 22 && p.y < 272, isTrue, reason: '$p');
        }
      }
      final lastNumber = l.studentBubble(digits - 1, 9);
      expect(l.answerBubble(0, 0).y - lastNumber.y, greaterThan(15));
      expect(l.numberPitchY, greaterThan(l.bubbleR * 2.4));
    }
    expect(() => MiniFormLayout(questionCount: 21, choiceCount: 5), throwsArgumentError);
  });

  test('kısa form ve A4 form otomatik ayırt edilip doğru okunur', () {
    final exam = _exam(12);
    final spec = ReadSpec(questions: 12, choices: 5, digits: 6);
    final answers = {for (var q = 0; q < 12; q++) q: [(q * 3) % 5]};
    // Kısa form
    final mini = FormRaster(MiniFormLayout(questionCount: 12, choiceCount: 5), pxPerMm: 4)
        .render(answers: answers, studentNumber: '001042', code: FormCode(examCode: FormCode.examCodeOf(exam.id), studentNumber: 1042));
    final rotated = img.copyRotate(mini, angle: 4);
    final r = readSheet(GrayImage.fromImage(rotated), spec);
    expect(r.mini, isTrue);
    expect(r.studentNumber, '001042');
    expect(r.code?.studentNumber, 1042);
    for (var q = 0; q < 12; q++) {
      expect(r.questions[q].answer.marked, {(q * 3) % 5}, reason: 'soru ${q + 1} ${r.questions[q].fills}');
    }
    // Ters çevrilmiş kısa form
    final r2 = readSheet(GrayImage.fromImage(img.copyRotate(mini, angle: 180)), spec);
    expect(r2.mini, isTrue);
    expect(r2.questions[5].answer.marked, {0});
    // A4 form aynı sınavla
    final a4 = FormRaster(FormLayout(questionCount: 12, choiceCount: 5, digits: 6), pxPerMm: 4)
        .render(answers: answers, studentNumber: '001042');
    final r3 = readSheet(GrayImage.fromImage(a4), spec);
    expect(r3.mini, isFalse);
    expect(r3.studentNumber, '001042');
    expect(r3.questions[4].answer.marked, {2});
  });

  test('basılı kısa quiz PDF\'i (4\'lü sayfa) kesilip okunur', () async {
    final pdftoppm = Platform.environment['PDFTOPPM'] ?? '/usr/local/bin/pdftoppm';
    if (!File(pdftoppm).existsSync() && !File('/usr/bin/pdftoppm').existsSync()) {
      markTestSkipped('pdftoppm yok');
      return;
    }
    final exe = File(pdftoppm).existsSync() ? pdftoppm : '/usr/bin/pdftoppm';
    final exam = _exam(20);
    final students = [
      for (var i = 0; i < 5; i++) Student(id: 's$i', firstName: 'Öğrenci', lastName: '$i', number: '${1040 + i}', className: '9-A')
    ];
    final bytes = await buildMiniFormsPdf(exam, students);
    final dir = Directory.systemTemp.createTempSync('mini');
    File('${dir.path}/f.pdf').writeAsBytesSync(bytes);
    final res = await Process.run(exe, ['-r', '200', '-gray', '-png', '-f', '1', '-l', '1', '${dir.path}/f.pdf', '${dir.path}/p']);
    expect(res.exitCode, 0, reason: '${res.stderr}');
    final png = dir.listSync().whereType<File>().firstWhere((f) => f.path.endsWith('.png'));
    final page = img.decodePng(png.readAsBytesSync())!;
    if (Platform.environment['MINI_PREVIEW'] != null) File(Platform.environment['MINI_PREVIEW']!).writeAsBytesSync(png.readAsBytesSync());
    // Sağ alt çeyreği kes (4. öğrenci), daireleri kalemle doldur.
    final w = page.width ~/ 2, h = page.height ~/ 2;
    final slip = img.copyCrop(page, x: w, y: h, width: page.width - w, height: page.height - h).convert(numChannels: 3);
    final layout = MiniFormLayout(questionCount: 20, choiceCount: 5);
    final px = slip.width / FormLayout.pageWidth;
    void fill(Pt p) => img.fillCircle(slip,
        x: (p.x * px).round(), y: (p.y * px).round(), radius: (layout.bubbleR * px * 0.85).round(), color: img.ColorRgb8(40, 40, 40));
    for (var q = 0; q < 20; q++) {
      if (q != 7) fill(layout.answerBubble(q, (q * 2) % 5));
    }
    const no = '001043';
    for (var d = 0; d < 6; d++) {
      fill(layout.studentBubble(d, int.parse(no[d])));
    }
    // Biraz uzaktan ve eğik çekilmiş gibi: kenar boşluğu ve döndürme.
    final canvas = img.Image(width: slip.width + 160, height: slip.height + 160, numChannels: 3);
    img.fill(canvas, color: img.ColorRgb8(150, 140, 120));
    img.compositeImage(canvas, slip, dstX: 80, dstY: 80);
    final photo = img.copyRotate(canvas, angle: -6);
    final jpg = img.decodeJpg(img.encodeJpg(photo, quality: 80))!;
    final r = readSheet(GrayImage.fromImage(jpg), const ReadSpec(questions: 20, choices: 5, digits: 6));
    expect(r.mini, isTrue);
    expect(r.studentNumber, no);
    expect(r.code?.studentNumber, 1043);
    expect(r.code?.resolve(FormCode.examCodeOf(exam.id)), isNotNull);
    for (var q = 0; q < 20; q++) {
      if (q == 7) {
        expect(r.questions[q].answer.state, MarkState.blank, reason: 'soru ${q + 1}');
      } else {
        expect(r.questions[q].answer.marked, {(q * 2) % 5}, reason: 'soru ${q + 1} ${r.questions[q].fills}');
        expect(r.questions[q].answer.state, MarkState.filled, reason: 'soru ${q + 1} ${r.questions[q].fills}');
      }
    }
    // İşaretli kâğıt çizimi kısa form yerleşimini kullanır.
    expect(layoutFor(exam, mini: true), isA<MiniFormLayout>());
    expect(layoutFor(exam), isNot(isA<MiniFormLayout>()));
    dir.deleteSync(recursive: true);
  });
}
