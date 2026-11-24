// Çocuk (ilkokul) kitapçığının köşesindeki küçük cevap kutusu: geometri,
// okuma ve düzleştirme.
//
// Kutu, A4 Netice formundan bağımsız, kendi dört köşe karesi olan küçük bir
// formdur. Öğretmen yalnızca kutuyu ya da sayfanın tamamını çekebilir:
// okuyucu, görüntüdeki kare adayları arasından kutunun oranına uyan ve
// daireleri beklenen yerde olan dörtlüyü seçer.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../core/models.dart';
import 'form_code.dart';
import 'form_layout.dart';
import 'homography.dart';
import 'omr_reader.dart';

/// Cevap kutusunun geometrisi (mm, kutunun sol üst köşesi 0,0).
class KidLayout {
  final int questionCount;
  final int choiceCount;

  /// Bir sütundaki soru sayısı.
  static const perColumn = 10;

  /// En fazla soru (3 sütun).
  static const maxQuestions = 30;

  static const markerSize = 6.5;
  static const bubbleRadius = 2.0;
  static const choicePitch = 5.4;
  static const rowPitch = 5.0;

  /// İlk satırın (1. soru) dairelerinin merkez yüksekliği.
  static const answersTop = 19.0;

  /// Başlık ve "Adım" satırları (kutunun üst bandı).
  static const titleTop = 1.2;
  static const nameTop = 8.6;

  /// Makine kodu: 2 satır × 22 kare.
  static const codePerRow = 22;
  static const codePitch = 2.2;
  static const codeRowPitch = 2.6;
  static const codeCellSize = 1.5;

  /// Soru numarasından ilk daireye kadar olan mesafe ve sütunlar arası boşluk.
  static const _labelW = 7.5;
  static const _colGap = 6.0;
  static const _side = 7.0;
  static const minWidth = 66.0;

  KidLayout({required this.questionCount, required this.choiceCount}) {
    if (questionCount < 1 || questionCount > maxQuestions) {
      throw ArgumentError('Soru sayısı 1–$maxQuestions arasında olmalı');
    }
    if (choiceCount < 2 || choiceCount > 5) {
      throw ArgumentError('Şık sayısı 2–5 arasında olmalı');
    }
  }

  int get columns => (questionCount / perColumn).ceil();
  int get rows => math.min(questionCount, perColumn);

  double get _blockWidth => _labelW + (choiceCount - 1) * choicePitch + bubbleRadius + _colGap;

  double get width => math.max(minWidth, 2 * _side + columns * _blockWidth - _colGap + 2);

  /// Cevap sütunlarının başladığı x (ortalanmış).
  double get _answersLeft => (width - (columns * _blockWidth - _colGap)) / 2;

  double get _lastRowY => answersTop + (rows - 1) * rowPitch;
  double get codeTop => _lastRowY + 6.0;
  double get height => codeTop + codeRowPitch + 2.5 + markerSize;

  double get aspect => height / width;

  /// Köşe karelerinin sol üst köşeleri: sol üst, sağ üst, sağ alt, sol alt.
  List<Pt> get markerOrigins => [
        const Pt(0, 0),
        Pt(width - markerSize, 0),
        Pt(width - markerSize, height - markerSize),
        Pt(0, height - markerSize),
      ];

  List<Pt> get markerCenters => [for (final o in markerOrigins) Pt(o.x + markerSize / 2, o.y + markerSize / 2)];

  /// Soru [index] (0'dan), şık [choice] (0 = A) dairesinin merkezi.
  Pt answerBubble(int index, int choice) {
    final col = index ~/ perColumn, row = index % perColumn;
    return Pt(_answersLeft + col * _blockWidth + _labelW + choice * choicePitch, answersTop + row * rowPitch);
  }

  /// Soru numarasının sağ kenarı (dairelerin solunda).
  Pt questionLabel(int index) {
    final b = answerBubble(index, 0);
    return Pt(b.x - bubbleRadius - 1.4, b.y);
  }

  /// Makine kodunun [i]. karesinin merkezi.
  Pt codeCell(int i) {
    final row = i ~/ codePerRow, col = i % codePerRow;
    final left = (width - (codePerRow - 1) * codePitch) / 2;
    return Pt(left + col * codePitch, codeTop + row * codeRowPitch);
  }
}

