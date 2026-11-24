// Kütüphane ekran görüntüleri: flutter test tool/bank_preview_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:netice/bank/bank_models.dart';
import 'package:netice/bank/bank_store.dart';
import 'package:netice/core/store.dart';
import 'package:netice/main.dart';
import 'package:netice/ui/bank/booklet_wizard_screen.dart';
import 'package:netice/ui/bank/image_tools.dart';
import 'package:netice/ui/bank/library_screen.dart';
import 'package:netice/ui/bank/note_screens.dart';
import 'package:netice/ui/bank/question_editor_screen.dart';
import 'package:netice/ui/exam_screen.dart';
import 'package:netice/ui/theme.dart';

import 'screenshots_test.dart' show loadFonts, shot;

Uint8List diagram() {
  final im = img.Image(width: 640, height: 300)..clear(img.ColorRgb8(255, 255, 255));
  final ink = img.ColorRgb8(15, 27, 61);
  img.drawLine(im, x1: 40, y1: 250, x2: 600, y2: 250, color: ink, thickness: 3);
  img.fillRect(im, x1: 120, y1: 170, x2: 220, y2: 250, color: img.ColorRgb8(16, 185, 129));
  img.drawLine(im, x1: 220, y1: 210, x2: 360, y2: 210, color: ink, thickness: 3);
  img.drawLine(im, x1: 340, y1: 195, x2: 360, y2: 210, color: ink, thickness: 3);
  img.drawLine(im, x1: 340, y1: 225, x2: 360, y2: 210, color: ink, thickness: 3);
  img.drawLine(im, x1: 120, y1: 210, x2: 20, y2: 210, color: img.ColorRgb8(232, 97, 60), thickness: 3);
  img.drawLine(im, x1: 40, y1: 195, x2: 20, y2: 210, color: img.ColorRgb8(232, 97, 60), thickness: 3);
  img.drawLine(im, x1: 40, y1: 225, x2: 20, y2: 210, color: img.ColorRgb8(232, 97, 60), thickness: 3);
  return Uint8List.fromList(img.encodePng(im));
}

