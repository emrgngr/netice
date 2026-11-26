part of 'pdf_documents.dart';

// Sınav sonrası öğretim belgeleri: çalışma grupları, öğrenci değerlendirme
// kâğıdı (exam wrapper) ve yıl sonu öğrenci devir dosyası.

/// Çalışma grupları: her grup, üyeleri, zayıf kazanımlar ve çalışma planı.
Future<Uint8List> buildStudyGroupsPdf({
  required Exam exam,
  required List<StudyGroup> groups,
  required Map<String, Student> students,
  SchoolInfo school = const SchoolInfo(),
}) async {
  final fonts = await _Fonts.load(school.fontFamily);
  final k = _Kit(exam, school, docTitle: tr('Çalışma Grupları'));
  final doc = pw.Document(theme: fonts.theme, title: tr('{0} çalışma grupları', [exam.name]), author: tr('Netice'));
  const colors = {StudyTier.support: _coral, StudyTier.reinforce: _amber, StudyTier.enrich: _emerald};
  doc.addPage(pw.MultiPage(
    textDirection: _dir,
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 30),
    header: k.header,
    footer: k.footer,
    build: (ctx) => [
      k.title(tr('Çalışma grupları'),
          tr('Sınav sonucuna göre farklılaştırılmış öğretim için üç grup (destek, pekiştirme, zenginleştirme)')),
      for (final g in groups) ...[
        pw.Container(
          margin: const pw.EdgeInsets.only(top: 10, bottom: 6),
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: pw.BoxDecoration(
            border: pw.Border(left: pw.BorderSide(color: colors[g.tier]!, width: 4)),
            color: _ivory,
          ),
          child: pw.Row(children: [
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(g.tier.label, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _ink)),
                pw.Text(g.tier.rule, style: const pw.TextStyle(fontSize: 8, color: _muted)),
              ]),
            ),
            pw.Text(tr('{0} öğrenci · ort. {1}', [g.members.length, L10n.percent(g.meanPct.round())]),
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          ]),
        ),
        pw.Text(
          [for (final m in g.members) students[m.sheet.studentId]?.fullName ?? tr('Eşleşmeyen kâğıt')].join(', '),
          style: const pw.TextStyle(fontSize: 9),
        ),
        if (g.weakOutcomes.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          pw.Text(tr('Odaklanılacak kazanımlar'), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          for (final (code, rate) in g.weakOutcomes)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2),
              child: pw.Row(children: [
                pw.SizedBox(width: 170, child: pw.Text(code, style: const pw.TextStyle(fontSize: 8), maxLines: 1)),
                pw.Expanded(child: k.hbar(rate, rate >= 0.5 ? _amber : _coral, height: 6)),
                pw.SizedBox(width: 34, child: pw.Text(_pct(rate), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8))),
              ]),
            ),
        ],
        if (g.misconceptions.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          pw.Text(tr('Grupta sık görülen yanılgılar'), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          for (final (m, n) in g.misconceptions) pw.Text('• $m ($n)', style: const pw.TextStyle(fontSize: 8.5)),
        ],
        pw.SizedBox(height: 6),
        pw.Text(tr('Önerilen çalışma'), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        for (final p in g.tier.plan) pw.Text('• $p', style: const pw.TextStyle(fontSize: 8.5)),
      ],
      k.signatures(),
    ],
  ));
  return doc.save();
}

