import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
// Arapça harfleri tuvale yazmadan önce birleştirmek için (pw.Text bunu kendisi yapar).
// ignore: implementation_imports
import 'package:pdf/src/pdf/font/arabic.dart' as arabic_text;
import 'package:pdf/widgets.dart' as pw;

import '../core/models.dart';
import '../core/insights.dart';
import '../core/misconceptions.dart';
import '../core/teaching.dart';
import '../core/overview.dart';
import '../core/progress.dart';
import '../core/report.dart';
import '../core/scoring.dart';
import '../core/term.dart';
import '../core/legal.dart';
import '../omr/form_code.dart';
import '../omr/form_layout.dart';
import '../l10n/l10n.dart';
import 'brand_footer.dart';
import 'kid_pdf.dart';
import 'kid_reports_pdf.dart';

part 'teaching_pdf.dart';

const _ink = PdfColor.fromInt(0xFF0F1B3D);
const _emerald = PdfColor.fromInt(0xFF10B981);
const _muted = PdfColor.fromInt(0xFF6B7280);
const _coral = PdfColor.fromInt(0xFFE8613C);
const _amber = PdfColor.fromInt(0xFFF2B33D);
const _gray = PdfColor.fromInt(0xFF9AA0AE);
const _ivory = PdfColor.fromInt(0xFFF6F3EC);
const _line = PdfColor.fromInt(0xFFE2DDD1);
const _levelPalette = [_emerald, PdfColor.fromInt(0xFF34D399), _amber, PdfColor.fromInt(0xFFF59E0B), _coral];

/// Düzey sayısı not sistemine göre değişir; renkler yeşilden kırmızıya yayılır.
PdfColor _levelColor(int i) {
  final n = Level.all.length;
  return _levelPalette[n <= 1 ? 0 : (i * (_levelPalette.length - 1) / (n - 1)).round()];
}

class _Fonts {
  final pw.Font regular;
  final pw.Font bold;
  final pw.Font italic;
  final pw.Font boldItalic;

  /// Latin dışı harfler (Kiril, Arap, Çin, Japon, Kore, Hint) için yedek yazı tipleri.
  final List<pw.Font> fallback;
  _Fonts(this.regular, this.bold, this.fallback, {pw.Font? italic, pw.Font? boldItalic})
      : italic = italic ?? regular,
        boldItalic = boldItalic ?? bold;

  static final _cache = <String, _Fonts>{};

  pw.ThemeData get theme =>
      pw.ThemeData.withFont(base: regular, bold: bold, italic: italic, boldItalic: boldItalic, fontFallback: fallback);

  /// [family]: netice, times ya da arial (Kurum bilgileri > Yazı stili).
  static Future<_Fonts> load([String family = 'netice']) async {
    await BrandAssets.load();
    final key = '${L10n.code}/$family';
    if (_cache[key] != null) return _cache[key]!;
    Future<pw.Font> f(String path) async => pw.Font.ttf(await rootBundle.load(path));
    final noto = await f('assets/pdf_fonts/NotoSans-Regular.ttf');
    final arabic = await f('assets/pdf_fonts/NotoSansArabic-Regular.ttf');
    final sc = await f('assets/pdf_fonts/NotoSansSC-Regular.ttf');
    final jp = await f('assets/pdf_fonts/NotoSansJP-Regular.ttf');
    final kr = await f('assets/pdf_fonts/NotoSansKR-Regular.ttf');
    final deva = await f('assets/pdf_fonts/NotoSansDevanagari-Regular.ttf');
    // Japonca seçiliyse ortak Çince/Japonca karakterler Japon biçimiyle yazılsın.
    final cjk = [
      ...switch (L10n.code) { 'ja' => [jp, sc], 'ko' => [kr, sc, jp], _ => [sc, jp] },
      if (L10n.code != 'ko') kr,
      deva,
    ];
    final jakarta = await f('assets/fonts/PlusJakartaSans_400Regular.ttf');
    final jakartaBold = await f('assets/fonts/PlusJakartaSans_700Bold.ttf');
    // Arapçada harflerin birleşmesi için Arap yazı tipi ana yazı tipi olmalı.
    if (L10n.rtl) {
      return _cache[key] = _Fonts(
          arabic, await f('assets/pdf_fonts/NotoSansArabic-Bold.ttf'), [jakarta, noto, ...cjk]);
    }
    final lib = switch (family) {
      'times' => 'LiberationSerif',
      'arial' => 'LiberationSans',
      _ => null,
    };
    if (lib != null) {
      return _cache[key] = _Fonts(
        await f('assets/pdf_fonts/$lib-Regular.ttf'),
        await f('assets/pdf_fonts/$lib-Bold.ttf'),
        [noto, arabic, ...cjk],
        italic: await f('assets/pdf_fonts/$lib-Italic.ttf'),
        boldItalic: await f('assets/pdf_fonts/$lib-BoldItalic.ttf'),
      );
    }
    return _cache[key] = _Fonts(jakarta, jakartaBold, [noto, arabic, ...cjk]);
  }

  /// Tuval üzerine doğrudan yazılan metin için, metindeki bütün harfleri
  /// içeren yazı tipini seçer; Arapçayı birleştirip sağdan sola çevirir.
  (PdfFont, String) pick(pw.Context ctx, String t, {bool bold = false}) {
    final main = (bold ? this.bold : regular).getFont(ctx);
    if (t.runes.every(main.isRuneSupported)) return (main, t);
    final shaped = RegExp(r'[\u0600-\u06FF]').hasMatch(t) ? arabic_text.convert(t) : t;
    for (final f in fallback) {
      final font = f.getFont(ctx);
      if (shaped.runes.every((r) => r == 32 || font.isRuneSupported(r))) return (font, shaped);
    }
    return (main, t);
  }
}

/// Raporlarla aynı yazı tipleri (soru kitapçığı gibi başka belgeler için).
Future<pw.ThemeData> pdfTheme([String family = 'netice']) async => (await _Fonts.load(family)).theme;

pw.TextDirection get _dir => L10n.rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;

/// Basılı optik formlar. Her öğrenci için adı ve numarası yazılı bir sayfa
/// üretir; [students] boşsa [blankCopies] adet boş form üretir.
///
/// Sınavda birden çok kitapçık varsa ve [alternateBooklets] açıksa isimli
/// formlar sırayla A, B, C… olarak basılır (kitapçık dairesi dolu gelir).
Future<Uint8List> buildFormsPdf(Exam exam, List<Student> students,
        {int blankCopies = 1, SchoolInfo school = const SchoolInfo(), bool alternateBooklets = false, bool bigCards = false}) =>
    buildClassFormsPdf([(exam, students)],
        blankCopies: blankCopies, school: school, alternateBooklets: alternateBooklets, bigCards: bigCards);

/// Birden çok şubenin isimli formlarını tek PDF'te basar; her şube kendi
/// sınavıyla (makine kodu) basılır. Kitapçıklar her şubede A'dan başlar.
Future<Uint8List> buildClassFormsPdf(List<(Exam, List<Student>)> groups,
    {int blankCopies = 1, SchoolInfo school = const SchoolInfo(), bool alternateBooklets = false, bool bigCards = false}) async {
  // Çocuk (ilkokul) sınavları: köşedeki kutunun isimli kartları (A4'e 4 ya da
  // büyük kartta 2 kart).
  if (groups.every((g) => g.$1.kidForm)) {
    return buildKidCardsPdf(groups, blankCopies: blankCopies, school: school, perPage: bigCards ? 2 : 4);
  }
  final fonts = await _Fonts.load();
  final first = groups.first.$1;
  final doc = pw.Document(theme: fonts.theme, title: tr('{0} · optik form', [first.name]), author: tr('Netice'));
  for (final (exam, students) in groups) {
    final layout = FormLayout(
        questionCount: exam.questionCount, choiceCount: exam.choiceCount, booklets: exam.bookletCount, digits: exam.numberDigits);
    final pages = students.isEmpty ? List<Student?>.filled(math.max(1, blankCopies), null) : students.cast<Student?>();
    for (var i = 0; i < pages.length; i++) {
      final s = pages[i];
      final booklet = exam.hasBooklets && alternateBooklets && s != null ? i % exam.bookletCount : null;
      doc.addPage(_formPage(layout, exam, fonts, school, student: s, booklet: booklet));
    }
  }
  return doc.save();
}

