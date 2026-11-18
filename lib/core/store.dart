import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../omr/form_code.dart';
import '../omr/form_layout.dart';
import '../omr/omr_reader.dart';
import 'models.dart';
import 'scoring.dart';

/// Uygulamanın tüm verisi. İlk sürümde cihazda tek bir JSON dosyasında
/// tutulur (internet gerekmez). Sonraki adım: şifreli SQLite + eşitleme.
/// Geri yüklenen yedekteki kayıt sayıları.
class BackupSummary {
  final int students, exams, sheets;
  const BackupSummary(this.students, this.exams, this.sheets);
}

class AppStore extends ChangeNotifier {
  final List<Student> students = [];
  final List<Exam> exams = [];
  final List<Sheet> sheets = [];

  /// Okul ve öğretmen bilgileri (rapor başlıkları için).
  SchoolInfo school = const SchoolInfo();

  /// İlk açılış rehberi gösterildi mi?
  bool onboardingDone = false;

  File? _file;
  bool loaded = false;

  /// Bu dönem okunan kâğıt sayısı (zaman kazancı sayacı için).
  int get readCount => sheets.length;

  /// Kâğıt başına elle tahmini 1,5 dk (hesaplama ekranda açıklanır).
  Duration get timeSaved => Duration(seconds: (readCount * 90).round());

  Map<String, Student> get studentById => {for (final s in students) s.id: s};

  List<String> get classNames {
    final set = <String>{...students.map((s) => s.className), ...exams.map((e) => e.className)}
      ..removeWhere((c) => c.isEmpty);
    return set.toList()..sort();
  }

  List<Student> studentsOf(String className) =>
      students.where((s) => s.className == className).toList()
        ..sort((a, b) => a.number.compareTo(b.number));

  List<Sheet> sheetsOf(String examId) => sheets.where((s) => s.examId == examId).toList();

  List<Result> resultsOf(Exam exam) => Scorer.scoreAll(exam, sheetsOf(exam.id));

  Exam? examById(String id) => exams.where((e) => e.id == id).firstOrNull;

  Future<void> load({Directory? dir}) async {
    final base = dir ?? await getApplicationSupportDirectory();
    _file = File('${base.path}${Platform.pathSeparator}netice_data.json');
    if (await _file!.exists()) {
      _apply(jsonDecode(await _file!.readAsString()) as Map<String, dynamic>);
    } else {
      seedDemo();
      await save();
    }
    loaded = true;
    notifyListeners();
  }

  /// Kayıtlar sırayla yazılır; üst üste gelen iki kayıt aynı geçici dosyayı
  /// paylaşıp birbirini bozmasın.
  Future<void>? _saving;

  Future<void> save() {
    final prev = _saving;
    final next = prev == null ? _write() : prev.catchError((_) {}).then((_) => _write());
    _saving = next;
    return next;
  }

  Map<String, dynamic> toJsonMap() => {
        'app': 'netice',
        'version': 1,
        'savedAt': DateTime.now().toIso8601String(),
        'students': students.map((s) => s.toJson()).toList(),
        'exams': exams.map((e) => e.toJson()).toList(),
        'sheets': sheets.map((s) => s.toJson()).toList(),
        'school': school.toJson(),
        'onboardingDone': onboardingDone,
      };

  void _apply(Map<String, dynamic> j) {
    final st = (j['students'] as List).map((e) => Student.fromJson(e as Map<String, dynamic>)).toList();
    final ex = (j['exams'] as List).map((e) => Exam.fromJson(e as Map<String, dynamic>)).toList();
    final sh = (j['sheets'] as List).map((e) => Sheet.fromJson(e as Map<String, dynamic>)).toList();
    students
      ..clear()
      ..addAll(st);
    exams
      ..clear()
      ..addAll(ex);
    sheets
      ..clear()
      ..addAll(sh);
    school = j['school'] is Map ? SchoolInfo.fromJson((j['school'] as Map).cast<String, dynamic>()) : const SchoolInfo();
    onboardingDone = j['onboardingDone'] as bool? ?? onboardingDone;
  }

  void finishOnboarding() {
    onboardingDone = true;
    _changed();
  }

  /// Taşınabilir yedek dosyasının içeriği (tüm sınıflar, sınavlar, kâğıtlar ve okul bilgisi).
  String exportBackup() => const JsonEncoder.withIndent(' ').convert(toJsonMap());

