import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// PDF'teki sayfa sayısını tahmin eder (toplu okumada "sayfa 12 / 40"
/// ilerlemesi için). Tarayıcıların ürettiği PDF'lerde sayfa ağacı ya düz
/// metindir ya da sıkıştırılmış nesne akışlarının (/ObjStm) içindedir; ikisine
/// de bakılır. Bulunamazsa null döner; okuma yine de sayfa sayfa sürer.
int? pdfPageCount(Uint8List data) {
  if (data.length < 5 || latin1.decode(data.sublist(0, 5)) != '%PDF-') return null;
  final raw = latin1.decode(data);
  final texts = <String>[raw];

  // Sıkıştırılmış nesne akışlarını açar (yalnızca /ObjStm; görüntü akışları
  // atlanır, büyük taramalarda yavaşlamasın).
  final objStm = RegExp(r'/Type\s*/ObjStm');
  for (final m in RegExp(r'stream\r?\n').allMatches(raw)) {
    final dictStart = raw.lastIndexOf('<<', m.start);
    if (dictStart < 0 || m.start - dictStart > 600) continue;
    final dict = raw.substring(dictStart, m.start);
    if (!objStm.hasMatch(dict)) continue;
    final end = raw.indexOf('endstream', m.end);
    if (end < 0) continue;
    try {
      texts.add(latin1.decode(const ZLibDecoder().decodeBytes(data.sublist(m.end, end))));
    } catch (_) {
      try {
        texts.add(latin1.decode(Inflate(data.sublist(m.end, end)).getBytes()));
      } catch (_) {}
    }
  }

  // 1) Kök sayfa ağacının /Count değeri: /Pages nesnelerinin en büyüğü.
  var count = 0;
  final pagesDict = RegExp(r'/Type\s*/Pages\b');
  for (final t in texts) {
    for (final m in pagesDict.allMatches(t)) {
      final from = t.lastIndexOf('<<', m.start);
      final to = t.indexOf('>>', m.end);
      final dict = t.substring(from < 0 ? m.start : from, to < 0 ? t.length : to);
      final c = RegExp(r'/Count\s+(\d+)').firstMatch(dict);
      final n = c == null ? 0 : int.parse(c.group(1)!);
      if (n > count) count = n;
    }
  }
  if (count > 0) return count;

  // 2) /Type /Page nesnelerini say.
  final page = RegExp(r'/Type\s*/Page(?![a-zA-Z])');
  for (final t in texts) {
    count += page.allMatches(t).length;
  }
  return count > 0 ? count : null;
}
