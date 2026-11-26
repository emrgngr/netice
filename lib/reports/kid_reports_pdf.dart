// Çocuk (ilkokul) sınavlarının raporları: öğrenci karnesi (gelişim
// yolculuğuyla) ve sınıf raporu. Klasik raporlarla aynı veriyi kullanır;
// sıralama, T puanı gibi çocuğu yarıştıran bilgiler yerine yıldızlar,
// cesaretlendirici sözler ve renkli, sade grafikler gösterir.

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/models.dart';
import '../core/progress.dart';
import '../core/report.dart';
import '../core/scoring.dart';
import '../core/term.dart';
import '../l10n/l10n.dart';
import 'brand_footer.dart';
import 'kid_pdf.dart';
import 'pdf_documents.dart' show pdfTheme;

const _green = PdfColor.fromInt(0xFF4FB86A);
const _softGreen = PdfColor.fromInt(0xFFDDF3E2);
const _amber = PdfColor.fromInt(0xFFF6B632);
const _softAmber = PdfColor.fromInt(0xFFFFF1CC);
const _softRose = PdfColor.fromInt(0xFFFBDDE5);
const _gray = PdfColor.fromInt(0xFFA3ADC2);
const _softGray = PdfColor.fromInt(0xFFEEF1F7);

pw.TextDirection get _dir => L10n.rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;

String _f1(double v) {
  final s = v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
  return s.replaceAll('.', L10n.decimal);
}

String _pct(double rate) => L10n.percent((rate * 100).round());

/// Başarı yüzdesine (0..100) göre 1–5 yıldız.
int kidStars(double pct) => pct >= 85
    ? 5
    : pct >= 70
    ? 4
    : pct >= 50
    ? 3
    : pct >= 30
    ? 2
    : 1;

/// Yıldız sayısına göre cesaretlendirici söz.
String kidPraise(int stars) => switch (stars) {
  5 => tr('Süpersin! Harika bir iş çıkardın.'),
  4 => tr('Çok iyi! Böyle devam et.'),
  3 => tr('İyi gidiyorsun! Biraz daha pratikle daha da iyi olacak.'),
  2 => tr('Emek verdin! Birlikte biraz daha çalışalım.'),
  _ => tr('Her gün biraz çalışarak başaracağız!'),
};

PdfColor _rateColor(double rate) => rate >= 0.7
    ? _green
    : rate >= 0.4
    ? _amber
    : kidRose;

PdfColor _rateSoft(double rate) => rate >= 0.7
    ? _softGreen
    : rate >= 0.4
    ? _softAmber
    : _softRose;

pw.Widget _stars(int n, double size) => pw.Row(
  mainAxisSize: pw.MainAxisSize.min,
  children: [
    for (var i = 0; i < 5; i++)
      pw.Padding(
        padding: pw.EdgeInsets.only(right: size * 0.12),
        child: kidStar(size, filled: i < n),
      ),
  ],
);

/// Yuvarlak uçlu yatay çubuk.
pw.Widget _bar(double frac, PdfColor color, {double height = 10, PdfColor track = _softGray}) => pw.LayoutBuilder(
  builder: (ctx, c) {
    final w = (c?.maxWidth ?? 100);
    final f = frac.isNaN ? 0.0 : frac.clamp(0.0, 1.0);
    return pw.Stack(
      children: [
        pw.Container(
          width: w,
          height: height,
          decoration: pw.BoxDecoration(color: track, borderRadius: pw.BorderRadius.circular(height / 2)),
        ),
        if (f > 0)
          pw.Container(
            width: (w * f).clamp(height, w),
            height: height,
            decoration: pw.BoxDecoration(color: color, borderRadius: pw.BorderRadius.circular(height / 2)),
          ),
      ],
    );
  },
);

/// Doğru (tik), yanlış (çarpı), boş (çizgi) işareti.
pw.Widget _mark(Outcome o, double size) => pw.CustomPaint(
  size: PdfPoint(size, size),
  painter: (canvas, s) {
    final w = s.x, h = s.y;
    canvas
      ..setLineWidth(w * 0.16)
      ..setLineCap(PdfLineCap.round)
      ..setLineJoin(PdfLineJoin.round);
    switch (o) {
      case Outcome.correct:
        canvas
          ..setStrokeColor(_green)
          ..moveTo(w * 0.15, h * 0.5)
          ..lineTo(w * 0.42, h * 0.22)
          ..lineTo(w * 0.88, h * 0.8)
          ..strokePath();
      case Outcome.wrong:
        canvas
          ..setStrokeColor(kidRose)
          ..moveTo(w * 0.2, h * 0.2)
          ..lineTo(w * 0.8, h * 0.8)
          ..moveTo(w * 0.8, h * 0.2)
          ..lineTo(w * 0.2, h * 0.8)
          ..strokePath();
      case Outcome.blank:
      case Outcome.cancelled:
        canvas
          ..setStrokeColor(_gray)
          ..moveTo(w * 0.22, h * 0.5)
          ..lineTo(w * 0.78, h * 0.5)
          ..strokePath();
    }
  },
);

