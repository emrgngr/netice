// Tablo dosyalarını okur: Excel (.xlsx ve eski .xls), LibreOffice / Google
// (.ods), e-Okul gibi sitelerin ".xls" adıyla verdiği HTML tablolar ve Excel
// 2003 XML. Hepsi aynı biçime çevrilir: sayfa sayfa (ad, satırlar).
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'import_export.dart';

typedef Sheets = List<(String, List<List<String>>)>;

/// Tablo dosyası uzantıları (dosya seçicilerde).
const spreadsheetExtensions = ['xlsx', 'xls', 'ods', 'csv'];

/// Dosya bir tablo dosyasıysa sayfalarını döner; değilse (düz metin, CSV,
/// PDF…) null. Biçim uzantıdan değil dosyanın içeriğinden anlaşılır.
Sheets? spreadsheetSheets(Uint8List bytes, [String fileName = '']) {
  if (bytes.length < 4) return null;
  // Zip: .xlsx ya da .ods
  if (bytes[0] == 0x50 && bytes[1] == 0x4B) {
    final zip = ZipDecoder().decodeBytes(bytes);
    if (zip.findFile('content.xml') != null && zip.findFile('xl/workbook.xml') == null) return _odsSheets(zip);
    return StudentImport.xlsxSheets(bytes);
  }
  // OLE2 bileşik belge: eski Excel 97–2003 (.xls)
  if (bytes[0] == 0xD0 && bytes[1] == 0xCF && bytes[2] == 0x11 && bytes[3] == 0xE0) return _XlsReader(bytes).sheets();
  // HTML ya da XML olarak kaydedilmiş ".xls" (e-Okul, MEBBİS vb.)
  final head = latin1.decode(bytes.sublist(0, bytes.length < 2048 ? bytes.length : 2048)).toLowerCase();
  final ext = fileName.toLowerCase();
  if (head.contains('<table') || head.contains('<html') || head.contains('<?xml') && head.contains('urn:schemas-microsoft-com:office:spreadsheet') ||
      (ext.endsWith('.xls') && head.trimLeft().startsWith('<'))) {
    final text = _decodeText(bytes);
    if (text.contains('urn:schemas-microsoft-com:office:spreadsheet')) return _xml2003Sheets(text);
    return _htmlSheets(text);
  }
  return null;
}

/// Dosyayı metne çevirir: UTF-8 değilse Türkçe Windows (1254) sayılır.
String _decodeText(Uint8List bytes) {
  var b = bytes;
  if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) b = b.sublist(3);
  if (b.length >= 2 && b[0] == 0xFF && b[1] == 0xFE) {
    return String.fromCharCodes([for (var i = 2; i + 1 < b.length; i += 2) b[i] | (b[i + 1] << 8)]);
  }
  try {
    return utf8.decode(b);
  } on FormatException {
    return cp1254Decode(b);
  }
}

/// Windows-1254 (Türkçe) kod sayfası.
String cp1254Decode(List<int> bytes) {
  const hi = {
    0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026, 0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02C6, //
    0x89: 0x2030, 0x8A: 0x0160, 0x8B: 0x2039, 0x8C: 0x0152, 0x91: 0x2018, 0x92: 0x2019, 0x93: 0x201C, 0x94: 0x201D,
    0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014, 0x98: 0x02DC, 0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A, 0x9C: 0x0153,
    0x9F: 0x0178, 0xD0: 0x011E, 0xDD: 0x0130, 0xDE: 0x015E, 0xF0: 0x011F, 0xFD: 0x0131, 0xFE: 0x015F,
  };
  return String.fromCharCodes([for (final c in bytes) hi[c] ?? c]);
}

String _num(double d) {
  if (d.isNaN || d.isInfinite) return '';
  if (d == d.roundToDouble() && d.abs() < 1e15) return d.toInt().toString();
  var s = d.toStringAsFixed(10);
  s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return s;
}

/// Boş sondaki hücreleri ve tamamen boş satırları atar.
List<List<String>> _clean(Iterable<List<String>> rows) {
  final out = <List<String>>[];
  for (final r in rows) {
    final c = [for (final x in r) x.trim()];
    while (c.isNotEmpty && c.last.isEmpty) {
      c.removeLast();
    }
    if (c.isNotEmpty) out.add(c);
  }
  return out;
}

