import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/grade_export.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/store.dart';
import 'package:netice/core/sync_merge.dart';

/// Drive'daki eşitleme dosyasının yerine bellekte tutulan "uzak" kopya;
/// CloudService.sync ile aynı adımları izler (ağ olmadan).
class FakeDrive {
  Map<String, dynamic>? remote;

  Future<SyncMergeResult> sync(AppStore s) async {
    final res = syncMerge(s.syncPayload(), remote, s.syncBase);
    if (res.incoming > 0) await s.applySync(res.merged);
    remote = res.merged;
    s.markSynced(syncFingerprints(res.merged), DateTime.now());
    return res;
  }
}

Future<AppStore> device(String name) async {
  final s = AppStore();
  await s.load(dir: Directory.systemTemp.createTempSync(name));
  return s;
}

/// Örnek sınavı ve kâğıtlarını öğretmenin kendi sınavıymış gibi kopyalar
/// (örnek veriler eşitlenmez).
void addRealExam(AppStore s, String id, {String name = 'Matematik 1'}) {
  final demo = s.exams.firstWhere((e) => e.id == 'demo_exam');
  final studs = {for (final st in s.students) st.id: st};
  s.exams.insert(0, Exam.fromJson({...demo.toJson(), 'id': id, 'name': name}));
  for (final sh in s.sheetsOf(demo.id)) {
    final st = studs[sh.studentId];
    final sid = 'real_${sh.studentId}';
    if (st != null && !s.students.any((x) => x.id == sid)) {
      s.students.add(Student.fromJson({...st.toJson(), 'id': sid}));
    }
    s.sheets.add(Sheet.fromJson({...sh.toJson(), 'examId': id, 'studentId': sid}));
  }
  s.commit();
}

