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

  test('formdan okunan ad: tam, ters sıra, kısalmış ad ile öğrenci bulunur', () async {
    expect(AppStore.normalizeName('şule öz'), 'ŞULEÖZ');
    expect(AppStore.normalizeName('Işıl İnce'), AppStore.normalizeName('IŞIL INCE'));
    expect(AppStore.normalizeName('Emine'), AppStore.normalizeName('EMİNE'));
    final s = AppStore();
    await s.load(dir: Directory.systemTemp.createTempSync('ad'));
    final cls = s.exams.first.className;
    final st = s.studentsOf(cls).first;
    expect(s.studentByReadName(cls, st.fullName.toUpperCase())?.id, st.id);
    expect(s.studentByReadName(cls, '${st.lastName} ${st.firstName}')?.id, st.id);
    final short = AppStore.normalizeName(st.fullName);
    if (short.length > 8) expect(s.studentByReadName(cls, short.substring(0, short.length - 1))?.id, st.id);
    // Okunamayan harf varsa kesin eşleşme yapılmaz, yalnız öneri olur.
    final broken = '${st.fullName.substring(0, 1)}?${st.fullName.substring(2)}';
    expect(s.studentByReadName(cls, broken), isNull);
    expect(AppStore.nameDistance(broken, st.fullName), lessThanOrEqualTo(1));
  });
}
