import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../core/models.dart';
import 'form_layout.dart';
import 'homography.dart';
import 'omr_reader.dart';

/// Başka firmaların optik formları için şablon.
///
/// Koordinatlar "sayfa birimi"ndedir: sayfa genişliği 1000, yüksekliği
/// 1000 × [aspect]. Sayfa, fotoğraftaki kâğıdın dört kenarından bulunur ve
/// düzleştirilir; daireler bu düzlemde öğretmenin işaretlediği yerlerdedir.
class FormTemplate {
  final String id;
  final String name;

  /// Yükseklik / genişlik (A4 dikey ≈ 1.414).
  final double aspect;
  final List<TemplateBlock> blocks;
  final NumberBlock? number;

  const FormTemplate({
    required this.id,
    required this.name,
    this.aspect = 297 / 210,
    this.blocks = const [],
    this.number,
  });

  static const width = 1000.0;
  double get height => width * aspect;

  /// Şablonun kapsadığı soru sayısı.
  int get questionCount => blocks.fold(0, (m, b) => math.max(m, b.start + b.count - 1));

  /// Şablonun en fazla şık sayısı.
  int get choiceCount => blocks.fold(0, (m, b) => math.max(m, b.choices));

  FormTemplate copyWith({String? name, double? aspect, List<TemplateBlock>? blocks, NumberBlock? number, bool clearNumber = false}) =>
      FormTemplate(
        id: id,
        name: name ?? this.name,
        aspect: aspect ?? this.aspect,
        blocks: blocks ?? this.blocks,
        number: clearNumber ? null : (number ?? this.number),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'aspect': aspect,
        'blocks': blocks.map((b) => b.toJson()).toList(),
        if (number != null) 'number': number!.toJson(),
      };

  factory FormTemplate.fromJson(Map<String, dynamic> j) => FormTemplate(
        id: j['id'] as String,
        name: j['name'] as String,
        aspect: (j['aspect'] as num?)?.toDouble() ?? 297 / 210,
        blocks: [for (final b in (j['blocks'] as List?) ?? const []) TemplateBlock.fromJson(b as Map<String, dynamic>)],
        number: j['number'] == null ? null : NumberBlock.fromJson(j['number'] as Map<String, dynamic>),
      );
}

/// Bir cevap bloğu: art arda gelen sorular, düzenli bir ızgarada.
class TemplateBlock {
  /// Bloğun ilk sorusunun numarası (1'den).
  final int start;
  final int count;
  final int choices;

  /// İlk sorunun ilk şıkkı ve son sorunun son şıkkının merkezleri (sayfa birimi).
  final Pt first, last;

  /// true: her satır bir soru, şıklar yan yana (en yaygın).
  /// false: her sütun bir soru, şıklar alt alta.
  final bool rows;

  const TemplateBlock({
    required this.start,
    required this.count,
    required this.choices,
    required this.first,
    required this.last,
    this.rows = true,
  });

  /// [q]. sorunun (bloğun içinde, 0'dan) [c]. şıkkının merkezi.
  Pt bubble(int q, int c) {
    final fq = count <= 1 ? 0.0 : q / (count - 1);
    final fc = choices <= 1 ? 0.0 : c / (choices - 1);
    final fx = rows ? fc : fq, fy = rows ? fq : fc;
    return Pt(first.x + (last.x - first.x) * fx, first.y + (last.y - first.y) * fy);
  }

  /// Daire yarıçapı: komşu daireler arası mesafeden.
  double get radius => _radius(first, last, rows ? choices : count, rows ? count : choices);

  Map<String, dynamic> toJson() => {
        'start': start,
        'count': count,
        'choices': choices,
        'first': [first.x, first.y],
        'last': [last.x, last.y],
        if (!rows) 'rows': false,
      };

  factory TemplateBlock.fromJson(Map<String, dynamic> j) => TemplateBlock(
        start: j['start'] as int,
        count: j['count'] as int,
        choices: j['choices'] as int,
        first: _pt(j['first']),
        last: _pt(j['last']),
        rows: j['rows'] as bool? ?? true,
      );
}

