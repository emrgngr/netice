import 'dart:math' as math;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../bank/bank_models.dart';
import '../bank/booklet_builder.dart';
import '../core/mastery.dart';
import '../core/models.dart';
import '../core/overview.dart';
import '../core/progress.dart';
import '../core/scoring.dart';
import '../core/store.dart';
import '../core/teaching.dart';
import '../core/term.dart';
import '../l10n/l10n.dart';
import '../reports/booklet_pdf.dart';
import '../reports/kid_reports_pdf.dart';
import '../reports/pdf_documents.dart';
import 'exam_screen.dart' show classHistoryOf, developmentHistory, developmentNotes;
import 'transfer_ui.dart' show transferEntryOf;

/// "Örnek raporlar" galerisindeki bölümler.
enum SampleGroup { results, analysis, term, forms, kids }

extension SampleGroupInfo on SampleGroup {
  String get label => switch (this) {
        SampleGroup.results => tr('Sınav sonuçları'),
        SampleGroup.analysis => tr('Sınıf ve kurum analizi'),
        SampleGroup.term => tr('Dönem sonu ve yıl sonu'),
        SampleGroup.forms => tr('Formlar ve kitapçıklar'),
        SampleGroup.kids => tr('İlkokul (çocuk dostu)'),
      };
}

/// Netice'nin üretebildiği her raporun örneği. Uygulamadaki galeri ve web
/// sitesindeki görseller (tool/ornek_raporlar_test.dart) aynı listeden gelir;
/// yeni bir rapor eklendiğinde buraya da eklenmelidir.
enum SampleReport {
  examReport,
  studentCard,
  reflection,
  labels,
  eokul,
  studyGroups,
  overview,
  compare,
  termGrades,
  termCards,
  outcomeTracking,
  transfer,
  forms,
  miniForm,
  answerKey,
  booklet,
  kidReport,
  kidCard,
  kidCertificate,
  kidCards,
}

extension SampleReportInfo on SampleReport {
  SampleGroup get group => switch (this) {
        SampleReport.examReport ||
        SampleReport.studentCard ||
        SampleReport.reflection ||
        SampleReport.labels ||
        SampleReport.eokul ||
        SampleReport.studyGroups =>
          SampleGroup.results,
        SampleReport.overview || SampleReport.compare => SampleGroup.analysis,
        SampleReport.termGrades || SampleReport.termCards || SampleReport.outcomeTracking || SampleReport.transfer =>
          SampleGroup.term,
        SampleReport.forms || SampleReport.miniForm || SampleReport.answerKey || SampleReport.booklet => SampleGroup.forms,
        SampleReport.kidReport || SampleReport.kidCard || SampleReport.kidCertificate || SampleReport.kidCards =>
          SampleGroup.kids,
      };

  /// e-Okul yalnız Türkiye'de kullanılır.
  bool get available => this != SampleReport.eokul || L10n.code == 'tr';

  /// Web sitesindeki görselin dosya adı (img/raporlar/ADI.jpg).
  String get slug => switch (this) {
        SampleReport.examReport => 'sinav_raporu',
        SampleReport.studentCard => 'ogrenci_karnesi',
        SampleReport.reflection => 'degerlendirme_kagidi',
        SampleReport.labels => 'sonuc_etiketleri',
        SampleReport.eokul => 'eokul_listesi',
        SampleReport.studyGroups => 'calisma_gruplari',
        SampleReport.overview => 'genel_analiz',
        SampleReport.compare => 'sube_karsilastirmasi',
        SampleReport.termGrades => 'donem_sonu_raporu',
        SampleReport.termCards => 'donem_karnesi',
        SampleReport.outcomeTracking => 'kazanim_takibi',
        SampleReport.transfer => 'devir_dosyasi',
        SampleReport.forms => 'optik_form',
        SampleReport.miniForm => 'kisa_quiz_formu',
        SampleReport.answerKey => 'cevap_anahtari',
        SampleReport.booklet => 'soru_kitapcigi',
        SampleReport.kidReport => 'cocuk_sinif_raporu',
        SampleReport.kidCard => 'cocuk_karnesi',
        SampleReport.kidCertificate => 'tebrik_belgesi',
        SampleReport.kidCards => 'isimli_cevap_kartlari',
      };

