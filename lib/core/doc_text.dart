import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'spreadsheet.dart';

/// Belgedeki yazıyı satır satır çıkarır: PDF, Word (.docx), Excel (.xlsx, .xls),
/// LibreOffice (.ods),
/// metin (.txt, .csv). Tablolarda hücreler " | " ile ayrılır. Desteklenmeyen
/// biçimde ya da yazı bulunamazsa boş metin döner.
String documentText(Uint8List bytes, String fileName) {
  final ext = fileName.contains('.') ? fileName.substring(fileName.lastIndexOf('.') + 1).toLowerCase() : '';
  try {
    switch (ext) {
      case 'pdf':
        return pdfText(bytes);
      case 'docx':
        return docxText(bytes);
      case 'xlsx' || 'xls' || 'ods':
        return [
          for (final (name, rows) in spreadsheetSheets(bytes, fileName) ?? const <(String, List<List<String>>)>[]) ...[
            if (name.isNotEmpty) name,
            for (final r in rows) r.where((c) => c.trim().isNotEmpty).join(' | '),
          ],
        ].join('\n');
      default:
        if (bytes.length > 4 && bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46) {
          return pdfText(bytes);
        }
        return utf8.decode(bytes, allowMalformed: true);
    }
  } catch (_) {
    return '';
  }
}

/// Word (.docx): paragraflar satır, tablo satırları " | " ile ayrılmış hücreler.
String docxText(Uint8List bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  final f = zip.findFile('word/document.xml');
  if (f == null) return '';
  final doc = XmlDocument.parse(utf8.decode(f.content as List<int>, allowMalformed: true));
  final out = StringBuffer();

  String para(XmlElement p) {
    final b = StringBuffer();
    for (final n in p.descendants.whereType<XmlElement>()) {
      switch (n.name.local) {
        case 't':
          b.write(n.innerText);
        case 'tab':
          b.write(' | ');
        case 'br':
          b.write('\n');
      }
    }
    return b.toString();
  }

  void walk(XmlElement e) {
    for (final c in e.childElements) {
      switch (c.name.local) {
        case 'p':
          out.writeln(para(c));
        case 'tbl':
          for (final row in c.childElements.where((r) => r.name.local == 'tr')) {
            final cells = [
              for (final cell in row.childElements.where((x) => x.name.local == 'tc'))
                cell.findAllElements('p', namespaceUri: '*').map(para).join(' ').trim(),
            ];
            out.writeln(cells.join(' | '));
          }
        default:
          walk(c);
      }
    }
  }

  walk(doc.rootElement);
  return out.toString();
}

// ---------------------------------------------------------------------------
// PDF: küçük bir yazı çıkarıcı. Sıkıştırılmış (Flate) içerik ve nesne akışları,
// ToUnicode eşlemeli yazı tipleri (Word/LibreOffice çıktıları) ve standart
// yazı tipleri desteklenir. Taranmış (yalnız görüntü) PDF'lerde yazı yoktur.

class _Obj {
  final String dict; // "<< … >>" ya da nesnenin tüm gövdesi
  final Uint8List? stream; // çözülmüş akış (varsa)
  _Obj(this.dict, this.stream);
}

class _CMap {
  final int bytes;
  final Map<int, String> map;
  _CMap(this.bytes, this.map);
}