/// Öğrenci numarası bloğu: her sütun bir basamak, 0–9 yukarıdan aşağı.
class NumberBlock {
  final int digits;

  /// İlk basamağın 0'ı ve son basamağın 9'unun merkezleri.
  final Pt first, last;

  const NumberBlock({required this.digits, required this.first, required this.last});

  Pt bubble(int d, int v) {
    final fx = digits <= 1 ? 0.0 : d / (digits - 1);
    return Pt(first.x + (last.x - first.x) * fx, first.y + (last.y - first.y) * v / 9);
  }

  double get radius => _radius(first, last, digits, 10);

  Map<String, dynamic> toJson() => {'digits': digits, 'first': [first.x, first.y], 'last': [last.x, last.y]};

  factory NumberBlock.fromJson(Map<String, dynamic> j) =>
      NumberBlock(digits: j['digits'] as int, first: _pt(j['first']), last: _pt(j['last']));
}

Pt _pt(Object? v) {
  final l = v as List;
  return Pt((l[0] as num).toDouble(), (l[1] as num).toDouble());
}

double _radius(Pt a, Pt b, int nx, int ny) {
  final sx = nx <= 1 ? double.infinity : (b.x - a.x).abs() / (nx - 1);
  final sy = ny <= 1 ? double.infinity : (b.y - a.y).abs() / (ny - 1);
  final s = math.min(sx, sy);
  return (s.isFinite ? s : 20) * 0.36;
}

// ---------------------------------------------------------------------------
// Sayfa bulma

