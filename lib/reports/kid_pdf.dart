// Çocuk (ilkokul) şablonunun ortak parçaları: okunaklı yazı tipi, renkler,
// köşedeki küçük cevap kutusu ve isimli cevap kartları.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/models.dart';
import '../l10n/l10n.dart';
import '../omr/form_code.dart';
import '../omr/kid_layout.dart';
import 'brand_footer.dart';
import 'pdf_documents.dart' show pdfTheme;

const kidInk = PdfColor.fromInt(0xFF2B3A67);
const kidMuted = PdfColor.fromInt(0xFF5B6A8F);
const kidLine = PdfColor.fromInt(0xFFC9D3EA);

/// Etkin renk teması: PDF oluşturan işlevler başta [useKidTheme] ile seçer.
KidTheme _kidTheme = KidTheme.rainbow;
KidTheme get activeKidTheme => _kidTheme;
void useKidTheme(KidTheme t) => _kidTheme = t;

PdfColor get kidSoftBlue => PdfColor.fromInt(_kidTheme.soft);
PdfColor get kidYellow => PdfColor.fromInt(_kidTheme.gradient[0]);
PdfColor get kidPink => PdfColor.fromInt(_kidTheme.gradient[1]);
PdfColor get kidBlue => PdfColor.fromInt(_kidTheme.gradient[2]);
PdfColor get kidRose => PdfColor.fromInt(_kidTheme.accent);

/// Soru numarası rozetlerinin renkleri (sırayla).
List<PdfColor> get kidBadgeColors => [for (final c in _kidTheme.badges) PdfColor.fromInt(c)];

const _mm = PdfPageFormat.mm;

/// Çocuk şablonunun yazı tipi: Andika (okumayı yeni öğrenenler için; a, g,
/// I, l harfleri karışmaz). Andika'da olmayan harfler (Arapça, Çince…) için
/// raporların yazı tipleri yedek olarak kullanılır. Arapçada ana yazı tipi
/// Arap yazı tipi kalmalıdır (harfler birleşsin).
Future<pw.ThemeData> kidPdfTheme([String family = 'netice']) async {
  final base = await pdfTheme(family);
  if (L10n.rtl) return base;
  try {
    final regular = pw.Font.ttf(await rootBundle.load('assets/pdf_fonts/Andika-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/pdf_fonts/Andika-Bold.ttf'));
    final style = base.defaultTextStyle;
    return pw.ThemeData.withFont(
      base: regular,
      bold: bold,
      italic: regular,
      boldItalic: bold,
      fontFallback: [if (style.font != null) style.font!, ...style.fontFallback],
    );
  } catch (_) {
    return base;
  }
}

/// Gülen yıldız (başlık rozeti). [filled] false ise yüzsüz, soluk yıldız
/// (karnelerde kazanılmamış yıldız).
pw.Widget kidStar(double size, {bool filled = true}) => pw.CustomPaint(
  size: PdfPoint(size, size),
  painter: (canvas, s) {
    final w = s.x, h = s.y;
    // Beş köşeli yıldız (y yukarı doğru artar).
    final pts = <PdfPoint>[];
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? w * 0.48 : w * 0.22;
      final a = 3.14159265 / 2 + i * 3.14159265 / 5;
      pts.add(PdfPoint(w / 2 + r * math.cos(a), h * 0.47 + r * math.sin(a)));
    }
    canvas
      ..setFillColor(filled ? const PdfColor.fromInt(0xFFF6B632) : const PdfColor.fromInt(0xFFEEF1F7))
      ..setStrokeColor(filled ? const PdfColor.fromInt(0xFFE39A10) : kidLine)
      ..setLineWidth(w * 0.03)
      ..setLineJoin(PdfLineJoin.round)
      ..moveTo(pts.first.x, pts.first.y);
    for (final p in pts.skip(1)) {
      canvas.lineTo(p.x, p.y);
    }
    canvas
      ..closePath()
      ..fillAndStrokePath();
    if (!filled) return;
    canvas
      ..setFillColor(kidInk)
      ..drawEllipse(w * 0.40, h * 0.50, w * 0.035, w * 0.035)
      ..drawEllipse(w * 0.60, h * 0.50, w * 0.035, w * 0.035)
      ..fillPath()
      ..setStrokeColor(kidInk)
      ..setLineWidth(w * 0.035)
      ..setLineCap(PdfLineCap.round)
      ..moveTo(w * 0.41, h * 0.40)
      ..curveTo(w * 0.46, h * 0.34, w * 0.54, h * 0.34, w * 0.59, h * 0.40)
      ..strokePath();
  },
);