// ———————————————————————————— .ods (OpenDocument)

Sheets _odsSheets(Archive zip) {
  final f = zip.findFile('content.xml')!;
  final doc = XmlDocument.parse(utf8.decode(f.content as List<int>, allowMalformed: true));
  String? attr(XmlElement e, String local) => e.attributes.where((a) => a.name.local == local).firstOrNull?.value;
  final out = <(String, List<List<String>>)>[];
  for (final t in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'table' && e.name.prefix == 'table')) {
    final rows = <List<String>>[];
    for (final r in t.descendants.whereType<XmlElement>().where((e) => e.name.local == 'table-row')) {
      final cells = <String>[];
      for (final c in r.childElements.where((e) => e.name.local == 'table-cell' || e.name.local == 'covered-table-cell')) {
        final rep = (int.tryParse(attr(c, 'number-columns-repeated') ?? '') ?? 1).clamp(1, 256);
        final type = attr(c, 'value-type');
        var v = [for (final p in c.childElements.where((e) => e.name.local == 'p')) p.innerText].join('\n');
        if (type == 'float' || type == 'percentage' || type == 'currency') {
          final d = double.tryParse(attr(c, 'value') ?? '');
          if (d != null && type == 'float') v = _num(d);
        }
        for (var k = 0; k < rep; k++) {
          cells.add(v);
        }
      }
      final rep = (int.tryParse(attr(r, 'number-rows-repeated') ?? '') ?? 1).clamp(1, 1000);
      if (cells.any((x) => x.trim().isNotEmpty)) {
        for (var k = 0; k < rep; k++) {
          rows.add(cells);
        }
      }
    }
    final clean = _clean(rows);
    if (clean.isNotEmpty) out.add((attr(t, 'name') ?? '', clean));
  }
  return out;
}

// ———————————————————————————— HTML tablo / Excel 2003 XML

String _htmlUnescape(String s) => s
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAllMapped(RegExp(r'&#(x?)([0-9a-fA-F]+);'), (m) {
      final c = int.tryParse(m[2]!, radix: m[1]!.isEmpty ? 10 : 16);
      return c == null ? '' : String.fromCharCode(c);
    })
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&')
    .replaceAll(RegExp(r'[ \t\r\n]+'), ' ');

Sheets _htmlSheets(String html) {
  final out = <(String, List<List<String>>)>[];
  final tables = RegExp(r'<table\b.*?</table>', caseSensitive: false, dotAll: true).allMatches(html).toList();
  final sources = tables.isEmpty ? [html] : [for (final m in tables) m[0]!];
  final rowRe = RegExp(r'<tr\b.*?(?=<tr\b|</table>|$)', caseSensitive: false, dotAll: true);
  final cellRe = RegExp(r'<t([dh])\b([^>]*)>(.*?)(?=<t[dh]\b|</tr>|$)', caseSensitive: false, dotAll: true);
  for (final src in sources) {
    final rows = <List<String>>[];
    for (final r in rowRe.allMatches(src)) {
      final cells = <String>[];
      for (final c in cellRe.allMatches(r[0]!)) {
        final span = int.tryParse(RegExp(r'colspan\s*=\s*"?(\d+)', caseSensitive: false).firstMatch(c[2]!)?[1] ?? '') ?? 1;
        cells.add(_htmlUnescape(c[3]!.replaceFirst(RegExp(r'</t[dh]>.*$', caseSensitive: false, dotAll: true), '')).trim());
        for (var k = 1; k < span.clamp(1, 50); k++) {
          cells.add('');
        }
      }
      rows.add(cells);
    }
    final clean = _clean(rows);
    if (clean.isNotEmpty) out.add(('', clean));
  }
  return out;
}

