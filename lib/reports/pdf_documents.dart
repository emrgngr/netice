import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/models.dart';
import '../core/progress.dart';
import '../core/report.dart';
import '../core/scoring.dart';
import '../core/term.dart';
import '../core/legal.dart';
import '../omr/form_code.dart';
import '../omr/form_layout.dart';

const _ink = PdfColor.fromInt(0xFF0F1B3D);
const _emerald = PdfColor.fromInt(0xFF10B981);
const _muted = PdfColor.fromInt(0xFF6B7280);
const _coral = PdfColor.fromInt(0xFFE8613C);
const _amber = PdfColor.fromInt(0xFFF2B33D);
const _gray = PdfColor.fromInt(0xFF9AA0AE);
const _ivory = PdfColor.fromInt(0xFFF6F3EC);
const _line = PdfColor.fromInt(0xFFE2DDD1);
const _levelColors = [_emerald, PdfColor.fromInt(0xFF34D399), _amber, PdfColor.fromInt(0xFFF59E0B), _coral];

class _Fonts {
  final pw.Font regular;
  final pw.Font bold;
  _Fonts(this.regular, this.bold);

  static Future<_Fonts> load() async {
    Future<pw.Font> f(String name) async =>
        pw.Font.ttf(await rootBundle.load('assets/fonts/PlusJakartaSans_$name.ttf'));
    return _Fonts(await f('400Regular'), await f('700Bold'));
  }
}

/// Basılı optik formlar. Her öğrenci için adı ve numarası yazılı bir sayfa
/// üretir; [students] boşsa [blankCopies] adet boş form üretir.
///
/// Sınavın B kitapçığı varsa ve [alternateBooklets] açıksa isimli formlar
/// sırayla A, B, A, B… olarak basılır (kitapçık dairesi dolu gelir).
Future<Uint8List> buildFormsPdf(Exam exam, List<Student> students,
    {int blankCopies = 1, SchoolInfo school = const SchoolInfo(), bool alternateBooklets = false}) async {
  final fonts = await _Fonts.load();
  final layout =
      FormLayout(questionCount: exam.questionCount, choiceCount: exam.choiceCount, booklets: exam.hasBooklets);
  final doc = pw.Document(title: '${exam.name} · optik form', author: 'Netice');
  final pages = students.isEmpty
      ? List<Student?>.filled(math.max(1, blankCopies), null)
      : students.cast<Student?>();
  for (var i = 0; i < pages.length; i++) {
    final s = pages[i];
    final booklet = exam.hasBooklets && alternateBooklets && s != null ? i % 2 : null;
    doc.addPage(_formPage(layout, exam, fonts, school, student: s, booklet: booklet));
  }
  return doc.save();
}

/// Cevap anahtarı formu. [filled] ise doğru şıklar karartılmış basılır ve
/// ikinci sayfada okunaklı bir anahtar listesi yer alır; değilse öğretmenin
/// elle dolduracağı boş bir anahtar formu üretilir.
Future<Uint8List> buildAnswerKeyPdf(Exam exam, {bool filled = true, SchoolInfo school = const SchoolInfo()}) async {
  final fonts = await _Fonts.load();
  final layout =
      FormLayout(questionCount: exam.questionCount, choiceCount: exam.choiceCount, booklets: exam.hasBooklets);
  final doc = pw.Document(title: '${exam.name} · cevap anahtarı', author: 'Netice');
  doc.addPage(_formPage(layout, exam, fonts, school, key: true, keyFilled: filled, booklet: exam.hasBooklets ? 0 : null));
  if (exam.hasBooklets && filled) {
    doc.addPage(_formPage(layout, exam, fonts, school, key: true, keyFilled: true, booklet: 1));
  }
  if (filled) {
    final k = _Kit(exam, school, docTitle: 'Cevap Anahtarı');
    final theme = pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold);
    final qs = exam.questions;
    String ans(Question q) => q.cancelled ? 'İptal' : (q.correct.isEmpty ? '–' : q.correct.map(_letter).join(' / '));
    String pts(double v) => v == v.roundToDouble() ? '${v.round()}' : _f1(v);
    final possible = qs.where((q) => !q.cancelled).fold<double>(0, (a, q) => a + q.points);
    // Sorunun puan tablosundaki gerçek değeri (ağırlık, toplam puana ölçeklenir).
    double worth(Question q) => possible == 0 ? 0 : q.points / possible * exam.rule.maxScore;
    doc.addPage(pw.MultiPage(
      theme: theme,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 28),
      header: k.header,
      footer: k.footer,
      build: (ctx) => [
        k.title('Cevap anahtarı', '${exam.questionCount} soru · ${exam.choiceCount} şık · sınav tarihi ${_date(exam.date)}'),
        for (final (label, list) in [
          (exam.hasBooklets ? 'A kitapçığı · hızlı okuma (beşli gruplar)' : 'Hızlı okuma (beşli gruplar)', qs),
          if (exam.hasBooklets) ('B kitapçığı · hızlı okuma (beşli gruplar)', exam.bookletBQuestions),
        ]) ...[
          pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: _ink)),
          pw.SizedBox(height: 6),
          pw.Wrap(spacing: 6, runSpacing: 6, children: [
            for (var i = 0; i < list.length; i += 5)
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: pw.BoxDecoration(color: _ivory, borderRadius: pw.BorderRadius.circular(4)),
                child: pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
                  pw.Text('${i + 1}–${math.min(i + 5, list.length)}  ',
                      style: const pw.TextStyle(color: _muted, fontSize: 8)),
                  pw.Text(
                    [
                      for (final q in list.skip(i).take(5))
                        q.cancelled ? '×' : (q.correct.isEmpty ? '–' : q.correct.map(_letter).join('/'))
                    ].join(' '),
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: _ink, letterSpacing: 1),
                  ),
                ]),
              ),
          ]),
          pw.SizedBox(height: 10),
        ],
        if (exam.hasBooklets)
          pw.Text('B kitapçığı sırası (B\'deki soru → A\'daki soru): '
              '${[for (var i = 0; i < exam.bookletOrder!.length; i++) '${i + 1}→${exam.bookletOrder![i] + 1}'].join('  ')}',
              style: const pw.TextStyle(color: _muted, fontSize: 7.5)),
        pw.SizedBox(height: 14),
        pw.TableHelper.fromTextArray(
          headers: [exam.hasBooklets ? 'Soru (A)' : 'Soru', 'Doğru cevap', 'Puan', 'Kazanım'],
          data: [
            for (final q in qs) ['${q.no}', ans(q), q.cancelled ? '–' : _f1(worth(q)).replaceAll(',0', ''), q.outcomeCode ?? ''],
          ],
          border: null,
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: _ink),
          cellStyle: const pw.TextStyle(fontSize: 8.5),
          oddRowDecoration: const pw.BoxDecoration(color: _ivory),
          cellAlignments: {0: pw.Alignment.center, 1: pw.Alignment.center, 2: pw.Alignment.center, 3: pw.Alignment.centerLeft},
          columnWidths: {
            0: const pw.FixedColumnWidth(40),
            1: const pw.FixedColumnWidth(80),
            2: const pw.FixedColumnWidth(50),
            3: const pw.FlexColumnWidth(),
          },
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          'Toplam puan: ${pts(exam.rule.maxScore)} · Geçme puanı: ${pts(exam.rule.pass)}'
          '${qs.any((q) => q.cancelled) ? ' · İptal edilen sorular herkese doğru sayılır.' : ''}',
          style: const pw.TextStyle(color: _muted, fontSize: 8),
        ),
      ],
    ));
  }
  return doc.save();
}

pw.Page _formPage(FormLayout layout, Exam exam, _Fonts fonts, SchoolInfo school,
        {Student? student, bool key = false, bool keyFilled = false, int? booklet}) =>
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (ctx) => pw.CustomPaint(
        size: PdfPoint(PdfPageFormat.a4.width, PdfPageFormat.a4.height),
        painter: (canvas, size) => _paintForm(canvas, size, layout, exam, student,
            (fonts.regular.getFont(ctx), fonts.bold.getFont(ctx)),
            key: key, keyFilled: keyFilled, school: school, booklet: booklet),
      ),
    );

const _frame = PdfColor.fromInt(0xFFB9B3A6);
const _tint = PdfColor.fromInt(0xFFF3F1EB);

