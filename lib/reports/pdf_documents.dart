import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/analysis.dart';
import '../core/models.dart';
import '../core/scoring.dart';
import '../omr/form_layout.dart';

const _ink = PdfColor.fromInt(0xFF0F1B3D);
const _emerald = PdfColor.fromInt(0xFF10B981);
const _muted = PdfColor.fromInt(0xFF6B7280);

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

/// Basılı optik formlar. Her öğrenci için adı yazılı bir sayfa üretir;
/// [students] boşsa tek bir genel form üretir.
Future<Uint8List> buildFormsPdf(Exam exam, List<Student> students) async {
  final fonts = await _Fonts.load();
  final layout = FormLayout(questionCount: exam.questionCount, choiceCount: exam.choiceCount);
  final doc = pw.Document(title: '${exam.name} · optik form', author: 'Netice');
  final pages = students.isEmpty ? <Student?>[null] : students.cast<Student?>();
  for (final s in pages) {
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (ctx) => pw.CustomPaint(
        size: PdfPoint(PdfPageFormat.a4.width, PdfPageFormat.a4.height),
        painter: (canvas, size) => _paintForm(
            canvas, size, layout, exam, s, (fonts.regular.getFont(ctx), fonts.bold.getFont(ctx))),
      ),
    ));
  }
  return doc.save();
}

