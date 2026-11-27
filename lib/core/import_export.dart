import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:xml/xml.dart';

import 'deneme.dart';
import 'models.dart';
import 'report.dart';
import 'scoring.dart';
import 'term.dart';
import '../l10n/l10n.dart';

/// Öğrenci listesi içe aktarma (CSV / Excel'den "CSV olarak kaydet").
///
/// Sütunlar başlıklardan otomatik tahmin edilir: ad, soyad, (okul) no,
/// sınıf/şube. "Ad Soyad" tek sütunsa son kelime soyad sayılır.
class StudentImport {
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

  static List<List<String>> _rows(String text) {
    final firstLine = text.split('\n').first;
    // Türkçe Excel CSV'leri genelde noktalı virgül kullanır.
    final delim = ';'.allMatches(firstLine).length > ','.allMatches(firstLine).length
        ? ';'
        : (firstLine.contains('\t') ? '\t' : ',');
    final rows = Csv(fieldDelimiter: delim, autoDetect: false)
        .decode(text.replaceAll('\r\n', '\n'));
    return rows
        .map((r) => r.map((c) => c.toString().trim()).toList())
        .where((r) => r.any((c) => c.isNotEmpty))
        .toList();
  }

  /// [defaultClass] sınıf sütunu yoksa kullanılır.
  static List<Student> parse(String text, {String defaultClass = ''}) {
    if (text.startsWith('﻿')) text = text.substring(1);
    return parseRows(_rows(text), defaultClass: defaultClass);
  }

  /// Excel (.xlsx) dosyasının bütün sayfalarını okur. Sınıf sütunu olmayan
  /// sayfalarda sınıf, başlık üstündeki "9. Sınıf / A Şubesi" satırından ya da
  /// sayfanın adından ("9-A") alınır; ikisi de yoksa [defaultClass].
  static List<Student> parseXlsx(List<int> bytes, {String defaultClass = ''}) => parseSheets(xlsxSheets(bytes), defaultClass: defaultClass);

  /// Herhangi bir tablo dosyasının sayfalarından (.xlsx, .xls, .ods…) öğrenciler.
  static List<Student> parseSheets(List<(String, List<List<String>>)> sheets, {String defaultClass = ''}) {
    final out = <Student>[];
    for (final (name, rows) in sheets) {
      final cls = _classFromTitle(rows) ?? (_genericSheet(name) ? null : name.trim()) ?? defaultClass;
      out.addAll(parseRows(rows, defaultClass: cls));
    }
    return out;
  }

  /// "Sayfa1", "Sheet2", "Feuil1"… gibi Excel'in kendi verdiği adlar sınıf değildir.
  static bool _genericSheet(String name) =>
      name.trim().isEmpty ||
      RegExp(r'^(sayfa|sheet|tabelle|feuil|hoja|foglio|лист|工作表|シート|ورقة|vərəq)\s*\d*$', caseSensitive: false)
          .hasMatch(name.trim());

  static final _titleClass = RegExp(
      r'(\d{1,2})\s*\.?\s*(?:SINIF|Sınıf|sınıf|SINIFI|Sınıfı|sınıfı)\s*[/\-–,]?\s*([A-ZÇĞİÖŞÜ])\s*(?:ŞUBESİ|Şubesi|şubesi|ŞUBE|Şube|şube)');
  static final _labelClass =
      RegExp(r'^(?:SINIF|Sınıf|sınıf|SINIFI|Sınıfı|sınıfı|Sınıf\s*/\s*Şube|ŞUBE|Şube|şube)\s*[:\-]?\s*(.*)$');

