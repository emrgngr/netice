import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../core/models.dart';
import 'form_code.dart';
import 'form_layout.dart';
import 'homography.dart';

/// 8 bit gri tonlamalı görüntü.
class GrayImage {
  final int width;
  final int height;
  final Uint8List data;

  /// Renkli fotoğrafta her pikselin kırmızı − mavi farkı (sıcaklık). Kâğıdı
  /// ahşap masa gibi sıcak renkli, açık tonlu zeminden ayırmak için kullanılır.
  final Int16List? warmth;

  GrayImage(this.width, this.height, this.data, {this.warmth})
      : assert(data.length == width * height);

  int at(int x, int y) => data[y * width + x];

  /// PNG/JPEG baytlarından gri görüntü oluşturur.
  static GrayImage? decode(Uint8List bytes) {
    final im = img.decodeImage(bytes);
    if (im == null) return null;
    // Telefon fotoğraflarındaki EXIF yön bilgisini uygula.
    return fromImage(img.bakeOrientation(im));
  }

  /// Saat yönünde [quarterTurns] × 90° döndürür.
  GrayImage rotate(int quarterTurns) {
    final q = quarterTurns % 4;
    if (q == 0) return this;
    final nw = q.isOdd ? height : width, nh = q.isOdd ? width : height;
    final out = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        int nx, ny;
        switch (q) {
          case 1:
            nx = height - 1 - y;
            ny = x;
          case 2:
            nx = width - 1 - x;
            ny = height - 1 - y;
          default:
            nx = y;
            ny = width - 1 - x;
        }
        out[ny * nw + nx] = data[row + x];
      }
    }
    return GrayImage(nw, nh, out);
  }

  /// Kamera karesinin parlaklık (Y) düzleminden gri görüntü (satır dolgusunu atlar).
  static GrayImage fromLumaPlane(Uint8List bytes, int width, int height, int bytesPerRow) {
    if (bytesPerRow == width) return GrayImage(width, height, Uint8List.fromList(bytes.sublist(0, width * height)));
    final out = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      out.setRange(y * width, (y + 1) * width, bytes, y * bytesPerRow);
    }
    return GrayImage(width, height, out);
  }

  /// iOS BGRA karesinden gri görüntü.
  static GrayImage fromBgra(Uint8List bytes, int width, int height, int bytesPerRow) {
    final out = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      var j = y * bytesPerRow;
      for (var x = 0; x < width; x++, j += 4) {
        out[y * width + x] = (bytes[j] * 114 + bytes[j + 1] * 587 + bytes[j + 2] * 299) ~/ 1000;
      }
    }
    return GrayImage(width, height, out);
  }

  static GrayImage fromImage(img.Image im) {
    final out = Uint8List(im.width * im.height);
    final color = im.numChannels >= 3;
    final warm = color ? Int16List(im.width * im.height) : null;
    var i = 0;
    for (final p in im) {
      if (warm != null) warm[i] = (p.r - p.b).round();
      out[i++] = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255);
    }
    return GrayImage(im.width, im.height, out, warmth: warm);
  }
}

/// Okuma hatası; mesaj öğretmene ne yapması gerektiğini söyler.
class OmrException implements Exception {
  final String message;
  const OmrException(this.message);
  @override
  String toString() => message;
}

/// Bir dairenin ölçülen doluluk oranı (0 = boş kâğıt, 1 = köşe işareti kadar koyu).
typedef FillValues = List<double>;

class OmrQuestion {
  final Answer answer;
  final FillValues fills;
  const OmrQuestion(this.answer, this.fills);
}

class OmrResult {
  final List<OmrQuestion> questions;

  /// Okunan öğrenci numarası; okunamadıysa null.
  final String? studentNumber;

  /// Numaranın okunabilen hâli: emin olunamayan rakamlar '?' (ör. "00?042").
  /// Numara düzeltme önerisi için kullanılır.
  final String? numberPattern;

  /// Bulunan köşe işaretlerinin görüntüdeki merkezleri.
  final List<Pt> markers;

  /// Kenardaki makine kodu (yeni formlarda); okunamadıysa null.
  final FormCode? code;

  /// Öğrencinin işaretlediği kitapçık (0 = A, 1 = B, 2 = C…); işaret yoksa null.
  final int? booklet;

  /// Çeyrek A4 kısa quiz formundan mı okundu?
  final bool mini;

  /// Formun ad soyad alanından okunan ad ('?' = okunamayan harf); alan yoksa null.
  final String? name;

