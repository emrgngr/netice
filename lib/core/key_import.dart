import 'dart:math' as math;

/// Bir cevap anahtarı belgesinden (PDF, Word, Excel, metin ya da görselden
/// okunan yazı) çıkarılan bilgiler.
class KeyImport {
  /// Kitapçık (0 = A, 1 = B…) → soru sırasıyla doğru şık (bulunamayan null).
  final Map<int, List<int?>> keys;

  /// Soru numarası (1'den) → konu / kazanım adı.
  final Map<int, String> topics;

  const KeyImport(this.keys, this.topics);

  bool get isEmpty => keys.isEmpty && topics.isEmpty;

  /// Kaç kitapçıkta en az bir cevap bulundu.
  int get bookletCount => keys.isEmpty ? 0 : keys.keys.reduce(math.max) + 1;

  int filledOf(int booklet) => keys[booklet]?.where((c) => c != null).length ?? 0;
}

const _letters = 'ABCDEFGH';

// "A kitapçığı", "B Grubu", "C KİTAPÇIĞI", "Booklet D", "Kitapçık türü: E"…
final _bookletAfter = RegExp(
  r'(?<![A-Za-zÇĞİÖŞÜçğıöşü])([A-Ha-h])\s*[-–.]?\s*(?:KİTAPÇI[ĞG]I|KITAPCI[ĞG]I|Kitapçığı|kitapçığı|Kitapcigi|kitapcigi|'
  r'KİTAPÇIK|KITAPCIK|Kitapçık|kitapçık|GRUBU|Grubu|grubu|BOOKLET|Booklet|booklet|FORMU|Formu|formu)',
);
final _bookletBefore = RegExp(
  r'(?:KİTAPÇIK|KITAPCIK|Kitapçık|kitapçık|Kitapcik|kitapcik|BOOKLET|Booklet|booklet|GRUP|Grup|grup)'
  r'\s*(?:TÜRÜ|türü|turu|TYPE|type)?\s*[:\-–]?\s*([A-H])(?![A-Za-zÇĞİÖŞÜçğıöşü])',
);

// "12-C", "12. C", "12) c", "Soru 12: C", "12 C"
final _pair = RegExp(r'(?<!\d)(\d{1,3})\s*[.)\-:–]?\s*([A-Ha-h])(?![A-Za-zÇĞİÖŞÜçğıöşü0-9])');
// "ABCDEABCDE" (art arda büyük harfler)
final _compact = RegExp(r'(?<![A-Za-zÇĞİÖŞÜçğıöşü])([A-H]{5,})(?![A-Za-zÇĞİÖŞÜçğıöşü])');
// "1-5 Hareket", "6 – 10: Kuvvet"
final _range = RegExp(r'^\s*(\d{1,3})\s*[-–]\s*(\d{1,3})\s*[:.)\-–|]?\s+([^\d|].{2,}?)\s*$');