/// Cevap anahtarı formu. [filled] ise doğru şıklar karartılmış basılır ve
/// ikinci sayfada okunaklı bir anahtar listesi yer alır; değilse öğretmenin
/// elle dolduracağı boş bir anahtar formu üretilir.
Future<Uint8List> buildAnswerKeyPdf(Exam exam, {bool filled = true, SchoolInfo school = const SchoolInfo()}) async {
  final fonts = await _Fonts.load();
  final layout =
      FormLayout(
          questionCount: exam.questionCount, choiceCount: exam.choiceCount, booklets: exam.bookletCount, digits: exam.numberDigits);
  final doc = pw.Document(theme: fonts.theme, title: tr('{0} · cevap anahtarı', [exam.name]), author: tr('Netice'));
  doc.addPage(_formPage(layout, exam, fonts, school, key: true, keyFilled: filled, booklet: exam.hasBooklets ? 0 : null));
  if (exam.hasBooklets && filled) {
    for (var b = 1; b < exam.bookletCount; b++) {
      doc.addPage(_formPage(layout, exam, fonts, school, key: true, keyFilled: true, booklet: b));
    }
  }
  if (filled) {
    final k = _Kit(exam, school, docTitle: tr('Cevap Anahtarı'));
    final theme = fonts.theme;
    final qs = exam.questions;
    String ans(Question q) => q.cancelled ? tr('İptal') : (q.correct.isEmpty ? '–' : q.correct.map(_letter).join(' / '));
    String pts(double v) => v == v.roundToDouble() ? '${v.round()}' : _f1(v);
    final possible = qs.where((q) => !q.cancelled).fold<double>(0, (a, q) => a + q.points);
    // Sorunun puan tablosundaki gerçek değeri (ağırlık, toplam puana ölçeklenir).
    double worth(Question q) => possible == 0 ? 0 : q.points / possible * exam.rule.maxScore;
    doc.addPage(pw.MultiPage(textDirection: _dir, 
      theme: theme,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 28),
      header: k.header,
      footer: k.footer,
      build: (ctx) => [
        k.title(tr('Cevap anahtarı'), tr('{0} soru · {1} şık · sınav tarihi {2}', [exam.questionCount, exam.choiceCount, _date(exam.date)])),
        for (final (label, list) in [
          (exam.hasBooklets ? tr('{0} kitapçığı · hızlı okuma (beşli gruplar)', ['A']) : tr('Hızlı okuma (beşli gruplar)'), qs),
          for (var b = 1; b < exam.bookletCount; b++)
            (tr('{0} kitapçığı · hızlı okuma (beşli gruplar)', [Exam.bookletLetter(b)]), exam.questionsOf(b)),
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
        for (var b = 1; b < exam.bookletCount; b++) ...[
          pw.Text(
              tr('{0} kitapçığı sırası ({0}\'deki soru → A\'daki soru): {1}', [
                Exam.bookletLetter(b),
                [for (var i = 0; i < exam.bookletOrders[b - 1].length; i++) '${i + 1}→${exam.bookletOrders[b - 1][i] + 1}'].join('  ')
              ]),
              style: const pw.TextStyle(color: _muted, fontSize: 7.5)),
          pw.SizedBox(height: 3),
        ],
        pw.SizedBox(height: 14),
        pw.TableHelper.fromTextArray(
          headers: [exam.hasBooklets ? tr('Soru (A)') : tr('Soru'), tr('Doğru cevap'), tr('Puan'), tr('Kazanım')],
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
          tr('Toplam puan: {0} · Geçme puanı: {1}{2}', [pts(exam.rule.maxScore), pts(exam.rule.pass), qs.any((q) => q.cancelled) ? tr(' · İptal edilen sorular herkese doğru sayılır.') : '']),
          style: const pw.TextStyle(color: _muted, fontSize: 8),
        ),
      ],
    ));
  }
  return doc.save();
}

pw.Page _formPage(FormLayout layout, Exam exam, _Fonts fonts, SchoolInfo school,
        {Student? student, bool key = false, bool keyFilled = false, int? booklet}) =>
    pw.Page(textDirection: _dir, 
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (ctx) => pw.CustomPaint(
        size: PdfPoint(PdfPageFormat.a4.width, PdfPageFormat.a4.height),
        painter: (canvas, size) => _paintForm(canvas, size, layout, exam, student,
            (String t, {bool bold = false}) => fonts.pick(ctx, t, bold: bold),
            key: key, keyFilled: keyFilled, school: school, booklet: booklet),
      ),
    );

const _frame = PdfColor.fromInt(0xFFB9B3A6);
const _tint = PdfColor.fromInt(0xFFF3F1EB);
// Formdaki etiketler: gri değil, koyu ve okunaklı.
const _label = PdfColor.fromInt(0xFF374151);

/// Optik formu çizer. Daireler ve köşe kareleri [FormLayout]'taki yerlerinde
/// kalır (okuma motoru onları orada arar); süslemeler dairelerden en az
/// 2,5 mm uzakta tutulur ve koyu dolgulu büyük şekil kullanılmaz.
typedef _FontPicker = (PdfFont, String) Function(String t, {bool bold});

void _paintForm(PdfGraphics g, PdfPoint size, FormLayout layout, Exam exam, Student? s, _FontPicker fonts,
    {bool key = false, bool keyFilled = false, SchoolInfo school = const SchoolInfo(), int? booklet}) {
  const mm = PdfPageFormat.mm;
  // PDF koordinatları sol alttan başlar; form mm koordinatları sol üstten.
  double x(double v) => v * mm;
  double y(double v) => size.y - v * mm;

  double width(String t, double pt, {bool bold = false}) {
    final (font, shaped) = fonts(t, bold: bold);
    return font.stringMetrics(shaped).width * pt / mm;
  }

  double fitPt(String t, double pt, double maxW, {bool bold = false}) {
    while (pt > 4.6 && width(t, pt, bold: bold) > maxW) {
      pt -= 0.2;
    }
    return pt;
  }

  void text(String t, double px, double py, double pt,
      {bool bold = false, PdfColor color = _ink, bool right = false, bool center = false}) {
    final (font, shaped) = fonts(t, bold: bold);
    final w = font.stringMetrics(shaped).width * pt / mm;
    final left = right ? px - w : (center ? px - w / 2 : px);
    g.setFillColor(color);
    g.drawString(font, pt, shaped, x(left), y(py));
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
    text(label, x0 + 2, y0 + 3.3, 6.6, bold: true, color: _label);
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
  text(tr('Netice'), 32, 15.4, 12, bold: true);
  text(tr('Kâğıttan sonuca, saniyeler içinde.'), 24.3, 19.6, 7, color: _label);
  text(key ? tr('CEVAP ANAHTARI') : tr('OPTİK CEVAP KÂĞIDI'), 186, 15.2, 11.5,
      bold: true, right: true, color: key ? _coral : _ink);
  text(
      tr('{0} soru · {1} şık{2}', [exam.questionCount, exam.choiceCount, booklet == null ? '' : tr(' · {0} kitapçığı', [_letter(booklet)])]),
      186, 19.6, 7.4, right: true, color: (booklet ?? 0) > 0 ? _coral : _label, bold: booklet != null);

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
  const l = 24.0;
  final r = layout.infoRight;
  final c1 = l + (r - l) * 0.346, c2 = l + (r - l) * 0.654;
  if (key) {
    field(tr('BU KÂĞIT'), tr('CEVAP ANAHTARIDIR · öğrenciye dağıtmayın'), l, 22, r, valueColor: _coral);
  } else {
    field(tr('ADI SOYADI'), s?.fullName ?? '', l, 22, r);
  }
  field(tr('SINIFI / ŞUBESİ'), key ? exam.className : (s?.className ?? ''), l, 32.5, c1);
  field(tr('OKUL NO'), key ? '—' : (s?.number ?? ''), c1 + 2, 32.5, c2);
  field(tr('SINAV TARİHİ'), _date(exam.date), c2 + 2, 32.5, r, bold: false);
  field(tr('SINAV'), exam.name, l, 43, r);
  field(tr('OKUL'), school.name.trim(), l, 53.5, c2, bold: false);
  field(tr('DERS'), school.subject.trim(), c2 + 2, 53.5, r, bold: false);

  // Öğretmen kutucukları.
  final cells = key
      ? [
          (tr('SORU'), '${exam.questionCount}'),
          (tr('ŞIK'), '${exam.choiceCount}'),
          (tr('TOPLAM PUAN'), exam.rule.maxScore == exam.rule.maxScore.roundToDouble()
              ? '${exam.rule.maxScore.round()}'
              : _f1(exam.rule.maxScore)),
          (tr('İPTAL'), '${exam.questions.where((q) => q.cancelled).length}'),
          (tr('KAZANIM'), '${exam.questions.map((q) => q.outcomeCode).whereType<String>().toSet().length}'),
        ]
      : [(tr('DOĞRU'), ''), (tr('YANLIŞ'), ''), (tr('BOŞ'), ''), (tr('NET'), ''), (tr('PUAN'), '')];
  text(key ? tr('SINAV BİLGİSİ') : tr('ÖĞRETMEN DOLDURUR'), l, 66.2, 6.8, bold: true, color: _label);
  final cw = (r - l - 4 * 1.5) / 5;
  for (var i = 0; i < cells.length; i++) {
    final x0 = l + i * (cw + 1.5);
    box(x0, 67.5, x0 + cw, 76, fill: key ? null : _tint);
    text(cells[i].$1, x0 + 1.6, 70.6, fitPt(cells[i].$1, 6.4, cw - 3.2, bold: true), bold: true, color: _label);
    if (cells[i].$2.isNotEmpty) text(cells[i].$2, x0 + cw - 2, 74.6, 9, bold: true, right: true);
  }

  // Doldurma örneği ve kısa yönerge. Kitapçık kutusu varsa yönerge onun
  // soluna sığacak kadar küçültülür (uzun dillerde ve 3+ kitapçıkta).
  final guideRight = layout.hasBooklets
      ? layout.bookletBubble(0).x - (layout.booklets <= 2 ? 6.0 : 4.6) - 2
      : r;
  double fit(List<String> lines, double pt) {
    var size = pt;
    while (size > 5.4 && lines.any((t) => width(t, size) > guideRight - l)) {
      size -= 0.2;
    }
    return size;
  }

  text(key ? tr('ÖĞRETMEN İÇİN') : tr('NASIL DOLDURULUR?'), l, 81, 6.8, bold: true, color: _label);
  if (key) {
    final lines = keyFilled
        ? [
            tr('Doğru şıklar Netice tarafından karartıldı.'),
            tr('Bu sayfa kontrol ve arşiv içindir; okunaklı'),
            tr('anahtar listesi son sayfadadır.'),
          ]
        : [
            tr('Her sorunun doğru şıkkını karartın.'),
            tr('Sonra Sınav ayarları › Anahtarı fotoğraftan'),
            tr('oku ile çekin; anahtar kendiliğinden girilir.'),
          ];
    final pt = fit(lines, 7.4);
    for (var i = 0; i < lines.length; i++) {
      text(lines[i], l, 85.6 + i * 3.6, pt, color: _ink);
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

    text(tr('Doğru:'), l, 86.4, 7.2, bold: true, color: _emerald);
    sample(l + 11.4, 85.4, fill: true);
    text(tr('Yanlış:'), l + 17, 86.4, 7.2, bold: true, color: _coral);
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
    final guide = [
      tr('Daireyi taşırmadan tamamen karartın.'),
      tr('Değiştirirken eskisini iyice silin.'),
      tr('Kenardaki siyah karelere yazmayın, kâğıdı katlamayın.'),
    ];
    final pt = fit(guide, 7.2);
    for (var i = 0; i < guide.length; i++) {
      text(guide[i], l, 90.8 + i * 3.25, pt, color: _ink);
    }
  }

  // ---- Kitapçık türü ----
  if (layout.hasBooklets) {
    final a = layout.bookletBubble(0), b = layout.bookletBubble(layout.bookletColumns - 1);
    final twoRows = layout.bookletRows > 1;
    final pad = layout.booklets <= 2 ? 6.0 : 4.6;
    box(a.x - pad, 79, b.x + pad, twoRows ? 97.6 : 96.5, radius: 2, fill: _tint);
    text(tr('KİTAPÇIK'), (a.x + b.x) / 2, 82.8, 6.6, bold: true, color: _label, center: true);
    for (var k = 0; k < layout.booklets; k++) {
      final p = layout.bookletBubble(k);
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
    if (!twoRows) {
      text(booklet == null ? tr('Türünüzü işaretleyin') : tr('{0} kitapçığı', [_letter(booklet)]), (a.x + b.x) / 2, 95, 5.8,
          color: _label, center: true);
    }
  }

  // ---- Öğrenci numarası ----
  final rad = FormLayout.bubbleRadius * mm;
  final first = layout.studentBubble(0, 0);
  final last = layout.studentBubble(layout.digits - 1, 9);
  box(first.x - 6, 22, last.x + 6, last.y + 5.2, radius: 2);
  text(tr('ÖĞRENCİ NUMARASI'), (first.x + last.x) / 2, 25.8, 6.8, bold: true, color: _label, center: true);
  final number = key ? null : s?.number.padLeft(layout.digits, '0');
  for (var d = 0; d < layout.digits; d++) {
    final top = layout.studentBubble(d, 0);
    final hw = layout.wideNumber ? 2.6 : 3.0;
    box(top.x - hw, 27.4, top.x + hw, 34.2, radius: 0.8, stroke: PdfColors.grey500);
    if (number != null && number.length == layout.digits) {
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
      text(_letter(c), b.x, y0 + 3.1, 7.4, bold: true, center: true, color: _ink);
    }
    for (var row = 0; row < rows; row++) {
      final q = firstQ + row;
      final b0 = layout.answerBubble(q, 0);
      text('${q + 1}', b0.x - 4.1, b0.y + 1.25, 8.6, bold: true, right: true);
      final question = key && booklet != null && booklet > 0 ? exam.questionsOf(booklet)[q] : exam.questions[q];
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
    text(tr('NOTLAR / AÇIKLAMA'), nx + 2.5, y0 + 4.2, 6.8, bold: true, color: _label);
    final mid = (nx + 186) / 2;
    box(nx, y0 + 44, mid - 1.5, y0 + 62, radius: 2);
    text(tr('ÖĞRENCİ İMZASI'), nx + 2.5, y0 + 48.2, 6.8, bold: true, color: _label);
    box(mid + 1.5, y0 + 44, 186, y0 + 62, radius: 2);
    text(tr('ÖĞRETMEN İMZASI'), mid + 4, y0 + 48.2, 6.8, bold: true, color: _label);
  }

  // ---- Alt bilgi ----
  text(tr('Sınav kodu: {0}', [exam.id]), 24, 271.5, 6.4, color: _label);
  text(tr('Formu %100 ölçekle yazdırın; fotokopiyle çoğaltabilirsiniz.'), 186, 271.5, fitPt(tr('Formu %100 ölçekle yazdırın; fotokopiyle çoğaltabilirsiniz.'), 6.4, 95), right: true, color: _label);

  // ---- Tanıtım (alt köşe kareleri arasında; okuma alanlarının dışında) ----
  g.setStrokeColor(_frame);
  g.setLineWidth(0.4);
  g.drawLine(x(24), y(277.6), x(186), y(277.6));
  g.strokePath();
  void fitted(String t, double py, double pt, {bool bold = false, PdfColor color = _muted}) {
    while (pt > 4.2 && width(t, pt, bold: bold) > 160) {
      pt -= 0.2;
    }
    text(t, 105, py, pt, bold: bold, color: color, center: true);
  }

  fitted(tr('Bu form Netice ile hazırlandı. Kâğıtları telefonunuzla okutun, sonuçlar ve raporlar saniyeler içinde hazır.'),
      281.6, 7.2,
      bold: true, color: _ink);
  fitted(
      tr('Ücretsiz indirin: Google Play ve App Store\'da "Netice" arayın · {0}',
          ['play.google.com/store/apps/details?id=$androidPackage']),
      285.8, 6.6,
      color: _emerald);
}

void _bubble(PdfGraphics g, double cx, double cy, double r, String label, _FontPicker fonts) {
  g.setStrokeColor(PdfColors.grey600);
  g.setLineWidth(0.7);
  g.drawEllipse(cx, cy, r, r);
  g.strokePath();
  // Harf/rakam belirgin ama dolgudan açık griyle basılır; okuma motoru
  // bunu "boş" sayar (taranmış PDF denemeleriyle doğrulandı).
  g.setFillColor(PdfColors.grey700);
  final (font, shaped) = fonts(label, bold: true);
  final w = font.stringMetrics(shaped).width * 6.6;
  g.drawString(font, 6.6, shaped, cx - w / 2, cy - 2.3);
}

String _f1(double v) => v.toStringAsFixed(1).replaceAll('.', L10n.decimal);
String _f2(double v) => v.toStringAsFixed(2).replaceAll('.', L10n.decimal);
String _pct(double v) => L10n.percent((v * 100).round());
String _letter(int i) => String.fromCharCode(65 + i);
/// Rapor zaman damgası: 18.11.2026 10:04
String reportStamp(DateTime d) =>
    '${_date(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _date(DateTime d) => L10n.date(d);
/// Ölçütlü klasik soruların karnedeki satırları: "K1 · İçerik: Yeterli – açıklama".
List<String> _rubricFeedback(Exam exam, Sheet sheet) => [
      for (var q = 0; q < exam.openQuestions.length; q++)
        if (exam.openQuestions[q].hasRubric && sheet.rubricLevels[q] != null)
          for (var c = 0; c < exam.openQuestions[q].rubric.length && c < sheet.rubricLevels[q]!.length; c++)
            if (sheet.rubricLevels[q]![c] >= 0)
              () {
                final cr = exam.openQuestions[q].rubric[c];
                final l = sheet.rubricLevels[q]![c];
                final d = cr.descriptor(l);
                return '• ${exam.openQuestions[q].label} · ${cr.name}: ${RubricCriterion.levelLabel(l)}${d.isEmpty ? '' : ' – $d'}';
              }(),
    ];

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
    final bold = pw.TextStyle(
      fontSize: school.headerSize,
      color: PdfColors.black,
      fontWeight: school.headerBold ? pw.FontWeight.bold : pw.FontWeight.normal,
      fontStyle: school.headerItalic ? pw.FontStyle.italic : pw.FontStyle.normal,
      decoration: school.headerUnderline ? pw.TextDecoration.underline : null,
    );
    final subject = school.subject.trim().isEmpty ? '' : tr(' {0} DERSİ', [SchoolInfo.upper(school.subject.trim())]);
    final cls = classLine ?? school.classLine(exam.className);
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 14),
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8))),
      child: pw.Column(children: [
        for (final line in school.letterhead)
          pw.Text(line, style: bold, textAlign: pw.TextAlign.center),
        pw.SizedBox(height: 8),
        pw.Text(
          tr('{0} EĞİTİM-ÖĞRETİM YILI {1}{2}', [SchoolInfo.academicYear(exam.date), cls, subject]),
          style: pw.TextStyle(
              fontSize: school.headerSize - 1,
              color: PdfColors.black,
              fontStyle: school.headerItalic ? pw.FontStyle.italic : pw.FontStyle.normal),
          textAlign: pw.TextAlign.center,
        ),
        pw.Text(SchoolInfo.upper(tr(docTitle)), style: bold),
        pw.SizedBox(height: 6),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(headerInfo ?? tr('Sınav: {0} · {1}', [exam.name, _date(exam.date)]),
              style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.black)),
          pw.Text(tr('Tarih: {0}', [_date(createdAt)]), style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.black)),
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
            if (top != null)
              pw.Text(top, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: school.signSize - 0.5)),
            pw.SizedBox(height: 30),
            pw.Text(name.trim().isEmpty ? '..............................' : name.trim(),
                textAlign: pw.TextAlign.center, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: school.signSize)),
            pw.Text(role, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: school.signSize - 1)),
          ]),
        );
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 30),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          sig(school.instructorRole, school.teacher),
          sig(school.headRole, school.principal, top: 'UYGUNDUR\n${_date(createdAt)}'),
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
              institution.isEmpty ? tr('Netice') : institution,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _ink),
            ),
          ],
        ),
        pw.Text(
          headerInfo ?? tr('{0} · {1} · Sınav: {2}', [exam.name, exam.className, _date(exam.date)]),
          style: const pw.TextStyle(color: _muted, fontSize: 9),
        ),
      ],
    ),
  );

  pw.Widget footer(pw.Context ctx) => pw.Column(children: [
    pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(tr('Rapor tarihi: {0}', [created]), style: const pw.TextStyle(color: _muted, fontSize: 8)),
        pw.Text(tr('Sayfa {0} / {1}', [ctx.pageNumber, ctx.pagesCount]), style: const pw.TextStyle(color: _muted, fontSize: 8)),
      ],
    ),
    pw.SizedBox(height: 3),
    brandStrip(),
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

  /// Çocuk sınavlarında sınıfın gelişim grafiği: aynı sınıfın sınavları
  /// eskiden yeniye (ad, ortalama yüzde).
  List<(String, double)> classHistory = const [],
}) async {
  if (exam.kidStyle) {
    return buildKidResultsPdf(exam: exam, results: results, students: students, school: school, classHistory: classHistory);
  }
  final fonts = await _Fonts.load(school.fontFamily);
  final r = ExamReport.build(exam, results);
  final s = r.stats;
  final k = _Kit(exam, school, docTitle: tr('Sınav Analiz Raporu'));
  final max = exam.rule.maxScore;
  final doc = pw.Document(
    theme: fonts.theme,
    title: tr('{0} sınav raporu', [exam.name]),
    author: tr('Netice'),
  );

  final rule = exam.rule.wrongsPerCorrect > 0
      ? tr('{0} yanlış 1 doğruyu götürür', [exam.rule.wrongsPerCorrect])
      : tr('Yanlış götürmez');
  final cancelled = exam.questions.where((q) => q.cancelled).map((q) => q.no).toList();

  doc.addPage(
    pw.MultiPage(textDirection: _dir, 
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
                      tr('SINAV RAPORU'),
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
                      tr('{0} · {1} · {2} soru · {3} şık · {4}{5}', [exam.className, _date(exam.date), exam.questionCount, exam.choiceCount, rule, cancelled.isEmpty ? '' : tr(' · İptal: {0}', [cancelled.join(', ')])]),
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
                    tr('sınıf ortalaması / {0}', [max.round()]),
                    style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 8),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    tr('Rapor tarihi: {0}', [k.created]),
                    style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 7.5),
                  ),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        k.title(tr('Genel istatistikler')),
        k.grid([
          k.statBox(tr('Katılım'), '${s.count}', hint: tr('okunan kâğıt')),
          k.statBox(tr('Ortalama'), _f1(s.mean), hint: tr('Medyan {0}', [_f1(s.median)])),
          k.statBox(tr('Standart sapma'), _f1(s.stdDev), hint: r.cv == null ? null : tr('Değişim katsayısı %{0}', [r.cv!.round()])),
          k.statBox(tr('Başarı oranı'), _pct(r.passRate), hint: tr('{0} ve üzeri alanlar', [exam.rule.pass.round()]), color: _emerald),
          k.statBox(tr('En yüksek'), _f1(s.max), color: _emerald),
          k.statBox(tr('En düşük'), _f1(s.min), color: _coral),
          k.statBox(tr('Açıklık'), _f1(r.range), hint: tr('en yüksek − en düşük')),
          k.statBox(tr('Çeyrekler'), '${_f1(r.q1)} – ${_f1(r.q3)}', hint: tr('öğrencilerin ortadaki yarısı')),
          k.statBox(tr('Ortalama net'), _f2(r.meanNet), hint: tr('{0} soru üzerinden', [r.activeQuestionCount])),
          k.statBox(tr('Ort. D / Y / B'), '${_f1(r.meanCorrect)} / ${_f1(r.meanWrong)} / ${_f1(r.meanBlank)}'),
          k.statBox(
            tr('KR-20 güvenirlik'),
            s.kr20 == null ? '–' : _f2(s.kr20!),
            hint: s.kr20 == null
                ? tr('hesaplanamadı')
                : s.kr20! >= 0.7
                ? tr('kabul edilebilir')
                : tr('düşük'),
          ),
          k.statBox(tr('Ölçme hatası (SEM)'), r.sem == null ? '–' : '±${_f1(r.sem!)}', hint: tr('puan cinsinden')),
          k.statBox(tr('Ortalama güçlük'), _f2(r.meanP), hint: tr('p: doğru oranı')),
          k.statBox(tr('Ort. ayırt edicilik'), _f2(r.meanD), hint: tr('D: üst − alt grup')),
          k.statBox(tr('Üst %27 ortalaması'), _f1(r.upperMean), color: _emerald),
          k.statBox(tr('Alt %27 ortalaması'), _f1(r.lowerMean), color: _coral),
        ]),
        k.title(tr('Grafik özeti')),
        () {
          final c = results.fold<int>(0, (a, x) => a + x.correct);
          final w = results.fold<int>(0, (a, x) => a + x.wrong);
          final b = results.fold<int>(0, (a, x) => a + x.blank);
          final passed = results.where((x) => x.score >= exam.rule.pass).length;
          return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(
                child: _pieBox(tr('Başarı düzeyleri'), [
              for (var i = 0; i < Level.all.length; i++) (Level.all[i].name, r.levelCounts[i].toDouble(), _levelColor(i)),
            ])),
            pw.SizedBox(width: 6),
            pw.Expanded(
                child: _pieBox(tr('Cevaplar'), [
              (tr('Doğru'), c.toDouble(), _emerald),
              (tr('Yanlış'), w.toDouble(), _coral),
              (tr('Boş'), b.toDouble(), _gray),
            ], donut: true)),
            pw.SizedBox(width: 6),
            pw.Expanded(
                child: _pieBox(tr('Geçme durumu'), [
              (tr('Geçti'), passed.toDouble(), _emerald),
              (tr('Geçemedi'), (results.length - passed).toDouble(), _coral),
            ], donut: true)),
            pw.SizedBox(width: 6),
            pw.Expanded(
                child: _pieBox(tr('Soru güçlüğü'), [
              (tr('Kolay'), (r.difficultyCounts[tr('Kolay')] ?? 0).toDouble(), _emerald),
              (tr('Orta'), (r.difficultyCounts[tr('Orta')] ?? 0).toDouble(), _ink),
              (tr('Zor'), (r.difficultyCounts[tr('Zor')] ?? 0).toDouble(), _coral),
            ], donut: true)),
          ]);
        }(),
        k.title(tr('Otomatik değerlendirme')),
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
        () {
          final plan = classActionPlan(r, students);
          if (plan.isEmpty) return pw.SizedBox();
          return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            k.title(tr('Ne yapmalı? Eylem planı')),
            for (var i = 0; i < plan.length; i++)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.SizedBox(
                      width: 14,
                      child: pw.Text('${i + 1}.', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _emerald))),
                  pw.Expanded(
                    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                      pw.Text(plan[i].title, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                      pw.Text(plan[i].detail, style: const pw.TextStyle(fontSize: 8.5)),
                    ]),
                  ),
                ]),
              ),
          ]);
        }(),
        pw.SizedBox(height: 6),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 3,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  k.title(tr('Puan dağılımı'), tr('Tam puana göre yüzdelik dilimlerde öğrenci sayısı')),
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
                  k.title(tr('Başarı düzeyleri')),
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
                          pw.Expanded(child: k.hbar(s.count == 0 ? 0 : r.levelCounts[i] / s.count, _levelColor(i))),
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
              tr('Soru güçlük grafiği'),
              tr('Her sorunun doğru cevaplanma oranı · yeşil: kolay, lacivert: orta, mercan: zor'),
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
                  k.title(tr('Soru güçlüğü')),
                  k.table(
                    [tr('Kolay'), tr('Orta'), tr('Zor')],
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
                  k.title(tr('Ayırt edicilik')),
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
          k.title(tr('Kazanım / konu analizi'), tr('Sınıfın her kazanımdaki doğru oranı')),
          for (final o in [...r.outcomes]..sort((a, b) => a.rate.compareTo(b.rate)))
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 5),
              child: pw.Row(
                children: [
                  pw.SizedBox(
                    width: 150,
                    child: pw.Text(
                      '${o.code}  (${tr('{0} soru', [o.questionNos.length])})',
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
        if (Misconceptions.any(exam) && results.isNotEmpty) ...[
          k.title(tr('Kavram yanılgıları'), tr('Yanlış şıklara yazılan yanılgılar ve bu şıkları seçen öğrenci sayısı')),
          k.table(
            [tr('Yanılgı'), tr('Soru / şık'), tr('Öğrenci'), tr('Oran')],
            [
              for (final f in Misconceptions.of(exam, [for (final x in results) x.sheet]))
                [
                  f.text,
                  f.sources.map((x) => '${x.$1}${_letter(x.$2)}').join(', '),
                  '${f.students.length}',
                  _pct(f.students.length / results.length),
                ],
            ],
            leftColumn: 0,
            widths: {0: const pw.FlexColumnWidth(4)},
          ),
        ],
        if (r.outcomes.isNotEmpty) ...[
          pw.NewPage(),
          k.title(tr('Kazanım ısı haritası'), tr('Her öğrencinin her kazanımdaki doğru oranı · yeşil ≥ %70 · sarı %50–69 · mercan < %50')),
          _heatmap(r, students),
        ],
        pw.NewPage(),
        k.title(
          tr('Sınıf sonuç listesi'),
          tr('Yüzdelik: sınıfın yüzde kaçından daha başarılı · T: ortalaması 50, sapması 10 olan standart puan'),
        ),
        k.table(
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
          leftColumn: 1,
          widths: {1: const pw.FlexColumnWidth(4)},
        ),
        pw.NewPage(),
        k.title(
          tr('Madde analizi'),
          tr('p = doğru oranı (güçlük) · D = ayırt edicilik (üst %27 − alt %27) · Değerler öğretmene yol gösteren uyarılardır.'),
        ),
        k.table(
          [
            tr('Soru'),
            tr('Anahtar'),
            if (r.outcomes.isNotEmpty) tr('Kazanım'),
            'p',
            'D',
            for (var c = 0; c < exam.choiceCount; c++) _letter(c),
            tr('Boş'),
            tr('Yorum'),
          ],
          [
            for (final it in r.items)
              () {
                final q = exam.questions[it.no - 1];
                return [
                  '${it.no}',
                  q.cancelled ? tr('İptal') : q.correct.map(_letter).join('/'),
                  if (r.outcomes.isNotEmpty) q.outcomeCode ?? '',
                  _f2(it.p),
                  _f2(it.d),
                  for (var c = 0; c < exam.choiceCount; c++)
                    q.correct.contains(c) ? '${it.choiceCounts[c]}*' : '${it.choiceCounts[c]}',
                  '${it.blankCount}',
                  it.suspiciousChoice != null
                      ? tr('Üst grup {0} seçti; anahtarı kontrol edin', [_letter(it.suspiciousChoice!)])
                      : '${it.difficultyLabel} · ${it.discriminationLabel}'
                          '${it.nonFunctional.isEmpty ? '' : ' · ${tr('İşlevsiz: {0}', [it.nonFunctional.map(_letter).join('/')])}'}',
                ];
              }(),
          ],
          fontSize: 7.5,
          widths: {(r.outcomes.isNotEmpty ? 6 : 5) + exam.choiceCount: const pw.FlexColumnWidth(4.5)},
        ),
        pw.SizedBox(height: 4),
        pw.Text(tr('* doğru şık'), style: const pw.TextStyle(color: _muted, fontSize: 7)),
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

  /// Öğrenci kimliği → tüm sınavlarına bakılarak yazılmış gelişim notu.
  Map<String, List<String>> notes = const {},

  /// Öğrenci kimliği → çalışması gereken konular (konu, başarı, hap bilgiler).
  Map<String, List<(String, double, List<String>)>> studyTopics = const {},

  /// Çocuk sınavlarında gelişim grafiği için öğrencinin tüm sınavları.
  Map<String, List<HistoryEntry>> history = const {},
}) async {
  if (exam.kidStyle) {
    return buildKidStudentCardsPdf(
        exam: exam,
        results: results,
        students: students,
        school: school,
        onlyStudentId: onlyStudentId,
        notes: notes,
        studyTopics: studyTopics,
        history: history);
  }
  final fonts = await _Fonts.load(school.fontFamily);
  final r = ExamReport.build(exam, results);
  final k = _Kit(exam, school, docTitle: tr('Öğrenci Sınav Karnesi'), letterheadEveryPage: true);
  final max = exam.rule.maxScore;
  final doc = pw.Document(
    theme: fonts.theme,
    title: tr('{0} öğrenci karneleri', [exam.name]),
    author: tr('Netice'),
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
      pw.Page(textDirection: _dir, 
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
                          tr('ÖĞRENCİ KARNESİ'),
                          style: pw.TextStyle(
                            color: _emerald,
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          stu?.fullName ?? tr('Eşleşmeyen kâğıt'),
                          style: pw.TextStyle(color: PdfColors.white, fontSize: 18, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Text(
                          '${tr('No')} ${stu?.number ?? '–'} · ${stu?.className ?? exam.className} · ${exam.name}',
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
                        '${tr('puan / {0}', [max.round()])} · ${st.level.name}',
                        style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 8),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
            k.grid([
              k.statBox(tr('Sınıf sırası'), '${st.rank} / ${r.standings.length}'),
              k.statBox(tr('Yüzdelik'), L10n.percent(st.percentile.round()), hint: tr('sınıfın bu kadarından başarılı')),
              k.statBox(tr('T puanı'), _f1(st.t), hint: tr('50 = sınıf ortalaması')),
              k.statBox(tr('Net'), _f2(res.net)),
              k.statBox(tr('Doğru'), '${res.correct}', color: _emerald),
              k.statBox(tr('Yanlış'), '${res.wrong}', color: _coral),
              k.statBox(tr('Boş'), '${res.blank}', color: _gray),
              k.statBox(tr('Başarı'), L10n.percent(st.pct.round())),
              if (stu?.goal != null)
                k.statBox(tr('Kişisel hedef'), L10n.percent(stu!.goal!.round()),
                    hint: st.pct >= stu.goal! ? tr('hedefe ulaştı') : tr('hedefe {0} puan kaldı', [(stu.goal! - st.pct).ceil()]),
                    color: st.pct >= stu.goal! ? _emerald : _amber),
              if (exam.hasOpen) ...[
                k.statBox(tr('Test kısmı'), '${_f1(res.testScore)} / ${_f1(exam.testMax)}'),
                k.statBox(tr('Klasik kısım'), res.openMissing ? tr('eksik') : '${_f1(res.openScore)} / ${_f1(exam.openMax)}'),
                for (var i = 0; i < exam.openQuestions.length && i < 2; i++)
                  k.statBox(exam.openQuestions[i].label,
                      i < res.sheet.openScores.length && res.sheet.openScores[i] != null
                          ? '${_f1(res.sheet.openScores[i]!)} / ${_f1(exam.openQuestions[i].maxPoints)}'
                          : '–'),
              ],
            ]),
            k.title(tr('Sınıfla karşılaştırma')),
            compare(tr('Öğrenci'), res.score, _emerald),
            compare(tr('Sınıf ortalaması'), r.stats.mean, _ink),
            compare(tr('En yüksek puan'), r.stats.max, _gray),
            if (r.outcomes.isNotEmpty) ...[
              k.title(tr('Kazanım / konu başarısı'), tr('Öğrenci (yeşil) ve sınıf (lacivert) doğru oranı')),
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
            k.title(tr('Cevaplar'), tr('Yeşil: doğru · mercan: yanlış · gri: boş/iptal · parantez içinde doğru cevap')),
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
                              : '${_answer(res.sheet.answers[i])} (${exam.questionAt(res.sheet.booklet, i).correct.map(_letter).join('/')})',
                          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if ((notes[res.sheet.studentId] ?? const []).isNotEmpty) ...[
              k.title(tr('Gelişim notu')),
              pw.Text(notes[res.sheet.studentId]!.take(4).join(' '), style: const pw.TextStyle(fontSize: 8.5)),
            ],
            if ((studyTopics[res.sheet.studentId] ?? const []).isNotEmpty) ...[
              k.title(tr('Çalışması gereken konular')),
              for (final (topic, rate, tips) in studyTopics[res.sheet.studentId]!.take(3))
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text('$topic  ·  ${L10n.percent((rate * 100).round())}',
                        style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                    for (final t in tips.take(2))
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(left: 8, top: 1.5),
                        child: pw.Text('• $t', style: const pw.TextStyle(fontSize: 8)),
                      ),
                  ]),
                ),
            ],
            if (_rubricFeedback(exam, res.sheet).isNotEmpty) ...[
              k.title(tr('Ölçütlü geri bildirim'), tr('Klasik soruların ölçütlere göre değerlendirmesi')),
              for (final line in _rubricFeedback(exam, res.sheet).take(6))
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 2),
                  child: pw.Text(line, style: const pw.TextStyle(fontSize: 8.5)),
                ),
            ],
            if (Misconceptions.ofSheet(exam, res.sheet).isNotEmpty) ...[
              k.title(tr('Dikkat edilecek kavram yanılgıları'), tr('Seçtiği yanlış şıklardan çıkarıldı')),
              for (final m in Misconceptions.ofSheet(exam, res.sheet).take(3))
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 2),
                  child: pw.Text('• $m', style: const pw.TextStyle(fontSize: 8.5)),
                ),
            ],
            if (wrongs.isNotEmpty) ...[
              k.title(tr('Tekrar edilmesi önerilen sorular')),
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
    doc.addPage(pw.Page(textDirection: _dir, build: (_) => pw.Center(child: pw.Text(tr('Henüz okunan kâğıt yok.')))));
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
            child: pw.Text(tr('Öğrenci'), style: pw.TextStyle(color: PdfColors.white, fontSize: 7, fontWeight: pw.FontWeight.bold)),
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
          cell(students[st.result.sheet.studentId]?.fullName ?? tr('Eşleşmedi'), align: pw.Alignment.centerLeft),
          for (final o in codes)
            () {
              final v = o.rateOf(exam, st.result);
              return cell(L10n.percent((v * 100).round()), color: _heatColor(v));
            }(),
        ]),
      pw.TableRow(children: [
        cell(tr('Sınıf'), bold: true, align: pw.Alignment.centerLeft),
        for (final o in codes) cell(L10n.percent((o.rate * 100).round()), color: _heatColor(o.rate), bold: true),
      ]),
    ],
  );
}

