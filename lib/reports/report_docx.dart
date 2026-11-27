// Raporların düzenlenebilir Word (.docx) sürümü. PDF ile aynı içerik:
// resmî yazı başlığı (açıksa), başlıklar, özet tabloları, sonuç listeleri ve
// imza alanı. Grafikler yerine sayısal tablolar kullanılır; öğretmen belgeyi
// Word'de düzeltip kurum yazısına ekleyebilir.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../core/deneme.dart';
import '../core/models.dart';
import '../core/report.dart';
import '../core/scoring.dart';
import '../core/term.dart';
import '../l10n/l10n.dart';

String _x(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

String _f1(double v) => v.toStringAsFixed(1).replaceAll('.', L10n.decimal);
String _f2(double v) => v.toStringAsFixed(2).replaceAll('.', L10n.decimal);
String _pct(double v) => L10n.percent((v * 100).round());
String _letter(int i) => String.fromCharCode(65 + i);

/// Sade bir Word belgesi yazıcısı: paragraflar, tablolar, sayfa sonu.
class DocxReport {
  final SchoolInfo school;
  final bool landscape;
  final DateTime createdAt = DateTime.now();
  final _body = StringBuffer();

  DocxReport(this.school, {this.landscape = false});

  bool get _rtl => L10n.rtl;
  String get _font => switch (school.fontFamily) {
        'times' => 'Times New Roman',
        'arial' => 'Arial',
        _ => 'Calibri',
      };

  /// Yazı alanının genişliği (twip).
  int get _textWidth => (landscape ? 16838 : 11906) - 2 * 900;

  String _run(String t, {bool bold = false, bool italic = false, bool underline = false, double size = 10.5, String? color}) {
    if (t.isEmpty) return '';
    final pr = StringBuffer('<w:rPr>');
    if (_rtl) pr.write('<w:rtl/>');
    if (bold) pr.write('<w:b/><w:bCs/>');
    if (italic) pr.write('<w:i/><w:iCs/>');
    if (underline) pr.write('<w:u w:val="single"/>');
    if (color != null) pr.write('<w:color w:val="$color"/>');
    final sz = (size * 2).round();
    pr.write('<w:sz w:val="$sz"/><w:szCs w:val="$sz"/></w:rPr>');
    final parts = t.split('\n');
    final b = StringBuffer();
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) b.write('<w:r>$pr<w:br/></w:r>');
      b.write('<w:r>$pr<w:t xml:space="preserve">${_x(parts[i])}</w:t></w:r>');
    }
    return b.toString();
  }

  String _p(String runs, {String align = '', int before = 0, int after = 80, bool keepNext = false, String border = ''}) {
    final pr = StringBuffer('<w:pPr>');
    if (keepNext) pr.write('<w:keepNext/>');
    if (border.isNotEmpty) pr.write(border);
    pr.write('<w:spacing w:before="$before" w:after="$after"/>');
    if (_rtl) pr.write('<w:bidi/>');
    if (align.isNotEmpty) pr.write('<w:jc w:val="$align"/>');
    pr.write('</w:pPr>');
    return '<w:p>$pr$runs</w:p>';
  }

  /// Resmî yazı başlığı (kurum bilgisi ve "resmî başlık" açıksa) ya da sade başlık.
  void letterhead({required String docTitle, required String classLine, required DateTime date, required String info}) {
    if (school.official) {
      final hs = school.headerSize;
      for (final line in school.letterhead) {
        _body.write(_p(
            _run(line, bold: school.headerBold, italic: school.headerItalic, underline: school.headerUnderline, size: hs),
            align: 'center',
            after: 0));
      }
      final subject = school.subject.trim().isEmpty ? '' : tr(' {0} DERSİ', [SchoolInfo.upper(school.subject.trim())]);
      _body.write(_p(
          _run(tr('{0} EĞİTİM-ÖĞRETİM YILI {1}{2}', [SchoolInfo.academicYear(date), classLine, subject]), size: hs - 1),
          align: 'center',
          before: 120,
          after: 0));
      _body.write(_p(_run(SchoolInfo.upper(docTitle), bold: school.headerBold, size: hs), align: 'center', after: 60));
    } else {
      final inst = school.name.trim();
      _body.write(_p(_run(inst.isEmpty ? tr('Netice') : inst, bold: true, size: 12), after: 0));
      _body.write(_p(_run(docTitle, bold: true, size: 14, color: '0F1B3D'), after: 40));
    }
    _body.write(_p(
      _run('$info    ·    ${tr('Tarih: {0}', [L10n.date(createdAt)])}', size: 9),
      after: 200,
      border: '<w:pBdr><w:bottom w:val="single" w:sz="6" w:space="4" w:color="000000"/></w:pBdr>',
    ));
  }

  void heading(String t, [String? sub]) {
    _body.write(_p(_run(t, bold: true, size: 13, color: '0F1B3D'), before: 200, after: sub == null ? 80 : 0, keepNext: true));
    if (sub != null) _body.write(_p(_run(sub, size: 8.5, color: '6B7280'), after: 80, keepNext: true));
  }

  void text(String t, {double size = 10, bool bold = false, String? color}) =>
      _body.write(_p(_run(t, size: size, bold: bold, color: color)));

  void note(String t) => _body.write(_p(_run(t, size: 8, color: '6B7280'), before: 40));

  void pageBreak() => _body.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');

  /// Tablo. [flex]: sütunların göreli genişlikleri (verilmezse eşit);
  /// [leftColumn] sola, diğerleri ortaya hizalanır.
  void table(List<String> headers, List<List<String>> rows, {List<double>? flex, int? leftColumn, double size = 9}) {
    final n = headers.length;
    final f = flex ?? List.filled(n, 1.0);
    final sum = f.fold(0.0, (a, b) => a + b);
    final widths = [for (final v in f) (_textWidth * v / sum).floor()];
    final b = StringBuffer('<w:tbl><w:tblPr><w:tblW w:w="$_textWidth" w:type="dxa"/>');
    if (_rtl) b.write('<w:bidiVisual/>');
    b.write('<w:tblBorders>');
    for (final side in ['top', 'left', 'bottom', 'right', 'insideH', 'insideV']) {
      b.write('<w:$side w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>');
    }
    b.write('</w:tblBorders><w:tblLayout w:type="fixed"/>'
        '<w:tblCellMar><w:left w:w="70" w:type="dxa"/><w:right w:w="70" w:type="dxa"/></w:tblCellMar></w:tblPr><w:tblGrid>');
    for (final w in widths) {
      b.write('<w:gridCol w:w="$w"/>');
    }
    b.write('</w:tblGrid>');
    String cell(int i, String t, {bool head = false, bool odd = false}) {
      final shade = head ? '0F1B3D' : (odd ? 'F6F3EC' : null);
      final align = i == leftColumn ? (_rtl ? 'right' : 'left') : 'center';
      return '<w:tc><w:tcPr><w:tcW w:w="${widths[i]}" w:type="dxa"/>'
          '${shade == null ? '' : '<w:shd w:val="clear" w:color="auto" w:fill="$shade"/>'}<w:vAlign w:val="center"/></w:tcPr>'
          '${_p(_run(t, bold: head, size: size, color: head ? 'FFFFFF' : null), align: align, before: 20, after: 20)}</w:tc>';
    }

    b.write('<w:tr><w:trPr><w:tblHeader/><w:cantSplit/></w:trPr>');
    for (var i = 0; i < n; i++) {
      b.write(cell(i, headers[i], head: true));
    }
    b.write('</w:tr>');
    for (var r = 0; r < rows.length; r++) {
      b.write('<w:tr><w:trPr><w:cantSplit/></w:trPr>');
      for (var i = 0; i < n; i++) {
        b.write(cell(i, i < rows[r].length ? rows[r][i] : '', odd: r.isOdd));
      }
      b.write('</w:tr>');
    }
    b.write('</w:tbl>');
    _body.write(b);
    _body.write(_p('', after: 60));
  }

  /// Ad–değer çiftlerini iki sütunlu özet tablolarına dizer.
  void stats(List<(String, String)> items, {int perRow = 3}) {
    final rows = <List<String>>[];
    for (var i = 0; i < items.length; i += perRow) {
      rows.add([
        for (var j = i; j < i + perRow; j++) ...(j < items.length ? [items[j].$1, items[j].$2] : ['', '']),
      ]);
    }
    table([for (var j = 0; j < perRow; j++) ...[tr('Gösterge'), tr('Değer')]], rows,
        flex: [for (var j = 0; j < perRow; j++) ...[2.2, 1.0]], leftColumn: null, size: 9);
  }

  /// Ders öğretmeni ve kurum amiri imza alanı (resmî başlık açıkken).
  void signatures() {
    if (!school.official) return;
    final half = (_textWidth / 2).floor();
    String sig(String role, String name, {String? top}) => '<w:tc><w:tcPr><w:tcW w:w="$half" w:type="dxa"/></w:tcPr>'
        '${top == null ? _p('', after: 0) : _p(_run(top, bold: true, size: school.signSize - 0.5), align: 'center', after: 0)}'
        '${_p('', before: 500, after: 0)}'
        '${_p(_run(name.trim().isEmpty ? '..............................' : name.trim(), bold: true, size: school.signSize), align: 'center', after: 0)}'
        '${_p(_run(role, size: school.signSize - 1), align: 'center', after: 0)}</w:tc>';
    _body.write('<w:tbl><w:tblPr><w:tblW w:w="$_textWidth" w:type="dxa"/>${_rtl ? '<w:bidiVisual/>' : ''}'
        '<w:tblBorders><w:top w:val="nil"/><w:left w:val="nil"/><w:bottom w:val="nil"/><w:right w:val="nil"/>'
        '<w:insideH w:val="nil"/><w:insideV w:val="nil"/></w:tblBorders></w:tblPr>'
        '<w:tblGrid><w:gridCol w:w="$half"/><w:gridCol w:w="$half"/></w:tblGrid><w:tr>'
        '${sig(school.instructorRole, school.teacher)}'
        '${sig(school.headRole, school.principal, top: 'UYGUNDUR\n${L10n.date(createdAt)}')}'
        '</w:tr></w:tbl>');
  }

  Uint8List save({String title = ''}) {
    final w = landscape ? 16838 : 11906, h = landscape ? 11906 : 16838;
    final footer = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:p><w:pPr><w:jc w:val="center"/></w:pPr>'
        '${_run(tr('Netice ile hazırlandı'), size: 8, color: '6B7280')}${_run('  ·  ', size: 8, color: '6B7280')}'
        '<w:r><w:rPr><w:color w:val="6B7280"/><w:sz w:val="16"/></w:rPr><w:fldChar w:fldCharType="begin"/></w:r>'
        '<w:r><w:rPr><w:color w:val="6B7280"/><w:sz w:val="16"/></w:rPr><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>'
        '<w:r><w:rPr><w:color w:val="6B7280"/><w:sz w:val="16"/></w:rPr><w:fldChar w:fldCharType="separate"/></w:r>'
        '<w:r><w:rPr><w:color w:val="6B7280"/><w:sz w:val="16"/></w:rPr><w:t>1</w:t></w:r>'
        '<w:r><w:rPr><w:color w:val="6B7280"/><w:sz w:val="16"/></w:rPr><w:fldChar w:fldCharType="end"/></w:r>'
        '</w:p></w:ftr>';
    final doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><w:body>$_body'
        '<w:sectPr><w:footerReference w:type="default" r:id="rIdFtr"/>'
        '<w:pgSz w:w="$w" w:h="$h"${landscape ? ' w:orient="landscape"' : ''}/>'
        '<w:pgMar w:top="850" w:right="900" w:bottom="850" w:left="900" w:header="400" w:footer="400" w:gutter="0"/>'
        '</w:sectPr></w:body></w:document>';
    final styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr>'
        '<w:rFonts w:ascii="$_font" w:hAnsi="$_font" w:cs="$_font" w:eastAsia="$_font"/><w:sz w:val="21"/><w:szCs w:val="21"/>'
        '<w:lang w:val="${L10n.code}"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="80" w:line="252" w:lineRule="auto"/></w:pPr></w:pPrDefault>'
        '</w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>';
    final core = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>${_x(title)}</dc:title><dc:creator>Netice</dc:creator></cp:coreProperties>';
    final files = <String, String>{
      '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
          '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
          '<Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>'
          '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
          '</Types>',
      '_rels/.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
          '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
          '</Relationships>',
      'word/_rels/document.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
          '<Relationship Id="rIdFtr" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>'
          '</Relationships>',
      'word/document.xml': doc,
      'word/styles.xml': styles,
      'word/footer1.xml': footer,
      'docProps/core.xml': core,
    };
    final arc = Archive();
    files.forEach((name, content) {
      final bytes = utf8.encode(content);
      arc.addFile(ArchiveFile(name, bytes.length, bytes));
    });
    return Uint8List.fromList(ZipEncoder().encode(arc));
  }
}