/// Optik formu çizer. Daireler ve köşe kareleri [FormLayout]'taki yerlerinde
/// kalır (okuma motoru onları orada arar); süslemeler dairelerden en az
/// 2,5 mm uzakta tutulur ve koyu dolgulu büyük şekil kullanılmaz.
void _paintForm(PdfGraphics g, PdfPoint size, FormLayout layout, Exam exam, Student? s, (PdfFont, PdfFont) fonts,
    {bool key = false, bool keyFilled = false, SchoolInfo school = const SchoolInfo(), int? booklet}) {
  const mm = PdfPageFormat.mm;
  // PDF koordinatları sol alttan başlar; form mm koordinatları sol üstten.
  double x(double v) => v * mm;
  double y(double v) => size.y - v * mm;

  double width(String t, double pt, {bool bold = false}) =>
      (bold ? fonts.$2 : fonts.$1).stringMetrics(t).width * pt / mm;

  void text(String t, double px, double py, double pt,
      {bool bold = false, PdfColor color = _ink, bool right = false, bool center = false}) {
    final w = width(t, pt, bold: bold);
    final left = right ? px - w : (center ? px - w / 2 : px);
    g.setFillColor(color);
    g.drawString(bold ? fonts.$2 : fonts.$1, pt, t, x(left), y(py));
  }

  void box(double x0, double y0, double x1, double y1,
      {PdfColor? stroke = _frame, PdfColor? fill, double radius = 1.6, double line = 0.5}) {
    if (fill != null) {
      g.setFillColor(fill);
      g.drawRRect(x(x0), y(y1), (x1 - x0) * mm, (y1 - y0) * mm, radius * mm, radius * mm);
      g.fillPath();
    }
    if (stroke != null) {
      g.setStrokeColor(stroke);
      g.setLineWidth(line);
      g.drawRRect(x(x0), y(y1), (x1 - x0) * mm, (y1 - y0) * mm, radius * mm, radius * mm);
      g.strokePath();
    }
  }

  void field(String label, String value, double x0, double y0, double x1,
      {double h = 9, PdfColor valueColor = _ink, bool bold = true}) {
    box(x0, y0, x1, y0 + h);
    text(label, x0 + 2, y0 + 3.1, 5.6, bold: true, color: _muted);
    if (value.isNotEmpty) {
      var v = value;
      var pt = 10.0;
      while (pt > 6.5 && width(v, pt, bold: bold) > x1 - x0 - 4) {
        pt -= 0.5;
      }
      text(v, x0 + 2, y0 + 7.4, pt, bold: bold, color: valueColor);
    }
  }

  // ---- Köşe kareleri (okuma için) ----
  g.setFillColor(PdfColors.black);
  for (final o in FormLayout.markerOrigins) {
    g.drawRect(x(o.x), y(o.y + FormLayout.markerSize), FormLayout.markerSize * mm, FormLayout.markerSize * mm);
  }
  g.fillPath();

  // ---- Üst bant ----
  g.setFillColor(_emerald);
  g.drawEllipse(x(25.8), y(13.6), 1.5 * mm, 1.5 * mm);
  g.fillPath();
  g.setFillColor(_ink);
  g.drawEllipse(x(29.4), y(13.6), 1.0 * mm, 1.0 * mm);
  g.fillPath();
  text('Netice', 32, 15.4, 12, bold: true);
  text('Kâğıttan sonuca, saniyeler içinde.', 24.3, 19.4, 6, color: _muted);
  text(key ? 'CEVAP ANAHTARI' : 'OPTİK CEVAP KÂĞIDI', 186, 15.2, 11.5,
      bold: true, right: true, color: key ? _coral : _ink);
  text(
      '${exam.questionCount} soru · ${exam.choiceCount} şık'
      '${booklet == null ? '' : ' · ${_letter(booklet)} kitapçığı'}',
      186, 19.2, 6.5, right: true, color: booklet == 1 ? _coral : _muted, bold: booklet != null);

  // ---- Makine kodu (sol kenar) ----
  final codeBits = FormCode(
    examCode: FormCode.examCodeOf(exam.id),
    studentNumber: key ? null : int.tryParse(s?.number ?? ''),
    booklet: booklet ?? 0,
  ).encode();
  g.setFillColor(PdfColors.black);
  for (var i = 0; i < codeBits.length; i++) {
    if (!codeBits[i]) continue;
    final c = FormCode.cell(i);
    const h = FormCode.cellSize / 2;
    g.drawRect(x(c.x - h), y(c.y + h), FormCode.cellSize * mm, FormCode.cellSize * mm);
  }
  g.fillPath();

  // ---- Bilgi alanları (sol blok) ----
  const l = 24.0, r = 128.0;
  if (key) {
    field('BU KÂĞIT', 'CEVAP ANAHTARIDIR · öğrenciye dağıtmayın', l, 22, r, valueColor: _coral);
  } else {
    field('ADI SOYADI', s?.fullName ?? '', l, 22, r);
  }
  field('SINIFI / ŞUBESİ', key ? exam.className : (s?.className ?? ''), l, 32.5, 60);
  field('OKUL NO', key ? '—' : (s?.number ?? ''), 62, 32.5, 92);
  field('SINAV TARİHİ', _date(exam.date), 94, 32.5, r, bold: false);
  field('SINAV', exam.name, l, 43, r);
  field('OKUL', school.name.trim(), l, 53.5, 92, bold: false);
  field('DERS', school.subject.trim(), 94, 53.5, r, bold: false);

  // Öğretmen kutucukları.
  final cells = key
      ? [
          ('SORU', '${exam.questionCount}'),
          ('ŞIK', '${exam.choiceCount}'),
          ('TOPLAM PUAN', exam.rule.maxScore == exam.rule.maxScore.roundToDouble()
              ? '${exam.rule.maxScore.round()}'
              : _f1(exam.rule.maxScore)),
          ('İPTAL', '${exam.questions.where((q) => q.cancelled).length}'),
          ('KAZANIM', '${exam.questions.map((q) => q.outcomeCode).whereType<String>().toSet().length}'),
        ]
      : [('DOĞRU', ''), ('YANLIŞ', ''), ('BOŞ', ''), ('NET', ''), ('PUAN', '')];
  text(key ? 'SINAV BİLGİSİ' : 'ÖĞRETMEN DOLDURUR', l, 66.2, 5.6, bold: true, color: _muted);
  const cw = (r - l - 4 * 1.5) / 5;
  for (var i = 0; i < cells.length; i++) {
    final x0 = l + i * (cw + 1.5);
    box(x0, 67.5, x0 + cw, 76, fill: key ? null : _tint);
    text(cells[i].$1, x0 + 1.6, 70.4, 5, bold: true, color: _muted);
    if (cells[i].$2.isNotEmpty) text(cells[i].$2, x0 + cw - 2, 74.6, 9, bold: true, right: true);
  }

  // Doldurma örneği ve kısa yönerge.
  text(key ? 'ÖĞRETMEN İÇİN' : 'NASIL DOLDURULUR?', l, 81, 5.6, bold: true, color: _muted);
  if (key) {
    final lines = keyFilled
        ? [
            'Doğru şıklar Netice tarafından karartıldı.',
            'Bu sayfa kontrol ve arşiv içindir; okunaklı',
            'anahtar listesi son sayfadadır.',
          ]
        : [
            'Her sorunun doğru şıkkını karartın.',
            'Sonra Sınav ayarları › Anahtarı fotoğraftan',
            'oku ile çekin; anahtar kendiliğinden girilir.',
          ];
    for (var i = 0; i < lines.length; i++) {
      text(lines[i], l, 85.4 + i * 3.4, 6.6, color: _ink);
    }
  } else {
    // Örnek daireler küçük çizilir (okuma motorunun köşe arayışına karışmasın).
    const er = 1.7;
    void sample(double cx, double cy, {bool fill = false}) {
      g.setStrokeColor(PdfColors.grey600);
      g.setLineWidth(0.5);
      g.drawEllipse(x(cx), y(cy), er * mm, er * mm);
      g.strokePath();
      if (fill) {
        g.setFillColor(const PdfColor.fromInt(0xFF1F1F1F));
        g.drawEllipse(x(cx), y(cy), er * 0.95 * mm, er * 0.95 * mm);
        g.fillPath();
      }
    }

    text('Doğru:', l, 86.3, 6.6, bold: true, color: _emerald);
    sample(l + 11.4, 85.4, fill: true);
    text('Yanlış:', l + 17, 86.3, 6.6, bold: true, color: _coral);
    final wx = [l + 28, l + 33.5, l + 39, l + 44.5];
    for (final cx in wx) {
      sample(cx, 85.4);
    }
    g.setStrokeColor(const PdfColor.fromInt(0xFF1F1F1F));
    g.setLineWidth(0.6);
    // ✓
    g.moveTo(x(wx[0] - 0.9), y(85.4));
    g.lineTo(x(wx[0] - 0.2), y(86.2));
    g.lineTo(x(wx[0] + 1.0), y(84.5));
    // ×
    g.moveTo(x(wx[1] - 0.9), y(84.5));
    g.lineTo(x(wx[1] + 0.9), y(86.3));
    g.moveTo(x(wx[1] + 0.9), y(84.5));
    g.lineTo(x(wx[1] - 0.9), y(86.3));
    // —
    g.moveTo(x(wx[3] - 1.0), y(85.4));
    g.lineTo(x(wx[3] + 1.0), y(85.4));
    g.strokePath();
    // nokta
    g.setFillColor(const PdfColor.fromInt(0xFF1F1F1F));
    g.drawEllipse(x(wx[2]), y(85.4), 0.45 * mm, 0.45 * mm);
    g.fillPath();
    text('Daireyi tamamen karartın; kurşun kalem ya da koyu', l, 90.6, 6.3);
    text('tükenmez kullanın. Değiştirirken eskisini iyice silin.', l, 93.6, 6.3);
    text('Kenardaki siyah karelere yazmayın, kâğıdı katlamayın.', l, 96.6, 6.3);
  }

  // ---- Kitapçık türü ----
  if (layout.booklets) {
    final a = FormLayout.bookletBubble(0), b = FormLayout.bookletBubble(1);
    box(a.x - 6, 79, b.x + 6, 96.5, radius: 2, fill: _tint);
    text('KİTAPÇIK', (a.x + b.x) / 2, 82.6, 5.6, bold: true, color: _muted, center: true);
    for (var k = 0; k < 2; k++) {
      final p = FormLayout.bookletBubble(k);
      g.setFillColor(PdfColors.white);
      g.drawEllipse(x(p.x), y(p.y), FormLayout.bubbleRadius * mm, FormLayout.bubbleRadius * mm);
      g.fillPath();
      _bubble(g, x(p.x), y(p.y), FormLayout.bubbleRadius * mm, _letter(k), fonts);
      if (booklet == k) {
        g.setFillColor(const PdfColor.fromInt(0xFF151515));
        g.drawEllipse(x(p.x), y(p.y), FormLayout.bubbleRadius * 0.95 * mm, FormLayout.bubbleRadius * 0.95 * mm);
        g.fillPath();
      }
    }
    text(booklet == null ? 'Türünüzü işaretleyin' : '${_letter(booklet)} kitapçığı', (a.x + b.x) / 2, 95, 5,
        color: _muted, center: true);
  }

  // ---- Öğrenci numarası ----
  final rad = FormLayout.bubbleRadius * mm;
  final first = layout.studentBubble(0, 0);
  final last = layout.studentBubble(FormLayout.studentDigits - 1, 9);
  box(first.x - 6, 22, last.x + 6, last.y + 5.2, radius: 2);
  text('ÖĞRENCİ NUMARASI', (first.x + last.x) / 2, 25.6, 5.6, bold: true, color: _muted, center: true);
  final number = key ? null : s?.number.padLeft(FormLayout.studentDigits, '0');
  for (var d = 0; d < FormLayout.studentDigits; d++) {
    final top = layout.studentBubble(d, 0);
    box(top.x - 3, 27.4, top.x + 3, 34.2, radius: 0.8, stroke: PdfColors.grey500);
    if (number != null && number.length == FormLayout.studentDigits) {
      text(number[d], top.x, 32.8, 10, bold: true, center: true);
    }
    for (var v = 0; v < 10; v++) {
      final b = layout.studentBubble(d, v);
      _bubble(g, x(b.x), y(b.y), rad, '$v', fonts);
    }
  }

  // ---- Cevaplar ----
  final per = FormLayout.questionsPerColumn;
  for (var col = 0; col < layout.columnCount; col++) {
    final firstQ = col * per;
    final rows = math.min(per, layout.questionCount - firstQ);
    final a0 = layout.answerBubble(firstQ, 0);
    final aN = layout.answerBubble(firstQ, layout.choiceCount - 1);
    final x0 = a0.x - 10, x1 = aN.x + 5;
    final y0 = FormLayout.answersTop - 8.2;
    final y1 = FormLayout.answersTop + (rows - 1) * FormLayout.rowPitch + 5;
    // Beşli grupları ayırt etmek için her ikinci grup hafif renkli.
    for (var gr = 1; gr * 5 < rows; gr += 2) {
      final top = FormLayout.answersTop + (gr * 5) * FormLayout.rowPitch - FormLayout.rowPitch / 2;
      final bottom = math.min(top + 5 * FormLayout.rowPitch, y1 - 0.4);
      box(x0 + 0.4, top, x1 - 0.4, bottom, stroke: null, fill: _tint, radius: 0.8);
    }
    box(x0, y0, x1, y1, radius: 2);
    for (var c = 0; c < layout.choiceCount; c++) {
      final b = layout.answerBubble(firstQ, c);
      text(_letter(c), b.x, y0 + 2.9, 6, bold: true, center: true, color: _muted);
    }
    for (var row = 0; row < rows; row++) {
      final q = firstQ + row;
      final b0 = layout.answerBubble(q, 0);
      text('${q + 1}', b0.x - 4.3, b0.y + 1.1, 7.5, bold: true, right: true);
      final question = key && booklet == 1 ? exam.bookletBQuestions[q] : exam.questions[q];
      for (var c = 0; c < layout.choiceCount; c++) {
        final b = layout.answerBubble(q, c);
        _bubble(g, x(b.x), y(b.y), rad, _letter(c), fonts);
        if (key && keyFilled && !question.cancelled && question.correct.contains(c)) {
          g.setFillColor(const PdfColor.fromInt(0xFF151515));
          g.drawEllipse(x(b.x), y(b.y), rad * 0.95, rad * 0.95);
          g.fillPath();
        }
      }
    }
  }

  // Tek sütunlu formda boş kalan sağ tarafa not ve imza alanları.
  if (!key && layout.columnCount == 1) {
    final nx = layout.answerBubble(0, layout.choiceCount - 1).x + 13;
    final y0 = FormLayout.answersTop - 8.2;
    box(nx, y0, 186, y0 + 40, radius: 2);
    text('NOTLAR / AÇIKLAMA', nx + 2.5, y0 + 4, 5.6, bold: true, color: _muted);
    final mid = (nx + 186) / 2;
    box(nx, y0 + 44, mid - 1.5, y0 + 62, radius: 2);
    text('ÖĞRENCİ İMZASI', nx + 2.5, y0 + 48, 5.6, bold: true, color: _muted);
    box(mid + 1.5, y0 + 44, 186, y0 + 62, radius: 2);
    text('ÖĞRETMEN İMZASI', mid + 4, y0 + 48, 5.6, bold: true, color: _muted);
  }

  // ---- Alt bilgi ----
  text('Sınav kodu: ${exam.id}', 24, 271.5, 5.6, color: _muted);
  text('Formu %100 ölçekle yazdırın; fotokopiyle çoğaltabilirsiniz.', 186, 271.5, 5.6, right: true, color: _muted);
}