class _KidKit {
  final Exam exam;
  final SchoolInfo school;
  final pw.ThemeData baseTheme;
  _KidKit(this.exam, this.school, this.baseTheme);

  String get _sub => [exam.name, if (exam.className.isNotEmpty) exam.className, L10n.date(exam.date)].join('  ·  ');

  /// Renkli başlık bandı: yıldız rozeti, başlık, alt satır ve sağda bir kutu.
  pw.Widget banner(String title, {String? subtitle, pw.Widget? trailing}) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      if (school.name.trim().isNotEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 5),
          child: pw.Text(
            school.name.trim(),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: kidMuted),
          ),
        ),
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: pw.BoxDecoration(
          gradient: pw.LinearGradient(colors: [kidYellow, kidPink, kidBlue]),
          borderRadius: pw.BorderRadius.circular(16),
        ),
        child: pw.Row(
          children: [
            pw.Container(
              width: 42,
              height: 42,
              alignment: pw.Alignment.center,
              decoration: const pw.BoxDecoration(shape: pw.BoxShape.circle, color: PdfColors.white),
              child: kidStar(30),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    title,
                    maxLines: 1,
                    style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold, color: kidInk),
                  ),
                  pw.Text(subtitle ?? _sub, maxLines: 2, style: const pw.TextStyle(fontSize: 9.5, color: kidMuted)),
                ],
              ),
            ),
            if (trailing != null) ...[pw.SizedBox(width: 8), trailing],
          ],
        ),
      ),
    ],
  );

  /// Bölüm başlığı (kutusuz; sayfalara bölünebilen tablolar için).
  pw.Widget heading(String title, {int color = 0, String? hint}) =>
      pw.Padding(padding: const pw.EdgeInsets.only(top: 10, bottom: 6, left: 2), child: _titleRow(title, color, hint));

  pw.Widget _titleRow(String title, int color, String? hint) => pw.Row(
    children: [
      pw.Container(
        width: 10,
        height: 10,
        decoration: pw.BoxDecoration(shape: pw.BoxShape.circle, color: kidBadgeColors[color % kidBadgeColors.length]),
      ),
      pw.SizedBox(width: 6),
      pw.Text(
        title,
        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: kidInk),
      ),
      if (hint != null) ...[
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: pw.Text(hint, maxLines: 1, style: const pw.TextStyle(fontSize: 7.5, color: kidMuted)),
        ),
      ],
    ],
  );

  /// Başlıklı, kesik kenarlı bölüm kutusu.
  pw.Widget section(String title, pw.Widget child, {int color = 0, String? hint}) => pw.Inseparable(
    child: pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      padding: const pw.EdgeInsets.fromLTRB(12, 7, 12, 8),
      decoration: pw.BoxDecoration(
        color: kidSoftBlue,
        border: pw.Border.all(color: kidLine, width: 1, style: pw.BorderStyle.dashed),
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [_titleRow(title, color, hint), pw.SizedBox(height: 6), child],
      ),
    ),
  );

  /// Büyük sayılı renkli kutucuk.
  pw.Widget tile(String label, String value, PdfColor color, PdfColor soft, {pw.Widget? extra}) => pw.Expanded(
    child: pw.Container(
      margin: const pw.EdgeInsets.symmetric(horizontal: 3),
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      decoration: pw.BoxDecoration(color: soft, borderRadius: pw.BorderRadius.circular(12)),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: color),
          ),
          // Tüm kutucuklar aynı boyda olsun diye işaret yeri her zaman ayrılır.
          pw.SizedBox(height: 12, child: pw.Center(child: extra)),
          pw.SizedBox(height: 2),
          pw.Text(
            label,
            textAlign: pw.TextAlign.center,
            maxLines: 2,
            style: const pw.TextStyle(fontSize: 8.5, color: kidInk),
          ),
        ],
      ),
    ),
  );

  pw.Widget footer(pw.Context ctx) => pw.Column(
    children: [
      if (ctx.pagesCount > 1)
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 7.5, color: kidMuted)),
        ),
      pw.Theme(data: baseTheme, child: brandStrip()),
    ],
  );

  /// Dikey çubuklarla gelişim grafiği: (etiket, yüzde 0..100, sınıf yüzdesi).
  pw.Widget growth(List<(String, double, double?)> points, {double height = 66}) {
    final pts = points.length > 8 ? points.sublist(points.length - 8) : points;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.SizedBox(
          height: height,
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < pts.length; i++)
                pw.Expanded(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 5),
                    child: pw.Stack(
                      overflow: pw.Overflow.visible,
                      children: [
                        pw.Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: pw.Container(
                            height: ((height - 14) * pts[i].$2 / 100).clamp(4, height - 14),
                            decoration: pw.BoxDecoration(
                              color: kidBadgeColors[(i + 1) % kidBadgeColors.length],
                              borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(6)),
                            ),
                          ),
                        ),
                        if (pts[i].$3 != null)
                          pw.Positioned(
                            left: -3,
                            right: -3,
                            bottom: ((height - 14) * pts[i].$3! / 100).clamp(0, height - 14),
                            child: pw.Container(height: 1.6, color: kidInk),
                          ),
                        pw.Positioned(
                          left: 0,
                          right: 0,
                          bottom:
                              ((height - 14) * [pts[i].$2, pts[i].$3 ?? 0].reduce((a, b) => a > b ? a : b) / 100).clamp(4, height - 14) + 2,
                          child: pw.Text(
                            L10n.percent(pts[i].$2.round()),
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: kidInk),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        pw.Container(height: 1.2, color: kidLine),
        pw.SizedBox(height: 3),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (final p in pts)
              pw.Expanded(
                child: pw.Text(
                  p.$1,
                  textAlign: pw.TextAlign.center,
                  maxLines: 2,
                  style: const pw.TextStyle(fontSize: 7, color: kidMuted),
                ),
              ),
          ],
        ),
        if (pts.any((p) => p.$3 != null)) ...[
          pw.SizedBox(height: 4),
          pw.Row(
            children: [
              pw.Container(width: 14, height: 1.6, color: kidInk),
              pw.SizedBox(width: 4),
              pw.Text(tr('Sınıf ortalaması'), style: const pw.TextStyle(fontSize: 7.5, color: kidMuted)),
            ],
          ),
        ],
      ],
    );
  }
}