String pdfText(Uint8List data) {
  final raw = latin1.decode(data);
  final objs = <int, _Obj>{};

  Uint8List? decode(String dict, Uint8List body) {
    // Süzgeçler sırayla uygulanır: ör. [/ASCII85Decode /FlateDecode].
    final fm = RegExp(r'/Filter\s*(\[[^\]]*\]|/\w+)').firstMatch(dict);
    if (fm == null) return body;
    var out = body;
    for (final f in RegExp(r'/(\w+)').allMatches(fm.group(1)!).map((m) => m.group(1)!)) {
      switch (f) {
        case 'FlateDecode' || 'Fl':
          try {
            out = Uint8List.fromList(const ZLibDecoder().decodeBytes(out));
          } catch (_) {
            try {
              out = Uint8List.fromList(Inflate(out).getBytes());
            } catch (_) {
              return null;
            }
          }
        case 'ASCII85Decode' || 'A85':
          out = _ascii85(out);
        case 'ASCIIHexDecode' || 'AHx':
          final h = latin1.decode(out).replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
          out = Uint8List.fromList([for (var k = 0; k + 1 < h.length; k += 2) int.parse(h.substring(k, k + 2), radix: 16)]);
        default:
          return null;
      }
    }
    return out;
  }

  final objRe = RegExp(r'(\d+)\s+\d+\s+obj\b');
  for (final m in objRe.allMatches(raw)) {
    final num = int.parse(m.group(1)!);
    final start = m.end;
    final end = raw.indexOf('endobj', start);
    if (end < 0) continue;
    var body = raw.substring(start, end);
    final si = body.indexOf('stream');
    if (si >= 0 && body.substring(0, si).contains('<<')) {
      final dict = body.substring(0, si);
      var ds = start + si + 6;
      if (raw.startsWith('\r\n', ds)) {
        ds += 2;
      } else if (raw.startsWith('\n', ds) || raw.startsWith('\r', ds)) {
        ds += 1;
      }
      var de = raw.lastIndexOf('endstream', end);
      if (de < ds) de = end;
      final len = RegExp(r'/Length\s+(\d+)(?!\s+\d+\s+R)').firstMatch(dict);
      if (len != null) {
        final l = int.parse(len.group(1)!);
        if (ds + l <= de) de = ds + l;
      }
      objs[num] = _Obj(dict, decode(dict, Uint8List.sublistView(data, ds, de)));
    } else {
      objs[num] = _Obj(body, null);
    }
  }

  // Nesne akışlarındaki (ObjStm) nesneler.
  for (final o in objs.values.toList()) {
    if (!o.dict.contains('/ObjStm') || o.stream == null) continue;
    final n = int.tryParse(RegExp(r'/N\s+(\d+)').firstMatch(o.dict)?.group(1) ?? '') ?? 0;
    final first = int.tryParse(RegExp(r'/First\s+(\d+)').firstMatch(o.dict)?.group(1) ?? '') ?? 0;
    final s = latin1.decode(o.stream!);
    final head = s.substring(0, first.clamp(0, s.length)).trim().split(RegExp(r'\s+'));
    for (var i = 0; i + 1 < head.length && i ~/ 2 < n; i += 2) {
      final num = int.tryParse(head[i]);
      final off = int.tryParse(head[i + 1]);
      if (num == null || off == null) continue;
      final a = first + off;
      final b = i + 3 < head.length ? first + (int.tryParse(head[i + 3]) ?? s.length - first) : s.length;
      if (a < s.length && !objs.containsKey(num)) objs[num] = _Obj(s.substring(a, b.clamp(a, s.length)), null);
    }
  }

  String body(int n) => objs[n]?.dict ?? '';
  int? ref(String dict, String key) {
    final m = RegExp('/$key\\s+(\\d+)\\s+\\d+\\s+R').firstMatch(dict);
    return m == null ? null : int.parse(m.group(1)!);
  }

  String? inlineDict(String dict, String key) {
    final i = dict.indexOf('/$key');
    if (i < 0) return null;
    var j = i + key.length + 1;
    while (j < dict.length && dict[j].trim().isEmpty) {
      j++;
    }
    if (!dict.startsWith('<<', j)) return null;
    var depth = 0;
    for (var k = j; k < dict.length - 1; k++) {
      if (dict.startsWith('<<', k)) {
        depth++;
        k++;
      } else if (dict.startsWith('>>', k)) {
        depth--;
        k++;
        if (depth == 0) return dict.substring(j, k + 1);
      }
    }
    return null;
  }

  // Yazı tipi → ToUnicode eşlemesi.
  final cmaps = <int, _CMap?>{};
  _CMap? cmapOfFont(int fontObj) => cmaps.putIfAbsent(fontObj, () {
        final r = ref(body(fontObj), 'ToUnicode');
        final st = r == null ? null : objs[r]?.stream;
        return st == null ? null : _parseCMap(latin1.decode(st));
      });

  Map<String, int> fontsOf(String resources) {
    var fd = inlineDict(resources, 'Font');
    if (fd == null) {
      final r = ref(resources, 'Font');
      if (r != null) fd = body(r);
    }
    if (fd == null) return {};
    return {for (final m in RegExp(r'/([^\s/<>\[\]()]+)\s+(\d+)\s+\d+\s+R').allMatches(fd)) m.group(1)!: int.parse(m.group(2)!)};
  }

  String resourcesOf(int page) {
    var n = page;
    for (var guard = 0; guard < 20; guard++) {
      final d = body(n);
      final inl = inlineDict(d, 'Resources');
      if (inl != null) return inl;
      final r = ref(d, 'Resources');
      if (r != null) return body(r);
      final p = ref(d, 'Parent');
      if (p == null) break;
      n = p;
    }
    return '';
  }

  // Sayfalar, sayfa ağacındaki sırayla.
  final pages = <int>[];
  final isPage = RegExp(r'/Type\s*/Page(?![s\w])');
  final isPages = RegExp(r'/Type\s*/Pages\b');
  void kids(int n, int depth) {
    if (depth > 30) return;
    final d = body(n);
    if (isPage.hasMatch(d)) {
      pages.add(n);
      return;
    }
    final k = RegExp(r'/Kids\s*\[([^\]]*)\]').firstMatch(d);
    if (k == null) return;
    for (final m in RegExp(r'(\d+)\s+\d+\s+R').allMatches(k.group(1)!)) {
      kids(int.parse(m.group(1)!), depth + 1);
    }
  }

  final roots = [
    for (final e in objs.entries)
      if (isPages.hasMatch(e.value.dict) && !e.value.dict.contains('/Parent')) e.key
  ];
  for (final r in roots) {
    kids(r, 0);
  }
  if (pages.isEmpty) {
    pages.addAll([for (final e in objs.entries) if (isPage.hasMatch(e.value.dict)) e.key]..sort());
  }

  final out = StringBuffer();
  for (final p in pages) {
    final d = body(p);
    final fonts = fontsOf(resourcesOf(p));
    final contents = <int>[];
    final arr = RegExp(r'/Contents\s*\[([^\]]*)\]').firstMatch(d);
    if (arr != null) {
      contents.addAll(RegExp(r'(\d+)\s+\d+\s+R').allMatches(arr.group(1)!).map((m) => int.parse(m.group(1)!)));
    } else {
      final c = ref(d, 'Contents');
      if (c != null) contents.add(c);
    }
    final bytes = BytesBuilder();
    for (final c in contents) {
      final s = objs[c]?.stream;
      if (s != null) {
        bytes
          ..add(s)
          ..addByte(10);
      }
    }
    _runContent(bytes.takeBytes(), (name) {
      final f = fonts[name];
      return f == null ? null : cmapOfFont(f);
    }, out);
    out.writeln();
  }
  return out.toString();
}

