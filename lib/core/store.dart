import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../omr/form_layout.dart';
import '../omr/omr_reader.dart';
import 'models.dart';
import 'scoring.dart';

/// Uygulamanın tüm verisi. İlk sürümde cihazda tek bir JSON dosyasında
/// tutulur (internet gerekmez). Sonraki adım: şifreli SQLite + eşitleme.
class AppStore extends ChangeNotifier {
  final List<Student> students = [];
  final List<Exam> exams = [];
  final List<Sheet> sheets = [];

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
      final j = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
      students.addAll((j['students'] as List).map((e) => Student.fromJson(e as Map<String, dynamic>)));
      exams.addAll((j['exams'] as List).map((e) => Exam.fromJson(e as Map<String, dynamic>)));
      sheets.addAll((j['sheets'] as List).map((e) => Sheet.fromJson(e as Map<String, dynamic>)));
    } else {
      seedDemo();
      await save();
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> save() async {
    final f = _file;
    if (f == null) return;
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode({
      'version': 1,
      'students': students.map((s) => s.toJson()).toList(),
      'exams': exams.map((e) => e.toJson()).toList(),
      'sheets': sheets.map((s) => s.toJson()).toList(),
    }));
    await tmp.rename(f.path);
  }

  void _changed() {
    notifyListeners();
    save();
  }

  void addStudents(List<Student> list) {
    final existing = {for (final s in students) '${s.className}|${s.number}'};
    students.addAll(list.where((s) => s.number.isEmpty || !existing.contains('${s.className}|${s.number}')));
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
  Sheet addScan(Exam exam, OmrResult r) {
    Student? st;
    if (r.studentNumber != null) {
      final n = int.tryParse(r.studentNumber!);
      st = studentsOf(exam.className).where((s) => int.tryParse(s.number) == n).firstOrNull;
    }
    final sheet = Sheet(examId: exam.id, studentId: st?.id, answers: r.answers);
    if (st != null) {
      sheets.removeWhere((s) => s.examId == exam.id && s.studentId == st!.id);
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
OmrReader readerFor(Exam exam) =>
    OmrReader(FormLayout(questionCount: exam.questionCount, choiceCount: exam.choiceCount));
