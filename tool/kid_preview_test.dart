// Çocuk (ilkokul) şablonu önizlemesi: flutter test tool/kid_preview_test.dart
// Çıktılar: build/kid/kitapcik.pdf, kartlar.pdf, karne.pdf, sinif_raporu.pdf
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:netice/bank/bank_models.dart';
import 'package:netice/bank/booklet_builder.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/progress.dart';
import 'package:netice/core/report.dart';
import 'package:netice/core/scoring.dart';
import 'package:netice/core/term.dart';
import 'package:netice/reports/kid_reports_pdf.dart';
import 'package:netice/reports/pdf_documents.dart';
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
        q(
          'Resimde bir bitkinin büyümesi var. Sıra hangisinde doğru verilmiş?',
          ['Tohum, filiz, fide, olgun bitki', 'Filiz, tohum, olgun bitki, fide', 'Olgun bitki, fide, tohum, filiz'],
          0,
          imageId: 'bitki',
        ),
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
        ),
      );
      final exam = plan.toExam(id: 'kid1', name: 'Canlıların Yaşam Döngüsü', className: '3-A');
      expect(exam.kidForm, isTrue);
      expect(exam.choiceCount, 3);
      final pdf = await buildBookletPdf(
        plan,
        school: const SchoolInfo(),
        image: (id) => id == 'bitki' ? pic : null,
        parts: const BookletPdfParts(answerKey: true),
        examCode: null,
      );
      final cards = await buildKidCardsPdf([
        (
          exam,
          const [
            Student(id: '1', firstName: 'Elif', lastName: 'Yıldız', number: '12', className: '3-A'),
            Student(id: '2', firstName: 'Can', lastName: 'Demir', number: '27', className: '3-A'),
            Student(id: '3', firstName: 'Zeynep', lastName: 'Kaya', number: '31', className: '3-A'),
          ],
        ),
      ]);
      Directory('build/kid').createSync(recursive: true);
      File('build/kid/kitapcik.pdf').writeAsBytesSync(pdf);
      File('build/kid/kartlar.pdf').writeAsBytesSync(cards);

      // Raporlar: 12 öğrencilik bir sınıf, önceki 3 sınav ve bu sınav.
      const names = [
        ('Elif', 'Yıldız'),
        ('Can', 'Demir'),
        ('Zeynep', 'Kaya'),
        ('Mert', 'Şahin'),
        ('Ayşe', 'Çelik'),
        ('Emir', 'Arslan'),
        ('Defne', 'Koç'),
        ('Yusuf', 'Aydın'),
        ('Ela', 'Öztürk'),
        ('Kerem', 'Kılıç'),
        ('Nehir', 'Polat'),
        ('Ali', 'Erdem'),
      ];
      final students = [
        for (var i = 0; i < names.length; i++)
          Student(id: 's$i', firstName: names[i].$1, lastName: names[i].$2, number: '${10 + i}', className: '3-A'),
      ];
      final byId = {for (final s in students) s.id: s};
      const topics = ['Yaşam döngüsü', 'Bitkiler', 'Hayvanlar'];
      Exam withTopics(Exam e) => e.copyWith(questions: [for (final q in e.questions) q.copyWith(outcomeCode: topics[(q.no - 1) % 3])]);
      List<Result> resultsFor(Exam e, double skill, int seed) => Scorer.scoreAll(e, [
        for (var i = 0; i < students.length; i++)
          Sheet(
            examId: e.id,
            studentId: students[i].id,
            answers: [
              for (var q = 0; q < e.questionCount; q++)
                if ((i * 7 + q * 3 + seed) % 11 == 0)
                  const Answer.blank()
                else if (((i * 5 + q * 13 + seed * 3) % 100) < (skill + (i % 4) * 8 - (q % 5) * 6))
                  Answer.choice(e.questions[q].correct.first)
                else
                  Answer.choice((e.questions[q].correct.first + 1) % e.choiceCount),
            ],
          ),
      ]);
      final cur = withTopics(exam.copyWith(date: DateTime(2026, 11, 24)));
      final past = [
        for (final (i, (name, skill)) in [('Mevsimler', 45.0), ('Duyu organları', 58.0), ('Maddeyi tanıyalım', 66.0)].indexed)
          (withTopics(exam.copyWith(id: 'p$i', name: name, date: DateTime(2026, 9 + i, 20))), skill),
      ];
      final curResults = resultsFor(cur, 74, 1);
      final history = <String, List<HistoryEntry>>{for (final s in students) s.id: []};
      final classHistory = <(String, double)>[];
      for (final (e, rs) in [for (final (e, skill) in past) (e, resultsFor(e, skill, e.date.month)), (cur, curResults)]) {
        final rep = ExamReport.build(e, rs);
        classHistory.add((e.name, rep.stats.mean / e.rule.maxScore * 100));
        for (final st in rep.standings) {
          history[st.result.sheet.studentId]!.add(HistoryEntry(e, st, rep.stats.mean, rs.length, const []));
        }
      }
      final karne = await buildStudentCardsPdf(
        exam: cur,
        results: curResults,
        students: byId,
        onlyStudentId: 's0',
        notes: const {
          's0': ['Son üç sınavda düzenli olarak yükseldi.', 'Bitkiler konusunda sınıfın üzerinde.'],
        },
        studyTopics: const {
          's0': [
            ('Hayvanlar', 0.5, ['Kurbağa yumurtadan çıkar, iribaş olur, sonra kurbağaya dönüşür.']),
          ],
        },
        history: history,
      );
      final sinif = await buildResultsPdf(exam: cur, results: curResults, students: byId, classHistory: classHistory);
      File('build/kid/karne.pdf').writeAsBytesSync(karne);
      File('build/kid/sinif_raporu.pdf').writeAsBytesSync(sinif);

      // Temalar: her temada kitapçık, karne ve sınıf raporu.
      for (final th in KidTheme.values) {
        final tplan = BookletPlan.build(
          qs,
          BookletOptions(
            title: 'Canlıların Yaşam Döngüsü',
            subtitle: 'Fen Bilimleri · 3. Sınıf · Haydi deneyelim!',
            style: BookletStyle.kids,
            kidTheme: th,
            fontSize: 14,
            officialHeader: false,
          ),
        );
        File('build/kid/tema_${th.name}_kitapcik.pdf').writeAsBytesSync(
          await buildBookletPdf(
            tplan,
            school: const SchoolInfo(),
            image: (id) => id == 'bitki' ? pic : null,
            parts: const BookletPdfParts(),
            examCode: null,
          ),
        );
        final te = cur.copyWith(kidTheme: th);
        File('build/kid/tema_${th.name}_karne.pdf').writeAsBytesSync(
          await buildStudentCardsPdf(exam: te, results: curResults, students: byId, onlyStudentId: 's0', history: history),
        );
      }

      // Büyük kartlar (A4'e 2) ve tebrik belgeleri.
      File('build/kid/buyuk_kartlar.pdf').writeAsBytesSync(await buildKidCardsPdf([(exam, students.take(2).toList())], perPage: 2));
      File('build/kid/tebrik.pdf').writeAsBytesSync(
        await buildKidCertificatesPdf(
          exam: cur.copyWith(kidTheme: KidTheme.space),
          results: curResults,
          students: byId,
          school: const SchoolInfo(name: 'Atatürk İlkokulu', teacher: 'Ayşe Öğretmen'),
        ),
      );

      // Dönem karnesi: dört sınavdan.
      final allExams = [for (final (e, _) in past) e, cur];
      final allResults = {for (final (e, skill) in past) e.id: resultsFor(e, skill, e.date.month), cur.id: curResults};
      final te = [for (final e in allExams) TermExam(e, ExamReport.build(e, allResults[e.id]!), 1)];
      final rows = [
        for (final s in students)
          () {
            final scores = [
              for (final e in te)
                () {
                  final st = e.report.standings.where((x) => x.result.sheet.studentId == s.id).firstOrNull;
                  return st?.pct;
                }(),
            ];
            final got = scores.whereType<double>().toList();
            return TermRow(s, scores, got.isEmpty ? null : got.reduce((a, b) => a + b) / got.length, {
              'Yaşam döngüsü': (0.82, 0.71),
              'Bitkiler': (0.64, 0.66),
              'Hayvanlar': (0.41, 0.58),
            });
          }(),
      ];
      final term = TermReport('3-A', Term.around(DateTime(2026, 11, 24)).first, te, rows);
      File('build/kid/donem_karnesi.pdf').writeAsBytesSync(await buildTermCardsPdf(term, onlyStudentId: 's0'));
    });
  });
}