void _paintForm(PdfGraphics g, PdfPoint size, FormLayout layout, Exam exam, Student? s, (PdfFont, PdfFont) fonts) {
  const mm = PdfPageFormat.mm;
  // PDF koordinatları sol alttan başlar; form mm koordinatları sol üstten.
  double x(double v) => v * mm;
  double y(double v) => size.y - v * mm;

  g.setFillColor(PdfColors.black);
  for (final o in FormLayout.markerOrigins) {
    g.drawRect(x(o.x), y(o.y + FormLayout.markerSize), FormLayout.markerSize * mm, FormLayout.markerSize * mm);
  }
  g.fillPath();

  void text(String t, double px, double py, double sizePt, {bool bold = false, PdfColor color = _ink}) {
    g.setFillColor(color);
    g.drawString(bold ? fonts.$2 : fonts.$1, sizePt, t, x(px), y(py));
  }

  text('Netice', 26, 17, 14, bold: true);
  text('Kâğıttan sonuca, saniyeler içinde.', 26, 22, 7, color: _muted);
  text(exam.name, 26, 33, 13, bold: true);
  text('${exam.className} · ${exam.questionCount} soru · ${exam.choiceCount} şık', 26, 39, 9, color: _muted);

  text('Ad Soyad', 26, 52, 8, color: _muted);
  g.setStrokeColor(PdfColors.grey500);
  g.setLineWidth(0.6);
  g.drawLine(x(26), y(62), x(120), y(62));
  g.strokePath();
  if (s != null) text(s.fullName, 27, 60, 12, bold: true);
  text('Sınıf / şube', 26, 70, 8, color: _muted);
  g.drawLine(x(26), y(80), x(120), y(80));
  g.strokePath();
  if (s != null) text(s.className, 27, 78, 12);

  text('Doldurma: dairenin içini kurşun ya da tükenmez kalemle tamamen karartın.', 26, 92, 7, color: _muted);
  text('Değiştirmek için önceki işareti iyice silin. Köşedeki siyah karelere dokunmayın.', 26, 96, 7, color: _muted);

  // Öğrenci numarası.
  text('Öğrenci no', FormLayout.studentOrigin.x - 3, 30, 8, color: _muted);
  final number = s?.number.padLeft(FormLayout.studentDigits, '0');
  final r = FormLayout.bubbleRadius * mm;
  for (var d = 0; d < FormLayout.studentDigits; d++) {
    final top = layout.studentBubble(d, 0);
    if (number != null && number.length == FormLayout.studentDigits) {
      text(number[d], top.x - 1.1, top.y - 4.2, 9, bold: true);
    }
    for (var v = 0; v < 10; v++) {
      final b = layout.studentBubble(d, v);
      _bubble(g, x(b.x), y(b.y), r, '$v', fonts);
    }
  }

  // Cevaplar.
  for (var q = 0; q < layout.questionCount; q++) {
    final l = layout.questionLabel(q);
    text('${q + 1}'.padLeft(3), l.x - 3, l.y + 1.2, 8, bold: true);
    for (var c = 0; c < layout.choiceCount; c++) {
      final b = layout.answerBubble(q, c);
      _bubble(g, x(b.x), y(b.y), r, String.fromCharCode(65 + c), fonts);
    }
  }
  text('Netice · ${exam.id}', 26, 285, 6, color: _muted);
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

/// Sınıf sonuç listesi ve madde analizi raporu.
Future<Uint8List> buildResultsPdf({
  required Exam exam,
  required List<Result> results,
  required Map<String, Student> students,
  String institution = '',
}) async {
  final fonts = await _Fonts.load();
  final stats = Analysis.examStats(exam, results);
  final items = Analysis.itemStats(exam, results);
  final sorted = [...results]..sort((a, b) => b.score.compareTo(a.score));
  String f1(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
  String f2(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

  final theme = pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold);
  final doc = pw.Document(theme: theme, title: '${exam.name} sonuçları', author: 'Netice');
  final date = '${exam.date.day.toString().padLeft(2, '0')}.${exam.date.month.toString().padLeft(2, '0')}.${exam.date.year}';

  pw.Widget header(pw.Context ctx) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300))),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(institution.isEmpty ? 'Netice' : institution,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _ink)),
          pw.Text('${exam.name} · ${exam.className} · $date', style: const pw.TextStyle(color: _muted, fontSize: 9)),
        ]),
      );
  pw.Widget footer(pw.Context ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Sayfa ${ctx.pageNumber} / ${ctx.pagesCount}', style: const pw.TextStyle(color: _muted, fontSize: 8)),
      );

  pw.Widget statBox(String label, String value) => pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.only(right: 6),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300), borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(label, style: const pw.TextStyle(color: _muted, fontSize: 8)),
            pw.SizedBox(height: 2),
            pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14, color: _ink)),
          ]),
        ),
      );

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    header: header,
    footer: footer,
    build: (ctx) => [
      pw.Text('Sınıf sonuç listesi', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _ink)),
      pw.SizedBox(height: 10),
      pw.Row(children: [
        statBox('Katılım', '${stats.count}'),
        statBox('Ortalama', f1(stats.mean)),
        statBox('Medyan', f1(stats.median)),
        statBox('Std. sapma', f1(stats.stdDev)),
        statBox('KR-20', stats.kr20 == null ? '–' : f2(stats.kr20!)),
      ]),
      pw.SizedBox(height: 14),
      pw.TableHelper.fromTextArray(
        headers: ['Sıra', 'Ad Soyad', 'No', 'D', 'Y', 'B', 'Net', 'Puan'],
        data: [
          for (var i = 0; i < sorted.length; i++)
            () {
              final r = sorted[i];
              final st = students[r.sheet.studentId];
              return [
                '${i + 1}',
                st?.fullName ?? 'Eşleşmedi',
                st?.number ?? '',
                '${r.correct}',
                '${r.wrong}',
                '${r.blank}',
                f2(r.net),
                f1(r.score),
              ];
            }()
        ],
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
        headerDecoration: const pw.BoxDecoration(color: _ink),
        cellStyle: const pw.TextStyle(fontSize: 9),
        oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF6F3EC)),
        cellAlignments: {for (var i = 0; i < 8; i++) i: i == 1 ? pw.Alignment.centerLeft : pw.Alignment.center},
        columnWidths: {1: const pw.FlexColumnWidth(4)},
      ),
      pw.NewPage(),
      pw.Text('Madde analizi', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _ink)),
      pw.SizedBox(height: 4),
      pw.Text('p = doğru oranı (güçlük) · D = ayırt edicilik (üst %27 − alt %27). '
          'Değerler öğretmene yol gösteren uyarılardır, kesin hüküm değildir.',
          style: const pw.TextStyle(color: _muted, fontSize: 8)),
      if (results.length < Analysis.reliableGroupSize)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4),
          child: pw.Text('Not: ${results.length} öğrenci ile madde istatistikleri güvenilir değildir.',
              style: const pw.TextStyle(color: PdfColor.fromInt(0xFFB7791F), fontSize: 8)),
        ),
      pw.SizedBox(height: 10),
      pw.TableHelper.fromTextArray(
        headers: [
          'Soru', 'Anahtar', 'p', 'D',
          for (var c = 0; c < exam.choiceCount; c++) String.fromCharCode(65 + c),
          'Boş', 'Uyarı'
        ],
        data: [
          for (final it in items)
            () {
              final q = exam.questions[it.no - 1];
              return [
                '${it.no}',
                q.cancelled ? 'İptal' : q.correct.map((c) => String.fromCharCode(65 + c)).join('/'),
                f2(it.p),
                f2(it.d),
                for (final n in it.choiceCounts) '$n',
                '${it.blankCount}',
                it.suspiciousChoice != null
                    ? 'Üst grup ${String.fromCharCode(65 + it.suspiciousChoice!)} seçti; anahtarı kontrol edin'
                    : '${it.difficultyLabel} · ${it.discriminationLabel}',
              ];
            }()
        ],
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8),
        headerDecoration: const pw.BoxDecoration(color: _ink),
        cellStyle: const pw.TextStyle(fontSize: 8),
        oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF6F3EC)),
        cellAlignment: pw.Alignment.center,
        columnWidths: {exam.choiceCount + 5: const pw.FlexColumnWidth(5)},
      ),
      pw.SizedBox(height: 16),
      pw.Text('Netice ile hazırlandı.', style: const pw.TextStyle(color: _emerald, fontSize: 8)),
    ],
  ));
  return doc.save();
}
