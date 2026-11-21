import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/store.dart';

void main() {
  test('işaretli kâğıt görüntüsü bağlanır, kalıcıdır ve sınavla birlikte silinir', () async {
    final dir = Directory.systemTemp.createTempSync('kagit');
    final a = AppStore();
    await a.load(dir: dir);
    final sheet = a.sheets.first;
    final updated = await a.attachSheetImage(sheet, Uint8List.fromList([0xFF, 0xD8, 1, 2, 3]));
    expect(updated, isNotNull);
    expect(a.sheetImageFile(updated!), isNotNull);
    await a.save();

    final b = AppStore();
    await b.load(dir: dir);
    final s2 = b.sheets.firstWhere((s) => s.imageId == updated.imageId);
    final file = b.sheetImageFile(s2)!;
    expect(file.readAsBytesSync().length, 5);
    expect(b.exportBackup().contains('kagitlar'), isFalse);

    b.deleteExam(s2.examId);
    expect(file.existsSync(), isFalse, reason: 'sınav silinince görüntü de silinmeli');
  });
}