  IconData get icon => switch (this) {
        SampleReport.examReport => Icons.insert_chart_rounded,
        SampleReport.studentCard => Icons.badge_rounded,
        SampleReport.reflection => Icons.rate_review_rounded,
        SampleReport.labels => Icons.label_rounded,
        SampleReport.eokul => Icons.school_rounded,
        SampleReport.studyGroups => Icons.diversity_3_rounded,
        SampleReport.overview => Icons.query_stats_rounded,
        SampleReport.compare => Icons.compare_arrows_rounded,
        SampleReport.termGrades => Icons.table_chart_rounded,
        SampleReport.termCards => Icons.workspace_premium_rounded,
        SampleReport.outcomeTracking => Icons.track_changes_rounded,
        SampleReport.transfer => Icons.drive_file_move_rounded,
        SampleReport.forms => Icons.grid_on_rounded,
        SampleReport.miniForm => Icons.view_module_rounded,
        SampleReport.answerKey => Icons.key_rounded,
        SampleReport.booklet => Icons.menu_book_rounded,
        SampleReport.kidReport => Icons.emoji_emotions_rounded,
        SampleReport.kidCard => Icons.star_rounded,
        SampleReport.kidCertificate => Icons.military_tech_rounded,
        SampleReport.kidCards => Icons.style_rounded,
      };

  Color get color => switch (group) {
        SampleGroup.results => const Color(0xFF1D4ED8),
        SampleGroup.analysis => const Color(0xFF0E7490),
        SampleGroup.term => const Color(0xFF3B4C8C),
        SampleGroup.forms => const Color(0xFFBE123C),
        SampleGroup.kids => const Color(0xFFD97706),
      };

  String get title => switch (this) {
        SampleReport.examReport => tr('Sınav raporu'),
        SampleReport.studentCard => tr('Öğrenci karnesi'),
        SampleReport.reflection => tr('Öğrenci değerlendirme kâğıdı'),
        SampleReport.labels => tr('Sonuç etiketleri'),
        SampleReport.eokul => tr('e-Okul listesi'),
        SampleReport.studyGroups => tr('Çalışma grupları'),
        SampleReport.overview => tr('Genel analiz'),
        SampleReport.compare => tr('Şube karşılaştırması'),
        SampleReport.termGrades => tr('Dönem sonu raporu'),
        SampleReport.termCards => tr('Dönem karnesi'),
        SampleReport.outcomeTracking => tr('Kazanım takibi'),
        SampleReport.transfer => tr('Öğrenci devir dosyası'),
        SampleReport.forms => tr('Öğrenci formları'),
        SampleReport.miniForm => tr('Kısa quiz formu'),
        SampleReport.answerKey => tr('Cevap anahtarı'),
        SampleReport.booklet => tr('Soru kitapçığı'),
        SampleReport.kidReport => tr('Çocuk dostu sınıf raporu'),
        SampleReport.kidCard => tr('Çocuk dostu karne'),
        SampleReport.kidCertificate => tr('Tebrik belgeleri'),
        SampleReport.kidCards => tr('İsimli cevap kartları'),
      };

  String get description => switch (this) {
        SampleReport.examReport =>
          tr('Sınıf ortalaması, başarı dağılımı, soru soru madde analizi ve öğrenci sıralaması.'),
        SampleReport.studentCard => tr('Her öğrenciye bir sayfa: puanı, konu başarısı, gelişim notu ve çalışma önerisi.'),
        SampleReport.reflection => tr('Öğrencinin kendi hatalarını inceleyip neden yanlış yaptığını yazdığı kâğıt.'),
        SampleReport.labels => tr('Kâğıtlara ya da deftere yapıştırılacak, puanlı küçük sonuç etiketleri.'),
        SampleReport.eokul => tr('e-Okul\'a not girerken yanınızda bulunacak, okul numarasına göre sıralı liste.'),
        SampleReport.studyGroups => tr('Sınıf sonuca göre üç gruba ayrılır; her gruba ne çalışacağı yazılır.'),
        SampleReport.overview => tr('Tüm sınıflar ve sınava giren tüm öğrenciler için genel istatistik.'),
        SampleReport.compare => tr('Aynı sınavı yapan şubelerin ortalama, başarı ve soru bazında karşılaştırması.'),
        SampleReport.termGrades => tr('Dönemin tüm sınavlarından ağırlıklı ortalama ve not çizelgesi.'),
        SampleReport.termCards => tr('Öğrencinin dönem boyunca tüm sınavlarını ve gelişimini gösteren karne.'),
        SampleReport.outcomeTracking => tr('Her kazanımda sınıfın ve her öğrencinin ulaştığı düzey.'),
        SampleReport.transfer => tr('Yıl sonunda bir sonraki öğretmene bırakılan öğrenci özeti.'),
        SampleReport.forms => tr('Öğrencinin adı ve numarası basılı, kamerayla okunan optik form.'),
        SampleReport.miniForm => tr('Bir A4\'e dört form: kısa quizler için kâğıt tasarrufu.'),
        SampleReport.answerKey => tr('Cevap anahtarı formu: okutunca anahtar kendiliğinden girilir.'),
        SampleReport.booklet => tr('Soru bankasından iki sütunlu, resmi başlıklı sınav kitapçığı.'),
        SampleReport.kidReport => tr('İlkokul için renkli, yıldızlı ve anlaşılır sınıf raporu.'),
        SampleReport.kidCard => tr('Velinin kolayca okuyacağı, yıldızlı ve resimli öğrenci karnesi.'),
        SampleReport.kidCertificate => tr('Başarılı öğrencilere verilecek renkli tebrik belgesi.'),
        SampleReport.kidCards => tr('Küçük öğrenciler için iri daireli, isimli cevap kartları.'),
      };

