import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/store.dart';

void main() {
  test('gece/gündüz seçimi kaydedilir ve geri yüklenir', () async {
    final dir = Directory.systemTemp.createTempSync('tema');
    final a = AppStore();
    await a.load(dir: dir);
    expect(a.themeMode, 'system');
    a.setThemeMode('dark');
    await a.save();
    final b = AppStore();
    await b.load(dir: dir);
    expect(b.themeMode, 'dark');
  });
}