  /// Başlık satırından önceki satırlarda yazan sınıf adı (e-Okul dökümleri).
  static String? _classFromTitle(List<List<String>> rows) {
    final hi = rows.take(15).toList().indexWhere(_isHeader);
    if (hi <= 0) return null;
    for (final r in rows.take(hi)) {
      for (var i = 0; i < r.length; i++) {
        final m = _titleClass.firstMatch(r[i]);
        if (m != null) return '${m.group(1)}-${m.group(2)}';
        final l = _labelClass.firstMatch(r[i].trim());
        if (l != null) {
          var v = l.group(1)!.trim();
          if (v.isEmpty) v = r.skip(i + 1).firstWhere((c) => c.trim().isNotEmpty, orElse: () => '').trim();
          if (v.isNotEmpty && v.length <= 12) return v;
        }
      }
    }
    return null;
  }

  static final _lineClass = RegExp(
      r'^\s*(\d{1,2})\s*[-/.]?\s*([A-ZÇĞİÖŞÜ])\s*(?:SINIFI|Sınıfı|sınıfı|SINIF|Sınıf|sınıf|ŞUBESİ|Şubesi|şubesi)\b');
  static final _cellClass = RegExp(r'^(\d{1,2})\s*[-/]\s*([A-ZÇĞİÖŞÜ])$');
  static final _gender = RegExp(r'^(?:KIZ|Kız|kız|ERKEK|Erkek|erkek|K|E)$');
  static final _word = RegExp(r"^[A-Za-zÇĞİÖŞÜçğıöşüÂÎÛâîû.'’\-]+$");