  /// Diğer numara alanlarından okunan numaralar (TC kimlik no vb.).
  final List<String> otherNumbers;

  /// Diğer kodlama alanlarından okunanlar (alan adı → değer; doğum tarihi, cinsiyet…).
  final Map<String, String> fields;

  const OmrResult({
    required this.questions,
    required this.studentNumber,
    required this.markers,
    this.code,
    this.booklet,
    this.numberPattern,
    this.mini = false,
    this.name,
    this.otherNumbers = const [],
    this.fields = const {},
  });

  List<Answer> get answers => questions.map((q) => q.answer).toList();

  int get reviewCount => questions.where((q) => q.answer.needsReview).length;
}

/// Doluluk eşikleri. "Sistem emin olmadığı hiçbir şeyi sessizce karara
/// bağlamaz": iki eşik arasındaki işaretler kontrol kuyruğuna düşer.
class OmrThresholds {
  /// Bu değerin üstü kesin dolu.
  final double filled;

  /// Bu değerin altı kesin boş; arası belirsiz.
  final double empty;

  const OmrThresholds({this.filled = 0.50, this.empty = 0.28});
}

/// Netice formunu okuyan motor. Tamamen cihaz üzerinde çalışır.
class OmrReader {
  final FormLayout layout;
  final OmrThresholds thresholds;

  OmrReader(this.layout, {this.thresholds = const OmrThresholds()});

  OmrResult read(GrayImage image) => readAt(image, _orient(image, findMarkers(image)));

  /// Birden çok yerleşim (A4 formu ve kısa quiz formu) olabiliyorsa kâğıdın
  /// hangisi olduğunu daire çemberlerinin yerinden anlar ve onunla okur.
  static OmrResult readAny(GrayImage image, List<FormLayout> layouts, {OmrThresholds thresholds = const OmrThresholds()}) {
    final found = findMarkers(image);
    OmrReader? best;
    List<Pt>? bestMarkers;
    var bestScore = double.negativeInfinity;
    for (final l in layouts) {
      final r = OmrReader(l, thresholds: thresholds);
      final (m, score) = r._orientScored(image, found);
      if (score > bestScore) {
        bestScore = score;
        best = r;
        bestMarkers = m;
      }
    }
    return best!.readAt(image, bestMarkers!);
  }

  /// Köşe işaretleri bulunmuş ve yönü düzeltilmiş kâğıdı okur.
  OmrResult readAt(GrayImage image, List<Pt> markers) {
    final hom = Homography.fromPoints(FormLayout.markerCenters, markers);

    // Siyah referansı: köşe işaretlerinin iç kısmı.
    final markerRadius = FormLayout.markerSize * 0.3 * hom.scaleAt(markers.first);
    var black = 0.0;
    for (final m in markers) {
      black += meanInDisk(image, m, markerRadius);
    }
    black /= 4;

    double fillAt(Pt formPt) {
      final c = hom.map(formPt);
      final scale = hom.scaleAt(formPt);
      final r = layout.bubbleR * scale;
      final white = localWhite(image, c, r * 1.8);
      final mean = meanInDisk(image, c, r * 0.62);
      final range = white - black;
      if (range < 20) return 0;
      return ((white - mean) / range).clamp(0.0, 1.0);
    }

    final questions = <OmrQuestion>[];
    for (var q = 0; q < layout.questionCount; q++) {
      final fills = [
        for (var c = 0; c < layout.choiceCount; c++)
          fillAt(layout.answerBubble(q, c))
      ];
      questions.add(OmrQuestion(classify(fills), fills));
    }

    final digits = StringBuffer();
    var numberOk = true;
    for (var d = 0; d < layout.digits; d++) {
      final fills = [for (var v = 0; v < 10; v++) fillAt(layout.studentBubble(d, v))];
      final a = classify(fills);
      if (a.state == MarkState.filled && a.marked.length == 1) {
        digits.write(a.marked.first);
      } else {
        // Her sütunda tam bir rakam beklenir: açık kalemle ya da gölgede
        // eşiğin altında kalsa da diğerlerinden belirgin koyu olanı kabul et.
        final order = [for (var v = 0; v < 10; v++) v]..sort((x, y) => fills[y].compareTo(fills[x]));
        final best = fills[order[0]], second = fills[order[1]];
        if (best >= 0.25 && best - second >= 0.18 && second < thresholds.empty) {
          digits.write(order[0]);
        } else {
          numberOk = false;
          digits.write('?');
        }
      }
    }

    // Kitapçık türü.
    int? booklet;
    if (layout.hasBooklets) {
      final a = classify([for (var k = 0; k < layout.booklets; k++) fillAt(layout.bookletBubble(k))]);
      if (a.state == MarkState.filled && a.marked.length == 1) booklet = a.marked.first;
    }

    // Makine kodu şeridi.
    final bits = <bool>[];
    for (var i = 0; i < FormCode.cells; i++) {
      final p = FormCode.cell(i);
      final c = hom.map(p);
      final scale = hom.scaleAt(p);
      final white = localWhite(image, c, 2.6 * scale);
      final mean = meanInDisk(image, c, 0.9 * scale);
      final range = white - black;
      bits.add(range >= 20 && (white - mean) / range > 0.5);
    }

    return OmrResult(
      questions: questions,
      studentNumber: numberOk ? digits.toString() : null,
      numberPattern: digits.toString().replaceAll('?', '').isEmpty ? null : digits.toString(),
      markers: markers,
      code: FormCode.decode(bits),
      booklet: booklet,
      mini: layout.mini,
    );
  }

