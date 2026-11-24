import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/doc_text.dart';
import 'package:netice/core/import_export.dart';
import 'package:netice/core/spreadsheet.dart';

void main() {
  for (final ext in ['xls', 'ods']) {
    test('$ext: sayfalar, Türkçe harfler, uzun liste', () {
      final bytes = File('test/fixtures/ornek.$ext').readAsBytesSync();
      final sheets = spreadsheetSheets(bytes, 'ornek.$ext')!;
      expect(sheets.map((s) => s.$1), ['9-A', 'Uzun']);
      expect(sheets[0].$2, [
        ['Okul No', 'Adı', 'Soyadı'],
        ['1042', 'Ayşe', 'Yılmaz'],
        ['1043', 'Çağrı', 'Öztürk'],
        ['1044', 'İsmail', 'Şahin'],
      ]);
      final long = sheets[1].$2;
      expect(long.length, 3000);
      for (final i in [0, 1, 817, 1999, 2999]) {
        expect(long[i][0], '$i');
        expect(long[i][1], 'Öğrenci adı numarası $i ğüşiöç');
        expect(long[i][2], i.isOdd ? '12.5' : '7');
      }
      expect(long[0][3], 'Öğrenci adı numarası 0 ğüşiöçx');

      final students = StudentImport.parseSheets(sheets);
      expect(students.where((s) => s.className == '9-A').map((s) => s.lastName), containsAll(['Yılmaz', 'Öztürk', 'Şahin']));
    });
  }

  test('e-Okul gibi HTML tablo (.xls adıyla, Windows-1254)', () {
    const html = '<html><body><table><tr><th>Okul No</th><th>Adı</th><th>Soyadı</th></tr>'
        '<tr><td>15</td><td>Gül&nbsp;</td><td>Ağaoğlu</td></tr><tr><td>16</td><td>Işık</td><td>Şen</td></tr></table></body></html>';
    final enc = Uint8List.fromList([
      for (final c in html.runes) {0x11E: 0xD0, 0x130: 0xDD, 0x15E: 0xDE, 0x11F: 0xF0, 0x131: 0xFD, 0x15F: 0xFE}[c] ?? c,
    ]);
    final s = spreadsheetSheets(enc, 'liste.xls')!;
    expect(s.single.$2, [
      ['Okul No', 'Adı', 'Soyadı'],
      ['15', 'Gül', 'Ağaoğlu'],
      ['16', 'Işık', 'Şen'],
    ]);
  });

  test('Excel 2003 XML', () {
    const x = '<?xml version="1.0"?><Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" '
        'xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet"><Worksheet ss:Name="10-B"><Table>'
        '<Row><Cell><Data ss:Type="String">Okul No</Data></Cell><Cell><Data ss:Type="String">Adı</Data></Cell></Row>'
        '<Row><Cell><Data ss:Type="Number">7.0</Data></Cell><Cell ss:Index="3"><Data ss:Type="String">Ece</Data></Cell></Row>'
        '</Table></Worksheet></Workbook>';
    final s = spreadsheetSheets(Uint8List.fromList(utf8.encode(x)), 'a.xls')!;
    expect(s.single.$1, '10-B');
    expect(s.single.$2[1], ['7', '', 'Ece']);
  });

  test('belge metni: .xls ve .ods ders notu / cevap anahtarı olarak okunur', () {
    for (final ext in ['xls', 'ods']) {
      final t = documentText(File('test/fixtures/ornek.$ext').readAsBytesSync(), 'ornek.$ext');
      expect(t, contains('1043 | Çağrı | Öztürk'));
    }
  });

  test('düz metin tablo sayılmaz', () {
    expect(spreadsheetSheets(Uint8List.fromList(utf8.encode('a;b\n1;2')), 'a.csv'), isNull);
  });
}
