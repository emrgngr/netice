// Cihazlar arası eşitlemenin birleştirme kuralı (üç yönlü birleştirme).
//
// Her cihaz, son eşitlemede herkesin üzerinde anlaştığı hâlin kayıt kayıt
// "parmak izini" (base) saklar. Yeni eşitlemede her kayıt için:
//   * yalnız bu cihazda değiştiyse bu cihazınki,
//   * yalnız öteki tarafta değiştiyse ötekinin,
//   * iki tarafta da değiştiyse bu cihazınki (son dokunan kazanır),
//   * bir tarafta silinip öteki tarafta değişmediyse silinir,
//   * bir tarafta silinip öteki tarafta değiştiyse değişen kalır,
//   * yeni kayıtlar iki taraftan da eklenir.
// Böylece kayıtlara zaman damgası eklemeden, telefonda okunan kâğıtlarla
// bilgisayarda açılan sınavlar birbirini ezmeden birleşir.

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Eşitlenen listeler; geri kalan her şey (Pro, hesap, ses ayarları…)
/// cihaza aittir.
const syncLists = ['students', 'exams', 'sheets', 'templates'];

/// Eşitlenen tekil ayarlar.
const syncSingles = ['school', 'gradeScale', 'classroomLinks'];

/// Örnek veriler eşitlenmez (her cihazın kendi örneği var).
bool _isDemo(String list, Map<String, dynamic> r) => switch (list) {
      'students' => '${r['id']}'.startsWith('demo_') || '${r['id']}'.startsWith('demoB_'),
      'exams' => '${r['id']}'.startsWith('demo_exam'),
      'sheets' => '${r['examId']}'.startsWith('demo_exam'),
      _ => false,
    };

String _fingerprint(Object? v) => sha1.convert(utf8.encode(jsonEncode(v))).toString().substring(0, 16);

/// Listedeki kayıtların anahtarları (aynı sırada). Kâğıtların kimliği
/// yoktur; sınav + görüntü (yoksa öğrenci) ile tanınır, çakışanlara sıra
/// eki verilir.
List<String> _keys(String list, List<Map<String, dynamic>> rows) {
  final seen = <String, int>{};
  return [
    for (final r in rows)
      () {
        final base = list == 'sheets'
            ? '${r['examId']}|${r['imageId'] ?? r['studentId'] ?? r['readNumber'] ?? '-'}'
            : '${r['id']}';
        final n = seen[base] = (seen[base] ?? 0) + 1;
        return n == 1 ? base : '$base#$n';
      }(),
  ];
}

List<Map<String, dynamic>> _rows(Map<String, dynamic> j, String list) => [
      for (final r in (j[list] as List? ?? const []))
        if (r is Map && !_isDemo(list, r.cast<String, dynamic>())) r.cast<String, dynamic>(),
    ];

/// Bir veri hâlinin kayıt parmak izleri: "liste/anahtar" → iz.
Map<String, String> syncFingerprints(Map<String, dynamic> j) {
  final out = <String, String>{};
  for (final list in syncLists) {
    final rows = _rows(j, list);
    final keys = _keys(list, rows);
    for (var i = 0; i < rows.length; i++) {
      out['$list/${keys[i]}'] = _fingerprint(rows[i]);
    }
  }
  for (final s in syncSingles) {
    if (j[s] != null) out['=$s'] = _fingerprint(j[s]);
  }
  return out;
}

class SyncMergeResult {
  /// Birleşmiş eşitleme verisi (yalnız [syncLists] ve [syncSingles]).
  final Map<String, dynamic> merged;

  /// Bu cihazdaki veride değişen kayıt sayısı (öteki cihazdan gelen).
  final int incoming;

  /// Öteki tarafa giden kayıt sayısı.
  final int outgoing;

  const SyncMergeResult(this.merged, this.incoming, this.outgoing);
}

/// [local]: bu cihazın verisi, [remote]: Drive'daki eşitleme dosyası (ilk
/// eşitlemede null), [base]: son eşitlemedeki parmak izleri.
SyncMergeResult syncMerge(Map<String, dynamic> local, Map<String, dynamic>? remote, Map<String, String> base) {
  final merged = <String, dynamic>{};
  var incoming = 0, outgoing = 0;
  final rem = remote ?? const <String, dynamic>{};

  for (final list in syncLists) {
    final lRows = _rows(local, list), rRows = _rows(rem, list);
    final lKeys = _keys(list, lRows), rKeys = _keys(list, rRows);
    final lMap = {for (var i = 0; i < lRows.length; i++) lKeys[i]: lRows[i]};
    final rMap = {for (var i = 0; i < rRows.length; i++) rKeys[i]: rRows[i]};
    final out = <Map<String, dynamic>>[];

    Map<String, dynamic>? decide(String k) {
      final l = lMap[k], r = rMap[k];
      final b = base['$list/$k'];
      final lf = l == null ? null : _fingerprint(l), rf = r == null ? null : _fingerprint(r);
      if (lf == rf) return l;
      if (l == null) {
        // Burada yok: hiç gelmemiş (yeni) ya da burada silinmiş.
        if (b == null || rf != b) {
          incoming++;
          return r;
        }
        outgoing++; // silme ötekine gider
        return null;
      }
      if (r == null) {
        if (b == null || lf != b) {
          outgoing++;
          return l;
        }
        incoming++; // ötekinde silinmiş
        return null;
      }
      if (lf == b) {
        incoming++;
        return r;
      }
      outgoing++;
      return l;
    }

    // Sıra: bu cihazdaki sıra korunur; öteki taraftan gelen yeni kayıtlar
    // sınavlarda başa (en yeni üstte), diğerlerinde sona eklenir.
    final fresh = <Map<String, dynamic>>[];
    for (final k in lKeys) {
      final v = decide(k);
      if (v != null) out.add(v);
    }
    for (final k in rKeys) {
      if (lMap.containsKey(k)) continue;
      final v = decide(k);
      if (v != null) fresh.add(v);
    }
    merged[list] = list == 'exams' ? [...fresh, ...out] : [...out, ...fresh];
  }

  for (final s in syncSingles) {
    final l = local[s], r = rem[s];
    final b = base['=$s'];
    final lf = l == null ? null : _fingerprint(l), rf = r == null ? null : _fingerprint(r);
    Object? v;
    if (lf == rf) {
      v = l;
    } else if (r != null && (l == null || lf == b)) {
      v = r;
      incoming++;
    } else {
      v = l;
      if (l != null) outgoing++;
    }
    if (v != null) merged[s] = v;
  }
  return SyncMergeResult(merged, incoming, outgoing);
}