  /// Yedeği okur ve mevcut verinin yerine koyar. Dosya Netice yedeği değilse
  /// [FormatException] atar ve hiçbir şeyi değiştirmez.
  Future<BackupSummary> restoreBackup(String text) async {
    final Map<String, dynamic> j;
    try {
      j = jsonDecode(text) as Map<String, dynamic>;
      if (j['students'] is! List || j['exams'] is! List || j['sheets'] is! List) throw const FormatException();
    } catch (_) {
      throw const FormatException('Bu dosya bir Netice yedeği değil.');
    }
    // Önce mevcut hâlin bir yedeğini al; yanlış dosya seçilirse geri dönülebilsin.
    await _autoBackup(force: true);
    final probe = AppStore().._apply(j); // ayrıştırma hatası mevcut veriyi bozmasın
    _apply(probe.toJsonMap());
    notifyListeners();
    await save();
    return BackupSummary(students.length, exams.length, sheets.length);
  }

  Directory? get _backupDir =>
      _file == null ? null : Directory('${_file!.parent.path}${Platform.pathSeparator}yedekler');

  /// Otomatik yedekler, en yenisi başta.
  List<File> autoBackups() {
    final d = _backupDir;
    if (d == null || !d.existsSync()) return [];
    return d.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
      ..sort((a, b) => b.path.compareTo(a.path));
  }

  /// Günde bir otomatik yedek; son 14 yedek saklanır.
  Future<void> _autoBackup({bool force = false}) async {
    final d = _backupDir;
    if (d == null) return;
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final day = '${now.year}${two(now.month)}${two(now.day)}';
    final existing = autoBackups();
    if (!force && existing.any((f) => f.uri.pathSegments.last.startsWith('netice_yedek_$day'))) return;
    await d.create(recursive: true);
    final name = 'netice_yedek_${day}_${two(now.hour)}${two(now.minute)}${two(now.second)}.json';
    await File('${d.path}${Platform.pathSeparator}$name').writeAsString(jsonEncode(toJsonMap()));
    for (final old in autoBackups().skip(14)) {
      try {
        await old.delete();
      } catch (_) {}
    }
  }