  /// Örneği o anki uygulama dilinde üretir.
  Future<Uint8List> build(SampleData d) {
    final school = d.school;
    switch (this) {
      case SampleReport.examReport:
        return buildResultsPdf(exam: d.exam, results: d.results, students: d.byId, school: school);
      case SampleReport.studentCard:
        return buildStudentCardsPdf(
            exam: d.exam,
            results: d.results,
            students: d.byId,
            school: school,
            onlyStudentId: d.featured,
            notes: developmentNotes(d.store, [d.featured]));
      case SampleReport.reflection:
        return buildReflectionPdf(
            exam: d.exam, results: d.results, students: d.byId, school: school, onlyStudentId: d.middle);
      case SampleReport.labels:
        return buildLabelsPdf(exam: d.exam, results: d.results, students: d.byId);
      case SampleReport.eokul:
        return buildEokulPdf(exam: d.exam, results: d.results, classStudents: d.store.studentsOf(d.exam.className), school: school);
      case SampleReport.studyGroups:
        return buildStudyGroupsPdf(
            exam: d.exam, groups: StudyGroups.of(d.exam, d.results), students: d.byId, school: school);
      case SampleReport.overview:
        return buildOverviewPdf(Overview.build(d.store), school: school);
      case SampleReport.compare:
        return buildComparePdf(compareExams(d.store, d.branchExams), school: school, students: d.byId);
      case SampleReport.termGrades:
        return buildTermGradesPdf(d.term, school: school);
      case SampleReport.termCards:
        return buildTermCardsPdf(d.term, school: school, onlyStudentId: d.featured);
      case SampleReport.outcomeTracking:
        return buildOutcomeTrackingPdf(d.term, school: school);
      case SampleReport.transfer:
        final s = d.byId[d.featured]!;
        return buildTransferPdf(
            entries: [transferEntryOf(d.store, s, Mastery.of(d.store, s.className))],
            school: school,
            period: tr('{0} öğretim yılı', [SchoolInfo.academicYear(DateTime.now())]));
      case SampleReport.forms:
        return buildFormsPdf(d.exam, d.store.studentsOf(d.exam.className).take(1).toList(), blankCopies: 0, school: school);
      case SampleReport.miniForm:
        // Kısa quiz formu en çok 14 soru alır: sınavın ilk 10 sorusu.
        final quiz = d.exam.copyWith(questions: d.exam.questions.take(10).toList());
        return buildMiniFormsPdf(quiz, d.store.studentsOf(d.exam.className).take(4).toList(), blankCopies: 0, school: school);
      case SampleReport.answerKey:
        return buildAnswerKeyPdf(d.exam, school: school);
      case SampleReport.booklet:
        return buildBookletPdf(d.booklet, school: school, image: (_) => null);
      case SampleReport.kidReport:
        return buildResultsPdf(
            exam: d.kidExam,
            results: d.kidResults,
            students: d.byId,
            school: d.kidSchool,
            classHistory: classHistoryOf(d.store, d.kidExam));
      case SampleReport.kidCard:
        return buildStudentCardsPdf(
            exam: d.kidExam,
            results: d.kidResults,
            students: d.byId,
            school: d.kidSchool,
            onlyStudentId: d.kidFeatured,
            history: developmentHistory(d.store, d.kidExam, [d.kidFeatured]));
      case SampleReport.kidCertificate:
        return buildKidCertificatesPdf(
            exam: d.kidExam, results: d.kidResults, students: d.byId, school: d.kidSchool, onlyStudentId: d.kidFeatured);
      case SampleReport.kidCards:
        return buildClassFormsPdf([(d.kidExam, d.store.studentsOf(d.kidExam.className).take(4).toList())],
            blankCopies: 0, school: d.kidSchool);
    }
  }
}

