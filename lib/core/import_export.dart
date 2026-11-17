import 'dart:convert';

import 'package:csv/csv.dart';

import 'models.dart';
import 'scoring.dart';

/// Öğrenci listesi içe aktarma (CSV / Excel'den "CSV olarak kaydet").
///
/// Sütunlar başlıklardan otomatik tahmin edilir: ad, soyad, (okul) no,
/// sınıf/şube. "Ad Soyad" tek sütunsa son kelime soyad sayılır.
class StudentImport {
  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('İ', 'i')
      .replaceAll('ş', 's')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  static List<List<String>> _rows(String text) {
    final firstLine = text.split('\n').first;
    // Türkçe Excel CSV'leri genelde noktalı virgül kullanır.
    final delim = ';'.allMatches(firstLine).length > ','.allMatches(firstLine).length
        ? ';'
        : (firstLine.contains('\t') ? '\t' : ',');
    final rows = Csv(fieldDelimiter: delim, autoDetect: false)
        .decode(text.replaceAll('\r\n', '\n'));
    return rows
        .map((r) => r.map((c) => c.toString().trim()).toList())
        .where((r) => r.any((c) => c.isNotEmpty))
        .toList();
  }

  /// [defaultClass] sınıf sütunu yoksa kullanılır.
  static List<Student> parse(String text, {String defaultClass = ''}) {
    if (text.startsWith('﻿')) text = text.substring(1);
    final rows = _rows(text);
    if (rows.isEmpty) return [];
    final header = rows.first.map(_norm).toList();
    int find(List<String> keys) => header.indexWhere((h) => keys.any((k) => h == k || h.contains(k)));

    var iNo = find(['okulno', 'ogrencino', 'numara', 'no']);
    var iFirst = header.indexWhere((h) => h == 'ad' || h == 'adi' || h == 'isim');
    var iLast = find(['soyad']);
    var iFull = find(['adsoyad', 'adisoyadi', 'adsoyadi']);
    final iClass = find(['sinif', 'sube']);
    final hasHeader = iNo >= 0 || iFirst >= 0 || iFull >= 0;
    final data = hasHeader ? rows.skip(1) : rows;
    if (!hasHeader) {
      // Başlıksız: no, ad soyad varsayımı.
      iNo = 0;
      iFull = 1;
    }

    final out = <Student>[];
    var i = 0;
    for (final r in data) {
      String at(int idx) => idx >= 0 && idx < r.length ? r[idx] : '';
      String first, last;
      if (iFirst >= 0 && iLast >= 0) {
        first = at(iFirst);
        last = at(iLast);
      } else {
        final parts = at(iFull >= 0 ? iFull : (iFirst >= 0 ? iFirst : 1)).split(RegExp(r'\s+'));
        last = parts.length > 1 ? parts.removeLast() : '';
        first = parts.join(' ');
      }
      final no = at(iNo).replaceAll(RegExp(r'\D'), '');
      if (first.isEmpty && last.isEmpty) continue;
      out.add(Student(
        id: 's${DateTime.now().microsecondsSinceEpoch}_${i++}',
        firstName: first,
        lastName: last,
        number: no,
        className: at(iClass).isNotEmpty ? at(iClass) : defaultClass,
      ));
    }
    return out;
  }
}

/// Excel'in doğrudan açabildiği not listesi (UTF-8 BOM + noktalı virgül).
String resultsCsv(Exam exam, List<Result> results, Map<String, Student> students) {
  final sorted = [...results]..sort((a, b) => b.score.compareTo(a.score));
  String n(double v) => v.toStringAsFixed(2).replaceAll('.', ',');
  final rows = <List<String>>[
    ['Sıra', 'Okul no', 'Ad', 'Soyad', 'Sınıf', 'Doğru', 'Yanlış', 'Boş', 'Net', 'Puan',
      for (final q in exam.questions) 'S${q.no}'],
    for (var i = 0; i < sorted.length; i++)
      () {
        final r = sorted[i];
        final s = students[r.sheet.studentId];
        return [
          '${i + 1}',
          s?.number ?? '',
          s?.firstName ?? 'Eşleşmedi',
          s?.lastName ?? '',
          s?.className ?? exam.className,
          '${r.correct}',
          '${r.wrong}',
          '${r.blank}',
          n(r.net),
          n(r.score),
          for (final a in r.sheet.answers)
            a.marked.isEmpty ? '' : a.marked.map((c) => String.fromCharCode(65 + c)).join('/'),
        ];
      }(),
  ];
  return '﻿${Csv(fieldDelimiter: ';', lineDelimiter: '\r\n').encode(rows)}';
}

List<int> utf8Bytes(String s) => utf8.encode(s);