Sheets _xml2003Sheets(String text) {
  final doc = XmlDocument.parse(text);
  final out = <(String, List<List<String>>)>[];
  String? attr(XmlElement e, String local) => e.attributes.where((a) => a.name.local == local).firstOrNull?.value;
  for (final ws in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'Worksheet')) {
    final rows = <List<String>>[];
    for (final r in ws.descendants.whereType<XmlElement>().where((e) => e.name.local == 'Row')) {
      final cells = <String>[];
      for (final c in r.childElements.where((e) => e.name.local == 'Cell')) {
        final idx = int.tryParse(attr(c, 'Index') ?? '');
        while (idx != null && cells.length < idx - 1) {
          cells.add('');
        }
        final data = c.childElements.where((e) => e.name.local == 'Data').firstOrNull;
        var v = data?.innerText ?? '';
        if (data != null && attr(data, 'Type') == 'Number') {
          final d = double.tryParse(v);
          if (d != null) v = _num(d);
        }
        cells.add(v);
      }
      rows.add(cells);
    }
    final clean = _clean(rows);
    if (clean.isNotEmpty) out.add((attr(ws, 'Name') ?? '', clean));
  }
  return out;
}

// ———————————————————————————— .xls (Excel 97–2003, BIFF8)

class _XlsReader {
  final Uint8List b;
  final ByteData d;
  _XlsReader(this.b) : d = ByteData.sublistView(b);

  int _u16(Uint8List x, int o) => x[o] | (x[o + 1] << 8);
  int _u32(Uint8List x, int o) => ByteData.sublistView(x).getUint32(o, Endian.little);

  /// OLE2 kabından "Workbook" akışını çıkarır.
  Uint8List? _workbookStream() {
    final secSize = 1 << d.getUint16(0x1E, Endian.little);
    final miniSize = 1 << d.getUint16(0x20, Endian.little);
    final dirStart = d.getInt32(0x30, Endian.little);
    final cutoff = d.getUint32(0x38, Endian.little);
    final miniFatStart = d.getInt32(0x3C, Endian.little);
    var difatNext = d.getInt32(0x44, Endian.little);
    int secOff(int s) => (s + 1) * secSize;

    // FAT sektörlerinin listesi (DIFAT).
    final fatSecs = <int>[];
    for (var i = 0; i < 109; i++) {
      final s = d.getInt32(0x4C + i * 4, Endian.little);
      if (s >= 0) fatSecs.add(s);
    }
    var guard = 0;
    while (difatNext >= 0 && guard++ < 10000) {
      final o = secOff(difatNext);
      if (o + secSize > b.length) break;
      for (var i = 0; i < secSize ~/ 4 - 1; i++) {
        final s = d.getInt32(o + i * 4, Endian.little);
        if (s >= 0) fatSecs.add(s);
      }
      difatNext = d.getInt32(o + secSize - 4, Endian.little);
    }
    final fat = <int>[];
    for (final s in fatSecs) {
      final o = secOff(s);
      if (o + secSize > b.length) break;
      for (var i = 0; i < secSize ~/ 4; i++) {
        fat.add(d.getInt32(o + i * 4, Endian.little));
      }
    }

    Uint8List chain(int start, {List<int>? table, Uint8List? from, int? unit, int? limit}) {
      final t = table ?? fat;
      final u = unit ?? secSize;
      final src = from ?? b;
      final out = BytesBuilder(copy: false);
      var s = start;
      var n = 0;
      while (s >= 0 && s < t.length && n++ < 1 << 20) {
        final o = from == null ? secOff(s) : s * u;
        if (o + u > src.length) {
          if (o < src.length) out.add(src.sublist(o));
          break;
        }
        out.add(Uint8List.sublistView(src, o, o + u));
        if (limit != null && out.length >= limit) break;
        s = t[s];
      }
      final r = out.takeBytes();
      return limit != null && r.length > limit ? r.sublist(0, limit) : r;
    }

    final dir = chain(dirStart);
    int? rootStart;
    int? rootSize;
    for (var o = 0; o + 128 <= dir.length; o += 128) {
      final nameLen = _u16(dir, o + 0x40);
      if (nameLen < 2 || nameLen > 64) continue;
      final name = String.fromCharCodes([for (var i = 0; i < nameLen - 2; i += 2) _u16(dir, o + i)]);
      final type = dir[o + 0x42];
      final start = ByteData.sublistView(dir).getInt32(o + 0x74, Endian.little);
      final size = _u32(dir, o + 0x78);
      if (type == 5) {
        rootStart = start;
        rootSize = size;
      }
      if (type == 2 && (name == 'Workbook' || name == 'Book')) {
        if (size < cutoff && rootStart != null) {
          final mini = chain(rootStart, limit: rootSize);
          final miniFat = <int>[];
          final mf = chain(miniFatStart);
          for (var i = 0; i + 4 <= mf.length; i += 4) {
            miniFat.add(ByteData.sublistView(mf).getInt32(i, Endian.little));
          }
          return chain(start, table: miniFat, from: mini, unit: miniSize, limit: size);
        }
        return chain(start, limit: size);
      }
    }
    return null;
  }