/// Sınav sonrası öğrenci değerlendirme kâğıdı (exam wrapper): öğrenci her
/// yanlışının nedenini işaretler, hazırlanmasını ve sonraki planını yazar.
Future<Uint8List> buildReflectionPdf({
  required Exam exam,
  required List<Result> results,
  required Map<String, Student> students,
  SchoolInfo school = const SchoolInfo(),
  String? onlyStudentId,
}) async {
  final fonts = await _Fonts.load(school.fontFamily);
  final k = _Kit(exam, school, docTitle: tr('Sınav Sonrası Öğrenci Değerlendirme Kâğıdı'), letterheadEveryPage: true);
  final doc = pw.Document(theme: fonts.theme, title: tr('{0} değerlendirme kâğıtları', [exam.name]), author: tr('Netice'));
  final reasons = [tr('Dikkatsizlik'), tr('Konuyu bilmiyordum'), tr('Soruyu yanlış anladım'), tr('İşlem hatası'), tr('Süre yetmedi')];
  pw.Widget box() => pw.Container(
        width: 9,
        height: 9,
        decoration: pw.BoxDecoration(border: pw.Border.all(color: _ink, width: 0.8), borderRadius: pw.BorderRadius.circular(1.5)),
      );
  pw.Widget lines(int n) => pw.Column(children: [
        for (var i = 0; i < n; i++)
          pw.Container(
            height: 18,
            decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.8))),
          ),
      ]);
  pw.Widget check(String s) => pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
        box(),
        pw.SizedBox(width: 4),
        pw.Text(s, style: const pw.TextStyle(fontSize: 8.5)),
        pw.SizedBox(width: 12),
      ]);

  final list = [
    for (final r in results)
      if (onlyStudentId == null || r.sheet.studentId == onlyStudentId) r,
  ]..sort((a, b) => (students[a.sheet.studentId]?.number ?? '').padLeft(10, '0').compareTo((students[b.sheet.studentId]?.number ?? '').padLeft(10, '0')));
  for (final res in list) {
    final stu = students[res.sheet.studentId];
    final missed = [
      for (var i = 0; i < exam.questionCount; i++)
        if (res.outcomes[i] == Outcome.wrong || res.outcomes[i] == Outcome.blank) i,
    ];
    doc.addPage(pw.MultiPage(
      textDirection: _dir,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 30, 36, 30),
      header: k.header,
      footer: k.footer,
      build: (ctx) => [
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(color: _ivory, borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Row(children: [
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(stu?.fullName ?? tr('Eşleşmeyen kâğıt'), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.Text('${tr('No')} ${stu?.number ?? '–'} · ${stu?.className ?? exam.className} · ${exam.name}',
                    style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
              ]),
            ),
            pw.Text('${_f1(res.score)} / ${exam.rule.maxScore.round()}', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          ]),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
            tr('Bu kâğıt not için değil, öğrenmen için. Her yanlışının yanına nedenini işaretle; böylece bir sonraki sınavda neye dikkat edeceğini bulursun.'),
            style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
        k.title(tr('1. Yanlış ya da boş bıraktığım sorular')),
        if (missed.isEmpty)
          pw.Text(tr('Tebrikler, hiç yanlışın yok! Aşağıdaki bölümleri yine de doldur.'), style: const pw.TextStyle(fontSize: 9))
        else
          pw.Table(
            border: pw.TableBorder.all(color: _line, width: 0.6),
            columnWidths: {
              0: const pw.FixedColumnWidth(30),
              1: const pw.FlexColumnWidth(2.2),
              2: const pw.FixedColumnWidth(44),
              for (var i = 0; i < reasons.length; i++) 3 + i: const pw.FlexColumnWidth(1),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: _ink),
                children: [
                  for (final h in [tr('Soru'), tr('Konu'), tr('Cevabım / doğru'), ...reasons])
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(3),
                      child: pw.Text(h,
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(fontSize: 6.8, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
                    ),
                ],
              ),
              for (final i in missed)
                pw.TableRow(children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('${i + 1}', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8.5))),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text(exam.questions[i].outcomeCode ?? '', maxLines: 1, style: const pw.TextStyle(fontSize: 7.5)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text(
                        '${_answer(res.sheet.answers[i])} / ${exam.questionAt(res.sheet.booklet, i).correct.map(_letter).join('/')}',
                        textAlign: pw.TextAlign.center,
                        style: const pw.TextStyle(fontSize: 8)),
                  ),
                  for (var r = 0; r < reasons.length; r++) pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Center(child: box())),
                ]),
            ],
          ),
        k.title(tr('2. Bu sınava nasıl hazırlandım?')),
        pw.Wrap(runSpacing: 6, children: [
          check(tr('Ders notlarımı okudum')),
          check(tr('Soru çözdüm')),
          check(tr('Arkadaşımla çalıştım')),
          check(tr('Konu tekrarı yaptım')),
          check(tr('Son gece çalıştım')),
          check(tr('Hazırlanamadım')),
        ]),
        pw.SizedBox(height: 6),
        pw.Text(tr('Toplam kaç saat çalıştım? ______     Puanımı önceden kaç tahmin etmiştim? ______'), style: const pw.TextStyle(fontSize: 8.5)),
        k.title(tr('3. Bir sonraki sınav için planım')),
        lines(3),
        k.title(tr('4. Öğretmenimden istediğim yardım')),
        lines(2),
        pw.SizedBox(height: 16),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(tr('Öğrenci imzası: ____________'), style: const pw.TextStyle(fontSize: 8.5)),
          pw.Text(tr('Veli imzası: ____________'), style: const pw.TextStyle(fontSize: 8.5)),
        ]),
      ],
    ));
  }
  if (list.isEmpty) {
    doc.addPage(pw.Page(textDirection: _dir, build: (_) => pw.Center(child: pw.Text(tr('Henüz okunan kâğıt yok.')))));
  }
  return doc.save();
}