void _bubble(PdfGraphics g, double cx, double cy, double r, String label, (PdfFont, PdfFont) fonts) {
  g.setStrokeColor(PdfColors.grey600);
  g.setLineWidth(0.7);
  g.drawEllipse(cx, cy, r, r);
  g.strokePath();
  // Harf açık gri basılır; okuma motoru bunu "boş" sayar.
  g.setFillColor(PdfColors.grey400);
  final w = fonts.$1.stringMetrics(label).width * 5.5;
  g.drawString(fonts.$1, 5.5, label, cx - w / 2, cy - 1.9);
}

String _f1(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
String _f2(double v) => v.toStringAsFixed(2).replaceAll('.', ',');
String _pct(double v) => '%${(v * 100).round()}';
String _letter(int i) => String.fromCharCode(65 + i);
/// Rapor zaman damgası: 18.11.2026 10:04
String reportStamp(DateTime d) =>
    '${_date(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
String _answer(Answer a) => a.marked.isEmpty ? '–' : a.marked.map(_letter).join('/');

/// Rapor sayfalarının ortak üst/alt bilgisi ve yardımcı parçaları.
class _Kit {
  final Exam exam;
  final SchoolInfo school;

  /// Sağ üstteki bilgi (verilmezse sınav adı, şube ve tarih).
  final String? headerInfo;

  /// Resmi başlıktaki belge adı ("Sınav Analiz Raporu").
  final String docTitle;

  /// Resmi başlıktaki sınıf ifadesi (verilmezse "9-A SINIFI").
  final String? classLine;

  /// Resmi başlık her sayfada mı (karneler), yalnız ilk sayfada mı?
  final bool letterheadEveryPage;

  /// Raporun oluşturulduğu an (cihaz saatiyle).
  final DateTime createdAt = DateTime.now();
  _Kit(this.exam, this.school,
      {this.headerInfo, this.docTitle = 'Rapor', this.classLine, this.letterheadEveryPage = false});

  String get institution => school.name.trim();

  /// Resmi yazı başlığı: T.C. / Kaymakamlık / Okul Müdürlüğü / belge adı.
  pw.Widget letterhead() {
    const bold = pw.TextStyle(fontSize: 10.5, color: PdfColors.black);
    final subject = school.subject.trim().isEmpty ? '' : ' ${SchoolInfo.upper(school.subject.trim())} DERSİ';
    final cls = classLine ?? '${SchoolInfo.upper(exam.className)} SINIFI';
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 14),
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8))),
      child: pw.Column(children: [
        pw.Text('T.C.', style: bold.copyWith(fontWeight: pw.FontWeight.bold)),
        if (school.authority.isNotEmpty)
          pw.Text(school.authority, style: bold.copyWith(fontWeight: pw.FontWeight.bold)),
        pw.Text(school.directorate, style: bold.copyWith(fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
        pw.SizedBox(height: 8),
        pw.Text(
          '${SchoolInfo.academicYear(exam.date)} EĞİTİM-ÖĞRETİM YILI $cls$subject',
          style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.black),
          textAlign: pw.TextAlign.center,
        ),
        pw.Text(SchoolInfo.upper(docTitle),
            style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: PdfColors.black)),
        pw.SizedBox(height: 6),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(headerInfo ?? 'Sınav: ${exam.name} · ${_date(exam.date)}',
              style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.black)),
          pw.Text('Tarih: ${_date(createdAt)}', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.black)),
        ]),
      ]),
    );
  }

  /// Resmi raporun sonundaki imza alanı: ders öğretmeni ve okul müdürü onayı.
  pw.Widget signatures() {
    if (!school.official) return pw.SizedBox();
    pw.Widget sig(String role, String name, {String? top}) => pw.SizedBox(
          width: 170,
          child: pw.Column(children: [
            if (top != null) pw.Text(top, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
            pw.SizedBox(height: 30),
            pw.Text(name.trim().isEmpty ? '..............................' : name.trim(),
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5)),
            pw.Text(role, style: const pw.TextStyle(fontSize: 8.5)),
          ]),
        );
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 30),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          sig(school.subject.trim().isEmpty ? 'Ders Öğretmeni' : '${school.subject.trim()} Öğretmeni', school.teacher),
          sig('Okul Müdürü', school.principal, top: 'UYGUNDUR\n${_date(createdAt)}'),
        ],
      ),
    );
  }

  String get created => reportStamp(createdAt);

  pw.Widget header(pw.Context ctx) =>
      school.official && (letterheadEveryPage || ctx.pageNumber == 1) ? letterhead() : _plainHeader(ctx);

  pw.Widget _plainHeader(pw.Context ctx) => pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 14),
    padding: const pw.EdgeInsets.only(bottom: 8),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _line)),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Row(
          children: [
            pw.Container(
              width: 10,
              height: 10,
              decoration: const pw.BoxDecoration(color: _emerald, shape: pw.BoxShape.circle),
            ),
            pw.SizedBox(width: 6),
            pw.Text(
              institution.isEmpty ? 'Netice' : institution,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _ink),
            ),
          ],
        ),
        pw.Text(
          headerInfo ?? '${exam.name} · ${exam.className} · Sınav: ${_date(exam.date)}',
          style: const pw.TextStyle(color: _muted, fontSize: 9),
        ),
      ],
    ),
  );

  pw.Widget footer(pw.Context ctx) => pw.Column(children: [
    pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text('Netice ile hazırlandı', style: const pw.TextStyle(color: _emerald, fontSize: 8)),
        pw.Text('Rapor tarihi: $created', style: const pw.TextStyle(color: _muted, fontSize: 8)),
        pw.Text('Sayfa ${ctx.pageNumber} / ${ctx.pagesCount}', style: const pw.TextStyle(color: _muted, fontSize: 8)),
      ],
    ),
    downloadNote(),
  ]);

  pw.Widget title(String t, [String? sub]) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 6, bottom: 8),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          t,
          style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: _ink),
        ),
        if (sub != null) pw.Text(sub, style: const pw.TextStyle(color: _muted, fontSize: 8)),
      ],
    ),
  );

  pw.Widget statBox(String label, String value, {String? hint, PdfColor color = _ink}) => pw.Container(
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _line),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: const pw.TextStyle(color: _muted, fontSize: 7.5)),
        pw.SizedBox(height: 2),
        pw.Text(
          value,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13, color: color),
        ),
        if (hint != null) pw.Text(hint, style: const pw.TextStyle(color: _muted, fontSize: 6.5)),
      ],
    ),
  );

  pw.Widget grid(List<pw.Widget> boxes, {int columns = 4}) => pw.Column(
    children: [
      for (var i = 0; i < boxes.length; i += columns)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (var j = i; j < i + columns; j++)
                pw.Expanded(
                  child: pw.Padding(
                    padding: pw.EdgeInsets.only(right: j == i + columns - 1 ? 0 : 6),
                    child: j < boxes.length ? boxes[j] : pw.SizedBox(),
                  ),
                ),
            ],
          ),
        ),
    ],
  );

  /// Dikey çubuk grafik.
  pw.Widget barChart(
    List<double> values,
    List<String> labels, {
    double height = 90,
    double? maxValue,
    List<PdfColor>? colors,
    String Function(double)? valueText,
  }) => pw.SizedBox(
    height: height + 26,
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < values.length; i++)
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 1.5),
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Text(
                    valueText?.call(values[i]) ?? _f1(values[i]),
                    style: const pw.TextStyle(fontSize: 6, color: _muted),
                  ),
                  pw.SizedBox(height: 1),
                  pw.Container(
                    height: math.max(
                      1,
                      height * values[i] / math.max(1e-9, maxValue ?? values.fold<double>(0, math.max)),
                    ),
                    decoration: pw.BoxDecoration(
                      color: colors?[i] ?? _ink,
                      borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(2)),
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(labels[i], style: const pw.TextStyle(fontSize: 6, color: _muted)),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  /// Yatay ilerleme çubuğu (0..1).
  pw.Widget hbar(double v, PdfColor color, {double height = 7}) => pw.Container(
    height: height,
    decoration: pw.BoxDecoration(color: _ivory, borderRadius: pw.BorderRadius.circular(height / 2)),
    child: pw.Row(
      children: [
        if (v > 0)
          pw.Expanded(
            flex: (v.clamp(0, 1) * 1000).round(),
            child: pw.Container(
              decoration: pw.BoxDecoration(color: color, borderRadius: pw.BorderRadius.circular(height / 2)),
            ),
          ),
        if (v < 1) pw.Expanded(flex: ((1 - v.clamp(0, 1)) * 1000).round(), child: pw.SizedBox()),
      ],
    ),
  );

  pw.Widget table(
    List<String> headers,
    List<List<String>> data, {
    Map<int, pw.TableColumnWidth>? widths,
    int? leftColumn,
    double fontSize = 8.5,
  }) => pw.TableHelper.fromTextArray(
    headers: headers,
    data: data,
    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: fontSize),
    headerDecoration: const pw.BoxDecoration(color: _ink),
    cellStyle: pw.TextStyle(fontSize: fontSize),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    oddRowDecoration: const pw.BoxDecoration(color: _ivory),
    border: null,
    cellAlignments: {
      for (var i = 0; i < headers.length; i++) i: i == leftColumn ? pw.Alignment.centerLeft : pw.Alignment.center,
    },
    columnWidths: widths,
  );
}

