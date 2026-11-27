import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/scoring.dart';
import 'package:netice/reports/report_docx.dart';

void main() {
  test('sınav raporu Word belgesi geçerli ve resmî başlıklı', () {
    final exam = Exam.fromKeyString(id: 'e', name: 'Fizik 1. Yazılı', className: '9-A', key: 'ABCDA', choiceCount: 4);
    const st = Student(id: 's1', firstName: 'Elif', lastName: 'Yılmaz', number: '101', className: '9-A');
    final sheet = Sheet(examId: 'e', studentId: 's1', answers: [
      for (final c in [0, 1, 2, 0, 0]) Answer(MarkState.filled, {c})
    ]);
    const school = SchoolInfo(province: 'Ankara', district: 'Çankaya', name: 'Atatürk Lisesi', officialHeader: true);
    final bytes = buildResultsDocx(exam: exam, results: Scorer.scoreAll(exam, [sheet]), students: {'s1': st}, school: school);
    final arc = ZipDecoder().decodeBytes(bytes);
    final names = arc.files.map((f) => f.name).toSet();
    expect(names, containsAll(['[Content_Types].xml', 'word/document.xml', 'word/styles.xml', 'word/footer1.xml']));
    final xml = utf8.decode(arc.findFile('word/document.xml')!.content as List<int>);
    expect(xml, contains('Elif Yılmaz'));
    expect(xml, contains('ÇANKAYA KAYMAKAMLIĞI'));
    expect(xml, contains('UYGUNDUR'));
  });
}
