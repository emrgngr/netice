import 'package:image/image.dart' as img;

import 'form_layout.dart';

/// Formu bir görüntüye çizer. Örnek (deneme) form, ekranda önizleme ve
/// okuma motorunun testleri için kullanılır. Basılı form için bkz.
/// `form_pdf.dart`.
class FormRaster {
  final FormLayout layout;

  /// Milimetre başına piksel (150 dpi ≈ 5.9).
  final double pxPerMm;

  FormRaster(this.layout, {this.pxPerMm = 150 / 25.4});

  int get width => (FormLayout.pageWidth * pxPerMm).round();
  int get height => (FormLayout.pageHeight * pxPerMm).round();

  /// Boş form. [answers] verilirse ilgili daireler doldurulur
  /// (soru indeksi → şık listesi). [studentNumber] 6 haneli olmalıdır.
  img.Image render({
    Map<int, List<int>> answers = const {},
    String? studentNumber,
    int fillShade = 45,
  }) {
    final im = img.Image(width: width, height: height, numChannels: 3);
    img.fill(im, color: img.ColorRgb8(255, 255, 255));

    for (final o in FormLayout.markerOrigins) {
      img.fillRect(
        im,
        x1: _p(o.x),
        y1: _p(o.y),
        x2: _p(o.x + FormLayout.markerSize),
        y2: _p(o.y + FormLayout.markerSize),
        color: img.ColorRgb8(0, 0, 0),
      );
    }

    final outline = img.ColorRgb8(120, 120, 120);
    final r = _p(FormLayout.bubbleRadius);
    for (var q = 0; q < layout.questionCount; q++) {
      for (var c = 0; c < layout.choiceCount; c++) {
        final b = layout.answerBubble(q, c);
        img.drawCircle(im, x: _p(b.x), y: _p(b.y), radius: r, color: outline);
      }
    }
    for (var d = 0; d < FormLayout.studentDigits; d++) {
      for (var v = 0; v < 10; v++) {
        final b = layout.studentBubble(d, v);
        img.drawCircle(im, x: _p(b.x), y: _p(b.y), radius: r, color: outline);
      }
    }

    final ink = img.ColorRgb8(fillShade, fillShade, fillShade);
    void fillBubble(Pt b) => img.fillCircle(im,
        x: _p(b.x), y: _p(b.y), radius: (r * 0.9).round(), color: ink);

    answers.forEach((q, choices) {
      for (final c in choices) {
        fillBubble(layout.answerBubble(q, c));
      }
    });
    if (studentNumber != null) {
      for (var d = 0; d < studentNumber.length && d < FormLayout.studentDigits; d++) {
        fillBubble(layout.studentBubble(d, int.parse(studentNumber[d])));
      }
    }
    return im;
  }

  int _p(double mm) => (mm * pxPerMm).round();
}