/// Köşedeki cevap kutusu. [name] verilirse "Adım" satırına basılır; [code]
/// verilirse makine kodu (sınav ve öğrenci) basılır.
pw.Widget kidAnswerBox(KidLayout l, {String? name, FormCode? code, double scale = 1}) {
  // Büyük kart: kutu bütünüyle büyütülür; okuyucu köşe karelerinden
  // ölçeklendiği için okuma değişmez.
  if (scale != 1) {
    return pw.SizedBox(
      width: l.width * _mm * scale,
      height: l.height * _mm * scale,
      child: pw.FittedBox(
        child: kidAnswerBox(l, name: name, code: code),
      ),
    );
  }
  final w = l.width * _mm, h = l.height * _mm;
  pw.Widget at(double xMm, double yMm, pw.Widget child) => pw.Positioned(left: xMm * _mm, top: yMm * _mm, child: child);
  const ms = KidLayout.markerSize;
  const r = KidLayout.bubbleRadius;
  final bits = code?.encode();
  return pw.SizedBox(
    width: w,
    height: h,
    child: pw.Stack(
      children: [
        pw.Positioned(
          left: ms / 2 * _mm,
          top: ms / 2 * _mm,
          child: pw.Container(
            width: (l.width - ms) * _mm,
            height: (l.height - ms) * _mm,
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              border: pw.Border.all(color: kidLine, width: 1.2),
              borderRadius: pw.BorderRadius.circular(3 * _mm),
            ),
          ),
        ),
        for (final o in l.markerOrigins) at(o.x, o.y, pw.Container(width: ms * _mm, height: ms * _mm, color: PdfColors.black)),
        at(
          ms + 2.5,
          KidLayout.titleTop,
          pw.SizedBox(
            width: (l.width - 2 * ms - 5) * _mm,
            height: 5 * _mm,
            child: pw.Center(
              child: pw.Text(
                tr('Cevaplarımı boyuyorum'),
                maxLines: 1,
                style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: kidMuted),
              ),
            ),
          ),
        ),
        at(
          5,
          KidLayout.nameTop,
          pw.Container(
            width: (l.width - 10) * _mm,
            height: 5.6 * _mm,
            padding: const pw.EdgeInsets.only(left: 3, right: 3, bottom: 1),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: kidLine, width: 0.8)),
            ),
            alignment: pw.Alignment.bottomLeft,
            child: pw.RichText(
              maxLines: 1,
              text: pw.TextSpan(
                children: [
                  pw.TextSpan(
                    text: tr('Adım:').padRight(tr('Adım:').length + 1),
                    style: const pw.TextStyle(fontSize: 7.5, color: kidMuted),
                  ),
                  if (name != null)
                    pw.TextSpan(
                      text: name,
                      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: kidInk),
                    ),
                ],
              ),
            ),
          ),
        ),
        for (var q = 0; q < l.questionCount; q++) ...[
          at(
            l.questionLabel(q).x - 6,
            l.questionLabel(q).y - 1.9,
            pw.SizedBox(
              width: 6 * _mm,
              child: pw.Text(
                '${q + 1}',
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: kidMuted),
              ),
            ),
          ),
          for (var c = 0; c < l.choiceCount; c++)
            at(
              l.answerBubble(q, c).x - r,
              l.answerBubble(q, c).y - r,
              pw.Container(
                width: 2 * r * _mm,
                height: 2 * r * _mm,
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(
                  shape: pw.BoxShape.circle,
                  border: pw.Border.all(color: const PdfColor.fromInt(0xFF7D89A8), width: 0.7),
                ),
                child: pw.Text(String.fromCharCode(65 + c), style: const pw.TextStyle(fontSize: 5.5, color: PdfColor.fromInt(0xFFAAB4CC))),
              ),
            ),
        ],
        if (bits != null)
          for (var i = 0; i < bits.length; i++)
            if (bits[i])
              at(
                l.codeCell(i).x - KidLayout.codeCellSize / 2,
                l.codeCell(i).y - KidLayout.codeCellSize / 2,
                pw.Container(width: KidLayout.codeCellSize * _mm, height: KidLayout.codeCellSize * _mm, color: PdfColors.black),
              ),
      ],
    ),
  );
}

