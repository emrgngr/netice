import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netice/bank/ai_questions.dart';
import 'package:netice/core/campaigns.dart';
import 'package:netice/core/pro.dart';
import 'package:netice/core/school_package.dart';

void main() {
  group('kampanyalar', () {
    test('tarihe göre doğru kampanya', () {
      expect(Campaign.current(DateTime(2027, 9, 10))?.id, 'okula-donus');
      expect(Campaign.current(DateTime(2026, 11, 24))?.id, 'ogretmenler-gunu');
      expect(Campaign.current(DateTime(2027, 1, 20))?.id, 'karne-ocak');
      expect(Campaign.current(DateTime(2027, 4, 1))?.id, 'sinav-donemi');
      expect(Campaign.current(DateTime(2027, 6, 15))?.id, 'karne-haziran');
      expect(Campaign.current(DateTime(2027, 7, 15)), isNull);
      expect(Campaign.current(DateTime(2027, 12, 15)), isNull);
    });

    test('kalan gün', () {
      final c = Campaign.all.firstWhere((c) => c.id == 'ogretmenler-gunu');
      expect(c.daysLeft(DateTime(2026, 11, 24, 19)), 7);
      expect(c.daysLeft(DateTime(2026, 11, 30)), 1);
    });

    test('okula dönüşte kurulana 30 gün deneme', () {
      expect(Campaign.trialFor(DateTime(2027, 9, 5)).inDays, 30);
      expect(Campaign.trialFor(DateTime(2027, 10, 5)).inDays, 14);
      expect(Campaign.trialFor(null).inDays, 14);
    });

    test('kampanya indirimi yıllık planlara uygulanır', () {
      final c = Campaign.current(DateTime(2026, 11, 24))!;
      final plans = ProService.plansFor(DateTime(2026, 11, 24), campaign: c);
      final pro = plans.firstWhere((p) => p.id == proYearlyId);
      final ai = plans.firstWhere((p) => p.id == proAiYearlyId);
      final term = plans.firstWhere((p) => p.id == proTermPassId);
      expect(pro.price, '299 TL / yıl');
      expect(pro.oldPrice, '399 TL / yıl');
      expect(ai.price, '524 TL / yıl');
      expect(ai.oldPrice, '699 TL / yıl');
      expect(term.oldPrice, isNull);
    });

    test('kampanyasız: davet indirimi yalnız Pro yıllıkta', () {
      final plans = ProService.plansFor(DateTime(2026, 12, 5), invite: true);
      expect(plans.firstWhere((p) => p.id == proYearlyId).price, '339 TL / yıl');
      expect(plans.firstWhere((p) => p.id == proAiYearlyId).oldPrice, isNull);
      expect(plans.firstWhere((p) => p.id == proAiYearlyId).note, contains('300'));
      expect(ProService.plansFor(DateTime(2026, 12, 5)).firstWhere((p) => p.id == proYearlyId).note, contains('33 TL'));
      expect(ProService.plansFor(DateTime(2026, 12, 5)).firstWhere((p) => p.id == proAiYearlyId).note, contains('58 TL'));
    });
  });

  group('okul paketi', () {
    test('öğretmen sayısına göre indirim', () {
      expect(SchoolPackage.discountFor(4), 0);
      expect(SchoolPackage.discountFor(5), 0.25);
      expect(SchoolPackage.discountFor(10), 0.35);
      expect(SchoolPackage.discountFor(30), 0.45);
      expect(SchoolPackage.perTeacherText('399 TL / yıl', 5), '299 TL / yıl');
      expect(SchoolPackage.perTeacherText('399 TL / yıl', 12), '259 TL / yıl');
      expect(SchoolPackage.perTeacherText('399 TL / yıl', 25), '219 TL / yıl');
      expect(SchoolPackage.totalText('399 TL / yıl', 10), '2590 TL');
      expect(SchoolPackage.totalText('29,99 € / Jahr', 10), '194,90 €');
    });

    test('teklif e-postası', () {
      final u = SchoolPackage.offerMail(subject: 'Teklif: Örnek Lisesi', body: 'Öğretmen sayısı: 12');
      expect(u.scheme, 'mailto');
      expect(Uri.decodeComponent(u.query), contains('Öğretmen sayısı: 12'));
    });
  });

  group('yapay zekâ hakkı', () {
    late Directory dir;
    late AiUsage u;
    final nov = DateTime(2026, 11, 24);
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('kota');
      u = AiUsage.forTest();
      await u.load(dir: dir);
    });
    tearDown(() => dir.delete(recursive: true));

    test('Pro ayda 50, Pro + Yapay Zekâ ayda 300', () {
      expect(u.remaining(AiTier.pro, nov), 50);
      expect(u.remaining(AiTier.ai, nov), 300);
      u.record(30, AiTier.pro, nov);
      expect(u.remaining(AiTier.pro, nov), 20);
    });

    test('ek paket aylık hak bitince kullanılır ve süresi dolmaz', () async {
      u.addCredits(200);
      u.record(45, AiTier.pro, nov);
      expect(u.credits, 200);
      expect(u.remaining(AiTier.pro, nov), 205);
      u.record(20, AiTier.pro, nov); // 5 aylık haktan, 15 paketten
      expect(u.credits, 185);
      expect(u.planRemaining(AiTier.pro, nov), 0);
      final dec = DateTime(2026, 12, 2);
      expect(u.remaining(AiTier.pro, dec), 50 + 185);
      final again = AiUsage.forTest();
      await again.load(dir: dir);
      expect(again.credits, 185, reason: 'paket hakkı dosyada saklanır');
    });

    test('denemede paket de kullanılabilir', () {
      u.addCredits(200);
      u.record(25, AiTier.trial, nov);
      expect(u.trialUsed, 20);
      expect(u.credits, 195);
    });
  });
}
