// Soru kitapçığı PDF'i: iki (ya da bir) sütunlu, resmi başlıklı, A–H
// kitapçıkları, cevap anahtarı, çözümlü kitapçık ve hap bilgi eki.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../bank/bank_models.dart';
import '../bank/booklet_builder.dart';
import '../core/models.dart';
import '../l10n/l10n.dart';
import '../omr/form_code.dart';
import '../omr/kid_layout.dart';
import 'brand_footer.dart';
import 'kid_pdf.dart';
import 'pdf_documents.dart' show pdfTheme;

const _ink = PdfColor.fromInt(0xFF0F1B3D);
const _emerald = PdfColor.fromInt(0xFF10B981);
const _muted = PdfColor.fromInt(0xFF6B7280);
const _soft = PdfColor.fromInt(0xFFF3F4F6);
const _line = PdfColor.fromInt(0xFFCBD0D8);

/// Kitapçık PDF'inde hangi parçalar olsun?
class BookletPdfParts {
  /// Basılacak kitapçık türleri (0 = A). Boş = hepsi.
  final Set<int> variants;
  final bool answerKey;
  final bool solutions;
  final bool tips;
  const BookletPdfParts({this.variants = const {}, this.answerKey = true, this.solutions = false, this.tips = false});
}

/// Bir sayfaya yerleştirilecek parça.
class _Block {
  final pw.Widget Function(double width, double maxHeight) build;

  /// Bölüm başlığı gibi bir sonraki parçadan ayrılmaması gerekenler.
  final bool keepWithNext;
  const _Block(this.build, {this.keepWithNext = false});
}

class _Layout {
  final PdfPageFormat format;
  final pw.EdgeInsets margin;
  final int columns;
  final double gap;
  _Layout(this.format, this.margin, this.columns, this.gap);

  double get innerWidth => format.width - margin.horizontal;
  double get innerHeight => format.height - margin.vertical;
  double get columnWidth => (innerWidth - gap * (columns - 1)) / columns;
}

String _letter(int i) => String.fromCharCode(65 + i);

String _fmt(double v) {
  final s = v.toStringAsFixed(2);
  return s.replaceAll(RegExp(r'\.?0+$'), '').replaceAll('.', L10n.decimal);
}

