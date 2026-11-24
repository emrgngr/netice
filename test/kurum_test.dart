import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/common_exam.dart';
import 'package:netice/core/insights.dart';
import 'package:netice/core/institution.dart';
import 'package:netice/core/license.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/pro.dart';
import 'package:netice/core/progress.dart';
import 'package:netice/core/report.dart';
import 'package:netice/core/store.dart';
import 'package:netice/reports/pdf_documents.dart';

final _seed = List<int>.generate(32, (i) => i * 7 % 256);

Future<String> _code({bool admin = false, DateTime? until, String name = 'Deneme Anadolu Lisesi'}) =>
    InstitutionLicense.sign(
        privateSeed: _seed,
        institution: name,
        id: 'deneme',
        admin: admin,
        until: until ?? DateTime.now().add(const Duration(days: 200)),
        seats: 40);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => InstitutionLicense.publicKeyOverride = await InstitutionLicense.publicKeyOf(_seed));
  setUp(() => AppStore.proFreeOnThisPlatform = false);

  group('Kurum lisansı', () {
    test('imzalı kod doğrulanır; değiştirilmiş kod reddedilir', () async {
      final code = await _code(admin: true);
      final l = await InstitutionLicense.verify(code);
      expect(l, isNotNull);
      expect(l!.institution, 'Deneme Anadolu Lisesi');
      expect(l.admin, isTrue);
      expect(l.seats, 40);

      // Veriyi değiştir (kurum adını başka bir adla), imza aynı kalsın.
      final parts = code.split('.');
      final j = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      j['k'] = 'Başka Kurum';
      final forged = '${parts[0]}.${base64Url.encode(utf8.encode(jsonEncode(j))).replaceAll('=', '')}.${parts[2]}';
      expect(await InstitutionLicense.verify(forged), isNull);
      expect(await InstitutionLicense.verify('NTC1.abc.def'), isNull);
      expect(await InstitutionLicense.verify('rastgele metin'), isNull);
    });

    test('lisans Pro açar, kurum adını sabitler, yedekten gelmez, açılışta yeniden doğrulanır', () async {
      final dir = Directory.systemTemp.createTempSync('lic');
      final s = AppStore();
      await s.load(dir: dir);
      s.trialStart = DateTime.now().subtract(const Duration(days: 30));
      expect(s.isPro, isFalse);
      s.setSchool(const SchoolInfo(name: 'Eski ad', officialHeader: true));
      s.setLicense(await InstitutionLicense.verify(await _code()));
      expect(s.isPro, isTrue);
      expect(s.isInstitutionAdmin, isFalse);
      expect(s.canUseAdminPanel, isFalse);
      expect(s.reportSchool.name, 'Deneme Anadolu Lisesi');
      expect(s.reportSchool.official, isTrue);
      await s.save();

      final again = AppStore();
      await again.load(dir: dir);
      expect(again.hasLicense, isTrue);

      final other = AppStore();
      await other.load(dir: Directory.systemTemp.createTempSync('lic2'));
      await other.restoreBackup(s.exportBackup());
      expect(other.license, isNull, reason: 'lisans cihaza aittir');
    });

    test('süresi dolan lisans Pro açmaz; yönetici kodu paneli açar', () async {
      final s = AppStore();
      await s.load(dir: Directory.systemTemp.createTempSync('lic3'));
      s.trialStart = DateTime.now().subtract(const Duration(days: 30));
      s.setLicense(await InstitutionLicense.verify(await _code(until: DateTime.now().subtract(const Duration(days: 2)))));
      expect(s.hasLicense, isFalse);
      expect(s.isPro, isFalse);
      s.setLicense(await InstitutionLicense.verify(await _code(admin: true)));
      expect(s.canUseAdminPanel, isTrue);
    });
  });

  group('Fiyatlar', () {
    test('yıllık 299 TL ve 3 aylık sınav dönemi paketi; aylık abonelik satılmaz', () {
      final plans = ProService.plansFor(DateTime(2026, 11, 21));
      expect(plans.map((p) => p.id), [proYearlyId, proTermPassId]);
      expect(plans.first.price, '299 TL / yıl');
      expect(plans.last.price, '119 TL / 3 ay');
      // Ertesi yıl %30 artış kuralı yeni fiyatlara da uygulanır.
      expect(ProService.plansFor(DateTime(2027, 11, 20)).first.price, '389 TL / yıl');
    });

    test('dönem paketi 90 gün açar; yeniden alınca süre eklenir', () async {
      final s = AppStore();
      await s.load(dir: Directory.systemTemp.createTempSync('pass'));
      s.trialStart = DateTime.now().subtract(const Duration(days: 30));
      expect(s.isPro, isFalse);
      final now = DateTime.now();
      s.addTermPass(now);
      expect(s.isPro, isTrue);
      s.addTermPass(now);
      expect(s.termPassUntil!.difference(now).inDays, 180);
    });
  });

  group('Ortak sınav', () {
    test('sınav paylaşılır, başka şube okur, sonuçlar geri gelir ve tek raporda birleşir', () async {
      final a = AppStore()..seedDemo(); // sınavı hazırlayan öğretmen
      final exam = a.examById('demo_exam')!;
      final file = exportCommonExam(a, exam);
      final commonId = a.examById('demo_exam')!.commonId;
      expect(commonId, isNotNull);
      expect(commonFileKind(file), CommonExamFile.examKind);
      expect(file.contains('demo_0'), isFalse, reason: 'sınav dosyasında öğrenci bilgisi olmaz');

      // Diğer öğretmen kendi şubesine ekler ve okur.
      final b = AppStore();
      final mine = importCommonExam(b, file, '10-C');
      expect(importCommonExam(b, file, '10-C').id, mine.id, reason: 'iki kez eklenmez');
      expect(mine.commonId, commonId);
      expect(mine.questions.length, exam.questions.length);
      final src = a.sheetsOf('demo_exam').take(5).toList();
      for (var i = 0; i < src.length; i++) {
        b.students.add(Student(id: 'b$i', firstName: 'Ad$i', lastName: 'Soyad', number: '${500 + i}', className: '10-C'));
        b.sheets.add(Sheet(examId: mine.id, studentId: 'b$i', answers: src[i].answers));
      }
      final results = exportCommonResults(b, mine);

      // Hazırlayan öğretmen sonuçları alır (iki kez alınsa da kopya olmaz).
      final r1 = importCommonResults(a, results);
      final r2 = importCommonResults(a, results);
      expect(r1.sheets, 5);
      expect(r1.students, 5);
      expect(r2.students, 0);
      final group = commonGroups(a)[commonId]!;
      expect(group.map((e) => e.className).toSet(), {'9-A', '10-C'});
      expect(a.sheetsOf(group.firstWhere((e) => e.className == '10-C').id).length, 5);
      expect(sameNameGroups(a).values.any((g) => g.any((e) => e.className == '10-C')), isTrue);

      final pdf = await buildComparePdf(compareExams(a, group), students: a.studentById);
      expect(pdf.length, greaterThan(1000));

      final sum = summarizeInstitution(a);
      expect(sum.common.single.classes.length, 2);
      expect(sum.byClass.map((c) => c.className), contains('10-C'));
    });

    test('optik formda seçilen her şube kendi ortak sınavını alır', () {
      final a = AppStore()..seedDemo();
      final exam = a.examById('demo_exam')!;
      expect(examForClass(a, exam, exam.className).id, exam.id);
      final other = examForClass(a, exam, 'Z-9');
      expect(other.className, 'Z-9');
      expect(other.id, isNot(exam.id));
      expect(other.commonId, isNotNull);
      expect(a.examById('demo_exam')!.commonId, other.commonId, reason: 'asıl sınav da ortak olur');
      expect(other.questions.map((q) => q.correct), exam.questions.map((q) => q.correct));
      expect(examForClass(a, a.examById('demo_exam')!, 'Z-9').id, other.id, reason: 'ikinci kez açılmaz');
    });

    test('yanlış dosya anlaşılır bir hatayla reddedilir', () {
      expect(() => importCommonResults(AppStore(), '{"app":"netice"}'), throwsFormatException);
      expect(commonFileKind('merhaba'), isNull);
    });
  });

  group('Cihazda yorum', () {
    test('sınav sonrası eylem planı ve öğrenci gelişim notu üretilir', () async {
      final s = AppStore()..seedDemo();
      final exam = s.examById('demo_exam')!;
      final rep = ExamReport.build(exam, s.resultsOf(exam));
      final plan = classActionPlan(rep, s.studentById);
      expect(plan, isNotEmpty);
      expect(plan.every((p) => p.title.isNotEmpty && p.detail.isNotEmpty), isTrue);

      final note = studentDevelopmentNote(historyOf(s, s.studentById['demo_0']!));
      expect(note, isNotEmpty);

      final pdf = await buildStudentCardsPdf(
          exam: exam,
          results: s.resultsOf(exam),
          students: s.studentById,
          onlyStudentId: 'demo_0',
          notes: {'demo_0': note});
      expect(pdf.length, greaterThan(1000));
      final full = await buildResultsPdf(exam: exam, results: s.resultsOf(exam), students: s.studentById);
      expect(full.length, greaterThan(1000));
    });
  });
}
