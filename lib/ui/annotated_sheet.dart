import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../core/models.dart';
import '../core/scoring.dart';
import '../omr/form_layout.dart';
import 'theme.dart';

/// İşaretli kâğıt: düzleştirilmiş kâğıt fotoğrafının üzerine her soru için
/// doğru (yeşil halka), yanlış (kırmızı halka + doğru şık yeşil kesik halka),
/// boş (doğru şık sarı kesik halka) ve iptal (gri çizgi) işaretleri çizilir.
class AnnotatedSheet extends StatelessWidget {
  final Uint8List jpeg;
  final Exam exam;
  final Result result;

  /// Kâğıdın kitapçığı; B ise daireler B sırasına göre gösterilir.
  final int booklet;
  const AnnotatedSheet({super.key, required this.jpeg, required this.exam, required this.result, this.booklet = 0});

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: FormLayout.pageWidth / FormLayout.pageHeight,
        child: Stack(fit: StackFit.expand, children: [
          Image.memory(jpeg, fit: BoxFit.fill, gaplessPlayback: true),
          CustomPaint(painter: SheetMarksPainter(exam: exam, result: result, booklet: booklet)),
        ]),
      );
}

class SheetMarksPainter extends CustomPainter {
  final Exam exam;
  final Result result;
  final int booklet;
  final bool drawScore;
  SheetMarksPainter({required this.exam, required this.result, this.booklet = 0, this.drawScore = true});

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / FormLayout.pageWidth;
    final layout = FormLayout(questionCount: exam.questionCount, choiceCount: exam.choiceCount, booklets: exam.hasBooklets);
    Offset at(Pt p) => Offset(p.x * k, p.y * k);
    final r = FormLayout.bubbleRadius * k * 1.45;
    final sw = 0.55 * k;
    Paint ring(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw;
    void dashed(Offset c, Color col) {
      const n = 10;
      for (var i = 0; i < n; i++) {
        final a = i * 2 * 3.14159265 / n;
        canvas.drawArc(Rect.fromCircle(center: c, radius: r), a, 3.14159265 / n, false, ring(col));
      }
    }

    // A sırasındaki soru i, B kitapçığında hangi satırda basılı?
    final order = exam.bookletOrder;
    int printedRow(int aIndex) {
      if (booklet != 1 || order == null) return aIndex;
      final b = order.indexOf(aIndex);
      return b < 0 ? aIndex : b;
    }

    for (var i = 0; i < exam.questionCount; i++) {
      final q = exam.questions[i];
      final row = printedRow(i);
      final marked = result.sheet.answers[i].marked;
      if (q.cancelled) {
        final a = at(layout.answerBubble(row, 0));
        final b = at(layout.answerBubble(row, exam.choiceCount - 1));
        canvas.drawLine(a - Offset(r, 0), b + Offset(r, 0), Paint()
          ..color = NColors.gray
          ..strokeWidth = sw);
        continue;
      }
      final outcome = result.outcomes[i];
      for (final c in marked) {
        canvas.drawCircle(at(layout.answerBubble(row, c)), r,
            ring(q.correct.contains(c) && outcome == Outcome.correct ? NColors.emerald : NColors.coral));
      }
      if (outcome != Outcome.correct) {
        for (final c in q.correct) {
          if (marked.contains(c)) continue;
          dashed(at(layout.answerBubble(row, c)), outcome == Outcome.blank ? NColors.amber : NColors.emerald);
        }
      }
      // Satır sonunda onay / çarpı / çizgi
      final end = at(layout.answerBubble(row, exam.choiceCount - 1)) + Offset(r * 2.3, 0);
      final m = r * 0.75;
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw * 1.3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      switch (outcome) {
        case Outcome.correct:
          canvas.drawPath(
              Path()
                ..moveTo(end.dx, end.dy)
                ..lineTo(end.dx + m * 0.6, end.dy + m * 0.6)
                ..lineTo(end.dx + m * 1.6, end.dy - m * 0.7),
              p..color = NColors.emerald);
        case Outcome.wrong:
          p.color = NColors.coral;
          canvas.drawLine(end + Offset(0, -m * 0.6), end + Offset(m * 1.2, m * 0.6), p);
          canvas.drawLine(end + Offset(0, m * 0.6), end + Offset(m * 1.2, -m * 0.6), p);
        default:
          canvas.drawLine(end, end + Offset(m * 1.2, 0), p..color = NColors.amber);
      }
    }

    if (drawScore) {
      // Sağ üstte puan rozeti
      final box = RRect.fromRectAndRadius(Rect.fromLTWH(size.width - 58 * k, 246 * k, 38 * k, 18 * k), Radius.circular(3 * k));
      canvas.drawRRect(box, Paint()..color = NColors.ink.withValues(alpha: 0.92));
      final tp = TextPainter(
        text: TextSpan(children: [
          TextSpan(
              text: result.score.toStringAsFixed(result.score % 1 == 0 ? 0 : 1).replaceAll('.', ','),
              style: TextStyle(fontFamily: 'PlusJakartaSans', color: Colors.white, fontSize: 9 * k, fontWeight: FontWeight.w900)),
          TextSpan(
              text: '\n${result.correct} D · ${result.wrong} Y · ${result.blank} B',
              style: TextStyle(fontFamily: 'PlusJakartaSans', color: Colors.white70, fontSize: 2.9 * k, fontWeight: FontWeight.w600)),
        ]),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(minWidth: box.width, maxWidth: box.width);
      tp.paint(canvas, Offset(box.left, box.top + (box.height - tp.height) / 2));
    }
  }

  @override
  bool shouldRepaint(SheetMarksPainter o) => o.result != result;
}