  Sheets sheets() {
    final wb = _workbookStream();
    if (wb == null) return const [];

    // Kayıtları ve sayfa başlangıçlarını topla.
    final sheetInfo = <(String, int)>[];
    final sst = <String>[];
    var p = 0;

    // Bir kaydı ve ardındaki CONTINUE parçalarını döner.
    List<Uint8List> withContinue(int at) {
      final parts = <Uint8List>[];
      var q = at;
      var first = true;
      while (q + 4 <= wb.length) {
        final id = _u16(wb, q);
        final len = _u16(wb, q + 2);
        if (!first && id != 0x3C) break;
        final end = (q + 4 + len).clamp(0, wb.length);
        parts.add(Uint8List.sublistView(wb, q + 4, end));
        q = end;
        first = false;
      }
      return parts;
    }

    while (p + 4 <= wb.length) {
      final id = _u16(wb, p);
      final len = _u16(wb, p + 2);
      final body = p + 4;
      if (body + len > wb.length) break;
      if (id == 0x85 && len >= 8) {
        // BOUNDSHEET
        final pos = _u32(wb, body);
        final type = wb[body + 5];
        final cch = wb[body + 6];
        final hi = wb[body + 7] & 1 == 1;
        final name = hi
            ? String.fromCharCodes([for (var i = 0; i < cch && body + 8 + i * 2 + 1 < wb.length; i++) _u16(wb, body + 8 + i * 2)])
            : String.fromCharCodes(wb.sublist(body + 8, (body + 8 + cch).clamp(0, wb.length)));
        if (type == 0) sheetInfo.add((name, pos));
      } else if (id == 0xFC) {
        sst.addAll(_readSst(withContinue(p)));
      } else if (id == 0x0A && sheetInfo.isNotEmpty) {
        break; // çalışma kitabı bölümünün sonu
      }
      p = body + len;
    }

    final out = <(String, List<List<String>>)>[];
    for (final (name, pos) in sheetInfo) {
      final cells = <int, Map<int, String>>{};
      void put(int r, int c, String v) => (cells[r] ??= {})[c] = v;
      var q = pos;
      var pendingFormula = (-1, -1);
      var started = false;
      while (q + 4 <= wb.length) {
        final id = _u16(wb, q);
        final len = _u16(wb, q + 2);
        final o = q + 4;
        if (o + len > wb.length) break;
        if (id == 0x0809) {
          if (started) break;
          started = true;
        } else if (id == 0x0A) {
          break;
        } else if (id == 0xFD && len >= 10) {
          final k = _u32(wb, o + 6);
          put(_u16(wb, o), _u16(wb, o + 2), k < sst.length ? sst[k] : '');
        } else if (id == 0x203 && len >= 14) {
          put(_u16(wb, o), _u16(wb, o + 2), _num(ByteData.sublistView(wb).getFloat64(o + 6, Endian.little)));
        } else if (id == 0x27E && len >= 10) {
          put(_u16(wb, o), _u16(wb, o + 2), _num(_rk(_u32(wb, o + 6))));
        } else if (id == 0xBD && len >= 6) {
          final r = _u16(wb, o);
          var c = _u16(wb, o + 2);
          for (var k = o + 4; k + 6 <= o + len - 2; k += 6, c++) {
            put(r, c, _num(_rk(_u32(wb, k + 2))));
          }
        } else if ((id == 0x204 || id == 0xD6) && len >= 8) {
          // LABEL / RSTRING
          final cch = _u16(wb, o + 6);
          final hi = len > 8 && wb[o + 8] & 1 == 1;
          final s = o + 9;
          put(_u16(wb, o), _u16(wb, o + 2),
              hi ? String.fromCharCodes([for (var i = 0; i < cch && s + i * 2 + 1 < o + len; i++) _u16(wb, s + i * 2)]) : String.fromCharCodes(wb.sublist(s, (s + cch).clamp(s, o + len))));
        } else if (id == 0x205 && len >= 8) {
          if (wb[o + 7] == 0) put(_u16(wb, o), _u16(wb, o + 2), wb[o + 6] == 1 ? 'TRUE' : 'FALSE');
        } else if (id == 0x06 && len >= 14) {
          final r = _u16(wb, o);
          final c = _u16(wb, o + 2);
          final res = Uint8List.sublistView(wb, o + 6, o + 14);
          if (res[6] == 0xFF && res[7] == 0xFF) {
            if (res[0] == 0) pendingFormula = (r, c);
            if (res[0] == 1) put(r, c, res[2] == 1 ? 'TRUE' : 'FALSE');
          } else {
            put(r, c, _num(ByteData.sublistView(res).getFloat64(0, Endian.little)));
          }
        } else if (id == 0x207 && pendingFormula.$1 >= 0) {
          final parts = withContinue(q);
          put(pendingFormula.$1, pendingFormula.$2, _Segments(parts).string(_u16(parts.first, 0), skip: 2));
          pendingFormula = (-1, -1);
        }
        q = o + len;
      }
      if (cells.isEmpty) continue;
      final rows = <List<String>>[];
      final keys = cells.keys.toList()..sort();
      for (final r in keys) {
        final m = cells[r]!;
        final maxC = m.keys.reduce((a, b) => a > b ? a : b);
        rows.add([for (var c = 0; c <= maxC; c++) m[c] ?? '']);
      }
      final clean = _clean(rows);
      if (clean.isNotEmpty) out.add((name, clean));
    }
    return out;
  }

