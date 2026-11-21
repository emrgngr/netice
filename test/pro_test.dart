import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/models.dart';
import 'package:netice/core/pro.dart';
import 'package:netice/core/store.dart';

void main() {
  setUp(() => AppStore.proFreeOnThisPlatform = false);

  test('ilk kurulumda 14 günlük deneme başlar, sonra Pro kilitlenir', () async {
    final s = AppStore();
    await s.load(dir: Directory.systemTemp.createTempSync('pro'));
    expect(s.inTrial, isTrue);
    expect(s.isPro, isTrue);
    expect(s.trialDaysLeft, 14);
    s.trialStart = DateTime.now().subtract(const Duration(days: 15));
    expect(s.isPro, isFalse);
    s.setSchool(const SchoolInfo(name: 'Okul', officialHeader: true));
    expect(s.reportSchool.official, isFalse, reason: 'resmi başlık Pro özelliği');
    s.confirmPro(proYearlyId);
    expect(s.isPro, isTrue);
    expect(s.reportSchool.official, isTrue);
  });

  test('abonelik yedek dosyasından gelmez', () async {
    final a = AppStore();
    await a.load(dir: Directory.systemTemp.createTempSync('proA'));
    a.confirmPro(proMonthlyId);
    final b = AppStore();
    await b.load(dir: Directory.systemTemp.createTempSync('proB'));
    await b.restoreBackup(a.exportBackup());
    expect(b.hasSubscription, isFalse);
  });
}