/// Şube karşılaştırma raporu.
Future<Uint8List> buildComparePdf(List<BranchRow> rows,
    {SchoolInfo school = const SchoolInfo(), Map<String, Student>? students}) async {
  final fonts = await _Fonts.load(school.fontFamily);
  final k = _Kit(rows.first.exam, school,
      headerInfo: tr('Şube karşılaştırması · {0}', [rows.map((r) => r.exam.className).join(', ')]),
      docTitle: tr('Şube Karşılaştırma Raporu'),
      classLine: tr('{0} ŞUBELERİ', [rows.map((r) => SchoolInfo.upper(r.exam.className)).toSet().join(', ')]));
  final doc = pw.Document(
      theme: fonts.theme, title: tr('Şube karşılaştırması'), author: tr('Netice'));
  final best = rows.reduce((a, b) => a.report.stats.mean >= b.report.stats.mean ? a : b);
  final sameShape = rows.every((r) => r.exam.questionCount == rows.first.exam.questionCount);
  final codes = {for (final r in rows) ...r.report.outcomes.map((o) => o.code)}.toList();
  // Tüm şubeler birlikte (ortak sınav): genel ortalama, başarı ve sıralama.
  final all = [
    for (final r in rows)
      for (final st in r.report.standings) (r, st),
  ]..sort((a, b) => b.$2.pct.compareTo(a.$2.pct));
  final total = all.length;
  final allMean = total == 0 ? 0.0 : all.map((x) => x.$2.result.score).reduce((a, b) => a + b) / total;
  final allPass = total == 0 ? 0.0 : all.where((x) => x.$2.result.score >= x.$1.exam.rule.pass).length / total;
  doc.addPage(pw.MultiPage(textDirection: _dir, 
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 30),
    header: (ctx) => k.header(ctx),
    footer: k.footer,
    build: (ctx) => [
      k.title(tr('Şube karşılaştırması'), rows.map((r) => '${r.exam.name} (${r.exam.className})').join(' · ')),
      k.barChart(
        [for (final r in rows) r.report.stats.mean],
        [for (final r in rows) r.exam.className],
        maxValue: rows.map((r) => r.exam.rule.maxScore).reduce(math.max),
        colors: [for (final r in rows) identical(r, best) ? _emerald : _ink],
        height: 110,
      ),
      pw.SizedBox(height: 8),
      k.table(
        [tr('Şube'), tr('Sınav'), tr('Kişi'), tr('Ortalama'), tr('Medyan'), tr('Std.'), tr('Başarı'), tr('En yüksek'), tr('En düşük'), 'KR-20'],
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
            ],
          if (students != null && rows.length >= 2)
            [tr('Tüm şubeler'), rows.first.exam.name, '$total', _f1(allMean), '–', '–', _pct(allPass), '–', '–', '–'],
        ],
        leftColumn: 1,
        widths: {1: const pw.FlexColumnWidth(3)},
      ),
      if (codes.isNotEmpty) ...[
        k.title(tr('Kazanım başarısı (%)')),
        k.table(
          [tr('Kazanım'), for (final r in rows) r.exam.className],
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
        k.title(tr('Soru bazında doğru oranı (%)')),
        k.table(
          [tr('Şube'), for (var q = 0; q < rows.first.exam.questionCount; q++) '${q + 1}'],
          [
            for (final r in rows) [r.exam.className, for (final it in r.report.items) '${(it.p * 100).round()}']
          ],
          fontSize: rows.first.exam.questionCount > 25 ? 5.5 : 7,
        ),
      ],
      if (students != null && all.isNotEmpty) ...[
        k.title(tr('Genel sıralama (tüm şubeler)'), tr('İlk {0} öğrenci', [math.min(20, total)])),
        k.table(
          [tr('Sıra'), tr('Öğrenci'), tr('Şube'), tr('Puan'), tr('Başarı')],
          [
            for (var i = 0; i < math.min(20, total); i++)
              [
                '${i + 1}',
                students[all[i].$2.result.sheet.studentId]?.fullName ?? '–',
                all[i].$1.exam.className,
                _f1(all[i].$2.result.score),
                _pct(all[i].$2.pct / 100),
              ]
          ],
          leftColumn: 1,
          widths: {1: const pw.FlexColumnWidth(3)},
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
  final fonts = await _Fonts.load(school.fontFamily);
  final k = _Kit(exam, school, docTitle: tr('Not Giriş Listesi'));
  final doc = pw.Document(
      theme: fonts.theme, title: tr('{0} e-Okul listesi', [exam.name]), author: tr('Netice'));
  final rows = eokulRows(exam, results, classStudents);
  doc.addPage(pw.MultiPage(textDirection: _dir, 
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 30),
    header: k.header,
    footer: k.footer,
    build: (ctx) => [
      k.title(tr('e-Okul not giriş listesi'), tr('Okul numarasına göre sıralı · puanlar tam sayıya yuvarlandı · {0} üzerinden', [exam.rule.maxScore.round()])),
      k.table(
        [tr('Sıra'), tr('Okul No'), tr('Ad Soyad'), tr('Puan'), tr('Not')],
        [
          for (var i = 0; i < rows.length; i++)
            [
              '${i + 1}',
              rows[i].$1.number,
              rows[i].$1.fullName,
              rows[i].$2 == null ? tr('G') : '${rows[i].$2}',
              rows[i].$2 == null ? tr('Sınava girmedi') : '',
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
      theme: fonts.theme, title: tr('{0} sonuç etiketleri', [exam.name]), author: tr('Netice'));
  final sorted = [...results]..sort((a, b) => (students[a.sheet.studentId]?.fullName ?? '~')
      .compareTo(students[b.sheet.studentId]?.fullName ?? '~'));
  const perPage = 24;
  const mm = PdfPageFormat.mm;
  for (var p = 0; p < sorted.length; p += perPage) {
    final page = sorted.skip(p).take(perPage).toList();
    doc.addPage(pw.Page(textDirection: _dir, 
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
                    child: pw.Text(st?.fullName ?? tr('Eşleşmeyen kâğıt'),
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
                      pw.Text('${tr('D')} ${r.correct}   ${tr('Y')} ${r.wrong}   ${tr('B')} ${r.blank}', style: const pw.TextStyle(fontSize: 8)),
                      pw.Text(tr('Net {0}', [_f2(r.net)]), style: const pw.TextStyle(fontSize: 8, color: _muted)),
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
  if (sorted.isEmpty) doc.addPage(pw.Page(textDirection: _dir, build: (_) => pw.Center(child: pw.Text(tr('Henüz okunan kâğıt yok.')))));
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
            pw.Text('${d.$2.round()} · ${total == 0 ? L10n.percent(0) : L10n.percent((d.$2 / total * 100).round())}',
                style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
          ]),
        ),
    ]),
  );
}

/// Paylaşılan her belgenin altındaki uygulama ve indirme bilgisi.
// Sağdan sola metin düzenleyicisi "…" karakterinde hata veriyor; Arapçada üç nokta kullanılır.
String _short(String s, [int n = 14]) => s.length <= n ? s : '${s.substring(0, n - 1)}${L10n.rtl ? '...' : '…'}';

_Kit _termKit(TermReport t, SchoolInfo school, String docTitle, {bool everyPage = false}) => _Kit(
      t.exams.last.exam,
      school,
      docTitle: docTitle,
      headerInfo: tr('{0} · {1} · {2} sınav', [t.term.label, t.className, t.exams.length]),
      classLine: school.classLine(t.className),
      letterheadEveryPage: everyPage,
    );

/// Dönem sonu not çizelgesi: her öğrencinin seçilen sınavlardaki puanı
/// (100 üzerinden), ağırlıklı ortalaması ve e-Okul'a girilecek tam sayı not.
Future<Uint8List> buildTermGradesPdf(TermReport t, {SchoolInfo school = const SchoolInfo()}) async {
  final fonts = await _Fonts.load(school.fontFamily);
  final k = _termKit(t, school, tr('Dönem Sonu Not Çizelgesi'));
  final doc = pw.Document(
      theme: fonts.theme, title: tr('Dönem not çizelgesi'), author: tr('Netice'));
  final equal = t.exams.every((e) => e.weight == t.exams.first.weight);
  final totalW = t.exams.fold<double>(0, (a, e) => a + e.weight);
  final graded = t.rows.where((r) => r.average != null).toList();
  doc.addPage(pw.MultiPage(textDirection: _dir, 
    pageFormat: t.exams.length > 5 ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 30),
    header: k.header,
    footer: k.footer,
    build: (ctx) => [
      k.title(tr('Dönem sonu not çizelgesi'),
          tr('{0} · puanlar 100 üzerinden · {1} · girilmeyen sınav ortalamaya katılmaz', [t.term.label, equal ? tr('sınavlar eşit ağırlıklı') : tr('ağırlıklı ortalama')])),
      k.grid([
        k.statBox(tr('Öğrenci'), '${t.rows.length}', hint: tr('{0} öğrencinin notu var', [graded.length])),
        k.statBox(tr('Sınav'), '${t.exams.length}'),
        k.statBox(tr('Sınıf ortalaması'), _f1(t.classAverage), color: _emerald),
        k.statBox(tr('En yüksek'), graded.isEmpty ? '–' : '${graded.map((r) => r.grade!).reduce(math.max)}'),
      ]),
      pw.SizedBox(height: 4),
      k.table(
        [tr('Sınav'), tr('Tarih'), tr('Ağırlık'), tr('Katılım'), tr('Sınıf ort. (100)')],
        [
          for (final e in t.exams)
            [
              e.exam.name,
              _date(e.exam.date),
              totalW == 0 ? '–' : L10n.percent((e.weight / totalW * 100).round()),
              '${e.report.results.length}',
              _f1(e.mean100),
            ]
        ],
        leftColumn: 0,
        widths: {0: const pw.FlexColumnWidth(4)},
      ),
      pw.SizedBox(height: 10),
      k.table(
        [tr('No'), tr('Ad Soyad'), for (var i = 0; i < t.exams.length; i++) '${i + 1}. ${_short(t.exams[i].exam.name, 12)}', tr('Ortalama'), tr('Dönem notu')],
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
        leftColumn: 1,
        widths: {1: const pw.FlexColumnWidth(3.5)},
        fontSize: t.exams.length > 6 ? 7 : 8.5,
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6),
        child: pw.Text(tr('G: sınava girmedi. Dönem notu, ortalamanın tam sayıya yuvarlanmış hâlidir.'),
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
  // Dönemin bütün sınavları çocuk görünümündeyse çocuk dönem karnesi.
  if (t.exams.isNotEmpty && t.exams.every((e) => e.exam.kidStyle)) {
    return buildKidTermCardsPdf(t, school: school, onlyStudentId: onlyStudentId);
  }
  final fonts = await _Fonts.load(school.fontFamily);
  final k = _termKit(t, school, tr('Dönem Kazanım Karnesi'), everyPage: true);
  final doc = pw.Document(
      theme: fonts.theme, title: tr('Dönem kazanım karnesi'), author: tr('Netice'));
  final rows = t.rows.where((r) => r.average != null && (onlyStudentId == null || r.student.id == onlyStudentId)).toList();
  if (rows.isEmpty) {
    doc.addPage(pw.Page(textDirection: _dir, build: (_) => pw.Center(child: pw.Text(tr('Bu dönemde sonucu olan öğrenci yok.')))));
    return doc.save();
  }
  PdfColor tone(double v) => v >= 0.7 ? _emerald : (v >= 0.5 ? _amber : _coral);

  for (final r in rows) {
    final out = r.outcomes.entries.toList()..sort((a, b) => b.value.$1.compareTo(a.value.$1));
    final strong = out.where((e) => e.value.$1 >= 0.7).map((e) => e.key).take(4).toList();
    final weak = out.reversed.where((e) => e.value.$1 < 0.5).map((e) => e.key).take(4).toList();
    final taken = [for (var i = 0; i < t.exams.length; i++) if (r.scores[i] != null) i];
    doc.addPage(pw.Page(textDirection: _dir, 
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
                pw.Text(tr('DÖNEM KAZANIM KARNESİ'),
                    style: pw.TextStyle(color: _emerald, fontSize: 8, fontWeight: pw.FontWeight.bold, letterSpacing: 1.5)),
                pw.SizedBox(height: 4),
                pw.Text(r.student.fullName,
                    style: pw.TextStyle(color: PdfColors.white, fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.Text('${tr('No')} ${r.student.number} · ${r.student.className} · ${t.term.label}',
                    style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 9)),
              ]),
            ),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('${r.grade}', style: pw.TextStyle(color: PdfColors.white, fontSize: 30, fontWeight: pw.FontWeight.bold)),
              pw.Text(tr('dönem ortalaması · sınıf {0}', [_f1(t.classAverage)]),
                  style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 8)),
            ]),
          ]),
        ),
        pw.SizedBox(height: 12),
        k.title(tr('Sınavlar'), tr('{0} / {1} sınava katıldı · puanlar 100 üzerinden', [r.taken, t.exams.length])),
        k.table(
          [tr('Sınav'), tr('Tarih'), tr('Puan'), tr('Sınıf ort.'), tr('Fark')],
          [
            for (var i = 0; i < t.exams.length; i++)
              [
                t.exams[i].exam.name,
                _date(t.exams[i].exam.date),
                r.scores[i] == null ? tr('Girmedi') : _f1(r.scores[i]!),
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
          k.title(tr('Gelişim')),
          k.barChart(
            [for (final i in taken) r.scores[i]!],
            [for (final i in taken) _date(t.exams[i].exam.date)],
            maxValue: 100,
            height: 70,
            colors: [for (final i in taken) r.scores[i]! >= t.exams[i].mean100 ? _emerald : _ink],
          ),
        ],
        if (out.isNotEmpty) ...[
          k.title(tr('Kazanımlar'), tr('Dönem boyunca bu kazanıma ait sorulardaki doğru oranı · çizgi: öğrenci, sağdaki: sınıf')),
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
                    child: pw.Text(tr('sınıf {0}', [_pct(e.value.$2)]),
                        textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 7, color: _muted))),
              ]),
            ),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(color: _ivory, borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(tr('Güçlü yönler: {0}', [strong.isEmpty ? tr('Henüz belirgin değil.') : strong.join(', ')]),
                  style: const pw.TextStyle(fontSize: 8.5)),
              pw.SizedBox(height: 3),
              pw.Text(tr('Çalışılması önerilen: {0}', [weak.isEmpty ? tr('Belirgin bir eksik görünmüyor.') : weak.join(', ')]),
                  style: const pw.TextStyle(fontSize: 8.5)),
            ]),
          ),
        ] else
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 10),
            child: pw.Text(tr('Sınavlarda kazanım kodu girilmediği için kazanım analizi yapılamadı.'),
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


/// Genel istatistik raporu: tüm sınıflar ve sınava giren tüm öğrenciler.
Future<Uint8List> buildOverviewPdf(Overview ov, {SchoolInfo school = const SchoolInfo(), String filter = ''}) async {
  final fonts = await _Fonts.load(school.fontFamily);
  final k = _Kit(ov.exams.first, school,
      headerInfo: tr('Genel istatistik · {0}', [filter]),
      docTitle: tr('Genel İstatistik Raporu'),
      classLine: SchoolInfo.upper(ov.classes.map((c) => c.name).join(', ')));
  final doc = pw.Document(theme: fonts.theme, title: tr('Genel istatistik'), author: tr('Netice'));
  String p(double v) => L10n.percent(v.round());
  final d = ov.dist;
  doc.addPage(pw.MultiPage(
    textDirection: _dir,
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 30),
    header: (ctx) => k.header(ctx),
    footer: k.footer,
    build: (ctx) => [
      k.title(tr('Genel istatistik'), filter),
      k.grid([
        k.statBox(tr('Genel başarı'), p(d.mean), hint: tr('Medyan {0}', [p(d.median)]), color: _emerald),
        k.statBox(tr('Sınav'), '${ov.exams.length}', hint: tr('{0} kâğıt', [ov.sheets])),
        k.statBox(tr('Öğrenci'), '${ov.participants}',
            hint: ov.participation == null ? null : tr('Katılım {0}', [p(ov.participation! * 100)])),
        k.statBox(tr('Geçme oranı'), _pct(ov.passRate)),
        k.statBox(tr('Std. sapma'), _f1(d.std)),
        k.statBox(tr('En yüksek'), p(d.max), hint: tr('En düşük {0}', [p(d.min)])),
        k.statBox(tr('Doğru oranı'), _pct(ov.correctRate),
            hint: tr('Yanlış {0} · boş {1}', [_pct(ov.wrongRate), _pct(ov.blankRate)])),
        k.statBox(tr('Sınıf'), '${ov.classes.length}',
            hint: ov.classes.length < 2 ? null : tr('Fark {0} puan', [ov.classGap.round()])),
      ]),
      pw.SizedBox(height: 4),
      for (final c in ov.comments)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Text('• $c', style: const pw.TextStyle(fontSize: 8.5)),
        ),
      k.title(tr('Puan dağılımı (%)')),
      k.barChart(
        [for (final v in ov.histogram10) v.toDouble()],
        [for (var i = 0; i < 10; i++) '${i * 10}'],
        valueText: (v) => '${v.round()}',
        colors: [for (var i = 0; i < 10; i++) i >= 8 ? _emerald : i >= 5 ? _ink : i >= 3 ? _amber : _coral],
        height: 80,
      ),
      k.title(tr('Sınıf sıralaması')),
      k.table(
        [tr('Sıra'), tr('Sınıf'), tr('Sınav'), tr('Kâğıt'), tr('Ortalama'), tr('Medyan'), tr('Std.'), tr('Başarı'), tr('Katılım'), tr('Değişim')],
        [
          for (final (i, c) in ov.classes.indexed)
            [
              '${i + 1}',
              c.name,
              '${c.examCount}',
              '${c.sheets}',
              p(c.dist.mean),
              p(c.dist.median),
              _f1(c.dist.std),
              _pct(c.passRate),
              c.participation == null ? '–' : _pct(c.participation!),
              c.trend == null ? '–' : '${c.trend! >= 0 ? '+' : '−'}${c.trend!.abs().round()}',
            ]
        ],
        leftColumn: 1,
      ),
      k.title(tr('Başarı düzeyleri')),
      k.table(
        [for (final l in Level.all) l.name],
        [
          [for (final n in ov.levelCounts) '$n (${ov.sheets == 0 ? '–' : _pct(n / ov.sheets)})']
        ],
      ),
      if (ov.students.isNotEmpty) ...[
        k.title(tr('En başarılı öğrenciler'), tr('İlk {0} öğrenci', [math.min(15, ov.students.length)])),
        k.table(
          [tr('Sıra'), tr('Öğrenci'), tr('Sınıf'), tr('Sınav'), tr('Ortalama')],
          [
            for (final (i, s) in ov.top.take(15).indexed)
              ['${i + 1}', s.student.fullName, s.student.className, '${s.count}', p(s.average)]
          ],
          leftColumn: 1,
          widths: {1: const pw.FlexColumnWidth(3)},
        ),
      ],
      if (ov.improved.isNotEmpty) ...[
        k.title(tr('En çok gelişenler')),
        k.table(
          [tr('Öğrenci'), tr('Sınıf'), tr('İlk'), tr('Son'), tr('Değişim')],
          [
            for (final s in ov.improved.take(10))
              [s.student.fullName, s.student.className, p(s.first), p(s.last), '+${s.change.round()}']
          ],
          leftColumn: 0,
          widths: {0: const pw.FlexColumnWidth(3)},
        ),
      ],
      if (ov.outcomes.isNotEmpty) ...[
        k.title(tr('Kazanım başarısı (%)')),
        k.table(
          [tr('Kazanım'), tr('Sınav'), tr('Kâğıt'), tr('Başarı')],
          [
            for (final o in ov.outcomes) [o.code, '${o.exams}', '${o.students}', _pct(o.rate)]
          ],
          leftColumn: 0,
          widths: {0: const pw.FlexColumnWidth(4)},
        ),
      ],
      k.title(tr('Sınavlar')),
      k.table(
        [tr('Tarih'), tr('Sınav'), tr('Sınıf'), tr('Kişi'), tr('Ortalama'), tr('Başarı')],
        [
          for (final x in ov.timeline)
            [L10n.date(x.exam.date), x.exam.name, x.exam.className, '${x.n}', p(x.mean), _pct(x.passRate)]
        ],
        leftColumn: 1,
        widths: {1: const pw.FlexColumnWidth(3)},
      ),
      k.signatures(),
    ],
  ));
  return doc.save();
}