String _examInfo(Exam exam) => tr('Sınav: {0} · {1}', [exam.name, L10n.date(exam.date)]);

/// Sınav analiz raporu (Word).
Uint8List buildResultsDocx({
  required Exam exam,
  required List<Result> results,
  required Map<String, Student> students,
  SchoolInfo school = const SchoolInfo(),
}) {
  final r = ExamReport.build(exam, results);
  final s = r.stats;
  final d = DocxReport(school);
  d.letterhead(docTitle: tr('Sınav Analiz Raporu'), classLine: school.classLine(exam.className), date: exam.date, info: _examInfo(exam));
  d.text(
      '${exam.name} · ${exam.className} · ${tr('{0} soru', [exam.questionCount])} · ${exam.rule.wrongsPerCorrect > 0 ? tr('{0} yanlış 1 doğruyu götürür', [exam.rule.wrongsPerCorrect]) : tr('Yanlış götürmez')}',
      bold: true);
  d.heading(tr('Genel istatistikler'));
  d.stats([
    (tr('Katılım'), '${s.count}'),
    (tr('Ortalama'), _f1(s.mean)),
    (tr('Medyan'), _f1(s.median)),
    (tr('Standart sapma'), _f1(s.stdDev)),
    (tr('Başarı oranı'), _pct(r.passRate)),
    (tr('En yüksek'), _f1(s.max)),
    (tr('En düşük'), _f1(s.min)),
    (tr('Çeyrekler'), '${_f1(r.q1)} – ${_f1(r.q3)}'),
    (tr('Ortalama net'), _f2(r.meanNet)),
    (tr('Ort. D / Y / B'), '${_f1(r.meanCorrect)} / ${_f1(r.meanWrong)} / ${_f1(r.meanBlank)}'),
    (tr('KR-20 güvenirlik'), s.kr20 == null ? '–' : _f2(s.kr20!)),
    (tr('Ölçme hatası (SEM)'), r.sem == null ? '–' : '±${_f1(r.sem!)}'),
    (tr('Ortalama güçlük'), _f2(r.meanP)),
    (tr('Ort. ayırt edicilik'), _f2(r.meanD)),
    (tr('Üst %27 ortalaması'), _f1(r.upperMean)),
    (tr('Alt %27 ortalaması'), _f1(r.lowerMean)),
  ]);
  d.heading(tr('Başarı düzeyleri'));
  d.table([tr('Düzey'), tr('Öğrenci'), tr('Oran')], [
    for (var i = 0; i < Level.all.length; i++)
      [Level.all[i].name, '${r.levelCounts[i]}', results.isEmpty ? '–' : _pct(r.levelCounts[i] / results.length)],
  ], flex: [3, 1, 1], leftColumn: 0);
  if (r.outcomes.isNotEmpty) {
    d.heading(tr('Kazanım / konu analizi'), tr('Sınıfın her kazanımdaki doğru oranı'));
    d.table([tr('Kazanım'), tr('Soru'), tr('Doğru oranı')], [
      for (final o in [...r.outcomes]..sort((a, b) => a.rate.compareTo(b.rate)))
        [o.code, o.questionNos.join(', '), _pct(o.rate)],
    ], flex: [4, 2, 1.2], leftColumn: 0);
  }
  if (exam.isMultiSubject) {
    final dn = DenemeReport.build(exam, results);
    d.heading(tr('Ders ders sonuçlar'));
    d.table([tr('Ders'), tr('Soru'), tr('Ort. doğru'), tr('Ort. yanlış'), tr('Ortalama net'), tr('Başarı')], [
      for (final x in dn.summaries) [x.section.name, '${x.counted}', _f2(x.meanCorrect), _f2(x.meanWrong), _f2(x.meanNet), L10n.percent(x.percent.round())],
    ], flex: [3, 1, 1, 1, 1, 1], leftColumn: 0);
  }
  d.pageBreak();
  d.heading(tr('Sınıf sonuç listesi'), tr('Yüzdelik: sınıfın yüzde kaçından daha başarılı · T: ortalaması 50, sapması 10 olan standart puan'));
  d.table(
    [tr('Sıra'), tr('Ad Soyad'), tr('No'), tr('D'), tr('Y'), tr('B'), tr('Net'), if (exam.hasOpen) ...[tr('Test'), tr('Klasik')], tr('Puan'), tr('Yüzdelik'), 'T', tr('Düzey')],
    [
      for (final st in r.standings)
        [
          '${st.rank}',
          students[st.result.sheet.studentId]?.fullName ?? tr('Eşleşmedi'),
          students[st.result.sheet.studentId]?.number ?? '',
          '${st.result.correct}',
          '${st.result.wrong}',
          '${st.result.blank}',
          _f2(st.result.net),
          if (exam.hasOpen) ...[_f1(st.result.testScore), st.result.openMissing ? tr('eksik') : _f1(st.result.openScore)],
          _f1(st.result.score),
          L10n.percent(st.percentile.round()),
          _f1(st.t),
          st.level.name,
        ],
    ],
    flex: [0.8, 3.5, 1.2, 0.7, 0.7, 0.7, 1, if (exam.hasOpen) ...[1, 1], 1, 1.2, 0.9, 1.6],
    leftColumn: 1,
    size: 8.5,
  );
  d.pageBreak();
  d.heading(tr('Madde analizi'), tr('p = doğru oranı (güçlük) · D = ayırt edicilik (üst %27 − alt %27) · Değerler öğretmene yol gösteren uyarılardır.'));
  d.table(
    [tr('Soru'), tr('Anahtar'), 'p', 'D', for (var c = 0; c < exam.choiceCount; c++) _letter(c), tr('Boş'), tr('Yorum')],
    [
      for (final it in r.items)
        () {
          final q = exam.questions[it.no - 1];
          return [
            '${it.no}',
            q.cancelled ? tr('İptal') : q.correct.map(_letter).join('/'),
            _f2(it.p),
            _f2(it.d),
            for (var c = 0; c < exam.choiceCount; c++) q.correct.contains(c) ? '${it.choiceCounts[c]}*' : '${it.choiceCounts[c]}',
            '${it.blankCount}',
            it.suspiciousChoice != null
                ? tr('Üst grup {0} seçti; anahtarı kontrol edin', [_letter(it.suspiciousChoice!)])
                : '${it.difficultyLabel} · ${it.discriminationLabel}',
          ];
        }(),
    ],
    flex: [0.7, 1, 0.8, 0.8, for (var c = 0; c < exam.choiceCount; c++) 0.6, 0.7, 4],
    leftColumn: 5 + exam.choiceCount,
    size: 8,
  );
  d.note(tr('* doğru şık'));
  d.signatures();
  return d.save(title: tr('{0} sınav raporu', [exam.name]));
}