PdfColor _pColor(double p) => p > 0.80
    ? _emerald
    : p >= 0.30
    ? _ink
    : _coral;

/// Kapsamlı sınıf raporu: özet, grafikler, otomatik yorumlar, başarı
/// düzeyleri, kazanım analizi, sonuç listesi ve madde analizi.
Future<Uint8List> buildResultsPdf({
  required Exam exam,
  required List<Result> results,
  required Map<String, Student> students,
  SchoolInfo school = const SchoolInfo(),
}) async {
  final fonts = await _Fonts.load();
  final r = ExamReport.build(exam, results);
  final s = r.stats;
  final k = _Kit(exam, school, docTitle: 'Sınav Analiz Raporu');
  final max = exam.rule.maxScore;
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
    title: '${exam.name} sınav raporu',
    author: 'Netice',
  );

  final rule = exam.rule.wrongsPerCorrect > 0
      ? '${exam.rule.wrongsPerCorrect} yanlış 1 doğruyu götürür'
      : 'Yanlış götürmez';
  final cancelled = exam.questions.where((q) => q.cancelled).map((q) => q.no).toList();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 30),
      header: k.header,
      footer: k.footer,
      build: (ctx) => [
        // Kapak bandı.
        pw.Container(
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(color: _ink, borderRadius: pw.BorderRadius.circular(10)),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'SINAV RAPORU',
                      style: pw.TextStyle(
                        color: _emerald,
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      exam.name,
                      style: pw.TextStyle(color: PdfColors.white, fontSize: 18, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      '${exam.className} · ${_date(exam.date)} · ${exam.questionCount} soru · ${exam.choiceCount} şık · $rule'
                      '${cancelled.isEmpty ? '' : ' · İptal: ${cancelled.join(', ')}'}',
                      style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 8),
                    ),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    _f1(s.mean),
                    style: pw.TextStyle(color: PdfColors.white, fontSize: 28, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text(
                    'sınıf ortalaması / ${max.round()}',
                    style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 8),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Rapor tarihi: ${k.created}',
                    style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 7.5),
                  ),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        k.title('Genel istatistikler'),
        k.grid([
          k.statBox('Katılım', '${s.count}', hint: 'okunan kâğıt'),
          k.statBox('Ortalama', _f1(s.mean), hint: 'Medyan ${_f1(s.median)}'),
          k.statBox('Standart sapma', _f1(s.stdDev), hint: r.cv == null ? null : 'Değişim katsayısı %${r.cv!.round()}'),
          k.statBox('Başarı oranı', _pct(r.passRate), hint: '${exam.rule.pass.round()} ve üzeri alanlar', color: _emerald),
          k.statBox('En yüksek', _f1(s.max), color: _emerald),
          k.statBox('En düşük', _f1(s.min), color: _coral),
          k.statBox('Açıklık', _f1(r.range), hint: 'en yüksek − en düşük'),
          k.statBox('Çeyrekler', '${_f1(r.q1)} – ${_f1(r.q3)}', hint: 'öğrencilerin ortadaki yarısı'),
          k.statBox('Ortalama net', _f2(r.meanNet), hint: '${r.activeQuestionCount} soru üzerinden'),
          k.statBox('Ort. D / Y / B', '${_f1(r.meanCorrect)} / ${_f1(r.meanWrong)} / ${_f1(r.meanBlank)}'),
          k.statBox(
            'KR-20 güvenirlik',
            s.kr20 == null ? '–' : _f2(s.kr20!),
            hint: s.kr20 == null
                ? 'hesaplanamadı'
                : s.kr20! >= 0.7
                ? 'kabul edilebilir'
                : 'düşük',
          ),
          k.statBox('Ölçme hatası (SEM)', r.sem == null ? '–' : '±${_f1(r.sem!)}', hint: 'puan cinsinden'),
          k.statBox('Ortalama güçlük', _f2(r.meanP), hint: 'p: doğru oranı'),
          k.statBox('Ort. ayırt edicilik', _f2(r.meanD), hint: 'D: üst − alt grup'),
          k.statBox('Üst %27 ortalaması', _f1(r.upperMean), color: _emerald),
          k.statBox('Alt %27 ortalaması', _f1(r.lowerMean), color: _coral),
        ]),
        k.title('Grafik özeti'),
        () {
          final c = results.fold<int>(0, (a, x) => a + x.correct);
          final w = results.fold<int>(0, (a, x) => a + x.wrong);
          final b = results.fold<int>(0, (a, x) => a + x.blank);
          final passed = results.where((x) => x.score >= exam.rule.pass).length;
          return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(
                child: _pieBox('Başarı düzeyleri', [
              for (var i = 0; i < Level.all.length; i++) (Level.all[i].name, r.levelCounts[i].toDouble(), _levelColors[i]),
            ])),
            pw.SizedBox(width: 6),
            pw.Expanded(
                child: _pieBox('Cevaplar', [
              ('Doğru', c.toDouble(), _emerald),
              ('Yanlış', w.toDouble(), _coral),
              ('Boş', b.toDouble(), _gray),
            ], donut: true)),
            pw.SizedBox(width: 6),
            pw.Expanded(
                child: _pieBox('Geçme durumu', [
              ('Geçti', passed.toDouble(), _emerald),
              ('Geçemedi', (results.length - passed).toDouble(), _coral),
            ], donut: true)),
            pw.SizedBox(width: 6),
            pw.Expanded(
                child: _pieBox('Soru güçlüğü', [
              ('Kolay', (r.difficultyCounts['Kolay'] ?? 0).toDouble(), _emerald),
              ('Orta', (r.difficultyCounts['Orta'] ?? 0).toDouble(), _ink),
              ('Zor', (r.difficultyCounts['Zor'] ?? 0).toDouble(), _coral),
            ], donut: true)),
          ]);
        }(),
        k.title('Otomatik değerlendirme'),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(color: _ivory, borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (final c in r.comments)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 3),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        margin: const pw.EdgeInsets.only(top: 3, right: 6),
                        width: 4,
                        height: 4,
                        decoration: const pw.BoxDecoration(color: _emerald, shape: pw.BoxShape.circle),
                      ),
                      pw.Expanded(child: pw.Text(c, style: const pw.TextStyle(fontSize: 8.5))),
                    ],
                  ),
                ),
            ],
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 3,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  k.title('Puan dağılımı', 'Tam puana göre yüzdelik dilimlerde öğrenci sayısı'),
                  k.barChart(
                    r.histogram10.map((e) => e.toDouble()).toList(),
                    [for (var i = 0; i < 10; i++) '${i * 10}'],
                    colors: [for (var i = 0; i < 10; i++) i >= 5 ? _emerald : _ink],
                    valueText: (v) => '${v.round()}',
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 16),
            pw.Expanded(
              flex: 2,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  k.title('Başarı düzeyleri'),
                  for (var i = 0; i < Level.all.length; i++)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 5),
                      child: pw.Row(
                        children: [
                          pw.SizedBox(
                            width: 70,
                            child: pw.Text(
                              '${Level.all[i].name} (${Level.all[i].minPct.round()}+)',
                              style: const pw.TextStyle(fontSize: 7.5),
                            ),
                          ),
                          pw.Expanded(child: k.hbar(s.count == 0 ? 0 : r.levelCounts[i] / s.count, _levelColors[i])),
                          pw.SizedBox(
                            width: 24,
                            child: pw.Text(
                              '${r.levelCounts[i]}',
                              textAlign: pw.TextAlign.right,
                              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            k.title(
              'Soru güçlük grafiği',
              'Her sorunun doğru cevaplanma oranı · yeşil: kolay, lacivert: orta, mercan: zor',
            ),
            k.barChart(
              [for (final it in r.items) exam.questions[it.no - 1].cancelled ? 0 : it.p * 100],
              [for (final it in r.items) '${it.no}'],
              maxValue: 100,
              height: 70,
              colors: [for (final it in r.items) exam.questions[it.no - 1].cancelled ? _gray : _pColor(it.p)],
              valueText: (v) => '${v.round()}',
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  k.title('Soru güçlüğü'),
                  k.table(
                    ['Kolay', 'Orta', 'Zor'],
                    [
                      [for (final e in r.difficultyCounts.values) '$e'],
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              flex: 2,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  k.title('Ayırt edicilik'),
                  k.table(
                    [...r.discriminationCounts.keys],
                    [
                      [for (final e in r.discriminationCounts.values) '$e'],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (r.outcomes.isNotEmpty) ...[
          k.title('Kazanım / konu analizi', 'Sınıfın her kazanımdaki doğru oranı'),
          for (final o in [...r.outcomes]..sort((a, b) => a.rate.compareTo(b.rate)))
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 5),
              child: pw.Row(
                children: [
                  pw.SizedBox(
                    width: 150,
                    child: pw.Text(
                      '${o.code}  (${o.questionNos.length} soru)',
                      style: const pw.TextStyle(fontSize: 8),
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                    ),
                  ),
                  pw.Expanded(
                    child: k.hbar(
                      o.rate,
                      o.rate >= 0.7
                          ? _emerald
                          : o.rate >= 0.5
                          ? _amber
                          : _coral,
                    ),
                  ),
                  pw.SizedBox(
                    width: 34,
                    child: pw.Text(
                      _pct(o.rate),
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (r.outcomes.isNotEmpty) ...[
          pw.NewPage(),
          k.title('Kazanım ısı haritası', 'Her öğrencinin her kazanımdaki doğru oranı · yeşil ≥ %70 · sarı %50–69 · mercan < %50'),
          _heatmap(r, students),
        ],
        pw.NewPage(),
        k.title(
          'Sınıf sonuç listesi',
          'Yüzdelik: sınıfın yüzde kaçından daha başarılı · T: ortalaması 50, sapması 10 olan standart puan',
        ),
        k.table(
          ['Sıra', 'Ad Soyad', 'No', 'D', 'Y', 'B', 'Net', if (exam.hasOpen) ...['Test', 'Klasik'], 'Puan', 'Yüzdelik', 'T', 'Düzey'],
          [
            for (final st in r.standings)
              [
                '${st.rank}',
                students[st.result.sheet.studentId]?.fullName ?? 'Eşleşmedi',
                students[st.result.sheet.studentId]?.number ?? '',
                '${st.result.correct}',
                '${st.result.wrong}',
                '${st.result.blank}',
                _f2(st.result.net),
                if (exam.hasOpen) ...[_f1(st.result.testScore), st.result.openMissing ? 'eksik' : _f1(st.result.openScore)],
                _f1(st.result.score),
                '%${st.percentile.round()}',
                _f1(st.t),
                st.level.name,
              ],
          ],
          leftColumn: 1,
          widths: {1: const pw.FlexColumnWidth(4)},
        ),
        pw.NewPage(),
        k.title(
          'Madde analizi',
          'p = doğru oranı (güçlük) · D = ayırt edicilik (üst %27 − alt %27) · Değerler öğretmene yol gösteren uyarılardır.',
        ),
        k.table(
          [
            'Soru',
            'Anahtar',
            if (r.outcomes.isNotEmpty) 'Kazanım',
            'p',
            'D',
            for (var c = 0; c < exam.choiceCount; c++) _letter(c),
            'Boş',
            'Yorum',
          ],
          [
            for (final it in r.items)
              () {
                final q = exam.questions[it.no - 1];
                return [
                  '${it.no}',
                  q.cancelled ? 'İptal' : q.correct.map(_letter).join('/'),
                  if (r.outcomes.isNotEmpty) q.outcomeCode ?? '',
                  _f2(it.p),
                  _f2(it.d),
                  for (var c = 0; c < exam.choiceCount; c++)
                    q.correct.contains(c) ? '${it.choiceCounts[c]}*' : '${it.choiceCounts[c]}',
                  '${it.blankCount}',
                  it.suspiciousChoice != null
                      ? 'Üst grup ${_letter(it.suspiciousChoice!)} seçti; anahtarı kontrol edin'
                      : '${it.difficultyLabel} · ${it.discriminationLabel}'
                          '${it.nonFunctional.isEmpty ? '' : ' · İşlevsiz: ${it.nonFunctional.map(_letter).join('/')}'}',
                ];
              }(),
          ],
          fontSize: 7.5,
          widths: {(r.outcomes.isNotEmpty ? 6 : 5) + exam.choiceCount: const pw.FlexColumnWidth(4.5)},
        ),
        pw.SizedBox(height: 4),
        pw.Text('* doğru şık', style: const pw.TextStyle(color: _muted, fontSize: 7)),
        k.signatures(),
      ],
    ),
  );
  return doc.save();
}

/// Öğrenci karneleri: her öğrenci için sınıfla karşılaştırmalı bir sayfa.
Future<Uint8List> buildStudentCardsPdf({
  required Exam exam,
  required List<Result> results,
  required Map<String, Student> students,
  SchoolInfo school = const SchoolInfo(),

  /// Verilirse yalnızca bu öğrencinin karnesi (istatistikler yine tüm sınıftan).
  String? onlyStudentId,
}) async {
  final fonts = await _Fonts.load();
  final r = ExamReport.build(exam, results);
  final k = _Kit(exam, school, docTitle: 'Öğrenci Sınav Karnesi', letterheadEveryPage: true);
  final max = exam.rule.maxScore;
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
    title: '${exam.name} öğrenci karneleri',
    author: 'Netice',
  );

  pw.Widget compare(String label, double v, PdfColor color) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: pw.Row(
      children: [
        pw.SizedBox(width: 90, child: pw.Text(label, style: const pw.TextStyle(fontSize: 8.5))),
        pw.Expanded(child: k.hbar(max == 0 ? 0 : v / max, color, height: 9)),
        pw.SizedBox(
          width: 36,
          child: pw.Text(
            _f1(v),
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        ),
      ],
    ),
  );

  for (final st in r.standings.where((x) => onlyStudentId == null || x.result.sheet.studentId == onlyStudentId)) {
    final res = st.result;
    final stu = students[res.sheet.studentId];
    final wrongs = [
      for (var i = 0; i < exam.questionCount; i++)
        if (res.outcomes[i] == Outcome.wrong || res.outcomes[i] == Outcome.blank) i,
    ];
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 30),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            k.header(ctx),
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(color: _ink, borderRadius: pw.BorderRadius.circular(10)),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'ÖĞRENCİ KARNESİ',
                          style: pw.TextStyle(
                            color: _emerald,
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          stu?.fullName ?? 'Eşleşmeyen kâğıt',
                          style: pw.TextStyle(color: PdfColors.white, fontSize: 18, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Text(
                          'No ${stu?.number ?? '–'} · ${stu?.className ?? exam.className} · ${exam.name}',
                          style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 8.5),
                        ),
                      ],
                    ),
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        _f1(res.score),
                        style: pw.TextStyle(color: PdfColors.white, fontSize: 30, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(
                        'puan / ${max.round()} · ${st.level.name}',
                        style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 8),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
            k.grid([
              k.statBox('Sınıf sırası', '${st.rank} / ${r.standings.length}'),
              k.statBox('Yüzdelik', '%${st.percentile.round()}', hint: 'sınıfın bu kadarından başarılı'),
              k.statBox('T puanı', _f1(st.t), hint: '50 = sınıf ortalaması'),
              k.statBox('Net', _f2(res.net)),
              k.statBox('Doğru', '${res.correct}', color: _emerald),
              k.statBox('Yanlış', '${res.wrong}', color: _coral),
              k.statBox('Boş', '${res.blank}', color: _gray),
              k.statBox('Başarı', '%${st.pct.round()}'),
              if (exam.hasOpen) ...[
                k.statBox('Test kısmı', '${_f1(res.testScore)} / ${_f1(exam.testMax)}'),
                k.statBox('Klasik kısım', res.openMissing ? 'eksik' : '${_f1(res.openScore)} / ${_f1(exam.openMax)}'),
                for (var i = 0; i < exam.openQuestions.length && i < 2; i++)
                  k.statBox(exam.openQuestions[i].label,
                      i < res.sheet.openScores.length && res.sheet.openScores[i] != null
                          ? '${_f1(res.sheet.openScores[i]!)} / ${_f1(exam.openQuestions[i].maxPoints)}'
                          : '–'),
              ],
            ]),
            k.title('Sınıfla karşılaştırma'),
            compare('Öğrenci', res.score, _emerald),
            compare('Sınıf ortalaması', r.stats.mean, _ink),
            compare('En yüksek puan', r.stats.max, _gray),
            if (r.outcomes.isNotEmpty) ...[
              k.title('Kazanım / konu başarısı', 'Öğrenci (yeşil) ve sınıf (lacivert) doğru oranı'),
              for (final o in r.outcomes)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 5),
                  child: pw.Row(
                    children: [
                      pw.SizedBox(width: 120, child: pw.Text(o.code, style: const pw.TextStyle(fontSize: 8))),
                      pw.Expanded(
                        child: pw.Column(
                          children: [
                            k.hbar(o.rateOf(exam, res), _emerald, height: 6),
                            pw.SizedBox(height: 2),
                            k.hbar(o.rate, _ink, height: 4),
                          ],
                        ),
                      ),
                      pw.SizedBox(
                        width: 60,
                        child: pw.Text(
                          '${_pct(o.rateOf(exam, res))} / ${_pct(o.rate)}',
                          textAlign: pw.TextAlign.right,
                          style: const pw.TextStyle(fontSize: 7.5),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            k.title('Cevaplar', 'Yeşil: doğru · mercan: yanlış · gri: boş/iptal · parantez içinde doğru cevap'),
            pw.Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (var i = 0; i < exam.questionCount; i++)
                  pw.Container(
                    width: 44,
                    padding: const pw.EdgeInsets.symmetric(vertical: 3),
                    decoration: pw.BoxDecoration(
                      color: switch (res.outcomes[i]) {
                        Outcome.correct => const PdfColor.fromInt(0xFFD1FAE5),
                        Outcome.wrong => const PdfColor.fromInt(0xFFFBE0D6),
                        _ => const PdfColor.fromInt(0xFFEEEFF2),
                      },
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text('${i + 1}', style: const pw.TextStyle(fontSize: 6.5, color: _muted)),
                        pw.Text(
                          res.outcomes[i] == Outcome.correct || exam.questions[i].cancelled
                              ? _answer(res.sheet.answers[i])
                              : '${_answer(res.sheet.answers[i])} (${exam.questions[i].correct.map(_letter).join('/')})',
                          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (wrongs.isNotEmpty) ...[
              k.title('Tekrar edilmesi önerilen sorular'),
              pw.Text(
                wrongs
                    .map((i) {
                      final c = exam.questions[i].outcomeCode;
                      return c == null || c.isEmpty ? '${i + 1}' : '${i + 1} ($c)';
                    })
                    .join(', '),
                style: const pw.TextStyle(fontSize: 8.5),
              ),
            ],
            pw.Spacer(),
            k.footer(ctx),
          ],
        ),
      ),
    );
  }
  if (r.standings.isEmpty) {
    doc.addPage(pw.Page(build: (_) => pw.Center(child: pw.Text('Henüz okunan kâğıt yok.'))));
  }
  return doc.save();
}

PdfColor _heatColor(double v) => v >= 0.7
    ? const PdfColor.fromInt(0xFFBFEFDC)
    : v >= 0.5
        ? const PdfColor.fromInt(0xFFFBE7B5)
        : const PdfColor.fromInt(0xFFF9D2C5);

pw.Widget _heatmap(ExamReport r, Map<String, Student> students) {
  final exam = r.exam;
  final codes = r.outcomes;
  pw.Widget cell(String t, {PdfColor? color, bool bold = false, pw.Alignment align = pw.Alignment.center}) =>
      pw.Container(
        alignment: align,
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        color: color,
        child: pw.Text(t,
            maxLines: 2,
            style: pw.TextStyle(fontSize: 7, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      );
  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.white, width: 1.2),
    columnWidths: {0: const pw.FlexColumnWidth(3), for (var i = 1; i <= codes.length; i++) i: const pw.FlexColumnWidth(1.4)},
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _ink),
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.all(3),
            child: pw.Text('Öğrenci', style: pw.TextStyle(color: PdfColors.white, fontSize: 7, fontWeight: pw.FontWeight.bold)),
          ),
          for (final o in codes)
            pw.Container(
              padding: const pw.EdgeInsets.all(3),
              alignment: pw.Alignment.center,
              child: pw.Text(o.code,
                  maxLines: 2,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(color: PdfColors.white, fontSize: 6.5, fontWeight: pw.FontWeight.bold)),
            ),
        ],
      ),
      for (final st in r.standings)
        pw.TableRow(children: [
          cell(students[st.result.sheet.studentId]?.fullName ?? 'Eşleşmedi', align: pw.Alignment.centerLeft),
          for (final o in codes)
            () {
              final v = o.rateOf(exam, st.result);
              return cell('%${(v * 100).round()}', color: _heatColor(v));
            }(),
        ]),
      pw.TableRow(children: [
        cell('Sınıf', bold: true, align: pw.Alignment.centerLeft),
        for (final o in codes) cell('%${(o.rate * 100).round()}', color: _heatColor(o.rate), bold: true),
      ]),
    ],
  );
}

/// Şube karşılaştırma raporu.
Future<Uint8List> buildComparePdf(List<BranchRow> rows, {SchoolInfo school = const SchoolInfo()}) async {
  final fonts = await _Fonts.load();
  final k = _Kit(rows.first.exam, school,
      headerInfo: 'Şube karşılaştırması · ${rows.map((r) => r.exam.className).join(', ')}',
      docTitle: 'Şube Karşılaştırma Raporu',
      classLine: '${rows.map((r) => SchoolInfo.upper(r.exam.className)).toSet().join(', ')} ŞUBELERİ');
  final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold), title: 'Şube karşılaştırması', author: 'Netice');
  final best = rows.reduce((a, b) => a.report.stats.mean >= b.report.stats.mean ? a : b);
  final sameShape = rows.every((r) => r.exam.questionCount == rows.first.exam.questionCount);
  final codes = {for (final r in rows) ...r.report.outcomes.map((o) => o.code)}.toList();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 30),
    header: (ctx) => k.header(ctx),
    footer: k.footer,
    build: (ctx) => [
      k.title('Şube karşılaştırması', rows.map((r) => '${r.exam.name} (${r.exam.className})').join(' · ')),
      k.barChart(
        [for (final r in rows) r.report.stats.mean],
        [for (final r in rows) r.exam.className],
        maxValue: rows.map((r) => r.exam.rule.maxScore).reduce(math.max),
        colors: [for (final r in rows) identical(r, best) ? _emerald : _ink],
        height: 110,
      ),
      pw.SizedBox(height: 8),
      k.table(
        ['Şube', 'Sınav', 'Kişi', 'Ortalama', 'Medyan', 'Std.', 'Başarı', 'En yüksek', 'En düşük', 'KR-20'],
        [
          for (final r in rows)
            [
              r.exam.className,
              r.exam.name,
              '${r.report.stats.count}',
              _f1(r.report.stats.mean),
              _f1(r.report.stats.median),
              _f1(r.report.stats.stdDev),
              _pct(r.report.passRate),
              _f1(r.report.stats.max),
              _f1(r.report.stats.min),
              r.report.stats.kr20 == null ? '–' : _f2(r.report.stats.kr20!),
            ]
        ],
        leftColumn: 1,
        widths: {1: const pw.FlexColumnWidth(3)},
      ),
      if (codes.isNotEmpty) ...[
        k.title('Kazanım başarısı (%)'),
        k.table(
          ['Kazanım', for (final r in rows) r.exam.className],
          [
            for (final c in codes)
              [
                c,
                for (final r in rows)
                  () {
                    final o = r.report.outcomes.where((o) => o.code == c).firstOrNull;
                    return o == null ? '–' : _pct(o.rate);
                  }()
              ]
          ],
          leftColumn: 0,
          widths: {0: const pw.FlexColumnWidth(3)},
        ),
      ],
      if (sameShape) ...[
        k.title('Soru bazında doğru oranı (%)'),
        k.table(
          ['Şube', for (var q = 0; q < rows.first.exam.questionCount; q++) '${q + 1}'],
          [
            for (final r in rows) [r.exam.className, for (final it in r.report.items) '${(it.p * 100).round()}']
          ],
          fontSize: rows.first.exam.questionCount > 25 ? 5.5 : 7,
        ),
      ],
      k.signatures(),
    ],
  ));
  return doc.save();
}

