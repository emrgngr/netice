// Not sistemi: öğrencinin yüzdesinin hangi düzeye (Pekiyi, A, sehr gut, 6…)
// karşılık geldiği. Varsayılan uygulama dilinden gelir; öğretmen hazır bir
// ülke sistemini seçebilir ya da düzeyleri ve sınırları kendisi yazabilir.

/// Bir düzey: adı ve en düşük yüzdesi (tam puanın yüzdesi).
class GradeBand {
  final String label;
  final double minPct;
  const GradeBand(this.label, this.minPct);

  Map<String, dynamic> toJson() => {'label': label, 'min': minPct};
  factory GradeBand.fromJson(Map<String, dynamic> j) => GradeBand('${j['label'] ?? ''}', (j['min'] as num?)?.toDouble() ?? 0);
}

class GradeScale {
  /// Hazır sistemin kimliği ('de', 'ch'…) ya da özel için 'custom'.
  final String id;
  final String name;

  /// Yüksekten düşüğe; sonuncusunun sınırı 0.
  final List<GradeBand> bands;
  const GradeScale({required this.id, required this.name, required this.bands});

  static const minBands = 2;
  static const maxBands = 12;

  /// Sıralar, sonuncuyu 0'a çeker. Geçersizse hata metni döner.
  static String? validate(List<GradeBand> bands) {
    if (bands.length < minBands) return 'few';
    if (bands.any((b) => b.label.trim().isEmpty)) return 'label';
    for (var i = 0; i < bands.length - 1; i++) {
      final m = bands[i].minPct;
      if (m <= 0 || m > 100 || m <= bands[i + 1].minPct) return 'order';
    }
    return null;
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'bands': [for (final b in bands) b.toJson()]};

  static GradeScale? fromJson(Object? j) {
    if (j is! Map) return null;
    final bands = [for (final b in (j['bands'] as List?) ?? const []) if (b is Map) GradeBand.fromJson(b.cast<String, dynamic>())];
    if (bands.length < minBands) return null;
    bands.sort((a, b) => b.minPct.compareTo(a.minPct));
    bands[bands.length - 1] = GradeBand(bands.last.label, 0);
    return GradeScale(id: '${j['id'] ?? 'custom'}', name: '${j['name'] ?? ''}', bands: bands);
  }

  /// Hazır ülke sistemleri. Düzey adları o ülkenin dilinde yazılır (çevrilmez).
  static const presets = <GradeScale>[
    GradeScale(id: 'tr', name: 'Türkiye · 100 üzerinden (5 düzey)', bands: [
      GradeBand('Pekiyi (5)', 85),
      GradeBand('İyi (4)', 70),
      GradeBand('Orta (3)', 60),
      GradeBand('Geçer (2)', 50),
      GradeBand('Geçmez (1)', 0),
    ]),
    GradeScale(id: 'tr-uni', name: 'Türkiye · üniversite harf notu', bands: [
      GradeBand('AA', 90),
      GradeBand('BA', 85),
      GradeBand('BB', 80),
      GradeBand('CB', 75),
      GradeBand('CC', 70),
      GradeBand('DC', 65),
      GradeBand('DD', 60),
      GradeBand('FD', 50),
      GradeBand('FF', 0),
    ]),
    GradeScale(id: 'us', name: 'USA · A–F', bands: [
      GradeBand('A', 90),
      GradeBand('B', 80),
      GradeBand('C', 70),
      GradeBand('D', 60),
      GradeBand('F', 0),
    ]),
    GradeScale(id: 'uk', name: 'UK · GCSE 9–1', bands: [
      GradeBand('9', 90),
      GradeBand('8', 80),
      GradeBand('7', 70),
      GradeBand('6', 60),
      GradeBand('5', 50),
      GradeBand('4', 40),
      GradeBand('3', 30),
      GradeBand('2', 20),
      GradeBand('1', 10),
      GradeBand('U', 0),
    ]),
    GradeScale(id: 'de', name: 'Deutschland · 1–6', bands: [
      GradeBand('1 (sehr gut)', 92),
      GradeBand('2 (gut)', 81),
      GradeBand('3 (befriedigend)', 67),
      GradeBand('4 (ausreichend)', 50),
      GradeBand('5 (mangelhaft)', 30),
      GradeBand('6 (ungenügend)', 0),
    ]),
    GradeScale(id: 'at', name: 'Österreich · 1–5', bands: [
      GradeBand('1 (Sehr gut)', 90),
      GradeBand('2 (Gut)', 80),
      GradeBand('3 (Befriedigend)', 65),
      GradeBand('4 (Genügend)', 50),
      GradeBand('5 (Nicht genügend)', 0),
    ]),
    GradeScale(id: 'ch', name: 'Schweiz · 6–1', bands: [
      GradeBand('6', 95),
      GradeBand('5,5', 85),
      GradeBand('5', 75),
      GradeBand('4,5', 65),
      GradeBand('4', 55),
      GradeBand('3,5', 45),
      GradeBand('3', 35),
      GradeBand('2', 0),
    ]),
    GradeScale(id: 'fr', name: 'France · /20', bands: [
      GradeBand('Très bien (16–20)', 80),
      GradeBand('Bien (14–16)', 70),
      GradeBand('Assez bien (12–14)', 60),
      GradeBand('Passable (10–12)', 50),
      GradeBand('Insuffisant (< 10)', 0),
    ]),
    GradeScale(id: 'it', name: 'Italia · 1–10', bands: [
      GradeBand('10', 95),
      GradeBand('9', 85),
      GradeBand('8', 75),
      GradeBand('7', 65),
      GradeBand('6 (sufficiente)', 55),
      GradeBand('5', 45),
      GradeBand('4', 0),
    ]),
    GradeScale(id: 'es', name: 'España · 0–10', bands: [
      GradeBand('Sobresaliente (9–10)', 90),
      GradeBand('Notable (7–8)', 70),
      GradeBand('Bien (6)', 60),
      GradeBand('Suficiente (5)', 50),
      GradeBand('Insuficiente (0–4)', 0),
    ]),
    GradeScale(id: 'ru', name: 'Россия · 5–2', bands: [
      GradeBand('5 (отлично)', 85),
      GradeBand('4 (хорошо)', 70),
      GradeBand('3 (удовл.)', 50),
      GradeBand('2 (неудовл.)', 0),
    ]),
    GradeScale(id: 'az', name: 'Azərbaycan · 5–2', bands: [
      GradeBand('5 (əla)', 85),
      GradeBand('4 (yaxşı)', 70),
      GradeBand('3 (kafi)', 50),
      GradeBand('2 (qeyri-kafi)', 0),
    ]),
    GradeScale(id: 'ar', name: 'العربية · ممتاز – راسب', bands: [
      GradeBand('ممتاز', 90),
      GradeBand('جيد جدا', 80),
      GradeBand('جيد', 65),
      GradeBand('مقبول', 50),
      GradeBand('راسب', 0),
    ]),
    GradeScale(id: 'zh', name: '中国 · 优秀–不及格', bands: [
      GradeBand('优秀', 90),
      GradeBand('良好', 80),
      GradeBand('中等', 70),
      GradeBand('及格', 60),
      GradeBand('不及格', 0),
    ]),
    GradeScale(id: 'ja', name: '日本 · 5–1', bands: [
      GradeBand('5', 90),
      GradeBand('4', 75),
      GradeBand('3', 60),
      GradeBand('2', 40),
      GradeBand('1', 0),
    ]),
  ];
}