Future<void> seedBank(BankStore b) async {
  final now = DateTime.now();
  var n = 0;
  BankQuestion q(String topic, Difficulty d, String text, List<String> ch, int ok, {String? imageId, String solution = ''}) => BankQuestion(
        id: 'bq${n++}',
        subject: 'Fizik',
        grade: '9. sınıf',
        topic: topic,
        difficulty: d,
        text: text,
        choices: ch,
        choiceCount: ch.length,
        correct: {ok},
        imageId: imageId,
        solution: solution,
        tags: n % 4 == 0 ? ['deneme'] : const [],
        favorite: n % 7 == 0,
        created: now.subtract(Duration(hours: n)),
        updated: now,
      );
  final pic = await b.saveImage(diagram());
  b.addQuestions([
    q('Hareket', Difficulty.easy, 'Sabit hızla giden bir araç 2 saatte 120 km yol alıyor. Aracın hızı kaç km/sa\'tir?', ['40', '50', '60', '80'], 2,
        solution: 'v = x / t = 120 / 2 = 60 km/sa'),
    q('Hareket', Difficulty.medium, 'Durgun hâlden 2 m/s² ivmeyle harekete başlayan bir cismin 5. saniye sonundaki hızı kaç m/s\'dir?',
        ['5', '8', '10', '12', '25'], 2),
    q('Hareket', Difficulty.hard, 'Konum-zaman grafiği parabol olan bir hareketli için aşağıdakilerden hangisi kesinlikle doğrudur?',
        ['Hızı sabittir', 'İvmesi sabittir', 'İvmesi sıfırdır', 'Yön değiştirmez', 'Hepsi'], 1),
    q('Kuvvet', Difficulty.easy, 'Şekildeki cisme etki eden net kuvvetin yönü nedir?', ['Sağa', 'Sola', 'Yukarı', 'Aşağı'], 0, imageId: pic),
    q('Kuvvet', Difficulty.medium, 'Kütlesi 4 kg olan bir cisme 20 N net kuvvet uygulanırsa ivmesi kaç m/s² olur?', ['2', '4', '5', '8'], 2,
        solution: 'F = m·a ⇒ a = 20 / 4 = 5 m/s²'),
    q('Kuvvet', Difficulty.medium, 'Sürtünme kuvveti ile ilgili aşağıdakilerden hangisi yanlıştır?',
        ['Harekete zıt yöndedir', 'Yüzeyin cinsine bağlıdır', 'Her zaman zararlıdır', 'Isı açığa çıkarır'], 2),
    q('Kuvvet', Difficulty.hard, 'Eğik düzlemde sabit hızla çekilen bir cisim için net kuvvet kaç N\'dur?', ['0', 'mg', 'mg·sinα', 'mg·cosα'], 0),
    q('Enerji', Difficulty.easy, 'Yerden h yüksekliğindeki bir cismin sahip olduğu enerji türü hangisidir?',
        ['Kinetik', 'Çekim potansiyel', 'Esneklik potansiyel', 'Isı'], 1),
    q('Enerji', Difficulty.medium, '2 kg kütleli cisim 3 m/s hızla hareket ediyor. Kinetik enerjisi kaç J\'dür?', ['3', '6', '9', '18'], 2),
    q('Enerji', Difficulty.hard, 'Sürtünmesiz ortamda serbest bırakılan bir cismin mekanik enerjisi için ne söylenebilir?',
        ['Artar', 'Azalır', 'Korunur', 'Önce artar sonra azalır'], 2),
    q('Isı ve sıcaklık', Difficulty.easy, 'Sıcaklık birimi aşağıdakilerden hangisidir?', ['Joule', 'Kalori', 'Kelvin', 'Watt'], 2),
    q('Isı ve sıcaklık', Difficulty.medium, 'Öz ısı ile ilgili hangisi doğrudur?',
        ['Madde miktarına bağlıdır', 'Ayırt edici özelliktir', 'Birimi °C\'dir', 'Hepsi'], 1),
    q('Isı ve sıcaklık', Difficulty.hard, 'Aynı sıcaklıktaki iki cisim temas ettirilirse ne olur?',
        ['Isı alışverişi olmaz', 'Büyük olan ısı verir', 'Küçük olan ısı verir', 'Hiçbiri'], 0),
  ]);
  b.upsertQuestion(BankQuestion(
    id: 'bq_open',
    subject: 'Fizik',
    grade: '9. sınıf',
    topic: 'Enerji',
    type: QuestionType.open,
    text: 'Enerjinin korunumu ilkesini günlük hayattan bir örnekle açıklayınız.',
    answerText: 'Sarkaç: potansiyel ve kinetik enerji dönüşümü',
    answerLines: 5,
    points: 10,
    created: now,
    updated: now,
  ));
  b.addNotes([
    BankNote(
        id: 'n1',
        kind: NoteKind.tip,
        subject: 'Fizik',
        topic: 'Hareket',
        title: 'Hız formülü',
        body: 'v = x / t. Birimler uyumlu olmalı: km ve saat ya da m ve saniye.',
        created: now,
        updated: now),
    BankNote(
        id: 'n2',
        kind: NoteKind.tip,
        subject: 'Fizik',
        topic: 'Kuvvet',
        title: 'Newton\'un 2. yasası',
        body: 'F(net) = m · a. Net kuvvet sıfırsa cisim ya durur ya da sabit hızla gider.',
        created: now,
        updated: now),
    BankNote(
        id: 'n3',
        kind: NoteKind.summary,
        subject: 'Fizik',
        grade: '9. sınıf',
        topic: 'Enerji',
        title: 'Enerji ve dönüşümleri',
        body:
            'Kinetik enerji: Ek = ½ m v²\nPotansiyel enerji: Ep = m g h\nSürtünmesiz ortamda mekanik enerji korunur; sürtünme varsa bir kısmı ısıya dönüşür.',
        created: now,
        updated: now),
    BankNote(
        id: 'n4',
        kind: NoteKind.tip,
        subject: 'Fizik',
        topic: 'Enerji',
        title: 'Korunum',
        body: 'Enerji yoktan var edilemez, vardan yok edilemez; yalnız biçim değiştirir.',
        created: now,
        updated: now),
  ]);
  b.upsertBooklet(Booklet(
    id: 'k1',
    name: '9. Sınıf Fizik 1. Yazılı',
    questionIds: [for (var i = 0; i < 13; i++) 'bq$i', 'bq_open'],
    options: const BookletOptions(title: '1. Dönem 1. Fizik Yazılısı', bookletCount: 2, shuffleChoices: true),
    created: now,
    updated: now,
  ));
}

