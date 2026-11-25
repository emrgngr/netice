// Klasik soru kitapçığı önizlemesi (örnek soru bankasından):
//   flutter test tool/kitapcik_onizleme_test.dart
// Çıktı: build/kitapcik/kitapcik.pdf (A ve B kitapçıkları, cevap anahtarı,
// çözümlü öğretmen nüshası ve hap bilgi eki).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netice/bank/bank_models.dart';
import 'package:netice/bank/bank_store.dart';
import 'package:netice/bank/booklet_builder.dart';
import 'package:netice/core/models.dart';
import 'package:netice/l10n/l10n.dart';
import 'package:netice/reports/booklet_pdf.dart';

import 'bank_preview_test.dart' show seedBank;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('soru kitapçığı önizlemesi', (t) async {
    await t.runAsync(() async {
      L10n.use(const String.fromEnvironment('LANG_SHOT', defaultValue: 'tr'));
      final b = BankStore.instance;
      await b.load(dir: Directory.systemTemp.createTempSync('kitapcik'));
      await seedBank(b);
      final plan = BookletPlan.build(
          b.questions,
          BookletOptions(
            title: '9. Sınıf Fizik',
            subtitle: '1. Dönem 1. Yazılı Sınavı',
            officialHeader: true,
            date: DateTime(2026, 11, 27),
            durationMinutes: 40,
            instructions: 'Her sorunun yalnız bir doğru cevabı vardır. Cevaplarınızı optik forma kurşun kalemle işaretleyiniz.',
            studentBox: true,
            columns: 2,
            fontSize: 10.5,
            columnRule: true,
            showPoints: false,
            sectionHeaders: true,
            pageNumbers: true,
            bookletCount: 2,
            shuffleQuestions: true,
            shuffleChoices: true,
            answerKeyPage: true,
            solutionsBooklet: true,
            tipsAppendix: true,
          ));
      final pdf = await buildBookletPdf(plan,
          school: const SchoolInfo(
              province: 'Ankara',
              district: 'Çankaya',
              name: 'Atatürk Anadolu Lisesi',
              principal: 'Ayşe Demir',
              teacher: 'Emine Yılmaz',
              subject: 'Fizik'),
          image: b.imageBytes,
          parts: const BookletPdfParts(answerKey: true, solutions: true, tips: true),
          tips: b.notes);
      Directory('build/kitapcik').createSync(recursive: true);
      File('build/kitapcik/kitapcik.pdf').writeAsBytesSync(pdf);
    });
  });
}