// ---------------------------------------------------------------------------
// Çeyrek A4 kısa quiz formu

/// Bir A4 sayfaya dört kısa quiz formu (çeyrek A4 / A6) basar. Kesik çizgiden
/// kesilip dağıtılır. [students] boşsa [blankCopies] adet boş form üretilir
/// (dördün katına tamamlanır).
Future<Uint8List> buildMiniFormsPdf(Exam exam, List<Student> students,
    {int blankCopies = 4, SchoolInfo school = const SchoolInfo()}) async {
  final fonts = await _Fonts.load();
  final layout = MiniFormLayout(questionCount: exam.questionCount, choiceCount: exam.choiceCount, digits: exam.numberDigits);
  final doc = pw.Document(theme: fonts.theme, title: tr('{0} · kısa quiz formu', [exam.name]), author: tr('Netice'));
  final slips = students.isEmpty
      ? List<Student?>.filled(((math.max(1, blankCopies) + 3) ~/ 4) * 4, null)
      : students.cast<Student?>();
  for (var p = 0; p < slips.length; p += 4) {
    final page = slips.sublist(p, math.min(p + 4, slips.length));
    doc.addPage(pw.Page(
      textDirection: _dir,
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (ctx) => pw.CustomPaint(
        size: PdfPoint(PdfPageFormat.a4.width, PdfPageFormat.a4.height),
        painter: (canvas, size) {
          for (var i = 0; i < page.length; i++) {
            _paintMiniForm(canvas, size, layout, exam, page[i], (String t, {bool bold = false}) => fonts.pick(ctx, t, bold: bold),
                ox: (i % 2) * FormLayout.pageWidth / 2, oy: (i ~/ 2) * FormLayout.pageHeight / 2, school: school);
          }
          // Kesim çizgileri.
          const mm = PdfPageFormat.mm;
          canvas.setStrokeColor(_gray);
          canvas.setLineWidth(0.5);
          canvas.setLineDashPattern([3, 3]);
          canvas.drawLine(105 * mm, 0, 105 * mm, size.y);
          canvas.drawLine(0, size.y - 148.5 * mm, size.x, size.y - 148.5 * mm);
          canvas.strokePath();
          canvas.setLineDashPattern();
        },
      ),
    ));
  }
  return doc.save();
}

