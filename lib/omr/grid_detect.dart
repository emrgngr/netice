import 'dart:math' as math;
import 'dart:typed_data';

import 'form_layout.dart' show Pt;
import 'omr_reader.dart' show GrayImage;
import 'template.dart';

/// Başka firma formunda daire ızgaralarını kendiliğinden bulur.
///
/// Düzleştirilmiş sayfada (genişlik [FormTemplate.width]) basılı daireler
/// aranır; birbirine eşit aralıklı, aynı boydaki daireler ızgara (blok) olarak
/// toplanır ve her blok türüne göre sınıflanır:
///  * 2–6 sütunlu, çok satırlı blok: cevap bloğu (her satır bir soru),
///  * 2–6 satırlı, çok sütunlu blok: şıkları alt alta cevap bloğu,
///  * 10 satırlı (0–9) blok: öğrenci numarası,
///  * tek satır/sütun 2–6 daire (sayfanın üst yarısında): kitapçık türü,
///  * harf ızgarası (ad soyad) gibi büyük bloklar: yok sayılır.
/// Sonuç her zaman öğretmene gösterilir; yanlış bulunan blok elle düzeltilir.
class DetectedForm {
  final List<TemplateBlock> blocks;
  final NumberBlock? number;
  final BookletBlock? booklet;

  /// Bulunan ama kullanılmayan ızgaralar (ad soyad, sınıf, cinsiyet…).
  final int ignored;

  const DetectedForm({this.blocks = const [], this.number, this.booklet, this.ignored = 0});

  bool get isEmpty => blocks.isEmpty && number == null && booklet == null;

  int get questionCount => blocks.fold(0, (m, b) => math.max(m, b.start + b.count - 1));

  FormTemplate applyTo(FormTemplate t) => FormTemplate(
        id: t.id,
        name: t.name,
        aspect: t.aspect,
        blocks: blocks,
        number: number,
        booklet: booklet,
      );
}

/// Fotoğraftaki formun ızgaralarını bulur ([corners]: sayfanın dört köşesi).
DetectedForm detectFormGrids(GrayImage g, List<Pt> corners, {double aspect = 297 / 210}) {
  final page = rectifyPage(g, corners, aspect: aspect, width: FormTemplate.width.round());
  final w = page.width, h = page.height;
  final px = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      px[y * w + x] = page.getPixel(x, y).r.toInt();
    }
  }
  return GridDetector(px, w, h).detect();
}

class _Blob {
  final double cx, cy, bw, bh;
  _Blob(this.cx, this.cy, this.bw, this.bh);
  double get size => (bw + bh) / 2;
}

class _Grid {
  final List<double> xs, ys; // sütun ve satır merkezleri (doğrusal uydurulmuş)
  final double bw, bh;

  /// Başka dairelerle bağlantısı olmayan, kendi başına bir grup mu?
  final bool alone;
  _Grid(this.xs, this.ys, this.bw, this.bh, {this.alone = true});
  int get nc => xs.length;
  int get nr => ys.length;
  double get left => xs.first;
  double get right => xs.last;
  double get top => ys.first;
  double get bottom => ys.last;
  Pt get first => Pt(xs.first, ys.first);
  Pt get last => Pt(xs.last, ys.last);
  double get pitchX => nc < 2 ? 0 : (xs.last - xs.first) / (nc - 1);
}

class GridDetector {
  final Uint8List px;
  final int w, h;
  GridDetector(this.px, this.w, this.h);

  DetectedForm detect() {
    final blobs = _blobs();
    final grids = _grids(blobs);
    return _classify(grids);
  }

  // -------------------------------------------------------------------------
  // 1. Koyu lekeler (daire adayları)