/// Örnek raporlar için ayrı, uygulamanın kendi verisine dokunmayan örnek
/// veri: 9-A ve 9-B şubeleri, iki fizik sınavı, ilkokul 3-A sınıfı ve bir
/// matematik kitapçığı. Adlar ve sınav adları uygulama dilindedir.
class SampleData {
  final AppStore store;
  final SchoolInfo school;
  final SchoolInfo kidSchool;
  late final Map<String, Student> byId = store.studentById;
  late final Exam exam = store.examById('demo_exam')!;
  late final List<Result> results = store.resultsOf(exam);
  late final List<Exam> branchExams = [exam, store.examById('demo_exam_b')!];
  late final Exam kidExam = store.examById('sample_kid_2')!;
  late final List<Result> kidResults = store.resultsOf(kidExam);
  late final BookletPlan booklet = _booklet();

  /// Karnede gösterilecek, sınıfın iyi öğrencilerinden biri.
  String get featured => 'demo_1';
  String get middle => 'demo_12';
  String get kidFeatured => 'sample_kid_1';

  late final TermReport term = () {
    final exams = store.exams.where((e) => e.className == exam.className && !e.kidStyle).toList();
    final first = exams.map((e) => e.date).reduce((a, b) => a.isBefore(b) ? a : b);
    final last = exams.map((e) => e.date).reduce((a, b) => a.isAfter(b) ? a : b);
    final t = Term.around(last).where((t) => t.contains(last)).firstOrNull ?? Term.current(last);
    // Örnekteki tüm sınavlar aynı döneme girsin.
    final range = t.contains(first) ? t : Term(t.label, first, t.end);
    return TermReport.build(store, exam.className, range, exams);
  }();

  SampleData._(this.store, this.school, this.kidSchool);

  /// [own] kullanıcının kurum bilgisi; doluysa örnekler kendi başlığıyla görünür.
  factory SampleData.create({SchoolInfo? own}) {
    final store = AppStore()..seedDemo();
    _addKids(store);
    final sample = SchoolInfo(
      province: L10n.code == 'tr' ? 'Ankara' : '',
      district: L10n.code == 'tr' ? 'Çankaya' : '',
      name: tr('Netice Örnek Lisesi'),
      principal: store.students.isEmpty ? '' : store.students[5].fullName,
      teacher: store.students.isEmpty ? '' : store.students[2].fullName,
      subject: tr('Fizik'),
      officialHeader: true,
    );
    final school = own == null || own.isEmpty ? sample : own.copyWith(officialHeader: true);
    final kidSchool = own == null || own.isEmpty
        ? sample.copyWith(name: tr('Netice Örnek İlkokulu'), subject: tr('Matematik'))
        : school;
    return SampleData._(store, school, kidSchool);
  }

  /// İlkokul 3-A: 12 öğrenci, üç şıklı iki kısa sınav (gelişim grafiği için).
  static void _addKids(AppStore store) {
    final source = store.studentsOf('9-A');
    for (var i = 0; i < 12 && i < source.length; i++) {
      final s = source[(i * 2 + 1) % source.length];
      store.students.add(Student(
          id: 'sample_kid_$i', firstName: s.firstName, lastName: s.lastName, number: '${11 + i}', className: '3-A'));
    }
    final rnd = math.Random(5);
    final now = DateTime.now();
    for (final (n, key, days, base) in [(1, 'BACBACABCB', 20, 0.55), (2, 'CABACBBACA', 3, 0.68)]) {
      final e = Exam.fromKeyString(
        id: 'sample_kid_$n',
        name: tr('Matematik Etkinliği {0}', [n]),
        className: '3-A',
        key: key,
        choiceCount: 3,
        date: now.subtract(Duration(days: days)),
      ).copyWith(kidForm: true);
      final topics = [tr('Toplama'), tr('Çıkarma'), tr('Geometrik şekiller')];
      store.exams.add(e.copyWith(questions: [
        for (final q in e.questions) q.copyWith(outcomeCode: topics[(q.no - 1) % 3]),
      ]));
      for (var i = 0; i < 12; i++) {
        final ability = (base + 0.4 * (12 - i) / 12).clamp(0.0, 0.97);
        store.sheets.add(Sheet(examId: e.id, studentId: 'sample_kid_$i', answers: [
          for (final q in e.questions)
            rnd.nextDouble() < ability ? Answer.choice(q.correct.first) : Answer.choice((q.correct.first + 1 + rnd.nextInt(2)) % 3),
        ]));
      }
    }
  }