  /// Kâğıt yan ya da ters çekildiyse köşe sırasını düzeltir: dört olası
  /// yönün her birinde basılı daire çemberlerinin gerçekten beklenen yerde
  /// olup olmadığına bakılır ve en tutarlı yön seçilir.
  List<Pt> _orient(GrayImage image, List<Pt> m) => _orientScored(image, m).$1;

  (List<Pt>, double) _orientScored(GrayImage image, List<Pt> m) {
    var best = m;
    var bestScore = double.negativeInfinity;
    for (var k = 0; k < 4; k++) {
      final cand = [for (var i = 0; i < 4; i++) m[(i + k) % 4]];
      final hom = Homography.fromPoints(FormLayout.markerCenters, cand);
      final score = _ringScore(image, hom);
      if (score > bestScore) {
        bestScore = score;
        best = cand;
      }
    }
    return (best, bestScore);
  }

  /// Daire çemberi üzerindeki noktalar, daireler arasındaki boşluktan ne kadar koyu?
  double _ringScore(GrayImage image, Homography hom) {
    var ring = 0.0, gap = 0.0;
    var n = 0;
    final pts = <Pt>[
      for (var q = 0; q < math.min(layout.questionCount, 12); q++) layout.answerBubble(q, 1),
      for (var d = 0; d < layout.digits; d++) layout.studentBubble(d, 5),
    ];
    for (final c in pts) {
      for (var a = 0; a < 12; a++) {
        final ang = a * math.pi / 6;
        final r = layout.bubbleR;
        final pr = hom.map(Pt(c.x + r * math.cos(ang), c.y + r * math.sin(ang)));
        final pg = hom.map(Pt(c.x + r * 1.33 * math.cos(ang), c.y + r * 1.33 * math.sin(ang)));
        if (!_inside(image, pr) || !_inside(image, pg)) return double.negativeInfinity;
        ring += image.at(pr.x.round(), pr.y.round());
        gap += image.at(pg.x.round(), pg.y.round());
        n++;
      }
    }
    return n == 0 ? double.negativeInfinity : (gap - ring) / n;
  }

  static bool _inside(GrayImage im, Pt p) => p.x >= 0 && p.y >= 0 && p.x < im.width - 0.5 && p.y < im.height - 0.5;

  /// Bir sorunun doluluk değerlerinden kararı verir.
  Answer classify(FillValues fills) => classifyFills(fills, thresholds);

  /// [classify]'ın okuyucudan bağımsız hâli (başka form düzenleri için).
  static Answer classifyFills(FillValues fills, OmrThresholds thresholds) {
    final filled = <int>{};
    final faint = <int>{};
    for (var i = 0; i < fills.length; i++) {
      if (fills[i] >= thresholds.filled) {
        filled.add(i);
      } else if (fills[i] >= thresholds.empty) {
        faint.add(i);
      }
    }
    if (filled.length > 1) return Answer(MarkState.multiple, filled);
    if (filled.length == 1 && faint.isEmpty) {
      return Answer(MarkState.filled, filled);
    }
    if (filled.isEmpty && faint.isEmpty) return const Answer.blank();
    // Silik ya da yarım silinmiş işaret: öğretmen karar verir.
    return Answer(MarkState.uncertain, {...filled, ...faint});
  }

  // ---------------------------------------------------------------------
  // Köşe işareti tespiti