/// e-Okul'a not girişini kolaylaştıran liste: okul numarasına göre sıralı,
/// tam sayıya yuvarlanmış puan; sınava girmeyenler işaretli.
Future<Uint8List> buildEokulPdf({
  required Exam exam,
  required List<Result> results,
  required List<Student> classStudents,
  SchoolInfo school = const SchoolInfo(),
}) async {
  final fonts = await _Fonts.load();
  final k = _Kit(exam, school, docTitle: 'Not Giriş Listesi');
  final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold), title: '${exam.name} e-Okul listesi', author: 'Netice');
  final rows = eokulRows(exam, results, classStudents);
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 30),
    header: k.header,
    footer: k.footer,
    build: (ctx) => [
      k.title('e-Okul not giriş listesi', 'Okul numarasına göre sıralı · puanlar tam sayıya yuvarlandı · ${exam.rule.maxScore.round()} üzerinden'),
      k.table(
        ['Sıra', 'Okul No', 'Ad Soyad', 'Puan', 'Not'],
        [
          for (var i = 0; i < rows.length; i++)
            [
              '${i + 1}',
              rows[i].$1.number,
              rows[i].$1.fullName,
              rows[i].$2 == null ? 'G' : '${rows[i].$2}',
              rows[i].$2 == null ? 'Sınava girmedi' : '',
            ]
        ],
        leftColumn: 2,
        widths: {2: const pw.FlexColumnWidth(4), 4: const pw.FlexColumnWidth(2)},
        fontSize: 10,
      ),
      k.signatures(),
    ],
  ));
  return doc.save();
}