/// Kısa formun QR koduna yazılan bilgi (telefon kamerasıyla okunduğunda
/// kâğıdın hangi quize ve öğrenciye ait olduğunu gösterir).
String miniFormQrText(Exam exam, Student? s) => [
      'NETICE QUIZ',
      exam.name.length > 40 ? exam.name.substring(0, 40) : exam.name,
      '${exam.className} · ${_date(exam.date)}',
      if (s != null) '${s.fullName} · ${s.number}',
      tr('Sınav kodu: {0}', [FormCode.examCodeOf(exam.id)]),
    ].join('\n');

/// Tek kısa formu, A4 sayfanın ([ox], [oy]) mm'den başlayan çeyreğine çizer.
/// Form birimleri [MiniFormLayout.printScale] ile küçültülür.
void _paintMiniForm(PdfGraphics g, PdfPoint size, MiniFormLayout layout, Exam exam, Student? s, _FontPicker fonts,
    {required double ox, required double oy, SchoolInfo school = const SchoolInfo()}) {
  const mm = PdfPageFormat.mm;
  const k = MiniFormLayout.printScale;
  double x(double u) => (ox + u * k) * mm;
  double y(double u) => size.y - (oy + u * k) * mm;

  double width(String t, double pt, {bool bold = false}) {
    final (font, shaped) = fonts(t, bold: bold);
    return font.stringMetrics(shaped).width * pt / mm / k; // form birimiyle
  }

  double fitPt(String t, double pt, double maxW, {bool bold = false}) {
    while (pt > 3.6 && width(t, pt, bold: bold) > maxW) {
      pt -= 0.2;
    }
    return pt;
  }

  void text(String t, double px, double py, double pt,
      {bool bold = false, PdfColor color = _ink, bool right = false, bool center = false}) {
    final (font, shaped) = fonts(t, bold: bold);
    final w = width(t, pt, bold: bold);
    final left = right ? px - w : (center ? px - w / 2 : px);
    g.setFillColor(color);
    g.drawString(font, pt, shaped, x(left), y(py));
  }

  void box(double x0, double y0, double x1, double y1,
      {PdfColor? stroke = _frame, PdfColor? fill, double radius = 2.4, double line = 0.45}) {
    final w = (x1 - x0) * k * mm, h = (y1 - y0) * k * mm, r = radius * k * mm;
    if (fill != null) {
      g.setFillColor(fill);
      g.drawRRect(x(x0), y(y1), w, h, r, r);
      g.fillPath();
    }
    if (stroke != null) {
      g.setStrokeColor(stroke);
      g.setLineWidth(line);
      g.drawRRect(x(x0), y(y1), w, h, r, r);
      g.strokePath();
    }
  }

  void bubble(Pt p, String label) {
    final r = layout.bubbleR * k * mm;
    g.setStrokeColor(PdfColors.grey600);
    g.setLineWidth(0.6);
    g.drawEllipse(x(p.x), y(p.y), r, r);
    g.strokePath();
    g.setFillColor(PdfColors.grey700);
    final (font, shaped) = fonts(label, bold: true);
    const pt = 5.2;
    final w = font.stringMetrics(shaped).width * pt;
    g.drawString(font, pt, shaped, x(p.x) - w / 2, y(p.y) - 1.85);
  }

  // ---- Köşe kareleri ----
  g.setFillColor(PdfColors.black);
  for (final o in FormLayout.markerOrigins) {
    g.drawRect(x(o.x), y(o.y + FormLayout.markerSize), FormLayout.markerSize * k * mm, FormLayout.markerSize * k * mm);
  }
  g.fillPath();

  // ---- Makine kodu ----
  final bits = FormCode(examCode: FormCode.examCodeOf(exam.id), studentNumber: int.tryParse(s?.number ?? '')).encode();
  g.setFillColor(PdfColors.black);
  for (var i = 0; i < bits.length; i++) {
    if (!bits[i]) continue;
    final c = FormCode.cell(i);
    const h = FormCode.cellSize / 2;
    g.drawRect(x(c.x - h), y(c.y + h), FormCode.cellSize * k * mm, FormCode.cellSize * k * mm);
  }
  g.fillPath();

  // ---- Üst satır ----
  g.setFillColor(_emerald);
  g.drawEllipse(x(26), y(15.2), 1.0 * mm, 1.0 * mm);
  g.fillPath();
  text(tr('Netice'), 29.5, 17.2, 6.4, bold: true);
  final kind = tr('KISA QUIZ');
  text(kind, 186, 17.2, 6.4, bold: true, right: true, color: _emerald);
  final info = tr('{0} soru · {1} şık', [exam.questionCount, exam.choiceCount]);
  text(info, 186 - width(kind, 6.4, bold: true) - 4, 17.2, 5, right: true, color: _label);

  // ---- QR ----
  const qx = 24.0, qy = 24.0, qs = 38.0;
  final qr = pw.Barcode.qrCode(errorCorrectLevel: pw.BarcodeQRCorrectionLevel.medium);
  g.setFillColor(PdfColors.black);
  for (final e in qr.make(miniFormQrText(exam, s), width: qs, height: qs)) {
    if (e is pw.BarcodeBar && e.black) {
      g.drawRect(x(qx + e.left), y(qy + e.top + e.height), e.width * k * mm, e.height * k * mm);
    }
  }
  g.fillPath();

  // ---- Bilgi alanları ----
  const ix = 68.0, ir = 186.0;
  final name = exam.name;
  text(name, ix, 29.5, fitPt(name, 8, ir - ix, bold: true), bold: true);
  final sub = [exam.className, _date(exam.date), if (school.name.trim().isNotEmpty) school.name.trim()].join(' · ');
  text(sub, ix, 36, fitPt(sub, 5.2, ir - ix), color: _label);
  box(ix, 40, ir, 55);
  text(tr('ADI SOYADI'), ix + 2.5, 45, 4.4, bold: true, color: _label);
  if (s != null) text(s.fullName, ix + 2.5, 52.5, fitPt(s.fullName, 7.6, ir - ix - 5, bold: true), bold: true);
  final hint = tr('Daireyi tamamen karartın. Kenardaki karelere yazmayın.');
  text(hint, ix, 61.5, fitPt(hint, 4.6, ir - ix), color: _label);

  // ---- Öğrenci numarası ----
  final first = layout.studentBubble(0, 0);
  final last = layout.studentBubble(layout.digits - 1, 9);
  final half = layout.numberPitchY / 2;
  box(28, first.y - half - 7.5, ir, last.y + half + 1.5, radius: 3);
  text(tr('ÖĞRENCİ NUMARASI'), 32, first.y - half - 2, 4.6, bold: true, color: _label);
  final hint2 = tr('her satıra bir hane');
  text(hint2, ir - 3, first.y - half - 2, 4.2, color: _label, right: true);
  final number = s?.number.padLeft(layout.digits, '0');
  for (var d = 0; d < layout.digits; d++) {
    final p = layout.studentBubble(d, 0);
    text('${d + 1}', 34, p.y + 1.5, 4.4, color: _gray, right: true);
    box(37, p.y - half + 1.2, 51, p.y + half - 1.2, radius: 1, stroke: PdfColors.grey500);
    if (number != null && number.length == layout.digits) text(number[d], 44, p.y + 2.6, 7, bold: true, center: true);
    for (var v = 0; v < 10; v++) {
      bubble(layout.studentBubble(d, v), '$v');
    }
  }

  // ---- Cevaplar ----
  final rows = layout.rowsPerColumn;
  for (var col = 0; col < layout.columnCount; col++) {
    final firstQ = col * rows;
    final n = math.min(rows, layout.questionCount - firstQ);
    final a0 = layout.answerBubble(firstQ, 0);
    final aN = layout.answerBubble(firstQ, layout.choiceCount - 1);
    final x0 = col == 0 ? 28.0 : a0.x - 14.5, x1 = col == 0 ? aN.x + 5.5 : ir;
    final y0 = a0.y - 13, y1 = a0.y + (n - 1) * layout.answerRowPitch + 7;
    for (var gr = 1; gr * 5 < n; gr += 2) {
      final top = a0.y + gr * 5 * layout.answerRowPitch - layout.answerRowPitch / 2;
      final bottom = math.min(top + 5 * layout.answerRowPitch, y1 - 0.6);
      box(x0 + 0.6, top, x1 - 0.6, bottom, stroke: null, fill: _tint, radius: 1);
    }
    box(x0, y0, x1, y1, radius: 3);
    for (var c = 0; c < layout.choiceCount; c++) {
      text(_letter(c), layout.answerBubble(firstQ, c).x, y0 + 6.5, 5.4, bold: true, center: true);
    }
    for (var r = 0; r < n; r++) {
      final q = firstQ + r;
      final l = layout.questionLabel(q);
      text('${q + 1}', l.x + 4, l.y + 2.2, 6.2, bold: true, right: true);
      for (var c = 0; c < layout.choiceCount; c++) {
        bubble(layout.answerBubble(q, c), _letter(c));
      }
    }
  }

  // ---- Alt bilgi (alt köşe kareleri arasında) ----
  final foot = tr('Netice ile hazırlandı · sınav kodu {0} · %100 ölçekle yazdırın', [FormCode.examCodeOf(exam.id)]);
  text(foot, 105, 284, fitPt(foot, 4.4, 160), color: _muted, center: true);
}

