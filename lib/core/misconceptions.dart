// Kavram yanılgısı teşhisi: öğretmenin yanlış şıklara yazdığı yanılgılardan
// sınıfta ve öğrencide hangi yanılgının görüldüğünü çıkarır.

import 'models.dart';

/// Sınavdaki kavram yanılgıları: hangi yanılgıyı kaç öğrenci taşıyor.
class MisconceptionFinding {
  final String text;

  /// Bu yanılgıyı yakalayan (soru no, şık) çiftleri.
  final List<(int, int)> sources;

  /// Yanılgıya düşen öğrencilerin kimlikleri (kâğıdın studentId'si).
  final Set<String> students;
  const MisconceptionFinding(this.text, this.sources, this.students);
}

class Misconceptions {
  /// Sınav sonuçlarından yanılgılar, en çok öğrencide görülenden aza.
  static List<MisconceptionFinding> of(Exam exam, List<Sheet> sheets) {
    final map = <String, (List<(int, int)>, Set<String>)>{};
    for (var i = 0; i < exam.questions.length; i++) {
      final q = exam.questions[i];
      if (q.cancelled) continue;
      for (final e in q.misconceptions.entries) {
        final text = q.misconceptionOf(e.key);
        if (text.isEmpty) continue;
        final key = text.toLowerCase();
        final slot = map.putIfAbsent(key, () => ([], {}));
        slot.$1.add((q.no, e.key));
        for (final s in sheets) {
          if (i >= s.answers.length) continue;
          final a = s.answers[i];
          if (a.marked.length == 1 && a.marked.first == e.key) slot.$2.add(s.studentId ?? s.readNumber ?? '?');
        }
      }
    }
    // Yazılış biçimi ilk görüldüğü gibi.
    final texts = <String, String>{};
    for (final q in exam.questions) {
      for (final e in q.misconceptions.entries) {
        final t = q.misconceptionOf(e.key);
        if (t.isNotEmpty) texts.putIfAbsent(t.toLowerCase(), () => t);
      }
    }
    final out = [for (final e in map.entries) MisconceptionFinding(texts[e.key] ?? e.key, e.value.$1, e.value.$2)];
    out.sort((a, b) => b.students.length.compareTo(a.students.length));
    return out;
  }

  /// Bir öğrencinin bu sınavda düştüğü yanılgılar.
  static List<String> ofSheet(Exam exam, Sheet sheet) {
    final out = <String>[];
    for (var i = 0; i < exam.questions.length && i < sheet.answers.length; i++) {
      final q = exam.questions[i];
      if (q.cancelled) continue;
      final a = sheet.answers[i];
      if (a.marked.length != 1) continue;
      final t = q.misconceptionOf(a.marked.first);
      if (t.isNotEmpty && !out.any((o) => o.toLowerCase() == t.toLowerCase())) out.add(t);
    }
    return out;
  }

  static bool any(Exam exam) => exam.questions.any((q) => q.misconceptions.values.any((m) => m.trim().isNotEmpty));
}