_CMap _parseCMap(String s) {
  var nbytes = 1;
  final cs = RegExp(r'begincodespacerange\s*<([0-9A-Fa-f]+)>').firstMatch(s);
  if (cs != null) nbytes = (cs.group(1)!.length / 2).ceil();
  final map = <int, String>{};
  String hexStr(String h) {
    if (h.length <= 2) return h.isEmpty ? '' : String.fromCharCode(int.parse(h, radix: 16));
    return String.fromCharCodes([for (var i = 0; i + 4 <= h.length; i += 4) int.parse(h.substring(i, i + 4), radix: 16)]);
  }

  for (final block in RegExp(r'beginbfchar(.*?)endbfchar', dotAll: true).allMatches(s)) {
    for (final m in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]*)>').allMatches(block.group(1)!)) {
      map[int.parse(m.group(1)!, radix: 16)] = hexStr(m.group(2)!);
    }
  }
  for (final block in RegExp(r'beginbfrange(.*?)endbfrange', dotAll: true).allMatches(s)) {
    for (final m in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*(<[0-9A-Fa-f]*>|\[[^\]]*\])').allMatches(block.group(1)!)) {
      final lo = int.parse(m.group(1)!, radix: 16), hi = int.parse(m.group(2)!, radix: 16);
      final dst = m.group(3)!;
      if (hi - lo > 0xFFFF) continue;
      if (dst.startsWith('[')) {
        final list = RegExp(r'<([0-9A-Fa-f]*)>').allMatches(dst).map((x) => hexStr(x.group(1)!)).toList();
        for (var c = lo; c <= hi && c - lo < list.length; c++) {
          map[c] = list[c - lo];
        }
      } else {
        final base = hexStr(dst.substring(1, dst.length - 1));
        if (base.isEmpty) continue;
        final last = base.codeUnitAt(base.length - 1);
        for (var c = lo; c <= hi; c++) {
          map[c] = base.substring(0, base.length - 1) + String.fromCharCode(last + (c - lo));
        }
      }
    }
  }
  return _CMap(nbytes, map);
}

