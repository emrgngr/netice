import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/legal.dart';
import 'package:netice/core/updates.dart';

void main() {
  test('sürüm karşılaştırma', () {
    expect(compareVersions('1.0.1', '1.0.0'), 1);
    expect(compareVersions('1.0.0', '1.0.0'), 0);
    expect(compareVersions('1.2.10', '1.2.9'), 1);
    expect(compareVersions('1.0', '1.0.0'), 0);
    expect(compareVersions('1.0.0+12', '1.0.0'), 0);
    expect(compareVersions('0.9.9', '1.0.0'), -1);
  });

  test('yenilikler yalnız aradaki sürümlerden ve bu platformdan gelir', () {
    const notes = [
      ReleaseNote('1.0.2', [ReleaseItem('iki')]),
      ReleaseNote('1.0.1', [ReleaseItem('bir'), ReleaseItem('yalnız iPhone', {'ios'}), ReleaseItem('yalnız test', {'linux'})]),
      ReleaseNote('1.0.0', [ReleaseItem('ilk')]),
    ];
    final items = notesBetween('1.0.0', '1.0.2', notes).map((i) => i.text).toList();
    expect(items, ['iki', 'bir', 'yalnız test']);
    expect(notesBetween('1.0.2', '1.0.2', notes), isEmpty);
  });

  test('güncelleme uyarısı yalnız daha yeni sürümde', () {
    final u = UpdateService.instance;
    u.debugSetLatest(appVersion);
    expect(u.updateAvailable, isFalse);
    u.debugSetLatest('99.0.0');
    expect(u.updateAvailable, isTrue);
    u.debugSetLatest(null);
    expect(u.updateAvailable, isFalse);
  });
}
