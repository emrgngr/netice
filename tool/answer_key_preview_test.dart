// Ayrıntılı cevap anahtarı önizlemesi: flutter test tool/answer_key_preview_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netice/bank/ai_questions.dart';
import 'package:netice/bank/bank_models.dart';
import 'package:netice/bank/booklet_builder.dart';
import 'package:netice/core/models.dart';
import 'package:netice/reports/booklet_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('ayrıntılı cevap anahtarı', (t) async {
    await t.runAsync(() async {
      const outcomes = ['Seçici geçirgenlik', 'Difüzyon', 'Osmoz', 'Aktif taşıma', 'Endositoz ve ekzositoz'];
      const diffs = [Difficulty.easy, Difficulty.medium, Difficulty.hard];
      final qs = [
        for (var i = 0; i < 20; i++)
          BankQuestion(
            id: 'q$i',
            subject: 'Biyoloji',
            topic: 'Hücre zarından madde geçişleri',
            outcome: outcomes[i ~/ 4],
            difficulty: diffs[(i * 7) % 3],
            text: 'Soru ${i + 1}: ${outcomes[i ~/ 4]} ile ilgili aşağıdakilerden hangisi doğrudur?',
            choices: ['Doğru ifade ${i + 1}', 'Çeldirici 1', 'Çeldirici 2', 'Çeldirici 3', 'Çeldirici 4'],
            correct: {0},
            solution: 'Notta: ${outcomes[i ~/ 4]} tanımı. Doğru şık bu tanımı verir; en yakın çeldirici pasif/aktif ayrımını karıştırır.',
            created: DateTime(2026),
            updated: DateTime(2026),
          ),
        for (var i = 0; i < 2; i++)
          BankQuestion(
            id: 'o$i',
            subject: 'Biyoloji',
            topic: 'Hücre zarından madde geçişleri',
            outcome: outcomes[i + 1],
            type: QuestionType.open,
            text: '${outcomes[i + 1]} olayını bir örnekle açıklayınız.',
            answerText: i == 0
                ? 'Maddelerin çok yoğun ortamdan az yoğun ortama enerji harcamadan geçmesidir. Örnek: odaya sıkılan parfüm kokusunun yayılması.'
                : 'Suyun seçici geçirgen zardan az yoğun çözeltiden çok yoğun çözeltiye geçmesidir. Örnek: tuzlu suya konan hücrenin büzülmesi.',
            solution: 'Tanım (4 puan) + doğru örnek (6 puan).',
            created: DateTime(2026),
            updated: DateTime(2026),
          ),
      ];
      final plan = BookletPlan.build(balanceAnswers(qs, seed: 3), const BookletOptions(title: '9. Sınıf Biyoloji Quiz', bookletCount: 2, shuffleChoices: true, totalScore: 100));
      final pdf = await buildBookletPdf(plan,
          school: const SchoolInfo(name: 'Örnek Anadolu Lisesi', teacher: 'Ders öğretmeni'),
          image: (_) => null,
          parts: const BookletPdfParts(answerKey: true));
      Directory('build/bank').createSync(recursive: true);
      File('build/bank/cevap_anahtari_ornek.pdf').writeAsBytesSync(pdf);
    });
  });
}
