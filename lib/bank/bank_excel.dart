// Soru bankası için Excel (.xlsx, .xls, .ods) ve CSV aktarma, örnek şablon üretme.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../core/import_export.dart';
import '../core/spreadsheet.dart';
import '../l10n/l10n.dart';
import 'bank_models.dart';
import 'bank_store.dart';

/// Excel'den okunanlar.
class BankImportResult {
  final List<BankQuestion> questions;
  final List<BankNote> notes;

  /// Atlanan satırlar: (sayfa, satır no, neden).
  final List<(String, int, String)> skipped;
  const BankImportResult(this.questions, this.notes, this.skipped);

  bool get isEmpty => questions.isEmpty && notes.isEmpty;
}

class BankExcel {
  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('İ', 'i')
      .replaceAll('ş', 's')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Sütun başlığı → alan adı.
  static String? _field(String header) {
    final h = _norm(header);
    if (h.isEmpty) return null;
    const exact = {
      'a': 'A', 'b': 'B', 'c': 'C', 'd': 'D', 'e': 'E',
      'asikki': 'A', 'bsikki': 'B', 'csikki': 'C', 'dsikki': 'D', 'esikki': 'E',
    };
    if (exact.containsKey(h)) return exact[h];
    bool any(List<String> keys) => keys.any(h.startsWith);
    if (any(['dusunme', 'bilissel', 'bloom', 'cognitive', 'denkniveau', 'taksonomi', 'taxonomy'])) return 'cognitive';
    if (any(['ders', 'subject', 'brans', 'fach', 'asignatura', 'predmet', 'materia', 'matiere', 'fenn'])) return 'subject';
    if (any(['sinif', 'duzey', 'seviye', 'grade', 'klasse', 'level', 'nivel', 'classe', 'sinf'])) return 'grade';
    if (any(['konu', 'topic', 'thema', 'tema', 'unite', 'mavzu', 'movzu'])) return 'topic';
    if (any(['kazanim', 'outcome', 'objective', 'hedef', 'lernziel', 'kod'])) return 'outcome';
    if (any(['zorluk', 'difficulty', 'schwierig', 'dificultad', 'cetinlik'])) return 'difficulty';
    if (any(['tur', 'tip', 'type', 'typ'])) return 'type';
    if (any(['cozum', 'aciklama', 'solution', 'explanation', 'losung'])) return 'solution';
    if (any(['cevap', 'dogru', 'answer', 'key', 'anahtar', 'antwort', 'respuesta', 'cavab'])) return 'answer';
    if (any(['etiket', 'tag'])) return 'tags';
    if (any(['kaynak', 'source', 'quelle', 'fuente', 'menbe'])) return 'source';
    if (any(['puan', 'point', 'punkt', 'bal'])) return 'points';
    if (any(['baslik', 'title', 'titel', 'titulo', 'basliq'])) return 'title';
    if (any(['metin', 'ozet', 'not', 'text', 'icerik', 'body', 'aciklama', 'hapbilgi', 'bilgi'])) return 'body';
    if (any(['soru', 'question', 'frage', 'pregunta', 'sual', 'kok'])) return 'text';
    return null;
  }

  static Map<int, String> _headerMap(List<String> row) {
    final m = <int, String>{};
    for (var i = 0; i < row.length; i++) {
      final f = _field(row[i]);
      if (f != null && !m.containsValue(f)) m[i] = f;
    }
    return m;
  }

  static QuestionType _type(String s, {required bool hasChoices}) {
    final t = _norm(s);
    if (t.isEmpty) return hasChoices ? QuestionType.multiple : QuestionType.open;
    if (t.startsWith('dogruyanlis') || t.startsWith('dy') || t.startsWith('truefalse') || t.startsWith('tf') || t.startsWith('richtig')) {
      return QuestionType.trueFalse;
    }
    if (t.startsWith('bosluk') || t.startsWith('fill') || t.startsWith('luck')) return QuestionType.fill;
    if (t.startsWith('klasik') || t.startsWith('acik') || t.startsWith('open') || t.startsWith('yazili') || t.startsWith('offen')) {
      return QuestionType.open;
    }
    return QuestionType.multiple;
  }

