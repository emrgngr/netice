import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/store.dart';

void main() {
  test('rakam farkı: okunamayan rakam her rakama uyar', () {
    expect(AppStore.numberDistance('001042', '1042'), 0);
    expect(AppStore.numberDistance('00?042', '1042'), 0);
    expect(AppStore.numberDistance('001043', '1042'), 1);
    expect(AppStore.numberDistance('??????', '1042'), isNull);
    expect(AppStore.numberDistance('001042', '1234567'), isNull);
  });

  test('eşleşmeyen kâğıda en yakın numaralı öğrenci önerilir', () async {
    final s = AppStore();
    await s.load(dir: Directory.systemTemp.createTempSync('oneri'));
    final exam = s.exams.first;
    final students = s.studentsOf(exam.className);
    // Bu sınavda kâğıdı olmayan bir öğrenci bırak.
    final target = students.first;
    s.sheets.removeWhere((x) => x.examId == exam.id && x.studentId == target.id);
    final n = target.number.padLeft(6, '0');
    // Son rakamı yanlış okunmuş, bir rakamı okunamamış numara.
    final wrongLast = '${n.substring(0, 5)}${(int.parse(n[5]) + 1) % 10}';
    final read = '?${wrongLast.substring(1)}';
    final sheet = Sheet(examId: exam.id, answers: s.sheetsOf(exam.id).first.answers, readNumber: read);
    s.sheets.add(sheet);
    final sug = s.suggestStudents(sheet);
    expect(sug, isNotEmpty);
    expect(sug.first.id, target.id);
    // Kalıcı.
    expect(Sheet.fromJson(sheet.toJson()).readNumber, read);
  });
}