  List<_Blob> _blobs() {
    // Yerel zemin: 51×51 kutu ortalaması (integral görüntü).
    final ii = Int64List((w + 1) * (h + 1));
    for (var y = 0; y < h; y++) {
      var row = 0;
      for (var x = 0; x < w; x++) {
        row += px[y * w + x];
        ii[(y + 1) * (w + 1) + x + 1] = ii[y * (w + 1) + x + 1] + row;
      }
    }
    const half = 25;
    final dark = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      final y0 = math.max(0, y - half), y1 = math.min(h, y + half + 1);
      for (var x = 0; x < w; x++) {
        final x0 = math.max(0, x - half), x1 = math.min(w, x + half + 1);
        final s = ii[y1 * (w + 1) + x1] - ii[y0 * (w + 1) + x1] - ii[y1 * (w + 1) + x0] + ii[y0 * (w + 1) + x0];
        final mean = s / ((x1 - x0) * (y1 - y0));
        if (px[y * w + x] < mean - math.max(22, mean * 0.1)) dark[y * w + x] = 1;
      }
    }
    // Kırık çemberler tek parça olsun diye 1 piksel genişlet.
    final mask = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (dark[y * w + x] == 0) continue;
        for (var dy = -1; dy <= 1; dy++) {
          final yy = y + dy;
          if (yy < 0 || yy >= h) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final xx = x + dx;
            if (xx >= 0 && xx < w) mask[yy * w + xx] = 1;
          }
        }
      }
    }

    final label = Int32List(w * h);
    final out = <_Blob>[];
    final stack = <int>[];
    var next = 0;
    for (var i = 0; i < mask.length; i++) {
      if (mask[i] == 0 || label[i] != 0) continue;
      next++;
      label[i] = next;
      stack.add(i);
      var area = 0, minX = w, maxX = 0, minY = h, maxY = 0;
      while (stack.isNotEmpty) {
        final p = stack.removeLast();
        area++;
        final x = p % w, y = p ~/ w;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        if (x > 0 && mask[p - 1] == 1 && label[p - 1] == 0) {
          label[p - 1] = next;
          stack.add(p - 1);
        }
        if (x < w - 1 && mask[p + 1] == 1 && label[p + 1] == 0) {
          label[p + 1] = next;
          stack.add(p + 1);
        }
        if (y > 0 && mask[p - w] == 1 && label[p - w] == 0) {
          label[p - w] = next;
          stack.add(p - w);
        }
        if (y < h - 1 && mask[p + w] == 1 && label[p + w] == 0) {
          label[p + w] = next;
          stack.add(p + w);
        }
      }
      // Genişletmeyi geri al (her yönde ~1 piksel).
      final bw = (maxX - minX - 1).toDouble(), bh = (maxY - minY - 1).toDouble();
      if (bw < 7 || bh < 7 || bw > 70 || bh > 70) continue;
      final ratio = bw / bh;
      if (ratio < 0.55 || ratio > 2.4) continue;
      final fill = area / ((maxX - minX + 1) * (maxY - minY + 1));
      if (fill < 0.12 || fill > 0.9) continue;
      // Köşeleri dolu kutular (yazı kutusu, kare çerçeve) daire değildir.
      var cornersDark = 0;
      for (final (x, y) in [(minX + 1, minY + 1), (maxX - 1, minY + 1), (minX + 1, maxY - 1), (maxX - 1, maxY - 1)]) {
        var any = false;
        for (var dy = 0; dy <= 2 && !any; dy++) {
          for (var dx = 0; dx <= 2 && !any; dx++) {
            final xx = x < (minX + maxX) / 2 ? x + dx : x - dx, yy = y < (minY + maxY) / 2 ? y + dy : y - dy;
            if (dark[yy * w + xx] == 1) any = true;
          }
        }
        if (any) cornersDark++;
      }
      if (cornersDark >= 3) continue;
      out.add(_Blob((minX + maxX) / 2, (minY + maxY) / 2, bw, bh));
    }
    // Dairenin içindeki harf ayrı leke olarak çıkar: daha büyük bir lekenin
    // içinde kalanları at.
    out.sort((a, b) => b.size.compareTo(a.size));
    final kept = <_Blob>[];
    for (final b in out) {
      final inside = kept.any((k) =>
          k.size > b.size * 1.3 && (b.cx - k.cx).abs() < k.bw / 2 && (b.cy - k.cy).abs() < k.bh / 2);
      if (!inside) kept.add(b);
    }
    return kept;
  }

  // -------------------------------------------------------------------------
  // 2. Izgaralar

  List<_Grid> _grids(List<_Blob> blobs) {
    final n = blobs.length;
    final parent = List<int>.generate(n, (i) => i);
    int find(int i) {
      while (parent[i] != i) {
        parent[i] = parent[parent[i]];
        i = parent[i];
      }
      return i;
    }

    // Komşu: aynı boy, aynı satır (ya da sütun) üzerinde ve yakın.
    final order = List<int>.generate(n, (i) => i)..sort((a, b) => blobs[a].cx.compareTo(blobs[b].cx));
    for (var ai = 0; ai < n; ai++) {
      final a = blobs[order[ai]];
      for (var bi = ai + 1; bi < n; bi++) {
        final b = blobs[order[bi]];
        final s = math.max(a.size, b.size);
        if (b.cx - a.cx > 2.8 * s) break;
        if ((a.bw - b.bw).abs() > 0.22 * math.max(a.bw, b.bw) || (a.bh - b.bh).abs() > 0.22 * math.max(a.bh, b.bh)) continue;
        final dx = (b.cx - a.cx).abs(), dy = (b.cy - a.cy).abs();
        final horiz = dy < 0.3 * math.min(a.bh, b.bh) && dx < 2.8 * s;
        final vert = dx < 0.3 * math.min(a.bw, b.bw) && dy < 2.8 * s;
        if (horiz || vert) parent[find(order[ai])] = find(order[bi]);
      }
    }
    final groups = <int, List<_Blob>>{};
    for (var i = 0; i < n; i++) {
      groups.putIfAbsent(find(i), () => []).add(blobs[i]);
    }

    final grids = <_Grid>[];
    for (final g in groups.values) {
      if (g.length < 2) continue;
      final bw = _median([for (final b in g) b.bw]), bh = _median([for (final b in g) b.bh]);
      // Önce büyük sütun boşluklarından, sonra her parçada büyük satır
      // boşluklarından, sonra yine sütunlardan böl.
      for (final colPart in _split(g, bw, (b) => b.cx)) {
        for (final rowPart in _split(colPart, bh, (b) => b.cy)) {
          for (final part in _split(rowPart, bw, (b) => b.cx)) {
            final cs = _cluster([for (final b in part) b.cx], 0.45 * bw);
            final rs = _cluster([for (final b in part) b.cy], 0.45 * bh);
            final cells = cs.length * rs.length;
            if (cells < 2 || part.length < cells * 0.7) continue;
            if (!_regular(cs) || !_regular(rs)) continue;
            // Her sütun/satır merkezini o sütundaki dairelerden yeniden hesapla, doğruya uydur.
            final xs = _fit([for (final c in cs) _median([for (final b in part) if ((b.cx - c).abs() < 0.45 * bw) b.cx])]);
            final ys = _fit([for (final r in rs) _median([for (final b in part) if ((b.cy - r).abs() < 0.45 * bh) b.cy])]);
            grids.add(_Grid(xs, ys, bw, bh, alone: g.length <= part.length + 1));
          }
        }
      }
    }
    return grids;
  }

  /// Daireleri bir eksende kümeleyip büyük boşluklardan parçalara ayırır.
  static List<List<_Blob>> _split(List<_Blob> g, double size, double Function(_Blob) axis) {
    if (g.isEmpty) return const [];
    final centers = _cluster([for (final b in g) axis(b)], 0.45 * size);
    final parts = _splitByGap(centers);
    if (parts.length == 1) return [g];
    return [
      for (final p in parts) [for (final b in g) if (axis(b) >= p.first - 0.45 * size && axis(b) <= p.last + 0.45 * size) b]
    ];
  }

  /// Değerleri yakınlığa göre kümeler, küme ortalamalarını sıralı döndürür.
  static List<double> _cluster(List<double> v, double gap) {
    final s = [...v]..sort();
    final out = <double>[];
    var sum = s.first, cnt = 1;
    for (var i = 1; i < s.length; i++) {
      if (s[i] - s[i - 1] > gap) {
        out.add(sum / cnt);
        sum = 0;
        cnt = 0;
      }
      sum += s[i];
      cnt++;
    }
    out.add(sum / cnt);
    return out;
  }

  /// Büyük boşluklardan böler (iki soru sütunu arasındaki numara alanı gibi).
  static List<List<double>> _splitByGap(List<double> c) {
    if (c.length < 3) return [c];
    final gaps = [for (var i = 1; i < c.length; i++) c[i] - c[i - 1]];
    final m = _median(gaps);
    final out = <List<double>>[];
    var cur = [c.first];
    for (var i = 1; i < c.length; i++) {
      if (gaps[i - 1] > 1.55 * m) {
        out.add(cur);
        cur = [];
      }
      cur.add(c[i]);
    }
    out.add(cur);
    return out;
  }

  static bool _regular(List<double> c) {
    if (c.length < 3) return true;
    final gaps = [for (var i = 1; i < c.length; i++) c[i] - c[i - 1]];
    final m = _median(gaps);
    return gaps.every((g) => (g - m).abs() <= m * 0.35);
  }

  /// En küçük kareler doğrusu: eşit aralıklı merkezler.
  static List<double> _fit(List<double> v) {
    final n = v.length;
    if (n < 3) return v;
    final mi = (n - 1) / 2, mv = v.reduce((a, b) => a + b) / n;
    var sxy = 0.0, sxx = 0.0;
    for (var i = 0; i < n; i++) {
      sxy += (i - mi) * (v[i] - mv);
      sxx += (i - mi) * (i - mi);
    }
    final b = sxy / sxx;
    return [for (var i = 0; i < n; i++) mv + b * (i - mi)];
  }

  static double _median(List<double> v) {
    if (v.isEmpty) return 0;
    final s = [...v]..sort();
    return s[s.length ~/ 2];
  }

  // -------------------------------------------------------------------------
  // 3. Sınıflama

  DetectedForm _classify(List<_Grid> grids) {
    final answers = <(_Grid, bool)>[]; // (ızgara, şıklar yan yana mı)
    final numbers = <_Grid>[];
    final singles = <_Grid>[];
    var ignored = 0;
    for (final g in grids) {
      final nr = g.nr, nc = g.nc;
      if (nr == 1 || nc == 1) {
        if (nr * nc >= 2 && nr * nc <= 6) {
          singles.add(g);
        } else {
          ignored++;
        }
      } else if (nr == 10 && nc >= 6 && nc <= 12) {
        numbers.add(g);
      } else if (nc >= 3 && nc <= 6 && nr >= 3 && nr <= 60) {
        answers.add((g, true));
      } else if (nr >= 3 && nr <= 6 && nc >= 7 && nc <= 60) {
        answers.add((g, false));
      } else {
        ignored++;
      }
    }

    // Cevap daireleri formun her yerinde aynı boydadır: en çok daireyi
    // taşıyan boydan çok farklı olan parçalar (ad soyad ızgarası kırıntısı) atılır.
    if (answers.length > 1) {
      final weight = <int, int>{};
      for (final (g, _) in answers) {
        final k = ((g.bw + g.bh) / 2).round();
        weight[k] = (weight[k] ?? 0) + g.nr * g.nc;
      }
      final main = weight.entries.reduce((a, b) => b.value > a.value ? b : a).key;
      final before = answers.length;
      answers.removeWhere((a) => ((a.$1.bw + a.$1.bh) / 2 - main).abs() > main * 0.25);
      ignored += before - answers.length;
    }

    // 10 satırlı, 3–5 sütunlu blok: cevap mı numara mı? Diğer cevap
    // bloklarından farklı sütun sayısı varsa ya da hepsinin üstündeyse numara.
    if (numbers.isEmpty) {
      final tens = answers.where((a) => a.$2 && a.$1.nr == 10 && a.$1.nc >= 3).toList();
      final others = answers.where((a) => !tens.contains(a)).toList();
      for (final t in tens) {
        if (others.isEmpty) continue;
        final majority = _mode([for (final o in others) o.$1.nc]);
        final above = others.every((o) => t.$1.bottom < o.$1.top);
        if (t.$1.nc != majority || above) {
          answers.remove(t);
          numbers.add(t.$1);
          break;
        }
      }
    }

    NumberBlock? number;
    if (numbers.isNotEmpty) {
      numbers.sort((a, b) => b.nc.compareTo(a.nc));
      final g = numbers.first;
      number = NumberBlock(digits: g.nc, first: g.first, last: g.last);
      ignored += numbers.length - 1;
    }

    // Kitapçık: sayfanın üst yarısındaki tek sıra 2–6 daire; en kalabalığı,
    // eşitlikte en üstteki (cinsiyet gibi alanlar genelde daha aşağıda).
    BookletBlock? booklet;
    final pageH = h.toDouble();
    final ref = [for (final (g, _) in answers) (g.bw + g.bh) / 2, if (number != null) (numbers.first.bw + numbers.first.bh) / 2];
    final minSize = ref.isEmpty ? 0.0 : 0.75 * (ref.reduce((a, b) => a + b) / ref.length);
    final cands = singles.where((s) => s.alone && s.top < pageH * 0.5 && math.min(s.bw, s.bh) >= minSize).toList();
    if (cands.isNotEmpty) {
      double distToNumber(_Grid s) {
        if (number == null) return s.top;
        final c = Pt((number.first.x + number.last.x) / 2, (number.first.y + number.last.y) / 2);
        return math.sqrt(math.pow(s.xs.first - c.x, 2) + math.pow(s.ys.first - c.y, 2));
      }

      cands.sort((a, b) {
        final c = (b.nr * b.nc).compareTo(a.nr * a.nc);
        if (c != 0) return c;
        if ((a.top - b.top).abs() > 20) return a.top.compareTo(b.top);
        return distToNumber(a).compareTo(distToNumber(b));
      });
      final g = cands.first;
      booklet = BookletBlock(count: g.nr * g.nc, first: g.first, last: g.last);
    }
    ignored += singles.length - (booklet == null ? 0 : 1);

    // Soru numaraları: üstten alta bantlar, her bantta soldan sağa.
    answers.sort((a, b) => a.$1.top.compareTo(b.$1.top));
    final bands = <List<(_Grid, bool)>>[];
    for (final a in answers) {
      final band = bands.where((bd) => bd.any((o) => a.$1.top < o.$1.bottom && o.$1.top < a.$1.bottom)).firstOrNull;
      if (band != null) {
        band.add(a);
      } else {
        bands.add([a]);
      }
    }
    final blocks = <TemplateBlock>[];
    var start = 1;
    for (final band in bands) {
      band.sort((a, b) => a.$1.left.compareTo(b.$1.left));
      for (final (g, rows) in band) {
        final count = rows ? g.nr : g.nc;
        final choices = rows ? g.nc : g.nr;
        blocks.add(TemplateBlock(start: start, count: count, choices: choices, first: g.first, last: g.last, rows: rows));
        start += count;
      }
    }
    return DetectedForm(blocks: blocks, number: number, booklet: booklet, ignored: ignored);
  }

  static int _mode(List<int> v) {
    final c = <int, int>{};
    for (final x in v) {
      c[x] = (c[x] ?? 0) + 1;
    }
    return c.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }
}
