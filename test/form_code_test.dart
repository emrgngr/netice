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
      for (var k = 2; k < 8; k++) FormCode(examCode: FormCode.examCodeOf('k$k'), studentNumber: 1200 + k, booklet: k),
    ]) {
      final bits = c.encode();
      final d = FormCode.decode(bits)!.resolve(c.examCode)!;
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
        .copyWith(bookletOrders: [
      [2, 0, 1]
    ]);
    expect(exam.questionsOf(1).map((q) => q.correct.first).toList(), [2, 0, 1]);
    final a = exam.toMasterOrder(1, [Answer.choice(2), Answer.choice(0), Answer.choice(1)]);
    expect(a.map((x) => x.marked.first).toList(), [0, 1, 2]);
  });

  test('A ve B kitapçığının makine kodu eski formlarla aynı; başka sınava çözülmez', () {
    for (final b in [0, 1]) {
      final d = FormCode.decode(FormCode(examCode: 0x1234, studentNumber: 4321, booklet: b).encode())!;
      // Eski sürümdeki gibi sınav kodu doğrudan okunur.
      expect(d.examCode, 0x1234);
      expect(d.booklet, b);
    }
    final c = FormCode.decode(FormCode(examCode: 0x1234, studentNumber: 1, booklet: 6).encode())!;
    expect(c.resolve(0x1234)!.booklet, 6);
    expect(c.resolve(0x1235), isNull);
  });

  test('C, D… kitapçık sıraları ve JSON (eski tek kitapçık biçimi de okunur)', () {
    final exam = Exam.fromKeyString(id: 'e', name: 'S', className: '9-A', key: 'ABCD').copyWith(bookletOrders: [
      [1, 0, 3, 2],
      [3, 2, 1, 0],
      [2, 3, 0, 1],
    ]);
    expect(exam.bookletCount, 4);
    expect(exam.questionsOf(2).map((q) => q.correct.first).toList(), [3, 2, 1, 0]);
    expect(exam.questionsOf(3).map((q) => q.correct.first).toList(), [2, 3, 0, 1]);
    expect(exam.printedIndex(3, 0), 2);
    expect(exam.masterIndex(3, 2), 0);
    final a = exam.toMasterOrder(3, [Answer.choice(2), Answer.choice(3), Answer.choice(0), Answer.choice(1)]);
    expect(a.map((x) => x.marked.first).toList(), [0, 1, 2, 3]);
    final back = Exam.fromJson(exam.toJson());
    expect(back.bookletOrders, exam.bookletOrders);
    final legacy = exam.toJson()
      ..remove('bookletOrders')
      ..['bookletOrder'] = [1, 0, 3, 2];
    expect(Exam.fromJson(legacy).bookletOrders, [
      [1, 0, 3, 2]
    ]);
    final single = Exam.fromKeyString(id: 'e', name: 'S', className: '9-A', key: 'ABCD');
    expect(Exam.fromJson(single.toJson()).hasBooklets, isFalse);
  });
}
