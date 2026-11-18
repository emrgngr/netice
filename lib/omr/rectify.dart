import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'form_layout.dart';
import 'homography.dart';
import 'omr_reader.dart';

/// Fotoğraftaki formu düzleştirir: köşe işaretlerinden perspektif düzeltilir
/// ve A4 oranında, [pxPerMm] çözünürlükte gri bir görüntü üretilir.
/// Sonuç, işaretli kâğıt görüntüsü olarak saklanır (form mm × pxPerMm).
img.Image rectifySheet(GrayImage g, List<Pt> markers, {double pxPerMm = 4}) {
  final hom = Homography.fromPoints(FormLayout.markerCenters, markers);
  final w = (FormLayout.pageWidth * pxPerMm).round();
  final h = (FormLayout.pageHeight * pxPerMm).round();
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = hom.map(Pt(x / pxPerMm, y / pxPerMm));
      final fx = p.x, fy = p.y;
      final x0 = fx.floor(), y0 = fy.floor();
      if (x0 < 0 || y0 < 0 || x0 + 1 >= g.width || y0 + 1 >= g.height) {
        out[y * w + x] = 255;
        continue;
      }
      // Çift doğrusal örnekleme
      final ax = fx - x0, ay = fy - y0;
      final a = g.at(x0, y0), b = g.at(x0 + 1, y0), c = g.at(x0, y0 + 1), d = g.at(x0 + 1, y0 + 1);
      final v = a * (1 - ax) * (1 - ay) + b * ax * (1 - ay) + c * (1 - ax) * ay + d * ax * ay;
      out[y * w + x] = v.round().clamp(0, 255);
    }
  }
  return img.Image.fromBytes(width: w, height: h, bytes: out.buffer, numChannels: 1);
}

/// Düzleştirilmiş kâğıdı küçük boyutlu JPEG'e çevirir (~60–120 KB).
Uint8List rectifiedJpeg(GrayImage g, List<Pt> markers) =>
    Uint8List.fromList(img.encodeJpg(rectifySheet(g, markers).convert(numChannels: 3), quality: 72));