/// (öğrenci, yuvarlanmış puan veya girmediyse null), okul numarasına göre.
List<(Student, int?)> eokulRows(Exam exam, List<Result> results, List<Student> classStudents) {
  final byId = {for (final r in results) r.sheet.studentId: r};
  final list = [for (final s in classStudents) (s, byId[s.id]?.score.round())];
  list.sort((a, b) => (int.tryParse(a.$1.number) ?? 0).compareTo(int.tryParse(b.$1.number) ?? 0));
  return list;
}

/// Kâğıda yapıştırılan sonuç etiketleri: A4, 3 × 8 = 24 etiket (70 × 37 mm).
Future<Uint8List> buildLabelsPdf({
  required Exam exam,
  required List<Result> results,
  required Map<String, Student> students,
}) async {
  final fonts = await _Fonts.load();
  final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold), title: '${exam.name} sonuç etiketleri', author: 'Netice');
  final sorted = [...results]..sort((a, b) => (students[a.sheet.studentId]?.fullName ?? '~')
      .compareTo(students[b.sheet.studentId]?.fullName ?? '~'));
  const perPage = 24;
  const mm = PdfPageFormat.mm;
  for (var p = 0; p < sorted.length; p += perPage) {
    final page = sorted.skip(p).take(perPage).toList();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (ctx) => pw.Column(children: [
        for (var row = 0; row < (page.length / 3).ceil(); row++)
          pw.Row(children: [
            for (final r in page.skip(row * 3).take(3))
          () {
            final st = students[r.sheet.studentId];
            return pw.Container(
              width: 69.9 * mm,
              height: 37.1 * mm,
              padding: const pw.EdgeInsets.fromLTRB(10, 9, 10, 7),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Row(children: [
                  pw.Expanded(
                    child: pw.Text(st?.fullName ?? 'Eşleşmeyen kâğıt',
                        maxLines: 1, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
                  ),
                  pw.Text(st?.number ?? '', style: const pw.TextStyle(fontSize: 7, color: _muted)),
                ]),
                pw.Text('${exam.name} · ${_date(exam.date)}',
                    maxLines: 1, style: const pw.TextStyle(fontSize: 6.5, color: _muted)),
                pw.Spacer(),
                pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                  pw.Expanded(
                    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                      pw.Text('D ${r.correct}   Y ${r.wrong}   B ${r.blank}', style: const pw.TextStyle(fontSize: 8)),
                      pw.Text('Net ${_f2(r.net)}', style: const pw.TextStyle(fontSize: 8, color: _muted)),
                    ]),
                  ),
                  pw.Text(_f1(r.score), style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: _ink)),
                ]),
              ]),
            );
          }(),
          ]),
      ]),
    ));
  }
  if (sorted.isEmpty) doc.addPage(pw.Page(build: (_) => pw.Center(child: pw.Text('Henüz okunan kâğıt yok.'))));
  return doc.save();
}

