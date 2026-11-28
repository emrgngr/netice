/// Uygulama içi arama: öğrenciler, sınıflar, sınavlar, soru bankası,
/// özellikler ve yardım tek kutudan aranır. Tamamen cihazda çalışır.
library;

/// Sonucun türü (gruplama ve simge için).
enum SearchKind { feature, student, className, exam, question, note, booklet, help }

/// Aranabilir tek kayıt. [open] sonuç seçilince çalışır (arayüz katmanı verir).
class SearchEntry {
  final SearchKind kind;
  final String title;
  final String subtitle;

  /// Başlıkta görünmeyen ama aranan ek sözcükler (ör. "excel e-okul aktar").
  final String keywords;
  final Object? ref;
  final double boost;

  late final String _t = foldSearch(title);
  late final String _s = foldSearch(subtitle);
  late final String _k = foldSearch(keywords);

  SearchEntry(this.kind, this.title, {this.subtitle = '', this.keywords = '', this.ref, this.boost = 0});

  /// Sorgu sözcüklerinin hepsi bulunursa puan, yoksa null.
  /// Başlığın başında > sözcük başında > başlık içinde > alt yazı/anahtar sözcük.
  double? score(List<String> words) {
    if (words.isEmpty) return null;
    var total = 0.0;
    for (final w in words) {
      double best = 0;
      if (_t.startsWith(w)) {
        best = 10;
      } else if (_t.contains(' $w') || _t.contains('-$w') || _t.contains('/$w')) {
        best = 7;
      } else if (w.length >= 4 && _t.contains(w)) {
        // Sözcük ortası yalnız uzun sorgularda ("den" → "Neden" gelmesin).
        best = 5;
      } else if (_k.split(' ').any((k) => k.startsWith(w))) {
        best = 4;
      } else if (_s.split(' ').any((k) => k.startsWith(w))) {
        best = 3;
      } else if (w.length >= 4 && (_s.contains(w) || _k.contains(w))) {
        best = 1.5;
      }
      if (best == 0) return null;
      total += best;
    }
    // Tam eşleşme ve kısa başlıklar biraz önde.
    if (_t == words.join(' ')) total += 6;
    return total + boost - _t.length / 200;
  }
}

/// Aramada büyük/küçük harf ve aksan farkını kaldırır: "Öğrenci" = "ogrenci",
/// "İ/I/ı" = "i", "é" = "e". Latin dışı yazılar (Arapça, Çince…) olduğu gibi kalır.
String foldSearch(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    b.write(_fold[c] ?? c.toLowerCase());
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

const _fold = {
  'İ': 'i', 'I': 'i', 'ı': 'i', 'Ç': 'c', 'ç': 'c', 'Ğ': 'g', 'ğ': 'g', 'Ö': 'o', 'ö': 'o', 'Ş': 's', 'ş': 's',
  'Ü': 'u', 'ü': 'u', 'Â': 'a', 'â': 'a', 'Î': 'i', 'î': 'i', 'Û': 'u', 'û': 'u', 'Ə': 'e', 'ə': 'e',
  'á': 'a', 'à': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'Á': 'a', 'À': 'a', 'Ä': 'a', 'Ã': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'É': 'e', 'È': 'e', 'Ê': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'Í': 'i', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'Ó': 'o', 'Ô': 'o',
  'ú': 'u', 'ù': 'u', 'Ú': 'u', 'ñ': 'n', 'Ñ': 'n', 'ß': 'ss', 'ё': 'е', 'Ё': 'е',
};

/// Sorguyu sözcüklere ayırır (boşluk ve noktalama).
List<String> searchWords(String query) =>
    foldSearch(query).split(RegExp(r'[\s,.;:!?()"]+')).where((w) => w.isNotEmpty).toList();

/// En iyi sonuçlar, puana göre; her türden en çok [perKind] sonuç.
List<SearchEntry> runSearch(Iterable<SearchEntry> entries, String query, {int perKind = 8, int limit = 40}) {
  final words = searchWords(query);
  if (words.isEmpty) return const [];
  final scored = <(SearchEntry, double)>[];
  for (final e in entries) {
    final s = e.score(words);
    if (s != null) scored.add((e, s));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  final count = <SearchKind, int>{};
  final out = <SearchEntry>[];
  for (final (e, _) in scored) {
    final n = count[e.kind] ?? 0;
    if (n >= perKind) continue;
    count[e.kind] = n + 1;
    out.add(e);
    if (out.length >= limit) break;
  }
  return out;
}