/// İsimli çocuk cevap kartları: A4'e 4 kart (2 × 2), kesme çizgili. Her
/// kartın kutusunda öğrencinin adı ve makine kodu (sınav + öğrenci numarası)
/// basılıdır; okutulunca kâğıt öğrenciye kendiliğinden bağlanır.
/// [students] boşsa [blankCopies] adet isimsiz kart basılır.
Future<Uint8List> buildKidCardsPdf(
  List<(Exam, List<Student>)> groups, {
  int blankCopies = 4,
  SchoolInfo school = const SchoolInfo(),
  int perPage = 4,
}) async {
  final big = perPage == 2;
  final baseTheme = await pdfTheme(school.fontFamily);
  final theme = await kidPdfTheme(school.fontFamily);
  final first = groups.first.$1;
  useKidTheme(first.kidTheme);
  final doc = pw.Document(theme: theme, title: tr('{0} · cevap kartları', [first.name]), author: 'Netice');
  final cards = <(Exam, Student?)>[];
  for (final (exam, students) in groups) {
    if (students.isEmpty) {
      cards.addAll(List.filled(blankCopies < 1 ? 1 : blankCopies, (exam, null)));
    } else {
      cards.addAll([for (final s in students) (exam, s)]);
    }
  }
  pw.Widget card(Exam exam, Student? s) {
    final l = kidLayoutFor(exam)!;
    // Büyük kartta kutu, yarım A4'ün başlık dışında kalan alanına sığacak kadar büyür.
    final scale = big ? math.min(math.min(170 / l.width, 100 / l.height), 1.9) : 1.0;
    final code = FormCode(examCode: FormCode.examCodeOf(exam.id), studentNumber: s == null ? null : int.tryParse(s.number));
    return pw.Padding(
      padding: big ? const pw.EdgeInsets.fromLTRB(40, 18, 40, 14) : const pw.EdgeInsets.all(14),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: pw.BoxDecoration(
              gradient: pw.LinearGradient(colors: [kidYellow, kidPink, kidBlue]),
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Row(
              children: [
                kidStar(big ? 26 : 18),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        exam.name,
                        maxLines: 1,
                        style: pw.TextStyle(fontSize: big ? 15 : 11, fontWeight: pw.FontWeight.bold, color: kidInk),
                      ),
                      if (exam.className.isNotEmpty) pw.Text(exam.className, style: const pw.TextStyle(fontSize: 8, color: kidMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            tr('Doğru cevabın dairesini tamamen boya.'),
            style: pw.TextStyle(fontSize: big ? 12 : 8.5, color: kidMuted),
          ),
          pw.SizedBox(height: 6),
          kidAnswerBox(l, name: s?.fullName, code: code, scale: scale),
        ],
      ),
    );
  }

  for (var i = 0; i < cards.length; i += perPage) {
    final chunk = cards.sublist(i, (i + perPage).clamp(0, cards.length));
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        textDirection: L10n.rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        build: (c) => pw.Stack(
          children: [
            pw.Column(
              children: [
                for (var row = 0; row < 2; row++)
                  pw.Expanded(
                    child: big
                        ? (row < chunk.length ? card(chunk[row].$1, chunk[row].$2) : pw.SizedBox())
                        : pw.Row(
                            children: [
                              for (var col = 0; col < 2; col++)
                                pw.Expanded(
                                  child: row * 2 + col < chunk.length
                                      ? card(chunk[row * 2 + col].$1, chunk[row * 2 + col].$2)
                                      : pw.SizedBox(),
                                ),
                            ],
                          ),
                  ),
              ],
            ),
            // Kesme çizgileri
            if (!big)
              pw.Positioned(
                left: PdfPageFormat.a4.width / 2,
                top: 0,
                bottom: 0,
                child: pw.Container(
                  width: 0,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      left: pw.BorderSide(color: kidLine, width: 0.6, style: pw.BorderStyle.dashed),
                    ),
                  ),
                ),
              ),
            pw.Positioned(
              top: PdfPageFormat.a4.height / 2,
              left: 0,
              right: 0,
              child: pw.Container(
                height: 0,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    top: pw.BorderSide(color: kidLine, width: 0.6, style: pw.BorderStyle.dashed),
                  ),
                ),
              ),
            ),
            pw.Positioned(
              left: 30,
              right: 30,
              bottom: 6,
              child: pw.Theme(data: baseTheme, child: brandStrip(divider: false)),
            ),
          ],
        ),
      ),
    );
  }
  return doc.save();
}
