import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/import_export.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/store.dart';
import 'package:netice/omr/form_code.dart';
import 'package:netice/omr/form_layout.dart';
import 'package:netice/omr/form_raster.dart';
import 'package:netice/omr/omr_reader.dart';

void main() {
  test('numarasız öğrencilere ad soyad sırasıyla sıra numarası verilir', () {
    final store = AppStore()
      ..students.add(const Student(id: 'x', firstName: 'Var', lastName: 'Olan', number: '2', className: 'Kurs-1'));
    final list = StudentImport.parse('Ad Soyad\nÜmit Kaya\nCan Er\nÇağla Demir\nİrem Su\nIşık Ay\n', defaultClass: 'Kurs-1');
    expect(list.every((s) => s.number.isEmpty), isTrue);
    expect(store.addStudents(list), 5);
    expect([for (final s in store.studentsOf('Kurs-1')) '${s.number} ${s.fullName}'],
        ['1 Can Er', '2 Var Olan', '3 Çağla Demir', '4 Işık Ay', '5 İrem Su', '6 Ümit Kaya']);
    // Aynı liste tekrar aktarılırsa kopya oluşmaz.
    expect(store.addStudents(StudentImport.parse('Ad Soyad\nCan Er\n', defaultClass: 'Kurs-1')), 0);
    expect(store.studentsOf('Kurs-1').length, 6);
    // Başka sınıfta numaralar yeniden 1'den başlar.
    store.addStudents([const Student(id: 'y', firstName: 'Ece', lastName: 'Tan', number: '', className: 'Kurs-2')]);
    expect(store.studentsOf('Kurs-2').single.number, '1');
  });

  test('isimli formdaki kod, numara işaretlenmeden öğrenciyi bulur', () {
    final store = AppStore();
    store.addStudents([const Student(id: 'a', firstName: 'Ali', lastName: 'Kaya', number: '', className: 'K')]);
    final st = store.students.single;
    final e = Exam(
      id: 'ek',
      name: 'Deneme',
      className: 'K',
      date: DateTime(2026, 11, 22),
      choiceCount: 4,
      questions: [for (var i = 0; i < 10; i++) Question(no: i + 1, correct: {0})],
    );
    store.exams.add(e);
    final im = FormRaster(FormLayout(questionCount: 10, choiceCount: 4)).render(
      answers: {for (var i = 0; i < 10; i++) i: [0]},
      code: FormCode(examCode: FormCode.examCodeOf(e.id), studentNumber: int.parse(st.number)),
    );
    final r = readerFor(e).read(GrayImage.fromImage(im));
    expect(store.addScan(e, r).studentId, 'a');
  });
}