/// Çok dersli deneme sonuç listesi (Word).
Uint8List buildDenemeDocx({required DenemeReport report, required Map<String, Student> students, SchoolInfo school = const SchoolInfo()}) {
  final exam = report.exam;
  final w = exam.hasWeightedScore;
  final d = DocxReport(school, landscape: true);
  d.letterhead(docTitle: tr('Deneme Sınavı Sonuç Listesi'), classLine: school.classLine(exam.className), date: exam.date, info: _examInfo(exam));
  d.heading(tr('Deneme sınavı sonuçları'),
      tr('{0} öğrenci · {1} ders · {2} soru · ortalama toplam net {3}', [report.rows.length, exam.sections.length, exam.questionCount, _f2(report.meanTotalNet)]));
  d.heading(tr('Ders başarı sıralaması'));
  d.table([tr('Sıra'), tr('Ders'), tr('Soru'), tr('Ortalama net'), tr('Başarı')], [
    for (final (i, s) in report.ranked.indexed) ['${i + 1}', s.section.name, '${s.counted}', _f2(s.meanNet), L10n.percent(s.percent.round())],
  ], flex: [0.6, 4, 1, 1.2, 1], leftColumn: 1);
  d.heading(tr('Öğrenci sıralaması'));
  d.table(
    [tr('Sıra'), tr('Ad Soyad'), for (final s in exam.sections) s.name, tr('Toplam net'), w ? tr('Puan') : tr('Not')],
    [
      for (final r in report.rows)
        [
          '${r.rank}',
          students[r.result.sheet.studentId]?.fullName ?? tr('Eşleşmeyen kâğıt'),
          for (final s in r.sections) '${s.correct}/${s.wrong} · ${_f2(s.net)}',
          _f2(r.totalNet),
          w ? _f2(r.weighted!) : _f1(r.result.score),
        ]
    ],
    flex: [0.6, 3, for (final _ in exam.sections) 1.4, 1, 1],
    leftColumn: 1,
    size: exam.sections.length > 5 ? 7.5 : 8.5,
  );
  d.note(tr('Ders sütunlarında doğru/yanlış · net yazılıdır.') + (w ? ' ${tr('Puan = taban puan + her dersin neti × katsayısı (tahmini).')}' : ''));
  d.signatures();
  return d.save(title: tr('{0} deneme sonuçları', [exam.name]));
}

