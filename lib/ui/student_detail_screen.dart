import 'package:material_ui/material_ui.dart';

import '../core/models.dart';
import '../core/progress.dart';
import '../main.dart';
import 'exam_screen.dart';
import 'sheet_image_screen.dart';
import 'theme.dart';
import 'widgets.dart';
import '../l10n/l10n.dart';
import '../core/ads.dart';
import 'ad_slot.dart';

/// Öğrencinin sınav geçmişi, gelişim grafiği ve güçlü/zayıf kazanımları.
class StudentDetailScreen extends StatelessWidget {
  final String studentId;
  final Future<void> Function(Student)? onEdit;
  const StudentDetailScreen({super.key, required this.studentId, this.onEdit});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final s = store.studentById[studentId];
    if (s == null) {
      // Öğrenci silindiyse ekranı kapat.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
      });
      return const Scaffold();
    }
    final h = historyOf(store, s);
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurface.withValues(alpha: 0.6);
    final warn = earlyWarnings(store).where((w) => w.student.id == s.id).firstOrNull;
    final avg = h.isEmpty ? 0.0 : h.map((e) => e.pct).reduce((a, b) => a + b) / h.length;
    final trend = h.length < 2 ? null : h.last.pct - h[h.length - 2].pct;
    final summary = outcomeSummary(h).entries.toList()..sort((a, b) => b.value.$1.compareTo(a.value.$1));

    return Scaffold(
      appBar: AppBar(title: Text(tr('Öğrenci')), actions: [
        if (onEdit != null)
          IconButton(tooltip: tr('Düzenle'), icon: const Icon(Icons.edit_outlined), onPressed: () => onEdit!(s)),
      ]),
      bottomNavigationBar: const AdBannerBar(AdPage.student),
      body: Watermark(
        child: ListView(padding: EdgeInsets.fromLTRB(20, 8, 20, 32 + MediaQuery.paddingOf(context).bottom), children: [
          HeroPanel(
            child: Row(children: [
              ScoreRing(
                value: avg,
                size: 92,
                track: Colors.white.withValues(alpha: 0.14),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22, fontFeatures: tabular),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.fullName,
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                  Text('${tr('No')} ${s.number} · ${s.className}', style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 18, runSpacing: 8, children: [
                    _Mini(tr('Sınav'), '${h.length}'),
                    _Mini(tr('Ortalama'), L10n.percent(avg.round())),
                    if (trend != null) _Mini(tr('Son değişim'), '${trend >= 0 ? '+' : ''}${trend.round()}'),
                  ]),
                ]),
              ),
            ]),
          ),
          if (warn != null) ...[
            const SizedBox(height: 12),
            Card(
              color: NColors.amber.withValues(alpha: 0.14),
              child: ListTile(
                leading: const Icon(Icons.priority_high_rounded, color: NColors.amber),
                title: Text(tr('Destek gerekebilir'), style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(tr('{0}{1}. Bu yalnızca size gösterilen bir hatırlatmadır.', [warn.reason[0].toUpperCase(), warn.reason.substring(1)])),
              ),
            ),
          ],
          if (h.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: 24),
              child: Text(tr('Bu öğrencinin henüz okunmuş bir kâğıdı yok.')),
            )
          else ...[
            SectionTitle(tr('Gelişim')),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 18, 16, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(height: 170, child: _TrendChart(h)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 16, children: [
                    _Legend(NColors.emerald, tr('Öğrenci')),
                    _Legend(t.colorScheme.onSurface.withValues(alpha: 0.35), tr('Sınıf ortalaması')),
                  ]),
                ]),
              ),
            ),
            SectionTitle(tr('Sınavlar')),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (final e in h.reversed)
                  ListTile(
                    title: Text(e.exam.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(tr('{0} · Sıra {1}/{2} · Sınıf ort. {3} · {4}', [dmy(e.exam.date), e.standing.rank, e.classSize, fmt1(e.classMean), e.standing.level.name])),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(fmt1(e.standing.result.score),
                          style: t.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontFeatures: tabular,
                              color: e.passed ? null : NColors.coral)),
                      if (hasSheetImage(context, e.standing.result.sheet))
                        IconButton(
                          tooltip: tr('İşaretli kâğıt'),
                          icon: const Icon(Icons.image_search_rounded),
                          onPressed: () => openSheetImage(context, e.exam, e.standing.result),
                        ),
                      IconButton(
                        tooltip: tr('Karneyi önizle'),
                        icon: const Icon(Icons.badge_outlined),
                        onPressed: () => openCardsPreview(context, e.exam, studentId: s.id),
                      ),
                      IconButton(
                        tooltip: tr('Karneyi veliye gönder'),
                        icon: const Icon(Icons.send_outlined),
                        onPressed: () => shareStudentCard(context, e.exam, s.id),
                      ),
                    ]),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => ExamScreen(examId: e.exam.id))),
                  ),
              ]),
            ),
            if (summary.isNotEmpty) ...[
              SectionTitle(tr('Kazanımlar (tüm sınavlar)')),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    for (final e in summary)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600))),
                            Text(L10n.percent((e.value.$1 * 100).round()),
                                style: const TextStyle(fontWeight: FontWeight.w800, fontFeatures: tabular)),
                            Text(tr('  sınıf %{0}', [(e.value.$2 * 100).round()]), style: TextStyle(color: muted, fontSize: 12)),
                          ]),
                          const SizedBox(height: 5),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: e.value.$1,
                              minHeight: 9,
                              color: e.value.$1 >= 0.7
                                  ? NColors.emerald
                                  : e.value.$1 >= 0.5
                                      ? NColors.amber
                                      : NColors.coral,
                              backgroundColor: t.colorScheme.surfaceContainerHighest,
                            ),
                          ),
                        ]),
                      ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        tr('Güçlü: {0}{1}', [summary.first.key, summary.length > 1 ? tr(' · Geliştirilmeli: {0}', [summary.last.key]) : '']),
                        style: TextStyle(color: muted),
                      ),
                    ),
                  ]),
                ),
              ),
            ],
          ],
        ]),
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  final String label, value;
  const _Mini(this.label, this.value);
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, fontFeatures: tabular)),
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
      ]);
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend(this.color, this.label);
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 14, height: 4, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

