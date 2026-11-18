import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/models.dart';
import 'package:netice/omr/form_code.dart';

void main() {
  test('makine kodu kodlanır ve çözülür; tek bit hatası yakalanır', () {
    for (final c in [
      const FormCode(examCode: 0, studentNumber: 0),
      const FormCode(examCode: 0xFFFF, studentNumber: 999999, booklet: 1),
      FormCode(examCode: FormCode.examCodeOf('demo_exam'), studentNumber: 1042),
      FormCode(examCode: FormCode.examCodeOf('x'), studentNumber: null, booklet: 1),
    ]) {
      final bits = c.encode();
      final d = FormCode.decode(bits)!;
      expect(d.examCode, c.examCode);
      expect(d.studentNumber, c.studentNumber);
      expect(d.booklet, c.booklet);
      for (var i = 1; i < 38; i++) {
        final bad = [...bits]..[i] = !bits[i];
        expect(FormCode.decode(bad), isNull, reason: 'bit $i');
      }
    }
    expect(FormCode.decode(List.filled(FormCode.cells, false)), isNull);
    expect(FormCode.decode(List.filled(FormCode.cells, true)), isNull);
  });

  test('B kitapçığı sırası çözülür ve cevaplar A sırasına çevrilir', () {
    expect(Exam.parseBookletOrder('3, 1, 2', 3), [2, 0, 1]);
    expect(Exam.parseBookletOrder('1 2 2', 3), isNull);
    expect(Exam.parseBookletOrder('1 2', 3), isNull);
    final exam = Exam.fromKeyString(id: 'e', name: 'S', className: '9-A', key: 'ABC')
        .copyWith(bookletOrder: [2, 0, 1]);
    expect(exam.bookletBQuestions.map((q) => q.correct.first).toList(), [2, 0, 1]);
    final a = exam.toBookletA([Answer.choice(2), Answer.choice(0), Answer.choice(1)]);
    expect(a.map((x) => x.marked.first).toList(), [0, 1, 2]);
  });
}
