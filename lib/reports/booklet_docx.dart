// Kitapçığı düzenlenebilir Word (.docx) belgesi olarak üretir. Öğretmen
// soruları Word'de düzeltip kendi biçimiyle basabilsin diye sade tutulur:
// başlık, öğrenci bilgi tablosu, yönerge, numaralı sorular, görseller,
// şıklar, klasik soru cevap satırları ve sonda cevap anahtarı.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;

import '../bank/bank_models.dart';
import '../bank/booklet_builder.dart';
import '../core/models.dart';
import '../l10n/l10n.dart';

String _x(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

String _letter(int i) => String.fromCharCode(65 + i);

String _fmt(double v) {
  final s = v.toStringAsFixed(2);
  return s.replaceAll(RegExp(r'\.?0+$'), '').replaceAll('.', L10n.decimal);
}

class _Doc {
  final body = StringBuffer();
  final media = <(String, Uint8List)>[];
  final double fs;
  final bool rtl;
  _Doc(this.fs, this.rtl);

  int get _sz => (fs * 2).round();

  String run(String t, {bool bold = false, bool italic = false, double? size, String? color}) {
    if (t.isEmpty) return '';
    final pr = StringBuffer('<w:rPr>');
    if (rtl) pr.write('<w:rtl/>');
    if (bold) pr.write('<w:b/><w:bCs/>');
    if (italic) pr.write('<w:i/>');
    if (color != null) pr.write('<w:color w:val="$color"/>');
    final sz = size == null ? _sz : (size * 2).round();
    pr.write('<w:sz w:val="$sz"/><w:szCs w:val="$sz"/></w:rPr>');
    // Satır sonları ayrı <w:br/> olur.
    final parts = t.split('\n');
    final b = StringBuffer();
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) b.write('<w:r>$pr<w:br/></w:r>');
      b.write('<w:r>$pr<w:t xml:space="preserve">${_x(parts[i])}</w:t></w:r>');
    }
    return b.toString();
  }

  void para(String runs,
      {String align = '', int before = 0, int after = 80, int indent = 0, int hanging = 0, bool keepNext = false, bool pageBreakBefore = false, String? shade, int? dotLineTo}) {
    final pr = StringBuffer('<w:pPr>');
    if (keepNext) pr.write('<w:keepNext/>');
    if (pageBreakBefore) pr.write('<w:pageBreakBefore/>');
    if (dotLineTo != null) pr.write('<w:tabs><w:tab w:val="${rtl ? 'left' : 'right'}" w:leader="dot" w:pos="$dotLineTo"/></w:tabs>');
    if (shade != null) pr.write('<w:shd w:val="clear" w:color="auto" w:fill="$shade"/>');
    pr.write('<w:spacing w:before="$before" w:after="$after"/>');
    if (indent > 0 || hanging > 0) pr.write('<w:ind w:left="${indent + hanging}" w:hanging="$hanging"/>');
    if (rtl) pr.write('<w:bidi/>');
    if (align.isNotEmpty) pr.write('<w:jc w:val="$align"/>');
    pr.write('</w:pPr>');
    body.write('<w:p>$pr${dotLineTo != null ? '<w:r><w:rPr><w:color w:val="9AA0AE"/></w:rPr><w:tab/></w:r>' : ''}$runs</w:p>');
  }

  void pageBreak() => body.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');

  /// Görseli ekler; [maxWidthTwips] sütun genişliği.
  void image(Uint8List? bytes, int maxWidthTwips, {int indent = 0}) {
    if (bytes == null || bytes.isEmpty) return;
    final info = img.findDecoderForData(bytes)?.startDecode(bytes);
    final png = bytes.length > 4 && bytes[0] == 0x89 && bytes[1] == 0x50;
    var w = (info?.width ?? 600).toDouble(), h = (info?.height ?? 400).toDouble();
    // Kesilmiş görseller ~150 dpi kabul edilir.
    const emuPerTwip = 635;
    var cx = w / 150 * 914400 * 0.85, cy = h / 150 * 914400 * 0.85;
    final maxCx = maxWidthTwips * emuPerTwip.toDouble();
    if (cx > maxCx) {
      cy = cy * maxCx / cx;
      cx = maxCx;
    }
    const maxCy = 9.0 * 914400; // 9 inç
    if (cy > maxCy) {
      cx = cx * maxCy / cy;
      cy = maxCy;
    }
    final n = media.length + 1;
    final name = 'image$n.${png ? 'png' : 'jpeg'}';
    media.add((name, bytes));
    final id = 'rIdImg$n';
    final ex = cx.round(), ey = cy.round();
    final drawing = '<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="$ex" cy="$ey"/><wp:docPr id="$n" name="Resim $n"/>'
        '<wp:cNvGraphicFramePr><a:graphicFrameLocks xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" noChangeAspect="1"/></wp:cNvGraphicFramePr>'
        '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
        '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:nvPicPr><pic:cNvPr id="$n" name="$name"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="$id"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$ex" cy="$ey"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
        '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>';
    para(drawing, indent: indent, after: 60);
  }

  /// Basit tablo: [rows] hücre metinleri, ilk satır kalın olabilir.
  void table(List<List<String>> rows, {bool header = false, List<int>? widths}) {
    final cols = rows.isEmpty ? 0 : rows.first.length;
    final b = StringBuffer('<w:tbl><w:tblPr><w:tblW w:w="5000" w:type="pct"/>'
        '<w:tblBorders>'
        '<w:top w:val="single" w:sz="4" w:color="9AA0AE"/><w:left w:val="single" w:sz="4" w:color="9AA0AE"/>'
        '<w:bottom w:val="single" w:sz="4" w:color="9AA0AE"/><w:right w:val="single" w:sz="4" w:color="9AA0AE"/>'
        '<w:insideH w:val="single" w:sz="4" w:color="9AA0AE"/><w:insideV w:val="single" w:sz="4" w:color="9AA0AE"/>'
        '</w:tblBorders>${rtl ? '<w:bidiVisual/>' : ''}</w:tblPr><w:tblGrid>');
    for (var c = 0; c < cols; c++) {
      b.write('<w:gridCol w:w="${widths != null && c < widths.length ? widths[c] : 2000}"/>');
    }
    b.write('</w:tblGrid>');
    for (var r = 0; r < rows.length; r++) {
      b.write('<w:tr>');
      for (final cell in rows[r]) {
        final bold = header && r == 0;
        b.write('<w:tc><w:tcPr>${bold ? '<w:shd w:val="clear" w:color="auto" w:fill="F3F4F6"/>' : ''}</w:tcPr>'
            '<w:p><w:pPr><w:spacing w:before="40" w:after="40"/>${rtl ? '<w:bidi/>' : ''}</w:pPr>${run(cell, bold: bold, size: fs - 1)}</w:p></w:tc>');
      }
      b.write('</w:tr>');
    }
    b.write('</w:tbl>');
    body.write(b);
    para('', after: 60);
  }
}

