import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/store.dart';
import 'package:netice/omr/omr_reader.dart';

void main() {
  final exam = Exam.fromKeyString(id: 'e', name: 'Deneme', className: '9-A', key: 'ABCDEABCDEABCDEABCDE');
  AppStore store() => AppStore()
    ..exams.add(exam)
    ..students.addAll(const [
      Student(id: 's1', firstName: 'Ada', lastName: 'Er', number: '101', className: '9-A'),
      Student(id: 's2', firstName: 'Can', lastName: 'Su', number: '102', className: '9-A'),
      Student(id: 's3', firstName: 'Ece', lastName: 'Ay', number: '103', className: '9-A'),
    ]);

  OmrResult read(String number, String answers) => OmrResult(
        questions: [
          for (final c in answers.split(''))
            OmrQuestion(
                c == '-' ? const Answer(MarkState.blank, {}) : Answer(MarkState.filled, {c.codeUnitAt(0) - 65}),
                const []),
        ],
        studentNumber: number,
        numberPattern: number,
        markers: const [],
      );

  test('aynı kâğıt ikinci kez okunursa eklenmez', () {
    final s = store();
    s.addScan(exam, read('000101', 'ABCDEABCDEABCDEABCDE'));
    expect(s.lastScanStatus, ScanStatus.added);
    s.addScan(exam, read('000101', 'ABCDEABCDEABCDEABCDE'));
    expect(s.lastScanStatus, ScanStatus.duplicate);
    expect(s.sheetsOf('e').length, 1);
  });

  test('birkaç işaret farklıysa yeniden okuma sayılır', () {
    final s = store();
    s.addScan(exam, read('000101', 'ABCDEABCDEABCDEABCDE'));
    s.addScan(exam, read('000101', 'ABCDEABCDEABCDEABCD-'));
    expect(s.lastScanStatus, ScanStatus.replaced);
    expect(s.sheetsOf('e').length, 1);
  });

  test('aynı numarayla bambaşka cevaplar: kontrole alınır, eski korunur, eksikler listelenir', () {
    final s = store();
    s.addScan(exam, read('000101', 'ABCDEABCDEABCDEABCDE'));
    final second = s.addScan(exam, read('000101', 'EDCBAEDCBAEDCBAEDCBA'));
    expect(s.lastScanStatus, ScanStatus.conflict);
    expect(second.studentId, isNull);
    expect(second.readNumber, '000101');
    expect(s.sheetsOf('e').where((x) => x.studentId == 's1').length, 1);
    // Öneri: s1'in kâğıdı var; numarası en yakın, kâğıdı olmayan öğrenciler.
    expect(s.suggestStudents(second).map((x) => x.id), containsAll(['s2', 's3']));
    expect(s.missingStudents(exam).map((x) => x.id), ['s2', 's3']);
  });
}