/// Köşedeki cevap kutusunu okur.
class KidReader {
  final KidLayout layout;
  final OmrThresholds thresholds;
  KidReader(this.layout, {this.thresholds = const OmrThresholds()});

  OmrResult read(GrayImage image) {
    _Found? best;
    for (final adaptive in [false, true]) {
      final f = _find(image, adaptive);
      if (f != null && (best == null || f.score > best.score)) best = f;
      if (best != null && best.score >= _goodScore) break;
    }
    if (best == null || best.score < _minScore) {
      throw const OmrException(
          'Cevap kutusu bulunamadı. Sayfanın köşesindeki cevap kutusunu, dört siyah karesi görünecek şekilde yakından çekin.');
    }
    final markers = best.markers;
    final hom = Homography.fromPoints(layout.markerCenters, markers);

    final mr = KidLayout.markerSize * 0.3 * hom.scaleAt(layout.markerCenters.first);
    var black = 0.0;
    for (final m in markers) {
      black += OmrReader.meanInDisk(image, m, mr);
    }
    black /= 4;

    double fillAt(Pt p, double radius, double whiteHalf) {
      final c = hom.map(p);
      final scale = hom.scaleAt(p);
      final white = OmrReader.localWhite(image, c, whiteHalf * scale);
      final mean = OmrReader.meanInDisk(image, c, radius * scale);
      final range = white - black;
      if (range < 20) return 0;
      return ((white - mean) / range).clamp(0.0, 1.0);
    }

    final questions = <OmrQuestion>[];
    for (var q = 0; q < layout.questionCount; q++) {
      final fills = [
        for (var c = 0; c < layout.choiceCount; c++)
          fillAt(layout.answerBubble(q, c), KidLayout.bubbleRadius * 0.62, KidLayout.bubbleRadius * 1.8)
      ];
      questions.add(OmrQuestion(OmrReader.classifyFills(fills, thresholds), fills));
    }

    final bits = [
      for (var i = 0; i < FormCode.cells; i++) fillAt(layout.codeCell(i), KidLayout.codeCellSize * 0.3, KidLayout.codeCellSize * 1.1) > 0.5
    ];

    return OmrResult(
      questions: questions,
      studentNumber: null,
      markers: markers,
      code: FormCode.decode(bits),
    );
  }

  static const _minScore = 10.0;
  static const _goodScore = 25.0;

  /// Kare adayları arasından kutunun köşelerini arar.
  _Found? _find(GrayImage image, bool adaptive) {
    var cands = OmrReader.markerCandidates(image, adaptive: adaptive, maxSideFraction: 0.3);
    if (cands.length < 4) return null;
    cands.sort((a, b) => b.area.compareTo(a.area));
    if (cands.length > 28) cands = cands.sublist(0, 28);
    final n = cands.length;
    final wantAspect = layout.aspect;
    _Found? best;
    for (var a = 0; a < n; a++) {
      for (var b = a + 1; b < n; b++) {
        for (var c = b + 1; c < n; c++) {
          for (var d = c + 1; d < n; d++) {
            final four = [cands[a], cands[b], cands[c], cands[d]];
            final sides = four.map((e) => e.side);
            final smin = sides.reduce(math.min), smax = sides.reduce(math.max);
            if (smax > smin * 1.45) continue;
            final pts = _clockwise([for (final e in four) e.center]);
            final e = [for (var i = 0; i < 4; i++) _dist(pts[i], pts[(i + 1) % 4])];
            // Karşılıklı kenarlar benzer olmalı (perspektif payıyla).
            if (_ratio(e[0], e[2]) > 1.6 || _ratio(e[1], e[3]) > 1.6) continue;
            final h = (e[0] + e[2]) / 2, v = (e[1] + e[3]) / 2;
            final shortEdge = math.min(h, v);
            // Kare boyutu kutuya göre: kenar ≈ 6,5 mm, kutu ≥ 66 mm.
            final rel = (smin + smax) / 2 / shortEdge;
            final expect = KidLayout.markerSize / (math.min(layout.width, layout.height) - KidLayout.markerSize);
            if (rel < expect * 0.55 || rel > expect * 1.8) continue;
            final asp = math.max(h, v) / shortEdge;
            final want = math.max(wantAspect, 1 / wantAspect);
            if (_ratio(asp, want) > 1.3) continue;
            // Dört yönü dene; daireler en iyi oturanı seç.
            for (var k = 0; k < 4; k++) {
              final cand = [for (var i = 0; i < 4; i++) pts[(i + k) % 4]];
              final s = _ringScore(image, cand);
              if (best == null || s > best.score) best = _Found(cand, s);
            }
          }
        }
      }
    }
    return best;
  }