Widget _themed(Widget home, AppStore store) => StoreScope(
      store: store,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: NTheme.light(), home: home),
    );

void main() {
  testWidgets('kütüphane ekranları', (tester) async {
    debugDisableShadows = false;
    await tester.runAsync(loadFonts);
    final store = AppStore();
    final dir = Directory.systemTemp.createTempSync('bankshots');
    await tester.runAsync(() => store.load(dir: dir));
    store.onboardingDone = true;
    store.ratePrompted = true;
    store.seedDemo();
    final b = BankStore.instance;
    await tester.runAsync(() async {
      await b.load(dir: dir);
      await seedBank(b);
    });

    const phone = Size(390, 844);
    await shot(tester, _themed(const LibraryScreen(), store), phone, 'banka_sorular');
    await shot(tester, _themed(const LibraryScreen(initialTab: 1), store), phone, 'banka_notlar');
    await shot(tester, _themed(const LibraryScreen(initialTab: 2), store), phone, 'banka_kitapciklar');
    await shot(tester, _themed(const LibraryScreen(initialTab: 3), store), const Size(390, 1600), 'banka_analiz');
    await shot(tester, _themed(const LibraryScreen(), store), const Size(1366, 820), 'banka_masaustu');
    await shot(tester, _themed(QuestionEditorScreen(question: b.questionById('bq1')), store), const Size(390, 1500), 'banka_soru_duzenle');
    await shot(tester, _themed(QuestionEditorScreen(question: b.questionById('bq3')), store), const Size(1366, 900), 'banka_soru_duzenle_masaustu');
    await shot(tester, _themed(const NoteViewScreen(noteId: 'n3'), store), phone, 'banka_not');
    await shot(tester, _themed(BookletWizardScreen(booklet: b.bookletById('k1')), store), const Size(390, 1100), 'kitapcik_1_sorular');
    await shot(tester, _themed(BookletWizardScreen(booklet: b.bookletById('k1')), store), const Size(390, 1700), 'kitapcik_3_puan',
        then: () async {
      await tester.tap(find.text('Kitapçık'));
    });
    await shot(tester, _themed(BookletWizardScreen(booklet: b.bookletById('k1')), store), const Size(390, 1000), 'kitapcik_2_cocuk_sablonu',
        then: () async {
      await tester.tap(find.text('Görünüm'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Çocuk / İlkokul'));
    });
    await shot(tester, _themed(Builder(builder: (c) => Scaffold(body: AutoPickSheet(used: const {}))), store), const Size(390, 1300), 'kitapcik_otomatik');
    final page = DocPage(diagram(), 640, 300);
    await shot(tester, _themed(CropScreen(pages: [page, page]), store), phone, 'banka_kes');
    await shot(tester, NeticeApp(store: store, splash: false), phone, 'banka_sekme', then: () async {
      await tester.tap(find.text('Kütüphane'));
    });
    await shot(tester, _themed(const ExamScreen(examId: 'demo_exam'), store), const Size(390, 3600), 'sinav_zayif_konular',
        then: () async => tester.tap(find.text('Analiz')));
    debugDisableShadows = true;
  });
}