/// Küçük pasta/halka grafik kutusu (dilim yüzdeleri açıklamada).
pw.Widget _pieBox(String title, List<(String, double, PdfColor)> data, {bool donut = false}) {
  final total = data.fold<double>(0, (a, d) => a + d.$2);
  final nonZero = data.where((d) => d.$2 > 0).toList();
  return pw.Container(
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(border: pw.Border.all(color: _line), borderRadius: pw.BorderRadius.circular(6)),
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(title, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _ink)),
      pw.SizedBox(height: 6),
      pw.SizedBox(
        height: 78,
        child: total == 0
            ? pw.Center(child: pw.Text('–'))
            : pw.Chart(
                grid: pw.PieGrid(),
                datasets: [
                  for (final d in nonZero)
                    pw.PieDataSet(
                      value: d.$2,
                      color: d.$3,
                      legend: nonZero.length == 1 ? null : '',
                      legendPosition: pw.PieLegendPosition.none,
                      innerRadius: donut ? 22 : 0,
                    ),
                ],
              ),
      ),
      pw.SizedBox(height: 6),
      for (final d in data)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 1.5),
          child: pw.Row(children: [
            pw.Container(width: 6, height: 6, decoration: pw.BoxDecoration(color: d.$3, borderRadius: pw.BorderRadius.circular(1.5))),
            pw.SizedBox(width: 4),
            pw.Expanded(child: pw.Text(d.$1, style: const pw.TextStyle(fontSize: 7))),
            pw.Text('${d.$2.round()} · ${total == 0 ? '%0' : '%${(d.$2 / total * 100).round()}'}',
                style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
          ]),
        ),
    ]),
  );
}

/// Paylaşılan her belgenin altındaki uygulama ve indirme bilgisi.
pw.Widget downloadNote() => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 3),
      child: pw.UrlLink(
        destination: downloadUrl,
        child: pw.RichText(
          textAlign: pw.TextAlign.center,
          text: pw.TextSpan(style: const pw.TextStyle(fontSize: 7, color: _muted), children: [
            pw.TextSpan(text: 'Netice', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _ink)),
            const pw.TextSpan(text: ' · Optik kâğıtları telefonla okutun, sonuç ve karne saniyeler içinde · Ücretsiz indirin: '),
            pw.TextSpan(text: downloadLabel, style: const pw.TextStyle(color: _emerald, decoration: pw.TextDecoration.underline)),
          ]),
        ),
      ),
    );

