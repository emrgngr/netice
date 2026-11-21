import 'dart:math' as math;

import 'form_layout.dart';

/// 3×3 perspektif dönüşümü (form mm koordinatı → görüntü pikseli).
class Homography {
  /// Satır sıralı 9 katsayı; h[8] = 1.
  final List<double> h;
  const Homography(this.h);

  /// 4 nokta eşlemesinden dönüşümü çözer.
  factory Homography.fromPoints(List<Pt> src, List<Pt> dst) {
    if (src.length != 4 || dst.length != 4) {
      throw ArgumentError('Tam 4 nokta gerekir');
    }
    // A · x = b, x = [h0..h7]
    final a = List.generate(8, (_) => List<double>.filled(9, 0));
    for (var i = 0; i < 4; i++) {
      final x = src[i].x, y = src[i].y, u = dst[i].x, v = dst[i].y;
      a[2 * i] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u];
      a[2 * i + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v];
    }
    // Kısmi pivotlamalı Gauss eliminasyonu.
    for (var col = 0; col < 8; col++) {
      var pivot = col;
      for (var r = col + 1; r < 8; r++) {
        if (a[r][col].abs() > a[pivot][col].abs()) pivot = r;
      }
      if (a[pivot][col].abs() < 1e-12) {
        throw StateError('Köşe noktaları dönüşüm için uygun değil');
      }
      final tmp = a[col];
      a[col] = a[pivot];
      a[pivot] = tmp;
      for (var r = 0; r < 8; r++) {
        if (r == col) continue;
        final f = a[r][col] / a[col][col];
        if (f == 0) continue;
        for (var c = col; c < 9; c++) {
          a[r][c] -= f * a[col][c];
        }
      }
    }
    final x = [for (var i = 0; i < 8; i++) a[i][8] / a[i][i], 1.0];
    return Homography(x);
  }

  Pt map(Pt p) {
    final w = h[6] * p.x + h[7] * p.y + h[8];
    return Pt(
      (h[0] * p.x + h[1] * p.y + h[2]) / w,
      (h[3] * p.x + h[4] * p.y + h[5]) / w,
    );
  }

  /// Bu dönüşümün [mm] başına yaklaşık piksel ölçeği ([p] civarında).
  double scaleAt(Pt p) {
    final a = map(p);
    final b = map(Pt(p.x + 1, p.y));
    final c = map(Pt(p.x, p.y + 1));
    final sx = ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y));
    final sy = ((c.x - a.x) * (c.x - a.x) + (c.y - a.y) * (c.y - a.y));
    return (math.sqrt(sx) + math.sqrt(sy)) / 2;
  }
}