  Future<void> _write() async {
    final f = _file;
    if (f == null) return;
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(toJsonMap()));
    await tmp.rename(f.path);
    try {
      await _autoBackup();
    } catch (_) {
      // Yedek alınamaması asıl kaydı engellemesin.
    }
  }

  void _changed() {
    notifyListeners();
    save();
  }

  static bool _isDemoExam(String id) => id.startsWith('demo_exam');
  static bool _isDemoStudent(String id) => id.startsWith('demo_') || id.startsWith('demoB_');

  /// İlk açılışta eklenen örnek sınıf ve sınavlar duruyor mu?
  bool get hasDemo => exams.any((e) => _isDemoExam(e.id)) || students.any((s) => _isDemoStudent(s.id));

  /// Örnek verileri siler; öğretmenin kendi kayıtlarına dokunmaz.
  void clearDemo() {
    sheets.removeWhere((s) => _isDemoExam(s.examId));
    exams.removeWhere((e) => _isDemoExam(e.id));
    students.removeWhere((s) => _isDemoStudent(s.id));
    _changed();
  }

  void setSchool(SchoolInfo info) {
    school = info;
    _changed();
  }

  void addStudents(List<Student> list) {
    final existing = {for (final s in students) '${s.className}|${s.number}'};
    students.addAll(list.where((s) => s.number.isEmpty || !existing.contains('${s.className}|${s.number}')));
    _changed();
  }

  void updateStudent(Student st) {
    final i = students.indexWhere((s) => s.id == st.id);
    if (i >= 0) students[i] = st;
    _changed();
  }

  /// Öğrenciyi siler; okunmuş kâğıtları "eşleşmeyen" olarak kalır.
  void deleteStudent(String id) {
    students.removeWhere((s) => s.id == id);
    _changed();
  }

  void upsertExam(Exam exam) {
    final i = exams.indexWhere((e) => e.id == exam.id);
    if (i >= 0) {
      exams[i] = exam;
    } else {
      exams.insert(0, exam);
    }
    _changed();
  }

  void deleteExam(String id) {
    exams.removeWhere((e) => e.id == id);
    sheets.removeWhere((s) => s.examId == id);
    _changed();
  }

  /// Okunan kâğıdı kaydeder. Aynı öğrencinin önceki kâğıdı varsa yenisiyle değiştirir.
  /// Makine kodundaki sınav koduna karşılık gelen sınav.
  Exam? examByCode(int code) => exams.where((e) => FormCode.examCodeOf(e.id) == code).firstOrNull;

  /// Okunan kâğıdı kaydeder. Formdaki makine kodu başka bir sınavı gösteriyorsa
  /// kâğıt o sınava kaydedilir (dönen kâğıdın examId'si farklı olur).
  /// Öğrenci, işaretlenen numaradan; o yoksa makine kodundan bulunur.
  Sheet addScan(Exam exam, OmrResult r) {
    final code = r.code;
    final other = code == null ? null : examByCode(code.examCode);
    // Yalnızca aynı yapıdaki (soru/şık sayısı) sınava yönlendirilir; okuma o yapıya göre yapıldı.
    final target = other != null &&
            other.questionCount == exam.questionCount &&
            other.choiceCount == exam.choiceCount &&
            other.hasBooklets == exam.hasBooklets
        ? other
        : exam;
    Student? st;
    final numbers = [
      if (r.studentNumber != null) int.tryParse(r.studentNumber!),
      code?.studentNumber,
    ].whereType<int>();
    for (final n in numbers) {
      st = studentsOf(target.className).where((s) => int.tryParse(s.number) == n).firstOrNull;
      if (st != null) break;
    }
    final booklet = target.hasBooklets ? (r.booklet ?? code?.booklet ?? 0) : 0;
    final answers = booklet == 1 ? target.toBookletA(r.answers) : r.answers;
    final sheet = Sheet(examId: target.id, studentId: st?.id, answers: answers, booklet: booklet);
    if (st != null) {
      sheets.removeWhere((s) => s.examId == target.id && s.studentId == st!.id);
    }
    sheets.add(sheet);
    _changed();
    return sheet;
  }

  void replaceSheet(Sheet old, Sheet updated) {
    final i = sheets.indexOf(old);
    if (i >= 0) sheets[i] = updated;
    _changed();
  }

  /// Örnek (kurgusal) veriyle ilk açılış: öğretmen sistemi hemen deneyebilir.
  /// Örnek veride gelişim, erken uyarı ve şube karşılaştırması görünsün
  /// diye: 9-A için daha eski bir quiz, 9-B şubesi için aynı quiz.
  void _seedExtra(int nA) {
    final rnd = math.Random(11);
    const topics = ['Hareket', 'Kuvvet', 'Enerji', 'Isı ve sıcaklık'];
    Exam tagged(Exam e) =>
        e.copyWith(questions: [for (final q in e.questions) q.copyWith(outcomeCode: topics[(q.no - 1) ~/ 5])]);
    List<Answer> answers(Exam e, double ability) => [
          for (var q = 0; q < e.questionCount; q++)
            () {
              final key = e.questions[q].correct.first;
              final roll = rnd.nextDouble();
              if (roll < ability) return Answer.choice(key);
              if (roll > 0.96) return const Answer.blank();
              return Answer.choice((key + 1 + rnd.nextInt(4)) % 5);
            }()
        ];

    // 9-A, Fizik Quiz 1: bazı öğrenciler bu sınavda daha iyiydi (düşüş örneği).
    final q1 = tagged(Exam.fromKeyString(
      id: 'demo_exam_q1',
      name: 'Fizik Quiz 1 (örnek)',
      className: '9-A',
      key: 'CABDEBCADEACBDECABED',
      date: DateTime.now().subtract(const Duration(days: 16)),
    ));
    exams.add(q1);
    for (var i = 0; i < nA; i++) {
      var ability = 0.35 + 0.6 * (nA - i) / nA;
      if (i % 6 == 5) ability = (ability + 0.3).clamp(0, 0.97);
      sheets.add(Sheet(examId: q1.id, studentId: 'demo_$i', answers: answers(q1, ability)));
    }

    // 9-B şubesi ve aynı Quiz 2.
    const namesB = [
      ['Aras', 'Yılmaz'], ['Beren', 'Şen'], ['Cem', 'Avcı'], ['Damla', 'Işık'], ['Eren', 'Toprak'],
      ['Feyza', 'Keskin'], ['Göktuğ', 'Sarı'], ['Hira', 'Ekinci'], ['Kaan', 'Uysal'], ['Melis', 'Aksoy'],
      ['Onur', 'Çakır'], ['Rana', 'Gök'], ['Sarp', 'Duman'], ['Tuana', 'Bayram'], ['Yiğit', 'Coşkun'],
      ['Zehra', 'Önal'], ['Alp', 'Karaca'], ['Bade', 'Tunç'],
    ];
    for (var i = 0; i < namesB.length; i++) {
      students.add(Student(
          id: 'demoB_$i', firstName: namesB[i][0], lastName: namesB[i][1], number: '${2040 + i}', className: '9-B'));
    }
    final q2b = tagged(Exam.fromKeyString(
      id: 'demo_exam_b',
      name: 'Fizik Quiz 2 (örnek)',
      className: '9-B',
      key: 'BDACEABDCEBADCEADBCE',
      date: DateTime.now().subtract(const Duration(days: 1)),
    ));
    exams.add(q2b);
    for (var i = 0; i < namesB.length; i++) {
      final ability = 0.45 + 0.5 * (namesB.length - i) / namesB.length;
      sheets.add(Sheet(examId: q2b.id, studentId: 'demoB_$i', answers: answers(q2b, ability)));
    }
  }

  void seedDemo() {
    const names = [
      ['Deniz', 'Arslan'], ['Elif', 'Kaya'], ['Mert', 'Yıldız'], ['Zeynep', 'Aydın'],
      ['Can', 'Demir'], ['Selin', 'Koç'], ['Ali', 'Şahin'], ['Ece', 'Çelik'],
      ['Burak', 'Öztürk'], ['Defne', 'Kılıç'], ['Emre', 'Aslan'], ['İpek', 'Doğan'],
      ['Kerem', 'Kurt'], ['Lara', 'Özdemir'], ['Ozan', 'Erdem'], ['Pelin', 'Güneş'],
      ['Arda', 'Polat'], ['Duru', 'Tekin'], ['Efe', 'Yalçın'], ['Nehir', 'Ateş'],
      ['Umut', 'Bulut'], ['Yağmur', 'Kara'], ['Baran', 'Uçar'], ['Asya', 'Bozkurt'],
    ];
    for (var i = 0; i < names.length; i++) {
      students.add(Student(
        id: 'demo_$i',
        firstName: names[i][0],
        lastName: names[i][1],
        number: '${1040 + i}',
        className: '9-A',
      ));
    }
    final exam = Exam.fromKeyString(
      id: 'demo_exam',
      name: 'Fizik Quiz 2 (örnek)',
      className: '9-A',
      key: 'BDACEABDCEBADCEADBCE',
      date: DateTime.now().subtract(const Duration(days: 2)),
    );
    // Örnek kazanımlar: her 5 soru bir konu.
    const topics = ['Hareket', 'Kuvvet', 'Enerji', 'Isı ve sıcaklık'];
    exams.add(exam.copyWith(questions: [
      for (final q in exam.questions) q.copyWith(outcomeCode: topics[(q.no - 1) ~/ 5]),
    ]));
    _seedExtra(names.length);
    final rnd = math.Random(7);
    for (var i = 0; i < names.length; i++) {
      final ability = 0.35 + 0.6 * (names.length - i) / names.length;
      sheets.add(Sheet(
        examId: exam.id,
        studentId: 'demo_$i',
        answers: [
          for (var q = 0; q < exam.questionCount; q++)
            () {
              final roll = rnd.nextDouble();
              final key = exam.questions[q].correct.first;
              // 12. soruda çoğu iyi öğrenci D'yi seçer: anahtar uyarısı örneği.
              if (q == 11 && ability > 0.6) return Answer.choice(3);
              if (roll < ability) return Answer.choice(key);
              if (roll > 0.96) return const Answer.blank();
              return Answer.choice((key + 1 + rnd.nextInt(4)) % 5);
            }()
        ],
      ));
    }
  }
}

/// Seçili sınav için okuma motoru oluşturur.
OmrReader readerFor(Exam exam) => OmrReader(
    FormLayout(questionCount: exam.questionCount, choiceCount: exam.choiceCount, booklets: exam.hasBooklets));
