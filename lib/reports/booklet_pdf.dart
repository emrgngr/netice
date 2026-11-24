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
Future<Uint8List> buildBookletPdf(
  BookletPlan plan, {
  required SchoolInfo school,
  required Uint8List? Function(String? id) image,
  BookletPdfParts parts = const BookletPdfParts(),
  List<BankNote> tips = const [],
}) async {
  final o = plan.options;
  final theme = await pdfTheme(school.fontFamily);
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
  final fs = o.fontSize.clamp(7.0, 16.0);
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
    pw.Widget one(int i) => pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: fs * 1.6, child: pw.Text('${_letter(i)})', style: style.copyWith(fontWeight: pw.FontWeight.bold))),
          pw.Expanded(child: pw.Text(texts[i], style: style)),
        ]);
    final longest = texts.fold(0, (a, t) => math.max(a, t.length));
    final perRow = !o.compactChoices
        ? 1
        : (longest * fs * 0.52 + fs * 2.2) * texts.length <= width
            ? texts.length
            : ((longest * fs * 0.52 + fs * 2.2) * 2 <= width ? 2 : 1);
    if (perRow == 1) {
      return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        for (var i = 0; i < texts.length; i++) pw.Padding(padding: const pw.EdgeInsets.only(top: 2), child: one(i)),
      ]);
    }
    final rows = <pw.Widget>[];
    for (var i = 0; i < texts.length; i += perRow) {
      rows.add(pw.Padding(
        padding: const pw.EdgeInsets.only(top: 2),
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
        final numW = fs * 2.0;
        final inner = width - numW;
        final pointsText = o.showPoints ? ' (${tr('{0} puan', [_fmt(p.points)])})' : '';
        return pw.Container(
          padding: pw.EdgeInsets.only(bottom: o.questionRule ? 6 : 2, top: 2),
          decoration: o.questionRule
              ? const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.5)))
              : null,
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.SizedBox(
              width: numW,
              child: pw.Text('${p.no}.', style: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold, color: _ink)),
            ),
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                if (q.text.trim().isNotEmpty || pointsText.isNotEmpty)
                  pw.RichText(
                    text: pw.TextSpan(children: [
                      pw.TextSpan(text: q.text.trim(), style: pw.TextStyle(fontSize: fs, lineSpacing: fs * 0.18)),
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
        (width, _) => pw.Container(
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

  pw.Widget header(BookletVariant v, {bool cover = false}) {
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
  List<List<List<_Block>>> paginate(List<_Block> blocks, double firstPageTop, double footerH, _Layout lay) {
    final colW = lay.columnWidth;
    final pages = <List<List<_Block>>>[];
    var page = <List<_Block>>[[]];
    var col = 0;
    double avail(int pageIndex) => lay.innerHeight - footerH - (pageIndex == 0 ? firstPageTop : 0);
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
      if (used > 0 && used + need > avail(pages.length)) {
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

  pw.Widget columnsOf(List<List<_Block>> cols, double maxH, _Layout lay) {
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
      children.add(pw.SizedBox(
        width: colW,
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          for (final b in blocks) pw.Padding(padding: const pw.EdgeInsets.only(bottom: 7), child: b.build(colW, maxH)),
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

  const footerH = 18.0;
  pw.Widget footer(String left, int pageNo, int pageCount, {bool hint = false}) => pw.Container(
        height: footerH,
        padding: const pw.EdgeInsets.only(top: 4),
        decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _line, width: 0.5))),
        child: pw.Row(children: [
          pw.Expanded(child: pw.Text(left, style: const pw.TextStyle(fontSize: 7, color: _muted))),
          if (hint) pw.Text(tr('Diğer sayfaya geçiniz.'), style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: _ink)),
          if (hint) pw.SizedBox(width: 10),
          if (o.pageNumbers) pw.Text('$pageNo / $pageCount', style: const pw.TextStyle(fontSize: 7, color: _muted)),
        ]),
      );

  /// Başlıklı ve sütunlu bir bölüm (kitapçık, çözümler, ek) ekler.
  void addSection({
    required List<_Block> blocks,
    required pw.Widget? top,
    required String footerLeft,
    bool hints = false,
    bool singleColumn = false,
  }) {
    final topH = top == null ? 0.0 : measure(top, layout.innerWidth);
    final lay = singleColumn ? _Layout(format, margin, 1, 0) : layout;
    final pages = paginate(blocks, topH, footerH, lay);
    for (var i = 0; i < pages.length; i++) {
      final cols = pages[i];
      final last = i == pages.length - 1;
      final maxH = layout.innerHeight - footerH - (i == 0 ? topH : 0);
      doc.addPage(pw.Page(
        pageTheme: pageTheme(),
        build: (c) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          if (i == 0 && top != null) top,
          pw.Expanded(child: columnsOf(cols, maxH, lay)),
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
