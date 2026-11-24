import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/common_exam.dart';
import 'package:netice/core/lan_sync.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('aynı ağda: sınav alınır, sonuçlar gönderilir ve toplayıcıda birleşir', () async {
    // Toplayıcı öğretmen (9-A) ve şube öğretmeni (9-B) ayrı cihazlar.
    final host = AppStore();
    final exam = makeCommon(
        host,
        Exam(id: 'x1', name: 'Ortak deneme', className: '9-A', date: DateTime(2026, 11, 24), choiceCount: 4, questions: [
          for (var i = 0; i < 5; i++) Question(no: i + 1, correct: {i % 4}),
        ]));
    final received = <String>[];
    final server = LanHost(
      commonId: exam.commonId!,
      teacher: 'Ayşe Hoca',
      examName: exam.name,
      examText: () => exportCommonExam(host, exam),
      onResults: (text, from) {
        final s = importCommonResults(host, text);
        received.add(from);
        return '${s.className} · ${s.sheets}';
      },
      pin: '4321',
    );
    await server.start(port: 0, beacon: false);
    addTearDown(server.stop);

    final peer = await LanClient.hello('127.0.0.1', server.port);
    expect(peer?.teacher, 'Ayşe Hoca');
    expect(peer?.exam, 'Ortak deneme');

    // Yanlış kod reddedilir.
    await expectLater(LanClient.fetchExam(peer!, '0000'), throwsA(isA<LanException>().having((e) => e.message, 'message', 'pin')));

    final branch = AppStore();
    final text = await LanClient.fetchExam(peer, '4321');
    final mine = importCommonExam(branch, text, '9-B');
    branch.students.add(const Student(id: 'b1', firstName: 'Can', lastName: 'Er', number: '7', className: '9-B', parentPhone: '0532'));
    branch.sheets.add(Sheet(examId: mine.id, studentId: 'b1', answers: [for (var i = 0; i < 5; i++) Answer.choice(i % 4)]));
    final summary = await LanClient.sendResults(peer, '4321', exportCommonResults(branch, mine), from: 'Mehmet Hoca');
    expect(summary, '9-B · 1');
    expect(received, ['Mehmet Hoca']);
    final group = commonGroups(host)[exam.commonId]!;
    expect(group.map((e) => e.className), ['9-A', '9-B']);
    final b = host.students.firstWhere((s) => s.className == '9-B');
    expect(b.parentPhone, '', reason: 'veli telefonu cihazdan çıkmamalı');

    // Başka sınavın sonucu kabul edilmez.
    final other = makeCommon(branch, Exam(id: 'x2', name: 'Başka', className: '9-B', date: DateTime(2026), choiceCount: 4, questions: [Question(no: 1, correct: {0})]));
    await expectLater(LanClient.sendResults(peer, '4321', exportCommonResults(branch, other)), throwsA(isA<LanException>()));
  });
}
