// İşaretli kâğıt önizlemesi: flutter test tool/annotated_preview_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/scoring.dart';
import 'package:netice/omr/form_layout.dart';
import 'package:netice/omr/omr_reader.dart';
import 'package:netice/omr/rectify.dart';
import 'package:netice/ui/annotated_sheet.dart';
import 'package:netice/ui/theme.dart';

import 'screenshots_test.dart' show loadFonts, shot;

void main() {
  testWidgets('işaretli kâğıt önizlemesi', (tester) async {
    debugDisableShadows = false;
    await tester.runAsync(loadFonts);
    final photo = File('test/fixtures/new_form_scan.jpg').readAsBytesSync();
    final gray = GrayImage.decode(photo)!;
    final r = OmrReader(FormLayout(questionCount: 20, choiceCount: 5)).read(gray);
    final jpeg = rectifiedJpeg(gray, r.markers);
    final exam = Exam.fromKeyString(id: 'x', name: 'Fizik Quiz', className: '9-A', key: 'ABCDEABCDEABCDEABCDE');
    final res = Scorer.score(exam, Sheet(examId: 'x', studentId: 's', answers: r.answers));
    const font = 'PlusJakartaSans';
    Widget label(String t, String s) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: const TextStyle(fontFamily: font, fontSize: 20, fontWeight: FontWeight.w800, color: NColors.ink)),
          Text(s, style: const TextStyle(fontFamily: font, fontSize: 13, color: Color(0xFF6B7280))),
          const SizedBox(height: 10),
        ]);
    Widget legend(Color c, String t, {bool dashed = false}) => Padding(
          padding: const EdgeInsets.only(right: 18),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c, width: dashed ? 1.5 : 3))),
            const SizedBox(width: 6),
            Text(t, style: const TextStyle(fontFamily: font, fontSize: 13, color: NColors.ink)),
          ]),
        );
    final page = MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFEFEBE2),
        body: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('İşaretli kâğıt görüntüsü (önizleme)',
                style: TextStyle(fontFamily: font, fontSize: 28, fontWeight: FontWeight.w800, color: NColors.ink)),
            const SizedBox(height: 4),
            const Text('Okutulan fotoğraf düzleştirilir, her sorunun sonucu kâğıdın üzerine çizilir ve öğrenciyle saklanır.',
                style: TextStyle(fontFamily: font, fontSize: 15, color: Color(0xFF6B7280))),
            const SizedBox(height: 18),
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    label('1. Telefonla çekilen fotoğraf', 'Eğik, gölgeli, olduğu gibi'),
                    Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(photo, fit: BoxFit.contain))),
                  ]),
                ),
                const SizedBox(width: 28),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    label('2. Netice\'nin işaretlediği kâğıt', 'Düzleştirildi, sonuçlar üzerine çizildi'),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(boxShadow: [
                          BoxShadow(color: NColors.ink.withValues(alpha: 0.18), blurRadius: 20, offset: const Offset(0, 8)),
                        ]),
                        child: AnnotatedSheet(jpeg: jpeg, exam: exam, result: res),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            Wrap(runSpacing: 6, children: [
              legend(NColors.emerald, 'Doğru cevap'),
              legend(NColors.coral, 'Yanlış işaret'),
              legend(NColors.emerald, 'Olması gereken şık', dashed: true),
              legend(NColors.amber, 'Boş bırakılan sorunun doğru şıkkı', dashed: true),
            ]),
          ]),
        ),
      ),
    );
    await shot(tester, page, const Size(1300, 1060), 'isaretli_kagit_onizleme');
    debugDisableShadows = true;
  });
}
