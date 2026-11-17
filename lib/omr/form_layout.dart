import 'dart:math' as math;

/// Formdaki bir noktanın milimetre cinsinden konumu (A4: 210 × 297 mm).
class Pt {
  final double x;
  final double y;
  const Pt(this.x, this.y);
  @override
  String toString() => 'Pt(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}

/// Netice A4 optik formunun geometrisi.
///
/// Form üreticisi (PDF) ve okuma motoru aynı yerleşimi kullanır; böylece
/// basılan her daire, okuma sırasında tam olarak aranan yerdedir.
class FormLayout {
  static const pageWidth = 210.0;
  static const pageHeight = 297.0;

  /// Köşe işaretlerinin kenar uzunluğu (mm).
  static const markerSize = 10.0;

  /// Köşe işaretlerinin sol üst köşeleri.
  static const _markerOrigins = [
    Pt(10, 10), // sol üst
    Pt(190, 10), // sağ üst
    Pt(190, 277), // sağ alt
    Pt(10, 277), // sol alt
  ];

  /// Köşe işaretlerinin merkezleri: sol üst, sağ üst, sağ alt, sol alt.
  static List<Pt> get markerCenters => _markerOrigins
      .map((p) => Pt(p.x + markerSize / 2, p.y + markerSize / 2))
      .toList();

  static List<Pt> get markerOrigins => _markerOrigins;

  /// Daire yarıçapı (mm).
  static const bubbleRadius = 2.4;

  /// Aynı sorudaki şıklar arası yatay mesafe (mm).
  static const choicePitch = 6.4;

  /// Soru satırları arası dikey mesafe (mm).
  static const rowPitch = 6.2;

  /// Bir sütundaki en fazla soru sayısı.
  static const questionsPerColumn = 25;

  /// Öğrenci numarası hane sayısı.
  static const studentDigits = 6;

  final int questionCount;
  final int choiceCount;

  FormLayout({required this.questionCount, required this.choiceCount}) {
    if (questionCount < 1 || questionCount > 100) {
      throw ArgumentError('Soru sayısı 1–100 arasında olmalı');
    }
    if (choiceCount != 4 && choiceCount != 5) {
      throw ArgumentError('Şık sayısı 4 ya da 5 olmalı');
    }
  }

  // ---- Öğrenci numarası alanı ----

  /// Numara ızgarasının sol üst dairesinin merkezi.
  static const studentOrigin = Pt(140, 40);
  static const digitPitchX = 7.0;
  static const digitPitchY = 6.2;

  /// [digit] numaralı hanenin (0 = en soldaki) [value] değerinin dairesi.
  Pt studentBubble(int digit, int value) => Pt(
        studentOrigin.x + digit * digitPitchX,
        studentOrigin.y + value * digitPitchY,
      );

  // ---- Cevap alanı ----

  static const answersTop = 110.0;
  static const answersLeft = 24.0;

  int get columnCount => (questionCount / questionsPerColumn).ceil();

  /// Sütunlar arası mesafe, kullanılabilir genişliğe yayılır.
  double get columnPitch {
    final blockWidth = (choiceCount - 1) * choicePitch + 12;
    if (columnCount <= 1) return blockWidth;
    final usable = 186 - answersLeft - blockWidth;
    return math.max(blockWidth + 4, usable / (columnCount - 1));
  }

  /// Soru [index] (0'dan başlar), şık [choice] (0 = A) dairesinin merkezi.
  Pt answerBubble(int index, int choice) {
    final col = index ~/ questionsPerColumn;
    final row = index % questionsPerColumn;
    return Pt(
      answersLeft + col * columnPitch + 10 + choice * choicePitch,
      answersTop + row * rowPitch,
    );
  }

  /// Soru numarasının yazılacağı nokta (dairelerin solunda).
  Pt questionLabel(int index) {
    final b = answerBubble(index, 0);
    return Pt(b.x - 10, b.y);
  }
}
