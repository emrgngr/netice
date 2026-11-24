// Konu özetleri ve hap bilgilerden çalışma föyü PDF'i. Sınav analizinde
// zayıf konular için de kullanılır ("Çalışılması gereken konular").

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../bank/bank_models.dart';
import '../core/models.dart';
import '../l10n/l10n.dart';
import 'pdf_documents.dart' show pdfTheme;

const _ink = PdfColor.fromInt(0xFF0F1B3D);
const _emerald = PdfColor.fromInt(0xFF10B981);
const _amber = PdfColor.fromInt(0xFFF59E0B);
const _muted = PdfColor.fromInt(0xFF6B7280);

/// Föydeki bir bölüm: başlık (ör. zayıf konu) ve notları.
class NotesSection {
  final String title;
  final String? subtitle;
  final List<BankNote> notes;
  const NotesSection(this.title, this.notes, {this.subtitle});
}

Future<Uint8List> buildNotesPdf({
  required String title,
  String? subtitle,
  required SchoolInfo school,
  required List<NotesSection> sections,
  required Uint8List? Function(String? id) image,
}) async {
  final theme = await pdfTheme(school.fontFamily);
  final doc = pw.Document(title: title, author: 'Netice', theme: theme);
  final dir = L10n.rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;

  pw.Widget note(BankNote n) {
    final tip = n.kind == NoteKind.tip;
    final color = tip ? _amber : _emerald;
    final imgs = [for (final id in n.imageIds) image(id)].whereType<Uint8List>().toList();
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.fromLTRB(12, 9, 12, 10),
      decoration: pw.BoxDecoration(
        color: tip ? const PdfColor.fromInt(0xFFFFFBEB) : const PdfColor.fromInt(0xFFF0FDF7),
        border: pw.Border(left: pw.BorderSide(color: color, width: 3)),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: pw.BoxDecoration(color: color, borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Text(SchoolInfo.upper(n.kind.label), style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.white)),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(child: pw.Text(n.displayTitle, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _ink))),
        ]),
        if (n.topicLabel.isNotEmpty && n.topicLabel != n.displayTitle)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2),
            child: pw.Text([n.subject, n.grade, n.topicLabel].where((s) => s.trim().isNotEmpty).toSet().join(' · '),
                style: const pw.TextStyle(fontSize: 8, color: _muted)),
          ),
        if (n.body.trim().isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 5),
            child: pw.Text(n.body.trim(), style: const pw.TextStyle(fontSize: 9.5, color: _ink, lineSpacing: 2)),
          ),
        for (final b in imgs)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6),
            child: () {
              final img = pw.MemoryImage(b);
              final w = math.min(480.0, (img.width ?? 600) * 0.55);
              return pw.Image(img, width: w, fit: pw.BoxFit.contain);
            }(),
          ),
      ]),
    );
  }

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 30),
    textDirection: dir,
    header: (c) => c.pageNumber == 1
        ? pw.SizedBox()
        : pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Text(title, style: const pw.TextStyle(fontSize: 8, color: _muted)),
          ),
    footer: (c) => pw.Row(children: [
      pw.Text(school.name.trim(), style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
      pw.Spacer(),
      pw.Text('${c.pageNumber} / ${c.pagesCount}', style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
    ]),
    build: (c) => [
      pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: pw.BoxDecoration(color: _ink, borderRadius: pw.BorderRadius.circular(8)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
          if (subtitle != null && subtitle.trim().isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 3),
              child: pw.Text(subtitle, style: const pw.TextStyle(fontSize: 9.5, color: PdfColor.fromInt(0xFFB8C2DC))),
            ),
        ]),
      ),
      pw.SizedBox(height: 14),
      for (final s in sections) ...[
        if (s.title.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4, bottom: 6),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Expanded(child: pw.Text(s.title, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _ink))),
              if (s.subtitle != null) pw.Text(s.subtitle!, style: const pw.TextStyle(fontSize: 9, color: _muted)),
            ]),
          ),
        if (s.notes.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 10),
            child: pw.Text(tr('Bu konu için henüz not eklenmemiş. Ders kitabındaki ilgili bölümü tekrar edin.'),
                style: const pw.TextStyle(fontSize: 9, color: _muted)),
          ),
        for (final n in s.notes) note(n),
      ],
    ],
  ));
  return doc.save();
}