String _shortName(Exam e) {
  final n = e.name.trim();
  return n.length <= 18 ? n : '${n.substring(0, 17)}…';
}

/// Çocuk sınavının öğrenci karnesi: her öğrenci için bir sayfa. Sıra ve T
/// puanı gösterilmez; yıldızlar, soru soru doğru/yanlış, konu çubukları,
/// sınıf ortalamasıyla karşılaştırma ve önceki sınavlardan gelişim grafiği.
Future<Uint8List> buildKidStudentCardsPdf({
  required Exam exam,
  required List<Result> results,
  required Map<String, Student> students,
  SchoolInfo school = const SchoolInfo(),
  String? onlyStudentId,
  Map<String, List<String>> notes = const {},
  Map<String, List<(String, double, List<String>)>> studyTopics = const {},
  Map<String, List<HistoryEntry>> history = const {},
}) async {
  useKidTheme(exam.kidTheme);
  final baseTheme = await pdfTheme(school.fontFamily);
  final theme = await kidPdfTheme(school.fontFamily);
  await BrandAssets.load();
  final r = ExamReport.build(exam, results);
  final k = _KidKit(exam, school, baseTheme);
  final max = exam.rule.maxScore;
  final doc = pw.Document(theme: theme, title: tr('{0} öğrenci karneleri', [exam.name]), author: tr('Netice'));

  pw.Widget compareRow(String label, double score, PdfColor color) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: pw.Row(
      children: [
        pw.SizedBox(
          width: 70,
          child: pw.Text(label, maxLines: 2, style: const pw.TextStyle(fontSize: 9, color: kidInk)),
        ),
        pw.Expanded(child: _bar(max == 0 ? 0 : score / max, color, height: 12)),
        pw.SizedBox(
          width: 34,
          child: pw.Text(
            _f1(score),
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: kidInk),
          ),
        ),
      ],
    ),
  );

  for (final st in r.standings.where((x) => onlyStudentId == null || x.result.sheet.studentId == onlyStudentId)) {
    final res = st.result;
    final id = res.sheet.studentId;
    final stu = students[id];
    final stars = kidStars(st.pct);
    final hist = history[id] ?? const <HistoryEntry>[];
    final tips = studyTopics[id] ?? const [];
    final note = notes[id] ?? const [];
    final weak = [
      for (var i = 0; i < exam.questionCount; i++)
        if (res.outcomes[i] == Outcome.wrong || res.outcomes[i] == Outcome.blank) i + 1,
    ];

    doc.addPage(
      pw.MultiPage(
        textDirection: _dir,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(30, 22, 30, 18),
        footer: k.footer,
        build: (ctx) => [
          k.banner(
            tr('Karnem'),
            trailing: pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: pw.BoxDecoration(color: PdfColors.white, borderRadius: pw.BorderRadius.circular(12)),
              child: pw.Column(
                children: [
                  pw.Text(
                    _f1(res.score),
                    style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: kidRose),
                  ),
                  pw.Text(tr('puan / {0}', [_f1(max)]), style: const pw.TextStyle(fontSize: 7.5, color: kidMuted)),
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 8),
          // İsim, yıldızlar ve övgü.
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: kidLine, width: 1.3),
              borderRadius: pw.BorderRadius.circular(14),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        stu?.fullName ?? tr('Eşleşmeyen kâğıt'),
                        style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: kidInk),
                      ),
                      if (stu != null && stu.number.isNotEmpty)
                        pw.Text('${tr('No')} ${stu.number}', style: const pw.TextStyle(fontSize: 9, color: kidMuted)),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        kidPraise(stars),
                        style: pw.TextStyle(fontSize: 12, color: kidRose, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 8),
                _stars(stars, 22),
              ],
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              k.tile(tr('Doğru'), '${res.correct}', _green, _softGreen, extra: _mark(Outcome.correct, 10)),
              k.tile(tr('Yanlış'), '${res.wrong}', kidRose, _softRose, extra: _mark(Outcome.wrong, 10)),
              k.tile(tr('Boş'), '${res.blank}', _gray, _softGray, extra: _mark(Outcome.blank, 10)),
              k.tile(tr('Başarı'), L10n.percent(st.pct.round()), kidInk, kidBlue),
            ],
          ),
          k.section(
            tr('Sorularım'),
            pw.Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < exam.questionCount; i++)
                  pw.Container(
                    width: 34,
                    padding: const pw.EdgeInsets.symmetric(vertical: 4),
                    decoration: pw.BoxDecoration(
                      color: switch (res.outcomes[i]) {
                        Outcome.correct => _softGreen,
                        Outcome.wrong => _softRose,
                        _ => _softGray,
                      },
                      borderRadius: pw.BorderRadius.circular(10),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(
                          '${i + 1}',
                          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: kidInk),
                        ),
                        pw.SizedBox(height: 2),
                        _mark(res.outcomes[i], 9),
                      ],
                    ),
                  ),
              ],
            ),
            color: 1,
          ),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: k.section(
                  tr('Sınıfımızla birlikte'),
                  pw.Column(
                    children: [
                      compareRow(tr('Benim puanım'), res.score, kidBadgeColors[0]),
                      compareRow(tr('Sınıf ortalaması'), r.stats.mean, kidBadgeColors[1]),
                    ],
                  ),
                  color: 2,
                ),
              ),
              if (r.outcomes.isNotEmpty) ...[
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: k.section(
                    tr('Konularım'),
                    pw.Column(
                      children: [
                        for (final o in r.outcomes.take(8))
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(bottom: 4),
                            child: pw.Row(
                              children: [
                                pw.SizedBox(
                                  width: 80,
                                  child: pw.Text(o.code, maxLines: 2, style: const pw.TextStyle(fontSize: 8.5, color: kidInk)),
                                ),
                                pw.Expanded(child: _bar(o.rateOf(exam, res), _rateColor(o.rateOf(exam, res)), height: 9)),
                                pw.SizedBox(width: 5),
                                _stars(kidStars(o.rateOf(exam, res) * 100), 8),
                              ],
                            ),
                          ),
                      ],
                    ),
                    color: 3,
                  ),
                ),
              ],
            ],
          ),
          if (hist.length >= 2)
            k.section(
              tr('Gelişim yolculuğum'),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  k.growth([
                    for (final h in hist)
                      (_shortName(h.exam), h.pct, h.exam.rule.maxScore == 0 ? null : h.classMean / h.exam.rule.maxScore * 100),
                  ]),
                  if (note.isNotEmpty) ...[
                    pw.SizedBox(height: 6),
                    pw.Text(note.take(3).join(' '), style: const pw.TextStyle(fontSize: 9, color: kidInk)),
                  ],
                ],
              ),
              hint: tr('Son sınavlarımdaki başarım'),
              color: 4,
            )
          else if (note.isNotEmpty)
            k.section(tr('Gelişim notu'), pw.Text(note.take(3).join(' '), style: const pw.TextStyle(fontSize: 9, color: kidInk)), color: 4),
          if (tips.isNotEmpty || weak.isNotEmpty)
            k.section(
              tr('Birlikte çalışalım'),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  for (final (topic, rate, t) in tips.take(3))
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 4),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            '$topic  ·  ${_pct(rate)}',
                            style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: kidInk),
                          ),
                          for (final s in t.take(2))
                            pw.Padding(
                              padding: const pw.EdgeInsets.only(left: 8, top: 1.5),
                              child: pw.Text('• $s', style: const pw.TextStyle(fontSize: 9, color: kidInk)),
                            ),
                        ],
                      ),
                    ),
                  if (weak.isNotEmpty)
                    pw.Text(tr('Tekrar bakalım: {0}. sorular', [weak.join(', ')]), style: const pw.TextStyle(fontSize: 9, color: kidMuted)),
                ],
              ),
              color: 5,
            ),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              for (final label in [tr('Öğretmenimin notu'), tr('Veli imzası')])
                pw.Expanded(
                  child: pw.Container(
                    height: 34,
                    margin: const pw.EdgeInsets.symmetric(horizontal: 3),
                    padding: const pw.EdgeInsets.all(6),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: kidLine, width: 1, style: pw.BorderStyle.dashed),
                      borderRadius: pw.BorderRadius.circular(10),
                    ),
                    child: pw.Text(label, style: const pw.TextStyle(fontSize: 8.5, color: kidMuted)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
  if (r.standings.isEmpty) {
    doc.addPage(
      pw.Page(
        textDirection: _dir,
        build: (_) => pw.Center(child: pw.Text(tr('Henüz okunan kâğıt yok.'))),
      ),
    );
  }
  return doc.save();
}

