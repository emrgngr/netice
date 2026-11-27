// "Belgeden soruları ayıkla" ekranının önizlemesi (örnek sonuçlarla).
//   flutter test tool/ayikla_onizleme_test.dart
// Çıktılar build/screenshots/ayikla_*.png.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/bank/ai_extract.dart';
import 'package:netice/core/store.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/bank/extract_screen.dart';
import 'package:netice/ui/theme.dart';

import 'screenshots_test.dart' show loadFonts, shot;

void main() {
  testWidgets('ayıklama ekranı', timeout: const Timeout(Duration(minutes: 3)), (tester) async {
    await tester.runAsync(loadFonts);
    final store = AppStore();
    await tester.runAsync(() => store.load(dir: Directory.systemTemp.createTempSync('ayikla')));
    final r = parseExtractResponse({
      'questions': [
        {'type': 'multiple', 'number': '1', 'text': 'Hücrenin enerji santrali olarak bilinen organel hangisidir?', 'topic': 'Hücre organelleri', 'choices': ['Ribozom', 'Mitokondri', 'Golgi cisimciği', 'Lizozom'], 'correct': 1, 'answer_source': 'document', 'difficulty': 'easy'},
        {'type': 'multiple', 'number': '2', 'text': 'Bitki hücresinde bulunup hayvan hücresinde bulunmayan yapı hangisidir?', 'topic': 'Bitki ve hayvan hücresi', 'choices': ['Hücre zarı', 'Çekirdek', 'Hücre duvarı', 'Sitoplazma'], 'correct': 2, 'answer_source': 'document', 'difficulty': 'easy'},
        {'type': 'multiple', 'number': '3', 'text': 'Grafikte bir enzimin farklı sıcaklıklardaki etkinliği verilmiştir. Buna göre enzimin en verimli çalıştığı sıcaklık aralığı hangisidir?', 'topic': 'Enzimler', 'choices': ['0–10 °C', '20–30 °C', '35–40 °C', '50–60 °C'], 'correct': 2, 'answer_source': 'solved', 'needs_figure': true, 'difficulty': 'medium'},
        {'type': 'true_false', 'number': '4', 'text': 'Prokaryot hücrelerde zarla çevrili çekirdek bulunur.', 'topic': 'Hücre çeşitleri', 'correct': 1, 'answer_source': 'document', 'difficulty': 'easy'},
        {'type': 'multiple', 'number': '5', 'text': 'Aşağıdakilerden hangisi difüzyonun hızını artırmaz?', 'topic': 'Madde geçişleri', 'choices': ['Sıcaklığın artması', 'Yoğunluk farkının artması', 'Molekül büyüklüğünün artması', 'Yüzey alanının artması'], 'correct': -1, 'answer_source': 'unknown', 'difficulty': 'medium'},
      ],
    }, subject: 'Biyoloji', grade: '9', sourceName: 'Hücre yaprak testi');
    Widget app(bool dark) => StoreScope(
        store: store,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? NTheme.dark() : NTheme.light(),
            home: ExtractQuestionsScreen(initial: r.questions, initialName: 'Hücre yaprak testi')));
    await shot(tester, app(false), const Size(1280, 1500), 'ayikla_genis');
    await shot(tester, app(false), const Size(390, 1800), 'ayikla_telefon');
    await shot(tester, app(true), const Size(1280, 1500), 'ayikla_gece');
  });
}
