import 'dart:math' as math;
import 'dart:typed_data';

import 'form_layout.dart';
import 'omr_reader.dart';

/// Kamera karesi için canlı ipucu.
enum FrameAdvice {
  /// Her şey yolunda (ya da söylenecek belirgin bir sorun yok).
  ok,

  /// Ortam çok karanlık.
  tooDark,

  /// Kâğıtta parlama / yansıma var.
  glare,

  /// Görüntü bulanık (telefon sallanıyor ya da odak yok).
  blurry,

  /// Kâğıt çok uzakta, çerçevenin küçük bir kısmını kaplıyor.
  tooFar,

  /// Telefon kâğıda paralel değil (kâğıt yamuk görünüyor).
  tilted,

  /// Kâğıdın bir köşesi çerçevenin kenarına çok yakın / dışarıda.
  edge,
}

/// Ölçülen değerler (test ve ayar için dışa açık).
class FrameStats {
  final double mean;
  final double glare;
  final double sharpness;
  final double? coverage;
  final double? squareness;
  final double? edgeMargin;
  const FrameStats({
    required this.mean,
    required this.glare,
    required this.sharpness,
    this.coverage,
    this.squareness,
    this.edgeMargin,
  });

  @override
  String toString() => 'mean=${mean.toStringAsFixed(0)} glare=${(glare * 100).toStringAsFixed(1)}% '
      'sharp=${sharpness.toStringAsFixed(3)} cover=${coverage?.toStringAsFixed(2)} '
      'square=${squareness?.toStringAsFixed(2)} edge=${edgeMargin?.toStringAsFixed(3)}';
}

/// Kareyi hızlıca değerlendirir. [markers] okuma başarılıysa bulunan köşe
/// işaretleridir; yoksa yalnızca ışık ve netlik ölçülür.
class FrameQuality {
  static const darkMean = 55.0;
  static const glareFraction = 0.035;
  static const minSharpness = 0.3;
  static const minCoverage = 0.22;
  static const minSquareness = 0.72;
  static const minEdgeMargin = 0.012;

  static FrameStats measure(GrayImage g, {List<Pt>? markers}) {
    // ~640 piksele küçült: hızlı ve küçük titreşimlere duyarsız.
    final f = math.max(1, (math.max(g.width, g.height) / 640).ceil());
    final w = g.width ~/ f, h = g.height ~/ f;
    final small = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var s = 0;
        for (var dy = 0; dy < f; dy++) {
          final row = (y * f + dy) * g.width + x * f;
          for (var dx = 0; dx < f; dx++) {
            s += g.data[row + dx];
          }
        }
        small[y * w + x] = s ~/ (f * f);
      }
    }
    final hist = List<int>.filled(256, 0);
    var sum = 0;
    for (final v in small) {
      hist[v]++;
      sum += v;
    }
    final n = small.length;
    final mean = sum / n;
    // Kontrast aralığı (yüzdelik 2 – 98).
    int pct(double p) {
      final target = n * p;
      var acc = 0;
      for (var v = 0; v < 256; v++) {
        acc += hist[v];
        if (acc >= target) return v;
      }
      return 255;
    }

    final range = math.max(24, pct(0.98) - pct(0.02));
    // Netlik: en güçlü kenarlardaki eğimin kontrasta oranı.
    final grads = List<int>.filled(256, 0);
    var gn = 0;
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final i = y * w + x;
        final gx = (small[i + 1] - small[i - 1]).abs();
        final gy = (small[i + w] - small[i - w]).abs();
        grads[math.min(255, math.max(gx, gy))]++;
        gn++;
      }
    }
    var acc = 0, p995 = 0;
    for (var v = 255; v >= 0; v--) {
      acc += grads[v];
      if (acc >= gn * 0.005) {
        p995 = v;
        break;
      }
    }
    final sharpness = p995 / range;

    // Parlama: kâğıt bölgesinin genel beyazı doymamışken içinde patlamış beyaz
    // lekeler. Tarayıcı görüntüsünde kâğıdın tamamı beyazdır; parlama sayılmaz.
    var x0 = w * 0.2, x1 = w * 0.8, y0 = h * 0.2, y1 = h * 0.8;
    if (markers != null && markers.length == 4) {
      x0 = markers.map((p) => p.x).reduce(math.min) / f;
      x1 = markers.map((p) => p.x).reduce(math.max) / f;
      y0 = markers.map((p) => p.y).reduce(math.min) / f;
      y1 = markers.map((p) => p.y).reduce(math.max) / f;
    }
    final rh = List<int>.filled(256, 0);
    var rn = 0;
    for (var y = math.max(0, y0.floor()); y < math.min(h, y1.ceil()); y++) {
      for (var x = math.max(0, x0.floor()); x < math.min(w, x1.ceil()); x++) {
        rh[small[y * w + x]]++;
        rn++;
      }
    }
    var glare = 0.0;
    if (rn > 0) {
      // Bölgenin parlak çeyreği (kâğıt) doymuşsa bu parlama değil, beyaz kâğıttır.
      var a = 0, paper = 255;
      for (var v = 0; v < 256; v++) {
        a += rh[v];
        if (a >= rn * 0.7) {
          paper = v;
          break;
        }
      }
      if (paper < 236) glare = (rh[252] + rh[253] + rh[254] + rh[255]) / rn;
    }

    double? coverage, squareness, edge;
    if (markers != null && markers.length == 4) {
      coverage = _area(markers) / (g.width * g.height);
      double d(Pt a, Pt b) => math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
      final s = [for (var i = 0; i < 4; i++) d(markers[i], markers[(i + 1) % 4])];
      final r1 = math.min(s[0], s[2]) / math.max(s[0], s[2]);
      final r2 = math.min(s[1], s[3]) / math.max(s[1], s[3]);
      squareness = math.min(r1, r2);
      var m = 1.0;
      for (final p in markers) {
        m = math.min(m, math.min(math.min(p.x, g.width - p.x) / g.width, math.min(p.y, g.height - p.y) / g.height));
      }
      edge = m;
    }
    return FrameStats(
      mean: mean,
      glare: glare,
      sharpness: sharpness,
      coverage: coverage,
      squareness: squareness,
      edgeMargin: edge,
    );
  }

  static FrameAdvice advise(FrameStats s) {
    if (s.mean < darkMean) return FrameAdvice.tooDark;
    if (s.glare > glareFraction) return FrameAdvice.glare;
    if (s.coverage != null) {
      if (s.edgeMargin! < minEdgeMargin) return FrameAdvice.edge;
      if (s.coverage! < minCoverage) return FrameAdvice.tooFar;
      if (s.squareness! < minSquareness) return FrameAdvice.tilted;
      return FrameAdvice.ok;
    }
    if (s.sharpness < minSharpness) return FrameAdvice.blurry;
    return FrameAdvice.ok;
  }

  static FrameAdvice assess(GrayImage g, {List<Pt>? markers}) => advise(measure(g, markers: markers));

  static double _area(List<Pt> p) {
    var a = 0.0;
    for (var i = 0; i < p.length; i++) {
      final q = p[(i + 1) % p.length];
      a += p[i].x * q.y - q.x * p[i].y;
    }
    return a.abs() / 2;
  }
}