  double _ringScore(GrayImage image, List<Pt> markers) {
    final Homography hom;
    try {
      hom = Homography.fromPoints(layout.markerCenters, markers);
    } catch (_) {
      return double.negativeInfinity;
    }
    var ring = 0.0, gap = 0.0;
    var n = 0;
    for (var q = 0; q < math.min(layout.questionCount, 14); q++) {
      for (var ch = 0; ch < layout.choiceCount; ch += math.max(1, layout.choiceCount - 1)) {
        final c = layout.answerBubble(q, ch);
        for (var a = 0; a < 12; a++) {
          final ang = a * math.pi / 6;
          const r = KidLayout.bubbleRadius;
          final pr = hom.map(Pt(c.x + r * math.cos(ang), c.y + r * math.sin(ang)));
          final pg = hom.map(Pt(c.x + r * 1.3 * math.cos(ang), c.y + r * 1.3 * math.sin(ang)));
          if (!_inside(image, pr) || !_inside(image, pg)) return double.negativeInfinity;
          ring += image.at(pr.x.round(), pr.y.round());
          gap += image.at(pg.x.round(), pg.y.round());
          n++;
        }
      }
    }
    return n == 0 ? double.negativeInfinity : (gap - ring) / n;
  }

  static bool _inside(GrayImage im, Pt p) => p.x >= 0 && p.y >= 0 && p.x < im.width - 0.5 && p.y < im.height - 0.5;
  static double _dist(Pt a, Pt b) => math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
  static double _ratio(double a, double b) => a > b ? a / math.max(b, 1e-9) : b / math.max(a, 1e-9);

  /// Noktaları ağırlık merkezi etrafında görüntüde saat yönüne dizer.
  static List<Pt> _clockwise(List<Pt> p) {
    final cx = p.fold(0.0, (s, e) => s + e.x) / p.length, cy = p.fold(0.0, (s, e) => s + e.y) / p.length;
    final l = [...p]..sort((a, b) => math.atan2(a.y - cy, a.x - cx).compareTo(math.atan2(b.y - cy, b.x - cx)));
    return l;
  }
}

class _Found {
  final List<Pt> markers;
  final double score;
  _Found(this.markers, this.score);
}

/// Okunan kutunun düzleştirilmiş JPEG görüntüsü (öğretmenin kontrolü için).
Uint8List kidSheetJpeg(GrayImage g, KidLayout layout, List<Pt> markers, {double pxPerMm = 8}) {
  final hom = Homography.fromPoints(layout.markerCenters, markers);
  final w = (layout.width * pxPerMm).round(), h = (layout.height * pxPerMm).round();
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = hom.map(Pt(x / pxPerMm, y / pxPerMm));
      final x0 = p.x.floor(), y0 = p.y.floor();
      if (x0 < 0 || y0 < 0 || x0 + 1 >= g.width || y0 + 1 >= g.height) {
        out[y * w + x] = 255;
        continue;
      }
      final ax = p.x - x0, ay = p.y - y0;
      final v = g.at(x0, y0) * (1 - ax) * (1 - ay) +
          g.at(x0 + 1, y0) * ax * (1 - ay) +
          g.at(x0, y0 + 1) * (1 - ax) * ay +
          g.at(x0 + 1, y0 + 1) * ax * ay;
      out[y * w + x] = v.round().clamp(0, 255);
    }
  }
  final im = img.Image.fromBytes(width: w, height: h, bytes: out.buffer, numChannels: 1);
  return Uint8List.fromList(img.encodeJpg(im.convert(numChannels: 3), quality: 75));
}

/// Sınav için kutu düzeni (çocuk formu değilse null).
KidLayout? kidLayoutFor(Exam exam) => exam.kidForm
    ? KidLayout(
        questionCount: exam.questionCount.clamp(1, KidLayout.maxQuestions), choiceCount: exam.choiceCount.clamp(2, 5))
    : null;