/// Fotoğraftaki kâğıdın dört köşesini bulur (sol üst, sağ üst, sağ alt, sol alt).
/// Kâğıt, kendisinden koyu bir zemin üzerinde olmalıdır. Tarayıcı görüntüsünde
/// (kâğıt tüm görüntüyü kaplıyorsa) görüntünün köşeleri döner.
class PageFinder {
  static List<Pt> find(GrayImage image, {double aspect = 297 / 210}) {
    const target = 800;
    final f = math.max(1, (math.max(image.width, image.height) / target).ceil());
    final w = image.width ~/ f, h = image.height ~/ f;
    final small = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        small[y * w + x] = image.at(x * f, y * f);
      }
    }
    final t = _otsu(small);
    // Kenarlara değen parlak bölge yoksa ya da bölge tüm görüntüyse: tarama.
    final mask = Uint8List(w * h);
    for (var i = 0; i < small.length; i++) {
      if (small[i] > t) mask[i] = 1;
    }
    // En büyük parlak bileşen.
    final label = Int32List(w * h);
    var best = 0, bestSize = 0, next = 0;
    final stack = <int>[];
    for (var i = 0; i < mask.length; i++) {
      if (mask[i] == 0 || label[i] != 0) continue;
      next++;
      var size = 0;
      stack.add(i);
      label[i] = next;
      while (stack.isNotEmpty) {
        final p = stack.removeLast();
        size++;
        final x = p % w, y = p ~/ w;
        void visit(int q) {
          if (mask[q] == 1 && label[q] == 0) {
            label[q] = next;
            stack.add(q);
          }
        }

        if (x > 0) visit(p - 1);
        if (x < w - 1) visit(p + 1);
        if (y > 0) visit(p - w);
        if (y < h - 1) visit(p + w);
      }
      if (size > bestSize) {
        bestSize = size;
        best = next;
      }
    }
    final full = [Pt(0, 0), Pt(image.width - 1.0, 0), Pt(image.width - 1.0, image.height - 1.0), Pt(0, image.height - 1.0)];
    if (bestSize < w * h * 0.15) throw const OmrException('Kâğıt bulunamadı. Kâğıdı koyu bir zemine koyun ve tamamı görünsün.');
    if (bestSize > w * h * 0.93) return full;

    // Kaba köşeler: uç noktalar.
    var tl = 0, tr = 0, br = 0, bl = 0;
    var vtl = 1 << 30, vtr = -(1 << 30), vbr = -(1 << 30), vbl = 1 << 30;
    for (var i = 0; i < label.length; i++) {
      if (label[i] != best) continue;
      final x = i % w, y = i ~/ w;
      if (x + y < vtl) {
        vtl = x + y;
        tl = i;
      }
      if (x + y > vbr) {
        vbr = x + y;
        br = i;
      }
      if (x - y > vtr) {
        vtr = x - y;
        tr = i;
      }
      if (x - y < vbl) {
        vbl = x - y;
        bl = i;
      }
    }
    Pt at(int i) => Pt((i % w).toDouble(), (i ~/ w).toDouble());
    var corners = [at(tl), at(tr), at(br), at(bl)];

    // İnce ayar: her kenar boyunca sınır noktalarına doğru uydur, kesişimleri al.
    final boundary = <Pt>[];
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final i = y * w + x;
        if (label[i] != best) continue;
        if (label[i - 1] != best || label[i + 1] != best || label[i - w] != best || label[i + w] != best) {
          boundary.add(Pt(x.toDouble(), y.toDouble()));
        }
      }
    }
    final lines = <(Pt, Pt)?>[];
    for (var s = 0; s < 4; s++) {
      final a = corners[s], b = corners[(s + 1) % 4];
      final len = _dist(a, b);
      if (len < 10) {
        lines.add(null);
        continue;
      }
      final pts = <Pt>[];
      for (final p in boundary) {
        // Kenara uzaklık ve kenar üzerindeki konum.
        final tpar = ((p.x - a.x) * (b.x - a.x) + (p.y - a.y) * (b.y - a.y)) / (len * len);
        if (tpar < 0.12 || tpar > 0.88) continue;
        final d = ((b.x - a.x) * (a.y - p.y) - (a.x - p.x) * (b.y - a.y)).abs() / len;
        if (d < len * 0.03 + 2) pts.add(p);
      }
      lines.add(pts.length < 10 ? null : _fitLine(pts));
    }
    if (lines.every((l) => l != null)) {
      final refined = <Pt>[];
      for (var s = 0; s < 4; s++) {
        final p = _intersect(lines[(s + 3) % 4]!, lines[s]!);
        if (p == null || _dist(p, corners[s]) > math.max(w, h) * 0.05) {
          refined.add(corners[s]);
        } else {
          refined.add(p);
        }
      }
      corners = refined;
    }
    // Ölçeği geri al (piksel merkezleri).
    corners = [for (final c in corners) Pt((c.x + 0.5) * f, (c.y + 0.5) * f)];
    // Kâğıt yatay görünüyorsa (dikey şablonda) sırayı bir kaydır.
    final top = _dist(corners[0], corners[1]), side = _dist(corners[1], corners[2]);
    if ((aspect > 1) != (side > top)) corners = [corners[3], corners[0], corners[1], corners[2]];
    return corners;
  }

  static double _dist(Pt a, Pt b) => math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));

  /// Doğru: (nokta, yön).
  static (Pt, Pt) _fitLine(List<Pt> pts) {
    var mx = 0.0, my = 0.0;
    for (final p in pts) {
      mx += p.x;
      my += p.y;
    }
    mx /= pts.length;
    my /= pts.length;
    var sxx = 0.0, sxy = 0.0, syy = 0.0;
    for (final p in pts) {
      final dx = p.x - mx, dy = p.y - my;
      sxx += dx * dx;
      sxy += dx * dy;
      syy += dy * dy;
    }
    final ang = 0.5 * math.atan2(2 * sxy, sxx - syy);
    return (Pt(mx, my), Pt(math.cos(ang), math.sin(ang)));
  }

  static Pt? _intersect((Pt, Pt) l1, (Pt, Pt) l2) {
    final (p, r) = l1;
    final (q, s) = l2;
    final den = r.x * s.y - r.y * s.x;
    if (den.abs() < 1e-9) return null;
    final t = ((q.x - p.x) * s.y - (q.y - p.y) * s.x) / den;
    return Pt(p.x + t * r.x, p.y + t * r.y);
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
    var sumB = 0.0, wB = 0, best = 0.0, t = 127;
    for (var i = 0; i < 256; i++) {
      wB += hist[i];
      if (wB == 0) continue;
      final wF = total - wB;
      if (wF == 0) break;
      sumB += i * hist[i];
      final mB = sumB / wB, mF = (sum - sumB) / wF;
      final between = wB * wF * (mB - mF) * (mB - mF);
      if (between > best) {
        best = between;
        t = i;
      }
    }
    return t;
  }
}