  static double _rk(int rk) {
    double v;
    if (rk & 2 != 0) {
      v = (rk >> 2).toSigned(30).toDouble();
    } else {
      final bd = ByteData(8)..setUint32(4, rk & 0xFFFFFFFC, Endian.little);
      v = bd.getFloat64(0, Endian.little);
    }
    return rk & 1 != 0 ? v / 100 : v;
  }

  List<String> _readSst(List<Uint8List> parts) {
    final seg = _Segments(parts);
    seg.skip(4);
    final unique = seg.u32();
    final out = <String>[];
    for (var i = 0; i < unique && !seg.done; i++) {
      final cch = seg.u16();
      out.add(seg.string(cch, rich: true));
    }
    return out;
  }
}

/// SST gibi CONTINUE kayıtlarına bölünmüş veriyi sırayla okur. Bir dizgenin
/// karakterleri parça sınırına gelirse yeni parça bir seçenek baytıyla başlar.
class _Segments {
  final List<Uint8List> parts;
  int _i = 0;
  int _o = 0;
  _Segments(this.parts);

  bool get done => _i >= parts.length;

  void _norm() {
    while (_i < parts.length && _o >= parts[_i].length) {
      _i++;
      _o = 0;
    }
  }

  int byte() {
    _norm();
    if (done) return 0;
    return parts[_i][_o++];
  }

  int u16() => byte() | (byte() << 8);
  int u32() => u16() | (u16() << 16);

  void skip(int n) {
    for (var k = 0; k < n; k++) {
      byte();
    }
  }

  /// XLUnicodeRichExtendedString (cch okunduktan sonra).
  String string(int cch, {bool rich = false, int skip = 0}) {
    if (skip > 0) this.skip(skip);
    final flags = byte();
    var hi = flags & 1 == 1;
    final runs = rich && flags & 8 != 0 ? u16() : 0;
    final ext = rich && flags & 4 != 0 ? u32() : 0;
    final codes = <int>[];
    while (codes.length < cch && !done) {
      _norm();
      if (done) break;
      if (_o == 0 && codes.isNotEmpty) {
        hi = byte() & 1 == 1; // parça sınırı: yeni seçenek baytı
        _norm();
      }
      if (hi) {
        if (_o + 1 >= parts[_i].length) {
          codes.add(u16());
        } else {
          codes.add(parts[_i][_o] | (parts[_i][_o + 1] << 8));
          _o += 2;
        }
      } else {
        codes.add(parts[_i][_o++]);
      }
      // Bir sonraki karakter yeni parçadaysa döngü başında seçenek baytı okunur.
      if (_i < parts.length && _o >= parts[_i].length && codes.length < cch) {
        _i++;
        _o = 0;
      }
    }
    this.skip(runs * 4 + ext);
    return String.fromCharCodes(codes);
  }
}
