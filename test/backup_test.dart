import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/store.dart';

void main() {
  test('yedek dışa aktarılır, başka cihazda geri yüklenir; bozuk dosya veriyi bozmaz', () async {
    final a = AppStore();
    await a.load(dir: Directory.systemTemp.createTempSync('yedekA'));
    a.setSchool(const SchoolInfo(name: 'Örnek Lisesi'));
    await a.save();
    final backup = a.exportBackup();
    expect(a.autoBackups(), isNotEmpty, reason: 'günlük otomatik yedek alınmalı');

    // "Diğer cihaz": boş başlar, yedeği yükler.
    final b = AppStore();
    await b.load(dir: Directory.systemTemp.createTempSync('yedekB'));
    b.students.clear();
    final summary = await b.restoreBackup(backup);
    expect(summary.students, a.students.length);
    expect(summary.sheets, a.sheets.length);
    expect(b.school.name, 'Örnek Lisesi');

    // Kalıcı mı?
    final dir = Directory.systemTemp.createTempSync('yedekC');
    final c = AppStore();
    await c.load(dir: dir);
    await c.restoreBackup(backup);
    final c2 = AppStore();
    await c2.load(dir: dir);
    expect(c2.exams.length, a.exams.length);

    // Bozuk dosya.
    final before = b.students.length;
    expect(() => b.restoreBackup('{"merhaba": 1}'), throwsA(isA<FormatException>()));
    expect(() => b.restoreBackup('yedek değil'), throwsA(isA<FormatException>()));
    expect(b.students.length, before);
  });
}