// ---------------------------------------------------------------------------
// Okuma

/// Şablona göre formu okur. Sonuç, Netice formuyla aynı biçimdedir; köşe
/// işaretleri yerine sayfanın dört köşesi döner.
class TemplateReader {
  final FormTemplate template;
  final int questionCount;
  final int choiceCount;
  final OmrThresholds thresholds;

  TemplateReader(this.template, {required this.questionCount, required this.choiceCount, this.thresholds = const OmrThresholds()});

  List<Pt> get pageCorners => [
        Pt(0, 0),
        Pt(FormTemplate.width, 0),
        Pt(FormTemplate.width, template.height),
        Pt(0, template.height),
      ];

  OmrResult read(GrayImage image, {List<Pt>? corners}) {
    final page = corners ?? orient(image, PageFinder.find(image, aspect: template.aspect));
    final hom = Homography.fromPoints(pageCorners, page);
    // Siyah referansı: sayfa içindeki en koyu %0,5.
    final black = _darkLevel(image, page);
    final helper = OmrReader(FormLayout(questionCount: 1, choiceCount: 4), thresholds: thresholds);

    double fillAt(Pt p, double radius) {
      final c = hom.map(p);
      final scale = hom.scaleAt(p);
      final r = radius * scale;
      final white = OmrReader.localWhite(image, c, r * 1.9);
      // En iyi hizayı bul: küçük kaymalara karşı çevrede en koyu noktayı ara.
      var mean = OmrReader.meanInDisk(image, c, r * 0.6);
      final step = r * 0.3;
      for (final d in const [(-1, 0), (1, 0), (0, -1), (0, 1)]) {
        final m = OmrReader.meanInDisk(image, Pt(c.x + d.$1 * step, c.y + d.$2 * step), r * 0.6);
        if (m < mean) mean = m;
      }
      final range = white - black;
      if (range < 20) return 0;
      return ((white - mean) / range).clamp(0.0, 1.0);
    }

    final answers = List<OmrQuestion>.generate(
        questionCount, (_) => const OmrQuestion(Answer.blank(), []));
    for (final b in template.blocks) {
      final r = b.radius;
      for (var q = 0; q < b.count; q++) {
        final idx = b.start - 1 + q;
        if (idx < 0 || idx >= questionCount) continue;
        final fills = [for (var c = 0; c < math.min(b.choices, choiceCount); c++) fillAt(b.bubble(q, c), r)];
        answers[idx] = OmrQuestion(helper.classify(fills), fills);
      }
    }

    String? number;
    String? pattern;
    final nb = template.number;
    if (nb != null) {
      final digits = StringBuffer();
      var ok = true;
      for (var d = 0; d < nb.digits; d++) {
        final fills = [for (var v = 0; v < 10; v++) fillAt(nb.bubble(d, v), nb.radius)];
        final order = [for (var v = 0; v < 10; v++) v]..sort((x, y) => fills[y].compareTo(fills[x]));
        final best = fills[order[0]], second = fills[order[1]];
        if (best >= 0.25 && best - second >= 0.18 && second < thresholds.empty + 0.05) {
          digits.write(order[0]);
        } else if (best < thresholds.empty) {
          // Boş bırakılmış basamak (kısa numara): atla.
          digits.write('-');
        } else {
          ok = false;
          digits.write('?');
        }
      }
      // Baştaki/sondaki boş basamaklar sıfır gibi sayılır (numara sağa ya da sola yaslanmış olabilir).
      final raw = digits.toString().replaceAll('-', '');
      final p = raw.padLeft(FormLayout.studentDigits, '0');
      pattern = raw.isEmpty || raw.replaceAll('?', '').isEmpty ? null : p;
      number = ok && raw.isNotEmpty ? p : null;
    }

    return OmrResult(
      questions: answers,
      studentNumber: number,
      numberPattern: pattern,
      markers: page,
    );
  }