/// Cevap anahtarı belgesinin yazısını çözer. Her kitapçığın cevaplarını ve
/// varsa soru–konu dağılımını döndürür. [choices] dışındaki şıklar yok sayılır.
KeyImport parseKeyText(String text, {required int questions, required int choices}) {
  final keys = <int, List<int?>>{};
  final topics = <int, String>{};
  var booklet = 0;
  List<int>? columns; // Tablo başlığında birden çok kitapçık varsa sütun sırası.
  final next = <int, int>{}; // Art arda yazılmış harfler için kitapçık başına sıradaki soru.

  List<int?> keyOf(int b) => keys.putIfAbsent(b, () => List<int?>.filled(questions, null));

  void put(int b, int q, String letter) {
    final c = letter.toUpperCase().codeUnitAt(0) - 65;
    if (q < 1 || q > questions || c < 0 || c >= choices) return;
    keyOf(b)[q - 1] = c;
    next[b] = q;
  }

  int? topicLine; // Bir önceki satırda konusu yazılan soru (taşan hücre için).
  void topic(int q, String raw) {
    final t = _cleanTopic(raw);
    if (t == null || q < 1 || q > questions) return;
    if (topics.containsKey(q)) return;
    topics[q] = t;
    topicLine = q;
  }

  for (var line in text.split(RegExp(r'\r?\n'))) {
    line = line.replaceAll('\t', ' | ').replaceAll(RegExp(r'[  ]+'), ' ').trim();
    if (line.isEmpty) continue;

    // PDF tablolarında satıra sığmayan konu alt satıra taşar: "Fizik biliminin" / "önemi".
    final prev = topicLine;
    topicLine = null;
    if (prev != null && RegExp(r'^[a-zçğıöşü]').hasMatch(line) && !RegExp(r'\d').hasMatch(line) && line.length < 60) {
      topics[prev] = '${topics[prev]} ${_cleanTopic(line) ?? line}';
      continue;
    }

    // Kitapçık başlıkları.
    final heads = <int>[
      for (final m in _bookletAfter.allMatches(line)) _letters.indexOf(m.group(1)!.toUpperCase()),
      for (final m in _bookletBefore.allMatches(line)) _letters.indexOf(m.group(1)!),
    ];
    final hasDigits = RegExp(r'\d').hasMatch(line);
    if (heads.length >= 2 && !_pair.hasMatch(line)) {
      // "Soru | A Kitapçığı | B Kitapçığı | Konu" gibi tablo başlığı.
      final order = <int>[];
      for (final m in RegExp(r'(?<![A-Za-zÇĞİÖŞÜçğıöşü])([A-H])(?![A-Za-zÇĞİÖŞÜçğıöşü])').allMatches(line)) {
        order.add(_letters.indexOf(m.group(1)!));
      }
      columns = order.length >= 2 ? order : heads;
      continue;
    }
    if (heads.length == 1 && !hasDigits) {
      booklet = heads.first;
      columns = null;
      continue;
    }
    if (heads.length == 1) booklet = heads.first;

    // Tablo satırı: "1 | C | A | Hareket" (sütun başına bir kitapçık).
    if (columns != null) {
      final cells = line.split(RegExp(r'\s*\|\s*|\s+'));
      final q = int.tryParse(cells.first.replaceAll(RegExp(r'[.)\-:]'), ''));
      if (q != null) {
        final rest = cells.skip(1).where((c) => c.isNotEmpty).toList();
        var used = 0;
        for (var k = 0; k < columns.length && k < rest.length; k++) {
          if (RegExp(r'^[A-Ha-h]$').hasMatch(rest[k])) {
            put(columns[k], q, rest[k]);
            used = k + 1;
          } else {
            break;
          }
        }
        if (used > 0) {
          final m = RegExp(r'^\s*\d{1,3}[.)\-:]?\s*(?:\|?\s*[A-Ha-h]\s*){' '$used' r'}\|?\s*(.*)$').firstMatch(line);
          if (m != null) topic(q, m.group(1)!);
          continue;
        }
      }
    }

    // Konu aralığı: "1-5 Hareket".
    final range = _range.firstMatch(line);
    if (range != null && !RegExp(r'^[A-Ha-h](?:\s|$)').hasMatch(range.group(3)!)) {
      final a = int.parse(range.group(1)!), b = int.parse(range.group(2)!);
      if (a <= b && b - a < questions) {
        for (var q = a; q <= b; q++) {
          topic(q, range.group(3)!);
        }
        continue;
      }
    }

    // "1-A 2-C 3-B" ya da "1. C Hareket".
    final pairs = _pair.allMatches(line).toList();
    if (pairs.isNotEmpty) {
      for (final m in pairs) {
        put(booklet, int.parse(m.group(1)!), m.group(2)!);
      }
      if (pairs.length == 1) topic(int.parse(pairs.first.group(1)!), line.substring(pairs.first.end));
      continue;
    }

    // "ABCDEABCDE…": sıradaki sorulardan devam eder.
    for (final m in _compact.allMatches(line)) {
      var q = (next[booklet] ?? 0) + 1;
      for (final ch in m.group(1)!.split('')) {
        put(booklet, q++, ch);
      }
    }
  }

  keys.removeWhere((_, v) => v.every((c) => c == null));
  return KeyImport(keys, topics);
}

String? _cleanTopic(String raw) {
  var t = raw.replaceAll('|', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  t = t.replaceAll(RegExp(r'^[\s:;,.\-–)]+|[\s:;,\-–]+$'), '').trim();
  // Yalnız harf/sayı artığı (ör. başka sütunun şıkkı) konu değildir.
  if (t.length < 3 || !RegExp(r'[A-Za-zÇĞİÖŞÜçğıöşü]{3,}').hasMatch(t)) return null;
  if (RegExp(r'^(?:[A-Ha-h]\s+)+[A-Ha-h]?$').hasMatch(t)) return null;
  return t;
}

/// Konu dağılımını "1-5 Hareket" satırlarına çevirir (Kazanımlar kutusu için).
String topicsToRanges(Map<int, String> topics, int questions) {
  final lines = <String>[];
  int? start;
  String? name;
  void flush(int end) {
    if (start != null && name != null) lines.add(start == end ? '$start $name' : '$start-$end $name');
  }

  for (var q = 1; q <= questions + 1; q++) {
    final t = q <= questions ? topics[q] : null;
    if (t != name) {
      flush(q - 1);
      start = t == null ? null : q;
      name = t;
    }
  }
  return lines.join('\n');
}

/// Yazı tanımanın bulduğu satırları (kutu: sol, üst, sağ, alt, yazı) görüntüdeki
/// yerlerine göre sıraya koyar: aynı yükseklikteki parçalar tek satırda,
/// soldan sağa " | " ile birleşir (tablolar satır satır okunur).
String rowsFromBoxes(List<(double, double, double, double, String)> boxes) {
  if (boxes.isEmpty) return '';
  final items = [...boxes]..sort((a, b) => (a.$2 + a.$4).compareTo(b.$2 + b.$4));
  final heights = [for (final b in items) b.$4 - b.$2]..sort();
  final tol = math.max(4.0, heights[heights.length ~/ 2] * 0.6);
  final rows = <List<(double, double, double, double, String)>>[];
  double? rowY;
  for (final b in items) {
    final cy = (b.$2 + b.$4) / 2;
    if (rowY == null || (cy - rowY).abs() > tol) {
      rows.add([b]);
      rowY = cy;
    } else {
      rows.last.add(b);
    }
  }
  return [
    for (final r in rows) (r..sort((a, b) => a.$1.compareTo(b.$1))).map((b) => b.$5.trim()).join(' | '),
  ].join('\n');
}
