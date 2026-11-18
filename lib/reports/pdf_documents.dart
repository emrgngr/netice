import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/models.dart';
import '../core/report.dart';
import '../core/scoring.dart';
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

/// Basılı optik formlar. Her öğrenci için adı yazılı bir sayfa üretir;
/// [students] boşsa tek bir genel form üretir.
Future<Uint8List> buildFormsPdf(Exam exam, List<Student> students) async {
  final fonts = await _Fonts.load();
  final layout = FormLayout(questionCount: exam.questionCount, choiceCount: exam.choiceCount);
  final doc = pw.Document(title: '${exam.name} · optik form', author: 'Netice');
  final pages = students.isEmpty ? <Student?>[null] : students.cast<Student?>();
  for (final s in pages) {
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (ctx) => pw.CustomPaint(
          size: PdfPoint(PdfPageFormat.a4.width, PdfPageFormat.a4.height),
          painter: (canvas, size) =>
              _paintForm(canvas, size, layout, exam, s, (fonts.regular.getFont(ctx), fonts.bold.getFont(ctx))),
        ),
      ),
    );
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
  final String institution;

  /// Raporun oluşturulduğu an (cihaz saatiyle).
  final DateTime createdAt = DateTime.now();
  _Kit(this.exam, this.institution);

  String get created => reportStamp(createdAt);

  pw.Widget header(pw.Context ctx) => pw.Container(
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
          '${exam.name} · ${exam.className} · Sınav: ${_date(exam.date)}',
          style: const pw.TextStyle(color: _muted, fontSize: 9),
        ),
      ],
    ),
  );

  pw.Widget footer(pw.Context ctx) => pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text('Netice ile hazırlandı', style: const pw.TextStyle(color: _emerald, fontSize: 8)),
      pw.Text('Rapor tarihi: $created', style: const pw.TextStyle(color: _muted, fontSize: 8)),
      pw.Text('Sayfa ${ctx.pageNumber} / ${ctx.pagesCount}', style: const pw.TextStyle(color: _muted, fontSize: 8)),
    ],
  );

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
  String institution = '',
}) async {
  final fonts = await _Fonts.load();
  final r = ExamReport.build(exam, results);
  final s = r.stats;
  final k = _Kit(exam, institution);
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
          ['Sıra', 'Ad Soyad', 'No', 'D', 'Y', 'B', 'Net', 'Puan', 'Yüzdelik', 'T', 'Düzey'],
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
  String institution = '',
}) async {
  final fonts = await _Fonts.load();
  final r = ExamReport.build(exam, results);
  final k = _Kit(exam, institution);
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

  for (final st in r.standings) {
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
