// "Nottan soru üret" ekran görüntüleri: flutter test tool/ai_preview_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/bank/bank_models.dart';
import 'package:netice/bank/bank_store.dart';
import 'package:netice/core/store.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/bank/ai_questions_screen.dart';
import 'package:netice/ui/bank/note_screens.dart';
import 'package:netice/ui/theme.dart';

import 'bank_preview_test.dart' show seedBank;
import 'screenshots_test.dart' show loadFonts, shot;

Widget _themed(Widget home, AppStore store) => StoreScope(
      store: store,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: NTheme.light(), home: home),
    );

void main() {
  testWidgets('nottan soru üret', (tester) async {
    debugDisableShadows = false;
    await tester.runAsync(loadFonts);
    final store = AppStore();
    final dir = Directory.systemTemp.createTempSync('aishots');
    await tester.runAsync(() => store.load(dir: dir));
    store.onboardingDone = true;
    store.ratePrompted = true;
    final b = BankStore.instance;
    await tester.runAsync(() async {
      await b.load(dir: dir);
      await seedBank(b);
    });
    final now = DateTime.now();
    BankQuestion q(int i, Difficulty d, String text, List<String> ch, int ok, String sol) => BankQuestion(
          id: 'ai$i',
          subject: 'Fizik',
          grade: '9. sınıf',
          topic: 'Enerji',
          difficulty: d,
          text: text,
          choices: ch,
          choiceCount: ch.length,
          correct: {ok},
          solution: sol,
          tags: const ['yapay zekâ'],
          created: now,
          updated: now,
        );
    final drafts = [
      q(1, Difficulty.easy, 'Kütlesi 2 kg olan bir cisim 3 m/s hızla hareket etmektedir. Cismin kinetik enerjisi kaç J\'dür?',
          ['3', '6', '9', '12', '18'], 2, 'Ek = ½ · m · v² = ½ · 2 · 3² = 9 J.'),
      q(2, Difficulty.medium, 'Yerden 5 m yükseklikteki 4 kg kütleli cismin yere göre çekim potansiyel enerjisi kaç J\'dür? (g = 10 m/s²)',
          ['20', '50', '100', '200', '400'], 3, 'Ep = m · g · h = 4 · 10 · 5 = 200 J.'),
      q(3, Difficulty.hard, 'Sürtünmeli bir yüzeyde kayan cisim duruyor. Bu olayla ilgili hangisi doğrudur?',
          ['Mekanik enerji korunur', 'Kinetik enerjinin bir kısmı ısıya dönüşür', 'Toplam enerji azalır', 'Potansiyel enerji artar', 'Enerji yok olur'], 1,
          'Sürtünme mekanik enerjinin bir kısmını ısıya dönüştürür; toplam enerji korunur.'),
      q(4, Difficulty.easy, 'Bir cismin hızı iki katına çıkarsa kinetik enerjisi de iki katına çıkar.', const [], 1,
              'Ek = ½ · m · v²: hız 2 katına çıkınca enerji 4 katına çıkar.')
          .copyWith(type: QuestionType.trueFalse),
      q(5, Difficulty.medium, 'Cismin yüksekliğinden dolayı sahip olduğu enerjiye _____ enerjisi denir.', const [], 0, '')
          .copyWith(type: QuestionType.fill, correct: const {}, answerText: 'çekim potansiyel'),
      q(6, Difficulty.hard, 'Serbest düşen bir cisimde enerji dönüşümünü açıklayınız.', const [], 0, '')
          .copyWith(type: QuestionType.open, correct: const {}, answerText: 'Cisim düşerken potansiyel enerjisi azalır, kinetik enerjisi artar; sürtünme yoksa toplam mekanik enerji sabit kalır.'),
    ];

    const phone = Size(390, 844);
    await shot(tester, _themed(const NoteViewScreen(noteId: 'n3'), store), phone, 'yz_1_not_ekrani');
    await shot(tester, _themed(const AiQuestionsScreen(noteId: 'n3'), store), phone, 'yz_2_secenekler');
    await shot(tester, _themed(AiQuestionsScreen(noteId: 'n3', initialDrafts: drafts), store), const Size(390, 2600), 'yz_3_oneriler');
    await shot(tester, _themed(const AiQuestionsScreen(noteId: 'n3'), store), phone, 'yz_4_elle_sayi', then: () async {
      await tester.enterText(find.byType(TextField).first, '60');
      await tester.pump();
    });
    debugDisableShadows = true;
  });
}