  /// Dört köşe işaretinin merkezini (sol üst, sağ üst, sağ alt, sol alt) bulur.
  /// Köşe karelerini bulur. Önce tek eşikle dener; güçlü gölge ya da
  /// dengesiz ışıkta başarısız olursa yerel (uyarlamalı) eşikle yeniden dener.
  static List<Pt> findMarkers(GrayImage image) {
    try {
      return _findMarkers(image, adaptive: false);
    } on OmrException {
      return _findMarkers(image, adaptive: true);
    }
  }

  static List<Pt> _findMarkers(GrayImage image, {required bool adaptive}) {
    final candidates = markerCandidates(image, adaptive: adaptive);
    final w = image.width, h = image.height;
    const f = 1;
    return _pickCorners(image, candidates, w, h, f);
  }

  /// Görüntüdeki kare biçimli koyu lekeler (köşe işareti adayları).
  /// [maxSideFraction]: bir adayın kenarı, görüntünün kısa kenarının en çok
  /// bu kadarı olabilir (yakından çekilen küçük cevap kutusunda daha büyük).
  static List<MarkerBlob> markerCandidates(GrayImage image, {required bool adaptive, double maxSideFraction = 0.12}) {
    // Hız için küçült.
    const target = 900;
    final f = math.max(1, (math.max(image.width, image.height) / target).ceil());
    final w = image.width ~/ f, h = image.height ~/ f;
    final small = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var s = 0;
        for (var dy = 0; dy < f; dy++) {
          final row = (y * f + dy) * image.width + x * f;
          for (var dx = 0; dx < f; dx++) {
            s += image.data[row + dx];
          }
        }
        small[y * w + x] = s ~/ (f * f);
      }
    }

    final dark = Uint8List(w * h);
    if (!adaptive) {
      final t = _otsu(small);
      for (var i = 0; i < small.length; i++) {
        dark[i] = small[i] < t ? 1 : 0;
      }
    } else {
      // Her pikseli çevresinin ortalamasıyla karşılaştır (integral görüntü).
      final integ = Int64List((w + 1) * (h + 1));
      for (var y = 0; y < h; y++) {
        var row = 0;
        for (var x = 0; x < w; x++) {
          row += small[y * w + x];
          integ[(y + 1) * (w + 1) + x + 1] = integ[y * (w + 1) + x + 1] + row;
        }
      }
      final r = math.max(8, math.max(w, h) ~/ 12);
      for (var y = 0; y < h; y++) {
        final y0 = math.max(0, y - r), y1 = math.min(h, y + r + 1);
        for (var x = 0; x < w; x++) {
          final x0 = math.max(0, x - r), x1 = math.min(w, x + r + 1);
          final sum = integ[y1 * (w + 1) + x1] - integ[y0 * (w + 1) + x1] - integ[y1 * (w + 1) + x0] + integ[y0 * (w + 1) + x0];
          final mean = sum / ((y1 - y0) * (x1 - x0));
          final v = small[y * w + x];
          dark[y * w + x] = v < mean * 0.62 && v < mean - 30 ? 1 : 0;
        }
      }
    }

    final labels = Int32List(w * h);
    final candidates = <MarkerBlob>[];
    final minSide = math.min(w, h) * 0.02;
    final maxSide = math.min(w, h) * maxSideFraction;
    var next = 1;
    final stack = <int>[];
    for (var start = 0; start < dark.length; start++) {
      if (dark[start] == 0 || labels[start] != 0) continue;
      var minX = w, minY = h, maxX = 0, maxY = 0, area = 0;
      var sx = 0.0, sy = 0.0;
      labels[start] = next;
      stack.add(start);
      while (stack.isNotEmpty) {
        final i = stack.removeLast();
        final x = i % w, y = i ~/ w;
        area++;
        sx += x;
        sy += y;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        void visit(int j) {
          if (dark[j] == 1 && labels[j] == 0) {
            labels[j] = next;
            stack.add(j);
          }
        }

        if (x > 0) visit(i - 1);
        if (x < w - 1) visit(i + 1);
        if (y > 0) visit(i - w);
        if (y < h - 1) visit(i + w);
      }
      next++;
      final bw = maxX - minX + 1, bh = maxY - minY + 1;
      if (bw < minSide || bh < minSide || bw > maxSide || bh > maxSide) continue;
      final aspect = bw / bh;
      if (aspect < 0.6 || aspect > 1.67) continue;
      // Döndürülmüş kare için doluluk oranı en az ~0.5'tir.
      if (area / (bw * bh) < 0.5) continue;
      candidates.add(MarkerBlob(Pt(sx / area * f + f / 2, sy / area * f + f / 2), area * f * f, (bw + bh) / 2 * f));
    }
    return candidates;
  }

  static List<Pt> _pickCorners(GrayImage image, List<MarkerBlob> candidates, int w, int h, int f) {
    if (candidates.length < 4) {
      throw const OmrException(
          'Kâğıdın dört köşesindeki siyah kareler bulunamadı. Kâğıdın tamamı görünecek şekilde biraz uzaklaştırın.');
    }

    // Her görüntü köşesine en yakın büyük adayı seç.
    final corners = [
      const Pt(0, 0),
      Pt(image.width.toDouble(), 0),
      Pt(image.width.toDouble(), image.height.toDouble()),
      Pt(0, image.height.toDouble()),
    ];
    final maxArea = candidates.map((c) => c.area).reduce(math.max);
    final big = candidates.where((c) => c.area >= maxArea * 0.35).toList();
    final chosen = <Pt>[];
    for (final corner in corners) {
      MarkerBlob? best;
      var bestD = double.infinity;
      for (final c in big) {
        final d = (c.center.x - corner.x).abs() + (c.center.y - corner.y).abs();
        if (d < bestD) {
          bestD = d;
          best = c;
        }
      }
      chosen.add(best!.center);
    }
    // Aynı aday iki köşeye seçildiyse form bütünüyle görünmüyordur.
    for (var i = 0; i < 4; i++) {
      for (var j = i + 1; j < 4; j++) {
        final a = chosen[i], b = chosen[j];
        if ((a.x - b.x).abs() + (a.y - b.y).abs() < math.min(w, h) * f * 0.2) {
          throw const OmrException(
              'Formun köşeleri net görünmüyor. Kâğıdı düz bir zemine koyup tamamını çerçeveye alın.');
        }
      }
    }
    return chosen;
  }

  static int _otsu(Uint8List data) {
    final hist = List<int>.filled(256, 0);
    for (final v in data) {
      hist[v]++;
    }
    final total = data.length;
    var sum = 0.0;
    for (var i = 0; i < 256; i++) {
      sum += i * hist[i];
    }
    var sumB = 0.0, wB = 0, best = 0.0, threshold = 127;
    for (var t = 0; t < 256; t++) {
      wB += hist[t];
      if (wB == 0) continue;
      final wF = total - wB;
      if (wF == 0) break;
      sumB += t * hist[t];
      final mB = sumB / wB, mF = (sum - sumB) / wF;
      final between = wB * wF * (mB - mF) * (mB - mF);
      if (between > best) {
        best = between;
        threshold = t;
      }
    }
    // Koyu işaretleri seçmek için eşiği biraz aşağı çek.
    return (threshold * 0.85).round();
  }

  // ---------------------------------------------------------------------
  // Örnekleme

  static double meanInDisk(GrayImage im, Pt c, double r) {
    final r2 = r * r;
    var s = 0, n = 0;
    final x0 = math.max(0, (c.x - r).floor()), x1 = math.min(im.width - 1, (c.x + r).ceil());
    final y0 = math.max(0, (c.y - r).floor()), y1 = math.min(im.height - 1, (c.y + r).ceil());
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final dx = x - c.x, dy = y - c.y;
        if (dx * dx + dy * dy <= r2) {
          s += im.at(x, y);
          n++;
        }
      }
    }
    return n == 0 ? 255 : s / n;
  }

  /// Dairenin çevresindeki kâğıt beyazı (yerel %90'lık değer); düzensiz
  /// ışığa karşı her daire kendi çevresine göre değerlendirilir.
  static double localWhite(GrayImage im, Pt c, double half) {
    final hist = List<int>.filled(256, 0);
    var n = 0;
    final x0 = math.max(0, (c.x - half).floor()), x1 = math.min(im.width - 1, (c.x + half).ceil());
    final y0 = math.max(0, (c.y - half).floor()), y1 = math.min(im.height - 1, (c.y + half).ceil());
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        hist[im.at(x, y)]++;
        n++;
      }
    }
    final target = n * 0.9;
    var acc = 0;
    for (var v = 0; v < 256; v++) {
      acc += hist[v];
      if (acc >= target) return v.toDouble();
    }
    return 255;
  }
}

/// Köşe işareti adayı: merkez (piksel), alan (piksel²) ve ortalama kenar (piksel).
class MarkerBlob {
  final Pt center;
  final int area;
  final double side;
  MarkerBlob(this.center, this.area, this.side);
}