/// Kitapçığı (ve seçilen ekleri) tek PDF olarak üretir.
///
/// Çocuk şablonunda ilk sayfanın köşesine küçük cevap kutusu basılır;
/// [examCode] verilirse (sınav önceden oluşturulduysa) kutuya makine kodu da
/// eklenir.
Future<Uint8List> buildBookletPdf(
  BookletPlan plan, {
  required SchoolInfo school,
  required Uint8List? Function(String? id) image,
  BookletPdfParts parts = const BookletPdfParts(),
  List<BankNote> tips = const [],
  int? examCode,
}) async {
  final o = plan.options;
  final kids = o.kids;
  final baseTheme = await pdfTheme(school.fontFamily);
  final theme = kids ? await kidPdfTheme(school.fontFamily) : baseTheme;
  final doc = pw.Document(title: o.title.isEmpty ? tr('Soru kitapçığı') : o.title, author: 'Netice', theme: theme);
  final ctx = pw.Context(document: doc.document).inheritFromAll([theme]);
  final format = switch (o.paper) {
    PaperSize.a4 => PdfPageFormat.a4,
    PaperSize.a5 => PdfPageFormat.a5,
    PaperSize.letter => PdfPageFormat.letter,
  };
  final small = o.paper == PaperSize.a5;
  final margin = small ? const pw.EdgeInsets.fromLTRB(26, 26, 26, 24) : const pw.EdgeInsets.fromLTRB(34, 32, 34, 28);
  final cols = o.columns.clamp(1, 2);
  final layout = _Layout(format, margin, cols, small ? 14 : 20);
  final fs = kids ? o.fontSize.clamp(12.0, 18.0) : o.fontSize.clamp(7.0, 16.0);
  final kidBox = plan.kidBox
      ? KidLayout(questionCount: plan.testMaster.length, choiceCount: plan.choiceCount.clamp(2, 5))
      : null;
  final dir = L10n.rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
  final multi = plan.variants.length > 1;
  final date = o.date ?? DateTime.now();

  double measure(pw.Widget w, double width) {
    final box = pw.SizedBox(width: width, child: w);
    box.layout(ctx, pw.BoxConstraints(maxWidth: width), parentUsesSize: true);
    return box.box!.height;
  }

  // ———————————————————————————— Parçalar

  pw.Widget imageBox(String? id, double width, double maxH) {
    final bytes = image(id);
    if (bytes == null) return pw.SizedBox();
    final img = pw.MemoryImage(bytes);
    final iw = (img.width ?? 600).toDouble(), ih = (img.height ?? 400).toDouble();
    // Kesilmiş görseller ~150 dpi; küçük görseller büyütülmesin.
    var w = math.min(width, iw * 0.55);
    var h = w * ih / iw;
    if (h > maxH) {
      h = maxH;
      w = h * iw / ih;
    }
    if (kids) {
      return pw.Container(
        width: width,
        margin: const pw.EdgeInsets.only(top: 3, bottom: 5),
        padding: const pw.EdgeInsets.all(5),
        decoration: pw.BoxDecoration(
          color: kidSoftBlue,
          border: pw.Border.all(color: const PdfColor.fromInt(0xFFE3ECFB), width: 1.2),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        alignment: pw.Alignment.center,
        child: pw.Image(img, width: math.min(w, width - 10), height: h, fit: pw.BoxFit.contain),
      );
    }
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 3, bottom: 3),
      child: pw.Image(img, width: w, height: h, fit: pw.BoxFit.contain),
    );
  }

  pw.Widget choicesBox(PrintedQuestion p, double width) {
    final q = p.question;
    final texts = q.type == QuestionType.trueFalse ? [tr('Doğru'), tr('Yanlış')] : p.choices;
    if (texts.isEmpty || texts.every((t) => t.trim().isEmpty)) return pw.SizedBox();
    final style = pw.TextStyle(fontSize: fs);
    // Çocuk şablonunda harf yuvarlak içinde.
    final letterW = kids ? fs * 2.0 : fs * 1.6;
    pw.Widget letter(int i) => kids
        ? pw.Container(
            width: fs * 1.45,
            height: fs * 1.45,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(shape: pw.BoxShape.circle, border: pw.Border.all(color: kidLine, width: 1.4)),
            child: pw.Text(_letter(i), style: pw.TextStyle(fontSize: fs * 0.62, fontWeight: pw.FontWeight.bold, color: kidMuted)),
          )
        : pw.Text('${_letter(i)})', style: style.copyWith(fontWeight: pw.FontWeight.bold));
    pw.Widget one(int i) => pw.Row(crossAxisAlignment: kids ? pw.CrossAxisAlignment.center : pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: letterW, child: kids ? pw.Align(alignment: pw.Alignment.centerLeft, child: letter(i)) : letter(i)),
          pw.Expanded(child: pw.Text(texts[i], style: kids ? style.copyWith(color: kidInk) : style)),
        ]);
    final longest = texts.fold(0, (a, t) => math.max(a, t.length));
    final per = longest * fs * (kids ? 0.56 : 0.52) + letterW + fs * (kids ? 1.2 : 0.6);
    final perRow = !o.compactChoices ? 1 : (per * texts.length <= width ? texts.length : (per * 2 <= width ? 2 : 1));
    if (perRow == 1) {
      return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        for (var i = 0; i < texts.length; i++) pw.Padding(padding: pw.EdgeInsets.only(top: kids ? 4 : 2), child: one(i)),
      ]);
    }
    final rows = <pw.Widget>[];
    for (var i = 0; i < texts.length; i += perRow) {
      rows.add(pw.Padding(
        padding: pw.EdgeInsets.only(top: kids ? 4 : 2),
        child: pw.Row(children: [
          for (var k = i; k < i + perRow; k++) pw.Expanded(child: k < texts.length ? one(k) : pw.SizedBox()),
        ]),
      ));
    }
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: rows);
  }

  pw.Widget answerLines(int n) => pw.Column(children: [
        for (var i = 0; i < n; i++)
          pw.Container(
            height: fs * 1.9,
            decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.5, style: pw.BorderStyle.dotted))),
          ),
      ]);

  _Block questionBlock(PrintedQuestion p, {bool open = false, bool withAnswer = false}) => _Block((width, maxH) {
        final q = p.question;
        final numW = kids ? fs * 2.5 : fs * 2.0;
        final inner = width - numW;
        final number = kids
            ? pw.Container(
                width: fs * 1.85,
                height: fs * 1.85,
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(shape: pw.BoxShape.circle, color: kidBadgeColors[(p.no - 1) % kidBadgeColors.length]),
                child: pw.Text('${p.no}', style: pw.TextStyle(fontSize: fs * 0.9, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
              )
            : pw.Text('${p.no}.', style: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold, color: _ink));
        final pointsText = o.showPoints ? ' (${tr('{0} puan', [_fmt(p.points)])})' : '';
        return pw.Container(
          padding: pw.EdgeInsets.only(bottom: o.questionRule ? 6 : 2, top: 2),
          decoration: o.questionRule
              ? const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.5)))
              : null,
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.SizedBox(width: numW, child: pw.Align(alignment: pw.Alignment.topLeft, child: number)),
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                if (q.text.trim().isNotEmpty || pointsText.isNotEmpty)
                  pw.RichText(
                    text: pw.TextSpan(children: [
                      pw.TextSpan(text: q.text.trim(), style: pw.TextStyle(fontSize: fs, lineSpacing: fs * (kids ? 0.24 : 0.18), color: kids ? kidInk : null)),
                      if (pointsText.isNotEmpty)
                        pw.TextSpan(text: pointsText, style: pw.TextStyle(fontSize: fs - 1.5, color: _muted)),
                    ]),
                  ),
                if (q.imageId != null) imageBox(q.imageId, inner, math.max(80, maxH - 60)),
                if (!open) choicesBox(p, inner),
                if (open && !withAnswer) answerLines(q.type == QuestionType.fill ? 1 : q.answerLines.clamp(0, 30)),
                if (withAnswer) ...[
                  pw.SizedBox(height: 3),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFE7F8F0), borderRadius: pw.BorderRadius.circular(3)),
                    child: pw.Text(
                        tr('Cevap: {0}', [
                          q.type == QuestionType.multiple
                              ? (p.printedCorrect.toList()..sort()).map(_letter).join('/')
                              : q.answerLabel,
                        ]),
                        style: pw.TextStyle(fontSize: fs - 0.5, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF047857))),
                  ),
                  if (q.solution.trim().isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 3),
                      child: pw.Text(q.solution.trim(), style: pw.TextStyle(fontSize: fs - 1, color: _ink)),
                    ),
                  if (q.solutionImageId != null) imageBox(q.solutionImageId, inner, math.max(80, maxH - 60)),
                ],
                if (o.showTopic && q.topicLabel.isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 2),
                    child: pw.Text(q.topicLabel, style: pw.TextStyle(fontSize: fs - 3, color: _muted, fontStyle: pw.FontStyle.italic)),
                  ),
              ]),
            ),
          ]),
        );
      });

  _Block sectionBlock(String title, {String? note}) => _Block(
        (width, _) => kids
            ? pw.Container(
                width: width,
                margin: const pw.EdgeInsets.only(top: 2, bottom: 4),
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: pw.BoxDecoration(color: kidYellow, borderRadius: pw.BorderRadius.circular(10)),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text(title, style: pw.TextStyle(fontSize: fs * 0.95, fontWeight: pw.FontWeight.bold, color: kidInk)),
                  if (note != null && note.isNotEmpty) pw.Text(note, style: pw.TextStyle(fontSize: fs * 0.7, color: kidMuted)),
                ]),
              )
            : pw.Container(
          width: width,
          margin: const pw.EdgeInsets.only(top: 2, bottom: 4),
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: const pw.BoxDecoration(
            color: _soft,
            border: pw.Border(left: pw.BorderSide(color: _emerald, width: 2.5)),
          ),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(SchoolInfo.upper(title), style: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold, color: _ink)),
            if (note != null && note.isNotEmpty) pw.Text(note, style: pw.TextStyle(fontSize: fs - 2, color: _muted)),
          ]),
        ),
        keepWithNext: true,
      );

  // ———————————————————————————— Üst bilgi

  pw.Widget badge(int variant) => pw.Container(
        width: 54,
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: _ink, width: 1.2), borderRadius: pw.BorderRadius.circular(4)),
        child: pw.Column(children: [
          pw.Text(_letter(variant), style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold, color: _ink)),
          pw.Text(tr('KİTAPÇIK'), style: const pw.TextStyle(fontSize: 6.5, color: _ink, letterSpacing: 0.6)),
        ]),
      );

  pw.Widget studentBox() {
    pw.Widget cell(String label, {int flex = 1}) => pw.Expanded(
          flex: flex,
          child: pw.Container(
            height: 24,
            padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: _line, width: 0.7)),
            child: pw.Text('$label:', style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
          ),
        );
    return pw.Row(children: [
      cell(tr('Adı Soyadı'), flex: 4),
      cell(tr('Numarası'), flex: 2),
      cell(school.groupLabel.isNotEmpty ? school.groupLabel : tr('Sınıfı'), flex: 2),
      cell(tr('Puanı'), flex: 2),
    ]);
  }

  pw.Widget infoLine(BookletVariant v) {
    final bits = <String>[
      tr('Tarih: {0}', [L10n.date(date)]),
      if (o.durationMinutes > 0) tr('Süre: {0} dk', [o.durationMinutes]),
      tr('Soru sayısı: {0}', [plan.questionCount]),
      if (plan.openMaster.isNotEmpty) tr('Test: {0} · Klasik: {1}', [plan.testMaster.length, plan.openMaster.length]),
    ];
    return pw.Text(bits.join('   ·   '), style: const pw.TextStyle(fontSize: 8, color: _muted));
  }

  /// Çocuk şablonunun başlığı: renkli şerit, yıldız rozeti, "Adım Soyadım" kutuları.
  pw.Widget kidHeader(BookletVariant v, {bool cover = false}) {
    final official = o.officialHeader && school.official;
    final title = o.title.trim().isEmpty ? tr('Sınav') : o.title.trim();
    final sub = o.subtitle.trim();
    final n = plan.testMaster.length + plan.openMaster.length;
    pw.Widget box(pw.Widget child, {int flex = 1}) => pw.Expanded(
          flex: flex,
          child: pw.Container(
            height: 26,
            margin: const pw.EdgeInsets.symmetric(horizontal: 3),
            padding: const pw.EdgeInsets.symmetric(horizontal: 8),
            alignment: pw.Alignment.centerLeft,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: kidLine, width: 1.3, style: pw.BorderStyle.dashed),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: child,
          ),
        );
    const label = pw.TextStyle(fontSize: 10, color: kidMuted);
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      if (official) ...[
        for (final line in school.letterhead)
          pw.Text(line, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: kidInk)),
        pw.SizedBox(height: 4),
      ],
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: pw.BoxDecoration(
          gradient: const pw.LinearGradient(colors: [kidYellow, kidPink, kidBlue]),
          borderRadius: pw.BorderRadius.circular(16),
        ),
        child: pw.Row(children: [
          pw.Container(
            width: 40,
            height: 40,
            alignment: pw.Alignment.center,
            decoration: const pw.BoxDecoration(shape: pw.BoxShape.circle, color: PdfColors.white),
            child: kidStar(28),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(title, style: pw.TextStyle(fontSize: cover ? 24 : 19, fontWeight: pw.FontWeight.bold, color: kidInk)),
              if (sub.isNotEmpty) pw.Text(sub, style: const pw.TextStyle(fontSize: 10.5, color: kidMuted)),
            ]),
          ),
          pw.SizedBox(width: 8),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: pw.BoxDecoration(color: PdfColors.white, borderRadius: pw.BorderRadius.circular(10)),
            child: pw.Column(children: [
              pw.Text('$n', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: kidRose)),
              pw.Text(tr('soru'), style: const pw.TextStyle(fontSize: 8, color: kidRose)),
            ]),
          ),
        ]),
      ),
      if (o.studentBox) ...[
        pw.SizedBox(height: 8),
        pw.Row(children: [
          box(pw.Text(tr('Adım Soyadım:'), style: label), flex: 5),
          box(pw.Text(school.groupLabel.isNotEmpty ? '${school.groupLabel}:' : tr('Sınıfım:'), style: label), flex: 2),
          box(
            pw.Row(children: [
              pw.Text(tr('Doğru sayım:'), style: label),
              pw.SizedBox(width: 4),
              kidStar(11),
              pw.Text('  ___ / ${plan.testMaster.isNotEmpty ? plan.testMaster.length : n}', style: label),
            ]),
            flex: 3,
          ),
        ]),
      ],
      if (o.instructions.trim().isNotEmpty) ...[
        pw.SizedBox(height: 7),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: pw.BoxDecoration(color: kidSoftBlue, borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Text(o.instructions.trim(), style: pw.TextStyle(fontSize: cover ? 12 : 10, color: kidInk)),
        ),
      ],
      pw.SizedBox(height: 10),
    ]);
  }

  pw.Widget header(BookletVariant v, {bool cover = false}) {
    if (kids) return kidHeader(v, cover: cover);
    final official = o.officialHeader && school.official;
    final titleStyle = pw.TextStyle(fontSize: cover ? 18 : 13, fontWeight: pw.FontWeight.bold, color: _ink);
    final title = o.title.trim().isEmpty ? tr('Sınav') : o.title.trim();
    final left = pw.Column(
      crossAxisAlignment: official ? pw.CrossAxisAlignment.center : pw.CrossAxisAlignment.start,
      children: [
        if (official) ...[
          for (final line in school.letterhead)
            pw.Text(line, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 3),
          pw.Text(tr('{0} EĞİTİM-ÖĞRETİM YILI', [SchoolInfo.academicYear(date)]),
              textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8.5)),
          pw.SizedBox(height: 2),
        ],
        pw.Text(SchoolInfo.upper(title), style: titleStyle, textAlign: official ? pw.TextAlign.center : pw.TextAlign.left),
        if (o.subtitle.trim().isNotEmpty)
          pw.Text(o.subtitle.trim(), style: const pw.TextStyle(fontSize: 9, color: _muted)),
      ],
    );
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(child: left),
        if (multi) ...[pw.SizedBox(width: 10), badge(v.index)],
      ]),
      pw.SizedBox(height: 6),
      infoLine(v),
      if (o.studentBox) ...[pw.SizedBox(height: 5), studentBox()],
      if (o.instructions.trim().isNotEmpty) ...[
        pw.SizedBox(height: 6),
        pw.Container(
          padding: const pw.EdgeInsets.all(6),
          decoration: pw.BoxDecoration(color: _soft, borderRadius: pw.BorderRadius.circular(3)),
          child: pw.Text(o.instructions.trim(), style: pw.TextStyle(fontSize: cover ? 10 : 8, color: _ink)),
        ),
      ],
      pw.SizedBox(height: 6),
      pw.Container(height: 1.2, color: _ink),
      pw.SizedBox(height: 6),
    ]);
  }

  // ———————————————————————————— Sayfalama

  /// Parçaları sütunlara ve sayfalara yerleştirir. Her sayfa, parçaların
  /// sütun listesi olarak döner.
  /// [reserve]: ilk sayfada son sütunun (ya da [reserveAll] ise bütün
  /// sütunların) altında boş bırakılacak yükseklik (cevap kutusu için).
  List<List<List<_Block>>> paginate(List<_Block> blocks, double firstPageTop, double footerH, _Layout lay,
      {double reserve = 0, bool reserveAll = false}) {
    final colW = lay.columnWidth;
    final pages = <List<List<_Block>>>[];
    var page = <List<_Block>>[[]];
    var col = 0;
    bool reserved(int pageIndex, int c) => reserve > 0 && pageIndex == 0 && (reserveAll || c == lay.columns - 1);
    double avail(int pageIndex, [int c = 0]) =>
        lay.innerHeight - footerH - (pageIndex == 0 ? firstPageTop : 0) - (reserved(pageIndex, c) ? reserve : 0);
    var used = 0.0;
    const spacing = 7.0;
    final heights = <double>[];

    for (var i = 0; i < blocks.length; i++) {
      final maxH = avail(pages.length) - 4;
      heights.add(measure(blocks[i].build(colW, maxH), colW) + spacing);
    }
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      final h = heights[i];
      // Başlık, altındaki ilk soruyla aynı sütunda kalsın.
      final need = b.keepWithNext && i + 1 < blocks.length ? h + heights[i + 1] : h;
      // Boş sütun normalde ilk parçayı her durumda alır; cevap kutusuna
      // ayrılan sütunda sığmıyorsa sonraki sütuna/sayfaya geçilir.
      while ((used > 0 || reserved(pages.length, col)) && used + need > avail(pages.length, col)) {
        col++;
        used = 0;
        if (col >= lay.columns) {
          pages.add(page);
          page = [[]];
          col = 0;
        } else {
          page.add([]);
        }
      }
      page[col].add(b);
      used += h;
    }
    if (page.any((c) => c.isNotEmpty) || pages.isEmpty) pages.add(page);
    return pages;
  }

  pw.Widget columnsOf(List<List<_Block>> cols, double maxH, _Layout lay, {pw.Widget? lastBottom}) {
    final colW = lay.columnWidth;
    final children = <pw.Widget>[];
    for (var c = 0; c < lay.columns; c++) {
      if (c > 0) {
        children.add(pw.Container(
          width: lay.gap,
          alignment: pw.Alignment.center,
          child: o.columnRule ? pw.Container(width: 0.6, color: _line) : pw.SizedBox(),
        ));
      }
      final blocks = c < cols.length ? cols[c] : const <_Block>[];
      final bottom = c == lay.columns - 1 ? lastBottom : null;
      children.add(pw.SizedBox(
        width: colW,
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          for (final b in blocks) pw.Padding(padding: const pw.EdgeInsets.only(bottom: 7), child: b.build(colW, maxH)),
          if (bottom != null) ...[pw.Spacer(), pw.Align(alignment: pw.Alignment.bottomRight, child: bottom)],
        ]),
      ));
    }
    return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: children);
  }

  pw.PageTheme pageTheme() => pw.PageTheme(
        pageFormat: format,
        margin: margin,
        theme: theme,
        textDirection: dir,
        buildBackground: o.watermark.trim().isEmpty
            ? null
            : (c) => pw.FullPage(
                  ignoreMargins: true,
                  child: pw.Center(
                    child: pw.Transform.rotate(
                      angle: 0.6,
                      child: pw.Opacity(
                        opacity: 0.07,
                        child: pw.Text(o.watermark.trim(), style: pw.TextStyle(fontSize: 54, fontWeight: pw.FontWeight.bold)),
                      ),
                    ),
                  ),
                ),
      );

  const footerH = 18.0 + brandStripHeight;
  pw.Widget kidFooter(String left, int pageNo, int pageCount, {bool hint = false}) => pw.Container(
        height: footerH,
        padding: const pw.EdgeInsets.only(top: 3),
        child: pw.Column(children: [
          pw.SizedBox(height: 13, child: pw.Row(children: [
            if (o.pageNumbers && pageNo > 0)
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8),
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(color: kidInk, borderRadius: pw.BorderRadius.circular(8)),
                child: pw.Text('$pageNo', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
              ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: pw.Container(
                height: 4,
                decoration: pw.BoxDecoration(
                  gradient: const pw.LinearGradient(colors: [kidPink, kidBlue, kidYellow, kidPink]),
                  borderRadius: pw.BorderRadius.circular(2),
                ),
              ),
            ),
            if (hint) ...[
              pw.SizedBox(width: 8),
              pw.Text(tr('Sayfayı çevir'), style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: kidRose)),
            ],
          ])),
          pw.Spacer(),
          // Tanıtım şeridi raporlardaki yazı tipiyle (Andika'nın satır yüksekliği şeride sığmaz).
          pw.Theme(data: baseTheme, child: brandStrip(divider: false)),
        ]),
      );

  pw.Widget footer(String left, int pageNo, int pageCount, {bool hint = false}) => kids
      ? kidFooter(left, pageNo, pageCount, hint: hint)
      : pw.Container(
        height: footerH,
        padding: const pw.EdgeInsets.only(top: 4),
        decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _line, width: 0.5))),
        child: pw.Column(children: [
          pw.Row(children: [
            pw.Expanded(child: pw.Text(left, style: const pw.TextStyle(fontSize: 7, color: _muted))),
            if (hint) pw.Text(tr('Diğer sayfaya geçiniz.'), style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: _ink)),
            if (hint) pw.SizedBox(width: 10),
            if (o.pageNumbers) pw.Text('$pageNo / $pageCount', style: const pw.TextStyle(fontSize: 7, color: _muted)),
          ]),
          pw.Spacer(),
          brandStrip(divider: false),
        ]),
      );

  /// Başlıklı ve sütunlu bir bölüm (kitapçık, çözümler, ek) ekler.
  ///
  /// [box]: ilk sayfanın sağ altına konacak cevap kutusu (çocuk şablonu).
  void addSection({
    required List<_Block> blocks,
    required pw.Widget? top,
    required String footerLeft,
    bool hints = false,
    bool singleColumn = false,
    pw.Widget? box,
  }) {
    final topH = top == null ? 0.0 : measure(top, layout.innerWidth);
    final lay = singleColumn ? _Layout(format, margin, 1, 0) : layout;
    // Kutu sütuna sığmıyorsa (A5 iki sütun) sayfanın altına, bütün sütunların altına konur.
    final boxW = kidBox == null ? 0.0 : kidBox.width * PdfPageFormat.mm;
    final boxH = kidBox == null ? 0.0 : kidBox.height * PdfPageFormat.mm + 8;
    final boxBelow = box != null && boxW > lay.columnWidth;
    final pages = paginate(blocks, topH, footerH, lay, reserve: box == null ? 0 : boxH, reserveAll: boxBelow);
    for (var i = 0; i < pages.length; i++) {
      final cols = pages[i];
      final last = i == pages.length - 1;
      final maxH = layout.innerHeight - footerH - (i == 0 ? topH : 0);
      final withBox = i == 0 && box != null;
      doc.addPage(pw.Page(
        pageTheme: pageTheme(),
        build: (c) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          if (i == 0 && top != null) top,
          pw.Expanded(child: columnsOf(cols, maxH, lay, lastBottom: withBox && !boxBelow ? box : null)),
          if (withBox && boxBelow) pw.Padding(padding: const pw.EdgeInsets.only(top: 4), child: pw.Align(alignment: pw.Alignment.centerRight, child: box)),
          footer(footerLeft, i + 1, pages.length, hint: hints && o.nextPageHint && !last),
        ]),
      ));
    }
  }

  // ———————————————————————————— Kitapçıklar

  final wanted = parts.variants.isEmpty ? {for (final v in plan.variants) v.index} : parts.variants;
  final title = o.title.trim().isEmpty ? tr('Sınav') : o.title.trim();

  List<_Block> blocksFor(BookletVariant v, {bool answers = false}) {
    final out = <_Block>[];
    // Ders bölümleri yalnız sorular derse göre bitişikse.
    final runs = <String>[];
    for (final p in v.test) {
      if (runs.isEmpty || runs.last != p.question.subject) runs.add(p.question.subject);
    }
    final sections = o.sectionHeaders && runs.toSet().length > 1 && runs.length == runs.toSet().length;
    String? current;
    for (final p in v.test) {
      if (sections && p.question.subject != current) {
        current = p.question.subject;
        out.add(sectionBlock(current.isEmpty ? tr('Diğer') : current));
      }
      out.add(questionBlock(p, withAnswer: answers));
    }
    if (v.open.isNotEmpty) {
      out.add(sectionBlock(tr('Klasik sorular'),
          note: answers ? null : tr('Cevaplarınızı her sorunun altındaki boşluğa yazınız.')));
      for (final p in v.open) {
        out.add(questionBlock(p, open: true, withAnswer: answers));
      }
    }
    return out;
  }

  for (final v in plan.variants.where((v) => wanted.contains(v.index))) {
    final footerLeft = [title, if (multi) tr('{0} kitapçığı', [v.letter])].join(' · ');
    if (o.coverPage) {
      doc.addPage(pw.Page(
        pageTheme: pageTheme(),
        build: (c) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          header(v, cover: true),
          pw.Spacer(),
          pw.Center(
            child: pw.Text(tr('Sınav başlayana kadar kitapçığı açmayınız.'),
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _ink)),
          ),
          pw.Spacer(),
          footer(footerLeft, 0, 0),
        ]),
      ));
    }
    addSection(
      blocks: blocksFor(v),
      top: o.coverPage ? null : header(v),
      footerLeft: footerLeft,
      hints: true,
      box: kidBox == null ? null : kidAnswerBox(kidBox, code: examCode == null ? null : FormCode(examCode: examCode)),
    );
  }

  // ———————————————————————————— Cevap anahtarı

  if (parts.answerKey && plan.questionCount > 0) {
    final shown = plan.variants.where((v) => wanted.contains(v.index)).toList();
    final n = plan.testMaster.length;
    final cell = const pw.TextStyle(fontSize: 8);
    final head = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white);
    pw.Widget table(int from, int to) => pw.Table(
          border: pw.TableBorder.all(color: _line, width: 0.5),
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
          children: [
            pw.TableRow(decoration: const pw.BoxDecoration(color: _ink), children: [
              pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(tr('Soru'), style: head)),
              for (final v in shown) pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(v.letter, style: head, textAlign: pw.TextAlign.center)),
            ]),
            for (var i = from; i < to; i++)
              pw.TableRow(decoration: pw.BoxDecoration(color: i.isEven ? PdfColors.white : _soft), children: [
                pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text('${i + 1}', style: cell)),
                for (final v in shown)
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(3),
                    child: pw.Text(
                      v.test[i].question.type == QuestionType.trueFalse
                          ? (v.test[i].printedCorrect.contains(1) ? tr('B (Y)') : tr('A (D)'))
                          : (v.test[i].printedCorrect.toList()..sort()).map(_letter).join('/'),
                      style: cell.copyWith(fontWeight: pw.FontWeight.bold),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
              ]),
          ],
        );
    final perCol = small ? 30 : 40;
    final chunks = <pw.Widget>[];
    for (var s = 0; s < n; s += perCol) {
      chunks.add(pw.SizedBox(width: shown.length > 4 ? 230 : 160, child: table(s, math.min(n, s + perCol))));
    }
    doc.addPage(pw.MultiPage(
      pageTheme: pageTheme(),
      build: (c) => [
        pw.Text(tr('CEVAP ANAHTARI'), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _ink)),
        pw.Text(title, style: const pw.TextStyle(fontSize: 9, color: _muted)),
        pw.SizedBox(height: 10),
        if (n > 0) pw.Wrap(spacing: 12, runSpacing: 12, children: chunks),
        if (plan.openMaster.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          pw.Text(tr('Klasik sorular'), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _ink)),
          pw.SizedBox(height: 4),
          for (var i = 0; i < plan.openMaster.length; i++)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Text(
                  '${i + 1}. (${tr('{0} puan', [_fmt(plan.openPoints[i])])}) ${plan.openMaster[i].answerText.trim().isEmpty ? '—' : plan.openMaster[i].answerText.trim()}',
                  style: const pw.TextStyle(fontSize: 9)),
            ),
        ],
        pw.SizedBox(height: 14),
        pw.Text(
          tr('Toplam {0} puan · {1}', [
            _fmt(plan.testPoints.fold(0.0, (a, b) => a + b) + plan.openPoints.fold(0.0, (a, b) => a + b)),
            o.wrongsPerCorrect > 0 ? tr('{0} yanlış 1 doğruyu götürür', [o.wrongsPerCorrect]) : tr('yanlışlar doğruyu götürmez'),
          ]),
          style: const pw.TextStyle(fontSize: 8.5, color: _muted),
        ),
      ],
    ));
  }

  // ———————————————————————————— Ayrıntılı cevap anahtarı (öğretmen nüshası)
  //
  // Her kitapçık için: özet (soru sayısı, puan, zorluk ve şık dağılımı),
  // konulara göre dağılım ve soru soru cevap, zorluk, konu, diğer
  // kitapçıklardaki numara ve açıklama.

  if (parts.answerKey && plan.testMaster.isNotEmpty) {
    final shown = plan.variants.where((v) => wanted.contains(v.index)).toList();
    final official = o.officialHeader && school.official;
    const cell = pw.TextStyle(fontSize: 8);
    final bold = cell.copyWith(fontWeight: pw.FontWeight.bold);
    final head = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white);
    pw.Widget pad(pw.Widget w) => pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3), child: w);
    pw.Widget sectionTitle(String t) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 12, bottom: 5),
          child: pw.Text(SchoolInfo.upper(t), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
        );

    // Konu dağılımı: sorular konuya göre, konular tek ise alt konuya (kazanım) göre.
    final topics = plan.testMaster.map((q) => q.topicLabel).where((t) => t.isNotEmpty).toSet();
    final outcomes = plan.testMaster.map((q) => q.outcome.trim()).where((t) => t.isNotEmpty).toSet();
    final byOutcome = topics.length <= 1 && outcomes.length > 1;
    String groupOf(BankQuestion q) {
      final g = byOutcome ? q.outcome.trim() : q.topicLabel;
      return g.isEmpty ? tr('Diğer') : g;
    }

    String topicCell(BankQuestion q) {
      final t = q.topicLabel, k = q.outcome.trim();
      // Tek konulu sınavda konu her satırda tekrarlanmaz; alt konu yazılır.
      if (byOutcome && k.isNotEmpty) return k;
      return k.isNotEmpty && k != t ? (t.isEmpty ? k : '$t — $k') : (t.isEmpty ? '—' : t);
    }

    String ranges(List<int> nos) {
      final l = [...nos]..sort();
      final out = <String>[];
      var i = 0;
      while (i < l.length) {
        var j = i;
        while (j + 1 < l.length && l[j + 1] == l[j] + 1) {
          j++;
        }
        out.add(j > i ? '${l[i]}–${l[j]}' : '${l[i]}');
        i = j + 1;
      }
      return out.join(', ');
    }

    for (final v in shown) {
      final qs = v.test;
      final n = qs.length;
      final others = shown.where((w) => w.index != v.index).toList();
      int? noIn(BookletVariant w, BankQuestion q) => w.test.where((p) => p.question.id == q.id).firstOrNull?.no;
      String answerOf(PrintedQuestion p) => p.question.type == QuestionType.trueFalse
          ? (p.printedCorrect.contains(1) ? tr('B (Y)') : tr('A (D)'))
          : (p.printedCorrect.toList()..sort()).map(_letter).join('/');

      // Özet
      final pts = qs.map((p) => p.points).toSet();
      final total = qs.fold(0.0, (a, p) => a + p.points);
      final diff = {for (final d in Difficulty.values) d: qs.where((p) => p.question.difficulty == d).length};
      String pct(int k) => L10n.percent(n == 0 ? 0 : (k * 100 / n).round());
      final letters = <String, int>{};
      for (final p in qs) {
        if (p.question.type == QuestionType.multiple) {
          for (final c in p.printedCorrect) {
            letters[_letter(c)] = (letters[_letter(c)] ?? 0) + 1;
          }
        }
      }
      final letterLine = (letters.keys.toList()..sort()).map((k) => '$k: ${letters[k]}').join('  ·  ');
      final summary = <(String, String)>[
        (
          tr('Soru sayısı'),
          pts.length == 1 ? tr('{0} (her biri {1} puan)', [n, _fmt(pts.first)]) : tr('{0} · toplam {1} puan', [n, _fmt(total)])
        ),
        (tr('Zorluk dağılımı'), [for (final d in Difficulty.values) '${d.label} ${diff[d]} (${pct(diff[d]!)})'].join('  ·  ')),
        if (letterLine.isNotEmpty) (tr('Şık dağılımı'), letterLine),
      ];

      // Konulara göre dağılım (ilk geçtiği sıraya göre)
      final groups = <String, List<int>>{};
      for (final p in qs) {
        groups.putIfAbsent(groupOf(p.question), () => []).add(p.no);
      }

      final keyTitle = multi ? tr('CEVAP ANAHTARI · {0} KİTAPÇIĞI', [v.letter]) : tr('CEVAP ANAHTARI');
      doc.addPage(pw.MultiPage(
        pageTheme: pageTheme(),
        footer: (c) => pw.Column(children: [
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('${tr('Öğretmen nüshası')} · ${c.pageNumber}/${c.pagesCount}', style: const pw.TextStyle(fontSize: 7, color: _muted)),
          ),
          pw.SizedBox(height: 3),
          brandStrip(),
        ]),
        build: (c) => [
          if (official) ...[
            for (final line in school.letterhead)
              pw.Text(line, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
            pw.Text(tr('{0} EĞİTİM-ÖĞRETİM YILI', [SchoolInfo.academicYear(date)]),
                textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8.5)),
            pw.SizedBox(height: 4),
          ],
          pw.Text(SchoolInfo.upper(title), textAlign: official ? pw.TextAlign.center : pw.TextAlign.left,
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _ink)),
          pw.Text(keyTitle, textAlign: official ? pw.TextAlign.center : pw.TextAlign.left,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _ink)),
          pw.SizedBox(height: 6),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 3),
            decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _ink, width: 1), bottom: pw.BorderSide(color: _ink, width: 1))),
            child: pw.Text(tr('ÖĞRETMEN NÜSHASIDIR — ÖĞRENCİLERE DAĞITILMAZ'),
                textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
          ),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: _line, width: 0.5),
            columnWidths: const {0: pw.FixedColumnWidth(110), 1: pw.FlexColumnWidth()},
            children: [
              for (final (k, val) in summary)
                pw.TableRow(children: [
                  pw.Container(color: _soft, child: pad(pw.Text(k, style: bold))),
                  pad(pw.Text(val, style: cell)),
                ]),
            ],
          ),
          sectionTitle(tr('Soruların konulara göre dağılımı')),
          pw.Table(
            border: pw.TableBorder.all(color: _line, width: 0.5),
            columnWidths: const {0: pw.FixedColumnWidth(90), 1: pw.FlexColumnWidth(), 2: pw.FixedColumnWidth(36)},
            children: [
              pw.TableRow(decoration: const pw.BoxDecoration(color: _ink), children: [
                pad(pw.Text(tr('Sorular'), style: head)),
                pad(pw.Text(byOutcome ? tr('Alt konu / kazanım') : tr('Konu'), style: head)),
                pad(pw.Text(tr('Adet'), style: head, textAlign: pw.TextAlign.center)),
              ]),
              for (final e in groups.entries)
                pw.TableRow(children: [
                  pad(pw.Text(ranges(e.value), style: bold)),
                  pad(pw.Text(e.key, style: cell)),
                  pad(pw.Text('${e.value.length}', style: cell, textAlign: pw.TextAlign.center)),
                ]),
            ],
          ),
          sectionTitle(tr('Cevap anahtarı')),
          pw.Table(
            border: pw.TableBorder.all(color: _line, width: 0.5),
            columnWidths: {
              0: const pw.FixedColumnWidth(22),
              1: const pw.FixedColumnWidth(34),
              2: const pw.FixedColumnWidth(36),
              3: const pw.FlexColumnWidth(1.3),
              for (var k = 0; k < others.length; k++) 4 + k: const pw.FixedColumnWidth(30),
              4 + others.length: const pw.FlexColumnWidth(2.6),
            },
            children: [
              pw.TableRow(
                repeat: true,
                decoration: const pw.BoxDecoration(color: _ink),
                children: [
                  pad(pw.Text(tr('No'), style: head)),
                  pad(pw.Text(tr('Cevap'), style: head)),
                  pad(pw.Text(tr('Zorluk'), style: head)),
                  pad(pw.Text(byOutcome ? tr('Alt konu') : tr('Konu'), style: head)),
                  for (final w in others) pad(pw.Text(tr('{0} kit. no', [w.letter]), style: head)),
                  pad(pw.Text(tr('Dayanak / kısa açıklama'), style: head)),
                ],
              ),
              for (final p in qs)
                pw.TableRow(decoration: pw.BoxDecoration(color: p.no.isEven ? _soft : PdfColors.white), children: [
                  pad(pw.Text('${p.no}', style: bold)),
                  pad(pw.Text(answerOf(p), style: bold.copyWith(fontSize: 9), textAlign: pw.TextAlign.center)),
                  pad(pw.Text(p.question.difficulty.label, style: cell)),
                  pad(pw.Text(topicCell(p.question), style: cell)),
                  for (final w in others) pad(pw.Text('${noIn(w, p.question) ?? '—'}', style: cell, textAlign: pw.TextAlign.center)),
                  pad(pw.Text(p.question.solution.trim().isEmpty ? '—' : p.question.solution.trim(), style: cell)),
                ]),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Text('${tr('Cevap dizisi')}: ${[for (final p in qs) '${p.no}-${answerOf(p)}'].join('   ')}', style: bold),
          pw.SizedBox(height: 6),
          if (others.isNotEmpty)
            pw.Text(tr('"{0} kit. no" sütunu aynı sorunun o kitapçıktaki numarasını gösterir.', [others.first.letter]),
                style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
          if (pts.length == 1)
            pw.Text(tr('Puan = doğru sayısı × {0}', [_fmt(pts.first)]) + (o.wrongsPerCorrect > 0 ? ' · ${tr('{0} yanlış 1 doğruyu götürür', [o.wrongsPerCorrect])}' : ''),
                style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
          if (plan.openMaster.isNotEmpty) ...[
            sectionTitle(tr('Klasik sorular · cevap anahtarı')),
            pw.Table(
              border: pw.TableBorder.all(color: _line, width: 0.5),
              columnWidths: const {
                0: pw.FixedColumnWidth(22),
                1: pw.FixedColumnWidth(34),
                2: pw.FlexColumnWidth(1.2),
                3: pw.FlexColumnWidth(2.2),
                4: pw.FlexColumnWidth(1.8),
              },
              children: [
                pw.TableRow(repeat: true, decoration: const pw.BoxDecoration(color: _ink), children: [
                  pad(pw.Text(tr('No'), style: head)),
                  pad(pw.Text(tr('Puan'), style: head)),
                  pad(pw.Text(tr('Konu'), style: head)),
                  pad(pw.Text(tr('Beklenen cevap'), style: head)),
                  pad(pw.Text(tr('Dayanak / kısa açıklama'), style: head)),
                ]),
                for (var i = 0; i < plan.openMaster.length; i++)
                  pw.TableRow(decoration: pw.BoxDecoration(color: i.isOdd ? _soft : PdfColors.white), children: [
                    pad(pw.Text('${i + 1}', style: bold)),
                    pad(pw.Text(_fmt(plan.openPoints[i]), style: cell, textAlign: pw.TextAlign.center)),
                    pad(pw.Text(topicCell(plan.openMaster[i]), style: cell)),
                    pad(pw.Text(plan.openMaster[i].answerText.trim().isEmpty ? '—' : plan.openMaster[i].answerText.trim(), style: cell)),
                    pad(pw.Text(plan.openMaster[i].solution.trim().isEmpty ? '—' : plan.openMaster[i].solution.trim(), style: cell)),
                  ]),
              ],
            ),
          ],
        ],
      ));
    }
  }

  // ———————————————————————————— Çözümlü kitapçık

  if (parts.solutions && plan.variants.isNotEmpty) {
    final v = plan.variants.first;
    addSection(
      blocks: blocksFor(v, answers: true),
      top: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Text(tr('ÇÖZÜMLÜ CEVAP ANAHTARI'), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _ink)),
        pw.Text(multi ? tr('{0} · {1} kitapçığı sırasıyla', [title, v.letter]) : title, style: const pw.TextStyle(fontSize: 9, color: _muted)),
        pw.SizedBox(height: 8),
        pw.Container(height: 1.2, color: _ink),
        pw.SizedBox(height: 6),
      ]),
      footerLeft: tr('{0} · çözümler', [title]),
    );
  }

  // ———————————————————————————— Hap bilgi eki

  if (parts.tips && tips.isNotEmpty) {
    final blocks = <_Block>[
      for (final n in tips)
        _Block((width, maxH) => pw.Container(
              width: width,
              padding: const pw.EdgeInsets.all(7),
              decoration: pw.BoxDecoration(
                color: n.kind == NoteKind.tip ? const PdfColor.fromInt(0xFFFFF8E6) : _soft,
                borderRadius: pw.BorderRadius.circular(4),
                border: pw.Border.all(color: n.kind == NoteKind.tip ? const PdfColor.fromInt(0xFFF2B33D) : _line, width: 0.7),
              ),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(n.displayTitle, style: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold, color: _ink)),
                if (n.topicLabel.isNotEmpty && n.topicLabel != n.displayTitle)
                  pw.Text(n.topicLabel, style: pw.TextStyle(fontSize: fs - 2.5, color: _muted)),
                if (n.body.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  pw.Text(n.body.trim(), style: pw.TextStyle(fontSize: fs - 1)),
                ],
                for (final id in n.imageIds.take(3)) imageBox(id, width - 14, math.max(80, maxH * 0.6)),
              ]),
            )),
    ];
    addSection(
      blocks: blocks,
      top: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Text(tr('KONU ÖZETLERİ VE HAP BİLGİLER'), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _ink)),
        pw.Text(title, style: const pw.TextStyle(fontSize: 9, color: _muted)),
        pw.SizedBox(height: 8),
      ]),
      footerLeft: tr('{0} · hap bilgiler', [title]),
    );
  }

  if (doc.document.pdfPageList.pages.isEmpty) {
    doc.addPage(pw.Page(pageTheme: pageTheme(), build: (c) => pw.Center(child: pw.Text(tr('Kitapçıkta soru yok.')))));
  }
  return doc.save();
}