/// Çocuk sınavının sınıf raporu: sınıf ortalaması, yıldız dağılımı, soru
/// soru sınıf başarısı, konular, sınıfın gelişimi ve öğrenci listesi.
/// [classHistory]: aynı sınıfın sınavları eskiden yeniye (ad, ortalama yüzde).
Future<Uint8List> buildKidResultsPdf({
  required Exam exam,
  required List<Result> results,
  required Map<String, Student> students,
  SchoolInfo school = const SchoolInfo(),
  List<(String, double)> classHistory = const [],
}) async {
  useKidTheme(exam.kidTheme);
  final baseTheme = await pdfTheme(school.fontFamily);
  final theme = await kidPdfTheme(school.fontFamily);
  await BrandAssets.load();
  final r = ExamReport.build(exam, results);
  final s = r.stats;
  final k = _KidKit(exam, school, baseTheme);
  final max = exam.rule.maxScore;
  final doc = pw.Document(theme: theme, title: tr('{0} sınav raporu', [exam.name]), author: tr('Netice'));
  final classPct = max == 0 ? 0.0 : s.mean / max * 100;

  final starCounts = List.filled(6, 0);
  for (final st in r.standings) {
    starCounts[kidStars(st.pct)]++;
  }
  final active = [
    for (final it in r.items)
      if (!exam.questions[it.no - 1].cancelled) it,
  ];
  final easy = [...active]..sort((a, b) => b.p.compareTo(a.p));
  final hard = [...active.where((it) => it.p < 0.6)]..sort((a, b) => a.p.compareTo(b.p));
  final support = [
    for (final st in r.standings)
      if (st.result.score < exam.rule.pass) students[st.result.sheet.studentId]?.fullName ?? tr('Eşleşmeyen kâğıt'),
  ];
  final list = [...r.standings]
    ..sort((a, b) {
      final na = students[a.result.sheet.studentId]?.fullName ?? '';
      final nb = students[b.result.sheet.studentId]?.fullName ?? '';
      return na.compareTo(nb);
    });

  pw.Widget callout(String title, List<String> items, PdfColor color, PdfColor soft) => pw.Expanded(
    child: pw.Container(
      margin: const pw.EdgeInsets.symmetric(horizontal: 3),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(color: soft, borderRadius: pw.BorderRadius.circular(10)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: color),
          ),
          pw.SizedBox(height: 3),
          pw.Text(items.isEmpty ? '–' : items.join(', '), style: const pw.TextStyle(fontSize: 9, color: kidInk)),
        ],
      ),
    ),
  );

  const cell = pw.TextStyle(fontSize: 8.5, color: kidInk);
  pw.Widget c(String t, {bool bold = false, pw.TextAlign align = pw.TextAlign.center}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
    child: pw.Text(
      t,
      textAlign: align,
      maxLines: 1,
      style: bold ? cell.copyWith(fontWeight: pw.FontWeight.bold) : cell,
    ),
  );

  doc.addPage(
    pw.MultiPage(
      textDirection: _dir,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(32, 26, 32, 22),
      footer: k.footer,
      build: (ctx) => [
        k.banner(tr('Sınıfımızın karnesi')),
        pw.SizedBox(height: 10),
        pw.Row(
          children: [
            k.tile(tr('Sınava giren'), '${s.count}', kidInk, kidBlue),
            k.tile(tr('Sınıf ortalaması'), _f1(s.mean), kidRose, kidPink, extra: _stars(kidStars(classPct), 8)),
            k.tile(tr('Ortalama doğru'), _f1(r.meanCorrect), _green, _softGreen),
            k.tile(tr('En yüksek puan'), _f1(s.max), PdfColor.fromInt(0xFFB07A00), _softAmber),
            k.tile(tr('Geçen öğrenci'), _pct(r.passRate), kidInk, _softGray),
          ],
        ),
        k.section(
          tr('Yıldız dağılımı'),
          pw.Column(
            children: [
              for (var n = 5; n >= 1; n--)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Row(
                    children: [
                      pw.SizedBox(width: 70, child: _stars(n, 10)),
                      pw.SizedBox(width: 8),
                      pw.Expanded(
                        child: _bar(r.standings.isEmpty ? 0 : starCounts[n] / r.standings.length, kidBadgeColors[5 - n], height: 11),
                      ),
                      pw.SizedBox(
                        width: 66,
                        child: pw.Text(
                          tr('{0} öğrenci', [starCounts[n]]),
                          textAlign: pw.TextAlign.right,
                          style: const pw.TextStyle(fontSize: 9, color: kidInk),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          hint: tr('5 yıldız: %85 ve üzeri · 4: %70 · 3: %50 · 2: %30'),
          color: 4,
        ),
        k.section(
          tr('Soru soru sınıfımız'),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final it in r.items)
                    pw.Container(
                      width: 40,
                      padding: const pw.EdgeInsets.symmetric(vertical: 4),
                      decoration: pw.BoxDecoration(
                        color: exam.questions[it.no - 1].cancelled ? _softGray : _rateSoft(it.p),
                        borderRadius: pw.BorderRadius.circular(10),
                      ),
                      child: pw.Column(
                        children: [
                          pw.Text(
                            '${it.no}',
                            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: kidInk),
                          ),
                          pw.Text(
                            exam.questions[it.no - 1].cancelled ? tr('iptal') : _pct(it.p),
                            style: pw.TextStyle(fontSize: 8, color: exam.questions[it.no - 1].cancelled ? _gray : _rateColor(it.p)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  callout(tr('En kolay bulduklarımız'), [for (final it in easy.take(3)) '${it.no}'], _green, _softGreen),
                  callout(tr('Tekrar edelim'), [for (final it in hard.take(5)) '${it.no}'], kidRose, _softRose),
                ],
              ),
            ],
          ),
          hint: tr('Doğru cevaplayan öğrencilerin oranı'),
          color: 1,
        ),
        if (r.outcomes.isNotEmpty)
          k.section(
            tr('Konularımız'),
            pw.Column(
              children: [
                for (final o in r.outcomes)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 5),
                    child: pw.Row(
                      children: [
                        pw.SizedBox(
                          width: 160,
                          child: pw.Text(o.code, maxLines: 2, style: const pw.TextStyle(fontSize: 9, color: kidInk)),
                        ),
                        pw.Expanded(child: _bar(o.rate, _rateColor(o.rate), height: 10)),
                        pw.SizedBox(
                          width: 40,
                          child: pw.Text(
                            _pct(o.rate),
                            textAlign: pw.TextAlign.right,
                            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: kidInk),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            color: 3,
          ),
        if (classHistory.length >= 2)
          k.section(
            tr('Sınıfımızın gelişimi'),
            k.growth([for (final (name, pct) in classHistory) (name, pct, null)]),
            hint: tr('Son sınavlarda sınıf ortalaması'),
            color: 2,
          ),
        // Öğrenci listesi ikinci sayfada başlar; tablo sayfaya bölünmesin.
        pw.NewPage(),
        k.heading(tr('Öğrencilerimiz'), hint: tr('Ada göre sıralı')),
        pw.Table(
          columnWidths: const {
            0: pw.FlexColumnWidth(4),
            1: pw.FlexColumnWidth(1.2),
            2: pw.FlexColumnWidth(1.2),
            3: pw.FlexColumnWidth(1.2),
            4: pw.FlexColumnWidth(1.4),
            5: pw.FlexColumnWidth(2.6),
          },
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: kidBlue, borderRadius: pw.BorderRadius.circular(6)),
              children: [
                c(tr('Ad Soyad'), bold: true, align: pw.TextAlign.left),
                c(tr('Doğru'), bold: true),
                c(tr('Yanlış'), bold: true),
                c(tr('Boş'), bold: true),
                c(tr('Puan'), bold: true),
                c(tr('Yıldız'), bold: true),
              ],
            ),
            for (var i = 0; i < list.length; i++)
              pw.TableRow(
                decoration: pw.BoxDecoration(color: i.isOdd ? kidSoftBlue : null),
                verticalAlignment: pw.TableCellVerticalAlignment.middle,
                children: [
                  c(students[list[i].result.sheet.studentId]?.fullName ?? tr('Eşleşmeyen kâğıt'), align: pw.TextAlign.left),
                  c('${list[i].result.correct}'),
                  c('${list[i].result.wrong}'),
                  c('${list[i].result.blank}'),
                  c(_f1(list[i].result.score), bold: true),
                  pw.Center(child: _stars(kidStars(list[i].pct), 8)),
                ],
              ),
          ],
        ),
        if (support.isNotEmpty)
          k.section(
            tr('Ek destek önerilen öğrenciler'),
            pw.Text(support.join(', '), style: const pw.TextStyle(fontSize: 9, color: kidInk)),
            hint: tr('Geçme puanının ({0}) altında kalanlar; yalnız öğretmen için', [_f1(exam.rule.pass)]),
            color: 5,
          ),
      ],
    ),
  );
  return doc.save();
}

/// Renkli, kesik çizgili çerçeve (belge kenarı) ve köşelerde yıldızlar.
pw.Widget _certFrame(pw.Widget child) => pw.Container(
  padding: const pw.EdgeInsets.all(10),
  decoration: pw.BoxDecoration(
    gradient: pw.LinearGradient(colors: [kidYellow, kidPink, kidBlue], begin: pw.Alignment.topLeft, end: pw.Alignment.bottomRight),
    borderRadius: pw.BorderRadius.circular(22),
  ),
  child: pw.Stack(
    children: [
      pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(40, 26, 40, 20),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          borderRadius: pw.BorderRadius.circular(16),
          border: pw.Border.all(color: kidRose, width: 1.6, style: pw.BorderStyle.dashed),
        ),
        child: child,
      ),
      pw.Positioned(left: 10, top: 10, child: kidStar(30)),
      pw.Positioned(right: 10, top: 10, child: kidStar(30)),
      pw.Positioned(left: 10, bottom: 10, child: kidStar(22)),
      pw.Positioned(right: 10, bottom: 10, child: kidStar(22)),
    ],
  ),
);

/// Tebrik belgeleri: her öğrenciye yatay A4 renkli bir belge. Yüksek
/// başarıda "Başarı Belgesi", diğerlerinde "Gayret Belgesi" yazar; her çocuk
/// emeği için kutlanır. [minStars] verilirse yalnız o kadar yıldızı olanlar.
Future<Uint8List> buildKidCertificatesPdf({
  required Exam exam,
  required List<Result> results,
  required Map<String, Student> students,
  SchoolInfo school = const SchoolInfo(),
  String? onlyStudentId,
  int minStars = 1,
}) async {
  useKidTheme(exam.kidTheme);
  final baseTheme = await pdfTheme(school.fontFamily);
  final theme = await kidPdfTheme(school.fontFamily);
  await BrandAssets.load();
  final r = ExamReport.build(exam, results);
  final doc = pw.Document(theme: theme, title: tr('{0} tebrik belgeleri', [exam.name]), author: tr('Netice'));
  final teacher = school.teacher.trim();
  final list = [
    for (final st in r.standings)
      if ((onlyStudentId == null || st.result.sheet.studentId == onlyStudentId) && kidStars(st.pct) >= minStars) st,
  ]..sort((a, b) => (students[a.result.sheet.studentId]?.fullName ?? '').compareTo(students[b.result.sheet.studentId]?.fullName ?? ''));

  for (final st in list) {
    final stu = students[st.result.sheet.studentId];
    final stars = kidStars(st.pct);
    final success = stars >= 4;
    doc.addPage(
      pw.Page(
        textDirection: _dir,
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(26),
        build: (ctx) => pw.Column(
          children: [
            pw.Expanded(
              child: _certFrame(
                pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    if (school.name.trim().isNotEmpty)
                      pw.Text(
                        school.name.trim(),
                        textAlign: pw.TextAlign.center,
                        style: const pw.TextStyle(fontSize: 12, color: kidMuted),
                      ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      success ? tr('Başarı Belgesi') : tr('Gayret Belgesi'),
                      style: pw.TextStyle(fontSize: 40, fontWeight: pw.FontWeight.bold, color: kidRose),
                    ),
                    pw.SizedBox(height: 10),
                    _stars(stars, 30),
                    pw.SizedBox(height: 16),
                    pw.Text(
                      stu?.fullName ?? tr('Eşleşmeyen kâğıt'),
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(fontSize: 32, fontWeight: pw.FontWeight.bold, color: kidInk),
                    ),
                    pw.Container(width: 300, height: 1.4, color: kidLine, margin: const pw.EdgeInsets.symmetric(vertical: 8)),
                    pw.Text(
                      success
                          ? tr('"{0}" sınavında gösterdiğin başarı için seni kutlarız. Böyle parlamaya devam et!', [exam.name])
                          : tr('"{0}" sınavındaki emeğin ve gayretin için seni kutlarız. Her gün biraz daha ilerliyorsun!', [exam.name]),
                      textAlign: pw.TextAlign.center,
                      style: const pw.TextStyle(fontSize: 15, color: kidInk),
                    ),
                    pw.SizedBox(height: 22),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              L10n.date(exam.date),
                              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: kidInk),
                            ),
                            pw.Text(exam.className, style: const pw.TextStyle(fontSize: 10, color: kidMuted)),
                          ],
                        ),
                        pw.Column(
                          children: [
                            pw.Container(width: 170, height: 1, color: kidInk),
                            pw.SizedBox(height: 3),
                            pw.Text(teacher.isEmpty ? tr('Öğretmenim') : teacher, style: const pw.TextStyle(fontSize: 11, color: kidInk)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Theme(data: baseTheme, child: brandStrip(divider: false)),
          ],
        ),
      ),
    );
  }
  if (list.isEmpty) {
    doc.addPage(
      pw.Page(
        textDirection: _dir,
        build: (_) => pw.Center(child: pw.Text(tr('Henüz okunan kâğıt yok.'))),
      ),
    );
  }
  return doc.save();
}

/// Çocuk görünümlü dönem karnesi: dönem boyunca sınavlar, yıldızlar, gelişim
/// grafiği, güçlü olduğu ve çalışacağı konular.
Future<Uint8List> buildKidTermCardsPdf(TermReport t, {SchoolInfo school = const SchoolInfo(), String? onlyStudentId}) async {
  final exam0 = t.exams.first.exam;
  useKidTheme(exam0.kidTheme);
  final baseTheme = await pdfTheme(school.fontFamily);
  final theme = await kidPdfTheme(school.fontFamily);
  await BrandAssets.load();
  final k = _KidKit(exam0, school, baseTheme);
  final doc = pw.Document(theme: theme, title: tr('Dönem karnem'), author: tr('Netice'));
  final rows = t.rows.where((r) => r.average != null && (onlyStudentId == null || r.student.id == onlyStudentId)).toList();
  if (rows.isEmpty) {
    doc.addPage(
      pw.Page(
        textDirection: _dir,
        build: (_) => pw.Center(child: pw.Text(tr('Bu dönemde sonucu olan öğrenci yok.'))),
      ),
    );
    return doc.save();
  }
  for (final r in rows) {
    final stars = kidStars(r.average!);
    final out = r.outcomes.entries.toList()..sort((a, b) => b.value.$1.compareTo(a.value.$1));
    final strong = [
      for (final e in out)
        if (e.value.$1 >= 0.7) e.key,
    ].take(4).toList();
    final weak = [
      for (final e in out.reversed)
        if (e.value.$1 < 0.5) e.key,
    ].take(4).toList();
    final taken = [
      for (var i = 0; i < t.exams.length; i++)
        if (r.scores[i] != null) i,
    ];
    doc.addPage(
      pw.MultiPage(
        textDirection: _dir,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(30, 22, 30, 18),
        footer: k.footer,
        build: (ctx) => [
          k.banner(
            tr('Dönem karnem'),
            subtitle: [t.term.label, if (t.className.isNotEmpty) t.className].join('  ·  '),
            trailing: pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: pw.BoxDecoration(color: PdfColors.white, borderRadius: pw.BorderRadius.circular(12)),
              child: pw.Column(
                children: [
                  pw.Text(
                    '${r.grade}',
                    style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: kidRose),
                  ),
                  pw.Text(tr('dönem ortalaması'), style: const pw.TextStyle(fontSize: 7.5, color: kidMuted)),
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: kidLine, width: 1.3),
              borderRadius: pw.BorderRadius.circular(14),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        r.student.fullName,
                        style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: kidInk),
                      ),
                      if (r.student.number.isNotEmpty)
                        pw.Text('${tr('No')} ${r.student.number}', style: const pw.TextStyle(fontSize: 9, color: kidMuted)),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        kidPraise(stars),
                        style: pw.TextStyle(fontSize: 12, color: kidRose, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                _stars(stars, 22),
              ],
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              k.tile(tr('Katıldığım sınav'), '${r.taken} / ${t.exams.length}', kidInk, kidBlue),
              k.tile(tr('Dönem ortalamam'), _f1(r.average!), kidRose, kidPink),
              k.tile(tr('Sınıf ortalaması'), _f1(t.classAverage), _green, _softGreen),
            ],
          ),
          if (taken.length >= 2)
            k.section(
              tr('Gelişim yolculuğum'),
              k.growth([for (final i in taken) (_shortName(t.exams[i].exam), r.scores[i]!, t.exams[i].mean100)]),
              hint: tr('Bu dönemdeki sınavlarım'),
              color: 4,
            ),
          k.section(
            tr('Sınavlarım'),
            pw.Column(
              children: [
                for (var i = 0; i < t.exams.length; i++)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 4),
                    child: pw.Row(
                      children: [
                        pw.Expanded(
                          child: pw.Text(t.exams[i].exam.name, maxLines: 1, style: const pw.TextStyle(fontSize: 9.5, color: kidInk)),
                        ),
                        pw.SizedBox(
                          width: 70,
                          child: pw.Text(L10n.date(t.exams[i].exam.date), style: const pw.TextStyle(fontSize: 8.5, color: kidMuted)),
                        ),
                        pw.SizedBox(
                          width: 40,
                          child: pw.Text(
                            r.scores[i] == null ? '–' : _f1(r.scores[i]!),
                            textAlign: pw.TextAlign.right,
                            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: kidInk),
                          ),
                        ),
                        pw.SizedBox(width: 10),
                        r.scores[i] == null
                            ? pw.SizedBox(
                                width: 56,
                                child: pw.Text(tr('Girmedi'), style: const pw.TextStyle(fontSize: 8.5, color: _gray)),
                              )
                            : _stars(kidStars(r.scores[i]!), 10),
                      ],
                    ),
                  ),
              ],
            ),
            color: 1,
          ),
          if (out.isNotEmpty) ...[
            k.section(
              tr('Konularım'),
              pw.Column(
                children: [
                  for (final e in out.take(10))
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 4),
                      child: pw.Row(
                        children: [
                          pw.SizedBox(
                            width: 150,
                            child: pw.Text(e.key, maxLines: 2, style: const pw.TextStyle(fontSize: 9, color: kidInk)),
                          ),
                          pw.Expanded(child: _bar(e.value.$1, _rateColor(e.value.$1), height: 9)),
                          pw.SizedBox(width: 6),
                          _stars(kidStars(e.value.$1 * 100), 9),
                        ],
                      ),
                    ),
                ],
              ),
              color: 3,
            ),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: k.section(
                    tr('Çok iyi olduğum konular'),
                    pw.Text(
                      strong.isEmpty ? tr('Henüz belirgin değil.') : strong.join(', '),
                      style: const pw.TextStyle(fontSize: 9, color: kidInk),
                    ),
                    color: 2,
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: k.section(
                    tr('Biraz daha çalışacağım konular'),
                    pw.Text(
                      weak.isEmpty ? tr('Belirgin bir eksik görünmüyor.') : weak.join(', '),
                      style: const pw.TextStyle(fontSize: 9, color: kidInk),
                    ),
                    color: 5,
                  ),
                ),
              ],
            ),
          ],
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              for (final label in [tr('Öğretmenimin notu'), tr('Veli imzası')])
                pw.Expanded(
                  child: pw.Container(
                    height: 40,
                    margin: const pw.EdgeInsets.symmetric(horizontal: 3),
                    padding: const pw.EdgeInsets.all(6),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: kidLine, width: 1, style: pw.BorderStyle.dashed),
                      borderRadius: pw.BorderRadius.circular(10),
                    ),
                    child: pw.Text(label, style: const pw.TextStyle(fontSize: 8.5, color: kidMuted)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
  return doc.save();
}
