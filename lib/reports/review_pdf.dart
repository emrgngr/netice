// Kişiye özel tekrar testi PDF'i: her öğrenciye kendi eksik konularından
// seçilmiş sorular, konuların hap bilgileri ve en sonda öğretmen için
// cevap anahtarı.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../bank/bank_models.dart';
import '../bank/personal_review.dart';
import '../core/models.dart';
import '../l10n/l10n.dart';
import 'pdf_documents.dart' show pdfTheme;

const _ink = PdfColor.fromInt(0xFF0F1B3D);
const _emerald = PdfColor.fromInt(0xFF10B981);
const _muted = PdfColor.fromInt(0xFF6B7280);
const _soft = PdfColor.fromInt(0xFFF3F4F6);
const _line = PdfColor.fromInt(0xFFCBD0D8);
const _tipBg = PdfColor.fromInt(0xFFFFF7E6);
const _tipLine = PdfColor.fromInt(0xFFF2B33D);

String _letter(int i) => String.fromCharCode(65 + i);

Future<Uint8List> buildPersonalReviewPdf(
  List<StudentReview> reviews, {
  required Exam exam,
  required SchoolInfo school,
  required Uint8List? Function(String? id) image,
  List<BankNote> Function(String topic)? tipsFor,
  bool answerKey = true,
}) async {
  final theme = await pdfTheme(school.fontFamily);
  final doc = pw.Document(title: tr('Kişiye özel tekrar testi'), author: 'Netice', theme: theme);
  final dir = L10n.rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
  const fs = 10.5;
  const margin = pw.EdgeInsets.fromLTRB(36, 32, 36, 30);

  pw.Widget imageBox(String? id, double maxW) {
    final bytes = image(id);
    if (bytes == null) return pw.SizedBox();
    final img = pw.MemoryImage(bytes);
    final iw = (img.width ?? 600).toDouble(), ih = (img.height ?? 400).toDouble();
    var w = math.min(maxW, iw * 0.55);
    var h = w * ih / iw;
    if (h > 300) {
      h = 300;
      w = h * iw / ih;
    }
    return pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3), child: pw.Image(img, width: w, height: h));
  }

  pw.Widget question(int no, BankQuestion q) {
    final choices = q.type == QuestionType.trueFalse ? [tr('Doğru'), tr('Yanlış')] : q.choices;
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 4, bottom: 8),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.4))),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.SizedBox(width: 22, child: pw.Text('$no.', style: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold, color: _ink))),
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            if (q.text.trim().isNotEmpty) pw.Text(q.text.trim(), style: const pw.TextStyle(fontSize: fs, lineSpacing: 2)),
            if (q.imageId != null) imageBox(q.imageId, 440),
            if (q.type.optical && choices.any((c) => c.trim().isNotEmpty))
              for (var i = 0; i < choices.length; i++)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 2),
                  child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.SizedBox(
                        width: 18, child: pw.Text('${_letter(i)})', style: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold))),
                    pw.Expanded(child: pw.Text(choices[i], style: const pw.TextStyle(fontSize: fs))),
                  ]),
                ),
            if (q.type.optical && choices.every((c) => c.trim().isEmpty))
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 3),
                child: pw.Text([for (var i = 0; i < q.optionCount; i++) '${_letter(i)})  ○'].join('      '),
                    style: const pw.TextStyle(fontSize: fs)),
              ),
            if (!q.type.optical)
              for (var i = 0; i < (q.type == QuestionType.fill ? 1 : q.answerLines.clamp(1, 12)); i++)
                pw.Container(
                  height: fs * 1.9,
                  decoration: const pw.BoxDecoration(
                      border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.5, style: pw.BorderStyle.dotted))),
                ),
            if (q.topicLabel.isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 2),
                child: pw.Text(q.topicLabel, style: pw.TextStyle(fontSize: fs - 3, color: _muted, fontStyle: pw.FontStyle.italic)),
              ),
          ]),
        ),
      ]),
    );
  }

  pw.Widget header(StudentReview r) => pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(color: _soft, borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(children: [
            pw.Expanded(
              child: pw.Text(SchoolInfo.upper(tr('Kişiye özel tekrar testi')),
                  style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _ink)),
            ),
            if (school.name.trim().isNotEmpty) pw.Text(school.name.trim(), style: const pw.TextStyle(fontSize: 8, color: _muted)),
          ]),
          pw.SizedBox(height: 4),
          pw.Text(
              [r.student.fullName, r.student.className, if (r.student.number.isNotEmpty) tr('No: {0}', [r.student.number])].join('  ·  '),
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _ink)),
          pw.SizedBox(height: 2),
          pw.Text(tr('"{0}" sınavında yanlış yaptığın ya da boş bıraktığın soruların benzerleri. Acele etme, her soruyu çözümüyle birlikte düşün.', [exam.name]),
              style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
          pw.SizedBox(height: 6),
          pw.Wrap(spacing: 4, runSpacing: 4, children: [
            pw.Text(tr('Çalışacağın konular:'), style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _ink)),
            for (final t in r.topics)
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: _emerald, width: 0.6), borderRadius: pw.BorderRadius.circular(8)),
                child: pw.Text(t, style: const pw.TextStyle(fontSize: 8, color: _ink)),
              ),
          ]),
        ]),
      );

  pw.Widget tips(StudentReview r) {
    if (tipsFor == null) return pw.SizedBox();
    final notes = <BankNote>[];
    for (final t in r.topics) {
      for (final n in tipsFor(t).where((n) => n.kind == NoteKind.tip).take(1)) {
        if (!notes.contains(n)) notes.add(n);
      }
      if (notes.length >= 3) break;
    }
    if (notes.isEmpty) return pw.SizedBox();
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      padding: const pw.EdgeInsets.all(8),
      decoration: const pw.BoxDecoration(color: _tipBg, border: pw.Border(left: pw.BorderSide(color: _tipLine, width: 2.5))),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(tr('Hatırla (hap bilgi)'), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _ink)),
        for (final n in notes)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 3),
            child: pw.Text('• ${n.displayTitle}: ${n.body.trim().replaceAll(RegExp(r'\s+'), ' ')}',
                style: const pw.TextStyle(fontSize: 8.5), maxLines: 4),
          ),
      ]),
    );
  }

  for (final r in reviews) {
    doc.addPage(pw.MultiPage(
      textDirection: dir,
      pageFormat: PdfPageFormat.a4,
      margin: margin,
      footer: (ctx) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 6),
        child: pw.Text('${r.student.fullName} · ${tr('Netice ile hazırlandı')} · ${ctx.pageNumber}',
            style: const pw.TextStyle(fontSize: 7, color: _muted)),
      ),
      build: (ctx) => [
        header(r),
        tips(r),
        pw.SizedBox(height: 8),
        for (var i = 0; i < r.questions.length; i++) question(i + 1, r.questions[i]),
      ],
    ));
  }

  if (answerKey && reviews.isNotEmpty) {
    doc.addPage(pw.MultiPage(
      textDirection: dir,
      pageFormat: PdfPageFormat.a4,
      margin: margin,
      build: (ctx) => [
        pw.Text(SchoolInfo.upper(tr('Öğretmen için cevap anahtarı')),
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _ink)),
        pw.Text(tr('Kişiye özel tekrar testleri · {0}', [exam.name]), style: const pw.TextStyle(fontSize: 9, color: _muted)),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: [tr('Öğrenci'), tr('Cevaplar')],
          headerStyle: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: _ink),
          cellStyle: const pw.TextStyle(fontSize: 8.5),
          columnWidths: {0: const pw.FlexColumnWidth(1.2), 1: const pw.FlexColumnWidth(3)},
          cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerLeft},
          data: [
            for (final r in reviews)
              [
                r.student.fullName,
                [for (var i = 0; i < r.questions.length; i++) '${i + 1}) ${r.questions[i].answerLabel}'].join('   '),
              ],
          ],
        ),
      ],
    ));
  }
  if (doc.document.pdfPageList.pages.isEmpty) doc.addPage(pw.Page(build: (_) => pw.SizedBox()));
  return doc.save();
}