  /// Kâğıt yan ya da ters çekildiyse köşe sırasını düzeltir: dört olası yönün
  /// her birinde basılı daire çemberlerinin beklenen yerde olup olmadığına bakılır.
  List<Pt> orient(GrayImage image, List<Pt> c) {
    var best = c;
    var bestScore = -double.infinity;
    for (var k = 0; k < 4; k++) {
      final cand = [for (var i = 0; i < 4; i++) c[(i + k) % 4]];
      final score = _ringScore(image, Homography.fromPoints(pageCorners, cand));
      if (score > bestScore) {
        bestScore = score;
        best = cand;
      }
    }
    return best;
  }

  double _ringScore(GrayImage image, Homography hom) {
    final samples = <(Pt, double)>[];
    for (final b in template.blocks) {
      for (var q = 0; q < b.count; q += 3) {
        for (var ch = 0; ch < b.choices; ch++) {
          samples.add((b.bubble(q, ch), b.radius));
        }
      }
    }
    final nb = template.number;
    if (nb != null) {
      for (var d = 0; d < nb.digits; d += 2) {
        for (var v = 0; v < 10; v += 3) {
          samples.add((nb.bubble(d, v), nb.radius));
        }
      }
    }
    if (samples.isEmpty) return 0;
    var total = 0.0;
    for (final (p, r) in samples) {
      final scale = hom.scaleAt(p);
      final rr = r * scale;
      // Çember ile çemberin hemen dışı arasındaki koyuluk farkı.
      var ring = 0.0, out = 0.0;
      for (var a = 0; a < 12; a++) {
        final ang = a * math.pi / 6;
        final pr = hom.map(Pt(p.x + r * math.cos(ang), p.y + r * math.sin(ang)));
        final po = hom.map(Pt(p.x + r * 1.45 * math.cos(ang), p.y + r * 1.45 * math.sin(ang)));
        ring += OmrReader.meanInDisk(image, pr, math.max(1, rr * 0.12));
        out += OmrReader.meanInDisk(image, po, math.max(1, rr * 0.12));
      }
      total += (out - ring) / 12;
    }
    return total / samples.length;
  }

  static double _darkLevel(GrayImage im, List<Pt> page) {
    final xs = page.map((p) => p.x), ys = page.map((p) => p.y);
    final x0 = math.max(0, xs.reduce(math.min).floor()), x1 = math.min(im.width - 1, xs.reduce(math.max).ceil());
    final y0 = math.max(0, ys.reduce(math.min).floor()), y1 = math.min(im.height - 1, ys.reduce(math.max).ceil());
    final hist = List<int>.filled(256, 0);
    var n = 0;
    final step = math.max(1, ((x1 - x0) / 400).floor());
    for (var y = y0; y <= y1; y += step) {
      for (var x = x0; x <= x1; x += step) {
        hist[im.at(x, y)]++;
        n++;
      }
    }
    var acc = 0;
    for (var v = 0; v < 256; v++) {
      acc += hist[v];
      if (acc >= n * 0.005) return v.toDouble();
    }
    return 0;
  }
}

/// Sayfayı düzleştirip şablon düzleminde (genişlik [width] piksel) bir görüntü üretir.
/// Şablon düzenleyicide ve işaretli kâğıt görüntüsünde kullanılır.
img.Image rectifyPage(GrayImage g, List<Pt> corners, {double aspect = 297 / 210, int width = 1000}) {
  final pageW = FormTemplate.width, pageH = FormTemplate.width * aspect;
  final hom = Homography.fromPoints([Pt(0, 0), Pt(pageW, 0), Pt(pageW, pageH), Pt(0, pageH)], corners);
  final s = pageW / width;
  final h = (pageH / s).round();
  final out = Uint8List(width * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < width; x++) {
      final p = hom.map(Pt(x * s, y * s));
      final xi = p.x.round(), yi = p.y.round();
      out[y * width + x] = (xi < 0 || yi < 0 || xi >= g.width || yi >= g.height) ? 255 : g.at(xi, yi);
    }
  }
  return img.Image.fromBytes(width: width, height: h, bytes: out.buffer, numChannels: 1);
}
