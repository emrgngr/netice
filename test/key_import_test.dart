import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/doc_text.dart';
import 'package:netice/core/key_import.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

String letters(List<int?> k) => k.map((c) => c == null ? '·' : String.fromCharCode(65 + c)).join();

void main() {
  test('kitapçık başlıklı bölümler ve "1-A" çiftleri', () {
    const text = '''
FİZİK QUIZ 3 CEVAP ANAHTARI
A KİTAPÇIĞI
1-A 2-B 3-C 4-D 5-E
6-A 7-B 8-C 9-D 10-E
B Kitapçığı
1. E 2. D 3. C 4. B 5. A
6) e 7) d 8) c 9) b 10) a
''';
    final r = parseKeyText(text, questions: 10, choices: 5);
    expect(r.bookletCount, 2);
    expect(letters(r.keys[0]!), 'ABCDEABCDE');
    expect(letters(r.keys[1]!), 'EDCBAEDCBA');
  });

  test('tablo: soru | A | B | konu sütunları', () {
    const text = '''
Soru No | A Kitapçığı | B Kitapçığı | Konu
1 | C | A | Hareket
2 | D | B | Hareket
3 | A | C | Kuvvet ve Hareket
4 | B | D | Enerji
''';
    final r = parseKeyText(text, questions: 4, choices: 5);
    expect(letters(r.keys[0]!), 'CDAB');
    expect(letters(r.keys[1]!), 'ABCD');
    expect(r.topics, {1: 'Hareket', 2: 'Hareket', 3: 'Kuvvet ve Hareket', 4: 'Enerji'});
    expect(topicsToRanges(r.topics, 4), '1-2 Hareket\n3 Kuvvet ve Hareket\n4 Enerji');
  });

  test('art arda harfler, konu aralıkları, şık sınırı', () {
    const text = '''
Kitapçık türü: A
ABCDA BCDAB
Kitapçık türü: B
DCBADCBADC
Konular:
1-5 Hareket
6 – 10: Kuvvet
''';
    final r = parseKeyText(text, questions: 10, choices: 4);
    expect(letters(r.keys[0]!), 'ABCDABCDAB');
    expect(letters(r.keys[1]!), 'DCBADCBADC');
    expect(r.topics[1], 'Hareket');
    expect(r.topics[10], 'Kuvvet');
    // 4 şıklı sınavda E yok sayılır.
    expect(letters(parseKeyText('1-E 2-A', questions: 2, choices: 4).keys[0]!), '·A');
  });

  test('satır başına soru, cevap ve kazanım', () {
    const text = '''
1. C  F.9.1.1. Fizik biliminin önemi
2. A  F.9.1.1. Fizik biliminin önemi
3. E  F.9.2.1. Madde ve özkütle
''';
    final r = parseKeyText(text, questions: 3, choices: 5);
    expect(letters(r.keys[0]!), 'CAE');
    expect(r.topics[3], 'F.9.2.1. Madde ve özkütle');
  });

  test('PDF (standart ve gömülü yazı tipi) ve Word belgesinden yazı çıkarma', () async {
    for (final embedded in [false, true]) {
      final doc = pw.Document();
      final font = embedded ? pw.Font.ttf(ByteData.sublistView(File('assets/pdf_fonts/NotoSans-Regular.ttf').readAsBytesSync())) : null;
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(embedded ? 'A KİTAPÇIĞI' : 'A KITAPCIGI', style: pw.TextStyle(font: font)),
          pw.Text('1-A 2-B 3-C 4-D', style: pw.TextStyle(font: font)),
          pw.Text(embedded ? 'B KİTAPÇIĞI' : 'B KITAPCIGI', style: pw.TextStyle(font: font)),
          pw.Text('1-D 2-C 3-B 4-A', style: pw.TextStyle(font: font)),
          pw.Text('1-2 Kuvvet ve Hareket', style: pw.TextStyle(font: font)),
        ]),
      ));
      final bytes = await doc.save();
      final text = documentText(bytes, 'anahtar.pdf');
      final r = parseKeyText(text, questions: 4, choices: 5);
      expect(letters(r.keys[0]!), 'ABCD', reason: 'gömülü: $embedded\n$text');
      expect(letters(r.keys[1]!), 'DCBA', reason: 'gömülü: $embedded\n$text');
      expect(r.topics[2], 'Kuvvet ve Hareket', reason: text);
    }

    const xml = '<?xml version="1.0" encoding="UTF-8"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>'
        '<w:p><w:r><w:t>Cevap Anahtarı</w:t></w:r></w:p>'
        '<w:tbl>'
        '<w:tr><w:tc><w:p><w:r><w:t>Soru</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>A Kitapçığı</w:t></w:r></w:p></w:tc>'
        '<w:tc><w:p><w:r><w:t>B Kitapçığı</w:t></w:r></w:p></w:tc></w:tr>'
        '<w:tr><w:tc><w:p><w:r><w:t>1</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>B</w:t></w:r></w:p></w:tc>'
        '<w:tc><w:p><w:r><w:t>E</w:t></w:r></w:p></w:tc></w:tr>'
        '<w:tr><w:tc><w:p><w:r><w:t>2</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>C</w:t></w:r></w:p></w:tc>'
        '<w:tc><w:p><w:r><w:t>A</w:t></w:r></w:p></w:tc></w:tr>'
        '</w:tbl></w:body></w:document>';
    final arc = Archive()..addFile(ArchiveFile.bytes('word/document.xml', utf8.encode(xml)));
    final docx = Uint8List.fromList(ZipEncoder().encodeBytes(arc));
    final r = parseKeyText(documentText(docx, 'anahtar.docx'), questions: 2, choices: 5);
    expect(letters(r.keys[0]!), 'BC');
    expect(letters(r.keys[1]!), 'EA');
  });

  test('gerçek Word ve LibreOffice PDF belgeleri (tablo ve liste)', () {
    for (final f in ['tablo.docx', 'tablo.pdf', 'liste.pdf']) {
      final r = parseKeyText(documentText(File('test/fixtures/keys/$f').readAsBytesSync(), f), questions: 100, choices: 5);
      expect(letters(r.keys[0]!.take(10).toList()), 'CDABEACDBE', reason: f);
      expect(letters(r.keys[1]!.take(10).toList()), 'EBDCAADBCE', reason: f);
      if (f.startsWith('tablo')) {
        expect(topicsToRanges(r.topics, 10), '1-3 Fizik biliminin önemi\n4-7 Madde ve özellikleri\n8-10 Hareket ve kuvvet', reason: f);
      }
    }
  });

  test('yazı tanıma kutuları satırlara dizilir', () {
    final text = rowsFromBoxes([
      (300, 102, 330, 120, 'E'),
      (10, 100, 40, 120, '1'),
      (150, 101, 180, 121, 'C'),
      (10, 140, 40, 160, '2'),
      (150, 141, 180, 161, 'D'),
      (300, 139, 330, 159, 'B'),
      (10, 60, 120, 80, 'Soru'),
      (150, 60, 260, 80, 'A Kitapçığı'),
      (300, 61, 420, 81, 'B Kitapçığı'),
    ]);
    expect(text, 'Soru | A Kitapçığı | B Kitapçığı\n1 | C | E\n2 | D | B');
    final r = parseKeyText(text, questions: 2, choices: 5);
    expect(letters(r.keys[0]!), 'CD');
    expect(letters(r.keys[1]!), 'EB');
  });
}