String _short(String s, [int n = 14]) => s.length <= n ? s : '${s.substring(0, n - 1)}…';

_Kit _termKit(TermReport t, SchoolInfo school, String docTitle, {bool everyPage = false}) => _Kit(
      t.exams.last.exam,
      school,
      docTitle: docTitle,
      headerInfo: '${t.term.label} · ${t.className} · ${t.exams.length} sınav',
      classLine: '${SchoolInfo.upper(t.className)} SINIFI',
      letterheadEveryPage: everyPage,
    );

/// Dönem sonu not çizelgesi: her öğrencinin seçilen sınavlardaki puanı
/// (100 üzerinden), ağırlıklı ortalaması ve e-Okul'a girilecek tam sayı not.
Future<Uint8List> buildTermGradesPdf(TermReport t, {SchoolInfo school = const SchoolInfo()}) async {
  final fonts = await _Fonts.load();
  final k = _termKit(t, school, 'Dönem Sonu Not Çizelgesi');
  final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold), title: 'Dönem not çizelgesi', author: 'Netice');
  final equal = t.exams.every((e) => e.weight == t.exams.first.weight);
  final totalW = t.exams.fold<double>(0, (a, e) => a + e.weight);
  final graded = t.rows.where((r) => r.average != null).toList();
  doc.addPage(pw.MultiPage(
    pageFormat: t.exams.length > 5 ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 30),
    header: k.header,
    footer: k.footer,
    build: (ctx) => [
      k.title('Dönem sonu not çizelgesi',
          '${t.term.label} · puanlar 100 üzerinden · ${equal ? 'sınavlar eşit ağırlıklı' : 'ağırlıklı ortalama'} · '
          'girilmeyen sınav ortalamaya katılmaz'),
      k.grid([
        k.statBox('Öğrenci', '${t.rows.length}', hint: '${graded.length} öğrencinin notu var'),
        k.statBox('Sınav', '${t.exams.length}'),
        k.statBox('Sınıf ortalaması', _f1(t.classAverage), color: _emerald),
        k.statBox('En yüksek', graded.isEmpty ? '–' : '${graded.map((r) => r.grade!).reduce(math.max)}'),
      ]),
      pw.SizedBox(height: 4),
      k.table(
        ['Sınav', 'Tarih', 'Ağırlık', 'Katılım', 'Sınıf ort. (100)'],
        [
          for (final e in t.exams)
            [
              e.exam.name,
              _date(e.exam.date),
              totalW == 0 ? '–' : '%${(e.weight / totalW * 100).round()}',
              '${e.report.results.length}',
              _f1(e.mean100),
            ]
        ],
        leftColumn: 0,
        widths: {0: const pw.FlexColumnWidth(4)},
      ),
      pw.SizedBox(height: 10),
      k.table(
        ['No', 'Ad Soyad', for (var i = 0; i < t.exams.length; i++) '${i + 1}. ${_short(t.exams[i].exam.name, 12)}', 'Ortalama', 'Dönem notu'],
        [
          for (final r in t.rows)
            [
              r.student.number,
              r.student.fullName,
              for (final s in r.scores) s == null ? 'G' : _f1(s),
              r.average == null ? '–' : _f2(r.average!),
              r.grade == null ? 'G' : '${r.grade}',
            ]
        ],
        leftColumn: 1,
        widths: {1: const pw.FlexColumnWidth(3.5)},
        fontSize: t.exams.length > 6 ? 7 : 8.5,
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6),
        child: pw.Text('G: sınava girmedi. Dönem notu, ortalamanın tam sayıya yuvarlanmış hâlidir.',
            style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
      ),
      k.signatures(),
    ],
  ));
  return doc.save();
}

/// Dönem kazanım karnesi: her öğrenciye bir sayfa; dönemdeki sınavları,
/// gelişim grafiği ve kazanım bazında birikimli başarısı.
Future<Uint8List> buildTermCardsPdf(TermReport t, {SchoolInfo school = const SchoolInfo(), String? onlyStudentId}) async {
  final fonts = await _Fonts.load();
  final k = _termKit(t, school, 'Dönem Kazanım Karnesi', everyPage: true);
  final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold), title: 'Dönem kazanım karnesi', author: 'Netice');
  final rows = t.rows.where((r) => r.average != null && (onlyStudentId == null || r.student.id == onlyStudentId)).toList();
  if (rows.isEmpty) {
    doc.addPage(pw.Page(build: (_) => pw.Center(child: pw.Text('Bu dönemde sonucu olan öğrenci yok.'))));
    return doc.save();
  }
  PdfColor tone(double v) => v >= 0.7 ? _emerald : (v >= 0.5 ? _amber : _coral);

  for (final r in rows) {
    final out = r.outcomes.entries.toList()..sort((a, b) => b.value.$1.compareTo(a.value.$1));
    final strong = out.where((e) => e.value.$1 >= 0.7).map((e) => e.key).take(4).toList();
    final weak = out.reversed.where((e) => e.value.$1 < 0.5).map((e) => e.key).take(4).toList();
    final taken = [for (var i = 0; i < t.exams.length; i++) if (r.scores[i] != null) i];
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 30),
      build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        k.header(ctx),
        pw.Container(
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(color: _ink, borderRadius: pw.BorderRadius.circular(10)),
          child: pw.Row(children: [
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('DÖNEM KAZANIM KARNESİ',
                    style: pw.TextStyle(color: _emerald, fontSize: 8, fontWeight: pw.FontWeight.bold, letterSpacing: 1.5)),
                pw.SizedBox(height: 4),
                pw.Text(r.student.fullName,
                    style: pw.TextStyle(color: PdfColors.white, fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.Text('No ${r.student.number} · ${r.student.className} · ${t.term.label}',
                    style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 9)),
              ]),
            ),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('${r.grade}', style: pw.TextStyle(color: PdfColors.white, fontSize: 30, fontWeight: pw.FontWeight.bold)),
              pw.Text('dönem ortalaması · sınıf ${_f1(t.classAverage)}',
                  style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 8)),
            ]),
          ]),
        ),
        pw.SizedBox(height: 12),
        k.title('Sınavlar', '${r.taken} / ${t.exams.length} sınava katıldı · puanlar 100 üzerinden'),
        k.table(
          ['Sınav', 'Tarih', 'Puan', 'Sınıf ort.', 'Fark'],
          [
            for (var i = 0; i < t.exams.length; i++)
              [
                t.exams[i].exam.name,
                _date(t.exams[i].exam.date),
                r.scores[i] == null ? 'Girmedi' : _f1(r.scores[i]!),
                _f1(t.exams[i].mean100),
                r.scores[i] == null
                    ? '–'
                    : '${r.scores[i]! >= t.exams[i].mean100 ? '+' : ''}${_f1(r.scores[i]! - t.exams[i].mean100)}',
              ]
          ],
          leftColumn: 0,
          widths: {0: const pw.FlexColumnWidth(4)},
        ),
        if (taken.length >= 2) ...[
          k.title('Gelişim'),
          k.barChart(
            [for (final i in taken) r.scores[i]!],
            [for (final i in taken) _date(t.exams[i].exam.date)],
            maxValue: 100,
            height: 70,
            colors: [for (final i in taken) r.scores[i]! >= t.exams[i].mean100 ? _emerald : _ink],
          ),
        ],
        if (out.isNotEmpty) ...[
          k.title('Kazanımlar', 'Dönem boyunca bu kazanıma ait sorulardaki doğru oranı · çizgi: öğrenci, sağdaki: sınıf'),
          for (final e in out.take(14))
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Row(children: [
                pw.SizedBox(width: 150, child: pw.Text(_short(e.key, 34), style: const pw.TextStyle(fontSize: 8))),
                pw.Expanded(child: k.hbar(e.value.$1, tone(e.value.$1), height: 8)),
                pw.SizedBox(
                    width: 34,
                    child: pw.Text(_pct(e.value.$1),
                        textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold))),
                pw.SizedBox(
                    width: 44,
                    child: pw.Text('sınıf ${_pct(e.value.$2)}',
                        textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 7, color: _muted))),
              ]),
            ),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(color: _ivory, borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Güçlü yönler: ${strong.isEmpty ? 'Henüz belirgin değil.' : strong.join(', ')}',
                  style: const pw.TextStyle(fontSize: 8.5)),
              pw.SizedBox(height: 3),
              pw.Text('Çalışılması önerilen: ${weak.isEmpty ? 'Belirgin bir eksik görünmüyor.' : weak.join(', ')}',
                  style: const pw.TextStyle(fontSize: 8.5)),
            ]),
          ),
        ] else
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 10),
            child: pw.Text('Sınavlarda kazanım kodu girilmediği için kazanım analizi yapılamadı.',
                style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
          ),
        pw.Spacer(),
        k.signatures(),
        pw.SizedBox(height: 6),
        k.footer(ctx),
      ]),
    ));
  }
  return doc.save();
}