// ---------------------------------------------------------------------------
// Kazanım takip çizelgesi

/// Dönem boyu kazanım takip çizelgesi: kazanım × sınav sınıf başarısı
/// (renkli), eğilim ve öğrenci × kazanım dönem başarısı.
Future<Uint8List> buildOutcomeTrackingPdf(TermReport t, {SchoolInfo school = const SchoolInfo()}) async {
  final fonts = await _Fonts.load(school.fontFamily);
  final k = _termKit(t, school, tr('Kazanım Takip Çizelgesi'));
  final doc = pw.Document(theme: fonts.theme, title: tr('Kazanım takip çizelgesi'), author: tr('Netice'));
  final track = OutcomeTrack.build(t);
  const fill = {0: PdfColor.fromInt(0xFFD1FAE5), 1: PdfColor.fromInt(0xFFFEF3C7), 2: PdfColor.fromInt(0xFFFEE2E2)};
  int band(double v) => v >= OutcomeTrack.mastered ? 0 : (v >= OutcomeTrack.partial ? 1 : 2);
  final head = pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white);
  const cellStyle = pw.TextStyle(fontSize: 7.5);
  pw.Widget cell(String s, {PdfColor? bg, bool left = false, pw.TextStyle? style}) => pw.Container(
        color: bg,
        alignment: left ? pw.Alignment.centerLeft : pw.Alignment.center,
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        child: pw.Text(s, style: style ?? cellStyle, maxLines: 2),
      );
  pw.Widget rateCell(double? v) => v == null ? cell('–', style: const pw.TextStyle(fontSize: 7.5, color: _gray)) : cell(_pct(v), bg: fill[band(v)]);

  pw.Widget legend() => pw.Row(children: [
        for (final (i, label) in [
          (0, tr('Kazanıldı (%{0} ve üstü)', [(OutcomeTrack.mastered * 100).round()])),
          (1, tr('Kısmen (%{0}–%{1})', [(OutcomeTrack.partial * 100).round(), (OutcomeTrack.mastered * 100).round() - 1])),
          (2, tr('Kazanılmadı (%{0} altı)', [(OutcomeTrack.partial * 100).round()])),
        ]) ...[
          pw.Container(width: 9, height: 9, color: fill[i]),
          pw.SizedBox(width: 3),
          pw.Text(label, style: const pw.TextStyle(fontSize: 7.5)),
          pw.SizedBox(width: 12),
        ],
        pw.Text(tr('–: o sınavda sorulmadı'), style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
      ]);

  final content = <pw.Widget>[
    k.title(tr('Kazanım takip çizelgesi'),
        tr('{0} · {1} · kazanımlar sınav sınav sınıfın doğru oranıyla izlenir', [t.term.label, t.className])),
  ];
  if (track.codes.isEmpty) {
    content.add(pw.Padding(
      padding: const pw.EdgeInsets.only(top: 20),
      child: pw.Text(
          tr('Seçilen sınavlarda kazanım bilgisi yok. Sınav ayarlarında sorulara kazanım (konu) yazın ya da sınavı soru bankasından oluşturun.'),
          style: const pw.TextStyle(fontSize: 10)),
    ));
  } else {
    final mastered = [for (var i = 0; i < track.codes.length; i++) track.termRate(i)].whereType<double>();
    content.addAll([
      k.grid([
        k.statBox(tr('Kazanım'), '${track.codes.length}'),
        k.statBox(tr('Kazanılan'), '${mastered.where((v) => v >= OutcomeTrack.mastered).length}', color: _emerald),
        k.statBox(tr('Kısmen'), '${mastered.where((v) => v >= OutcomeTrack.partial && v < OutcomeTrack.mastered).length}', color: _amber),
        k.statBox(tr('Kazanılmayan'), '${mastered.where((v) => v < OutcomeTrack.partial).length}', color: _coral),
      ]),
      pw.SizedBox(height: 4),
      legend(),
      pw.SizedBox(height: 6),
      pw.Table(
        border: pw.TableBorder.all(color: _line, width: 0.5),
        columnWidths: {
          0: const pw.FixedColumnWidth(22),
          1: const pw.FlexColumnWidth(5),
          for (var j = 0; j < t.exams.length; j++) j + 2: const pw.FlexColumnWidth(1.25),
          t.exams.length + 2: const pw.FlexColumnWidth(1.3),
          t.exams.length + 3: const pw.FlexColumnWidth(1.2),
        },
        children: [
          pw.TableRow(decoration: const pw.BoxDecoration(color: _ink), repeat: true, children: [
            cell('#', style: head),
            cell(tr('Kazanım'), style: head, left: true),
            for (var j = 0; j < t.exams.length; j++) cell('${j + 1}. ${_short(t.exams[j].exam.name, 10)}\n${_date(t.exams[j].exam.date)}', style: head),
            cell(tr('Dönem'), style: head),
            cell(tr('Eğilim'), style: head),
          ]),
          for (var i = 0; i < track.codes.length; i++)
            pw.TableRow(children: [
              cell('K${i + 1}'),
              cell(track.codes[i], left: true),
              for (final v in track.byExam[i]) rateCell(v),
              rateCell(track.termRate(i)),
              () {
                final d = track.trend(i);
                if (d == null) return cell('–', style: const pw.TextStyle(fontSize: 7.5, color: _gray));
                final up = d >= 5, down = d <= -5;
                return cell('${up ? '↑' : (down ? '↓' : '→')} ${d >= 0 ? '+' : ''}${d.round()}',
                    style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: up ? _emerald : (down ? _coral : _muted)));
              }(),
            ]),
        ],
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 4),
        child: pw.Text(tr('Eğilim: kazanımın ilk ve son sorulduğu sınav arasındaki fark (yüzde puan).'),
            style: const pw.TextStyle(fontSize: 7, color: _muted)),
      ),
    ]);
  }
  doc.addPage(pw.MultiPage(
    textDirection: _dir,
    pageFormat: PdfPageFormat.a4.landscape,
    margin: const pw.EdgeInsets.fromLTRB(30, 26, 30, 26),
    header: k.header,
    footer: k.footer,
    build: (ctx) => content,
  ));

  // Öğrenci × kazanım: sayfaya en fazla 14 kazanım sütunu.
  final students = t.rows.where((r) => track.byStudent.containsKey(r.student.id)).toList();
  if (track.codes.isNotEmpty && students.isNotEmpty) {
    const per = 14;
    for (var start = 0; start < track.codes.length; start += per) {
      final idx = [for (var i = start; i < math.min(start + per, track.codes.length); i++) i];
      doc.addPage(pw.MultiPage(
        textDirection: _dir,
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(30, 26, 30, 26),
        header: k.header,
        footer: k.footer,
        build: (ctx) => [
          k.title(tr('Öğrenci kazanım çizelgesi'),
              tr('Her öğrencinin dönem boyunca kazanımlardaki doğru oranı · K{0}–K{1}', [idx.first + 1, idx.last + 1])),
          legend(),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(color: _line, width: 0.5),
            columnWidths: {
              0: const pw.FixedColumnWidth(34),
              1: const pw.FlexColumnWidth(4),
              for (var j = 0; j < idx.length; j++) j + 2: const pw.FlexColumnWidth(1),
              idx.length + 2: const pw.FlexColumnWidth(1.4),
            },
            children: [
              pw.TableRow(decoration: const pw.BoxDecoration(color: _ink), repeat: true, children: [
                cell(tr('No'), style: head),
                cell(tr('Ad Soyad'), style: head, left: true),
                for (final i in idx) cell('K${i + 1}', style: head),
                cell(tr('Kazanılan'), style: head),
              ]),
              for (final r in students)
                pw.TableRow(children: [
                  cell(r.student.number),
                  cell(r.student.fullName, left: true),
                  for (final i in idx) rateCell(track.byStudent[r.student.id]![track.codes[i]]),
                  () {
                    final (m, n) = track.masteredOf(r.student.id);
                    return cell('$m / $n', style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold));
                  }(),
                ]),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Wrap(spacing: 10, runSpacing: 2, children: [
            for (final i in idx)
              pw.Text('K${i + 1}: ${_short(track.codes[i], 60)}', style: const pw.TextStyle(fontSize: 7, color: _muted)),
          ]),
        ],
      ));
    }
  }
  return doc.save();
}