// WinAnsi'nin 0x80–0x9F aralığı ve Türkçe karakterler için kaba eşleme.
String _latin(List<int> b) => String.fromCharCodes(b.map((c) => switch (c) {
      0x91 || 0x92 => 0x27,
      0x93 || 0x94 => 0x22,
      0x96 || 0x97 => 0x2D,
      _ => c,
    }));

void _runContent(Uint8List s, _CMap? Function(String font) fontMap, StringBuffer out) {
  final ops = <Object>[];
  _CMap? cmap;
  // Yazı konumu: satır başının y'si (Td ile göreli, Tm/BT ile mutlak).
  var lineY = 0.0;
  double? lastTextY;
  var forceBreak = false;
  var pendingSpace = false;
  // Grafik dönüşümünün dikey kısmı (cm ile; q/Q yığını). Tablo hücreleri
  // çoğu zaman "cm" ile yerleştirilir.
  var ctmD = 1.0, ctmF = 0.0;
  final stack = <(double, double)>[];
  double absY() => ctmD * lineY + ctmF;

  void emit(String t) {
    final y = absY();
    if (lastTextY != null) {
      if (forceBreak || (y - lastTextY!).abs() > 1) {
        out.writeln();
      } else if (pendingSpace) {
        out.write(' ');
      }
    }
    forceBreak = false;
    pendingSpace = false;
    lastTextY = y;
    out.write(t);
  }

  void text(List<int> bytes) {
    if (cmap == null) {
      emit(_latin(bytes));
      return;
    }
    final b = StringBuffer();
    final n = cmap.bytes;
    for (var i = 0; i + n <= bytes.length; i += n) {
      var code = 0;
      for (var k = 0; k < n; k++) {
        code = (code << 8) | bytes[i + k];
      }
      b.write(cmap.map[code] ?? (n == 1 ? String.fromCharCode(code) : ''));
    }
    emit(b.toString());
  }

  void newline() => forceBreak = true;
  void space() => pendingSpace = true;

  var i = 0;
  final n = s.length;
  bool isWs(int c) => c == 32 || c == 10 || c == 13 || c == 9 || c == 12 || c == 0;
  bool isDelim(int c) => c == 40 || c == 41 || c == 60 || c == 62 || c == 91 || c == 93 || c == 47 || c == 123 || c == 125 || c == 37;

  List<int> literal() {
    final b = <int>[];
    var depth = 1;
    i++;
    while (i < n) {
      final c = s[i];
      if (c == 92 && i + 1 < n) {
        i++;
        final e = s[i];
        switch (e) {
          case 110:
            b.add(10);
          case 114:
            b.add(13);
          case 116:
            b.add(9);
          case 98:
            b.add(8);
          case 102:
            b.add(12);
          case 10:
            break;
          case 13:
            if (i + 1 < n && s[i + 1] == 10) i++;
          default:
            if (e >= 48 && e <= 55) {
              var v = e - 48;
              for (var k = 0; k < 2 && i + 1 < n && s[i + 1] >= 48 && s[i + 1] <= 55; k++) {
                i++;
                v = v * 8 + s[i] - 48;
              }
              b.add(v & 0xFF);
            } else {
              b.add(e);
            }
        }
      } else if (c == 40) {
        depth++;
        b.add(c);
      } else if (c == 41) {
        depth--;
        if (depth == 0) {
          i++;
          return b;
        }
        b.add(c);
      } else {
        b.add(c);
      }
      i++;
    }
    return b;
  }

  List<int> hex() {
    i++;
    final h = StringBuffer();
    while (i < n && s[i] != 62) {
      if (!isWs(s[i])) h.writeCharCode(s[i]);
      i++;
    }
    i++;
    var str = h.toString();
    if (str.length.isOdd) str += '0';
    return [for (var k = 0; k + 1 < str.length; k += 2) int.tryParse(str.substring(k, k + 2), radix: 16) ?? 0];
  }

  final arrays = <List<Object>>[];
  void push(Object o) => arrays.isEmpty ? ops.add(o) : arrays.last.add(o);
  double num(int back) {
    final k = ops.length - back;
    return k >= 0 && ops[k] is double ? ops[k] as double : 0;
  }

  while (i < n) {
    final c = s[i];
    if (isWs(c)) {
      i++;
    } else if (c == 37) {
      while (i < n && s[i] != 10 && s[i] != 13) {
        i++;
      }
    } else if (c == 40) {
      push(literal());
    } else if (c == 60 && i + 1 < n && s[i + 1] == 60) {
      i += 2;
      push('<<');
    } else if (c == 62 && i + 1 < n && s[i + 1] == 62) {
      i += 2;
    } else if (c == 60) {
      push(hex());
    } else if (c == 91) {
      arrays.add([]);
      i++;
    } else if (c == 93) {
      i++;
      if (arrays.isNotEmpty) {
        final a = arrays.removeLast();
        push(a);
      }
    } else if (c == 47) {
      final st = ++i;
      while (i < n && !isWs(s[i]) && !isDelim(s[i])) {
        i++;
      }
      push('/${latin1.decode(s.sublist(st, i))}');
    } else {
      final st = i;
      while (i < n && !isWs(s[i]) && !isDelim(s[i])) {
        i++;
      }
      if (i == st) {
        i++;
        continue;
      }
      final tok = latin1.decode(s.sublist(st, i));
      final v = double.tryParse(tok);
      if (v != null) {
        push(v);
        continue;
      }
      switch (tok) {
        case 'BI':
          // Satır içi görüntü: EI'ye kadar atla.
          final ei = latin1.decode(s.sublist(i)).indexOf(RegExp(r'\sEI\s'));
          i = ei < 0 ? n : i + ei + 4;
        case 'Tf':
          final k = ops.length - 2;
          if (k >= 0 && ops[k] is String && (ops[k] as String).startsWith('/')) cmap = fontMap((ops[k] as String).substring(1));
        case 'Tj':
          if (ops.isNotEmpty && ops.last is List<int>) text(ops.last as List<int>);
        case "'" || '"':
          newline();
          if (ops.isNotEmpty && ops.last is List<int>) text(ops.last as List<int>);
        case 'TJ':
          if (ops.isNotEmpty && ops.last is List<Object>) {
            for (final e in ops.last as List<Object>) {
              if (e is List<int>) {
                text(e);
              } else if (e is double && e < -180) {
                space();
              }
            }
          }
        case 'q':
          stack.add((ctmD, ctmF));
        case 'Q':
          if (stack.isNotEmpty) (ctmD, ctmF) = stack.removeLast();
        case 'cm':
          // Yeni = m × eski; yalnız dikey bileşenler (döndürme yok sayılır).
          final d = num(3), f = num(1);
          ctmF = f * ctmD + ctmF;
          ctmD = d * ctmD;
          space();
        case 'BT':
          lineY = 0;
        case 'Td' || 'TD':
          final ty = num(1), tx = num(2);
          lineY += ty;
          if (tx.abs() > 0.5) space();
        case 'T*':
          newline();
        case 'Tm':
          // Mutlak konum: önceki T*'ın satır sonu yerine y karşılaştırılır.
          lineY = num(1);
          forceBreak = false;
          space();
        case 'ET':
          space();
      }
      ops.clear();
    }
  }
}

Uint8List _ascii85(Uint8List b) {
  final out = <int>[];
  final group = <int>[];
  for (var i = 0; i < b.length; i++) {
    final c = b[i];
    if (c == 126) break; // "~>" sonu
    if (c <= 32) continue;
    if (c == 122 && group.isEmpty) {
      out.addAll(const [0, 0, 0, 0]);
      continue;
    }
    if (c < 33 || c > 117) continue;
    group.add(c - 33);
    if (group.length == 5) {
      var v = 0;
      for (final d in group) {
        v = v * 85 + d;
      }
      out.addAll([(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255]);
      group.clear();
    }
  }
  if (group.isNotEmpty) {
    final n = group.length;
    while (group.length < 5) {
      group.add(84);
    }
    var v = 0;
    for (final d in group) {
      v = v * 85 + d;
    }
    out.addAll([(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255].take(n - 1));
  }
  return Uint8List.fromList(out);
}