/// Öğrenci yüzdesi ve sınıf ortalaması (yüzde) çizgi grafiği.
class _TrendChart extends StatelessWidget {
  final List<HistoryEntry> h;
  const _TrendChart(this.h);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return CustomPaint(
      painter: _TrendPainter(
        student: [for (final e in h) e.pct],
        klass: [for (final e in h) e.exam.rule.maxScore == 0 ? 0 : e.classMean / e.exam.rule.maxScore * 100],
        labels: [for (final e in h) '${e.exam.date.day}.${e.exam.date.month}'],
        font: t.textTheme.bodySmall?.fontFamily,
        grid: t.colorScheme.outlineVariant,
        muted: t.colorScheme.onSurface.withValues(alpha: 0.35),
        text: t.colorScheme.onSurface.withValues(alpha: 0.6),
      ),
      size: Size.infinite,
    );
  }
}

class _TrendPainter extends CustomPainter {
  final List<double> student, klass;
  final List<String> labels;
  final Color grid, muted, text;
  final String? font;
  _TrendPainter(
      {required this.student,
      required this.klass,
      required this.labels,
      required this.grid,
      required this.muted,
      required this.text,
      this.font});

  @override
  void paint(Canvas canvas, Size size) {
    const left = 30.0, bottom = 20.0;
    final w = size.width - left - 8, hgt = size.height - bottom - 6;
    final g = Paint()
      ..color = grid
      ..strokeWidth = 1;
    void label(String s, Offset o, {bool center = false}) {
      final tp = TextPainter(
          text: TextSpan(text: s, style: TextStyle(color: text, fontSize: 10, fontFamily: font)), textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, center ? o - Offset(tp.width / 2, 0) : o - Offset(tp.width, tp.height / 2));
    }

    for (final v in [0, 50, 100]) {
      final y = 6 + hgt * (1 - v / 100);
      canvas.drawLine(Offset(left, y), Offset(left + w, y), g);
      label('$v', Offset(left - 6, y));
    }
    Offset pt(int i, double v) =>
        Offset(left + (student.length == 1 ? w / 2 : w * i / (student.length - 1)), 6 + hgt * (1 - v.clamp(0, 100) / 100));
    void line(List<double> vs, Color c, double width, {bool dots = true}) {
      final p = Path();
      for (var i = 0; i < vs.length; i++) {
        i == 0 ? p.moveTo(pt(i, vs[i]).dx, pt(i, vs[i]).dy) : p.lineTo(pt(i, vs[i]).dx, pt(i, vs[i]).dy);
      }
      canvas.drawPath(
          p,
          Paint()
            ..color = c
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round);
      if (dots) {
        for (var i = 0; i < vs.length; i++) {
          canvas.drawCircle(pt(i, vs[i]), width + 2, Paint()..color = c);
        }
      }
    }

    line(klass, muted, 2, dots: false);
    line(student, NColors.emerald, 3);
    for (var i = 0; i < labels.length; i++) {
      label(labels[i], Offset(pt(i, 0).dx, size.height - bottom + 5), center: true);
    }
  }

  @override
  bool shouldRepaint(_TrendPainter o) => o.student != student || o.klass != klass;
}
