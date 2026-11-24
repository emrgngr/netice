// Çocuk (ilkokul) şablonu önizlemesi: flutter test tool/kid_preview_test.dart
// Çıktılar: build/kid/kitapcik.pdf, build/kid/kartlar.pdf
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:netice/bank/bank_models.dart';
import 'package:netice/bank/booklet_builder.dart';
import 'package:netice/core/models.dart';
import 'package:netice/l10n/l10n.dart';
import 'package:netice/reports/booklet_pdf.dart';
import 'package:netice/reports/kid_pdf.dart';

/// Basit bir bitki büyüme çizimi (tohum → filiz → fide → olgun bitki).
Uint8List plantPicture() {
  final im = img.Image(width: 720, height: 230)..clear(img.ColorRgb8(255, 255, 255));
  final soil = img.ColorRgb8(201, 154, 107), seed = img.ColorRgb8(138, 90, 51), leaf = img.ColorRgb8(124, 194, 90);
  final stem = img.ColorRgb8(78, 154, 59), red = img.ColorRgb8(239, 79, 79);
  img.fillRect(im, x1: 10, y1: 160, x2: 710, y2: 195, color: soil, radius: 14);
  img.fillCircle(im, x: 80, y: 165, radius: 18, color: seed);
  // filiz
  img.fillCircle(im, x: 250, y: 165, radius: 15, color: seed);
  img.drawLine(im, x1: 250, y1: 160, x2: 250, y2: 128, color: stem, thickness: 6);
  img.fillCircle(im, x: 236, y: 126, radius: 11, color: leaf);
  img.fillCircle(im, x: 264, y: 126, radius: 11, color: leaf);
  // fide
  img.drawLine(im, x1: 430, y1: 162, x2: 430, y2: 70, color: stem, thickness: 8);
  for (final (x, y) in [(405, 110), (455, 95), (430, 62)]) {
    img.fillCircle(im, x: x, y: y, radius: 17, color: leaf);
  }
  // olgun bitki
  img.drawLine(im, x1: 620, y1: 162, x2: 620, y2: 30, color: stem, thickness: 9);
  for (final (x, y) in [(588, 120), (652, 100), (590, 70), (650, 48)]) {
    img.fillCircle(im, x: x, y: y, radius: 20, color: leaf);
  }
  for (final (x, y) in [(600, 95), (640, 75), (612, 45)]) {
    img.fillCircle(im, x: x, y: y, radius: 13, color: red);
  }
  final ink = img.ColorRgb8(43, 58, 103);
  for (final (i, x) in [(1, 80), (2, 250), (3, 430), (4, 620)]) {
    img.drawString(im, '$i', font: img.arial24, x: x - 6, y: 200, color: ink);
  }
  return Uint8List.fromList(img.encodePng(im));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('çocuk kitapçığı ve cevap kartları', (t) async {
    await t.runAsync(() async {
      L10n.use(const String.fromEnvironment('LANG_SHOT', defaultValue: 'tr'));
      final now = DateTime(2026, 11, 24);
      var n = 0;
      BankQuestion q(String text, List<String> ch, int ok, {String? imageId}) => BankQuestion(
            id: 'k${n++}',
            subject: 'Fen Bilimleri',
            grade: '3. sınıf',
            topic: 'Canlıların yaşam döngüsü',
            difficulty: Difficulty.easy,
            text: text,
            choices: ch,
            choiceCount: ch.length,
            correct: {ok},
            imageId: imageId,
            created: now,
            updated: now,
          );
      final qs = [
        q('Bir canlının doğumundan ölümüne kadar geçirdiği aşamalara ne ad verilir?', ['Beslenme', 'Yaşam döngüsü', 'Solunum'], 1),
        q('Hangisi kurbağanın yaşam döngüsünde YOKTUR?', ['Yumurta', 'İribaş', 'Tohum'], 2),
        q('Resimde bir bitkinin büyümesi var. Sıra hangisinde doğru verilmiş?',
            ['Tohum, filiz, fide, olgun bitki', 'Filiz, tohum, olgun bitki, fide', 'Olgun bitki, fide, tohum, filiz'], 0,
            imageId: 'bitki'),
        q('Tohumun toprakta uyanıp ilk filizini çıkarmasına ne denir?', ['Çimlenme', 'Çiçeklenme', 'Yaprak dökme'], 0),
        q('Hangisi bir bitki değildir?', ['Elma', 'Kelebek', 'Papatya'], 1),
        q('Ali\'nin saksısındaki çiçek hiç su almazsa ne olur?', ['Daha hızlı büyür.', 'Solar ve kurur.', 'Rengi hiç değişmez.'], 1),
        q('Kelebeğin yaşam döngüsünde tırtıldan sonra hangi evre gelir?', ['Pupa', 'Yumurta', 'İribaş'], 0),
        q('Hangisi canlıların ortak özelliklerinden biridir?', ['Uçabilmek', 'Beslenmek', 'Yüzebilmek'], 1),
        q('Yumurtadan çıkan canlı hangisidir?', ['Kedi', 'Tavuk', 'İnek'], 1),
        q('Bitkilerin büyümesi için hangisi gerekli değildir?', ['Su', 'Güneş ışığı', 'Oyuncak'], 2),
      ];
      final pic = plantPicture();
      final plan = BookletPlan.build(
          qs,
          const BookletOptions(
            title: 'Canlıların Yaşam Döngüsü',
            subtitle: 'Fen Bilimleri · 3. Sınıf · Haydi deneyelim!',
            style: BookletStyle.kids,
            fontSize: 14,
            officialHeader: false,
          ));
      final exam = plan.toExam(id: 'kid1', name: 'Canlıların Yaşam Döngüsü', className: '3-A');
      expect(exam.kidForm, isTrue);
      expect(exam.choiceCount, 3);
      final pdf = await buildBookletPdf(plan,
          school: const SchoolInfo(),
          image: (id) => id == 'bitki' ? pic : null,
          parts: const BookletPdfParts(answerKey: true),
          examCode: null);
      final cards = await buildKidCardsPdf([
        (
          exam,
          const [
            Student(id: '1', firstName: 'Elif', lastName: 'Yıldız', number: '12', className: '3-A'),
            Student(id: '2', firstName: 'Can', lastName: 'Demir', number: '27', className: '3-A'),
            Student(id: '3', firstName: 'Zeynep', lastName: 'Kaya', number: '31', className: '3-A'),
          ]
        )
      ]);
      Directory('build/kid').createSync(recursive: true);
      File('build/kid/kitapcik.pdf').writeAsBytesSync(pdf);
      File('build/kid/kartlar.pdf').writeAsBytesSync(cards);
    });
  });
}