  /// Sayılarla yazılmış, her dilde aynı kalan matematik soruları.
  BookletPlan _booklet() {
    final now = DateTime.now();
    var n = 0;
    BankQuestion q(String topic, Difficulty d, String text, List<String> ch, int ok) => BankQuestion(
          id: 'sq${n++}',
          subject: tr('Matematik'),
          grade: '6',
          topic: topic,
          difficulty: d,
          text: text,
          choices: ch,
          choiceCount: ch.length,
          correct: {ok},
          created: now,
          updated: now,
        );
    final ops = tr('Dört işlem'), frac = tr('Kesirler'), geo = tr('Geometri'), eq = tr('Denklemler');
    String calc(String e) => tr('{0} işleminin sonucu kaçtır?', [e]);
    final qs = [
      q(ops, Difficulty.easy, calc('12 + 7 × 3'), ['33', '57', '27', '30'], 0),
      q(ops, Difficulty.medium, calc('(48 ÷ 6) − 3 × 2'), ['10', '2', '4', '14'], 1),
      q(ops, Difficulty.medium, calc('125 × 8 − 999'), ['1', '11', '101', '0'], 0),
      q(frac, Difficulty.easy, calc('3/4 + 1/8'), ['4/12', '7/8', '1/2', '5/8'], 1),
      q(frac, Difficulty.medium, calc('2/3 × 9/4'), ['3/2', '11/7', '6/12', '18/7'], 0),
      q(frac, Difficulty.hard, tr('{0} kesrinin ondalık gösterimi hangisidir?', ['7/20']), ['0,72', '0,35', '3,5', '0,7'], 1),
      q(geo, Difficulty.easy, tr('Kenarları {0} cm ve {1} cm olan dikdörtgenin çevresi kaç cm\'dir?', [8, 5]),
          ['13', '40', '26', '18'], 2),
      q(geo, Difficulty.medium, tr('Kenarları {0} cm ve {1} cm olan dikdörtgenin alanı kaç cm²\'dir?', [8, 5]),
          ['40', '26', '13', '80'], 0),
      q(eq, Difficulty.easy, tr('{0} ise x kaçtır?', ['x + 14 = 31']), ['45', '17', '15', '21'], 1),
      q(eq, Difficulty.medium, tr('{0} ise x kaçtır?', ['3x − 7 = 20']), ['9', '13', '27', '6'], 0),
      q(eq, Difficulty.hard, tr('{0} ise x kaçtır?', ['2(x + 4) = 26']), ['11', '13', '9', '15'], 2),
      q(ops, Difficulty.hard, calc('2⁵ − 3³'), ['1', '5', '6', '−1'], 1),
      q(ops, Difficulty.easy, calc('36 ÷ 4 + 5'), ['14', '9', '4', '41'], 0),
      q(ops, Difficulty.medium, calc('7 × 8 − 6 × 9'), ['8', '2', '12', '0'], 1),
      q(ops, Difficulty.easy, calc('1000 − 457'), ['643', '553', '543', '457'], 2),
      q(ops, Difficulty.medium, calc('√144 + √81'), ['15', '21', '225', '23'], 1),
      q(frac, Difficulty.medium, calc('5/6 − 1/3'), ['4/3', '1/2', '4/6', '2/3'], 1),
      q(frac, Difficulty.hard, calc('3/5 ÷ 9/10'), ['2/3', '27/50', '3/2', '1/3'], 0),
      q(geo, Difficulty.medium, tr('Bir üçgenin iki iç açısı {0}° ve {1}°\'dir. Üçüncü açı kaç derecedir?', [50, 70]),
          ['50', '60', '70', '120'], 1),
      q(eq, Difficulty.medium, tr('{0} ise x kaçtır?', ['x ÷ 3 = 12']), ['4', '9', '15', '36'], 3),
      q(eq, Difficulty.hard, tr('{0} ise x kaçtır?', ['5x + 2 = 3x + 10']), ['4', '6', '2', '8'], 0),
    ];
    return BookletPlan.build(
        qs,
        BookletOptions(
          title: tr('6. Sınıf Matematik'),
          subtitle: tr('1. Dönem 1. Yazılı Sınavı'),
          officialHeader: true,
          date: now,
          durationMinutes: 40,
          instructions: tr('Her sorunun yalnız bir doğru cevabı vardır. Cevaplarınızı optik forma işaretleyiniz.'),
          studentBox: true,
          columns: 2,
          fontSize: 10.5,
          columnRule: true,
          sectionHeaders: true,
          pageNumbers: true,
        ));
  }
}
