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

  /// Öğrenci numarası hane sayısı (eski formlar): 6.
  static const studentDigits = 6;

  /// Bu formdaki öğrenci numarası hane sayısı: 6 ya da 10.
  final int digits;

  final int questionCount;
  final int choiceCount;

  /// Kitapçık türü sayısı (1 = tek kitapçık). 2 ve üstünde formda kitapçık
  /// daireleri (A, B, C…) basılır ve okunur.
  final int booklets;

  /// Formda en fazla kaç kitapçık dairesi olabilir (A–H).
  static const maxBooklets = 8;

  FormLayout({required this.questionCount, required this.choiceCount, this.booklets = 1, this.digits = 6}) {
    if (digits != 6 && digits != 10) {
      throw ArgumentError('Öğrenci numarası 6 ya da 10 hane olmalı');
    }
    if (questionCount < 1 || questionCount > 100) {
      throw ArgumentError('Soru sayısı 1–100 arasında olmalı');
    }
    // 2–3 şık yalnız çocuk (ilkokul) sınavlarında; formun yerleşimi aynıdır.
    if (choiceCount < 2 || choiceCount > 5) {
      throw ArgumentError('Şık sayısı 2–5 arasında olmalı');
    }
    if (booklets < 1 || booklets > maxBooklets) {
      throw ArgumentError('Kitapçık sayısı 1–$maxBooklets arasında olmalı');
    }
  }

  bool get hasBooklets => booklets > 1;

  // ---- Öğrenci numarası alanı ----

  /// Numara ızgarasının sol üst dairesinin merkezi (6 haneli formda).
  /// 10 haneli formda ızgara sola uzar, sütunlar biraz sıklaşır; sağ kenar
  /// aynı kalır.
  static const studentOrigin = Pt(140, 40);
  static const digitPitchX = 7.0;
  static const digitPitchY = 6.2;

  bool get wideNumber => digits == 10;
  double get _digitPitch => wideNumber ? 6.0 : digitPitchX;
  double get _studentLeft => wideNumber ? 126.0 : studentOrigin.x;

  /// Bilgi alanlarının (ad, sınıf…) sağ kenarı: numara kutusunun solu.
  double get infoRight => wideNumber ? 116.0 : 128.0;

  /// [digit] numaralı hanenin (0 = en soldaki) [value] değerinin dairesi.
  Pt studentBubble(int digit, int value) => Pt(
        _studentLeft + digit * _digitPitch,
        studentOrigin.y + value * digitPitchY,
      );

  // ---- Kitapçık türü (A, B, C…) ----

  /// Kitapçık dairelerinin sütun sayısı: 4'e kadar tek satır, fazlası iki satır.
  int get bookletColumns => booklets <= 4 ? booklets : (booklets / 2).ceil();
  int get bookletRows => booklets <= 4 ? 1 : 2;

  /// Kitapçık dairesinin merkezi (0 = A, 1 = B, 2 = C…).
  ///
  /// İki kitapçıkta yerleşim eski formlarla aynıdır (basılmış A/B formları
  /// okunmaya devam eder). Daha fazlasında daireler sıkışık bir ızgaraya dizilir.
  Pt bookletBubble(int b) {
    // 10 haneli formda numara kutusu genişlediği için daireler sola kayar.
    final shift = wideNumber ? -16.0 : 0.0;
    if (booklets <= 2) return Pt(113.5 + shift + b * 9.0, 88.6);
    final cols = bookletColumns;
    final col = b % cols, row = b ~/ cols;
    final x = 116.5 + shift + (col - (cols - 1) / 2) * 6.6;
    final y = bookletRows == 1 ? 88.6 : 86.8 + row * 6.3;
    return Pt(x, y);
  }

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