  static Set<int> _answer(String s, QuestionType type) {
    final t = s.trim().toUpperCase();
    if (t.isEmpty) return {};
    if (type == QuestionType.trueFalse) {
      final n = _norm(s);
      if (n.startsWith('y') || n.startsWith('f') || n == 'b' || n.startsWith('w') || n == '0') return {1};
      return {0};
    }
    final out = <int>{};
    for (final m in RegExp(r'[A-E]').allMatches(t)) {
      out.add(m.group(0)!.codeUnitAt(0) - 65);
    }
    if (out.isEmpty) {
      final n = int.tryParse(t);
      if (n != null && n >= 1 && n <= 5) out.add(n - 1);
    }
    return out;
  }

  /// Bütün çalışma sayfalarını okur: başlığında "Soru" ya da şık sütunları
  /// olanlar soru, "Başlık / Metin" olanlar not sayılır.
  static BankImportResult parseRows(List<(String, List<List<String>>)> sheets) {
    final qs = <BankQuestion>[];
    final ns = <BankNote>[];
    final skipped = <(String, int, String)>[];
    final now = DateTime.now();
    for (final (name, rows) in sheets) {
      // Başlık satırı ilk 10 satırdan en çok tanınan sütunu olan.
      var hi = -1;
      var best = 0;
      for (var i = 0; i < rows.length && i < 10; i++) {
        final n = _headerMap(rows[i]).length;
        if (n > best) {
          best = n;
          hi = i;
        }
      }
      if (hi < 0 || best < 2) continue;
      final h = _headerMap(rows[hi]);
      final fields = h.values.toSet();
      final isQuestions = fields.contains('text') || fields.contains('A');
      final isNotes = !isQuestions && fields.contains('body');
      if (!isQuestions && !isNotes) continue;
      for (var r = hi + 1; r < rows.length; r++) {
        final row = rows[r];
        String v(String f) {
          final i = h.entries.where((e) => e.value == f).firstOrNull?.key;
          return i == null || i >= row.length ? '' : row[i].trim();
        }

        if (row.every((c) => c.trim().isEmpty)) continue;
        final tags = v('tags').split(RegExp(r'[,;]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        if (isQuestions) {
          final choices = [for (final l in ['A', 'B', 'C', 'D', 'E']) v(l)];
          while (choices.isNotEmpty && choices.last.isEmpty) {
            choices.removeLast();
          }
          final text = v('text');
          if (text.isEmpty) {
            skipped.add((name, r + 1, tr('soru metni boş')));
            continue;
          }
          final type = _type(v('type'), hasChoices: choices.isNotEmpty);
          final correct = type.optical ? _answer(v('answer'), type) : <int>{};
          if (type == QuestionType.multiple && choices.length < 2) {
            skipped.add((name, r + 1, tr('en az iki şık gerekli')));
            continue;
          }
          if (type.optical && correct.isEmpty) {
            skipped.add((name, r + 1, tr('doğru cevap yazılmamış')));
            continue;
          }
          qs.add(BankQuestion(
            id: BankStore.newId('q'),
            subject: v('subject'),
            grade: v('grade'),
            topic: v('topic'),
            outcome: v('outcome'),
            difficulty: Difficulty.parse(v('difficulty')),
            cognitive: CognitiveLevel.parse(v('cognitive')),
            type: type,
            text: text,
            choices: type == QuestionType.multiple ? choices : const [],
            choiceCount: type == QuestionType.trueFalse ? 2 : (choices.length.clamp(2, 5)),
            correct: correct,
            answerText: type.optical ? '' : v('answer'),
            solution: v('solution'),
            tags: tags,
            source: v('source'),
            points: double.tryParse(v('points').replaceAll(',', '.')) ?? 1,
            created: now,
            updated: now,
          ));
        } else {
          final body = v('body');
          final title = v('title');
          if (body.isEmpty && title.isEmpty) continue;
          final kindRaw = _norm(v('type'));
          ns.add(BankNote(
            id: BankStore.newId('n'),
            kind: kindRaw.startsWith('hap') || kindRaw.startsWith('tip') || kindRaw.startsWith('ipucu') ? NoteKind.tip : NoteKind.summary,
            subject: v('subject'),
            grade: v('grade'),
            topic: v('topic'),
            outcome: v('outcome'),
            title: title,
            body: body,
            tags: tags,
            source: v('source'),
            created: now,
            updated: now,
          ));
        }
      }
    }
    return BankImportResult(qs, ns, skipped);
  }

  static BankImportResult parseXlsx(List<int> bytes) => parseRows(StudentImport.xlsxSheets(bytes));

  /// Herhangi bir tablo dosyası (.xlsx, .xls, .ods) ya da CSV.
  static BankImportResult parseFile(Uint8List bytes, String fileName) {
    final sheets = spreadsheetSheets(bytes, fileName);
    return sheets != null ? parseRows(sheets) : parseCsv(utf8.decode(bytes, allowMalformed: true));
  }

  static BankImportResult parseCsv(String text) {
    if (text.startsWith('﻿')) text = text.substring(1);
    final first = text.split('\n').first;
    final delim = ';'.allMatches(first).length > ','.allMatches(first).length ? ';' : (first.contains('\t') ? '\t' : ',');
    final rows = <List<String>>[];
    for (final line in const LineSplitter().convert(text)) {
      rows.add(_splitCsv(line, delim));
    }
    return parseRows([('CSV', rows)]);
  }

  static List<String> _splitCsv(String line, String d) {
    final out = <String>[];
    final b = StringBuffer();
    var q = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        if (q && i + 1 < line.length && line[i + 1] == '"') {
          b.write('"');
          i++;
        } else {
          q = !q;
        }
      } else if (c == d && !q) {
        out.add(b.toString());
        b.clear();
      } else {
        b.write(c);
      }
    }
    out.add(b.toString());
    return out;
  }

  // ———————————————————————————— Şablon ve dışa aktarma

  static List<String> get questionHeaders => [
        tr('Ders'),
        tr('Sınıf / düzey'),
        tr('Konu'),
        tr('Kazanım'),
        tr('Zorluk (Kolay/Orta/Zor)'),
        tr('Tür (Test/DY/Boşluk/Klasik)'),
        tr('Soru'),
        'A',
        'B',
        'C',
        'D',
        'E',
        tr('Cevap'),
        tr('Çözüm'),
        tr('Etiketler'),
        tr('Puan'),
        tr('Düşünme düzeyi (Hatırlama…Yaratma)'),
      ];

  static List<String> get noteHeaders => [
        tr('Tür (Özet/Hap)'),
        tr('Başlık'),
        tr('Ders'),
        tr('Sınıf / düzey'),
        tr('Konu'),
        tr('Kazanım'),
        tr('Metin'),
        tr('Etiketler'),
      ];

  static String _typeCell(QuestionType t) => switch (t) {
        QuestionType.multiple => tr('Test'),
        QuestionType.trueFalse => tr('DY'),
        QuestionType.fill => tr('Boşluk'),
        QuestionType.open => tr('Klasik'),
        QuestionType.matching => tr('Eşleştirme'),
        QuestionType.trueFalseTable => tr('DY tablosu'),
        QuestionType.wordBank => tr('Kelime havuzu'),
        QuestionType.ordering => tr('Sıralama'),
      };

  static List<String> questionRow(BankQuestion q) => [
        q.subject,
        q.grade,
        q.topic,
        q.outcome,
        q.difficulty.label,
        _typeCell(q.type),
        // Madde listeli türlerde maddeler metnin altına numaralı yazılır.
        q.items.isEmpty ? q.text : [q.text, for (var i = 0; i < q.items.length; i++) '${i + 1}) ${q.items[i]}'].join('\n').trim(),
        for (var i = 0; i < 5; i++) i < q.choices.length ? q.choices[i] : '',
        q.type.optical
            ? (q.type == QuestionType.trueFalse ? (q.correct.contains(1) ? tr('Y') : tr('D')) : q.answerLabel)
            : q.answerText,
        q.solution,
        q.tags.join(', '),
        q.points.toString(),
        q.cognitive == CognitiveLevel.none ? '' : q.cognitive.label,
      ];

  static List<String> noteRow(BankNote n) => [
        n.kind == NoteKind.tip ? tr('Hap') : tr('Özet'),
        n.title,
        n.subject,
        n.grade,
        n.topic,
        n.outcome,
        n.body,
        n.tags.join(', '),
      ];

  /// Öğretmenin dolduracağı örnek şablon (iki sayfa: Sorular, Notlar).
  static Uint8List template() => writeXlsx([
        (
          tr('Sorular'),
          [
            questionHeaders,
            [
              tr('Fizik'), '9', tr('Kuvvet ve hareket'), 'F.9.2.1', tr('Kolay'), tr('Test'),
              tr('Net kuvvet sıfır olan bir cisim için aşağıdakilerden hangisi kesinlikle doğrudur?'),
              tr('Duruyordur'), tr('Hızlanıyordur'), tr('Hızı değişmez'), tr('Yavaşlıyordur'), tr('Yön değiştiriyordur'),
              'C', tr('Newton\'un 1. yasası: net kuvvet sıfırsa hız sabittir.'), tr('çıkmış soru'), '5', tr('Anlama'),
            ],
            [
              tr('Fizik'), '9', tr('Kuvvet ve hareket'), '', tr('Orta'), tr('DY'),
              tr('Sürtünme kuvveti her zaman harekete zıt yöndedir.'), '', '', '', '', '', tr('D'), '', '', '5', tr('Hatırlama'),
            ],
            [
              tr('Fizik'), '9', tr('Enerji'), '', tr('Zor'), tr('Klasik'),
              tr('Serbest bırakılan bir cismin mekanik enerjisinin korunduğunu bir örnekle açıklayınız.'),
              '', '', '', '', '', tr('Potansiyel enerji kinetik enerjiye dönüşür, toplam sabit kalır.'), '', '', '10', tr('Değerlendirme'),
            ],
          ]
        ),
        (
          tr('Notlar'),
          [
            noteHeaders,
            [tr('Hap'), tr('Newton\'un 1. yasası'), tr('Fizik'), '9', tr('Kuvvet ve hareket'), '', tr('Net kuvvet sıfırsa cisim ya durur ya da sabit hızla gider.'), ''],
            [tr('Özet'), tr('Enerji dönüşümleri'), tr('Fizik'), '9', tr('Enerji'), '', tr('• Kinetik enerji: Ek = ½·m·v²\n• Potansiyel enerji: Ep = m·g·h\n• Sürtünme yoksa toplam mekanik enerji korunur.'), ''],
          ]
        ),
      ]);

  /// Bankayı (ya da seçilenleri) Excel'e yazar.
  static Uint8List export(List<BankQuestion> qs, List<BankNote> ns) => writeXlsx([
        (tr('Sorular'), [questionHeaders, for (final q in qs) questionRow(q)]),
        (tr('Notlar'), [noteHeaders, for (final n in ns) noteRow(n)]),
      ]);

  /// Basit .xlsx yazıcı: satır içi metin hücreleri, kalın başlık satırı.
  static Uint8List writeXlsx(List<(String, List<List<String>>)> sheets) {
    String esc(String s) => const HtmlEscape(HtmlEscapeMode.element)
        .convert(s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), ''));
    String col(int i) {
      var n = i + 1;
      var s = '';
      while (n > 0) {
        final m = (n - 1) % 26;
        s = String.fromCharCode(65 + m) + s;
        n = (n - 1) ~/ 26;
      }
      return s;
    }

    final a = Archive();
    void add(String name, String content) {
      final b = utf8.encode(content);
      a.addFile(ArchiveFile(name, b.length, b));
    }

    final n = sheets.length;
    add('[Content_Types].xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '${[for (var i = 1; i <= n; i++) '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
        '</Types>');
    add('_rels/.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>');
    add('xl/workbook.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
        '${[for (var i = 0; i < n; i++) '<sheet name="${esc(sheets[i].$1)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}'
        '</sheets></workbook>');
    add('xl/_rels/workbook.xml.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '${[for (var i = 0; i < n; i++) '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>'].join()}'
        '<Relationship Id="rId${n + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>');
    add('xl/styles.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts>'
        '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>'
        '<fill><patternFill patternType="solid"><fgColor rgb="FF0F1B3D"/></patternFill></fill></fills>'
        '<borders count="1"><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs>'
        '<cellXfs count="3"><xf/><xf fontId="1" fillId="2" applyFont="1" applyFill="1"/><xf applyAlignment="1"><alignment wrapText="1" vertical="top"/></xf></cellXfs>'
        '</styleSheet>');
    for (var s = 0; s < n; s++) {
      final rows = sheets[s].$2;
      final b = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
          '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>'
          '<cols><col min="1" max="40" width="18" customWidth="1"/></cols><sheetData>');
      for (var r = 0; r < rows.length; r++) {
        b.write('<row r="${r + 1}">');
        for (var c = 0; c < rows[r].length; c++) {
          final v = rows[r][c];
          if (v.isEmpty) continue;
          b.write('<c r="${col(c)}${r + 1}" t="inlineStr" s="${r == 0 ? 1 : 2}"><is><t xml:space="preserve">${esc(v)}</t></is></c>');
        }
        b.write('</row>');
      }
      b.write('</sheetData></worksheet>');
      add('xl/worksheets/sheet${s + 1}.xml', b.toString());
    }
    return Uint8List.fromList(ZipEncoder().encode(a));
  }
}
