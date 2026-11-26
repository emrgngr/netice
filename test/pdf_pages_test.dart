import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/pdf_pages.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<Uint8List> _pdf(int pages, {required bool compress, PdfVersion version = PdfVersion.pdf_1_4}) {
  final doc = pw.Document(compress: compress, version: version);
  for (var i = 0; i < pages; i++) {
    doc.addPage(pw.Page(build: (_) => pw.Center(child: pw.Text('Sayfa ${i + 1}'))));
  }
  return doc.save();
}

void main() {
  test('düz PDF sayfa sayısı', () async {
    expect(pdfPageCount(await _pdf(1, compress: false)), 1);
    expect(pdfPageCount(await _pdf(37, compress: false)), 37);
  });

  test('sıkıştırılmış ve nesne akışlı PDF sayfa sayısı', () async {
    expect(pdfPageCount(await _pdf(12, compress: true)), 12);
    expect(pdfPageCount(await _pdf(25, compress: true, version: PdfVersion.pdf_1_5)), 25);
  });

  test('PDF olmayan dosya', () {
    expect(pdfPageCount(Uint8List.fromList([1, 2, 3, 4, 5, 6])), isNull);
  });
}