void main() {
  test('Moodle CSV: kimlik, e-posta, not ve geri bildirim sütunları', () async {
    final s = await device('moodle');
    final exam = s.exams.firstWhere((e) => e.id == 'demo_exam');
    final first = s.students.firstWhere((x) => x.id == 'demo_0');
    s.updateStudent(first.copyWith(email: 'ogr0@okul.k12.tr'));
    final rows = gradeRows(s.resultsOf(exam), s.studentById);
    expect(rows, isNotEmpty);
    final csv = moodleCsv(exam, rows);
    final lines = csv.split('\n');
    expect(lines.first, 'ID number,Email address,First name,Last name,${exam.name},${exam.name} (feedback)');
    expect(lines.length, rows.length + 1);
    expect(csv, contains('ogr0@okul.k12.tr'));
    // Ondalık nokta, en çok iki basamak.
    for (final g in rows) {
      expect(gradeText(g.score), isNot(contains(',')));
    }
    expect(gradeText(85), '85');
    expect(gradeText(72.5), '72.5');
    expect(gradeText(66.666), '66.67');
  });

  test('Classroom eşleştirme: önce e-posta, sonra ad (sıra ve Türkçe harf fark etmez)', () {
    const ours = [
      Student(id: 'a', firstName: 'Ayşe', lastName: 'Yılmaz', number: '1', className: '9-A'),
      Student(id: 'b', firstName: 'İsmail', lastName: 'Çelik', number: '2', className: '9-A'),
      Student(id: 'c', firstName: 'Can', lastName: 'Demir', number: '3', className: '9-A', email: 'can.d@okul.org'),
      Student(id: 'd', firstName: 'Ali', lastName: 'Kaya', number: '4', className: '9-A'),
      Student(id: 'e', firstName: 'Zeynep', lastName: 'Ak', number: '5', className: '9-A'),
    ];
    const theirs = [
      LmsStudent('g1', 'AYSE YILMAZ', ''),
      LmsStudent('g2', 'Celik Ismail', ''),
      LmsStudent('g3', 'Canberk Demirci', 'can.d@okul.org'),
      LmsStudent('g4', 'Ali Kaya', ''),
      LmsStudent('g5', 'Ali Kaya', ''), // iki Ali Kaya: belirsiz, elle seçilmeli
    ];
    final m = matchStudents(ours, theirs);
    expect(m['a'], 'g1');
    expect(m['b'], 'g2');
    expect(m['c'], 'g3');
    expect(m['d'], isNull);
    expect(m['e'], isNull);
    expect(nameKey('Şükrü  Öztürk'), nameKey('ozturk sukru'));
  });

  test('eşitleme: iki cihaz birbirinin sınavını, kâğıdını ve silmesini alır', () async {
    final drive = FakeDrive();
    final phone = await device('telefon');
    final pc = await device('bilgisayar');
    final pcDemo = pc.exams.length;

    // Telefonda sınav açılıp okundu, eşitlendi.
    addRealExam(phone, 'e1');
    final r1 = await drive.sync(phone);
    expect(r1.incoming, 0);
    expect(r1.outgoing, greaterThan(0));

    // Bilgisayar ilk kez eşitlenince sınav gelir; örnek verileri kendinde kalır.
    await drive.sync(pc);
    expect(pc.examById('e1'), isNotNull);
    expect(pc.sheetsOf('e1').length, phone.sheetsOf('e1').length);
    expect(pc.exams.length, pcDemo + 1);
    expect(pc.autoBackups(), isNotEmpty, reason: 'ilk eşitlemeden önce yedek alınır');

    // Bilgisayarda ikinci sınav açılır, telefonda ilk sınavın bir kâğıdı silinir.
    addRealExam(pc, 'e2', name: 'Fizik 1');
    final gone = phone.sheetsOf('e1').first;
    phone.removeSheet(gone);
    await drive.sync(pc);
    await drive.sync(phone);
    await drive.sync(pc);
    expect(phone.examById('e2')?.name, 'Fizik 1');
    expect(pc.sheetsOf('e1').length, phone.sheetsOf('e1').length);
    expect(pc.sheetsOf('e1').length, pc.sheetsOf('e2').length - 1);

    // Bilgisayarda sınav silinir; telefonda da silinir.
    pc.deleteExam('e2');
    await drive.sync(pc);
    await drive.sync(phone);
    expect(phone.examById('e2'), isNull);
    expect(phone.sheetsOf('e2'), isEmpty);

    // Değişiklik yokken eşitleme hiçbir şey taşımaz.
    final idle = await drive.sync(phone);
    expect(idle.incoming + idle.outgoing, 0);

    // Okul bilgisi bir cihazda değişince ötekine geçer; Pro gibi cihaz
    // ayarları geçmez.
    phone.setSchool(const SchoolInfo(name: 'Atatürk Lisesi'));
    phone.proProduct = 'netice_pro_yillik';
    await drive.sync(phone);
    await drive.sync(pc);
    expect(pc.school.name, 'Atatürk Lisesi');
    expect(pc.proProduct, isNull);
  });

  test('eşitleme: iki cihazda aynı anda değişen kayıtta bu cihazınki kalır, eksilmez', () async {
    final drive = FakeDrive();
    final a = await device('A');
    final b = await device('B');
    addRealExam(a, 'e1');
    await drive.sync(a);
    await drive.sync(b);
    a.upsertExam(a.examById('e1')!.copyWith(name: 'A adı'));
    b.upsertExam(b.examById('e1')!.copyWith(name: 'B adı'));
    await drive.sync(a);
    await drive.sync(b);
    expect(b.examById('e1')!.name, 'B adı');
    await drive.sync(a);
    expect(a.examById('e1')!.name, 'B adı', reason: 'son eşitleyen kazanır, iki cihaz aynı hâle gelir');
  });

  test('eşitleme durumu yedekten geri yüklenmez; öğrenci e-postası yedekte kalır', () async {
    final a = await device('yedekS');
    final st = a.students.first;
    a.updateStudent(st.copyWith(email: 'x@y.com'));
    a.setSyncEnabled(true);
    a.markSynced({'students/x': '1'}, DateTime(2026, 1, 1));
    final backup = a.exportBackup();
    final b = await device('yedekT');
    await b.restoreBackup(backup);
    expect(b.syncEnabled, isFalse);
    expect(b.syncBase, isEmpty);
    expect(b.students.firstWhere((x) => x.id == st.id).email, 'x@y.com');
  });
}