/// e-Okul not giriş listesi (Word): okul numarasına göre sıralı.
Uint8List buildEokulDocx({
  required Exam exam,
  required List<(Student, int?)> rows,
  SchoolInfo school = const SchoolInfo(),
}) {
  final d = DocxReport(school);
  d.letterhead(docTitle: tr('Not Giriş Listesi'), classLine: school.classLine(exam.className), date: exam.date, info: _examInfo(exam));
  d.heading(tr('e-Okul not giriş listesi'),
      tr('Okul numarasına göre sıralı · puanlar tam sayıya yuvarlandı · {0} üzerinden', [exam.rule.maxScore.round()]));
  d.table([tr('Sıra'), tr('Okul No'), tr('Ad Soyad'), tr('Puan'), tr('Not')], [
    for (var i = 0; i < rows.length; i++)
      ['${i + 1}', rows[i].$1.number, rows[i].$1.fullName, rows[i].$2 == null ? tr('G') : '${rows[i].$2}', rows[i].$2 == null ? tr('Sınava girmedi') : ''],
  ], flex: [0.7, 1.2, 4, 1, 2], leftColumn: 2);
  d.signatures();
  return d.save(title: tr('{0} e-Okul listesi', [exam.name]));
}

/// Dönem sonu not çizelgesi (Word).
Uint8List buildTermGradesDocx(TermReport t, {SchoolInfo school = const SchoolInfo()}) {
  final equal = t.exams.every((e) => e.weight == t.exams.first.weight);
  final totalW = t.exams.fold<double>(0, (a, e) => a + e.weight);
  final d = DocxReport(school, landscape: t.exams.length > 5);
  d.letterhead(
    docTitle: tr('Dönem Sonu Not Çizelgesi'),
    classLine: school.classLine(t.className),
    date: t.exams.last.exam.date,
    info: tr('{0} · {1} · {2} sınav', [t.term.label, t.className, t.exams.length]),
  );
  d.heading(tr('Dönem sonu not çizelgesi'),
      tr('{0} · puanlar 100 üzerinden · {1} · girilmeyen sınav ortalamaya katılmaz', [t.term.label, equal ? tr('sınavlar eşit ağırlıklı') : tr('ağırlıklı ortalama')]));
  d.table([tr('Sınav'), tr('Tarih'), tr('Ağırlık'), tr('Katılım'), tr('Sınıf ort. (100)')], [
    for (final e in t.exams)
      [e.exam.name, L10n.date(e.exam.date), totalW == 0 ? '–' : L10n.percent((e.weight / totalW * 100).round()), '${e.report.results.length}', _f1(e.mean100)],
  ], flex: [4, 1.5, 1, 1, 1.4], leftColumn: 0);
  d.table(
    [tr('No'), tr('Ad Soyad'), for (var i = 0; i < t.exams.length; i++) '${i + 1}. ${t.exams[i].exam.name}', tr('Ortalama'), tr('Dönem notu')],
    [
      for (final r in t.rows)
        [
          r.student.number,
          r.student.fullName,
          for (final s in r.scores) s == null ? tr('G') : _f1(s),
          r.average == null ? '–' : _f2(r.average!),
          r.grade == null ? tr('G') : '${r.grade}',
        ]
    ],
    flex: [1, 3.5, for (final _ in t.exams) 1.2, 1.2, 1.2],
    leftColumn: 1,
    size: t.exams.length > 6 ? 7.5 : 9,
  );
  d.note(tr('G: sınava girmedi. Dönem notu, ortalamanın tam sayıya yuvarlanmış hâlidir.'));
  d.signatures();
  return d.save(title: tr('Dönem not çizelgesi'));
}