  /// PDF ya da Word'den çıkan düz yazıdaki öğrenci listesi. Sayfalardaki
  /// "9. Sınıf / A Şubesi", "Sınıf: 9-A" ya da "9-A SINIFI" başlıkları
  /// altındaki öğrenciler o sınıfa yazılır; satırda "9-A" gibi bir hücre
  /// varsa o kullanılır. Satır "sıra no, okul no, ad, soyad…" ya da
  /// "okul no, ad soyad…" biçiminde olmalıdır.
  static List<Student> parseText(String text, {String defaultClass = ''}) {
    final out = <Student>[];
    var cls = defaultClass;
    var i = 0;
    final seen = <String>{};
    for (var line in text.split(RegExp(r'\r?\n'))) {
      line = line.replaceAll('|', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (line.isEmpty) continue;
      final t = _titleClass.firstMatch(line) ?? _lineClass.firstMatch(line);
      if (t != null) {
        cls = '${t.group(1)}-${t.group(2)}';
        continue;
      }
      final l = _labelClass.firstMatch(line);
      if (l != null && !RegExp(r'^\d').hasMatch(line)) {
        final v = l.group(1)!.trim();
        final c = _cellClass.firstMatch(v);
        if (c != null) {
          cls = '${c.group(1)}-${c.group(2)}';
        } else if (v.isNotEmpty && v.length <= 12 && !v.contains(' ')) {
          cls = v;
        }
        continue;
      }
      final tok = line.split(' ');
      var k = 0;
      final nums = <String>[];
      while (k < tok.length && nums.length < 3 && RegExp(r'^\d{1,12}[.)]?$').hasMatch(tok[k])) {
        nums.add(tok[k].replaceAll(RegExp(r'\D'), ''));
        k++;
      }
      if (nums.isEmpty) continue;
      String? rowClass;
      final name = <String>[];
      for (; k < tok.length; k++) {
        final c = _cellClass.firstMatch(tok[k]);
        if (c != null) {
          rowClass = '${c.group(1)}-${c.group(2)}';
          break;
        }
        if (name.length >= 2 && _gender.hasMatch(tok[k])) break;
        if (!_word.hasMatch(tok[k]) || !RegExp(r'[A-Za-zÇĞİÖŞÜçğıöşü]').hasMatch(tok[k])) break;
        name.add(tok[k]);
      }
      if (rowClass == null) {
        for (final x in tok.skip(k)) {
          final c = _cellClass.firstMatch(x);
          if (c != null) {
            rowClass = '${c.group(1)}-${c.group(2)}';
            break;
          }
        }
      }
      if (name.length < 2) continue;
      final no = nums.length >= 2 ? nums[1] : nums[0];
      final klass = rowClass ?? cls;
      if (!seen.add('$klass|$no|${name.join(' ')}')) continue;
      final last = name.removeLast();
      out.add(Student(
        id: 's${DateTime.now().microsecondsSinceEpoch}_${i++}',
        firstName: name.join(' '),
        lastName: last,
        number: no,
        className: klass,
      ));
    }
    return out;
  }

  /// .xlsx içindeki ilk çalışma sayfasını satır listesine çevirir.
  static List<List<String>> xlsxRows(List<int> bytes) => xlsxSheets(bytes).firstOrNull?.$2 ?? [];

  /// .xlsx içindeki bütün çalışma sayfaları, kitaptaki sırayla: (ad, satırlar).
  /// Boş sayfalar atlanır.
  static List<(String, List<List<String>>)> xlsxSheets(List<int> bytes) {
    final zip = ZipDecoder().decodeBytes(bytes);
    String? read(String name) {
      final f = zip.findFile(name);
      return f == null ? null : utf8.decode(f.content as List<int>, allowMalformed: true);
    }

    final shared = <String>[];
    final ss = read('xl/sharedStrings.xml');
    if (ss != null) {
      for (final si in XmlDocument.parse(ss).findAllElements('si')) {
        shared.add(si.findAllElements('t').map((t) => t.innerText).join());
      }
    }
    // Sayfaların dosya adlarını workbook ilişkilerinden bul; yoksa sheet1.
    final sheets = <(String, String)>[];
    final wb = read('xl/workbook.xml');
    final rels = read('xl/_rels/workbook.xml.rels');
    if (wb != null && rels != null) {
      final relDoc = XmlDocument.parse(rels);
      for (final sh in XmlDocument.parse(wb).findAllElements('sheet')) {
        final rid = sh.attributes.where((a) => a.name.local == 'id').firstOrNull?.value;
        final target = relDoc
            .findAllElements('Relationship')
            .where((r) => r.getAttribute('Id') == rid)
            .firstOrNull
            ?.getAttribute('Target');
        if (target == null) continue;
        final path = target.startsWith('/') ? target.substring(1) : 'xl/${target.replaceFirst(RegExp(r'^\./'), '')}';
        sheets.add((sh.getAttribute('name') ?? '', path));
      }
    }
    if (sheets.isEmpty) sheets.add(('', 'xl/worksheets/sheet1.xml'));

    final out = <(String, List<List<String>>)>[];
    for (final (name, path) in sheets) {
      final xml = read(path);
      if (xml == null) continue;
      final rows = _sheetRows(xml, shared);
      if (rows.isNotEmpty) out.add((name, rows));
    }
    return out;
  }

  static List<List<String>> _sheetRows(String xml, List<String> shared) {
    int colIndex(String ref) {
      var n = 0;
      for (final ch in ref.codeUnits) {
        if (ch < 65 || ch > 90) break;
        n = n * 26 + (ch - 64);
      }
      return n - 1;
    }

    final rows = <List<String>>[];
    for (final row in XmlDocument.parse(xml).findAllElements('row')) {
      final cells = <String>[];
      var next = 0;
      for (final c in row.findElements('c')) {
        final ref = c.getAttribute('r');
        final idx = ref == null ? next : colIndex(ref);
        final type = c.getAttribute('t');
        String v;
        if (type == 's') {
          final k = int.tryParse(c.getElement('v')?.innerText ?? '');
          v = k != null && k < shared.length ? shared[k] : '';
        } else if (type == 'inlineStr') {
          v = c.findAllElements('t').map((t) => t.innerText).join();
        } else {
          v = c.getElement('v')?.innerText ?? '';
          // 1042.0 gibi sayıları tam sayıya çevir.
          final d = double.tryParse(v);
          if (d != null && d == d.roundToDouble() && d.abs() < 1e15) v = d.toInt().toString();
        }
        while (cells.length < idx) {
          cells.add('');
        }
        cells.add(v.trim());
        next = idx + 1;
      }
      if (cells.any((x) => x.isNotEmpty)) rows.add(cells);
    }
    return rows;
  }

  static bool _isHeader(List<String> row) {
    final h = row.map(_norm).toList();
    return h.any((x) => x == 'ad' || x == 'adi' || x == 'isim' || x.contains('soyad') || x.contains('okulno') ||
        x.contains('ogrencino') || x == 'no' || x == 'numara' || x.contains('adsoyad'));
  }

  /// "Arapça", "Arabic", "ar", "العربية" gibi yazımlardan uygulama dil kodu.
  static String languageCodeOf(String raw) {
    final t = raw.trim().toLowerCase();
    if (t.isEmpty) return '';
    for (final l in AppLanguage.all) {
      if (t == l.code || t == l.name.toLowerCase()) return l.code;
    }
    const names = {
      'tr': ['türkçe', 'turkce', 'turkish', 'türk'],
      'en': ['ingilizce', 'english', 'inglés', 'anglais', 'englisch'],
      'az': ['azerice', 'azerbaycanca', 'azerbaijani', 'azəri'],
      'de': ['almanca', 'german', 'deutsch'],
      'ar': ['arapça', 'arapca', 'arabic', 'arabe', 'arabisch'],
      'es': ['ispanyolca', 'spanish', 'español', 'espanol', 'spanisch'],
      'ru': ['rusça', 'rusca', 'russian', 'русский', 'russisch'],
      'it': ['italyanca', 'italian', 'italiano'],
      'fr': ['fransızca', 'fransizca', 'french', 'français', 'francais'],
      'zh': ['çince', 'cince', 'chinese', '中文'],
      'ja': ['japonca', 'japanese', '日本語'],
      'pt': ['portekizce', 'portuguese', 'português', 'portugues'],
      'hi': ['hintçe', 'hintce', 'hindi', 'हिन्दी'],
      'id': ['endonezce', 'indonesian', 'bahasa indonesia', 'indonesia'],
      'ko': ['korece', 'korean', '한국어'],
    };
    for (final e in names.entries) {
      if (e.value.any((n) => t.startsWith(n))) return e.key;
    }
    return '';
  }

  static List<Student> parseRows(List<List<String>> allRows, {String defaultClass = ''}) {
    if (allRows.isEmpty) return [];
    // e-Okul gibi dökümlerde başlıktan önce okul adı vb. satırlar olabilir.
    final hi = allRows.take(15).toList().indexWhere(_isHeader);
    final rows = hi > 0 ? allRows.sublist(hi) : allRows;
    final header = rows.first.map(_norm).toList();
    // Anahtarlar öncelik sırasıyla aranır; önce tam eşleşme, sonra içerme.
    int find(List<String> keys) {
      for (final k in keys) {
        final i = header.indexWhere((h) => h == k);
        if (i >= 0) return i;
      }
      for (final k in keys) {
        final i = header.indexWhere((h) => h.contains(k) && !(k == 'no' && h.length > 4));
        if (i >= 0) return i;
      }
      return -1;
    }

    var iNo = find(['okulno', 'ogrencino', 'numara', 'no']);
    var iFirst = header.indexWhere((h) => h == 'ad' || h == 'adi' || h == 'isim');
    var iLast = find(['soyad']);
    var iFull = find(['adsoyad', 'adisoyadi', 'adsoyadi']);
    final iClass = find(['sinif', 'sube']);
    final iPhone = find(['velitelefonu', 'velitelefon', 'velitel', 'velicep', 'telefon', 'gsm', 'cep', 'phone']);
    final iMail = find(['eposta', 'email', 'mail', 'epostaadresi', 'emailaddress']);
    final iLang = find(['velidili', 'velidil', 'parentlanguage', 'homelanguage', 'evdili', 'anadili']);
    final hasHeader = iNo >= 0 || iFirst >= 0 || iFull >= 0;
    final data = hasHeader ? rows.skip(1) : rows;
    if (!hasHeader) {
      // Başlıksız: no, ad soyad varsayımı.
      iNo = 0;
      iFull = 1;
    }

    final out = <Student>[];
    var i = 0;
    for (final r in data) {
      String at(int idx) => idx >= 0 && idx < r.length ? r[idx] : '';
      String first, last;
      if (iFirst >= 0 && iLast >= 0) {
        first = at(iFirst);
        last = at(iLast);
      } else {
        final parts = at(iFull >= 0 ? iFull : (iFirst >= 0 ? iFirst : 1)).split(RegExp(r'\s+'));
        last = parts.length > 1 ? parts.removeLast() : '';
        first = parts.join(' ');
      }
      final no = at(iNo).replaceAll(RegExp(r'\D'), '');
      if (first.isEmpty && last.isEmpty) continue;
      out.add(Student(
        id: 's${DateTime.now().microsecondsSinceEpoch}_${i++}',
        firstName: first,
        lastName: last,
        number: no,
        className: at(iClass).isNotEmpty ? at(iClass) : defaultClass,
        parentPhone: iPhone >= 0 ? at(iPhone).trim() : '',
        email: iMail >= 0 && at(iMail).contains('@') ? at(iMail).trim() : '',
        parentLanguage: iLang >= 0 ? languageCodeOf(at(iLang)) : '',
      ));
    }
    return out;
  }
}

/// Excel'in doğrudan açabildiği not listesi (UTF-8 BOM + noktalı virgül).
String resultsCsv(Exam exam, List<Result> results, Map<String, Student> students) {
  final report = ExamReport.build(exam, results);
  final deneme = exam.isMultiSubject ? DenemeReport.build(exam, results) : null;
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp = '${L10n.date(now)} ${two(now.hour)}:${two(now.minute)}';
  String n(double v) => v.toStringAsFixed(2).replaceAll('.', L10n.decimal);
  final extra = exam.hasOpen ? exam.openQuestions.length + 2 : 0;
  // Başka firma formlarındaki diğer kodlama alanları (doğum tarihi, cinsiyet…): en sonda.
  final fieldNames = <String>{for (final r in results) ...r.sheet.fields.keys}.toList();
  final rows = <List<String>>[
    [tr('Sıra'), tr('Okul no'), 'Ad', tr('Soyad'), tr('Sınıf'), tr('Doğru'), tr('Yanlış'), tr('Boş'), tr('Net'),
      if (exam.hasOpen) ...[tr('Test puanı'), for (final q in exam.openQuestions) q.label, tr('Klasik toplam')],
      tr('Puan'), tr('Başarı %'), tr('Yüzdelik'),
      tr('T puanı'), tr('Düzey'),
      for (final o in report.outcomes) tr('Kazanım: {0} %', [o.code]),
      for (final q in exam.questions) 'S${q.no}',
      ...fieldNames,
      if (deneme != null) ...[
        for (final sec in exam.sections) ...['${sec.name} ${tr('D')}', '${sec.name} ${tr('Y')}', '${sec.name} ${tr('Net')}'],
        tr('Toplam net'),
        if (exam.hasWeightedScore) tr('Deneme puanı'),
        tr('Deneme sırası'),
      ]],
    for (final st in report.standings)
      () {
        final r = st.result;
        final s = students[r.sheet.studentId];
        return [
          '${st.rank}',
          s?.number ?? '',
          s?.firstName ?? tr('Eşleşmedi'),
          s?.lastName ?? '',
          s?.className ?? exam.className,
          '${r.correct}',
          '${r.wrong}',
          '${r.blank}',
          n(r.net),
          if (exam.hasOpen) ...[
            n(r.testScore),
            for (var i = 0; i < exam.openQuestions.length; i++)
              i < r.sheet.openScores.length && r.sheet.openScores[i] != null ? n(r.sheet.openScores[i]!) : '',
            n(r.openScore),
          ],
          n(r.score),
          n(st.pct),
          n(st.percentile),
          n(st.t),
          st.level.name,
          for (final o in report.outcomes) n(o.rateOf(exam, r) * 100),
          for (final a in r.sheet.answers)
            a.marked.isEmpty ? '' : a.marked.map((c) => String.fromCharCode(65 + c)).join('/'),
          for (final f in fieldNames) r.sheet.fields[f] ?? '',
          if (deneme != null)
            ...() {
              final d = deneme.rows.firstWhere((x) => identical(x.result, r), orElse: () => deneme.rowOf(r.sheet.studentId)!);
              return [
                for (final x in d.sections) ...['${x.correct}', '${x.wrong}', n(x.net)],
                n(d.totalNet),
                if (exam.hasWeightedScore) n(d.weighted!),
                '${d.rank}',
              ];
            }(),
        ];
      }(),
    [],
    [tr('Sınıf ortalaması'), '', '', '', '', n(report.meanCorrect), n(report.meanWrong), n(report.meanBlank),
      n(report.meanNet), for (var i = 0; i < extra; i++) '', n(report.stats.mean)],
    [tr('Doğru oranı (p)'), '', '', '', '', '', '', '', '', '', '', '', '', '', for (var i = 0; i < extra; i++) '',
      for (final o in report.outcomes) n(o.rate * 100),
      for (final it in report.items) n(it.p)],
    [tr('Ayırt edicilik (D)'), '', '', '', '', '', '', '', '', '', '', '', '', '', for (var i = 0; i < extra; i++) '',
      for (final _ in report.outcomes) '',
      for (final it in report.items) n(it.d)],
    [],
    [tr('Sınav'), exam.name, '', tr('Sınav tarihi'), L10n.date(exam.date), '',
      tr('Rapor tarihi'), stamp],
  ];
  return '\uFEFF${Csv(fieldDelimiter: ';', lineDelimiter: '\r\n').encode(rows)}';
}

List<int> utf8Bytes(String s) => utf8.encode(s);

/// e-Okul giriş listesi (Excel): okul numarasına göre sıralı, tam sayı puan.
String eokulCsv(Exam exam, List<Result> results, List<Student> classStudents) {
  final byId = {for (final r in results) r.sheet.studentId: r};
  final list = [...classStudents]
    ..sort((a, b) => (int.tryParse(a.number) ?? 0).compareTo(int.tryParse(b.number) ?? 0));
  final rows = <List<String>>[
    [tr('Sıra'), tr('Okul No'), tr('Adı'), tr('Soyadı'), tr('Puan'), tr('Not')],
    for (var i = 0; i < list.length; i++)
      [
        '${i + 1}',
        list[i].number,
        list[i].firstName,
        list[i].lastName,
        byId[list[i].id] == null ? tr('G') : '${byId[list[i].id]!.score.round()}',
        byId[list[i].id] == null ? tr('Sınava girmedi') : '',
      ],
  ];
  return '\uFEFF${Csv(fieldDelimiter: ';', lineDelimiter: '\r\n').encode(rows)}';
}

/// Dönem sonu not çizelgesi (Excel): her sınav 100 üzerinden, ortalama ve
/// e-Okul'a girilecek tam sayı not.
String termCsv(TermReport t) {
  String n(double v) => v.toStringAsFixed(2).replaceAll('.', L10n.decimal);
  final rows = <List<String>>[
    [tr('Okul No'), tr('Adı'), tr('Soyadı'), tr('Sınıf'), for (final e in t.exams) e.exam.name, tr('Ortalama'), tr('Dönem notu')],
    for (final r in t.rows)
      [
        r.student.number,
        r.student.firstName,
        r.student.lastName,
        r.student.className,
        for (final s in r.scores) s == null ? tr('G') : n(s),
        r.average == null ? '' : n(r.average!),
        r.grade == null ? tr('G') : '${r.grade}',
      ],
    [],
    [tr('Ağırlık'), '', '', '', for (final e in t.exams) n(e.weight)],
    [tr('Sınıf ort. (100)'), '', '', '', for (final e in t.exams) n(e.mean100), n(t.classAverage)],
    [tr('Dönem'), t.term.label],
  ];
  return '\uFEFF${Csv(fieldDelimiter: ';', lineDelimiter: '\r\n').encode(rows)}';
}