/// Kitapçığı .docx olarak üretir. [variants] boşsa bütün kitapçıklar.
Uint8List buildBookletDocx(
  BookletPlan plan, {
  required SchoolInfo school,
  required Uint8List? Function(String? id) image,
  Set<int> variants = const {},
  bool answerKey = true,
}) {
  final o = plan.options;
  final fs = o.fontSize.clamp(8.0, 16.0);
  final d = _Doc(fs, L10n.rtl);
  final (pageW, pageH) = switch (o.paper) {
    PaperSize.a4 => (11906, 16838),
    PaperSize.a5 => (8391, 11906),
    PaperSize.letter => (12240, 15840),
  };
  final margin = o.paper == PaperSize.a5 ? 850 : 1077;
  final cols = o.columns.clamp(1, 2);
  final textW = pageW - 2 * margin;
  final colW = cols == 2 ? (textW - 567) ~/ 2 : textW;
  final multi = plan.variants.length > 1;
  final date = o.date ?? DateTime.now();
  final wanted = variants.isEmpty ? {for (final v in plan.variants) v.index} : variants;
  final chosen = plan.variants.where((v) => wanted.contains(v.index)).toList();

  // Bölümler: başlık tek sütun, sorular [cols] sütun. Word'de sütun değişimi
  // bölüm sonuyla yapılır.
  String sect({required int columns, bool continuous = true}) =>
      '<w:p><w:pPr><w:sectPr>${continuous ? '<w:type w:val="continuous"/>' : ''}'
      '<w:pgSz w:w="$pageW" w:h="$pageH"/>'
      '<w:pgMar w:top="$margin" w:right="$margin" w:bottom="$margin" w:left="$margin" w:header="567" w:footer="567" w:gutter="0"/>'
      '<w:cols w:num="$columns" w:space="567"${o.columnRule && columns > 1 ? ' w:sep="1"' : ''}/>'
      '${L10n.rtl ? '<w:bidi/>' : ''}</w:sectPr></w:pPr></w:p>';

  void header(BookletVariant v) {
    if (o.officialHeader && school.official) {
      for (final l in school.letterhead) {
        d.para(d.run(l, bold: true, size: fs + 0.5), align: 'center', after: 0);
      }
      d.para('', after: 60);
    }
    final title = o.title.trim().isEmpty ? tr('Soru kitapçığı') : o.title.trim();
    d.para(d.run(title, bold: true, size: fs + 4), align: 'center', after: 40);
    if (o.subtitle.trim().isNotEmpty) d.para(d.run(o.subtitle.trim(), size: fs + 1), align: 'center', after: 40);
    final info = [
      L10n.date(date),
      if (o.durationMinutes > 0) tr('Süre: {0} dk', [o.durationMinutes]),
      tr('{0} soru', [plan.questionCount]),
      if (multi) tr('{0} kitapçığı', [v.letter]),
    ].join('  ·  ');
    d.para(d.run(info, size: fs - 1, color: '4B5563'), align: 'center', after: 120);
    if (o.studentBox) {
      d.table([
        ['${tr('Adı Soyadı')}:', '${tr('Numara')}:'],
        ['${tr('Sınıf / şube')}:', '${tr('Puan')}:'],
      ], widths: [textW ~/ 2, textW ~/ 2]);
    }
    if (o.instructions.trim().isNotEmpty) {
      d.para(d.run(o.instructions.trim(), italic: true, size: fs - 1), after: 120, shade: 'F3F4F6');
    }
  }

  void question(PrintedQuestion p, {bool open = false, bool withAnswer = false}) {
    final q = p.question;
    const hang = 425;
    final pts = o.showPoints ? ' (${tr('{0} puan', [_fmt(p.points)])})' : '';
    d.para(d.run('${p.no}. ', bold: true) + d.run(q.text.trim()) + d.run(pts, size: fs - 1.5, color: '6B7280'),
        hanging: hang, before: 80, after: 40, keepNext: true);
    if (q.imageId != null) d.image(image(q.imageId), colW - hang, indent: hang);
    if (!open) {
      final texts = q.type == QuestionType.trueFalse ? [tr('Doğru'), tr('Yanlış')] : p.choices;
      if (texts.any((t) => t.trim().isNotEmpty)) {
        for (var i = 0; i < texts.length; i++) {
          d.para(d.run('${_letter(i)}) ', bold: true) + d.run(texts[i]), indent: hang, hanging: 340, after: 20);
        }
      }
    } else if (!withAnswer) {
      final n = q.type == QuestionType.fill ? 1 : q.answerLines.clamp(1, 30);
      for (var i = 0; i < n; i++) {
        d.para('', indent: hang, after: 0, before: 140, dotLineTo: colW - 60);
      }
    }
    if (withAnswer) {
      final a = q.type == QuestionType.multiple ? (p.printedCorrect.toList()..sort()).map(_letter).join('/') : q.answerLabel;
      d.para(d.run(tr('Cevap: {0}', [a]), bold: true, color: '047857'), indent: hang, after: 40);
    }
    if (o.showTopic && q.topicLabel.isNotEmpty) {
      d.para(d.run(q.topicLabel, italic: true, size: fs - 3, color: '6B7280'), indent: hang, after: 40);
    }
  }

  for (var vi = 0; vi < chosen.length; vi++) {
    final v = chosen[vi];
    header(v);
    d.body.write(sect(columns: 1, continuous: vi > 0 ? false : true));
    final runs = <String>[];
    for (final p in v.test) {
      if (runs.isEmpty || runs.last != p.question.subject) runs.add(p.question.subject);
    }
    final sections = o.sectionHeaders && runs.toSet().length > 1 && runs.length == runs.toSet().length;
    String? current;
    for (final p in v.test) {
      if (sections && p.question.subject != current) {
        current = p.question.subject;
        d.para(d.run(SchoolInfo.upper(current.isEmpty ? tr('Diğer') : current), bold: true), shade: 'F3F4F6', before: 120, keepNext: true);
      }
      question(p);
    }
    if (v.open.isNotEmpty) {
      d.para(d.run(SchoolInfo.upper(tr('Klasik sorular')), bold: true), shade: 'F3F4F6', before: 160, keepNext: true);
      for (final p in v.open) {
        question(p, open: true);
      }
    }
    d.body.write(sect(columns: cols));
  }

  if (answerKey && chosen.isNotEmpty && plan.questionCount > 0) {
    d.para(d.run(SchoolInfo.upper(tr('Cevap anahtarı')), bold: true, size: fs + 2), pageBreakBefore: true, after: 120);
    for (final v in chosen) {
      if (multi) d.para(d.run(tr('{0} kitapçığı', [v.letter]), bold: true), before: 80, after: 40);
      final rows = <List<String>>[
        [tr('Soru'), tr('Cevap'), tr('Konu')],
        for (final p in v.test)
          ['${p.no}', (p.printedCorrect.toList()..sort()).map(_letter).join('/'), p.question.topicLabel],
        for (final p in v.open) ['K${p.no}', p.question.answerLabel, p.question.topicLabel],
      ];
      d.table(rows, header: true, widths: [textW ~/ 8, textW ~/ 4, textW * 5 ~/ 8]);
    }
  }
  // Son bölüm özellikleri gövdenin sonunda.
  final lastSect = '<w:sectPr><w:type w:val="continuous"/><w:pgSz w:w="$pageW" w:h="$pageH"/>'
      '<w:pgMar w:top="$margin" w:right="$margin" w:bottom="$margin" w:left="$margin" w:header="567" w:footer="567" w:gutter="0"/>'
      '<w:cols w:num="1"/></w:sectPr>';

  final document = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
      '<w:body>${d.body}$lastSect</w:body></w:document>';

  final rels = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>');
  for (var i = 0; i < d.media.length; i++) {
    rels.write('<Relationship Id="rIdImg${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/${d.media[i].$1}"/>');
  }
  rels.write('</Relationships>');

  final font = switch (school.fontFamily) {
    'times' => 'Times New Roman',
    'arial' => 'Arial',
    _ => 'Calibri',
  };
  final styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="$font" w:hAnsi="$font" w:cs="$font" w:eastAsia="$font"/>'
      '<w:sz w:val="${(fs * 2).round()}"/><w:szCs w:val="${(fs * 2).round()}"/><w:lang w:val="${L10n.code}"/></w:rPr></w:rPrDefault>'
      '<w:pPrDefault><w:pPr><w:spacing w:after="80" w:line="264" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>'
      '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>'
      '</w:styles>';

  final contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Default Extension="png" ContentType="image/png"/>'
      '<Default Extension="jpeg" ContentType="image/jpeg"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
      '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
      '</Types>';
  const rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
      '</Relationships>';
  final core = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
      '<dc:title>${_x(o.title.trim().isEmpty ? tr('Soru kitapçığı') : o.title.trim())}</dc:title><dc:creator>Netice</dc:creator>'
      '</cp:coreProperties>';

  final a = Archive();
  void add(String name, String text) {
    final b = utf8.encode(text);
    a.addFile(ArchiveFile(name, b.length, b));
  }

  add('[Content_Types].xml', contentTypes);
  add('_rels/.rels', rootRels);
  add('docProps/core.xml', core);
  add('word/document.xml', document);
  add('word/styles.xml', styles);
  add('word/_rels/document.xml.rels', rels.toString());
  for (final (name, bytes) in d.media) {
    a.addFile(ArchiveFile('word/media/$name', bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(a));
}
