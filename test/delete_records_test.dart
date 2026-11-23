import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/store.dart';
import 'package:netice/omr/omr_reader.dart';

void main() {
  Exam exam(String id) => Exam.fromKeyString(id: id, name: 'Sınav $id', className: '9-A', key: 'ABCDEABCDE');
  final e1 = exam('e1'), e2 = exam('e2');
  AppStore store() => AppStore()
    ..exams.addAll([e1, e2])
    ..students.addAll(const [
      Student(id: 's1', firstName: 'Ada', lastName: 'Er', number: '101', className: '9-A'),
      Student(id: 's2', firstName: 'Can', lastName: 'Su', number: '102', className: '9-A'),
    ]);

  OmrResult read(String number, String answers) => OmrResult(
        questions: [
          for (final c in answers.split('')) OmrQuestion(Answer(MarkState.filled, {c.codeUnitAt(0) - 65}), const []),
        ],
        studentNumber: number,
        numberPattern: number,
        markers: const [],
      );

  test('tek okuma silinir; öğrenciler ve diğer kâğıtlar kalır, geri alınabilir', () {
    final s = store();
    s.addScan(e1, read('000101', 'ABCDEABCDE'));
    final second = s.addScan(e1, read('000102', 'ABCDEABCDA'));
    s.addScan(e2, read('000101', 'ABCDEABCDE'));
    final i = s.removeSheet(second);
    expect(i, greaterThanOrEqualTo(0));
    expect(s.sheetsOf('e1').map((x) => x.studentId), ['s1']);
    expect(s.sheetsOf('e2').length, 1);
    expect(s.students.length, 2);
    expect(s.exams.length, 2);
    s.restoreSheet(i, second);
    expect(s.sheetsOf('e1').length, 2);
    s.restoreSheet(i, second); // iki kez eklenmez
    expect(s.sheetsOf('e1').length, 2);
  });

  test('sınav silinir; öğrenciler ve diğer sınav kalır, geri alınabilir', () {
    final s = store();
    s.addScan(e1, read('000101', 'ABCDEABCDE'));
    s.addScan(e2, read('000102', 'ABCDEABCDE'));
    final removed = s.removeExams(['e1']);
    expect(s.exams.map((e) => e.id), ['e2']);
    expect(s.sheetsOf('e1'), isEmpty);
    expect(s.sheetsOf('e2').length, 1);
    expect(s.students.length, 2);
    s.restoreExams(removed);
    expect(s.exams.map((e) => e.id), ['e1', 'e2']);
    expect(s.sheetsOf('e1').length, 1);
  });
}
