import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/search.dart';

void main() {
  test('Türkçe ve aksan farkı aramayı etkilemez', () {
    expect(foldSearch('Öğrenci  KARNESİ'), 'ogrenci karnesi');
    expect(foldSearch('Işık İnce Çağrı Şule Ümit'), 'isik ince cagri sule umit');
    expect(foldSearch('Élève Straße'), 'eleve strasse');
    expect(searchWords('  karne, veli? '), ['karne', 'veli']);
  });

  test('başlık başı > sözcük başı > anahtar sözcük', () {
    final a = SearchEntry(SearchKind.feature, 'Karne yazdır');
    final b = SearchEntry(SearchKind.feature, 'Öğrenci karneleri');
    final c = SearchEntry(SearchKind.feature, 'Toplu gönderim', keywords: 'karne veli');
    final w = searchWords('karne');
    expect(a.score(w)! > b.score(w)!, isTrue);
    expect(b.score(w)! > c.score(w)!, isTrue);
  });

  test('her sözcük bulunmalı; kısa sözcük ortadan eşleşmez', () {
    final e = SearchEntry(SearchKind.help, 'Neden Netice?');
    expect(e.score(searchWords('den')), isNull);
    expect(e.score(searchWords('neden yok')), isNull);
    expect(e.score(searchWords('net')), isNotNull);
  });

  test('runSearch sıralar ve tür başına sınırlar', () {
    final entries = [
      for (var i = 0; i < 20; i++) SearchEntry(SearchKind.student, 'Ali $i'),
      SearchEntry(SearchKind.feature, 'Ali özelliği', boost: 5),
    ];
    final r = runSearch(entries, 'ali', perKind: 8);
    expect(r.first.kind, SearchKind.feature);
    expect(r.where((e) => e.kind == SearchKind.student).length, 8);
    expect(runSearch(entries, '   '), isEmpty);
  });
}
